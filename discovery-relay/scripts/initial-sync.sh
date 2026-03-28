#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

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

cd "$PROJECT_DIR"

RELAY_WAS_RUNNING=false
if $COMPOSE_CMD ps --services --filter status=running | grep -qx 'strfry-relay'; then
    RELAY_WAS_RUNNING=true
fi

restore_relay() {
    if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
        return
    fi

    echo "Restoring live relay container..."
    set +e
    $COMPOSE_CMD up -d strfry-relay >/dev/null
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        echo "WARNING: Failed to restore strfry-relay automatically" >&2
    fi
}

if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
    echo "ERROR: strfry-relay is not running. Start the stack first with ./scripts/bootstrap.sh" >&2
    exit 1
fi

echo "Stopping relay during historical sync to avoid LMDB contention..."
$COMPOSE_CMD stop strfry-relay >/dev/null

sync_relay() {
    local relay_url="$1"
    local direction="$2"
    local filter="${3:-}"

    echo "Syncing from $relay_url"

    if [[ "$direction" == "down" ]]; then
        if [[ -n "$filter" ]]; then
            $COMPOSE_CMD run --rm --no-deps strfry-relay \
                --config /etc/strfry.conf sync "$relay_url" --dir down --filter "$filter"
        else
            $COMPOSE_CMD run --rm --no-deps strfry-relay \
                --config /etc/strfry.conf sync "$relay_url" --dir down
        fi
    else
        if [[ -n "$filter" ]]; then
            $COMPOSE_CMD run --rm --no-deps strfry-relay \
                --config /etc/strfry.conf sync "$relay_url" --dir both --filter "$filter"
        else
            $COMPOSE_CMD run --rm --no-deps strfry-relay \
                --config /etc/strfry.conf sync "$relay_url" --dir both
        fi
    fi
}

trap 'restore_relay' EXIT

sync_relay "wss://discovery.eu.nostria.app/" down
sync_relay "wss://discovery.us.nostria.app/" down
sync_relay "wss://discovery.af.nostria.app/" down
sync_relay "wss://purplepag.es/" down
sync_relay "wss://indexer.coracle.social/" down '{"kinds":[10002]}'
sync_relay "wss://relay.damus.io/" down
sync_relay "wss://relay.primal.net/" down

echo "Historical sync completed. Restarting relay..."
restore_relay

echo "Current event counts:"
$COMPOSE_CMD run --rm --no-deps strfry-relay --config /etc/strfry.conf scan '{}' | wc -l
$COMPOSE_CMD run --rm --no-deps strfry-relay --config /etc/strfry.conf scan '{"kinds":[3]}' | wc -l
$COMPOSE_CMD run --rm --no-deps strfry-relay --config /etc/strfry.conf scan '{"kinds":[10002]}' | wc -l