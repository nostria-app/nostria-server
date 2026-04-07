#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DISCOVERY_FILTER='{"kinds":[3,10002]}'
MAIN_SERVICE_NAME="strfry-main"

get_compose_cmd() {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
        return
    fi

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
        return
    fi

    echo "ERROR: neither docker-compose nor docker compose is available" >&2
    exit 1
}

COMPOSE_CMD=$(get_compose_cmd)
SYNC_SUCCESS_COUNT=0
SYNC_FAILURE_COUNT=0

cd "$PROJECT_DIR"

RELAY_WAS_RUNNING=false
if $COMPOSE_CMD ps --services --filter status=running | grep -qx "$MAIN_SERVICE_NAME"; then
    RELAY_WAS_RUNNING=true
fi

restore_relay() {
    if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
        return
    fi

    echo "Restoring live relay container..."
    set +e
    $COMPOSE_CMD up -d "$MAIN_SERVICE_NAME" >/dev/null
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        echo "WARNING: Failed to restore $MAIN_SERVICE_NAME automatically" >&2
    fi
}

if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
    echo "ERROR: $MAIN_SERVICE_NAME is not running. Start the stack first with ./scripts/bootstrap.sh" >&2
    exit 1
fi

echo "Stopping relay during historical sync to avoid LMDB contention..."
$COMPOSE_CMD stop "$MAIN_SERVICE_NAME" >/dev/null

sync_relay() {
    local relay_url="$1"
    local direction="$2"
    local filter="${3:-}"

    echo "Syncing from $relay_url"

    local exit_code
    set +e

    if [[ "$direction" == "down" ]]; then
        if [[ -n "$filter" ]]; then
            $COMPOSE_CMD run --rm --no-deps "$MAIN_SERVICE_NAME" \
                --config /etc/strfry.conf sync "$relay_url" --dir down --filter "$filter"
        else
            $COMPOSE_CMD run --rm --no-deps "$MAIN_SERVICE_NAME" \
                --config /etc/strfry.conf sync "$relay_url" --dir down
        fi
    else
        if [[ -n "$filter" ]]; then
            $COMPOSE_CMD run --rm --no-deps "$MAIN_SERVICE_NAME" \
                --config /etc/strfry.conf sync "$relay_url" --dir both --filter "$filter"
        else
            $COMPOSE_CMD run --rm --no-deps "$MAIN_SERVICE_NAME" \
                --config /etc/strfry.conf sync "$relay_url" --dir both
        fi
    fi

    exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]]; then
        SYNC_SUCCESS_COUNT=$((SYNC_SUCCESS_COUNT + 1))
        return 0
    fi

    SYNC_FAILURE_COUNT=$((SYNC_FAILURE_COUNT + 1))
    echo "WARNING: Sync from $relay_url failed with exit code $exit_code" >&2
    return "$exit_code"
}

trap 'restore_relay' EXIT

if ! sync_relay "wss://discovery.af.nostria.app/" down "$DISCOVERY_FILTER"; then
    echo "Continuing with remaining discovery upstreams..." >&2
fi

if ! sync_relay "wss://purplepag.es/" down; then
    echo "Continuing with remaining discovery upstreams..." >&2
fi

if ! sync_relay "wss://indexer.coracle.social/" down '{"kinds":[10002]}'; then
    echo "Continuing with remaining discovery upstreams..." >&2
fi

if ! sync_relay "wss://relay.damus.io/" down; then
    echo "Continuing with remaining discovery upstreams..." >&2
fi

if ! sync_relay "wss://relay.primal.net/" down; then
    echo "Continuing with remaining discovery upstreams..." >&2
fi

if [[ $SYNC_SUCCESS_COUNT -eq 0 ]]; then
    echo "ERROR: All discovery relay sync attempts failed" >&2
    exit 1
fi

if [[ $SYNC_FAILURE_COUNT -gt 0 ]]; then
    echo "WARNING: $SYNC_FAILURE_COUNT discovery relay sync attempt(s) failed, but at least one upstream completed" >&2
fi

echo "Historical sync completed. Restarting relay..."
restore_relay

echo "Current event counts:"
$COMPOSE_CMD exec -T "$MAIN_SERVICE_NAME" /app/strfry --config /etc/strfry.conf scan '{}' | wc -l
$COMPOSE_CMD exec -T "$MAIN_SERVICE_NAME" /app/strfry --config /etc/strfry.conf scan '{"kinds":[3]}' | wc -l
$COMPOSE_CMD exec -T "$MAIN_SERVICE_NAME" /app/strfry --config /etc/strfry.conf scan '{"kinds":[10002]}' | wc -l