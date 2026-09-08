#!/bin/bash

# ==============================================================================
# SFCC Sandbox Launcher Script
# ==============================================================================

# 1. Load configuration: .env first (resolved relative to this script, not the CWD),
#    then the project's dw.json for whatever is still missing.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/load_config.sh"

load_env_file || exit 1
resolve_sfcc_config

# 2. Validate the resulting configuration
if [ -z "$SFCC_REALM" ] || [ -z "$SFCC_INSTANCE" ]; then
    echo "❌ ERROR: SFCC_REALM/SFCC_INSTANCE are missing in $ENV_FILE and could not be read from dw.json"
    exit 1
fi

SANDBOX_ID="${SFCC_REALM}-${SFCC_INSTANCE}"
SANDBOX_URL="https://${SANDBOX_ID}.dx.commercecloud.salesforce.com/on/demandware.store/Sites-Site/default/ViewApplication-DisplayWelcomePage"

POLL_INTERVAL=${POLL_INTERVAL:-15}
MAX_TIMEOUT=${MAX_TIMEOUT:-900} # 15 minutes default timeout

# Interactive login: the user always authenticates through the browser, so no client secret is needed
do_login() {
    echo "⚠️ Session expired or unauthorized for WebDAV."

    if [ -z "$SFCC_OAUTH_CLIENT_ID" ]; then
        if [ ! -t 0 ]; then
            echo "❌ ERROR: SFCC_OAUTH_CLIENT_ID is missing in $ENV_FILE and in dw.json, and no terminal is available to ask for it."
            exit 1
        fi
        read -p "🔑 Enter your SFCC_OAUTH_CLIENT_ID: " SFCC_OAUTH_CLIENT_ID
    fi

    echo "🌐 Initiating login via browser..."
    npx sfcc-ci auth:login "$SFCC_OAUTH_CLIENT_ID"
}

# 3. Validate Active Session with a real API call
echo "🔐 Validating sfcc-ci authentication with Sandbox API..."

if ! npx sfcc-ci client:auth:token > /dev/null 2>&1; then
    do_login
else
    # Test active WebDAV access against the target sandbox
    if ! npx sfcc-ci sandbox:get -s "$SANDBOX_ID" > /dev/null 2>&1; then
        do_login
    else
        echo "✅ Active authenticated session verified."
    fi
fi

# 4. Trigger Sandbox Start
echo "🚀 Requesting start for Sandbox: $SANDBOX_ID..."
npx sfcc-ci sandbox:start -s "$SANDBOX_ID"

# 5. Launch the configured editor (LAUNCH_EDITOR: .env, else the dotfiles' choice)
open_project

# 6. Poll Sandbox Status with Timeout
echo "⏳ Monitoring sandbox readiness (Timeout: ${MAX_TIMEOUT}s)..."
ELAPSED=0

while [ $ELAPSED -lt $MAX_TIMEOUT ]; do
    STATUS=$(npx sfcc-ci sandbox:list | grep -E "$SFCC_REALM" | grep -E "$SFCC_INSTANCE" \
        | awk -F '│' '{print $5}' | xargs | tr '[:upper:]' '[:lower:]')

    [ -z "$STATUS" ] && STATUS="unknown"
    echo "   [$(date +'%H:%M:%S')] Status: '$STATUS' (${ELAPSED}s / ${MAX_TIMEOUT}s)"

    case "$STATUS" in
        started)
            echo -e "\n✅ SUCCESS: Sandbox $SANDBOX_ID is running!"
            echo "🌐 Opening Business Manager in browser..."
            start "$SANDBOX_URL"
            exit 0
            ;;
        failed|deleting|deleted)
            echo -e "\n❌ ERROR: Sandbox reached an unrecoverable state: '$STATUS'."
            exit 1
            ;;
    esac

    # Any other state (starting, pending, creating, stopping, stopped, unknown)
    # is transient while the sandbox boots, so keep polling.
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# 7. Timeout Exceeded
echo -e "\n⏱️ ERROR: Timeout reached (${MAX_TIMEOUT}s) while waiting for Sandbox to start."
exit 1
