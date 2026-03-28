#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/sync-common.sh"

print_pid_status() {
    local label="$1"
    local pid_file="$2"

    if [[ ! -f "$pid_file" ]]; then
        echo "$label: not running"
        return
    fi

    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" >/dev/null 2>&1; then
        echo "$label: running (PID $pid)"
    else
        echo "$label: stale PID file ($pid)"
    fi
}

print_log_excerpt() {
    local label="$1"
    local file="$2"
    local pattern="$3"

    if [[ ! -f "$file" ]]; then
        echo "$label: no log file"
        return
    fi

    local line
    line=$(grep "$pattern" "$file" | tail -n 1 || true)
    if [[ -n "$line" ]]; then
        echo "$label: $line"
    else
        echo "$label: no matching log lines yet"
    fi
}

echo "OpenResist relay sync status"
echo "============================"
echo "Data root: $DATA_ROOT"
echo "Log dir:   $LOG_DIR"
echo

if relay_running; then
    echo "Relay mode: relay container is running"
else
    echo "Relay mode: relay container is stopped"
fi

print_pid_status "Live router sync" "$STATE_DIR/live-sync-router.pid"

if pgrep -af '/home/blockcore/src/nostria/nostria-server/openresist-relay/scripts/start-cutover-sync.sh' >/dev/null 2>&1; then
    echo "Cutover orchestrator: running"
else
    echo "Cutover orchestrator: not running"
fi

if pgrep -af '/home/blockcore/src/nostria/nostria-server/openresist-relay/scripts/full-sync.sh eu' >/dev/null 2>&1; then
    echo "EU full sync: running"
else
    echo "EU full sync: not running"
fi

if pgrep -af '/home/blockcore/src/nostria/nostria-server/openresist-relay/scripts/full-sync.sh us' >/dev/null 2>&1; then
    echo "US full sync: running"
else
    echo "US full sync: not running"
fi

echo
echo "Container state:"
compose ps || true

echo
echo "Current total events: $(count_events)"
echo
print_log_excerpt "Latest DOWN line" "$LOG_DIR/cutover-sync.log" 'DOWN:'
print_log_excerpt "Latest writer line" "$LOG_DIR/cutover-sync.log" 'Writer: added:'
print_log_excerpt "Latest live router line" "$LOG_DIR/live-sync-router.log" 'Connected to|Connecting to|Router sync'