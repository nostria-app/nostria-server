#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

printf '[%s] [discovery.cutover] Starting EU sync\n' "$(date -Is)"
bash "$SCRIPT_DIR/sync-discovery-eu.sh"

printf '[%s] [discovery.cutover] Starting US sync\n' "$(date -Is)"
bash "$SCRIPT_DIR/sync-discovery-us.sh"

printf '[%s] [discovery.cutover] EU and US sync complete\n' "$(date -Is)"