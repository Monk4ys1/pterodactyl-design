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
#    --branch <name>        Git-Ref der Quelle; kein Fallback auf andere Refs
#    --yes                  Keine Rueckfragen
#    --no-backup            Kein Backup anlegen (nicht empfohlen)
#    --no-cli               Den Befehl "nebula" nicht installieren
#    --no-admin             Adminbereich unveraendert lassen
#    --dry-run              Nur anzeigen, nichts schreiben
# =============================================================================
set -euo pipefail
umask 022

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
  --branch <name>      Git-Ref der Quelle; kein Fallback auf andere Refs
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
REF_EXPLICIT=0
BRANCH="$DEFAULT_BRANCH"
if [ -n "${PTD_BRANCH+x}" ]; then
    BRANCH="$PTD_BRANCH"
    REF_EXPLICIT=1
fi
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
    regular_file "$archive" || return 1

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
    regular_file "$PANEL/artisan" || die "artisan fehlt oder ist ein Symlink."
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
        --branch)     BRANCH="${2:-}"; REF_EXPLICIT=1; shift ;;
        --branch=*)   BRANCH="${1#*=}"; REF_EXPLICIT=1 ;;
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
    [ "$(id -u)" = "0" ] || die "Bitte als root ausfuehren:  sudo bash $0"
}

regular_file() {
    [ -f "$1" ] || return 1
    if [ -L "$1" ]; then
        return 1
    fi
    return 0
}

real_dir() {
    [ -d "$1" ] || return 1
    if [ -L "$1" ]; then
        return 1
    fi
    return 0
}

installer_dir() {
    local dir
    dir="$(dirname "${BASH_SOURCE[0]}")"
    if dir="$(cd "$dir" 2>/dev/null && pwd)"; then
        printf '%s' "$dir"
        return 0
    fi
    printf ''
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Programm fehlt: $1"
}

# Refs, die resolve_source versucht. Eine gesetzte Ref hat keinen Fallback.
source_ref_list() {
    local b
    printf '%s\n' "$BRANCH"
    [ "${REF_EXPLICIT:-0}" = "1" ] && return 0
    for b in "${FALLBACK_BRANCHES[@]}"; do
        [ "$b" = "$BRANCH" ] || printf '%s\n' "$b"
    done
}

# Installierte Kopie unter LIB_DIR ist keine Quelle: nebula update muss neu laden.
source_is_installed_lib() {
    local script_real here here_real lib_real
    script_real="$(realpath -e "${BASH_SOURCE[0]}" 2>/dev/null || true)"
    lib_real="$(realpath -e "$LIB_DIR" 2>/dev/null || true)"
    if [ -n "$script_real" ] && [ -n "$lib_real" ]; then
        case "$script_real" in
            "$lib_real"|"$lib_real"/*) return 0 ;;
        esac
    fi
    here="$(installer_dir)"
    here_real="$(realpath -e "$here" 2>/dev/null || true)"
    if [ -n "$here_real" ] && [ -n "$lib_real" ] && [ "$here_real" = "$lib_real" ]; then
        return 0
    fi
    if [ -n "$script_real" ]; then
        case "$script_real" in
            "$LIB_DIR"|"$LIB_DIR"/*) return 0 ;;
        esac
    fi
    return 1
}

cleanup_source() {
    if [ -n "${SRC_TMP:-}" ]; then
        rm -rf "$SRC_TMP"
        SRC_TMP=""
    fi
    if [ -n "${SRC_TARBALL:-}" ]; then
        rm -f "$SRC_TARBALL"
        SRC_TARBALL=""
    fi
}

# -----------------------------------------------------------------------------
# Quelle bereitstellen (lokal oder von GitHub)
# -----------------------------------------------------------------------------
resolve_source() {
    local here
    here="$(installer_dir)"

    if ! source_is_installed_lib \
        && [ -n "$here" ] \
        && [ -d "$here/theme/css" ] \
        && [ -f "$here/scripts/build.sh" ] \
        && [ ! -L "$here/theme" ] \
        && [ ! -L "$here/scripts/build.sh" ]; then
        SRC="$here"
        info "Quelle: lokales Verzeichnis ${C_DIM}$SRC${C_RESET}"
        return
    fi

    need_tool curl
    need_tool tar

    SRC_TMP="$(mktemp -d)"
    trap cleanup_source EXIT
    SRC_TARBALL="$(mktemp)"

    local branches=() b
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        branches+=("$b")
    done < <(source_ref_list)

    local url
    for b in "${branches[@]}"; do
        valid_ref "$b" || continue
        info "Lade Quelle von GitHub (Ref: $b) …"
        # Dieselbe Ref als Branch-URL und als Tag/Commit/HEAD. Keine andere Ref.
        for url in "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${b}" \
                   "https://codeload.github.com/${REPO}/tar.gz/${b}"; do
            rm -rf "${SRC_TMP:?}/"* 2>/dev/null || true
            rm -f "$SRC_TARBALL"
            if curl -fsSL --tlsv1.2 --proto '=https' --proto-redir '=https' --max-redirs 2 --retry 2 --max-time 60 \
                -o "$SRC_TARBALL" "$url" \
                && archive_is_safe "$SRC_TARBALL" \
                && tar -xzf "$SRC_TARBALL" -C "$SRC_TMP" --strip-components=1 --no-same-owner --no-same-permissions \
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

    if [ "${REF_EXPLICIT:-0}" = "1" ]; then
        die "Quelle fuer die angegebene Ref '$BRANCH' konnte nicht geladen werden. Kein Fallback."
    fi
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
            if [ ! -f "$PANEL/artisan" ] || [ ! -d "$PANEL/resources/views" ]; then
                die "Unter '$PANEL' liegt kein Laravel-Panel (artisan/resources/views fehlen)."
            fi
            warn "'$PANEL' sieht nicht nach einem originalen Pterodactyl Panel aus – es wird trotzdem fortgefahren."
        fi
        harden_panel_path
        return
    fi

    local c
    for c in /var/www/pterodactyl /var/www/panel /var/www/html/pterodactyl /var/www/html/panel /srv/pterodactyl; do
        if is_panel "$c"; then PANEL="$c"; harden_panel_path; return; fi
    done

    local f d n=0
    while IFS= read -r -d '' f; do
        n=$((n + 1))
        [ "$n" -le 20 ] || break
        [ -n "$f" ] || continue
        d="$(dirname "$f")"
        if is_panel "$d"; then PANEL="$d"; harden_panel_path; return; fi
    done < <(find /var/www /srv /opt -xdev -maxdepth 4 -name artisan -type f -print0 2>/dev/null || true)

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
THEME_REL="public/themes/$THEME_SLUG"

# Jede Komponente muss im Panel liegen und darf kein Symlink sein.
# Fehlende Endkomponenten sind erlaubt, vorhandene werden mit realpath geprueft.
path_is_confined() {
    local rel="$1" panel part rest cur real
    [ -n "${PANEL:-}" ] || return 1
    panel="$(realpath -e "$PANEL" 2>/dev/null || true)"
    [ -n "$panel" ] && [ "$panel" != "/" ] || return 1
    [ -n "$rel" ] || return 1
    case "$rel" in
        /*|*\\*) return 1 ;;
    esac
    rest="$rel"
    cur="$panel"
    while [ -n "$rest" ]; do
        part="${rest%%/*}"
        if [ "$part" = "$rest" ]; then
            rest=""
        else
            rest="${rest#*/}"
        fi
        [ -n "$part" ] || return 1
        [ "$part" != "." ] && [ "$part" != ".." ] || return 1
        cur="$cur/$part"
        if [ -L "$cur" ]; then
            return 1
        fi
        if [ ! -e "$cur" ]; then
            while [ -n "$rest" ]; do
                part="${rest%%/*}"
                if [ "$part" = "$rest" ]; then
                    rest=""
                else
                    rest="${rest#*/}"
                fi
                [ -n "$part" ] || return 1
                [ "$part" != "." ] && [ "$part" != ".." ] || return 1
            done
            real="$(realpath -e "$(dirname "$cur")" 2>/dev/null || true)"
            case "$real" in
                "$panel"|"$panel"/*) return 0 ;;
                *) return 1 ;;
            esac
        fi
    done
    real="$(realpath -e "$cur" 2>/dev/null || true)"
    case "$real" in
        "$panel"|"$panel"/*) return 0 ;;
        *) return 1 ;;
    esac
}

require_confined() {
    path_is_confined "$1" || die "Pfad verlaesst das Panel oder enthaelt einen Symlink: $1"
}

under_panel() {
    local real="$1" panel
    panel="$(realpath -e "$PANEL" 2>/dev/null || true)"
    if [ -z "$panel" ] || [ -z "$real" ]; then
        return 1
    fi
    case "$real" in
        "$panel"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Schreibt nur ueber eine neue Datei im bereits geprueften Verzeichnis und
# ersetzt den Zieleintrag per rename, ohne einen Symlink zu folgen.
safe_install_file() {
    local dest="$1" srcf="$2" rel dir tmp real parent_rel
    rel="${dest#"$PANEL"/}"
    [ "$dest" = "$PANEL/$rel" ] || die "Ziel ausserhalb des Panels."
    parent_rel="$(dirname "$rel")"
    [ "$parent_rel" != "." ] || parent_rel=""
    if [ -n "$parent_rel" ]; then
        require_confined "$parent_rel"
    fi
    if [ -L "$dest" ]; then
        die "Ziel ist ein Symlink: $rel"
    fi
    if [ -e "$dest" ] && [ ! -f "$dest" ]; then
        die "Ziel ist keine regulaere Datei: $rel"
    fi
    if [ -e "$dest" ]; then
        require_confined "$rel"
    fi
    dir="$(dirname "$dest")"
    real_dir "$dir" || die "Zielverzeichnis fehlt oder ist ein Symlink: ${parent_rel:-.}"
    tmp="$(mktemp "$dir/.nebula.XXXXXX")"
    real="$(realpath -e "$tmp" 2>/dev/null || true)"
    if ! under_panel "$real"; then
        rm -f "$tmp"
        die "Temporaere Datei liegt ausserhalb des Panels."
    fi
    if ! cp "$srcf" "$tmp"; then
        rm -f "$tmp"
        die "Kopieren fehlgeschlagen: $rel"
    fi
    local mode="${3:-644}"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || { rm -f "$tmp"; die "Ungueltiger Dateimodus."; }
    chmod "$mode" "$tmp"
    if [ -L "$dir" ] || [ -L "$dest" ]; then
        rm -f "$tmp"
        die "Zielpfad wurde waehrend des Schreibens zu einem Symlink: $rel"
    fi
    if ! mv -T "$tmp" "$dest"; then
        rm -f "$tmp"
        die "Schreiben fehlgeschlagen: $rel"
    fi
    regular_file "$dest" || die "Schreiben fehlgeschlagen: $rel"
    real="$(realpath -e "$dest" 2>/dev/null || true)"
    if ! under_panel "$real"; then
        rm -f -- "$dest"
        die "Geschriebene Datei liegt ausserhalb des Panels: $rel"
    fi
}

safe_replace_file() {
    local dest="$1" srcf="$2" rel dir tmp real mode
    rel="${dest#"$PANEL"/}"
    [ "$dest" = "$PANEL/$rel" ] || die "Ziel ausserhalb des Panels."
    require_confined "$rel"
    regular_file "$dest" || die "Zieldatei fehlt oder ist ein Symlink: $rel"
    dir="$(dirname "$dest")"
    real_dir "$dir" || die "Zielverzeichnis fehlt oder ist ein Symlink."
    tmp="$(mktemp "$dir/.nebula.XXXXXX")"
    real="$(realpath -e "$tmp" 2>/dev/null || true)"
    if ! under_panel "$real"; then
        rm -f "$tmp"
        die "Temporaere Datei liegt ausserhalb des Panels."
    fi
    if ! cp "$srcf" "$tmp"; then
        rm -f "$tmp"
        die "Kopieren fehlgeschlagen: $rel"
    fi
    mode="$(stat -c '%a' "$dest" 2>/dev/null || echo 644)"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || mode="644"
    chmod "$mode" "$tmp"
    if [ "$(id -u)" = "0" ]; then
        if ! chown --reference="$dest" "$tmp"; then
            rm -f "$tmp"
            die "Besitzer konnte nicht uebernommen werden: $rel"
        fi
    fi
    if [ -L "$dir" ] || [ -L "$dest" ]; then
        rm -f "$tmp"
        die "Zielpfad wurde waehrend des Schreibens zu einem Symlink: $rel"
    fi
    if ! mv -T "$tmp" "$dest"; then
        rm -f "$tmp"
        die "Schreiben fehlgeschlagen: $rel"
    fi
    regular_file "$dest" || die "Schreiben fehlgeschlagen: $rel"
    real="$(realpath -e "$dest" 2>/dev/null || true)"
    if ! under_panel "$real"; then
        rm -f -- "$dest"
        die "Geschriebene Datei liegt ausserhalb des Panels: $rel"
    fi
}

safe_reset_theme_dir() {
    local parent_rel="public/themes" target="$PANEL/$THEME_REL"
    require_confined "$parent_rel"
    real_dir "$PANEL/$parent_rel" || die "public/themes fehlt oder ist ein Symlink."
    if [ -L "$target" ]; then
        rm -f -- "$target"
    elif [ -d "$target" ]; then
        require_confined "$THEME_REL"
        rm -rf -- "$target"
    elif [ -e "$target" ]; then
        rm -f -- "$target"
    fi
    mkdir -- "$target"
    require_confined "$THEME_REL"
    chmod 755 "$target"
}

known_asset_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    case "$1" in
        nebula*.css|nebula*.js|theme.json|ASSET_VERSION) return 0 ;;
        *) return 1 ;;
    esac
}

install_built_assets() {
    local build_dir="$1" f base target found=0 user group
    local -a candidates=()
    target="$PANEL/$THEME_REL"
    safe_reset_theme_dir
    local nullglob_was=0
    shopt -q nullglob && nullglob_was=1
    shopt -s nullglob
    candidates=("$build_dir"/nebula*.css "$build_dir"/nebula*.js "$build_dir/theme.json" "$build_dir/ASSET_VERSION")
    if [ "$nullglob_was" = "0" ]; then
        shopt -u nullglob
    fi
    [ "${#candidates[@]}" -gt 0 ] || die "Build lieferte keine Assets."
    for f in "${candidates[@]}"; do
        regular_file "$f" || die "Build-Artefakt ungueltig: $f"
        base="$(basename "$f")"
        known_asset_name "$base" || die "Ungueltiger Asset-Name: $base"
        safe_install_file "$target/$base" "$f"
        found=1
    done
    [ "$found" = "1" ] || die "Build lieferte keine Assets."
    if [ "$(id -u)" = "0" ]; then
        user="$(web_user)"
        group="$(web_group)"
        chown -h "$user:$group" "$target"
        for f in "$target"/*; do
            [ -e "$f" ] || continue
            regular_file "$f" || die "Asset ist ein Symlink: $(basename "$f")"
            chown -h "$user:$group" "$f"
            chmod 644 "$f"
        done
    fi
}

remove_theme_dir() {
    local parent_rel="public/themes" target="$PANEL/$THEME_REL"
    if [ ! -e "$PANEL/$parent_rel" ] && [ ! -L "$PANEL/$parent_rel" ]; then
        return 0
    fi
    require_confined "$parent_rel"
    if [ -L "$target" ]; then
        rm -f -- "$target"
        return 0
    fi
    if [ ! -e "$target" ]; then
        return 0
    fi
    require_confined "$THEME_REL"
    rm -rf -- "$target"
}

remove_state_file() {
    local dest="$PANEL/$STATE_FILE"
    if [ -L "$dest" ]; then
        rm -f -- "$dest"
        return 0
    fi
    if [ -e "$dest" ]; then
        require_confined "$STATE_FILE"
        rm -f -- "$dest"
    fi
}

# Kopiert nur die bekannten Mitglieder aus einem bereits entpackten Archiv.
restore_members_from() {
    local root="$1" rel src base f src_real root_real
    local -a blades=() assets=()
    root_real="$(realpath -e "$root" 2>/dev/null || true)"
    [ -n "$root_real" ] || die "Entpacktes Backup nicht lesbar."
    for rel in "$WRAPPER_REL" "$ADMIN_REL"; do
        src="$root/$rel"
        [ -e "$src" ] || [ -L "$src" ] || continue
        regular_file "$src" || die "Backup-Mitglied ist kein regulaeres File: $rel"
        src_real="$(realpath -e "$src" 2>/dev/null || true)"
        case "$src_real" in
            "$root_real"/*) ;;
            *) die "Backup-Mitglied liegt ausserhalb des Archivs: $rel" ;;
        esac
        require_confined "$rel"
        blades+=("$rel")
    done
    local theme_src="$root/$THEME_REL" do_theme=0
    if [ -e "$theme_src" ] || [ -L "$theme_src" ]; then
        real_dir "$theme_src" || die "Theme-Backup ist kein Verzeichnis."
        src_real="$(realpath -e "$theme_src" 2>/dev/null || true)"
        case "$src_real" in
            "$root_real"/*) ;;
            *) die "Theme-Backup liegt ausserhalb des Archivs." ;;
        esac
        require_confined "public/themes"
        for f in "$theme_src"/*; do
            [ -e "$f" ] || [ -L "$f" ] || continue
            base="$(basename "$f")"
            known_asset_name "$base" || die "Unbekanntes Backup-Asset: $base"
            regular_file "$f" || die "Backup-Asset ist kein regulaeres File: $base"
            src_real="$(realpath -e "$f" 2>/dev/null || true)"
            case "$src_real" in
                "$root_real"/*) ;;
                *) die "Backup-Asset liegt ausserhalb des Archivs: $base" ;;
            esac
            assets+=("$base")
        done
        do_theme=1
    fi
    for rel in "${blades[@]+"${blades[@]}"}"; do
        [ -n "$rel" ] || continue
        safe_replace_file "$PANEL/$rel" "$root/$rel"
    done
    if [ "$do_theme" = "1" ]; then
        safe_reset_theme_dir
        for base in "${assets[@]+"${assets[@]}"}"; do
            [ -n "$base" ] || continue
            safe_install_file "$PANEL/$THEME_REL/$base" "$theme_src/$base"
        done
    fi
}

# Ersetzt LIB_DIR erst, wenn die neue Kopie vollstaendig ist.
swap_lib_dir() {
    local src="$1" parent stage old src_real lib_real
    if [ -z "$src" ] || [ ! -d "$src" ]; then
        die "CLI-Quelle fehlt."
    fi
    src_real="$(realpath -e "$src" 2>/dev/null || true)"
    [ -n "$src_real" ] || die "CLI-Quelle nicht aufloesbar."
    if [ -e "$LIB_DIR" ] || [ -L "$LIB_DIR" ]; then
        lib_real="$(realpath -e "$LIB_DIR" 2>/dev/null || true)"
        if [ -n "$lib_real" ] && [ "$src_real" = "$lib_real" ]; then
            die "CLI-Quelle ist das Installationsverzeichnis selbst."
        fi
    fi
    parent="$(dirname "$LIB_DIR")"
    [ -d "$parent" ] || die "CLI-Elternverzeichnis fehlt."
    stage="$(mktemp -d "$parent/.nebula-stage.XXXXXX")"
    if ! cp -a "$src/theme" "$src/scripts" "$src/install.sh" "$src/VERSION" "$src/theme.json" "$stage/"; then
        rm -rf "$stage"
        die "CLI-Kopie fehlgeschlagen."
    fi
    if [ ! -f "$stage/install.sh" ] || [ ! -d "$stage/theme/css" ] || [ ! -f "$stage/scripts/build.sh" ]; then
        rm -rf "$stage"
        die "CLI-Kopie unvollstaendig."
    fi
    if find "$stage" -type l -print -quit | grep -q .; then
        rm -rf "$stage"
        die "CLI-Quelle enthaelt Symlinks."
    fi
    if ! chmod 755 "$stage" "$stage/install.sh"; then
        rm -rf "$stage"
        die "CLI-Rechte konnten nicht gesetzt werden."
    fi
    local script
    for script in "$stage/scripts/"*.sh; do
        [ -f "$script" ] || { rm -rf "$stage"; die "CLI-Skript fehlt."; }
        if ! chmod +x "$script"; then
            rm -rf "$stage"
            die "CLI-Rechte konnten nicht gesetzt werden."
        fi
    done
    old=""
    if [ -e "$LIB_DIR" ] || [ -L "$LIB_DIR" ]; then
        old="$parent/.nebula-old.$$.$RANDOM"
        rm -rf -- "$old"
        mv -- "$LIB_DIR" "$old"
    fi
    if ! mv -- "$stage" "$LIB_DIR"; then
        rm -rf -- "$stage"
        if [ -n "$old" ] && [ -e "$old" ]; then
            mv -- "$old" "$LIB_DIR"
        fi
        die "CLI-Verzeichnis konnte nicht ersetzt werden."
    fi
    if [ -n "$old" ]; then
        rm -rf -- "$old"
    fi
    chmod 755 "$LIB_DIR"
}

# -----------------------------------------------------------------------------
# Blade-Injektion
# -----------------------------------------------------------------------------
strip_block() {
    # $1 = Datei
    local file="$1" tmp rel
    rel="${file#"$PANEL"/}"
    [ "$file" = "$PANEL/$rel" ] || die "Blade-Pfad ausserhalb des Panels."
    [ -e "$file" ] || [ -L "$file" ] || return 0
    require_confined "$rel"
    regular_file "$file" || die "Blade-Datei fehlt oder ist ein Symlink: $rel"
    grep -q 'NEBULA:START' "$file" || return 0
    tmp="$(mktemp)"
    sed '/{{-- NEBULA:START --}}/,/{{-- NEBULA:END --}}/d' "$file" > "$tmp"
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s Block aus %s entfernen\n' "$C_DIM" "$C_RESET" "$file"
        rm -f "$tmp"
        return 0
    fi
    safe_replace_file "$file" "$tmp"
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

    safe_replace_file "$file" "$tmp"
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
    if [ -e "$PANEL/$WRAPPER_REL" ] || [ -L "$PANEL/$WRAPPER_REL" ]; then
        require_confined "$WRAPPER_REL"
        regular_file "$PANEL/$WRAPPER_REL" || die "wrapper.blade.php ist kein regulaeres File."
        files+=("$WRAPPER_REL")
    fi
    if [ -e "$PANEL/$ADMIN_REL" ] || [ -L "$PANEL/$ADMIN_REL" ]; then
        require_confined "$ADMIN_REL"
        regular_file "$PANEL/$ADMIN_REL" || die "admin.blade.php ist kein regulaeres File."
        files+=("$ADMIN_REL")
    fi
    if [ -e "$PANEL/$THEME_REL" ] || [ -L "$PANEL/$THEME_REL" ]; then
        require_confined "$THEME_REL"
        real_dir "$PANEL/$THEME_REL" || die "Theme-Verzeichnis ist kein echtes Verzeichnis."
        if find "$PANEL/$THEME_REL" -type l -print -quit | grep -q .; then
            die "Theme-Verzeichnis enthaelt Symlinks – Backup abgelehnt."
        fi
        files+=("$THEME_REL")
    fi

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
    if [ -z "$real" ] || ! regular_file "$real"; then
        die "Backup nicht vorhanden: $archive"
    fi
    case "$real" in
        "$root"/*) ;;
        *) die "Backup liegt ausserhalb von $BACKUP_ROOT." ;;
    esac
    owner="$(stat -c '%U' "$real" 2>/dev/null || echo '')"
    [ "$owner" = "root" ] || die "Backup gehoert nicht root: $real"
    archive_is_safe "$real" || die "Backup-Archiv enthaelt unsichere Pfade oder Links."
    confirm "Backup '$real' nach $PANEL zuruecksichern?" || { info "Abgebrochen."; return 0; }
    if [ "$DRY_RUN" != "1" ]; then
        local extract
        extract="$(mktemp -d)"
        if ! tar -xzf "$real" -C "$extract" --no-same-owner --no-same-permissions \
            || find "$extract" -type l -print -quit | grep -q .; then
            rm -rf "$extract"
            die "Backup konnte nicht sicher entpackt werden."
        fi
        restore_members_from "$extract"
        rm -rf "$extract"
    else
        printf '  %s[dry-run]%s Backup nach %s entpacken und bekannte Dateien kopieren\n' "$C_DIM" "$C_RESET" "$PANEL"
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
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<JSON
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
    safe_install_file "$PANEL/$STATE_FILE" "$tmp" 600
    rm -f "$tmp"
    regular_file "$PANEL/$STATE_FILE" || die "Zustandsdatei unsicher."
    chmod 600 "$PANEL/$STATE_FILE"
}

read_state() {
    regular_file "$PANEL/$STATE_FILE" || return 1
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
    swap_lib_dir "$SRC"

    local qlib qpanel clitemp
    printf -v qlib '%q' "$LIB_DIR"
    printf -v qpanel '%q' "$PANEL"
    clitemp="$(mktemp "$(dirname "$CLI_PATH")/.nebula-cli.XXXXXX")"
    cat > "$clitemp" <<CLI
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
    chmod 755 "$clitemp"
    mv -T "$clitemp" "$CLI_PATH"
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

    require_confined "$WRAPPER_REL"
    regular_file "$PANEL/$WRAPPER_REL" || die "Erwartete Datei fehlt oder ist ein Symlink: $PANEL/$WRAPPER_REL"

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
    if [ "$DRY_RUN" != "1" ]; then
        install_built_assets "$build_dir"
    else
        printf '  %s[dry-run]%s Assets nach %s\n' "$C_DIM" "$C_RESET" "$PANEL/$THEME_REL"
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

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s %s und %s entfernen\n' "$C_DIM" "$C_RESET" "$THEME_REL" "$STATE_FILE"
    else
        remove_theme_dir
        remove_state_file
    fi
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
