#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this script with sudo" >&2
    exit 1
fi

bash "$SCRIPT_DIR/install-sync-timer.sh"
bash "$SCRIPT_DIR/install-live-sync-service.sh"

echo
echo "Persistent discovery sync jobs are installed and enabled."