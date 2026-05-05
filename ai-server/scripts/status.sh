#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
export DOCKER_API_VERSION=${DOCKER_API_VERSION:-1.41}

get_compose_cmd() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
        return
    fi

    echo "ERROR: neither docker compose nor docker-compose is available" >&2
    exit 1
}

COMPOSE_CMD=$(get_compose_cmd)

cd "$PROJECT_DIR"
$COMPOSE_CMD ps
docker stats --no-stream --format 'name={{.Name}} mem={{.MemUsage}} cpu={{.CPUPerc}}' openresist-ai-server 2>/dev/null || true

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    . .env
    set +a
    port=${AI_SERVER_HOST_PORT:-8088}

    if command -v curl >/dev/null 2>&1; then
        echo
        curl -fsS "http://127.0.0.1:$port/health" || true
        echo
    fi
fi
