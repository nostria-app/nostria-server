#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SYSTEMD_DIR="$PROJECT_DIR/systemd"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this script with sudo" >&2
    exit 1
fi

install -m 0644 "$SYSTEMD_DIR/openresist-discovery-live-sync.service" /etc/systemd/system/openresist-discovery-live-sync.service

systemctl daemon-reload
systemctl enable --now openresist-discovery-live-sync.service

echo "Installed and started openresist-discovery-live-sync.service"
systemctl status --no-pager openresist-discovery-live-sync.service