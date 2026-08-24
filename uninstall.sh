#!/usr/bin/env bash
# Bequemer Aufruf fuer die Deinstallation – reicht alles an install.sh weiter.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/install.sh" ]; then
    exec bash "$HERE/install.sh" --uninstall "$@"
fi
exec bash <(curl -fsSL "https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/main/install.sh") --uninstall "$@"
