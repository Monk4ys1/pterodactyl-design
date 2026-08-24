#!/usr/bin/env bash
# =============================================================================
# Nebula · tests/run.sh
# Baut die Bundles, startet einen Nachbau der Panel-Oberflaeche samt
# Wings-WebSocket und prueft das Theme in einem echten Chromium.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

command -v node >/dev/null 2>&1 || { echo "node wird benoetigt"; exit 1; }

echo "› Bundles bauen"
bash "$ROOT/scripts/build.sh" "$ROOT/dist" >/dev/null

cd "$HERE"
if [ ! -d node_modules ]; then
    echo "› Abhaengigkeiten installieren"
    npm install --silent
fi

echo "› Testserver starten"
node server.js > server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null http://127.0.0.1:8899/ 2>/dev/null; then break; fi
    sleep 0.3
done

echo "› Client-Oberflaeche pruefen"
node browser.test.js

echo "› Adminbereich pruefen"
node admin.test.js

echo "› Screenshots liegen unter tests/shots/"
