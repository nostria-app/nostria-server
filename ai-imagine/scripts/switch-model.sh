#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-imagine
ENV_FILE="$PROJECT_DIR/.env"
export DOCKER_API_VERSION=${DOCKER_API_VERSION:-1.41}

usage() {
    cat <<'EOF'
Usage: bash ./scripts/switch-model.sh <preset>

Presets:
  flux1-schnell
  flux1-schnell-gguf
  flux1-dev-gguf
  flux1-kontext-dev
  z-image-turbo
  z-image-base
  flux2-dev
  flux2-klein-4b
  flux2-klein-base-4b
  qwen-image
  qwen-image-edit
  qwen-image-edit-2509
  chroma
  ernie-image-turbo
  sdxl-base
  sd15

Run the matching download first when files are missing:
  bash ./scripts/download-model.sh <preset>
EOF
}

if [[ $# -lt 1 || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

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

find_one() {
    local dir=$1
    local pattern=$2
    local required=${3:-required}
    local match

    if [[ ! -d "$dir" ]]; then
        if [[ "$required" == "required" ]]; then
            echo "ERROR: missing directory $dir" >&2
            echo "Run: bash ./scripts/download-model.sh $preset" >&2
            return 1
        fi
        return 0
    fi

    match=$(find "$dir" -type f -name "$pattern" | sort | head -n 1 || true)
    if [[ -z "$match" && "$required" == "required" ]]; then
        echo "ERROR: no file matching '$pattern' under $dir" >&2
        echo "Run: bash ./scripts/download-model.sh $preset" >&2
        return 1
    fi

    printf '%s' "$match"
}

container_path() {
    local host_path=$1
    printf '%s' "${host_path/#$DATA_ROOT\/models/\/models}"
}

set_env_value() {
    local key=$1
    local value=$2
    local escaped

    mkdir -p "$(dirname "$ENV_FILE")"
    touch "$ENV_FILE"
    escaped=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$ENV_FILE"
    else
        printf '%s="%s"\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

require_file() {
    local file=$1
    if [[ ! -e "$file" ]]; then
        echo "ERROR: missing $file" >&2
        echo "Run: bash ./scripts/download-model.sh $preset" >&2
        exit 1
    fi
}

validate_model_args() {
    if [[ -z "$model_args" || "$model_args" == *"--diffusion-model  "* || "$model_args" == *"/models/models/"* ]]; then
        echo "ERROR: invalid model arguments for preset '$preset': $model_args" >&2
        echo "Run: bash ./scripts/download-model.sh $preset" >&2
        exit 1
    fi

    if [[ "$model_args" =~ --(diffusion-model|vae|clip_l|t5xxl|llm)[[:space:]]*(--|$) ]]; then
        echo "ERROR: missing value in model arguments for preset '$preset': $model_args" >&2
        echo "Run: bash ./scripts/download-model.sh $preset" >&2
        exit 1
    fi
}

preset=$1
model_args=""
default_args=""
extra_args=""

vae_flux="$DATA_ROOT/models/vae/ae.safetensors"
vae_flux2="$DATA_ROOT/models/vae/flux2_ae.safetensors"
vae_qwen="$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
clip_l="$DATA_ROOT/models/text_encoders/clip_l.safetensors"
t5_fp8="$DATA_ROOT/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"
t5_fp16="$DATA_ROOT/models/text_encoders/t5xxl_fp16.safetensors"

case "$preset" in
    flux1-schnell)
        require_file "$DATA_ROOT/models/diffusion_models/flux1-schnell.safetensors"
        require_file "$vae_flux"
        require_file "$clip_l"
        require_file "$t5_fp8"
        model_args="--diffusion-model /models/diffusion_models/flux1-schnell.safetensors --vae /models/vae/ae.safetensors --clip_l /models/text_encoders/clip_l.safetensors --t5xxl /models/text_encoders/t5xxl_fp8_e4m3fn.safetensors"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 4 -W 1024 -H 1024 -v"
        ;;
    flux1-schnell-gguf)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux1-schnell-gguf" '*.gguf')")
        require_file "$vae_flux"
        require_file "$clip_l"
        require_file "$t5_fp16"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --clip_l /models/text_encoders/clip_l.safetensors --t5xxl /models/text_encoders/t5xxl_fp16.safetensors"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 4 -W 1024 -H 1024 -v"
        ;;
    flux1-dev-gguf)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux1-dev-gguf" '*.gguf')")
        require_file "$vae_flux"
        require_file "$clip_l"
        require_file "$t5_fp16"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --clip_l /models/text_encoders/clip_l.safetensors --t5xxl /models/text_encoders/t5xxl_fp16.safetensors"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    flux1-kontext-dev)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux1-kontext-dev" '*.gguf')")
        require_file "$vae_flux"
        require_file "$clip_l"
        require_file "$t5_fp16"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --clip_l /models/text_encoders/clip_l.safetensors --t5xxl /models/text_encoders/t5xxl_fp16.safetensors"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    z-image-turbo)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/z-image-turbo" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen3-4b-instruct-2507" '*.gguf')")
        require_file "$vae_flux"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --llm $llm"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 8 -W 512 -H 1024 -v"
        ;;
    z-image-base)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/z-image-base" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen3-4b" '*.gguf')")
        require_file "$vae_flux"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --llm $llm"
        default_args="--cfg-scale 5.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    flux2-dev)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux2-dev" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/mistral-small-3.2-24b" '*.gguf')")
        require_file "$vae_flux2"
        model_args="--diffusion-model $model --vae /models/vae/flux2_ae.safetensors --llm $llm"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    flux2-klein-4b|flux2-klein)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux2-klein-4b" '*klein*4*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen3-4b" '*.gguf')")
        require_file "$vae_flux2"
        model_args="--diffusion-model $model --vae /models/vae/flux2_ae.safetensors --llm $llm"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 4 -W 1024 -H 1024 -v"
        ;;
    flux2-klein-base-4b)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/flux2-klein-base-4b" '*base*4*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen3-4b" '*.gguf')")
        require_file "$vae_flux2"
        model_args="--diffusion-model $model --vae /models/vae/flux2_ae.safetensors --llm $llm"
        default_args="--cfg-scale 4.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    qwen-image)
        echo "ERROR: preset '$preset' is currently disabled for this stable-diffusion.cpp build." >&2
        echo "The downloaded Qwen VAE fails to load with: tensor 'first_stage_model.*' not in model file." >&2
        echo "Use flux1-kontext-dev for reference/edit workflows, or retry Qwen after a compatible upstream Qwen VAE/binary is available." >&2
        exit 1
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/qwen-image" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b" '*.gguf')")
        require_file "$vae_qwen"
        model_args="--diffusion-model $model --vae /models/vae/qwen_image_vae.safetensors --llm $llm --diffusion-fa"
        default_args="--cfg-scale 4.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        ;;
    qwen-image-edit)
        echo "ERROR: preset '$preset' is currently disabled for this stable-diffusion.cpp build." >&2
        echo "The downloaded Qwen VAE fails to load with: tensor 'first_stage_model.*' not in model file." >&2
        echo "Use flux1-kontext-dev for reference/edit workflows, or retry Qwen after a compatible upstream Qwen VAE/binary is available." >&2
        exit 1
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/qwen-image-edit" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b" '*.gguf')")
        require_file "$vae_qwen"
        model_args="--diffusion-model $model --vae /models/vae/qwen_image_vae.safetensors --llm $llm --diffusion-fa"
        default_args="--cfg-scale 2.5 --sampling-method euler --steps 20 --flow-shift 3 -W 1024 -H 1024 -v"
        ;;
    qwen-image-edit-2509)
        echo "ERROR: preset '$preset' is currently disabled for this stable-diffusion.cpp build." >&2
        echo "The downloaded Qwen VAE fails to load with: tensor 'first_stage_model.*' not in model file." >&2
        echo "Use flux1-kontext-dev for reference/edit workflows, or retry Qwen after a compatible upstream Qwen VAE/binary is available." >&2
        exit 1
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/qwen-image-edit-2509" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b" '*.gguf')")
        llm_vision=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b" '*mmproj*.gguf' optional)")
        require_file "$vae_qwen"
        model_args="--diffusion-model $model --vae /models/vae/qwen_image_vae.safetensors --llm $llm --diffusion-fa"
        if [[ -n "$llm_vision" ]]; then
            model_args="$model_args --llm_vision $llm_vision"
        fi
        default_args="--cfg-scale 2.5 --sampling-method euler --steps 20 --flow-shift 3 -W 1024 -H 1024 -v"
        ;;
    chroma)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/chroma" '*.gguf')")
        require_file "$vae_flux"
        require_file "$t5_fp16"
        model_args="--diffusion-model $model --vae /models/vae/ae.safetensors --t5xxl /models/text_encoders/t5xxl_fp16.safetensors"
        default_args="--cfg-scale 4.0 --sampling-method euler --steps 20 -W 1024 -H 1024 -v"
        extra_args="--chroma-disable-dit-mask"
        ;;
    ernie-image-turbo)
        model=$(container_path "$(find_one "$DATA_ROOT/models/diffusion_models/ernie-image-turbo" '*.gguf')")
        llm=$(container_path "$(find_one "$DATA_ROOT/models/text_encoders/ministral-3-3b" '*.gguf')")
        require_file "$vae_flux2"
        model_args="--diffusion-model $model --vae /models/vae/flux2_ae.safetensors --llm $llm"
        default_args="--cfg-scale 1.0 --sampling-method euler --steps 8 -W 1024 -H 1024 -v"
        ;;
    sdxl-base)
        model=$(container_path "$(find_one "$DATA_ROOT/models/checkpoints/sdxl-base" '*.safetensors')")
        vae=$(container_path "$(find_one "$DATA_ROOT/models/vae" 'sdxl*.safetensors' optional)")
        model_args="-m $model"
        if [[ -n "$vae" ]]; then
            model_args="$model_args --vae $vae"
        fi
        default_args="--cfg-scale 7.0 --sampling-method euler_a --steps 30 -W 1024 -H 1024 -v"
        ;;
    sd15)
        model=$(container_path "$(find_one "$DATA_ROOT/models/checkpoints/sd15" '*.safetensors')")
        model_args="-m $model"
        default_args="--cfg-scale 7.0 --sampling-method euler_a --steps 30 -W 512 -H 512 -v"
        ;;
    *)
        echo "ERROR: unknown preset '$preset'" >&2
        usage >&2
        exit 1
        ;;
esac

validate_model_args

set_env_value SDCPP_MODEL_PRESET "$preset"
set_env_value SDCPP_MODEL_ARGS "$model_args"
set_env_value SDCPP_DEFAULT_ARGS "$default_args"
set_env_value SDCPP_EXTRA_ARGS "$extra_args"

COMPOSE_CMD=$(get_compose_cmd)
cd "$PROJECT_DIR"
$COMPOSE_CMD up -d stable-diffusion-cpp

echo "Switched ai-imagine to preset: $preset"
echo "Model args: $model_args"
