#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/sync-common.sh"

RETRY_SLEEP_SECONDS=${LIVE_SYNC_RETRY_SLEEP_SECONDS:-5}
ROUTER_CONFIG="/etc/strfry-router.conf"

echo "Live router sync loop starting for ribo.nostria.app and rilo.nostria.app"

if relay_running; then
    echo "Stopping $SERVICE_NAME before starting live router sync"
    compose stop "$SERVICE_NAME" >/dev/null
fi

while true; do
    echo "Router sync connecting at $(date -Is)"
    compose run --rm --no-deps \
        -v "$PROJECT_DIR/config/strfry-router.conf:$ROUTER_CONFIG:ro" \
        "$SERVICE_NAME" \
        --config /etc/strfry.conf router "$ROUTER_CONFIG"
    sync_exit_code=$?
    echo "Router sync exited with code $sync_exit_code at $(date -Is)"
    sleep "$RETRY_SLEEP_SECONDS"
done