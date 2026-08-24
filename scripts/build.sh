#!/usr/bin/env bash
# =============================================================================
# Nebula · build.sh
# Fasst die Quelldateien zu den auslieferbaren Bundles unter dist/ zusammen.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
VERSION="$(tr -d ' \n\r' < "$ROOT/VERSION")"

CLIENT_CSS=(00-tokens.css 10-base.css 20-shell.css 30-components.css 40-console.css
            50-auth.css 60-ptd-ui.css 70-charts.css 80-overview.css)
ADMIN_CSS=(00-tokens.css admin.css)
CLIENT_JS=(00-boot.js 10-core.js 20-tagger.js 25-rail.js 30-settings.js 40-palette.js
           50-console.js 60-stats.js 65-overview.js 70-notify.js 80-shortcuts.js
           85-tags.js 90-enhance.js)
ADMIN_JS=(00-boot.js 10-core.js 30-settings.js)

banner() {
    printf '/*! Nebula %s · %s · https://github.com/Monk4ys1/pterodactyl-design */\n' "$VERSION" "$1"
}

concat() {
    local kind="$1" dir="$2" out="$3"; shift 3
    banner "$kind" > "$out"
    local f
    for f in "$@"; do
        printf '\n/* ---- %s ---- */\n' "$f" >> "$out"
        cat "$dir/$f" >> "$out"
    done
    sed -i "s/__PTD_VERSION__/$VERSION/g" "$out"
}

mkdir -p "$OUT"
rm -f "$OUT"/nebula*.css "$OUT"/nebula*.js

concat "client stylesheet" "$ROOT/theme/css" "$OUT/nebula.css"       "${CLIENT_CSS[@]}"
concat "admin stylesheet"  "$ROOT/theme/css" "$OUT/nebula-admin.css" "${ADMIN_CSS[@]}"
concat "client bundle"     "$ROOT/theme/js"  "$OUT/nebula.js"        "${CLIENT_JS[@]}"
concat "admin bundle"      "$ROOT/theme/js"  "$OUT/nebula-admin.js"  "${ADMIN_JS[@]}"

cp "$ROOT/theme.json" "$OUT/theme.json"
sed -i "s/__PTD_VERSION__/$VERSION/g" "$OUT/theme.json" 2>/dev/null || true

# Fingerprint fuer die Cache-Invalidierung der eingebundenen Assets
if command -v sha256sum >/dev/null 2>&1; then
    HASH="$(cat "$OUT"/nebula.css "$OUT"/nebula.js "$OUT"/nebula-admin.css "$OUT"/nebula-admin.js | sha256sum | cut -c1-10)"
else
    HASH="$(cat "$OUT"/nebula.css "$OUT"/nebula.js | shasum -a 256 | cut -c1-10)"
fi
printf '%s-%s' "$VERSION" "$HASH" > "$OUT/ASSET_VERSION"

echo "Nebula $VERSION gebaut nach $OUT (Asset-Version $(cat "$OUT/ASSET_VERSION"))"
ls -lh "$OUT" | sed 's/^/  /'
