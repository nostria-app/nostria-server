#!/usr/bin/env sh
set -eu

if command -v llama-server >/dev/null 2>&1; then
    SERVER_BIN=llama-server
elif [ -x /app/llama-server ]; then
    SERVER_BIN=/app/llama-server
else
    echo "ERROR: llama-server binary was not found in the container image" >&2
    exit 1
fi

if [ -z "${LLAMA_MODEL_FILE:-}" ]; then
    echo "ERROR: LLAMA_MODEL_FILE is not set" >&2
    exit 1
fi

MODEL_PATH="/models/${LLAMA_MODEL_FILE}"
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: model file not found: $MODEL_PATH" >&2
    echo "Download a GGUF into /mnt/data/openresist/ai-server/models and update LLAMA_MODEL_FILE." >&2
    exit 1
fi

set -- \
    --host 0.0.0.0 \
    --port 8080 \
    --model "$MODEL_PATH" \
    --alias "${LLAMA_MODEL_ALIAS:-nostria-ai}" \
    --ctx-size "${LLAMA_CTX_SIZE:-4096}" \
    --threads "${LLAMA_THREADS:-0}" \
    --parallel "${LLAMA_PARALLEL:-1}" \
    --batch-size "${LLAMA_BATCH_SIZE:-512}" \
    --ubatch-size "${LLAMA_UBATCH_SIZE:-128}" \
    --cache-type-k "${LLAMA_CACHE_TYPE_K:-q4_0}" \
    --cache-type-v "${LLAMA_CACHE_TYPE_V:-q4_0}"

if [ -n "${LLAMA_API_KEY:-}" ]; then
    set -- "$@" --api-key "$LLAMA_API_KEY"
fi

if [ "${LLAMA_MLOCK:-false}" = "true" ]; then
    set -- "$@" --mlock
fi

if [ "${LLAMA_NO_MMAP:-false}" = "true" ]; then
    set -- "$@" --no-mmap
fi

if [ -n "${LLAMA_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2086
    set -- "$@" $LLAMA_EXTRA_ARGS
fi

exec "$SERVER_BIN" "$@"
