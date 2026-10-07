#!/usr/bin/env bash
# Bequemer Aufruf fuer die Deinstallation – reicht alles an install.sh weiter.
# Der Einzeiler laedt install.sh ohne Pruefsumme. Fuer einen festgenagelten Stand
# das Repository als root ausfuehren:
#   sudo bash ./install.sh --tag vX.Y.Z --checksum <sha256> --uninstall
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/install.sh" ]; then
    exec bash "$HERE/install.sh" --uninstall "$@"
fi
exec bash <(curl -fsSL --tlsv1.2 --proto '=https' --proto-redir '=https' "https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/HEAD/install.sh") --uninstall "$@"
