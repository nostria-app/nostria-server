#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

"$SCRIPT_DIR/full-sync.sh" eu
"$SCRIPT_DIR/full-sync.sh" us
"$SCRIPT_DIR/start-live-sync.sh"

echo "Cutover sync completed initial EU and US catch-up and started live sync loops."