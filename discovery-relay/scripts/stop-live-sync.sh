#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/live-sync-common.sh"

PID_FILE="$STATE_DIR/live-sync-router.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "No live router sync PID file found"
    exit 0
fi

pid=$(cat "$PID_FILE")
if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid"
    echo "Stopped live router sync (PID $pid)"
else
    echo "Live router sync was not running"
fi

rm -f "$PID_FILE"