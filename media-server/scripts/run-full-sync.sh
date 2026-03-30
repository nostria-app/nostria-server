#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
LOG_DIR=/mnt/data/openresist/media/log
LOG_FILE="$LOG_DIR/full-sync.log"

REMOTE_USERNAME=${REMOTE_USERNAME:-admin}
REMOTE_PASSWORD=${REMOTE_PASSWORD:?REMOTE_PASSWORD is required}
REMOTE_URLS=${REMOTE_URLS:-"https://mibo.nostria.app https://milo.nostria.app"}

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

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG_FILE"
}

run_sync() {
    local remote_url="$1"

    log "starting full sync from ${remote_url}"
    docker run --rm \
        --entrypoint=node \
        -e BLOSSOM_CONFIG=/app/data/config.yml \
        -v /mnt/data/openresist/media:/app/data \
        -v "$SCRIPT_DIR/full-sync.mjs:/tmp/full-sync.mjs:ro" \
        ghcr.io/nostria-app/nostria-media:latest \
        /tmp/full-sync.mjs \
            --remoteUrl "$remote_url" \
            --remoteUsername "$REMOTE_USERNAME" \
            --remotePassword "$REMOTE_PASSWORD" | tee -a "$LOG_FILE"
    log "finished full sync from ${remote_url}"
}

cd "$PROJECT_DIR"

pkill -f '/tmp/full-sync.mjs' >/dev/null 2>&1 || true

$COMPOSE_CMD stop media-server || true

for remote_url in $REMOTE_URLS; do
    run_sync "$remote_url"
done

$COMPOSE_CMD up -d media-server | tee -a "$LOG_FILE"
log "media server restarted"
