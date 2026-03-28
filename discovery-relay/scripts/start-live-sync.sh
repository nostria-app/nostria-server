#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/live-sync-common.sh"

PID_FILE="$STATE_DIR/live-sync-router.pid"
LOG_FILE="$LOG_DIR/live-sync-router.log"

if [[ -f "$PID_FILE" ]]; then
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" >/dev/null 2>&1; then
        echo "Live router sync is already running with PID $existing_pid"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

if ! relay_running; then
    echo "Starting $SERVICE_NAME before live router sync"
    compose up -d "$SERVICE_NAME" >/dev/null
fi

nohup bash "$SCRIPT_DIR/live-sync.sh" >> "$LOG_FILE" 2>&1 &
new_pid=$!
echo "$new_pid" > "$PID_FILE"
echo "Started live router sync with PID $new_pid"
echo "Logging to $LOG_FILE"