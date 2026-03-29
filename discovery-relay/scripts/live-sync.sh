#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/live-sync-common.sh"

RETRY_SLEEP_SECONDS=${LIVE_SYNC_RETRY_SLEEP_SECONDS:-5}
LOCAL_RELAY_URL=${LOCAL_RELAY_URL:-ws://strfry-relay:7777}
DISCOVERY_FILTER_TEMPLATE='{"kinds":[3,10002],"since":%s}'

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*"
}

ensure_relay_running() {
    if relay_running; then
        return
    fi

    log "Relay container is down; starting $SERVICE_NAME"
    compose up -d "$SERVICE_NAME" >/dev/null
}

monitor_relay_loop() {
    while true; do
        ensure_relay_running
        sleep "$RETRY_SLEEP_SECONDS"
    done
}

run_follow_local_to_remote_loop() {
    local label="$1"
    local remote_url="$2"
    local filter_description="${3:-all events}"
    local filter_template="${4:-{\"since\":%s}}"

    while true; do
        ensure_relay_running

        local since
        since=$(date +%s)
        local filter
        filter=$(printf "$filter_template" "$since")

        log "[$label] following local relay $filter_description into $remote_url since=$since"
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
        ensure_relay_running

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

log "Live sync supervisor starting for Coracle, Purple Pages, Primal, Damus, discovery.eu, and discovery.us in both configured directions"

if ! relay_running; then
    log "Starting $SERVICE_NAME before starting live sync"
    compose up -d "$SERVICE_NAME" >/dev/null
fi

monitor_relay_loop &
child_pids+=("$!")

run_follow_local_to_remote_loop coracle wss://indexer.coracle.social/ &
child_pids+=("$!")

run_follow_local_to_remote_loop purplepages wss://purplepag.es/ &
child_pids+=("$!")

run_follow_local_to_remote_loop discovery-eu-up wss://discovery.eu.nostria.app/ "for kinds 3 and 10002" "$DISCOVERY_FILTER_TEMPLATE" &
child_pids+=("$!")

run_follow_local_to_remote_loop discovery-us-up wss://discovery.us.nostria.app/ "for kinds 3 and 10002" "$DISCOVERY_FILTER_TEMPLATE" &
child_pids+=("$!")

run_follow_remote_to_local_loop primal wss://relay.primal.net/ "kind 10002" '{"kinds":[10002],"since":%s}' &
child_pids+=("$!")

run_follow_remote_to_local_loop damus wss://relay.damus.io/ "kind 10002" '{"kinds":[10002],"since":%s}' &
child_pids+=("$!")

run_follow_remote_to_local_loop discovery-eu-down wss://discovery.eu.nostria.app/ "kinds 3 and 10002" "$DISCOVERY_FILTER_TEMPLATE" &
child_pids+=("$!")

run_follow_remote_to_local_loop discovery-us-down wss://discovery.us.nostria.app/ "kinds 3 and 10002" "$DISCOVERY_FILTER_TEMPLATE" &
child_pids+=("$!")

wait