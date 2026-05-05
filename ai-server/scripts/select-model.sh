#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/ai-server
ENV_FILE="$PROJECT_DIR/.env"

usage() {
    cat <<'EOF'
Usage: bash ./scripts/select-model.sh <relative-gguf-path> [alias]

Example:
  bash ./scripts/select-model.sh llama-4-scout/model.Q4_K_M.gguf llama-4-scout
  bash ./scripts/select-model.sh minimax-m2.7/model.UD-IQ4_XS.gguf minimax-m2.7
EOF
}

set_env_value() {
    local key=$1
    local value=$2

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

if [[ $# -lt 1 || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

relative_model=$1
alias=${2:-$(basename "$relative_model" .gguf)}

if [[ "$relative_model" = /* || "$relative_model" == *..* ]]; then
    echo "ERROR: provide a safe path relative to $DATA_ROOT/models" >&2
    exit 1
fi

if [[ ! -f "$DATA_ROOT/models/$relative_model" ]]; then
    echo "ERROR: model not found: $DATA_ROOT/models/$relative_model" >&2
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
fi

set_env_value LLAMA_MODEL_FILE "$relative_model"
set_env_value LLAMA_MODEL_ALIAS "$alias"

echo "Selected model: $relative_model"
echo "Model alias:    $alias"
echo "Restart with:   bash ./scripts/bootstrap.sh"
