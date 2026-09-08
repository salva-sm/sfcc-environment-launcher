#!/bin/bash

# ==============================================================================
# SFCC Sandbox Stopper Script
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/shutdown.log"

config_log() { echo "[$(date +'%H:%M:%S')] $*" >> "$LOG_FILE"; }

echo "[$(date +'%Y-%m-%d %H:%M:%S')] System shutdown detected. Initiating SFCC Sandbox stop sequence..." >> "$LOG_FILE"

# 1. Load configuration: .env first (resolved relative to this script, not the CWD),
#    then the project's dw.json for whatever is still missing.
. "$SCRIPT_DIR/load_config.sh"

load_env_file || exit 1
resolve_sfcc_config

# 2. Validate the resulting configuration
if [ -z "$SFCC_REALM" ] || [ -z "$SFCC_INSTANCE" ]; then
  config_log "ERROR: SFCC_REALM/SFCC_INSTANCE are missing in $ENV_FILE and could not be read from dw.json"
  exit 1
fi

SANDBOX_ID="${SFCC_REALM}-${SFCC_INSTANCE}"

# 3. Reuse the session opened by start_environment.sh — no client secret, so there is
#    no headless fallback here (a browser login is impossible during shutdown).
if ! npx sfcc-ci client:auth:token > /dev/null 2>&1; then
  config_log "WARNING: no active sfcc-ci session. The stop request will most likely be rejected."
fi

# 4. Trigger Sandbox Stop using npx sfcc-ci
config_log "Requesting stop for Sandbox: $SANDBOX_ID..."
npx sfcc-ci sandbox:stop -s "$SANDBOX_ID" >> "$LOG_FILE" 2>&1

config_log "Stop request execution finished."