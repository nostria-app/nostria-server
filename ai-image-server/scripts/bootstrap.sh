#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-image-server
ENV_FILE="$PROJECT_DIR/.env"
ENV_TEMPLATE="$PROJECT_DIR/.env.example"
START_SERVICE=true
export DOCKER_API_VERSION=${DOCKER_API_VERSION:-1.41}

usage() {
    cat <<'EOF'
Usage: bash ./scripts/bootstrap.sh [--no-start]

Options:
  --no-start    Create data directories and .env only; do not build/start containers
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-start)
            START_SERVICE=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

get_compose_cmd() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
        return
    fi

    echo "ERROR: neither docker compose nor docker-compose is available" >&2
    exit 1
}

generate_api_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
        return
    fi

    head -c 32 /dev/urandom | base64 | tr -d '\n='
}

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
fi

mkdir -p \
    "$DATA_ROOT/models/checkpoints" \
    "$DATA_ROOT/models/diffusers" \
    "$DATA_ROOT/models/diffusion_models" \
    "$DATA_ROOT/models/text_encoders" \
    "$DATA_ROOT/models/vae" \
    "$DATA_ROOT/models/clip" \
    "$DATA_ROOT/models/loras" \
    "$DATA_ROOT/models/controlnet" \
    "$DATA_ROOT/models/upscale_models" \
    "$DATA_ROOT/input" \
    "$DATA_ROOT/output" \
    "$DATA_ROOT/user" \
    "$DATA_ROOT/custom_nodes" \
    "$DATA_ROOT/cache" \
    "$DATA_ROOT/logs"

if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    api_key=$(generate_api_key)
    sed -i "s/^IMAGE_API_KEY=.*/IMAGE_API_KEY=$api_key/" "$ENV_FILE"
    echo "Created $ENV_FILE with a generated IMAGE_API_KEY"
else
    echo "Keeping existing env at $ENV_FILE"
fi

if [[ "$START_SERVICE" != "true" ]]; then
    echo "Data root initialized: $DATA_ROOT"
    exit 0
fi

COMPOSE_CMD=$(get_compose_cmd)

cd "$PROJECT_DIR"
$COMPOSE_CMD build
$COMPOSE_CMD up -d

echo "AI image API is starting on ${AI_IMAGE_SERVER_HOST_BIND:-127.0.0.1}:${AI_IMAGE_SERVER_HOST_PORT:-8090}"
echo "Persistent data root: $DATA_ROOT"