#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist
SERVICE_ROOT="$DATA_ROOT/discovery-relay"
STRFRY_DIR=$(cd "$PROJECT_DIR/../../strfry" && pwd)
EXPECTED_STRFRY_VERSION="1.1.0"

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

CURRENT_STRFRY_REF="unknown"
if command -v git >/dev/null 2>&1 && [[ -d "$STRFRY_DIR/.git" ]]; then
    CURRENT_STRFRY_REF=$(git -C "$STRFRY_DIR" describe --tags --always --dirty 2>/dev/null || true)
fi

mkdir -p "$SERVICE_ROOT/db" "$SERVICE_ROOT/log"

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
fi

if [[ ! -w "$DATA_ROOT" && ! -w /mnt/data ]]; then
    echo "ERROR: DATA_ROOT is not writable: $DATA_ROOT" >&2
    exit 1
fi

echo "Using data root: $SERVICE_ROOT"
echo "Using compose command: $COMPOSE_CMD"
echo "Using strfry source: $STRFRY_DIR ($CURRENT_STRFRY_REF)"
if [[ "$CURRENT_STRFRY_REF" != "$EXPECTED_STRFRY_VERSION" ]]; then
    echo "WARNING: expected strfry $EXPECTED_STRFRY_VERSION for the discovery relay build" >&2
fi
echo "Building and starting discovery relay stack..."

cd "$PROJECT_DIR"
$COMPOSE_CMD up -d --build strfry-relay

echo "Discovery relay is starting on 127.0.0.1:7777"
echo "Cloudflare Tunnel origin should target: http://127.0.0.1:7777"
echo "Use scripts/initial-sync.sh when you want to run a manual discovery data sync."