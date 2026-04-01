#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=/mnt/data/openresist/stream-server
JANUS_CONFIG_DIR="$DATA_ROOT/janus"
RENDER_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --render-only)
            RENDER_ONLY=true
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

get_compose_cmd() {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
        return
    fi

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
        return
    fi

    echo "ERROR: neither docker-compose nor docker compose is available" >&2
    exit 1
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

fetch_metered_turn_settings() {
    python3 - "$METERED_TURN_DOMAIN" "$METERED_TURN_API_KEY" <<'PY'
import json
import re
import shlex
import sys
import urllib.parse
import urllib.request

domain, api_key = sys.argv[1:3]
url = f"https://{domain}/api/v1/turn/credentials?apiKey={urllib.parse.quote(api_key, safe='')}"

try:
    with urllib.request.urlopen(url, timeout=10) as response:
        payload = json.load(response)
except Exception as exc:
    print(f"Metered TURN API request failed: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(payload, list):
    print("Metered TURN API returned a non-array payload", file=sys.stderr)
    raise SystemExit(1)

rankings = {
    ("turn", "udp"): 0,
    ("turn", "tcp"): 1,
    ("turns", "tls"): 2,
    ("turns", "tcp"): 3,
    ("turn", ""): 4,
    ("turns", ""): 5,
}

best = None

for server in payload:
    if not isinstance(server, dict):
        continue
    urls = server.get("urls") or server.get("url") or server.get("uri") or []
    if isinstance(urls, str):
        urls = [urls]
    username = server.get("username")
    credential = server.get("credential")
    if not username or not credential:
        continue

    for candidate in urls:
        if not isinstance(candidate, str):
            continue
        match = re.match(r'^(turns?):([^:?]+)(?::(\d+))?(?:\?transport=([a-z]+))?$', candidate)
        if not match:
            continue

        scheme, host, port, transport = match.groups()
        if scheme == "turns" and not transport:
            transport = "tls"
        elif not transport:
            transport = "udp"

        score = rankings.get((scheme, transport), 99)
        item = {
            "score": score,
            "server": host,
            "port": port or ("443" if scheme == "turns" else "3478"),
            "type": transport,
            "user": username,
            "pwd": credential,
        }
        if best is None or item["score"] < best["score"]:
            best = item

if best is None:
    print("Metered TURN API returned no usable TURN credentials", file=sys.stderr)
    raise SystemExit(1)

for key, value in {
    "JANUS_TURN_SERVER": best["server"],
    "JANUS_TURN_PORT": best["port"],
    "JANUS_TURN_TYPE": best["type"],
    "JANUS_TURN_USER": best["user"],
    "JANUS_TURN_PWD": best["pwd"],
}.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

render_template() {
    local template_file=$1
    local target_file=$2
    local content
    local janus_stun_block=''
    local janus_public_ip_block=''
    local janus_keep_private_host_block=''
    local janus_turn_block=''
    local janus_room_secret_block=''
    local janus_room_pin_block=''
    local janus_room_audiocodec_block=''
    local janus_room_videocodec_block=''

    content=$(<"$template_file")

    if [[ -n "${JANUS_STUN_SERVER:-}" ]]; then
        janus_stun_block=$'        stun_server = "'"$JANUS_STUN_SERVER"$'"\n'
        janus_stun_block+=$'        stun_port = '"$JANUS_STUN_PORT"$'\n'
    fi

    if [[ -n "${JANUS_PUBLIC_IP:-}" ]]; then
        janus_public_ip_block=$'        nat_1_1_mapping = "'"$JANUS_PUBLIC_IP"$'"\n'
    fi

    if [[ "${JANUS_KEEP_PRIVATE_HOST:-false}" == "true" ]]; then
        janus_keep_private_host_block=$'        keep_private_host = true\n'
    fi

    if [[ -n "${JANUS_TURN_SERVER:-}" && -n "${JANUS_TURN_USER:-}" && -n "${JANUS_TURN_PWD:-}" ]]; then
        janus_turn_block=$'        turn_server = "'"$JANUS_TURN_SERVER"$'"\n'
        janus_turn_block+=$'        turn_port = '"$JANUS_TURN_PORT"$'\n'
        janus_turn_block+=$'        turn_type = "'"$JANUS_TURN_TYPE"$'"\n'
        janus_turn_block+=$'        turn_user = "'"$JANUS_TURN_USER"$'"\n'
        janus_turn_block+=$'        turn_pwd = "'"$JANUS_TURN_PWD"$'"\n'
    fi

    if [[ -n "${JANUS_ROOM_SECRET:-}" ]]; then
        janus_room_secret_block=$'        secret = "'"$JANUS_ROOM_SECRET"$'"\n'
    fi

    if [[ -n "${JANUS_ROOM_PIN:-}" ]]; then
        janus_room_pin_block=$'        pin = "'"$JANUS_ROOM_PIN"$'"\n'
    fi

    if [[ -n "${JANUS_ROOM_AUDIOCODEC:-}" ]]; then
        janus_room_audiocodec_block=$'        audiocodec = "'"$JANUS_ROOM_AUDIOCODEC"$'"\n'
    fi

    if [[ -n "${JANUS_ROOM_VIDEOCODEC:-}" ]]; then
        janus_room_videocodec_block=$'        videocodec = "'"$JANUS_ROOM_VIDEOCODEC"$'"\n'
    fi

    content=${content//__JANUS_ADMIN_SECRET__/$(escape_sed_replacement "$JANUS_ADMIN_SECRET")}
    content=${content//__JANUS_RTP_PORT_RANGE__/$(escape_sed_replacement "$JANUS_RTP_PORT_RANGE")}
    content=${content//__JANUS_ROOM_ID__/$(escape_sed_replacement "$WHIP_ROOM_ID")}
    content=${content//__JANUS_ROOM_DESCRIPTION__/$(escape_sed_replacement "$JANUS_ROOM_DESCRIPTION")}
    content=${content//__JANUS_ROOM_PUBLISHERS__/$(escape_sed_replacement "$JANUS_ROOM_PUBLISHERS")}
    content=${content//__JANUS_ROOM_BITRATE__/$(escape_sed_replacement "$JANUS_ROOM_BITRATE")}
    content=${content//__JANUS_ROOM_BITRATE_CAP__/$(escape_sed_replacement "$JANUS_ROOM_BITRATE_CAP")}
    content=${content//__JANUS_STUN_BLOCK__/$janus_stun_block}
    content=${content//__JANUS_PUBLIC_IP_BLOCK__/$janus_public_ip_block}
    content=${content//__JANUS_KEEP_PRIVATE_HOST_BLOCK__/$janus_keep_private_host_block}
    content=${content//__JANUS_TURN_BLOCK__/$janus_turn_block}
    content=${content//__JANUS_ROOM_SECRET_BLOCK__/$janus_room_secret_block}
    content=${content//__JANUS_ROOM_PIN_BLOCK__/$janus_room_pin_block}
    content=${content//__JANUS_ROOM_AUDIOCODEC_BLOCK__/$janus_room_audiocodec_block}
    content=${content//__JANUS_ROOM_VIDEOCODEC_BLOCK__/$janus_room_videocodec_block}

    printf '%s\n' "$content" > "$target_file"
}

if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
fi

WHIP_PORT=${WHIP_PORT:-7080}
WHIP_BASE_PATH=${WHIP_BASE_PATH:-/whip}
WHIP_ENDPOINT_ID=${WHIP_ENDPOINT_ID:-live}
WHIP_ROOM_ID=${WHIP_ROOM_ID:-1234}
WHIP_ENDPOINT_LABEL=${WHIP_ENDPOINT_LABEL:-OpenResist Live}
JANUS_ROOM_DESCRIPTION=${JANUS_ROOM_DESCRIPTION:-OpenResist Live Room}
JANUS_ROOM_PUBLISHERS=${JANUS_ROOM_PUBLISHERS:-6}
JANUS_ROOM_AUDIOCODEC=${JANUS_ROOM_AUDIOCODEC:-opus}
JANUS_ROOM_VIDEOCODEC=${JANUS_ROOM_VIDEOCODEC:-h264,vp8}
JANUS_ROOM_BITRATE=${JANUS_ROOM_BITRATE:-500000}
JANUS_ROOM_BITRATE_CAP=${JANUS_ROOM_BITRATE_CAP:-true}
JANUS_ADMIN_SECRET=${JANUS_ADMIN_SECRET:-change-this-admin-secret}
JANUS_RTP_PORT_RANGE=${JANUS_RTP_PORT_RANGE:-20000-20100}
JANUS_STUN_PORT=${JANUS_STUN_PORT:-3478}
JANUS_TURN_PORT=${JANUS_TURN_PORT:-3478}
JANUS_TURN_TYPE=${JANUS_TURN_TYPE:-udp}

if [[ -n "${METERED_TURN_DOMAIN:-}" && -n "${METERED_TURN_API_KEY:-}" ]]; then
    if metered_turn_settings=$(fetch_metered_turn_settings 2>&1); then
        eval "$metered_turn_settings"
    else
        echo "WARNING: $metered_turn_settings" >&2
    fi
fi

COMPOSE_CMD=$(get_compose_cmd)

if [[ ! -d /mnt/data ]]; then
    echo "ERROR: /mnt/data does not exist" >&2
    exit 1
fi

mkdir -p "$JANUS_CONFIG_DIR"

render_template "$PROJECT_DIR/config/janus/janus.jcfg.template" "$JANUS_CONFIG_DIR/janus.jcfg"
render_template "$PROJECT_DIR/config/janus/janus.transport.websockets.jcfg.template" "$JANUS_CONFIG_DIR/janus.transport.websockets.jcfg"
render_template "$PROJECT_DIR/config/janus/janus.plugin.videoroom.jcfg.template" "$JANUS_CONFIG_DIR/janus.plugin.videoroom.jcfg"

if [[ -z "${JANUS_PUBLIC_IP:-}" && -z "${JANUS_STUN_SERVER:-}" ]]; then
    echo "WARNING: neither JANUS_PUBLIC_IP nor JANUS_STUN_SERVER is set; Janus may advertise unusable ICE candidates" >&2
fi

cd "$PROJECT_DIR"
if [[ "$RENDER_ONLY" == "true" ]]; then
    echo "Rendered Janus config into $JANUS_CONFIG_DIR"
    exit 0
fi

$COMPOSE_CMD pull janus
$COMPOSE_CMD build stream-server
$COMPOSE_CMD up -d janus stream-server

echo "Stream server is starting on 127.0.0.1:${WHIP_PORT}"
echo "WHIP endpoint: http://127.0.0.1:${WHIP_PORT}${WHIP_BASE_PATH}/endpoint/${WHIP_ENDPOINT_ID}"
echo "Janus RTP port range: ${JANUS_RTP_PORT_RANGE}/udp"
echo "Persistent data root: $DATA_ROOT"