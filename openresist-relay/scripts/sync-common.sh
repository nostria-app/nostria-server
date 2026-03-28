#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
SERVICE_NAME="openresist-relay"
DATA_ROOT="/mnt/data/openresist/relay"
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

count_events() {
    if relay_running; then
        compose exec -T "$SERVICE_NAME" /app/strfry --config /etc/strfry.conf scan '{}' | wc -l
        return
    fi

    compose run --rm --no-deps "$SERVICE_NAME" --config /etc/strfry.conf scan '{}' | wc -l
}

sync_url_for_target() {
    case "$1" in
        eu)
            echo "wss://ribo.eu.nostria.app/"
            ;;
        us)
            echo "wss://ribo.us.nostria.app/"
            ;;
        *)
            echo "ERROR: unknown sync target '$1'" >&2
            exit 1
            ;;
    esac
}

target_label() {
    case "$1" in
        eu)
            echo "EU"
            ;;
        us)
            echo "US"
            ;;
        *)
            echo "ERROR: unknown sync target '$1'" >&2
            exit 1
            ;;
    esac
}

run_sync_once() {
    local target="$1"
    local relay_url
    relay_url=$(sync_url_for_target "$target")

    compose run --rm --no-deps "$SERVICE_NAME" \
        --config /etc/strfry.conf sync "$relay_url" --dir down
}