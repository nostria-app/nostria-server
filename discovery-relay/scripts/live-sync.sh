#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/live-sync-common.sh"

RETRY_SLEEP_SECONDS=${LIVE_SYNC_RETRY_SLEEP_SECONDS:-5}
LOCAL_RELAY_URL=${LOCAL_RELAY_URL:-ws://strfry-relay:7777}

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*"
}

run_follow_local_to_remote_loop() {
    local label="$1"
    local remote_url="$2"

    while true; do
        local since
        since=$(date +%s)
        local filter
        filter=$(printf '{"since":%s}' "$since")

        log "[$label] following local relay into $remote_url since=$since"
        set +e
        compose run --rm --no-deps "$SERVICE_NAME" \
            --config /etc/strfry.conf download --follow "$LOCAL_RELAY_URL" --filter "$filter" \
            | compose run --rm --no-deps -T "$SERVICE_NAME" \
                --config /etc/strfry.conf upload "$remote_url"
        local pipeline_exit=$?
        set -e

        log "[$label] local-follow/upload pipeline exited with code $pipeline_exit; retrying in ${RETRY_SLEEP_SECONDS}s"
        sleep "$RETRY_SLEEP_SECONDS"
    done
}

run_follow_remote_to_local_loop() {
    local label="$1"
    local remote_url="$2"
    local filter_description="$3"
    local filter="$4"

    while true; do
        local since
        since=$(date +%s)
        local follow_filter
        follow_filter=$(printf "$filter" "$since")

        log "[$label] following $filter_description from $remote_url into $LOCAL_RELAY_URL since=$since"
        set +e
        compose run --rm --no-deps "$SERVICE_NAME" \
            --config /etc/strfry.conf download --follow "$remote_url" --filter "$follow_filter" \
            | compose run --rm --no-deps -T "$SERVICE_NAME" \
                --config /etc/strfry.conf upload "$LOCAL_RELAY_URL"
        local pipeline_exit=$?
        set -e

        log "[$label] follow/upload pipeline exited with code $pipeline_exit; retrying in ${RETRY_SLEEP_SECONDS}s"
        sleep "$RETRY_SLEEP_SECONDS"
    done
}

child_pids=()

cleanup() {
    local pid
    for pid in "${child_pids[@]:-}"; do
        kill "$pid" >/dev/null 2>&1 || true
    done
    wait >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

log "Live sync supervisor starting for Coracle, Purple Pages, Primal, Damus, discovery.eu, and discovery.us"

if ! relay_running; then
    log "Starting $SERVICE_NAME before starting live sync"
    compose up -d "$SERVICE_NAME" >/dev/null
fi

run_follow_local_to_remote_loop coracle wss://indexer.coracle.social/ &
child_pids+=("$!")

run_follow_local_to_remote_loop purplepages wss://purplepag.es/ &
child_pids+=("$!")

run_follow_remote_to_local_loop primal wss://relay.primal.net/ "kind 10002" '{"kinds":[10002],"since":%s}' &
child_pids+=("$!")

run_follow_remote_to_local_loop damus wss://relay.damus.io/ "kind 10002" '{"kinds":[10002],"since":%s}' &
child_pids+=("$!")

run_follow_remote_to_local_loop discovery-eu wss://discovery.eu.nostria.app/ "all events" '{"since":%s}' &
child_pids+=("$!")

run_follow_remote_to_local_loop discovery-us wss://discovery.us.nostria.app/ "all events" '{"since":%s}' &
child_pids+=("$!")

wait