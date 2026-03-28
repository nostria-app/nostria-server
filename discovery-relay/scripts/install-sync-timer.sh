#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SYSTEMD_DIR="$PROJECT_DIR/systemd"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this script with sudo" >&2
    exit 1
fi

install -m 0644 "$SYSTEMD_DIR/openresist-discovery-sync.service" /etc/systemd/system/openresist-discovery-sync.service
install -m 0644 "$SYSTEMD_DIR/openresist-discovery-sync.timer" /etc/systemd/system/openresist-discovery-sync.timer

systemctl daemon-reload
systemctl enable --now openresist-discovery-sync.timer

echo "Installed and started openresist-discovery-sync.timer"
systemctl status --no-pager openresist-discovery-sync.timer