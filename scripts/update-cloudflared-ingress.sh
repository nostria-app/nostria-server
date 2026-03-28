#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=${CONFIG_FILE:-/etc/cloudflared/config.yml}
TARGET_HOSTNAME=indexer.openresist.com
TARGET_SERVICE=http://127.0.0.1:7777
RESTART_CLOUDFLARED=true

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/update-cloudflared-ingress.sh [options]

Options:
  --hostname <hostname>   Hostname to route through the tunnel
  --service <url>         Local origin service URL
  --config <path>         cloudflared config file path
  --no-restart            Update the config but do not restart cloudflared
  --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            TARGET_HOSTNAME=${2:?missing value for --hostname}
            shift 2
            ;;
        --service)
            TARGET_SERVICE=${2:?missing value for --service}
            shift 2
            ;;
        --config)
            CONFIG_FILE=${2:?missing value for --config}
            shift 2
            ;;
        --no-restart)
            RESTART_CLOUDFLARED=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this script with sudo or as root" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: cloudflared config not found: $CONFIG_FILE" >&2
    exit 1
fi

if ! grep -q '^ingress:' "$CONFIG_FILE"; then
    echo "ERROR: ingress section not found in $CONFIG_FILE" >&2
    exit 1
fi

TMP_FILE=$(mktemp)
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"

awk -v target_hostname="$TARGET_HOSTNAME" -v target_service="$TARGET_SERVICE" '
BEGIN {
    in_ingress = 0
    skip_target = 0
    count = 0
    fallback = "  - service: http_status:404"
}

{
    if (!in_ingress) {
        print
        if ($0 ~ /^ingress:[[:space:]]*$/) {
            in_ingress = 1
        }
        next
    }

    if (skip_target) {
        if ($0 ~ /^    /) {
            next
        }
        skip_target = 0
    }

    if ($0 == "  - hostname: " target_hostname) {
        skip_target = 1
        next
    }

    if ($0 ~ /^  - service:[[:space:]]*http_status:404([[:space:]]*#.*)?$/) {
        fallback = $0
        next
    }

    lines[++count] = $0
}

END {
    for (i = 1; i <= count; i++) {
        print lines[i]
    }
    print "  - hostname: " target_hostname
    print "    service: " target_service
    print fallback
}
' "$CONFIG_FILE" > "$TMP_FILE"

cp "$CONFIG_FILE" "$BACKUP_FILE"
install -m 0644 "$TMP_FILE" "$CONFIG_FILE"
rm -f "$TMP_FILE"

echo "Updated $CONFIG_FILE"
echo "Backup written to $BACKUP_FILE"

if [[ "$RESTART_CLOUDFLARED" == "true" ]]; then
    systemctl restart cloudflared
    systemctl status --no-pager cloudflared
fi