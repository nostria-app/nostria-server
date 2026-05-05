#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-image-server
ENV_FILE="$PROJECT_DIR/.env"
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: bash ./scripts/download-model.sh [--dry-run] <model|repo> [file-pattern]

Models:
  z-image-turbo    Download configured Z-Image-Turbo diffusers files
  flux1-schnell    Download configured FLUX.1 schnell files; requires HF access approval
  flux2-klein      Download configured FLUX.2 klein files; update repo ID if needed

Examples:
  bash ./scripts/download-model.sh --dry-run z-image-turbo
  bash ./scripts/download-model.sh z-image-turbo
  HF_TOKEN=... bash ./scripts/download-model.sh flux1-schnell
  bash ./scripts/download-model.sh owner/repo-name '*.safetensors'
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

case "$1" in
    z-image-turbo)
        repo=${Z_IMAGE_REPO:-Tongyi-MAI/Z-Image-Turbo}
        pattern=${2:-${Z_IMAGE_PATTERN:-*.safetensors}}
        target_dir="$DATA_ROOT/models/diffusers/z-image-turbo"
        ;;
    flux1-schnell)
        repo=${FLUX1_SCHNELL_REPO:-black-forest-labs/FLUX.1-schnell}
        pattern=${2:-${FLUX1_SCHNELL_PATTERN:-*.safetensors}}
        target_dir="$DATA_ROOT/models/diffusers/flux1-schnell"
        ;;
    flux2-klein)
        repo=${FLUX2_KLEIN_REPO:-black-forest-labs/FLUX.2-klein}
        pattern=${2:-${FLUX2_KLEIN_PATTERN:-*.safetensors}}
        target_dir="$DATA_ROOT/models/diffusers/flux2-klein"
        ;;
    */*)
        repo=$1
        pattern=${2:-*.safetensors}
        safe_name=$(printf '%s' "$repo" | tr '/:' '--')
        target_dir="$DATA_ROOT/models/diffusers/$safe_name"
        ;;
    *)
        echo "ERROR: unknown model '$1'" >&2
        usage >&2
        exit 1
        ;;
esac

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
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

Install it on the host with:
  python3 -m pip install --user -U huggingface_hub

Then rerun this script. Set HF_TOKEN first for gated repositories such as FLUX.1 schnell.
EOF
    exit 1
fi

mkdir -p "$target_dir" "$DATA_ROOT/cache/huggingface"

echo "Downloading from Hugging Face"
echo "  repo:    $repo"
echo "  include: $pattern"
echo "  target:  $target_dir"

args=(download "$repo" --include "$pattern" --local-dir "$target_dir" --cache-dir "$DATA_ROOT/cache/huggingface")
if [[ "$DRY_RUN" == "true" ]]; then
    args+=(--dry-run)
fi

"$HF_CLI" "${args[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
    exit 0
fi

echo
echo "Downloaded model files:"
find "$target_dir" -type f \( -name '*.safetensors' -o -name '*.pt' -o -name '*.bin' \) -printf '  %P\n' | sort