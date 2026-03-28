#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/live-sync-common.sh"

status_label() {
    local label="$1"
    local value="$2"
    printf '%-18s %s\n' "$label" "$value"
}

relay_container_count=$(compose ps --services --filter status=running 2>/dev/null | grep -cx "$SERVICE_NAME" || true)
run_container_count=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ec '^discovery-relay_strfry-relay_run_' || true)
PID_FILE=$(get_live_sync_pid_file)
LOG_FILE=$(get_live_sync_log_file)

if relay_running; then
    relay_status="running"
else
    relay_status="stopped"
fi

live_sync_status="stopped"
live_sync_pid="-"
if [[ -f "$PID_FILE" ]]; then
    live_sync_pid=$(cat "$PID_FILE")
    if kill -0 "$live_sync_pid" >/dev/null 2>&1; then
        live_sync_status="running"
    else
        live_sync_status="stale pid file"
    fi
fi

status_label "Relay" "$relay_status"
status_label "Live sync" "$live_sync_status"
status_label "PID" "$live_sync_pid"
status_label "Relay containers" "$relay_container_count"
status_label "Worker containers" "$run_container_count"
status_label "Log file" "$LOG_FILE"

if systemctl list-unit-files openresist-discovery-live-sync.service >/dev/null 2>&1; then
    systemd_state=$(systemctl is-active openresist-discovery-live-sync.service 2>/dev/null || true)
    status_label "Systemd unit" "$systemd_state"
fi

if [[ -f "$LOG_FILE" ]]; then
    printf '\nRecent live sync log:\n'
    tail -n 20 "$LOG_FILE"
fi