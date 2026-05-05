#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-server
ENV_FILE="$PROJECT_DIR/.env"
ENV_TEMPLATE="$PROJECT_DIR/.env.example"
export DOCKER_API_VERSION=${DOCKER_API_VERSION:-1.41}

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

mkdir -p "$DATA_ROOT/models" "$DATA_ROOT/cache" "$DATA_ROOT/logs"

if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    api_key=$(generate_api_key)
    sed -i "s/^LLAMA_API_KEY=.*/LLAMA_API_KEY=$api_key/" "$ENV_FILE"
    echo "Created $ENV_FILE with a generated LLAMA_API_KEY"
else
    echo "Keeping existing env at $ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ -z "${LLAMA_MODEL_FILE:-}" ]]; then
    echo "ERROR: LLAMA_MODEL_FILE is empty in $ENV_FILE" >&2
    exit 1
fi

if [[ ! -f "$DATA_ROOT/models/$LLAMA_MODEL_FILE" ]]; then
    cat >&2 <<EOF
ERROR: selected model is missing:
  $DATA_ROOT/models/$LLAMA_MODEL_FILE

Download a model first, then select the GGUF file:
  bash ./scripts/download-model.sh scout
  bash ./scripts/select-model.sh <relative-path-under-models> llama-4-scout

For MiniMax, use:
  bash ./scripts/download-model.sh minimax
EOF
    exit 1
fi

COMPOSE_CMD=$(get_compose_cmd)

cd "$PROJECT_DIR"
$COMPOSE_CMD build ai-server
$COMPOSE_CMD up -d ai-server

echo "AI server is starting on ${AI_SERVER_HOST_BIND:-127.0.0.1}:${AI_SERVER_HOST_PORT:-8088}"
echo "Persistent data root: $DATA_ROOT"
