#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/media
CONFIG_TEMPLATE="$PROJECT_DIR/config/config.yml"
CONFIG_TARGET="$DATA_ROOT/config.yml"

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

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
fi

mkdir -p "$DATA_ROOT/data/blobs"

if [[ ! -f "$CONFIG_TARGET" ]]; then
    cp "$CONFIG_TEMPLATE" "$CONFIG_TARGET"
    echo "Created $CONFIG_TARGET from template"
else
    echo "Keeping existing config at $CONFIG_TARGET"
fi

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo "WARNING: $PROJECT_DIR/.env is missing; Blossom may generate a new admin password on each start" >&2
    echo "Copy .env.example to .env and set BLOSSOM_ADMIN_PASSWORD for a stable dashboard login" >&2
fi

cd "$PROJECT_DIR"
$COMPOSE_CMD pull media-server
$COMPOSE_CMD up -d media-server

echo "Media server is starting on 127.0.0.1:3000"
echo "Persistent data root: $DATA_ROOT"
