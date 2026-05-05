#!/usr/bin/env bash
set -euo pipefail

mkdir -p models checkpoints input output user custom_nodes

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --disable-auto-launch \
    ${COMFYUI_EXTRA_ARGS:-}