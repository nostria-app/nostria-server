#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-imagine
ENV_FILE="$PROJECT_DIR/.env"

usage() {
    cat <<'EOF'
Usage: bash ./scripts/download-model.sh <model|repo> [file-pattern]

Models:
  flux1-schnell       Download FLUX.1 schnell safetensors and text encoders
    flux1-schnell-gguf  Download preconverted FLUX.1 schnell GGUF plus FLUX encoders
    flux1-dev-gguf      Download preconverted FLUX.1 dev GGUF plus FLUX encoders
    flux1-kontext-dev   Download FLUX.1 Kontext dev GGUF plus FLUX encoders
  z-image-turbo       Download Z-Image-Turbo GGUF plus Qwen3 4B GGUF text encoder
    z-image-base        Download Z-Image base GGUF plus Qwen3 4B GGUF text encoder
    flux2-dev           Download FLUX.2 dev GGUF plus Mistral Small text encoder
    flux2-klein-4b      Download FLUX.2 klein 4B GGUF plus Qwen3 4B GGUF text encoder
    flux2-klein-base-4b Download FLUX.2 klein base 4B GGUF plus Qwen3 4B GGUF text encoder
    qwen-image          Download Qwen Image GGUF plus Qwen2.5-VL text encoder
    qwen-image-edit     Download Qwen Image Edit GGUF plus Qwen2.5-VL text encoder
    qwen-image-edit-2509 Download Qwen Image Edit 2509 GGUF plus Qwen2.5-VL assets
    chroma              Download Chroma GGUF plus FLUX VAE/T5 assets
    ernie-image-turbo   Download ERNIE-Image-Turbo GGUF plus Ministral text encoder
    sdxl-base           Download SDXL Base 1.0 safetensors
    sd15                Download Stable Diffusion 1.5 safetensors

Examples:
  bash ./scripts/download-model.sh flux1-schnell
    bash ./scripts/download-model.sh flux1-kontext-dev '*Q4_K_M*.gguf'
  bash ./scripts/download-model.sh z-image-turbo '*Q3_K*.gguf'
    bash ./scripts/download-model.sh flux2-klein-4b '*Q4_K_M*.gguf'
  bash ./scripts/download-model.sh owner/repo-name '*.gguf'

Set HF_TOKEN in the environment or .env if a repository requires Hugging Face access approval.
EOF
}

if [[ $# -lt 1 || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

if command -v hf >/dev/null 2>&1; then
    HF_CLI=$(command -v hf)
elif [[ -x "$HOME/.local/bin/hf" ]]; then
    HF_CLI="$HOME/.local/bin/hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_CLI=$(command -v huggingface-cli)
elif [[ -x "$HOME/.local/bin/huggingface-cli" ]]; then
    HF_CLI="$HOME/.local/bin/huggingface-cli"
else
    cat >&2 <<'EOF'
ERROR: Hugging Face CLI is not installed.

Install it on the host with one of:
  python3 -m pip install --user -U huggingface_hub[hf_transfer]
  pipx install huggingface_hub
EOF
    exit 1
fi

download_file() {
    local repo=$1
    local file=$2
    local target_dir=$3

    mkdir -p "$target_dir" "$DATA_ROOT/cache"
    "$HF_CLI" download "$repo" "$file" \
        --local-dir "$target_dir" \
        --cache-dir "$DATA_ROOT/cache/huggingface"
}

download_pattern() {
    local repo=$1
    local pattern=$2
    local target_dir=$3

    mkdir -p "$target_dir" "$DATA_ROOT/cache"
    "$HF_CLI" download "$repo" \
        --include "$pattern" \
        --local-dir "$target_dir" \
        --cache-dir "$DATA_ROOT/cache/huggingface"
}

link_first_match() {
    local source_dir=$1
    local pattern=$2
    local target=$3
    local source

    source=$(find "$source_dir" -type f -name "$pattern" | sort | head -n 1 || true)
    if [[ -n "$source" && ! -e "$target" ]]; then
        ln -s "$source" "$target"
    fi
}

case "$1" in
    flux1-schnell)
        download_file "${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}" flux1-schnell.safetensors "$DATA_ROOT/models/diffusion_models"
        download_file "${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}" ae.safetensors "$DATA_ROOT/models/vae"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" clip_l.safetensors "$DATA_ROOT/models/text_encoders"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" t5xxl_fp8_e4m3fn.safetensors "$DATA_ROOT/models/text_encoders"
        ;;
    flux1-schnell-gguf)
        pattern=${2:-*q4_0*.gguf}
        download_pattern "${FLUX1_SCHNELL_GGUF_REPO:-leejet/FLUX.1-schnell-gguf}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux1-schnell-gguf"
        download_file "${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}" ae.safetensors "$DATA_ROOT/models/vae"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" clip_l.safetensors "$DATA_ROOT/models/text_encoders"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" t5xxl_fp16.safetensors "$DATA_ROOT/models/text_encoders"
        ;;
    flux1-dev-gguf)
        pattern=${2:-*q4_0*.gguf}
        download_pattern "${FLUX1_DEV_GGUF_REPO:-leejet/FLUX.1-dev-gguf}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux1-dev-gguf"
        download_file "${FLUX1_DEV_REPO:-black-forest-labs/FLUX.1-dev}" ae.safetensors "$DATA_ROOT/models/vae"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" clip_l.safetensors "$DATA_ROOT/models/text_encoders"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" t5xxl_fp16.safetensors "$DATA_ROOT/models/text_encoders"
        ;;
    flux1-kontext-dev)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${FLUX1_KONTEXT_GGUF_REPO:-QuantStack/FLUX.1-Kontext-dev-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux1-kontext-dev"
        download_file "${FLUX1_DEV_REPO:-black-forest-labs/FLUX.1-dev}" ae.safetensors "$DATA_ROOT/models/vae"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" clip_l.safetensors "$DATA_ROOT/models/text_encoders"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" t5xxl_fp16.safetensors "$DATA_ROOT/models/text_encoders"
        ;;
    z-image-turbo)
        pattern=${2:-*Q3_K*.gguf}
        download_pattern "${Z_IMAGE_TURBO_GGUF_REPO:-leejet/Z-Image-Turbo-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/z-image-turbo"
        download_pattern "${QWEN3_4B_INSTRUCT_GGUF_REPO:-unsloth/Qwen3-4B-Instruct-2507-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen3-4b-instruct-2507"
        download_file "${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}" ae.safetensors "$DATA_ROOT/models/vae"
        ;;
    z-image-base)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${Z_IMAGE_BASE_GGUF_REPO:-unsloth/Z-Image-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/z-image-base"
        download_pattern "${QWEN3_4B_GGUF_REPO:-unsloth/Qwen3-4B-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen3-4b"
        download_file "${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}" ae.safetensors "$DATA_ROOT/models/vae"
        ;;
    flux2-dev)
        pattern=${2:-*Q4_K_S*.gguf}
        download_pattern "${FLUX2_DEV_GGUF_REPO:-city96/FLUX.2-dev-gguf}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux2-dev"
        download_pattern "${MISTRAL_SMALL_32_24B_GGUF_REPO:-unsloth/Mistral-Small-3.2-24B-Instruct-2506-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/mistral-small-3.2-24b"
        download_pattern "${FLUX2_DEV_REPO:-black-forest-labs/FLUX.2-dev}" '*ae*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*ae*.safetensors' "$DATA_ROOT/models/vae/flux2_ae.safetensors"
        ;;
    flux2-klein|flux2-klein-4b)
        pattern=${2:-*Q4*.gguf}
        download_pattern "${FLUX2_KLEIN_4B_GGUF_REPO:-leejet/FLUX.2-klein-4B-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux2-klein-4b"
        download_pattern "${QWEN3_4B_GGUF_REPO:-unsloth/Qwen3-4B-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen3-4b"
        download_pattern "${FLUX2_DEV_REPO:-black-forest-labs/FLUX.2-dev}" '*ae*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*ae*.safetensors' "$DATA_ROOT/models/vae/flux2_ae.safetensors"
        ;;
    flux2-klein-base-4b)
        pattern=${2:-*Q4*.gguf}
        download_pattern "${FLUX2_KLEIN_BASE_4B_GGUF_REPO:-leejet/FLUX.2-klein-base-4B-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/flux2-klein-base-4b"
        download_pattern "${QWEN3_4B_GGUF_REPO:-unsloth/Qwen3-4B-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen3-4b"
        download_pattern "${FLUX2_DEV_REPO:-black-forest-labs/FLUX.2-dev}" '*ae*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*ae*.safetensors' "$DATA_ROOT/models/vae/flux2_ae.safetensors"
        ;;
    qwen-image)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${QWEN_IMAGE_GGUF_REPO:-QuantStack/Qwen-Image-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/qwen-image"
        download_pattern "${QWEN25_VL_7B_GGUF_REPO:-mradermacher/Qwen2.5-VL-7B-Instruct-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b"
        download_pattern "${QWEN_IMAGE_COMFY_REPO:-Comfy-Org/Qwen-Image_ComfyUI}" 'split_files/vae/*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*qwen*vae*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        link_first_match "$DATA_ROOT/models/vae" '*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        ;;
    qwen-image-edit)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${QWEN_IMAGE_EDIT_GGUF_REPO:-QuantStack/Qwen-Image-Edit-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/qwen-image-edit"
        download_pattern "${QWEN25_VL_7B_GGUF_REPO:-mradermacher/Qwen2.5-VL-7B-Instruct-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b"
        download_pattern "${QWEN_IMAGE_COMFY_REPO:-Comfy-Org/Qwen-Image_ComfyUI}" 'split_files/vae/*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*qwen*vae*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        link_first_match "$DATA_ROOT/models/vae" '*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        ;;
    qwen-image-edit-2509)
        pattern=${2:-*Q4_K_S*.gguf}
        download_pattern "${QWEN_IMAGE_EDIT_2509_GGUF_REPO:-QuantStack/Qwen-Image-Edit-2509-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/qwen-image-edit-2509"
        download_pattern "${QWEN25_VL_7B_GGUF_REPO:-mradermacher/Qwen2.5-VL-7B-Instruct-GGUF}" '*Q8_0*.gguf' "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b"
        download_pattern "${QWEN25_VL_7B_GGUF_REPO:-mradermacher/Qwen2.5-VL-7B-Instruct-GGUF}" '*mmproj*.gguf' "$DATA_ROOT/models/text_encoders/qwen2.5-vl-7b"
        download_pattern "${QWEN_IMAGE_COMFY_REPO:-Comfy-Org/Qwen-Image_ComfyUI}" 'split_files/vae/*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*qwen*vae*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        link_first_match "$DATA_ROOT/models/vae" '*.safetensors' "$DATA_ROOT/models/vae/qwen_image_vae.safetensors"
        ;;
    chroma)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${CHROMA_GGUF_REPO:-silveroxides/Chroma-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/chroma"
        download_file "${FLUX1_DEV_REPO:-black-forest-labs/FLUX.1-dev}" ae.safetensors "$DATA_ROOT/models/vae"
        download_file "${FLUX_TEXT_ENCODERS_REPO:-comfyanonymous/flux_text_encoders}" t5xxl_fp16.safetensors "$DATA_ROOT/models/text_encoders"
        ;;
    ernie-image-turbo)
        pattern=${2:-*Q4_K_M*.gguf}
        download_pattern "${ERNIE_IMAGE_TURBO_GGUF_REPO:-unsloth/ERNIE-Image-Turbo-GGUF}" "$pattern" "$DATA_ROOT/models/diffusion_models/ernie-image-turbo"
        download_pattern "${MINISTRAL_33B_GGUF_REPO:-unsloth/Ministral-3-3B-Instruct-2512-GGUF}" '*Q4_K_M*.gguf' "$DATA_ROOT/models/text_encoders/ministral-3-3b"
        download_pattern "${FLUX2_DEV_REPO:-black-forest-labs/FLUX.2-dev}" '*ae*.safetensors' "$DATA_ROOT/models/vae"
        link_first_match "$DATA_ROOT/models/vae" '*ae*.safetensors' "$DATA_ROOT/models/vae/flux2_ae.safetensors"
        ;;
    sdxl-base)
        download_file "${SDXL_BASE_REPO:-stabilityai/stable-diffusion-xl-base-1.0}" sd_xl_base_1.0.safetensors "$DATA_ROOT/models/checkpoints/sdxl-base"
        download_file "${SDXL_VAE_REPO:-madebyollin/sdxl-vae-fp16-fix}" sdxl_vae.safetensors "$DATA_ROOT/models/vae" || true
        ;;
    sd15)
        download_file "${SD15_REPO:-stable-diffusion-v1-5/stable-diffusion-v1-5}" v1-5-pruned-emaonly.safetensors "$DATA_ROOT/models/checkpoints/sd15"
        ;;
    */*)
        repo=$1
        pattern=${2:-*.gguf}
        safe_name=$(printf '%s' "$repo" | tr '/:' '--')
        download_pattern "$repo" "$pattern" "$DATA_ROOT/models/$safe_name"
        ;;
    *)
        echo "ERROR: unknown model '$1'" >&2
        usage >&2
        exit 1
        ;;
esac

echo
echo "Available model files under $DATA_ROOT/models:"
find "$DATA_ROOT/models" -type f \( -name '*.safetensors' -o -name '*.gguf' \) -printf '  %P\n' | sort