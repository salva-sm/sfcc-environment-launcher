#!/bin/bash

# ==============================================================================
# Shared configuration loader
# ------------------------------------------------------------------------------
# Reads .env and fills the gaps from the dotfiles (project path, editor) and
# from the project's dw.json: SFCC_REALM and SFCC_INSTANCE come from "hostname"
# (<realm>-<instance>.dx....), SFCC_OAUTH_CLIENT_ID from "client-id".
# Values already set in .env always win.
# ==============================================================================

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$CONFIG_DIR/.env"

# Callers may define their own config_log (e.g. to append to a log file) before sourcing.
if ! declare -F config_log > /dev/null; then
    config_log() { echo "$@"; }
fi

load_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        config_log "❌ ERROR: .env file not found at $ENV_FILE"
        return 1
    fi

    set -a
    . <(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$ENV_FILE")
    set +a

    # Legacy variable names (REALM / INSTANCE / PROJECT_PATH) still supported.
    : "${SFCC_REALM:=$REALM}"
    : "${SFCC_INSTANCE:=$INSTANCE}"
    : "${LOCAL_PROJECT_PATH:=$PROJECT_PATH}"

    if [ -z "$LOCAL_PROJECT_PATH" ]; then
        LOCAL_PROJECT_PATH=$(dotfiles_project_path) \
            && config_log "📁 Project path taken from dotfiles: $LOCAL_PROJECT_PATH"
    fi

    : "${LAUNCH_EDITOR:=$(dotfiles_env_value DOTFILES_EDITOR)}"
    : "${LAUNCH_EDITOR:=code}"
    LAUNCH_EDITOR=$(echo "$LAUNCH_EDITOR" | tr '[:upper:]' '[:lower:]')
    case "$LAUNCH_EDITOR" in
        vscode|vs-code|"visual studio code") LAUNCH_EDITOR="code" ;;
    esac
    export LAUNCH_EDITOR
}

# The dotfiles repo already knows where the project lives and which editor to
# use. Its env.local is read from disk, not inherited from the shell: the
# scheduled task runs `bash -c`, which never loads .bashrc.
dotfiles_dir() {
    local dir="${DOTFILES_DIR:-$HOME/Github/dotfiles}"
    [ -f "$dir/git-bash/env.local" ] || return 1
    echo "$dir"
}

# Sourced in a subshell so that env.local's own exports never override .env.
dotfiles_env_value() {
    local dir
    dir=$(dotfiles_dir) || return 1
    ( . "$dir/git-bash/env.local" > /dev/null 2>&1; printf '%s' "${!1}" )
}

# The generated *.code-workspace wins because it lists every project folder;
# SFCC_PROJECT_DIR is the fallback, relative to vscode/workspaces/.
dotfiles_project_path() {
    local dir
    dir=$(dotfiles_dir) || return 1

    local workspaces="$dir/vscode/workspaces"
    if [ -f "$workspaces/sfcc.code-workspace" ]; then
        echo "$workspaces/sfcc.code-workspace"
        return 0
    fi

    local project_dir
    project_dir=$(dotfiles_env_value SFCC_PROJECT_DIR)
    [ -n "$project_dir" ] && [ -d "$workspaces/$project_dir" ] || return 1
    ( cd "$workspaces/$project_dir" && pwd )
}

# Extracts a string property from a flat JSON file without requiring jq.
json_string_value() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" \
        | head -n 1 \
        | sed -e 's/.*:[[:space:]]*"//' -e 's/"$//'
}

# Folder paths declared in a VS Code *.code-workspace file, resolved to absolute.
workspace_folders() {
    local workspace_dir
    workspace_dir="$(cd "$(dirname "$1")" && pwd)"

    grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" \
        | sed -e 's/.*:[[:space:]]*"//' -e 's/"$//' \
        | while IFS= read -r folder; do
            case "$folder" in
                /*|[A-Za-z]:*) echo "$folder" ;;
                *) echo "$workspace_dir/$folder" ;;
            esac
        done
}

# LOCAL_PROJECT_PATH may point to a project directory or to a VS Code workspace file.
project_roots() {
    [ -n "$LOCAL_PROJECT_PATH" ] || return 0

    if [ -d "$LOCAL_PROJECT_PATH" ]; then
        echo "$LOCAL_PROJECT_PATH"
        return 0
    fi

    case "$LOCAL_PROJECT_PATH" in
        *.code-workspace) workspace_folders "$LOCAL_PROJECT_PATH" ;;
        *) [ -f "$LOCAL_PROJECT_PATH" ] && dirname "$LOCAL_PROJECT_PATH" ;;
    esac
}

# Zed can't read *.code-workspace files, so it gets the folders declared inside.
open_project() {
    if [ -z "$LOCAL_PROJECT_PATH" ]; then
        config_log "ℹ️ No project path configured (.env / dotfiles), skipping editor auto-launch."
        return 0
    fi

    if ! command -v "$LAUNCH_EDITOR" > /dev/null 2>&1; then
        config_log "⚠️ Editor '$LAUNCH_EDITOR' is not on PATH, skipping editor auto-launch."
        return 0
    fi

    local targets=()
    if [ "$LAUNCH_EDITOR" = "zed" ]; then
        while IFS= read -r root; do
            [ -d "$root" ] && targets+=("$root")
        done < <(project_roots)
    else
        targets=("$LOCAL_PROJECT_PATH")
    fi

    if [ ${#targets[@]} -eq 0 ]; then
        config_log "⚠️ No existing folder found for $LOCAL_PROJECT_PATH, skipping editor auto-launch."
        return 0
    fi

    config_log "💻 Opening $LAUNCH_EDITOR at: ${targets[*]}"
    "$LAUNCH_EDITOR" "${targets[@]}"
}

# First dw.json found at the root of a project or one level below it (e.g. source/dw.json).
find_dw_json() {
    if [ -n "$DW_JSON_PATH" ] && [ -f "$DW_JSON_PATH" ]; then
        echo "$DW_JSON_PATH"
        return 0
    fi

    local dw_json
    dw_json=$(project_roots | while IFS= read -r root; do
        [ -d "$root" ] && find "$root" -maxdepth 2 -name dw.json -type f 2>/dev/null
    done | head -n 1)

    [ -n "$dw_json" ] || return 1
    echo "$dw_json"
}

# hostname is the full sandbox host (<realm>-<instance>.dx.commercecloud.salesforce.com).
set_realm_and_instance_from_host() {
    local host="$1"
    local sandbox_id="${host%%.*}"

    case "$sandbox_id" in
        *-*) ;;
        *)
            config_log "⚠️ Could not derive realm/instance from hostname '$host'."
            return 1
            ;;
    esac

    local instance="${sandbox_id#*-}"
    : "${SFCC_REALM:=${sandbox_id%%-*}}"
    : "${SFCC_INSTANCE:=${instance%%-*}}"
}

resolve_sfcc_config() {
    if [ -n "$SFCC_REALM" ] && [ -n "$SFCC_INSTANCE" ] && [ -n "$SFCC_OAUTH_CLIENT_ID" ]; then
        return 0
    fi

    local dw_json
    if ! dw_json=$(find_dw_json); then
        config_log "ℹ️ No dw.json found under LOCAL_PROJECT_PATH; using .env values only."
        return 0
    fi

    config_log "🔎 Completing configuration from $dw_json"

    if [ -z "$SFCC_REALM" ] || [ -z "$SFCC_INSTANCE" ]; then
        set_realm_and_instance_from_host "$(json_string_value hostname "$dw_json")"
    fi

    : "${SFCC_OAUTH_CLIENT_ID:=$(json_string_value client-id "$dw_json")}"

    export SFCC_REALM SFCC_INSTANCE SFCC_OAUTH_CLIENT_ID
}
