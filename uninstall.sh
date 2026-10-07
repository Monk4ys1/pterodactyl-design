#!/usr/bin/env bash
# Bequemer Aufruf fuer die Deinstallation – reicht alles an install.sh weiter.
# --tag und --checksum werden abgelehnt, wenn install.sh neben diesem Skript
# liegt: aus einem Checkout wuerden sie sonst still ignoriert. Fuer einen
# festgenagelten Download den Einzeiler nutzen:
#   sudo bash <(curl -fsSL …/install.sh) --tag vX.Y.Z --checksum <sha256> --uninstall
# sudo entfernt PTD_SHA256. Das Flag --checksum bevorzugen,
# oder: sudo --preserve-env=PTD_SHA256
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/install.sh" ]; then
    exec bash "$HERE/install.sh" --uninstall "$@"
fi
exec bash <(curl -fsSL --tlsv1.2 --proto '=https' --proto-redir '=https' "https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/HEAD/install.sh") --uninstall "$@"
