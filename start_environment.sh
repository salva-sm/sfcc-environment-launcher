#!/bin/bash

# ==============================================================================
# SFCC Sandbox Launcher Script
# ==============================================================================

# 1. Load local configuration from .env if available
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ ERROR: .env file not found."
  exit 1
fi

# 2. Validate required configuration from .env
if [ -z "$REALM" ] || [ -z "$INSTANCE" ]; then
    echo "❌ ERROR: REALM or INSTANCE is missing in .env"
    exit 1
fi

SANDBOX_ID="${REALM}-${INSTANCE}"
SANDBOX_URL="https://${REALM}-${INSTANCE}.dx.commercecloud.salesforce.com/on/demandware.store/Sites-Site/default/ViewApplication-DisplayWelcomePage"

POLL_INTERVAL=${POLL_INTERVAL:-15}
MAX_TIMEOUT=${MAX_TIMEOUT:-900} # 15 minutes default timeout

# Function to perform interactive login
do_login() {
    echo "⚠️ Session expired or unauthorized for WebDAV."
    if [ -z "$SFCC_OAUTH_CLIENT_ID" ]; then
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

# 5. Launch VS Code
if [ -n "$PROJECT_PATH" ]; then
    echo "💻 Opening VS Code at: $PROJECT_PATH"
    code "$PROJECT_PATH"
else
    echo "ℹ️ PROJECT_PATH not set in .env, skipping VS Code auto-launch."
fi

# 6. Poll Sandbox Status with Timeout
echo "⏳ Monitoring sandbox readiness (Timeout: ${MAX_TIMEOUT}s)..."
ELAPSED=0

while [ $ELAPSED -lt $MAX_TIMEOUT ]; do
    RAW_LINE=$(npx sfcc-ci sandbox:list | grep -E "$REALM" | grep -E "$INSTANCE")
    STATUS=$(npx sfcc-ci sandbox:list | grep -E "$REALM" | grep -E "$INSTANCE" | awk -F '│' '{print $5}' | xargs)

    [ -z "$STATUS" ] && STATUS="unknown"
    echo "   [$(date +'%H:%M:%S')] Status: '$STATUS' (${ELAPSED}s / ${MAX_TIMEOUT}s)"

    if [ "$STATUS" == "started" ]; then
        echo -e "\n✅ SUCCESS: Sandbox $SANDBOX_ID is running!"
        echo "🌐 Opening Business Manager in browser..."
        start "$SANDBOX_URL"
        exit 0
    elif [ "$STATUS" != "stopped" ] && [ "$STATUS" != "unknown" ]; then
        echo -e "\n⚠️ WARNING: Unexpected sandbox status encountered: '$STATUS'."
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# 7. Timeout Exceeded
echo -e "\n⏱️ ERROR: Timeout reached (${MAX_TIMEOUT}s) while waiting for Sandbox to start."
exit 1
