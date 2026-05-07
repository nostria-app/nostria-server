#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-imagine
OLD_MODEL_ROOT=/mnt/data/openresist/ai-image-server/models
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

link_if_present() {
    local source=$1
    local target=$2

    if [[ -e "$target" ]]; then
        return
    fi

    if [[ -e "$source" ]]; then
        mkdir -p "$(dirname "$target")"
        ln -s "$source" "$target"
        echo "Linked $target -> $source"
    fi
}

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
fi

mkdir -p \
    "$DATA_ROOT/models/checkpoints" \
    "$DATA_ROOT/models/diffusion_models" \
    "$DATA_ROOT/models/clip_vision" \
    "$DATA_ROOT/models/text_encoders" \
    "$DATA_ROOT/models/loras" \
    "$DATA_ROOT/models/upscalers" \
    "$DATA_ROOT/models/vae" \
    "$DATA_ROOT/output" \
    "$DATA_ROOT/cache"

if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    echo "Created $ENV_FILE"
else
    echo "Keeping existing env at $ENV_FILE"
fi

link_if_present "$OLD_MODEL_ROOT/diffusion_models/flux1-schnell.safetensors" "$DATA_ROOT/models/diffusion_models/flux1-schnell.safetensors"
link_if_present "$OLD_MODEL_ROOT/diffusers/flux1-schnell/flux1-schnell.safetensors" "$DATA_ROOT/models/diffusion_models/flux1-schnell.safetensors"
link_if_present "$OLD_MODEL_ROOT/vae/ae.safetensors" "$DATA_ROOT/models/vae/ae.safetensors"
link_if_present "$OLD_MODEL_ROOT/diffusers/flux1-schnell/ae.safetensors" "$DATA_ROOT/models/vae/ae.safetensors"
link_if_present "$OLD_MODEL_ROOT/text_encoders/clip_l.safetensors" "$DATA_ROOT/models/text_encoders/clip_l.safetensors"
link_if_present "$OLD_MODEL_ROOT/text_encoders/t5xxl_fp8_e4m3fn.safetensors" "$DATA_ROOT/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"

missing=0
for required in \
    "$DATA_ROOT/models/diffusion_models/flux1-schnell.safetensors" \
    "$DATA_ROOT/models/vae/ae.safetensors" \
    "$DATA_ROOT/models/text_encoders/clip_l.safetensors" \
    "$DATA_ROOT/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing required default model file: $required" >&2
        missing=1
    fi
done

if [[ "$missing" -ne 0 ]]; then
    cat >&2 <<'EOF'

Download or import FLUX.1 schnell first:
  bash ./scripts/download-model.sh flux1-schnell

Then rerun:
  bash ./scripts/bootstrap.sh
EOF
    exit 1
fi

COMPOSE_CMD=$(get_compose_cmd)

cd "$PROJECT_DIR"
$COMPOSE_CMD build stable-diffusion-cpp
$COMPOSE_CMD up -d stable-diffusion-cpp

echo "stable-diffusion.cpp is starting on ${AI_IMAGINE_HOST_BIND:-0.0.0.0}:${AI_IMAGINE_HOST_PORT:-8090}"
echo "Persistent data root: $DATA_ROOT"