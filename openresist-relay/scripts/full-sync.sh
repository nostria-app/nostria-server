#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/sync-common.sh"

TARGET=${1:-}
if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <eu|us>" >&2
    exit 1
fi

MAX_NO_PROGRESS=${SYNC_MAX_NO_PROGRESS:-2}
RETRY_SLEEP_SECONDS=${SYNC_RETRY_SLEEP_SECONDS:-5}
LABEL=$(target_label "$TARGET")
RELAY_URL=$(sync_url_for_target "$TARGET")
RELAY_WAS_RUNNING=false

if relay_running; then
    RELAY_WAS_RUNNING=true
fi

restore_relay() {
    if [[ "$RELAY_WAS_RUNNING" != "true" ]]; then
        return
    fi

    echo "Restoring relay after $LABEL full sync..."
    compose up -d "$SERVICE_NAME" >/dev/null
}

trap 'restore_relay' EXIT

pre_sync_total=$(count_events)
previous_total=$pre_sync_total
attempt=0
no_progress_attempts=0

echo "$LABEL full sync starting from $RELAY_URL"
echo "Pre-sync total: $pre_sync_total"

if [[ "$RELAY_WAS_RUNNING" == "true" ]]; then
    echo "Stopping relay during $LABEL full sync to avoid LMDB write-lock contention"
    compose stop "$SERVICE_NAME" >/dev/null
fi

while true; do
    attempt=$((attempt + 1))

    echo "$LABEL sync attempt $attempt from $RELAY_URL"
    set +e
    run_sync_once "$TARGET"
    sync_exit_code=$?
    set -e

    current_total=$(count_events)
    total_delta=$((current_total - previous_total))

    echo "$LABEL counts after attempt $attempt: total=$current_total delta=$total_delta exit_code=$sync_exit_code"

    if (( total_delta == 0 )); then
        no_progress_attempts=$((no_progress_attempts + 1))
        echo "$LABEL no progress on attempt $attempt ($no_progress_attempts/$MAX_NO_PROGRESS)"
    else
        no_progress_attempts=0
    fi

    previous_total=$current_total

    if (( no_progress_attempts >= MAX_NO_PROGRESS )); then
        echo "$LABEL full sync appears exhausted after $attempt attempts"
        break
    fi

    echo "$LABEL retrying in $RETRY_SLEEP_SECONDS seconds"
    sleep "$RETRY_SLEEP_SECONDS"
done

echo "$LABEL full sync complete. Final total: $(count_events)"