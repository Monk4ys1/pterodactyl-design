#!/usr/bin/env bash
# =============================================================================
#  Nebula · Ein-Befehl-Installer fuer das Pterodactyl Panel
#
#  Installation:
#    bash <(curl -fsSL https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/main/install.sh)
#
#  Weitere Befehle:
#    ./install.sh --update      Theme aktualisieren
#    ./install.sh --uninstall   Theme vollstaendig entfernen
#    ./install.sh --doctor      Installation pruefen
#    ./install.sh --status      Aktuellen Zustand anzeigen
#    ./install.sh --restore     Letztes Backup zuruecksicheren
#
#  Optionen:
#    --path <verzeichnis>   Pfad zum Panel (Standard: automatisch erkannt)
#    --branch <name>        Git-Branch der Quelle
#    --yes                  Keine Rueckfragen
#    --no-backup            Kein Backup anlegen (nicht empfohlen)
#    --no-cli               Den Befehl "nebula" nicht installieren
#    --no-admin             Adminbereich unveraendert lassen
#    --dry-run              Nur anzeigen, nichts schreiben
# =============================================================================
set -euo pipefail

REPO="Monk4ys1/pterodactyl-design"
THEME_SLUG="nebula"
THEME_NAME="Nebula"
DEFAULT_BRANCH="main"
FALLBACK_BRANCHES=("main" "master" "claude/pterodactyl-design-features-w3r8mz")
LIB_DIR="/usr/local/lib/nebula-theme"
CLI_PATH="/usr/local/bin/nebula"
BACKUP_ROOT="/var/backups/nebula"
STATE_FILE=".nebula-install.json"

usage() {
    cat <<'HELP'
Nebula – Design- und Feature-Paket fuer das Pterodactyl Panel

Installation
  bash <(curl -fsSL https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/main/install.sh)

Befehle
  --install            Theme installieren (Standard)
  --update, -u         Theme aktualisieren
  --uninstall          Theme vollstaendig entfernen
  --doctor             Installation pruefen
  --status             Aktuellen Zustand anzeigen
  --restore            Letztes Backup zuruecksichern

Optionen
  --path <verzeichnis> Pfad zum Panel (Standard: automatisch erkannt)
  --branch <name>      Git-Branch der Quelle
  --yes, -y            Keine Rueckfragen stellen
  --no-backup          Kein Backup anlegen (nicht empfohlen)
  --no-cli             Den Befehl "nebula" nicht installieren
  --no-admin           Adminbereich unveraendert lassen
  --dry-run            Nur anzeigen, nichts schreiben
  --help, -h           Diese Hilfe
HELP
}

ACTION="install"
PANEL=""
BRANCH="${PTD_BRANCH:-$DEFAULT_BRANCH}"
ASSUME_YES=0
DO_BACKUP=1
DO_CLI=1
DO_ADMIN=1
DRY_RUN=0
SRC=""
SRC_TMP=""

# -----------------------------------------------------------------------------
# Ausgabe
# -----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
    C_OK=$'\033[38;5;42m'; C_WARN=$'\033[38;5;214m'; C_ERR=$'\033[38;5;203m'
    C_ACC=$'\033[38;5;141m'; C_ACC2=$'\033[38;5;80m'
else
    C_RESET=""; C_DIM=""; C_B=""; C_OK=""; C_WARN=""; C_ERR=""; C_ACC=""; C_ACC2=""
fi

say()   { printf '%s\n' "$*"; }
info()  { printf '  %s•%s %s\n' "$C_ACC" "$C_RESET" "$*"; }
ok()    { printf '  %s✔%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_WARN" "$C_RESET" "$*"; }
err()   { printf '  %s✘%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
step()  { printf '\n%s%s%s\n' "$C_B" "$*" "$C_RESET"; }
die()   { err "$*"; exit 1; }

banner() {
    printf '\n'
    printf '   %s███╗   ██╗███████╗██████╗ ██╗   ██╗██╗      █████╗%s\n'  "$C_ACC"  "$C_RESET"
    printf '   %s████╗  ██║██╔════╝██╔══██╗██║   ██║██║     ██╔══██╗%s\n' "$C_ACC"  "$C_RESET"
    printf '   %s██╔██╗ ██║█████╗  ██████╔╝██║   ██║██║     ███████║%s\n' "$C_ACC2" "$C_RESET"
    printf '   %s██║╚██╗██║██╔══╝  ██╔══██╗██║   ██║██║     ██╔══██║%s\n' "$C_ACC2" "$C_RESET"
    printf '   %s██║ ╚████║███████╗██████╔╝╚██████╔╝███████╗██║  ██║%s\n' "$C_ACC2" "$C_RESET"
    printf '   %s╚═╝  ╚═══╝╚══════╝╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝%s\n' "$C_ACC2" "$C_RESET"
    printf '   %sDesign & Feature-Paket fuer das Pterodactyl Panel%s\n\n' "$C_DIM" "$C_RESET"
}

confirm() {
    [ "$ASSUME_YES" = "1" ] && return 0
    [ -t 0 ] || return 0
    local answer
    printf '  %s?%s %s [J/n] ' "$C_ACC" "$C_RESET" "$1"
    read -r answer || return 0
    case "$answer" in [nN]*) return 1 ;; *) return 0 ;; esac
}

run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

# -----------------------------------------------------------------------------
# Argumente
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --install)    ACTION="install" ;;
        --update|-u)  ACTION="update" ;;
        --uninstall)  ACTION="uninstall" ;;
        --doctor)     ACTION="doctor" ;;
        --status)     ACTION="status" ;;
        --restore)    ACTION="restore" ;;
        --path)       PANEL="${2:-}"; shift ;;
        --path=*)     PANEL="${1#*=}" ;;
        --branch)     BRANCH="${2:-}"; shift ;;
        --branch=*)   BRANCH="${1#*=}" ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --no-backup)  DO_BACKUP=0 ;;
        --no-cli)     DO_CLI=0 ;;
        --no-admin)   DO_ADMIN=0 ;;
        --dry-run)    DRY_RUN=1 ;;
        --help|-h)    usage; exit 0 ;;
        *)            die "Unbekannte Option: $1  (--help fuer Hilfe)" ;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# Vorbedingungen
# -----------------------------------------------------------------------------
need_root() {
    [ "$(id -u)" = "0" ] || die "Bitte als root ausfuehren:  sudo bash $0 $*"
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Programm fehlt: $1"
}

# -----------------------------------------------------------------------------
# Quelle bereitstellen (lokal oder von GitHub)
# -----------------------------------------------------------------------------
resolve_source() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

    if [ -n "$here" ] && [ -d "$here/theme/css" ] && [ -f "$here/scripts/build.sh" ]; then
        SRC="$here"
        info "Quelle: lokales Verzeichnis ${C_DIM}$SRC${C_RESET}"
        return
    fi

    need_tool curl
    need_tool tar

    SRC_TMP="$(mktemp -d)"
    trap 'rm -rf "$SRC_TMP"' EXIT

    local branches=("$BRANCH")
    local b
    for b in "${FALLBACK_BRANCHES[@]}"; do
        [ "$b" = "$BRANCH" ] || branches+=("$b")
    done

    for b in "${branches[@]}"; do
        info "Lade Quelle von GitHub (Branch: $b) …"
        if curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$b" \
            | tar -xz -C "$SRC_TMP" --strip-components=1 2>/dev/null; then
            if [ -d "$SRC_TMP/theme/css" ]; then
                SRC="$SRC_TMP"
                BRANCH="$b"
                ok "Quelle geladen (Branch: $b)"
                return
            fi
        fi
        rm -rf "${SRC_TMP:?}/"* 2>/dev/null || true
    done

    die "Quelle konnte nicht geladen werden. Netzwerk pruefen oder --path/--branch angeben."
}

# -----------------------------------------------------------------------------
# Panel finden und pruefen
# -----------------------------------------------------------------------------
is_panel() {
    local d="$1"
    [ -f "$d/artisan" ] || return 1
    [ -f "$d/config/app.php" ] || return 1
    [ -d "$d/resources/views" ] || return 1
    grep -qi 'pterodactyl' "$d/composer.json" 2>/dev/null || \
    grep -qi 'pterodactyl' "$d/config/app.php" 2>/dev/null || return 1
    return 0
}

detect_panel() {
    if [ -n "$PANEL" ]; then
        PANEL="${PANEL%/}"
        if ! is_panel "$PANEL"; then
            [ -f "$PANEL/artisan" ] && [ -d "$PANEL/resources/views" ] || \
                die "Unter '$PANEL' liegt kein Laravel-Panel (artisan/resources/views fehlen)."
            warn "'$PANEL' sieht nicht nach einem originalen Pterodactyl Panel aus – es wird trotzdem fortgefahren."
        fi
        return
    fi

    local c
    for c in /var/www/pterodactyl /var/www/panel /var/www/html/pterodactyl /var/www/html/panel /srv/pterodactyl; do
        if is_panel "$c"; then PANEL="$c"; return; fi
    done

    local found
    found="$(find /var/www /srv /opt -maxdepth 4 -name artisan -type f 2>/dev/null | head -n 20 || true)"
    local f d
    for f in $found; do
        d="$(dirname "$f")"
        if is_panel "$d"; then PANEL="$d"; return; fi
    done

    die "Panel nicht gefunden. Bitte mit --path /var/www/pterodactyl angeben."
}

panel_version() {
    sed -n "s/.*'version'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" "$PANEL/config/app.php" 2>/dev/null | head -n1
}

web_user() {
    local u
    u="$(stat -c '%U' "$PANEL/storage" 2>/dev/null || echo '')"
    if [ -z "$u" ] || [ "$u" = "root" ] || [ "$u" = "UNKNOWN" ]; then
        for u in www-data nginx apache pterodactyl; do
            id "$u" >/dev/null 2>&1 && { echo "$u"; return; }
        done
        echo "root"; return
    fi
    echo "$u"
}

web_group() {
    local u g
    u="$(web_user)"
    g="$(stat -c '%G' "$PANEL/storage" 2>/dev/null || echo '')"
    if [ -n "$g" ] && [ "$g" != "UNKNOWN" ] && [ "$g" != "root" ]; then
        echo "$g"; return
    fi
    id -gn "$u" 2>/dev/null || echo "$u"
}

php_bin() {
    command -v php >/dev/null 2>&1 && { echo php; return; }
    for p in /usr/bin/php8.3 /usr/bin/php8.2 /usr/bin/php8.1 /usr/bin/php; do
        [ -x "$p" ] && { echo "$p"; return; }
    done
    echo ""
}

WRAPPER_REL="resources/views/templates/wrapper.blade.php"
ADMIN_REL="resources/views/layouts/admin.blade.php"

# -----------------------------------------------------------------------------
# Blade-Injektion
# -----------------------------------------------------------------------------
strip_block() {
    # $1 = Datei
    local file="$1" tmp
    [ -f "$file" ] || return 0
    grep -q 'NEBULA:START' "$file" || return 0
    tmp="$(mktemp)"
    sed '/{{-- NEBULA:START --}}/,/{{-- NEBULA:END --}}/d' "$file" > "$tmp"
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s Block aus %s entfernen\n' "$C_DIM" "$C_RESET" "$file"
        rm -f "$tmp"
        return 0
    fi
    cat "$tmp" > "$file"          # erhaelt Besitzer, Rechte und SELinux-Kontext
    rm -f "$tmp"
}

inject_block() {
    # $1 = Datei, $2 = Snippet-Datei
    local file="$1" snippet="$2" tmp
    [ -f "$file" ] || { warn "Datei fehlt, uebersprungen: $file"; return 0; }

    strip_block "$file"

    if ! grep -qi '</head>' "$file"; then
        warn "Kein </head> in $file gefunden – uebersprungen."
        return 0
    fi

    tmp="$(mktemp)"
    awk -v snip="$snippet" '
        BEGIN { done = 0 }
        {
            if (!done && tolower($0) ~ /<\/head>/) {
                while ((getline line < snip) > 0) print line
                close(snip)
                done = 1
            }
            print
        }
    ' "$file" > "$tmp"

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s Block in %s einfuegen\n' "$C_DIM" "$C_RESET" "$file"
        rm -f "$tmp"
        return 0
    fi

    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# Backup
# -----------------------------------------------------------------------------
make_backup() {
    [ "$DO_BACKUP" = "1" ] || { warn "Backup uebersprungen (--no-backup)."; return 0; }
    local stamp archive
    stamp="$(date +%Y%m%d-%H%M%S)"
    archive="$BACKUP_ROOT/$stamp.tar.gz"

    run mkdir -p "$BACKUP_ROOT"

    local files=()
    [ -f "$PANEL/$WRAPPER_REL" ] && files+=("$WRAPPER_REL")
    [ -f "$PANEL/$ADMIN_REL" ] && files+=("$ADMIN_REL")
    [ -d "$PANEL/public/themes/$THEME_SLUG" ] && files+=("public/themes/$THEME_SLUG")

    if [ "${#files[@]}" -eq 0 ]; then
        warn "Nichts zu sichern."
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s Backup nach %s\n' "$C_DIM" "$C_RESET" "$archive"
        return 0
    fi

    tar czf "$archive" -C "$PANEL" "${files[@]}" 2>/dev/null
    chmod 600 "$archive"
    ok "Backup: $archive"
    echo "$archive" > "$BACKUP_ROOT/latest"
}

restore_backup() {
    local archive="${1:-}"
    if [ -z "$archive" ]; then
        [ -f "$BACKUP_ROOT/latest" ] || die "Kein Backup gefunden unter $BACKUP_ROOT."
        archive="$(cat "$BACKUP_ROOT/latest")"
    fi
    [ -f "$archive" ] || die "Backup nicht vorhanden: $archive"
    confirm "Backup '$archive' nach $PANEL zuruecksichern?" || { info "Abgebrochen."; return 0; }
    run tar xzf "$archive" -C "$PANEL"
    clear_views
    ok "Backup zurueckgesichert."
}

# -----------------------------------------------------------------------------
# Laravel-Cache
# -----------------------------------------------------------------------------
clear_views() {
    local php user
    php="$(php_bin)"
    [ -n "$php" ] || { warn "PHP nicht gefunden – bitte 'php artisan view:clear' selbst ausfuehren."; return 0; }
    user="$(web_user)"
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s php artisan view:clear\n' "$C_DIM" "$C_RESET"
        return 0
    fi
    if [ "$user" != "root" ] && command -v runuser >/dev/null 2>&1; then
        runuser -u "$user" -- "$php" "$PANEL/artisan" view:clear >/dev/null 2>&1 || \
            (cd "$PANEL" && "$php" artisan view:clear >/dev/null 2>&1) || true
    else
        (cd "$PANEL" && "$php" artisan view:clear >/dev/null 2>&1) || true
    fi
    ok "View-Cache geleert."
}

# -----------------------------------------------------------------------------
# Zustandsdatei
# -----------------------------------------------------------------------------
write_state() {
    local asset="$1"
    [ "$DRY_RUN" = "1" ] && return 0
    cat > "$PANEL/$STATE_FILE" <<JSON
{
  "theme": "$THEME_NAME",
  "slug": "$THEME_SLUG",
  "version": "$(cat "$SRC/VERSION" 2>/dev/null | tr -d ' \n\r')",
  "asset_version": "$asset",
  "branch": "$BRANCH",
  "installed_at": "$(date -Iseconds)",
  "panel_version": "$(panel_version)",
  "files": ["$WRAPPER_REL", "$ADMIN_REL", "public/themes/$THEME_SLUG"]
}
JSON
    chmod 640 "$PANEL/$STATE_FILE" 2>/dev/null || true
}

read_state() {
    [ -f "$PANEL/$STATE_FILE" ] || return 1
    sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$PANEL/$STATE_FILE" | head -n1
}

# -----------------------------------------------------------------------------
# CLI-Helfer
# -----------------------------------------------------------------------------
install_cli() {
    [ "$DO_CLI" = "1" ] || return 0
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s CLI nach %s installieren\n' "$C_DIM" "$C_RESET" "$CLI_PATH"
        return 0
    fi
    rm -rf "$LIB_DIR"
    mkdir -p "$LIB_DIR"
    cp -r "$SRC/theme" "$SRC/scripts" "$SRC/install.sh" "$SRC/VERSION" "$SRC/theme.json" "$LIB_DIR/" 2>/dev/null || true
    chmod +x "$LIB_DIR/install.sh" "$LIB_DIR/scripts/"*.sh 2>/dev/null || true

    cat > "$CLI_PATH" <<CLI
#!/usr/bin/env bash
# Nebula Theme – Verwaltungsbefehl
set -euo pipefail
LIB="$LIB_DIR"
PANEL_ARG=(--path "$PANEL")
case "\${1:-help}" in
    install)   shift; exec bash "\$LIB/install.sh" --install   "\${PANEL_ARG[@]}" "\$@" ;;
    update)    shift; exec bash "\$LIB/install.sh" --update    "\${PANEL_ARG[@]}" "\$@" ;;
    uninstall) shift; exec bash "\$LIB/install.sh" --uninstall "\${PANEL_ARG[@]}" "\$@" ;;
    doctor)    shift; exec bash "\$LIB/install.sh" --doctor    "\${PANEL_ARG[@]}" "\$@" ;;
    status)    shift; exec bash "\$LIB/install.sh" --status    "\${PANEL_ARG[@]}" "\$@" ;;
    restore)   shift; exec bash "\$LIB/install.sh" --restore   "\${PANEL_ARG[@]}" "\$@" ;;
    *)
        echo "Nebula Theme"
        echo "  nebula update      Theme aktualisieren"
        echo "  nebula uninstall   Theme entfernen"
        echo "  nebula doctor      Installation pruefen"
        echo "  nebula status      Zustand anzeigen"
        echo "  nebula restore     Letztes Backup zuruecksichern"
        ;;
esac
CLI
    chmod +x "$CLI_PATH"
    ok "Befehl installiert: ${C_B}nebula${C_RESET}"
}

# -----------------------------------------------------------------------------
# Installation
# -----------------------------------------------------------------------------
do_install() {
    step "1/6  Panel pruefen"
    local pv
    pv="$(panel_version)"
    info "Pfad:    $PANEL"
    info "Version: ${pv:-unbekannt}"
    info "Web-User: $(web_user):$(web_group)"

    case "$pv" in
        1.11.*|1.10.*) ok "Version wird unterstuetzt." ;;
        1.*)           warn "Version $pv ist nicht getestet – Installation ist reversibel." ;;
        "")            warn "Version nicht lesbar – es wird trotzdem fortgefahren." ;;
        *)             warn "Unerwartete Version '$pv'. Bei Problemen: nebula uninstall" ;;
    esac

    [ -f "$PANEL/$WRAPPER_REL" ] || die "Erwartete Datei fehlt: $PANEL/$WRAPPER_REL"

    if grep -q 'NEBULA:START' "$PANEL/$WRAPPER_REL" 2>/dev/null; then
        info "Bestehende Installation gefunden – wird ersetzt."
    fi

    confirm "Nebula in '$PANEL' installieren?" || { info "Abgebrochen."; exit 0; }

    step "2/6  Backup anlegen"
    make_backup

    step "3/6  Theme bauen"
    local build_dir asset
    build_dir="$(mktemp -d)"
    bash "$SRC/scripts/build.sh" "$build_dir" >/dev/null
    asset="$(cat "$build_dir/ASSET_VERSION")"
    ok "Bundles erstellt (Asset-Version $asset)"

    step "4/6  Dateien kopieren"
    local target="$PANEL/public/themes/$THEME_SLUG"
    run rm -rf "$target"
    run mkdir -p "$target"
    if [ "$DRY_RUN" != "1" ]; then
        cp "$build_dir"/nebula*.css "$build_dir"/nebula*.js "$build_dir/theme.json" "$target/"
        cp "$build_dir/ASSET_VERSION" "$target/ASSET_VERSION"
        chown -R "$(web_user)":"$(web_group)" "$target"
        find "$target" -type f -exec chmod 644 {} +
        chmod 755 "$target"
    fi
    ok "Assets unter public/themes/$THEME_SLUG"

    step "5/6  Views anpassen"
    local snip_client snip_admin
    snip_client="$(mktemp)"; snip_admin="$(mktemp)"
    sed "s/__ASSET_VERSION__/$asset/g" "$SRC/theme/blade/head.blade.php"       > "$snip_client"
    sed "s/__ASSET_VERSION__/$asset/g" "$SRC/theme/blade/admin-head.blade.php" > "$snip_admin"

    inject_block "$PANEL/$WRAPPER_REL" "$snip_client"
    ok "Client-Oberflaeche: $WRAPPER_REL"

    if [ "$DO_ADMIN" = "1" ] && [ -f "$PANEL/$ADMIN_REL" ]; then
        inject_block "$PANEL/$ADMIN_REL" "$snip_admin"
        ok "Adminbereich: $ADMIN_REL"
    else
        info "Adminbereich unveraendert."
    fi
    rm -f "$snip_client" "$snip_admin"

    step "6/6  Abschluss"
    clear_views
    write_state "$asset"
    install_cli
    rm -rf "$build_dir"

    printf '\n  %s%s ist aktiv.%s\n\n' "$C_OK$C_B" "$THEME_NAME" "$C_RESET"
    printf '  %sStrg + K%s   Command-Palette (Server suchen, Aktionen)\n' "$C_B" "$C_RESET"
    printf '  %sStrg + /%s   Tastenkuerzel-Uebersicht\n' "$C_B" "$C_RESET"
    printf '  %sZahnrad%s    Unten rechts: Farben, Layout, Funktionen\n' "$C_B" "$C_RESET"
    printf '\n  %sBrowser-Cache leeren bzw. mit Strg+F5 neu laden.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sEntfernen jederzeit mit:%s nebula uninstall\n\n' "$C_DIM" "$C_RESET"
}

# -----------------------------------------------------------------------------
# Deinstallation
# -----------------------------------------------------------------------------
do_uninstall() {
    step "Nebula entfernen"
    info "Panel: $PANEL"
    confirm "Theme aus '$PANEL' entfernen?" || { info "Abgebrochen."; exit 0; }

    strip_block "$PANEL/$WRAPPER_REL"
    [ "$DRY_RUN" = "1" ] || ok "Block aus $WRAPPER_REL entfernt."
    if [ -f "$PANEL/$ADMIN_REL" ]; then
        strip_block "$PANEL/$ADMIN_REL"
        [ "$DRY_RUN" = "1" ] || ok "Block aus $ADMIN_REL entfernt."
    fi

    run rm -rf "$PANEL/public/themes/$THEME_SLUG"
    run rm -f "$PANEL/$STATE_FILE"
    [ "$DRY_RUN" = "1" ] || ok "Assets entfernt."

    clear_views

    if [ "$DRY_RUN" != "1" ]; then
        rm -f "$CLI_PATH"
        rm -rf "$LIB_DIR"
    fi

    printf '\n  %sDas Panel ist wieder im Originalzustand.%s\n' "$C_OK" "$C_RESET"
    printf '  %sBackups bleiben unter %s erhalten.%s\n\n' "$C_DIM" "$BACKUP_ROOT" "$C_RESET"
}

# -----------------------------------------------------------------------------
# Diagnose
# -----------------------------------------------------------------------------
do_doctor() {
    step "Diagnose"
    local fails=0

    check() {
        if eval "$2" >/dev/null 2>&1; then ok "$1"; else err "$1"; fails=$((fails + 1)); fi
    }

    check "Panel gefunden ($PANEL)"                 "is_panel '$PANEL'"
    check "wrapper.blade.php vorhanden"             "[ -f '$PANEL/$WRAPPER_REL' ]"
    check "Nebula im Client-Template eingebunden"   "grep -q 'NEBULA:START' '$PANEL/$WRAPPER_REL'"
    check "Asset-Verzeichnis vorhanden"             "[ -d '$PANEL/public/themes/$THEME_SLUG' ]"
    check "nebula.css vorhanden"                    "[ -s '$PANEL/public/themes/$THEME_SLUG/nebula.css' ]"
    check "nebula.js vorhanden"                     "[ -s '$PANEL/public/themes/$THEME_SLUG/nebula.js' ]"
    check "Assets fuer Webserver lesbar"            "[ -r '$PANEL/public/themes/$THEME_SLUG/nebula.css' ]"
    check "PHP verfuegbar"                          "[ -n \"\$(php_bin)\" ]"

    if [ -f "$PANEL/$ADMIN_REL" ]; then
        if grep -q 'NEBULA:START' "$PANEL/$ADMIN_REL"; then
            ok "Nebula im Admin-Template eingebunden"
        else
            warn "Adminbereich nicht eingebunden (mit --no-admin installiert?)"
        fi
    fi

    local pv iv
    pv="$(panel_version)"; iv="$(read_state panel_version || true)"
    if [ -n "$iv" ] && [ -n "$pv" ] && [ "$pv" != "$iv" ]; then
        warn "Panel wurde seit der Installation aktualisiert ($iv → $pv). Empfehlung: nebula update"
    fi

    printf '\n'
    if [ "$fails" -eq 0 ]; then
        printf '  %sAlles in Ordnung.%s\n\n' "$C_OK" "$C_RESET"
    else
        printf '  %s%d Pruefung(en) fehlgeschlagen.%s  Reparatur: nebula update\n\n' "$C_ERR" "$fails" "$C_RESET"
        exit 1
    fi
}

do_status() {
    step "Zustand"
    info "Panel:          $PANEL"
    info "Panel-Version:  $(panel_version)"
    if [ -f "$PANEL/$STATE_FILE" ]; then
        info "Theme-Version:  $(read_state version)"
        info "Asset-Version:  $(read_state asset_version)"
        info "Installiert am: $(read_state installed_at)"
        info "Branch:         $(read_state branch)"
    else
        warn "Nebula ist in diesem Panel nicht installiert."
    fi
    if [ -f "$BACKUP_ROOT/latest" ]; then
        info "Letztes Backup: $(cat "$BACKUP_ROOT/latest")"
    fi
    printf '\n'
}

# -----------------------------------------------------------------------------
# Ablauf
# -----------------------------------------------------------------------------
banner
need_root

case "$ACTION" in
    install|update)
        resolve_source
        detect_panel
        do_install
        ;;
    uninstall)
        detect_panel
        do_uninstall
        ;;
    doctor)
        detect_panel
        do_doctor
        ;;
    status)
        detect_panel
        do_status
        ;;
    restore)
        detect_panel
        restore_backup
        ;;
esac
