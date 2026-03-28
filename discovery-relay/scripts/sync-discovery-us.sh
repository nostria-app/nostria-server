#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
PROJECT_NAME=$(basename "$PROJECT_DIR")
MAX_NO_PROGRESS=${US_SYNC_MAX_NO_PROGRESS:-2}
RETRY_SLEEP_SECONDS=${US_SYNC_RETRY_SLEEP_SECONDS:-5}

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

compose() {
    $COMPOSE_CMD -f "$COMPOSE_FILE" "$@"
}

relay_running() {
    compose ps --services --filter status=running | grep -qx 'strfry-relay'
}

active_sync_container() {
    docker ps --format '{{.Names}}' | grep -E "^${PROJECT_NAME}_strfry-relay_run_" | head -n 1 || true
}

count_events() {
    local filter="$1"

    if relay_running; then
        compose exec -T strfry-relay /app/strfry --config /etc/strfry.conf scan "$filter" | wc -l
        return
    fi

    compose run --rm --no-deps strfry-relay /app/strfry --config /etc/strfry.conf scan "$filter" | wc -l
}

wait_for_active_sync() {
    local container_name="$1"

    if [[ -z "$container_name" ]]; then
        return
    fi

    echo "Waiting for existing sync container to finish: $container_name"
    while docker ps --format '{{.Names}}' | grep -Fxq "$container_name"; do
        sleep 5
    done
}

RELAY_WAS_RUNNING=false
if relay_running; then
    RELAY_WAS_RUNNING=true
fi

EXISTING_SYNC_CONTAINER=$(active_sync_container)
if [[ -n "$EXISTING_SYNC_CONTAINER" ]]; then
    RELAY_WAS_RUNNING=true
fi

restore_relay() {
    if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
        return
    fi

    echo "Restoring live relay container..."
    set +e
    compose up -d strfry-relay >/dev/null
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        echo "WARNING: Failed to restore strfry-relay automatically" >&2
    fi
}

if [[ "$RELAY_WAS_RUNNING" != "true" && -z "$EXISTING_SYNC_CONTAINER" ]]; then
    echo "ERROR: strfry-relay is not running. Start it first with ./scripts/bootstrap.sh" >&2
    exit 1
fi

wait_for_active_sync "$EXISTING_SYNC_CONTAINER"

pre_sync_total=$(count_events '{}')
pre_sync_kind10002=$(count_events '{"kinds":[10002]}')

echo "Pre-sync counts:"
echo "  total:   $pre_sync_total"
echo "  kind10002: $pre_sync_kind10002"

trap 'restore_relay' EXIT

if relay_running; then
    echo "Stopping relay during discovery.us sync..."
    compose stop strfry-relay >/dev/null
fi

attempt=0
no_progress_attempts=0
previous_total=$pre_sync_total
previous_kind10002=$pre_sync_kind10002

while true; do
    attempt=$((attempt + 1))

    echo "Sync attempt $attempt from wss://discovery.us.nostria.app/..."
    set +e
    compose run --rm --no-deps strfry-relay \
        --config /etc/strfry.conf sync wss://discovery.us.nostria.app/ --dir down
    sync_exit_code=$?
    set -e

    current_total=$(count_events '{}')
    current_kind10002=$(count_events '{"kinds":[10002]}')
    total_delta=$((current_total - previous_total))
    kind10002_delta=$((current_kind10002 - previous_kind10002))

    echo "Counts after attempt $attempt:"
    echo "  total:      $current_total (delta $total_delta)"
    echo "  kind10002:  $current_kind10002 (delta $kind10002_delta)"
    echo "  exit code:  $sync_exit_code"

    if (( total_delta == 0 && kind10002_delta == 0 )); then
        no_progress_attempts=$((no_progress_attempts + 1))
        echo "No new events imported on attempt $attempt ($no_progress_attempts/$MAX_NO_PROGRESS)."
    else
        no_progress_attempts=0
    fi

    previous_total=$current_total
    previous_kind10002=$current_kind10002

    if (( no_progress_attempts >= MAX_NO_PROGRESS )); then
        echo "US sync appears exhausted or stalled after $attempt attempts."
        break
    fi

    echo "Retrying in $RETRY_SLEEP_SECONDS seconds..."
    sleep "$RETRY_SLEEP_SECONDS"
done

echo "Sync loop complete. Restoring relay..."
restore_relay

echo "Post-sync counts:"
echo "  total:   $(count_events '{}')"
echo "  kind10002: $(count_events '{"kinds":[10002]}')"