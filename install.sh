#!/usr/bin/env bash
# =============================================================================
#  Nebula · Ein-Befehl-Installer fuer das Pterodactyl Panel
#
#  Installation:
#    bash <(curl -fsSL https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/HEAD/install.sh)
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
#    --branch <name>        Git-Ref der Quelle (Branch, Tag oder Commit)
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
DEFAULT_BRANCH="HEAD"                     # HEAD = Standardbranch des Repositories
FALLBACK_BRANCHES=("HEAD" "main" "master")
LIB_DIR="/usr/local/lib/nebula-theme"
CLI_PATH="/usr/local/bin/nebula"
BACKUP_ROOT="/var/backups/nebula"
STATE_FILE=".nebula-install.json"

usage() {
    cat <<'HELP'
Nebula – Design- und Feature-Paket fuer das Pterodactyl Panel

Installation
  bash <(curl -fsSL https://raw.githubusercontent.com/Monk4ys1/pterodactyl-design/HEAD/install.sh)

Befehle
  --install            Theme installieren (Standard)
  --update, -u         Theme aktualisieren
  --uninstall          Theme vollstaendig entfernen
  --doctor             Installation pruefen
  --status             Aktuellen Zustand anzeigen
  --restore            Letztes Backup zuruecksichern

Optionen
  --path <verzeichnis> Pfad zum Panel (Standard: automatisch erkannt)
  --branch <name>      Git-Ref der Quelle (Branch, Tag oder Commit)
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
    if [ ! -t 0 ]; then
        die "Keine interaktive Konsole. Zum Fortfahren --yes setzen."
    fi
    local answer
    printf '  %s?%s %s [J/n] ' "$C_ACC" "$C_RESET" "$1"
    if ! read -r answer; then
        die "Eingabe abgebrochen."
    fi
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
# Eingaben, die in Shell, JSON, HTML oder Archive einfliessen
# -----------------------------------------------------------------------------
valid_ref() {
    local r="$1" part
    [ -n "$r" ] || return 1
    [ "${#r}" -le 160 ] || return 1
    [[ "$r" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    [[ "$r" == -* ]] && return 1
    local IFS=/
    for part in $r; do
        [ -n "$part" ] || return 1
        [ "$part" != "." ] || return 1
        [ "$part" != ".." ] || return 1
    done
    return 0
}

valid_asset() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# Ablehnen: 0. Erlaubt: 1. Absichtliche Umkehr, damit "&& return" lesbar bleibt.
member_rejected() {
    local m="$1"
    [ -n "$m" ] || return 0
    m="${m#./}"
    case "$m" in
        /*|*\\*) return 0 ;;
    esac
    case "/$m/" in
        *"/../"*|*"//"*) return 0 ;;
    esac
    return 1
}

archive_is_safe() {
    local archive="$1" line member n=0
    [ -f "$archive" ] && [ ! -L "$archive" ] || return 1

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$((n + 1))
        [ "$n" -le 500 ] || return 1
        case "$line" in
            -*|d*) ;;
            *) return 1 ;;
        esac
    done < <(tar -tvzf "$archive" 2>/dev/null) || return 1
    [ "$n" -ge 1 ] || return 1

    while IFS= read -r member; do
        if member_rejected "$member"; then
            return 1
        fi
    done < <(tar -tzf "$archive" 2>/dev/null) || return 1
    return 0
}

prepare_backup_root() {
    if [ -e "$BACKUP_ROOT" ] && [ ! -d "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist kein Verzeichnis: $BACKUP_ROOT"
    fi
    if [ -d "$BACKUP_ROOT" ]; then
        local owner
        owner="$(stat -c '%U' "$BACKUP_ROOT" 2>/dev/null || echo '')"
        [ "$owner" = "root" ] || die "Backup-Verzeichnis gehoert nicht root: $BACKUP_ROOT"
    fi
    mkdir -p "$BACKUP_ROOT"
    chown root:root "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"
}

harden_panel_path() {
    local real mode other d
    real="$(realpath -e "$PANEL" 2>/dev/null || true)"
    [ -n "$real" ] || die "Panel-Pfad nicht aufloesbar: $PANEL"
    [ "$real" != "/" ] || die "Panel-Pfad ungueltig."
    PANEL="$real"
    d="$PANEL"
    while [ "$d" != "/" ]; do
        mode="$(stat -c '%a' "$d" 2>/dev/null || echo 777)"
        other="${mode: -1}"
        case "$other" in
            2|3|6|7) die "Pfad ist fuer andere beschreibbar: $d" ;;
        esac
        d="$(dirname "$d")"
    done
    [ -f "$PANEL/artisan" ] && [ ! -L "$PANEL/artisan" ] || die "artisan fehlt oder ist ein Symlink."
    mode="$(stat -c '%a' "$PANEL/artisan")"
    other="${mode: -1}"
    case "$other" in
        2|3|6|7) die "artisan ist fuer andere beschreibbar." ;;
    esac
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

valid_ref "$BRANCH" || die "Ungueltige Git-Ref in --branch oder PTD_BRANCH."

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
    local tarball
    tarball="$(mktemp)"
    trap 'rm -rf "$SRC_TMP"; rm -f "$tarball"' EXIT

    local branches=("$BRANCH")
    local b
    for b in "${FALLBACK_BRANCHES[@]}"; do
        [ "$b" = "$BRANCH" ] || branches+=("$b")
    done

    local url
    for b in "${branches[@]}"; do
        valid_ref "$b" || continue
        info "Lade Quelle von GitHub (Ref: $b) …"
        # Erst als Branch, dann als beliebiger Ref (HEAD, Tag, Commit).
        for url in "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${b}" \
                   "https://codeload.github.com/${REPO}/tar.gz/${b}"; do
            rm -rf "${SRC_TMP:?}/"* 2>/dev/null || true
            rm -f "$tarball"
            if curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 2 --retry 2 --max-time 60 \
                -o "$tarball" "$url" \
                && archive_is_safe "$tarball" \
                && tar -xzf "$tarball" -C "$SRC_TMP" --strip-components=1 --no-same-owner --no-same-permissions \
                && [ -d "$SRC_TMP/theme/css" ] \
                && [ ! -L "$SRC_TMP/theme" ] \
                && [ ! -L "$SRC_TMP/scripts/build.sh" ] \
                && ! find "$SRC_TMP" -type l -print -quit | grep -q .; then
                SRC="$SRC_TMP"
                BRANCH="$b"
                ok "Quelle geladen (Ref: $b)"
                return
            fi
            rm -rf "${SRC_TMP:?}/"* 2>/dev/null || true
        done
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
        harden_panel_path
        return
    fi

    local c
    for c in /var/www/pterodactyl /var/www/panel /var/www/html/pterodactyl /var/www/html/panel /srv/pterodactyl; do
        if is_panel "$c"; then PANEL="$c"; harden_panel_path; return; fi
    done

    local f d
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        d="$(dirname "$f")"
        if is_panel "$d"; then PANEL="$d"; harden_panel_path; return; fi
    done < <(find /var/www /srv /opt -xdev -maxdepth 4 -name artisan -type f 2>/dev/null | head -n 20 || true)

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

    prepare_backup_root
    tar czf "$archive" -C "$PANEL" "${files[@]}" 2>/dev/null
    chmod 600 "$archive"
    chown root:root "$archive"
    printf '%s\n' "$archive" > "$BACKUP_ROOT/latest"
    chmod 600 "$BACKUP_ROOT/latest"
    ok "Backup: $archive"
}

restore_backup() {
    local archive root real owner
    prepare_backup_root
    [ -f "$BACKUP_ROOT/latest" ] || die "Kein Backup gefunden unter $BACKUP_ROOT."
    archive="$(head -n 1 "$BACKUP_ROOT/latest")"
    root="$(realpath -e "$BACKUP_ROOT")"
    real="$(realpath -e "$archive" 2>/dev/null || true)"
    [ -n "$real" ] && [ -f "$real" ] && [ ! -L "$real" ] || die "Backup nicht vorhanden: $archive"
    case "$real" in
        "$root"/*) ;;
        *) die "Backup liegt ausserhalb von $BACKUP_ROOT." ;;
    esac
    owner="$(stat -c '%U' "$real" 2>/dev/null || echo '')"
    [ "$owner" = "root" ] || die "Backup gehoert nicht root: $real"
    archive_is_safe "$real" || die "Backup-Archiv enthaelt unsichere Pfade oder Links."
    confirm "Backup '$real' nach $PANEL zuruecksichern?" || { info "Abgebrochen."; return 0; }
    if [ "$DRY_RUN" != "1" ]; then
        tar -xzf "$real" -C "$PANEL" --no-same-owner --no-same-permissions
    else
        printf '  %s[dry-run]%s tar -xzf %s -C %s\n' "$C_DIM" "$C_RESET" "$real" "$PANEL"
    fi
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
    if [ -L "$PANEL/artisan" ]; then
        warn "artisan ist ein Symlink – view:clear uebersprungen."
        return 0
    fi
    if [ "$user" = "root" ] || ! command -v runuser >/dev/null 2>&1; then
        warn "view:clear nicht als root ausgefuehrt. Bitte danach selbst 'php artisan view:clear' aufrufen."
        return 0
    fi
    if runuser -u "$user" -- "$php" "$PANEL/artisan" view:clear >/dev/null 2>&1; then
        ok "View-Cache geleert."
    else
        warn "view:clear als $user fehlgeschlagen. Bitte danach selbst ausfuehren."
    fi
}

# -----------------------------------------------------------------------------
# Zustandsdatei
# -----------------------------------------------------------------------------
write_state() {
    local asset="$1" ver branch pv now
    valid_asset "$asset" || die "Ungueltige Asset-Version."
    [ "$DRY_RUN" = "1" ] && return 0
    ver="$(tr -cd '0-9A-Za-z._-' < "$SRC/VERSION" 2>/dev/null | head -c 32 || true)"
    [ -n "$ver" ] || ver="unknown"
    branch="$(json_escape "$BRANCH")"
    pv="$(json_escape "$(panel_version || true)")"
    now="$(json_escape "$(date -Iseconds)")"
    cat > "$PANEL/$STATE_FILE" <<JSON
{
  "theme": "Nebula",
  "slug": "nebula",
  "version": "${ver}",
  "asset_version": "${asset}",
  "branch": "${branch}",
  "installed_at": "${now}",
  "panel_version": "${pv}",
  "files": ["resources/views/templates/wrapper.blade.php", "resources/views/layouts/admin.blade.php", "public/themes/nebula"]
}
JSON
    chmod 600 "$PANEL/$STATE_FILE" 2>/dev/null || true
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
    chmod 755 "$LIB_DIR"
    cp -r "$SRC/theme" "$SRC/scripts" "$SRC/install.sh" "$SRC/VERSION" "$SRC/theme.json" "$LIB_DIR/" 2>/dev/null || true
    chmod +x "$LIB_DIR/install.sh" "$LIB_DIR/scripts/"*.sh 2>/dev/null || true

    local qlib qpanel
    printf -v qlib '%q' "$LIB_DIR"
    printf -v qpanel '%q' "$PANEL"
    cat > "$CLI_PATH" <<CLI
#!/usr/bin/env bash
# Nebula Theme – Verwaltungsbefehl
set -euo pipefail
LIB=$qlib
PANEL_ARG=(--path $qpanel)
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
    valid_asset "$asset" || die "Ungueltige Asset-Version."
    snip_client="$(mktemp)"; snip_admin="$(mktemp)"
    sed "s|__ASSET_VERSION__|${asset}|g" "$SRC/theme/blade/head.blade.php"       > "$snip_client"
    sed "s|__ASSET_VERSION__|${asset}|g" "$SRC/theme/blade/admin-head.blade.php" > "$snip_admin"

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
    printf '  %sStrg + K%s          Befehlspalette – Server suchen, Aktionen ausloesen\n' "$C_B" "$C_RESET"
    printf '  %sStrg + B%s          Seitenschiene ein- und ausklappen\n' "$C_B" "$C_RESET"
    printf '  %sStrg + Umschalt+D%s Mini-Konsole (bleibt beim Reiterwechsel offen)\n' "$C_B" "$C_RESET"
    printf '  %sStrg + /%s          Alle Tastenkuerzel\n' "$C_B" "$C_RESET"
    printf '  %sZahnrad%s           Unten rechts: Farben, Layout, Module, Warnregeln\n' "$C_B" "$C_RESET"
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
        local label="$1"
        shift
        if "$@" >/dev/null 2>&1; then ok "$label"; else err "$label"; fails=$((fails + 1)); fi
    }

    check "Panel gefunden ($PANEL)"               is_panel "$PANEL"
    check "wrapper.blade.php vorhanden"           test -f "$PANEL/$WRAPPER_REL"
    check "Nebula im Client-Template eingebunden" grep -q NEBULA:START "$PANEL/$WRAPPER_REL"
    check "Asset-Verzeichnis vorhanden"           test -d "$PANEL/public/themes/$THEME_SLUG"
    check "nebula.css vorhanden"                  test -s "$PANEL/public/themes/$THEME_SLUG/nebula.css"
    check "nebula.js vorhanden"                   test -s "$PANEL/public/themes/$THEME_SLUG/nebula.js"
    check "Assets fuer Webserver lesbar"          test -r "$PANEL/public/themes/$THEME_SLUG/nebula.css"
    if [ -n "$(php_bin)" ]; then ok "PHP verfuegbar"; else err "PHP verfuegbar"; fails=$((fails + 1)); fi

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
if [ "${PTD_SELFTEST:-}" = "1" ]; then
    if [ "${BASH_SOURCE[0]}" != "$0" ]; then
        return 0
    fi
    exit 0
fi

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
