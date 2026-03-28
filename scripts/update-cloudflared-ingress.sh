#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=${CONFIG_FILE:-/etc/cloudflared/config.yml}
DEFAULT_HOSTNAME=indexer.openresist.com
TARGET_SERVICE=http://127.0.0.1:7777
RESTART_CLOUDFLARED=true
TARGET_HOSTNAMES=()

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/update-cloudflared-ingress.sh [options]

Options:
    --hostname <hostname>   Hostname to route through the tunnel; repeat to add multiple hostnames
  --service <url>         Local origin service URL
  --config <path>         cloudflared config file path
  --no-restart            Update the config but do not restart cloudflared
  --help                  Show this help

Examples:
    sudo ./scripts/update-cloudflared-ingress.sh
    sudo ./scripts/update-cloudflared-ingress.sh --hostname relay.openresist.com --hostname ribo.eu.nostria.app --hostname ribo.us.nostria.app --service http://127.0.0.1:7778
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            TARGET_HOSTNAMES+=("${2:?missing value for --hostname}")
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

if [[ ${#TARGET_HOSTNAMES[@]} -eq 0 ]]; then
    TARGET_HOSTNAMES=("$DEFAULT_HOSTNAME")
fi

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
HOSTNAME_FILE=$(mktemp)
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"

printf '%s\n' "${TARGET_HOSTNAMES[@]}" > "$HOSTNAME_FILE"

awk -v hostname_file="$HOSTNAME_FILE" -v target_service="$TARGET_SERVICE" '
BEGIN {
    in_ingress = 0
    skip_target = 0
    count = 0
    target_count = 0
    fallback = "  - service: http_status:404"

    while ((getline line < hostname_file) > 0) {
        if (line == "") {
            continue
        }

        if (!(line in target_hostnames)) {
            target_hostnames[line] = 1
            target_hostname_order[++target_count] = line
        }
    }

    close(hostname_file)
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

    if ($0 ~ /^  - hostname: /) {
        current_hostname = $0
        sub(/^  - hostname: /, "", current_hostname)

        if (current_hostname in target_hostnames) {
            skip_target = 1
            next
        }
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

    for (i = 1; i <= target_count; i++) {
        print "  - hostname: " target_hostname_order[i]
        print "    service: " target_service
    }

    print fallback
}
' "$CONFIG_FILE" > "$TMP_FILE"

cp "$CONFIG_FILE" "$BACKUP_FILE"
install -m 0644 "$TMP_FILE" "$CONFIG_FILE"
rm -f "$TMP_FILE"
rm -f "$HOSTNAME_FILE"

echo "Updated $CONFIG_FILE"
echo "Backup written to $BACKUP_FILE"
echo "Configured hostnames: ${TARGET_HOSTNAMES[*]}"

if [[ "$RESTART_CLOUDFLARED" == "true" ]]; then
    systemctl restart cloudflared
    systemctl status --no-pager cloudflared
fi