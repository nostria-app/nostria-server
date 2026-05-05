#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-server
ENV_FILE="$PROJECT_DIR/.env"

usage() {
    cat <<'EOF'
Usage: bash ./scripts/download-model.sh <model|repo> [file-pattern]

Models:
  scout       Download the configured Llama 4 Scout GGUF pattern
  minimax     Download the configured MiniMax-M2.7 GGUF pattern

Examples:
  bash ./scripts/download-model.sh scout
  bash ./scripts/download-model.sh minimax
  bash ./scripts/download-model.sh unsloth/MiniMax-M2.7-GGUF '*UD-IQ4_XS*.gguf'

Set HF_TOKEN in the environment first if the repository requires Hugging Face access approval.
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

case "$1" in
    scout)
        repo=${LLAMA_SCOUT_REPO:-unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF}
        pattern=${2:-${LLAMA_SCOUT_PATTERN:-*Q4*.gguf}}
        target_dir="$DATA_ROOT/models/llama-4-scout"
        ;;
    minimax)
        repo=${MINIMAX_REPO:-unsloth/MiniMax-M2.7-GGUF}
        pattern=${2:-${MINIMAX_PATTERN:-*UD-IQ4_XS*.gguf}}
        target_dir="$DATA_ROOT/models/minimax-m2.7"
        ;;
    */*)
        repo=$1
        pattern=${2:-*.gguf}
        safe_name=$(printf '%s' "$repo" | tr '/:' '--')
        target_dir="$DATA_ROOT/models/$safe_name"
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
ERROR: huggingface-cli is not installed.

Install it on the host with one of:
  python3 -m pip install --user -U huggingface_hub[hf_transfer]
  pipx install huggingface_hub

Then rerun this script. For faster large downloads, also export HF_HUB_ENABLE_HF_TRANSFER=1.
EOF
    exit 1
fi

mkdir -p "$target_dir" "$DATA_ROOT/cache"

echo "Downloading from Hugging Face"
echo "  repo:    $repo"
echo "  include: $pattern"
echo "  target:  $target_dir"

"$HF_CLI" download "$repo" \
    --include "$pattern" \
    --local-dir "$target_dir" \
    --cache-dir "$DATA_ROOT/cache/huggingface"

echo
echo "Downloaded GGUF files:"
find "$target_dir" -type f \( -name '*.gguf' -o -name '*.gguf.*' \) -printf '  %P\n' | sort

first_model=$(find "$target_dir" -type f \( -name '*.gguf' -o -name '*.gguf.*' \) | sort | head -n 1 || true)
if [[ -n "$first_model" ]]; then
    relative_model=${first_model#"$DATA_ROOT/models/"}
    echo
    echo "Select one with:"
    echo "  bash ./scripts/select-model.sh '$relative_model'"
fi
