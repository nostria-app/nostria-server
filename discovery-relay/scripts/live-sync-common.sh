#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
SERVICE_NAME="strfry-relay"
DATA_ROOT="/mnt/data/openresist/discovery-relay"
LOG_DIR="$DATA_ROOT/log"
STATE_DIR="$DATA_ROOT/sync"

mkdir -p "$LOG_DIR" "$STATE_DIR"

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
    compose ps --services --filter status=running | grep -qx "$SERVICE_NAME"
}