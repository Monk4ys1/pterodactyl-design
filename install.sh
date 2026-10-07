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
#    --branch <name>        Git-Branch der Quelle; kein Fallback auf andere Refs
#    --tag <name>           Tag festnageln (zuerst refs/tags, kein Fallback)
#    --checksum <sha256>    SHA-256 des codeload-Archivs; sudo streicht PTD_SHA256
#    --yes                  Keine Rueckfragen
#    --no-backup            Kein Backup anlegen (nicht empfohlen)
#    --no-cli               Den Befehl "nebula" nicht installieren
#    --no-admin             Adminbereich unveraendert lassen
#    --dry-run              Nur anzeigen, nichts schreiben
# =============================================================================
set -euo pipefail
umask 022

# CWD darf nicht auf sys.path liegen, wenn spaeter ctypes importiert wird.
_ptd_src="${BASH_SOURCE[0]}"
_ptd_dir="$(dirname "$_ptd_src")"
if _ptd_abs="$(cd "$_ptd_dir" 2>/dev/null && pwd)"; then
    _ptd_src="${_ptd_abs}/$(basename "$_ptd_src")"
fi
cd / || exit 1

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
  --branch <name>      Git-Branch der Quelle; zuerst refs/heads, kein Fallback
  --tag <name>         Tag festnageln; zuerst refs/tags, dann der bloße Name
  --checksum <sha256>  SHA-256 des Quellarchivs von codeload.github.com
                       sudo entfernt die Variable PTD_SHA256. Flag bevorzugen,
                       oder: sudo --preserve-env=PTD_SHA256
                       Aus einem lokalen Checkout werden --tag und --checksum
                       abgelehnt, statt still ignoriert zu werden.
                       Ohne Angabe bleibt der bisherige Download erhalten.
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
TAG_REQUESTED=0
BRANCH_REQUESTED=0
BRANCH="$DEFAULT_BRANCH"
if [ -n "${PTD_BRANCH+x}" ]; then
    BRANCH="$PTD_BRANCH"
    REF_EXPLICIT=1
    BRANCH_REQUESTED=1
fi
SEAL_PATHS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
ASSUME_YES=0
DO_BACKUP=1
DO_CLI=1
DO_ADMIN=1
DRY_RUN=0
CHECKSUM="${PTD_SHA256:-}"
SRC=""
SRC_ROOT=""
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

valid_checksum() {
    [[ "${1:-}" =~ ^[0-9a-fA-F]{64}$ ]]
}

# Steuerzeichen aus Panel-Dateien duerfen die Root-Konsole nicht umschreiben.
sanitize_text() {
    local s="$1"
    # shellcheck disable=SC2001
    printf '%s' "$s" | tr -d '\000-\037\177'
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
    # Tar-Verzeichnisse enden auf "/". Sonst wird "/dir//" und jedes echte Archiv abgelehnt.
    m="${m%/}"
    [ -n "$m" ] || return 0
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

# 0, wenn der Modus fuer Gruppe oder andere beschreibbar ist (oder unbekannt).
mode_go_writable() {
    local mode="$1" gw ow
    [ "${#mode}" -ge 3 ] || return 0
    gw="${mode: -2:1}"
    ow="${mode: -1}"
    case "$gw" in 2|3|6|7) return 0 ;; esac
    case "$ow" in 2|3|6|7) return 0 ;; esac
    return 1
}

# Existierender Vorfahr von BACKUP_ROOT. Als root muss er root gehoeren und
# darf nicht gruppen- oder fremdbeschreibbar sein. Sonst folgt mkdir einem Tausch.
backup_ancestor_ok() {
    local d="$1" mode
    [ -n "$d" ] || return 1
    while [ ! -d "$d" ] && [ "$d" != "/" ]; do
        d="$(dirname "$d")"
    done
    [ -d "$d" ] && [ ! -L "$d" ] || return 1
    if [ "$(id -u)" != "0" ]; then
        return 0
    fi
    [ "$(stat -c '%u' "$d" 2>/dev/null || echo '')" = "0" ] || return 1
    mode="$(stat -c '%a' "$d" 2>/dev/null || echo '')"
    if mode_go_writable "$mode"; then
        return 1
    fi
    return 0
}

prepare_backup_root() {
    local parent
    if [ -L "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist ein Symlink: $BACKUP_ROOT"
    fi
    if [ -e "$BACKUP_ROOT" ] && [ ! -d "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist kein Verzeichnis: $BACKUP_ROOT"
    fi
    parent="$(dirname "$BACKUP_ROOT")"
    backup_ancestor_ok "$parent" || die "Backup-Elternverzeichnis gehoert nicht root oder ist beschreibbar: $(sanitize_text "$parent")"
    if [ -d "$BACKUP_ROOT" ]; then
        local owner
        owner="$(stat -c '%U' "$BACKUP_ROOT" 2>/dev/null || echo '')"
        [ "$owner" = "root" ] || die "Backup-Verzeichnis gehoert nicht root: $BACKUP_ROOT"
        if [ -L "$BACKUP_ROOT" ]; then
            die "Backup-Pfad ist ein Symlink: $BACKUP_ROOT"
        fi
    fi
    mkdir -p -- "$BACKUP_ROOT"
    if [ -L "$BACKUP_ROOT" ] || [ ! -d "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist kein Verzeichnis: $BACKUP_ROOT"
    fi
    if [ "$(id -u)" = "0" ]; then
        chown -h root:root -- "$BACKUP_ROOT" || die "Backup-Verzeichnis nicht schuetzbar."
    fi
    if [ -L "$BACKUP_ROOT" ] || [ ! -d "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist ein Symlink: $BACKUP_ROOT"
    fi
    chmod 700 -- "$BACKUP_ROOT" || die "Backup-Verzeichnis nicht schuetzbar."
    if [ -L "$BACKUP_ROOT" ] || [ ! -d "$BACKUP_ROOT" ]; then
        die "Backup-Pfad ist ein Symlink: $BACKUP_ROOT"
    fi
}

# Autodetect und --path: jedes Elternverzeichnis muss root gehoeren und darf
# nicht gruppen- oder fremdbeschreibbar sein, damit www-data das Panel nicht
# gegen einen Symlink tauschen kann. Das Panel-Verzeichnis selbst darf www-data
# gehoeren; es wird vor dem Schreiben auf root:root 0755 gesetzt.
parents_root_owned() {
    local d="$1" owner mode
    [ -n "$d" ] || return 1
    d="$(dirname "$d")"
    while [ "$d" != "/" ]; do
        if [ -L "$d" ]; then
            return 1
        fi
        owner="$(stat -c '%u' "$d" 2>/dev/null || echo '')"
        [ "$owner" = "0" ] || return 1
        mode="$(stat -c '%a' "$d" 2>/dev/null || echo '')"
        if mode_go_writable "$mode"; then
            return 1
        fi
        d="$(dirname "$d")"
    done
    return 0
}

panel_parent_advice() {
    die "Panel gefunden, aber ein Elternverzeichnis von '$(sanitize_text "$1")' gehoert nicht root oder ist fuer die Gruppe oder andere beschreibbar. Bitte die Eltern auf root:root und 0755 setzen, zum Beispiel: sudo chown root:root /var/www && sudo chmod 755 /var/www. Das Panel-Verzeichnis selbst darf www-data gehoeren. Bei mehreren Panels --path angeben."
}

fail_if_many_panels() {
    [ "$#" -le 1 ] && return 0
    die "Mehrere Panels gefunden. Bitte genau eines mit --path angeben: $*"
}

harden_panel_path() {
    local real mode d
    real="$(realpath -e "$PANEL" 2>/dev/null || true)"
    [ -n "$real" ] || die "Panel-Pfad nicht aufloesbar: $PANEL"
    [ "$real" != "/" ] || die "Panel-Pfad ungueltig."
    PANEL="$real"
    parents_root_owned "$PANEL" || panel_parent_advice "$PANEL"
    d="$PANEL"
    while [ "$d" != "/" ]; do
        if [ -L "$d" ]; then
            die "Pfad enthaelt einen Symlink: $(sanitize_text "$d")"
        fi
        mode="$(stat -c '%a' "$d" 2>/dev/null || echo 777)"
        if mode_go_writable "$mode"; then
            die "Pfad ist fuer die Gruppe oder andere beschreibbar: $(sanitize_text "$d"). Bitte chmod 755 setzen."
        fi
        d="$(dirname "$d")"
    done
    regular_file "$PANEL/artisan" || die "artisan fehlt oder ist ein Symlink."
    mode="$(stat -c '%a' "$PANEL/artisan")"
    if mode_go_writable "$mode"; then
        die "artisan ist fuer die Gruppe oder andere beschreibbar."
    fi
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
        --branch)     BRANCH="${2:-}"; REF_EXPLICIT=1; BRANCH_REQUESTED=1; shift ;;
        --branch=*)   BRANCH="${1#*=}"; REF_EXPLICIT=1; BRANCH_REQUESTED=1 ;;
        --tag)        BRANCH="${2:-}"; REF_EXPLICIT=1; TAG_REQUESTED=1; shift ;;
        --tag=*)      BRANCH="${1#*=}"; REF_EXPLICIT=1; TAG_REQUESTED=1 ;;
        --checksum)
            CHECKSUM="${2:-}"
            shift
            [ -n "$CHECKSUM" ] || die "--checksum braucht eine SHA-256-Summe (64 Hex-Zeichen)."
            ;;
        --checksum=*)
            CHECKSUM="${1#*=}"
            [ -n "$CHECKSUM" ] || die "--checksum braucht eine SHA-256-Summe (64 Hex-Zeichen)."
            ;;
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

valid_ref "$BRANCH" || die "Ungueltige Git-Ref in --branch, --tag oder PTD_BRANCH."
if [ -n "$CHECKSUM" ]; then
    valid_checksum "$CHECKSUM" || die "Ungueltige SHA-256-Pruefsumme (64 Hex-Zeichen)."
fi

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

# Absoluter Pfad, damit ein PATH-Hook python3 nicht ersetzen kann.
python3_bin() {
    local c
    for c in /usr/bin/python3 /usr/local/bin/python3; do
        if [ -x "$c" ]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    return 1
}

require_python3() {
    python3_bin >/dev/null || die "python3 fehlt. Bitte installieren: apt install python3"
}

# rename/unlink/copy ueber Verzeichnis-Dateideskriptoren und O_NOFOLLOW.
# mv, rm und cp loesen den Pfad danach neu auf; ein getauschter Parent
# wuerde sonst in ein fremdes Verzeichnis schreiben oder es loeschen.
# -I und eine leere Umgebung: kein ctypes.py aus CWD oder PYTHONPATH.
fd_py() {
    local py
    py="$(python3_bin)" || die "python3 fehlt. Bitte installieren: apt install python3"
    (
        cd /
        # shellcheck disable=SC2093
        exec /usr/bin/env -i PATH="/usr/bin:/bin" "$py" -I - "$@"
    ) <<'PY'
import ctypes
import os
import stat
import sys

AT_REMOVEDIR = 0x200
_libc = ctypes.CDLL(None, use_errno=True)


def fail(msg):
    sys.stderr.write(msg + "\n")
    raise SystemExit(1)


def unlink_at(dirfd, name, flags):
    if _libc.unlinkat(int(dirfd), os.fsencode(name), int(flags)) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), name)


def open_dir(parent, name):
    return os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_CLOEXEC, dir_fd=parent)


def safe_name(name):
    if not name or name in (".", "..") or "/" in name or "\\" in name:
        fail("ungueltiger name")


def walk(root, rel):
    if not rel or rel.startswith("/") or "\\" in rel:
        fail("ungueltiger relativer pfad")
    parts = [p for p in rel.split("/") if p != ""]
    if not parts or any(p in (".", "..") for p in parts):
        fail("ungueltiger relativer pfad")
    fd = os.open(root, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in parts[:-1]:
            nxt = open_dir(fd, part)
            os.close(fd)
            fd = nxt
    except Exception:
        os.close(fd)
        raise
    return fd, parts[-1]


def rm_at(parent, name):
    safe_name(name)
    st = os.lstat(name, dir_fd=parent)
    if stat.S_ISLNK(st.st_mode) or stat.S_ISREG(st.st_mode):
        os.unlink(name, dir_fd=parent)
        return
    if not stat.S_ISDIR(st.st_mode):
        fail("weder datei noch verzeichnis")
    fd = open_dir(parent, name)
    try:
        for entry in os.listdir(fd):
            if entry in (".", ".."):
                continue
            rm_at(fd, entry)
    finally:
        os.close(fd)
    unlink_at(parent, name, AT_REMOVEDIR)


def copy_from(parent, name, dest, allowed):
    safe_name(name)
    st = os.lstat(name, dir_fd=parent)
    if not stat.S_ISREG(st.st_mode):
        fail("keine regulaere datei")
    if st.st_nlink != 1:
        fail("hardlink")
    if st.st_uid not in allowed:
        fail("uid")
    src = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
    try:
        fst = os.fstat(src)
    except OSError:
        os.close(src)
        raise
    if fst.st_nlink != 1 or fst.st_ino != st.st_ino or fst.st_uid != st.st_uid:
        os.close(src)
        fail("datei geaendert")
    try:
        out = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            while True:
                chunk = os.read(src, 1024 * 1024)
                if not chunk:
                    break
                os.write(out, chunk)
        finally:
            os.close(out)
    finally:
        os.close(src)


def publish(root, rel, src, kind):
    parent, name = walk(root, rel)
    try:
        try:
            st = os.lstat(name, dir_fd=parent)
        except FileNotFoundError:
            st = None
        if st is not None and stat.S_ISLNK(st.st_mode):
            fail("ziel ist ein symlink")
        if kind == "dir":
            if st is not None:
                fail("ziel existiert bereits")
        elif st is not None and not stat.S_ISREG(st.st_mode):
            fail("ziel ist keine datei")
        os.rename(src, name, dst_dir_fd=parent)
    finally:
        os.close(parent)


def unlink_rel(root, rel):
    parent, name = walk(root, rel)
    try:
        try:
            os.lstat(name, dir_fd=parent)
        except FileNotFoundError:
            return
        rm_at(parent, name)
    finally:
        os.close(parent)


def snapshot(root, rel, dest_root, allowed):
    parent, name = walk(root, rel)
    try:
        st = os.lstat(name, dir_fd=parent)
        if stat.S_ISLNK(st.st_mode):
            fail("symlink")
        dest = os.path.join(dest_root, rel)
        if stat.S_ISDIR(st.st_mode):
            os.makedirs(dest, 0o700)
            fd = open_dir(parent, name)
            try:
                for entry in os.listdir(fd):
                    if entry in (".", ".."):
                        continue
                    safe_name(entry)
                    est = os.lstat(entry, dir_fd=fd)
                    if stat.S_ISLNK(est.st_mode) or not stat.S_ISREG(est.st_mode):
                        fail("unsicherer verzeichniseintrag")
                    copy_from(fd, entry, os.path.join(dest, entry), allowed)
            finally:
                os.close(fd)
        elif stat.S_ISREG(st.st_mode):
            os.makedirs(os.path.dirname(dest), 0o700)
            copy_from(parent, name, dest, allowed)
        else:
            fail("weder datei noch verzeichnis")
    finally:
        os.close(parent)


def open_nofollow_dir(path):
    if os.path.islink(path):
        fail("symlink")
    return os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_CLOEXEC)


def rename_into(directory, name, src):
    safe_name(name)
    fd = open_nofollow_dir(directory)
    try:
        try:
            st = os.lstat(name, dir_fd=fd)
        except FileNotFoundError:
            st = None
        if st is not None and stat.S_ISLNK(st.st_mode):
            fail("ziel ist ein symlink")
        os.rename(src, name, dst_dir_fd=fd)
    finally:
        os.close(fd)


def unlink_child(directory, name):
    fd = open_nofollow_dir(directory)
    try:
        try:
            os.lstat(name, dir_fd=fd)
        except FileNotFoundError:
            return
        rm_at(fd, name)
    finally:
        os.close(fd)


def parse_uids(text):
    out = set()
    for part in text.split(","):
        part = part.strip()
        if part.isdigit():
            out.add(int(part))
    return out


def main():
    if len(sys.argv) < 2:
        fail("befehl fehlt")
    cmd = sys.argv[1]
    try:
        if cmd == "publish-file" and len(sys.argv) == 5:
            publish(sys.argv[2], sys.argv[3], sys.argv[4], "file")
        elif cmd == "publish-dir" and len(sys.argv) == 5:
            publish(sys.argv[2], sys.argv[3], sys.argv[4], "dir")
        elif cmd == "unlink" and len(sys.argv) == 4:
            unlink_rel(sys.argv[2], sys.argv[3])
        elif cmd == "snapshot" and len(sys.argv) in (5, 6):
            allowed = {os.geteuid(), 0}
            if len(sys.argv) == 6:
                allowed |= parse_uids(sys.argv[5])
            snapshot(sys.argv[2], sys.argv[3], sys.argv[4], allowed)
        elif cmd == "rename-into" and len(sys.argv) == 5:
            rename_into(sys.argv[2], sys.argv[3], sys.argv[4])
        elif cmd == "unlink-child" and len(sys.argv) == 4:
            unlink_child(sys.argv[2], sys.argv[3])
        else:
            fail("unbekannter befehl")
    except SystemExit:
        raise
    except OSError as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
PY
}

installer_dir() {
    local dir
    dir="$(dirname "$_ptd_src")"
    if [ -d "$dir" ] && [ ! -L "$dir" ]; then
        printf '%s' "$dir"
        return 0
    fi
    printf ''
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Programm fehlt: $1"
}

# --tag versucht refs/tags vor dem bloßen Namen. --branch bleibt bei refs/heads.
source_archive_urls() {
    local b="$1"
    if [ "${TAG_REQUESTED:-0}" = "1" ]; then
        printf '%s\n' "https://codeload.github.com/${REPO}/tar.gz/refs/tags/${b}"
        printf '%s\n' "https://codeload.github.com/${REPO}/tar.gz/${b}"
    else
        printf '%s\n' "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${b}"
        printf '%s\n' "https://codeload.github.com/${REPO}/tar.gz/${b}"
    fi
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
    if [ -n "${SRC_ROOT:-}" ]; then
        rm -rf -- "$SRC_ROOT"
    elif [ -n "${SRC_TMP:-}" ]; then
        rm -rf -- "$SRC_TMP"
    fi
    if [ -z "${SRC_ROOT:-}" ] && [ -n "${SRC_TARBALL:-}" ]; then
        rm -f -- "$SRC_TARBALL"
    fi
    SRC_ROOT=""
    SRC_TMP=""
    SRC_TARBALL=""
}

sha256_of() {
    local f="$1" hex
    if command -v sha256sum >/dev/null 2>&1; then
        hex="$(sha256sum -- "$f" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        hex="$(shasum -a 256 -- "$f" | awk '{print $1}')"
    else
        die "sha256sum fehlt. Ohne das Programm kann --checksum nicht geprueft werden."
    fi
    printf '%s' "$hex" | tr 'A-F' 'a-f'
}

checksum_matches() {
    local file="$1" expect got
    valid_checksum "$CHECKSUM" || return 1
    expect="$(printf '%s' "$CHECKSUM" | tr 'A-F' 'a-f')"
    got="$(sha256_of "$file")"
    [ -n "$got" ] && [ "$got" = "$expect" ]
}

# -----------------------------------------------------------------------------
# Quelle bereitstellen (lokal oder von GitHub)
# -----------------------------------------------------------------------------
# Update mit Summe, aber ohne Tag und ohne Branch, wuerde die Summe gegen
# den wandernden Standardbranch pruefen und danach nie wieder gelingen.
refuse_checksum_without_ref() {
    [ "${ACTION:-}" = "update" ] || return 0
    [ -n "${CHECKSUM:-}" ] || return 0
    if [ "${TAG_REQUESTED:-0}" = "1" ] || [ "${BRANCH_REQUESTED:-0}" = "1" ]; then
        return 0
    fi
    die "Eine Pruefsumme ohne --tag oder --branch kann nebula update nicht zuordnen: der Standardbranch aendert sich, die Summe nicht. Bitte --tag <name> --checksum <summe> angeben."
}

resolve_source() {
    require_python3
    local here
    here="$(installer_dir)"

    if ! source_is_installed_lib \
        && [ -n "$here" ] \
        && [ -d "$here/theme/css" ] \
        && [ -f "$here/scripts/build.sh" ] \
        && [ ! -L "$here/theme" ] \
        && [ ! -L "$here/scripts/build.sh" ]; then
        if [ -n "$CHECKSUM" ] || [ "${TAG_REQUESTED:-0}" = "1" ]; then
            die "--tag und --checksum gelten nur fuer den Download von GitHub. Aus einem lokalen Verzeichnis wuerden sie still ignoriert und werden deshalb abgelehnt."
        fi
        SRC="$here"
        if [ "$(id -u)" = "0" ]; then
            tree_owned_by_root "$SRC" || die "Lokale Quelle gehoert nicht root oder ist beschreibbar. Auch --no-cli fuehrt sie nicht aus. Vorher: chown -R root:root <quelle>"
        fi
        info "Quelle: lokales Verzeichnis ${C_DIM}$(sanitize_text "$SRC")${C_RESET}"
        return
    fi

    require_python3
    refuse_checksum_without_ref
    need_tool curl
    need_tool tar
    if [ -n "$CHECKSUM" ]; then
        command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
            || die "sha256sum fehlt. Ohne das Programm kann --checksum nicht geprueft werden."
        if [ "${TAG_REQUESTED:-0}" != "1" ] && [ "${BRANCH_REQUESTED:-0}" != "1" ]; then
            warn "Die Pruefsumme gilt nur fuer diesen Lauf und wird nicht in nebula gespeichert, weil kein --tag und kein --branch gesetzt ist."
        fi
    else
        warn "Keine SHA-256-Pruefsumme gesetzt. Optional: --tag <name> --checksum <sha256>."
        if [ -n "${SUDO_USER:-}" ]; then
            warn "sudo entfernt PTD_SHA256. Bitte --checksum verwenden oder: sudo --preserve-env=PTD_SHA256"
        fi
    fi

    # Tarball nur innerhalb eines 0700-Verzeichnisses. Nicht per Pfad in /tmp neu anlegen.
    SRC_ROOT="$(mktemp -d)"
    chmod 700 "$SRC_ROOT" || { rm -rf -- "$SRC_ROOT"; die "Quellverzeichnis nicht schuetzbar."; }
    SRC_TMP="$SRC_ROOT/tree"
    mkdir -m 700 -- "$SRC_TMP"
    SRC_TARBALL="$SRC_ROOT/source.tar.gz"
    if [ "${PTD_SELFTEST:-}" != "1" ]; then
        trap finish_exit EXIT
    fi

    local branches=() b
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        branches+=("$b")
    done < <(source_ref_list)

    local url
    for b in "${branches[@]}"; do
        valid_ref "$b" || continue
        info "Lade Quelle von GitHub (Ref: $b) …"
        # --tag zuerst refs/tags, sonst zuerst refs/heads. Danach der bloße Name.
        local -a urls=()
        while IFS= read -r url; do
            [ -n "$url" ] || continue
            urls+=("$url")
        done < <(source_archive_urls "$b")
        for url in "${urls[@]}"; do
            rm -rf -- "${SRC_TMP:?}/"* 2>/dev/null || true
            rm -f -- "$SRC_TARBALL"
            if curl -fsSL --tlsv1.2 --proto '=https' --proto-redir '=https' --max-redirs 2 --retry 2 --max-time 60 \
                -o "$SRC_TARBALL" "$url" \
                && { [ -z "$CHECKSUM" ] || checksum_matches "$SRC_TARBALL"; } \
                && archive_is_safe "$SRC_TARBALL" \
                && tar -xzf "$SRC_TARBALL" -C "$SRC_TMP" --strip-components=1 --no-same-owner --no-same-permissions \
                && [ -d "$SRC_TMP/theme/css" ] \
                && [ ! -L "$SRC_TMP/theme" ] \
                && [ ! -L "$SRC_TMP/scripts/build.sh" ] \
                && ! find "$SRC_TMP" -type l -print -quit | grep -q .; then
                SRC="$SRC_TMP"
                BRANCH="$b"
                ok "Quelle geladen (Ref: $b)"
                if [ -n "$CHECKSUM" ]; then
                    ok "SHA-256 geprueft."
                fi
                return
            fi
            rm -rf -- "${SRC_TMP:?}/"* 2>/dev/null || true
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
            warn "'$(sanitize_text "$PANEL")' sieht nicht nach einem originalen Pterodactyl Panel aus – es wird trotzdem fortgefahren."
        fi
        harden_panel_path
        return
    fi

    local -a panel_hits=() weak=()
    local c f d n=0 p seen u real
    for c in /var/www/pterodactyl /var/www/panel /var/www/html/pterodactyl /var/www/html/panel /srv/pterodactyl; do
        if is_panel "$c"; then
            if parents_root_owned "$c"; then
                panel_hits+=("$(realpath -e "$c")")
            else
                weak+=("$c")
            fi
        fi
    done

    while IFS= read -r -d '' f; do
        n=$((n + 1))
        [ "$n" -le 20 ] || break
        [ -n "$f" ] || continue
        d="$(dirname "$f")"
        if is_panel "$d"; then
            if parents_root_owned "$d"; then
                panel_hits+=("$(realpath -e "$d")")
            else
                weak+=("$d")
            fi
        fi
    done < <(find /var/www /srv /opt -xdev -maxdepth 4 -name artisan -type f -print0 2>/dev/null || true)

    local -a uniq=()
    for p in "${panel_hits[@]+"${panel_hits[@]}"}"; do
        [ -n "$p" ] || continue
        seen=0
        for u in "${uniq[@]+"${uniq[@]}"}"; do
            [ "$u" = "$p" ] && seen=1
        done
        [ "$seen" = "0" ] || continue
        uniq+=("$p")
    done
    fail_if_many_panels "${uniq[@]+"${uniq[@]}"}"
    if [ "${#uniq[@]}" -eq 1 ]; then
        PANEL="${uniq[0]}"
        harden_panel_path
        return
    fi
    if [ "${#weak[@]}" -gt 0 ]; then
        real="$(realpath -e "${weak[0]}" 2>/dev/null || echo "${weak[0]}")"
        panel_parent_advice "$real"
    fi
    die "Panel nicht gefunden. Bitte mit --path /var/www/pterodactyl angeben."
}

panel_version() {
    local v
    v="$(sed -n "s/.*'version'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" "$PANEL/config/app.php" 2>/dev/null | head -n1 || true)"
    sanitize_text "$v"
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

# Unmittelbar vor mv/rm/cp: jede Elternkomponente ist ein echtes Verzeichnis.
# Schlaegt das fehl, wird das Ziel nicht angefasst.
parent_still_real() {
    local dest="$1" rel="$2" dir parent_rel panel part rest cur
    dir="$(dirname "$dest")"
    real_dir "$dir" || return 1
    parent_rel="$(dirname "$rel")"
    [ "$parent_rel" = "." ] && parent_rel=""
    panel="$(realpath -e "$PANEL" 2>/dev/null || true)"
    [ -n "$panel" ] && [ "$panel" != "/" ] || return 1
    real_dir "$panel" || return 1
    if [ -n "$parent_rel" ]; then
        rest="$parent_rel"
        cur="$panel"
        while [ -n "$rest" ]; do
            part="${rest%%/*}"
            if [ "$part" = "$rest" ]; then
                rest=""
            else
                rest="${rest#*/}"
            fi
            [ -n "$part" ] && [ "$part" != "." ] && [ "$part" != ".." ] || return 1
            cur="$cur/$part"
            real_dir "$cur" || return 1
        done
    fi
    real_dir "$dir" || return 1
    return 0
}

# Gleicher Geraeteknoten: sonst wird mv zu Kopieren+Loeschen und die Race kehrt zurueck.
require_same_device() {
    local a b
    a="$(stat -c '%d' "$1" 2>/dev/null || true)"
    b="$(stat -c '%d' "$2" 2>/dev/null || true)"
    [ -n "$a" ] || return 1
    [ "$a" = "$b" ]
}

# Verzeichnis, in dem root (oder der aktuelle Benutzer) eine 0700-Zwischenablage
# anlegen kann, die der Web-Benutzer nicht ersetzen kann. Nicht das Zielverzeichnis.
stage_anchor() {
    local dest_dir="$1" dev dir
    dev="$(stat -c '%d' "$dest_dir" 2>/dev/null || true)"
    [ -n "$dev" ] || return 1
    dir="$(dirname "$dest_dir")"
    while true; do
        if stage_anchor_safe "$dir" "$dev"; then
            printf '%s\n' "$dir"
            return 0
        fi
        [ "$dir" = "/" ] && break
        dir="$(dirname "$dir")"
    done
    # Eigenes Dateisystem: der Elternpfad liegt woanders. Der root-eigene
    # Panel-Root bleibt ein gueltiger Anker fuer Dateien direkt im Panel.
    if [ -n "${PANEL:-}" ] && [ "$dest_dir" = "$PANEL" ] && stage_anchor_safe "$PANEL" "$dev"; then
        printf '%s\n' "$PANEL"
        return 0
    fi
    return 1
}

stage_anchor_safe() {
    local dir="$1" dev="$2" owner perms ow gw st
    [ -d "$dir" ] || return 1
    if [ -L "$dir" ]; then
        return 1
    fi
    [ "$(stat -c '%d' "$dir" 2>/dev/null || true)" = "$dev" ] || return 1
    owner="$(stat -c '%u' "$dir" 2>/dev/null || true)"
    perms="$(stat -c '%A' "$dir" 2>/dev/null || true)"
    [ "${#perms}" -eq 10 ] || return 1
    gw="${perms:5:1}"
    ow="${perms:8:1}"
    st="${perms:9:1}"
    if [ "$ow" = "w" ]; then
        if [ "$(id -u)" != "0" ] || [ "$owner" != "0" ]; then
            return 1
        fi
        if [ "$st" != "t" ] && [ "$st" != "T" ]; then
            return 1
        fi
        return 0
    fi
    if [ "$gw" = "w" ]; then
        return 1
    fi
    if [ "$owner" = "0" ] || [ "$owner" = "$(id -u)" ]; then
        return 0
    fi
    return 1
}

open_private_stage() {
    local dest_dir="$1" anchor stage
    real_dir "$dest_dir" || die "Zielverzeichnis fehlt oder ist ein Symlink."
    anchor="$(stage_anchor "$dest_dir")" || die "Keine sichere Zwischenablage auf demselben Dateisystem."
    stage="$(mktemp -d -- "$anchor/.nebula-stage.XXXXXX")"
    chmod 700 "$stage" || { rm -rf -- "$stage"; die "Zwischenablage nicht schuetzbar."; }
    if [ "$(id -u)" = "0" ]; then
        chown -h root:root "$stage" || { rm -rf -- "$stage"; die "Zwischenablage nicht schuetzbar."; }
    fi
    if [ -L "$stage" ] || [ ! -d "$stage" ]; then
        rm -rf -- "$stage"
        die "Zwischenablage ist ein Symlink."
    fi
    case "$stage" in
        "$dest_dir"|"$dest_dir"/*)
            if [ "$anchor" = "$PANEL" ] && [ "$dest_dir" = "$PANEL" ] \
                && stage_anchor_safe "$PANEL" "$(stat -c '%d' "$PANEL" 2>/dev/null || echo '')"; then
                :
            else
                rm -rf -- "$stage"
                die "Zwischenablage liegt im beschreibbaren Zielverzeichnis."
            fi
            ;;
    esac
    if ! require_same_device "$stage" "$dest_dir"; then
        rm -rf -- "$stage"
        die "Zwischenablage und Ziel liegen auf verschiedenen Dateisystemen."
    fi
    printf '%s\n' "$stage"
}

close_private_stage() {
    local stage="$1"
    [ -n "$stage" ] || return 0
    case "$(basename "$stage")" in
        .nebula-stage.*) rm -rf -- "$stage" ;;
        *) die "Zwischenablage unerwartet: $stage" ;;
    esac
}

# Vor der ersten Datei: Anker vorhersagen. Nach dem Siegeln muessen sie existieren.
anchor_ready() {
    local dest_dir="$1" dev
    [ -d "$dest_dir" ] && [ ! -L "$dest_dir" ] || return 1
    if stage_anchor "$dest_dir" >/dev/null; then
        return 0
    fi
    [ "$(id -u)" = "0" ] || return 1
    [ -d "$PANEL" ] && [ ! -L "$PANEL" ] || return 1
    dev="$(stat -c '%d' "$dest_dir" 2>/dev/null || true)"
    [ -n "$dev" ] && [ "$(stat -c '%d' "$PANEL" 2>/dev/null || true)" = "$dev" ]
}

preflight_anchors() {
    local d
    for d in "$PANEL" "$PANEL/resources" "$PANEL/resources/views" \
        "$PANEL/resources/views/templates" "$PANEL/public"; do
        if [ -L "$d" ] || [ ! -d "$d" ]; then
            return 1
        fi
    done
    if [ -L "$PANEL/resources/views/layouts" ]; then
        return 1
    fi
    if [ -e "$PANEL/resources/views/layouts" ] && [ ! -d "$PANEL/resources/views/layouts" ]; then
        return 1
    fi
    if [ -L "$PANEL/public/themes" ]; then
        return 1
    fi
    if [ -e "$PANEL/public/themes" ] && [ ! -d "$PANEL/public/themes" ]; then
        return 1
    fi
    anchor_ready "$PANEL/public" || return 1
    anchor_ready "$PANEL/resources/views/templates" || return 1
    anchor_ready "$PANEL" || return 1
    return 0
}

# chown -h, danach erneut pruefen, erst dann chmod. chmod folgt dem letzten Glied.
claim_dir() {
    local path="$1" create="${2:-0}"
    if [ -L "$path" ]; then
        die "Verzeichnis ist ein Symlink und wird nicht angefasst: $(sanitize_text "$path")"
    fi
    if [ -e "$path" ] && [ ! -d "$path" ]; then
        die "Pfad ist kein Verzeichnis: $(sanitize_text "$path")"
    fi
    if [ ! -e "$path" ]; then
        [ "$create" = "1" ] || die "Verzeichnis fehlt: $(sanitize_text "$path")"
        [ "$DRY_RUN" = "1" ] && return 0
        mkdir -m 0755 -- "$path" || die "Verzeichnis konnte nicht angelegt werden: $(sanitize_text "$path")"
    fi
    if [ -L "$path" ] || [ ! -d "$path" ]; then
        die "Verzeichnis ist ein Symlink und wird nicht angefasst: $(sanitize_text "$path")"
    fi
    [ "$DRY_RUN" = "1" ] && return 0
    if [ "$(id -u)" = "0" ]; then
        chown -h root:root -- "$path" || die "Besitzer konnte nicht gesetzt werden: $(sanitize_text "$path")"
    fi
    if [ -L "$path" ] || [ ! -d "$path" ]; then
        die "Verzeichnis wurde waehrend des Siegelns ersetzt: $(sanitize_text "$path")"
    fi
    chmod 0755 -- "$path" || die "Rechte konnten nicht gesetzt werden: $(sanitize_text "$path")"
    if [ -L "$path" ] || [ ! -d "$path" ]; then
        die "Verzeichnis wurde waehrend des Siegelns ersetzt: $(sanitize_text "$path")"
    fi
    if [ "$(id -u)" = "0" ]; then
        [ "$(stat -c '%u' "$path")" = "0" ] || die "Verzeichnis gehoert nach dem Siegeln nicht root: $(sanitize_text "$path")"
    fi
    if mode_go_writable "$(stat -c '%a' "$path")"; then
        die "Verzeichnis ist nach dem Siegeln noch beschreibbar: $(sanitize_text "$path")"
    fi
}

# Urspruenglichen Besitzer merken, bevor das Siegel root:root 0755 setzt.
remember_dir() {
    local path="$1"
    [ -d "$path" ] && [ ! -L "$path" ] || return 0
    SEAL_PATHS+=("$path")
    SEAL_UIDS+=("$(stat -c '%u' "$path")")
    SEAL_GIDS+=("$(stat -c '%g' "$path")")
    SEAL_MODES+=("$(stat -c '%a' "$path")")
}

# Von unten nach oben: erst chmod, dann chown -h. Der Parent gehoert dabei
# noch root, www-data kann den Eintrag also nicht dazwischen tauschen.
restore_sealed_dirs() {
    local i path mode uid gid n
    n="${#SEAL_PATHS[@]}"
    [ "$n" -gt 0 ] || return 0
    for (( i=n-1; i>=0; i-- )); do
        path="${SEAL_PATHS[$i]}"
        mode="${SEAL_MODES[$i]}"
        uid="${SEAL_UIDS[$i]}"
        gid="${SEAL_GIDS[$i]}"
        if [ -L "$path" ] || [ ! -d "$path" ]; then
            warn "Verzeichnis nicht wiederhergestellt (kein echtes Verzeichnis): $(sanitize_text "$path")"
            continue
        fi
        chmod "$mode" -- "$path" || warn "chmod fehlgeschlagen: $(sanitize_text "$path")"
        if [ -L "$path" ] || [ ! -d "$path" ]; then
            warn "Verzeichnis wurde vor dem chown ersetzt: $(sanitize_text "$path")"
            continue
        fi
        if [ "$(id -u)" = "0" ]; then
            chown -h "$uid:$gid" -- "$path" || warn "chown fehlgeschlagen: $(sanitize_text "$path")"
        fi
    done
    SEAL_PATHS=()
    SEAL_UIDS=()
    SEAL_GIDS=()
    SEAL_MODES=()
}

finish_exit() {
    local rc=$?
    set +e
    restore_sealed_dirs
    cleanup_source
    exit "$rc"
}

# Bei jedem Install, Update, Uninstall und Restore. Pterodactyl-Upgrades setzen
# chown -R www-data auf den Baum; www-data koennte sonst resources oder public
# gegen einen Symlink tauschen. storage und bootstrap/cache bleiben unberuehrt.
# Nach dem Lauf stellt der Exit-Trap Besitzer, Gruppe und Modus wieder her,
# damit php artisan p:upgrade nicht root als Besitzer uebernimmt.
prepare_panel_writes() {
    require_python3
    [ -n "${PANEL:-}" ] || die "Panel-Pfad fehlt."
    if [ ! -d "$PANEL" ] || [ -L "$PANEL" ]; then
        die "Panel-Pfad ist kein Verzeichnis."
    fi
    preflight_anchors || die "Keine sichere Zwischenablage auf demselben Dateisystem. Abbruch vor der ersten Aenderung."
    if [ "${#SEAL_PATHS[@]}" -eq 0 ]; then
        remember_dir "$PANEL"
        remember_dir "$PANEL/resources"
        remember_dir "$PANEL/resources/views"
        remember_dir "$PANEL/resources/views/templates"
        remember_dir "$PANEL/resources/views/layouts"
        remember_dir "$PANEL/public"
        remember_dir "$PANEL/public/themes"
    fi
    if [ "${PTD_SELFTEST:-}" != "1" ]; then
        trap finish_exit EXIT
    fi
    claim_dir "$PANEL" 0
    claim_dir "$PANEL/resources" 0
    claim_dir "$PANEL/resources/views" 0
    claim_dir "$PANEL/resources/views/templates" 0
    claim_dir "$PANEL/resources/views/layouts" 1
    claim_dir "$PANEL/public" 0
    claim_dir "$PANEL/public/themes" 1
    if [ "$DRY_RUN" = "1" ]; then
        return 0
    fi
    anchor_ready "$PANEL/public/themes" || die "Zwischenablage nach dem Siegeln nicht verfuegbar. Es wurden noch keine Theme-Dateien geschrieben."
    anchor_ready "$PANEL/resources/views/templates" || die "Zwischenablage nach dem Siegeln nicht verfuegbar. Es wurden noch keine Theme-Dateien geschrieben."
    anchor_ready "$PANEL" || die "Zwischenablage nach dem Siegeln nicht verfuegbar. Es wurden noch keine Theme-Dateien geschrieben."
}

# Temporaere Arbeit nur unter einem existierenden Elternverzeichnis.
# Als root muss dieses root gehoeren.
private_workdir() {
    local d parent
    d="$(mktemp -d)"
    if [ -z "$d" ] || [ -L "$d" ] || [ ! -d "$d" ]; then
        die "Temporaeres Verzeichnis unsicher."
    fi
    chmod 700 "$d" || { rm -rf -- "$d"; die "Temporaeres Verzeichnis nicht schuetzbar."; }
    parent="$(dirname "$d")"
    if [ "$(id -u)" = "0" ]; then
        if [ -L "$parent" ] || [ "$(stat -c '%u' "$parent" 2>/dev/null || echo '')" != "0" ]; then
            rm -rf -- "$d"
            die "Build-Verzeichnis liegt nicht unter einem root-eigenen Elternverzeichnis."
        fi
    fi
    printf '%s\n' "$d"
}

# Veroeffentlichen per renameat. Schlaegt die Elternpruefung fehl, bleibt die
# Zwischenablage liegen und das Ziel wird nicht angefasst.
publish_file() {
    local staged="$1" dest="$2" rel="$3" dir real
    dir="$(dirname "$dest")"
    if ! require_same_device "$(dirname "$staged")" "$dir"; then
        return 1
    fi
    if [ -L "$dest" ]; then
        return 1
    fi
    if ! parent_still_real "$dest" "$rel"; then
        return 1
    fi
    if ! fd_py publish-file "$PANEL" "$rel" "$staged"; then
        return 1
    fi
    if ! regular_file "$dest"; then
        return 1
    fi
    real="$(realpath -e "$dest" 2>/dev/null || true)"
    if ! under_panel "$real" || ! path_is_confined "$rel"; then
        return 1
    fi
    return 0
}

# Leeres Verzeichnis per rename. Bei Fehler wird das Ziel nicht entfernt.
publish_tree_dir() {
    local staged="$1" dest="$2" rel="$3" dir
    dir="$(dirname "$dest")"
    if ! require_same_device "$staged" "$dir"; then
        return 1
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        return 1
    fi
    if ! parent_still_real "$dest" "$rel"; then
        return 1
    fi
    if ! fd_py publish-dir "$PANEL" "$rel" "$staged"; then
        return 1
    fi
    if ! path_is_confined "$rel" || ! real_dir "$dest"; then
        return 1
    fi
    return 0
}

# Inhalt entsteht in einer 0700-Zwischenablage ausserhalb des Web-Verzeichnisses.
# Danach genau ein mv -T ins Panel.
stage_file_into() {
    local dest="$1" srcf="$2" mode="$3" rel="$4" dir stage tmp
    dir="$(dirname "$dest")"
    real_dir "$dir" || die "Zielverzeichnis fehlt oder ist ein Symlink."
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "Ungueltiger Dateimodus."
    stage="$(open_private_stage "$dir")"
    tmp="$stage/file"
    if ! cp -- "$srcf" "$tmp"; then
        close_private_stage "$stage"
        die "Kopieren fehlgeschlagen."
    fi
    chmod "$mode" "$tmp" || { close_private_stage "$stage"; die "chmod fehlgeschlagen."; }
    if [ "$(id -u)" = "0" ]; then
        # Immer root. Nie den Besitzer der Zieldatei uebernehmen: der folgt sonst
        # einem von www-data getauschten Verzeichnis in ein fremdes Root-Ziel.
        chown -h root:root -- "$tmp" || { close_private_stage "$stage"; die "Besitzer konnte nicht gesetzt werden."; }
    fi
    if ! require_same_device "$stage" "$dir"; then
        close_private_stage "$stage"
        die "Zwischenablage und Ziel liegen auf verschiedenen Dateisystemen."
    fi
    if ! parent_still_real "$dest" "$rel" || [ -L "$dest" ]; then
        close_private_stage "$stage"
        die "Zielverzeichnis wurde waehrend des Schreibens ersetzt."
    fi
    if ! publish_file "$tmp" "$dest" "$rel"; then
        close_private_stage "$stage"
        die "Schreiben fehlgeschlagen: $rel"
    fi
    close_private_stage "$stage"
}

# Schreibt nur ueber eine Zwischenablage und ersetzt den Zieleintrag per rename.
safe_install_file() {
    local dest="$1" srcf="$2" rel dir parent_rel mode
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
    mode="${3:-644}"
    stage_file_into "$dest" "$srcf" "$mode" "$rel"
}

safe_replace_file() {
    local dest="$1" srcf="$2" rel dir mode
    rel="${dest#"$PANEL"/}"
    [ "$dest" = "$PANEL/$rel" ] || die "Ziel ausserhalb des Panels."
    require_confined "$rel"
    regular_file "$dest" || die "Zieldatei fehlt oder ist ein Symlink: $rel"
    dir="$(dirname "$dest")"
    real_dir "$dir" || die "Zielverzeichnis fehlt oder ist ein Symlink."
    mode="$(stat -c '%a' "$dest" 2>/dev/null || echo 644)"
    mode="$(mask_blade_mode "$mode")"
    stage_file_into "$dest" "$srcf" "$mode" "$rel"
}

# Alte Blade-Modi duerfen setuid, Gruppen- und Fremdschreiben nicht behalten.
mask_blade_mode() {
    local mode="$1"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || mode="644"
    printf '%o' $((8#$mode & 0644))
}

# Entfernt nur, wenn die Elternkette unmittelbar davor noch echt ist.
# Sonst Rueckgabe 1, ohne das Ziel anzufassen.
discard_panel_path() {
    local target="$1" rel="$2"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
    fi
    if ! parent_still_real "$target" "$rel"; then
        return 1
    fi
    path_is_confined "$rel" || return 1
    if [ -L "$target" ]; then
        :
    elif [ -d "$target" ]; then
        real_dir "$target" || return 1
    else
        regular_file "$target" || return 1
    fi
    parent_still_real "$target" "$rel" || return 1
    fd_py unlink "$PANEL" "$rel"
}

safe_reset_theme_dir() {
    local parent_rel="public/themes" target="$PANEL/$THEME_REL" stage newdir
    require_confined "$parent_rel"
    real_dir "$PANEL/$parent_rel" || die "public/themes fehlt oder ist ein Symlink."
    if [ -e "$target" ] || [ -L "$target" ]; then
        discard_panel_path "$target" "$THEME_REL" || die "Theme-Verzeichnis konnte nicht sicher entfernt werden."
    fi
    stage="$(open_private_stage "$PANEL/$parent_rel")"
    newdir="$stage/$THEME_SLUG"
    mkdir -- "$newdir"
    chmod 755 "$newdir" || { close_private_stage "$stage"; die "chmod fehlgeschlagen."; }
    if [ "$(id -u)" = "0" ]; then
        chown -h root:root "$newdir" || { close_private_stage "$stage"; die "Besitzer konnte nicht gesetzt werden."; }
    fi
    if ! parent_still_real "$target" "$THEME_REL" || ! path_is_confined "$parent_rel"; then
        close_private_stage "$stage"
        die "public/themes wurde waehrend der Installation zu einem Symlink."
    fi
    if ! require_same_device "$stage" "$PANEL/$parent_rel"; then
        close_private_stage "$stage"
        die "Zwischenablage und Ziel liegen auf verschiedenen Dateisystemen."
    fi
    if ! publish_tree_dir "$newdir" "$target" "$THEME_REL"; then
        close_private_stage "$stage"
        die "Theme-Verzeichnis liegt ausserhalb des Panels oder ist ein Symlink."
    fi
    close_private_stage "$stage"
}

known_asset_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    case "$1" in
        nebula*.css|nebula*.js|theme.json|ASSET_VERSION) return 0 ;;
        *) return 1 ;;
    esac
}

install_built_assets() {
    local build_dir="$1" f base target found=0
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
    # Modus und Besitzer stehen schon an der Zwischenablage (root:root, 0644).
    # Danach kein weiterer Besitzer- oder Rechtewechsel auf dem Panel-Pfad:
    # www-data kann public/themes dazwischen gegen einen Symlink tauschen.
}

remove_theme_dir() {
    local parent_rel="public/themes" target="$PANEL/$THEME_REL"
    if [ ! -e "$PANEL/$parent_rel" ] && [ ! -L "$PANEL/$parent_rel" ]; then
        return 0
    fi
    require_confined "$parent_rel"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
    fi
    discard_panel_path "$target" "$THEME_REL" || die "Theme-Verzeichnis konnte nicht sicher entfernt werden."
}

remove_state_file() {
    local dest="$PANEL/$STATE_FILE"
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        return 0
    fi
    discard_panel_path "$dest" "$STATE_FILE" || die "Zustandsdatei konnte nicht sicher entfernt werden."
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
# Root fuehrt die Kopie spaeter aus. Fremde Besitzer oder beschreibbare
# Dateien werden abgelehnt, statt nach /usr/local/lib uebernommen.
tree_owned_by_root() {
    local root="$1" f uid mode gw ow
    [ -d "$root" ] && [ ! -L "$root" ] || return 1
    while IFS= read -r -d '' f; do
        if [ -L "$f" ]; then
            return 1
        fi
        uid="$(stat -c '%u' "$f" 2>/dev/null || echo '')"
        [ "$uid" = "0" ] || return 1
        mode="$(stat -c '%a' "$f" 2>/dev/null || echo '')"
        [ "${#mode}" -ge 3 ] || return 1
        gw="${mode: -2:1}"
        ow="${mode: -1}"
        case "$gw" in 2|3|6|7) return 1 ;; esac
        case "$ow" in 2|3|6|7) return 1 ;; esac
    done < <(find -P "$root" -print0)
    return 0
}

swap_lib_dir() {
    local src="$1" parent stage old src_real lib_real script
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
    real_dir "$parent" || die "CLI-Elternverzeichnis fehlt."
    if [ "$(id -u)" = "0" ]; then
        [ "$(stat -c '%u' "$parent")" = "0" ] || die "CLI-Elternverzeichnis gehoert nicht root."
        tree_owned_by_root "$src" || die "Lokale Quelle gehoert nicht root oder ist beschreibbar. Vorher: chown -R root:root <quelle>"
    fi
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
    for script in "$stage/scripts/"*.sh; do
        [ -f "$script" ] || { rm -rf "$stage"; die "CLI-Skript fehlt."; }
        if ! chmod +x "$script"; then
            rm -rf "$stage"
            die "CLI-Rechte konnten nicht gesetzt werden."
        fi
    done
    old=""
    real_dir "$parent" || { rm -rf -- "$stage"; die "CLI-Elternverzeichnis unsicher."; }
    if [ -e "$LIB_DIR" ] || [ -L "$LIB_DIR" ]; then
        old="$(mktemp -d "$parent/.nebula-old.XXXXXX")"
        chmod 700 "$old" || { rm -rf -- "$stage" "$old"; die "Zwischenname nicht schuetzbar."; }
        rmdir -- "$old" || { rm -rf -- "$stage"; die "Zwischenname nicht frei."; }
        real_dir "$parent" || { rm -rf -- "$stage"; die "CLI-Elternverzeichnis unsicher."; }
        if ! fd_py rename-into "$parent" "$(basename "$old")" "$LIB_DIR"; then
            rm -rf -- "$stage"
            die "CLI-Verzeichnis konnte nicht beiseitegelegt werden."
        fi
    fi
    real_dir "$parent" || {
        if [ -n "$old" ] && [ -e "$old" ]; then
            fd_py rename-into "$parent" "$(basename "$LIB_DIR")" "$old" || true
        fi
        rm -rf -- "$stage"
        die "CLI-Elternverzeichnis unsicher."
    }
    if ! fd_py rename-into "$parent" "$(basename "$LIB_DIR")" "$stage"; then
        rm -rf -- "$stage"
        if [ -n "$old" ] && [ -e "$old" ]; then
            if ! fd_py rename-into "$parent" "$(basename "$LIB_DIR")" "$old"; then
                die "Rollback des CLI-Verzeichnisses fehlgeschlagen. Altbestand: $old"
            fi
        fi
        die "CLI-Verzeichnis konnte nicht ersetzt werden."
    fi
    if [ -n "$old" ] && [ -e "$old" ]; then
        rm -rf -- "$old"
    fi
    real_dir "$parent" || die "CLI-Verzeichnis unsicher."
    real_dir "$LIB_DIR" || die "CLI-Verzeichnis unsicher."
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
    local private archive_tmp
    private="$(private_workdir)"
    if ! snapshot_panel_files "$private" "${files[@]}"; then
        rm -rf -- "$private"
        die "Backup-Quelle wurde ersetzt oder ist unsicher."
    fi
    real_dir "$BACKUP_ROOT" || { rm -rf -- "$private"; die "Backup-Verzeichnis unsicher."; }
    if [ "$(id -u)" = "0" ]; then
        [ "$(stat -c '%u' "$BACKUP_ROOT")" = "0" ] || { rm -rf -- "$private"; die "Backup-Verzeichnis gehoert nicht root."; }
    fi
    archive_tmp="$(mktemp "$BACKUP_ROOT/.nebula-bak.XXXXXX")"
    if ! tar czf "$archive_tmp" -C "$private" "${files[@]}"; then
        rm -f -- "$archive_tmp"
        rm -rf -- "$private"
        die "Backup konnte nicht gepackt werden."
    fi
    rm -rf -- "$private"
    chmod 600 "$archive_tmp"
    if [ "$(id -u)" = "0" ]; then
        chown root:root "$archive_tmp"
    fi
    real_dir "$BACKUP_ROOT" || { rm -f -- "$archive_tmp"; die "Backup-Verzeichnis unsicher."; }
    if [ -L "$BACKUP_ROOT/latest" ]; then
        rm -f -- "$archive_tmp"
        die "Backup-Zeiger ist ein Symlink."
    fi
    fd_py rename-into "$BACKUP_ROOT" "$(basename "$archive")" "$archive_tmp" \
        || { rm -f -- "$archive_tmp"; die "Backup konnte nicht abgelegt werden."; }
    printf '%s\n' "$archive" > "$BACKUP_ROOT/latest"
    chmod 600 "$BACKUP_ROOT/latest"
    ok "Backup: $(sanitize_text "$archive")"
}

# Kopiert nur gepruefte regulaere Dateien. tar liest danach diese Kopie,
# nicht den von www-data beschreibbaren Panel-Baum.
snapshot_owner_spec() {
    local spec uid
    spec="$(id -u),0"
    if [ -d "$PANEL/storage" ] && [ ! -L "$PANEL/storage" ]; then
        uid="$(stat -c '%u' "$PANEL/storage" 2>/dev/null || true)"
        if [ -n "$uid" ]; then
            spec="$spec,$uid"
        fi
    fi
    printf '%s' "$spec"
}

snapshot_panel_files() {
    local dest_root="$1" rel src
    shift
    for rel in "$@"; do
        [ -n "$rel" ] || return 1
        src="$PANEL/$rel"
        path_is_confined "$rel" || return 1
        parent_still_real "$src" "$rel" || return 1
        if [ -d "$src" ] && [ ! -L "$src" ]; then
            real_dir "$src" || return 1
        else
            regular_file "$src" || return 1
        fi
        parent_still_real "$src" "$rel" || return 1
        fd_py snapshot "$PANEL" "$rel" "$dest_root" "$(snapshot_owner_spec)" || return 1
    done
    return 0
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
    prepare_panel_writes
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
    restore_sealed_dirs
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
    regular_file "$PANEL/artisan" || { warn "artisan ist kein regulaeres File – view:clear uebersprungen."; return 0; }
    # Eigenes Pseudoterminal: der Web-Benutzer erbt nicht das TTY von root.
    if runuser --pty -u "$user" -- "$php" "$PANEL/artisan" view:clear >/dev/null 2>&1; then
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
    local tmp tag sum
    tag=""
    sum=""
    if [ "${TAG_REQUESTED:-0}" = "1" ]; then
        tag="$(json_escape "$BRANCH")"
    fi
    if [ -n "$CHECKSUM" ]; then
        sum="$(json_escape "$(printf '%s' "$CHECKSUM" | tr 'A-F' 'a-f')")"
    fi
    tmp="$(mktemp)"
    cat > "$tmp" <<JSON
{
  "theme": "Nebula",
  "slug": "nebula",
  "version": "${ver}",
  "asset_version": "${asset}",
  "branch": "${branch}",
  "tag": "${tag}",
  "checksum": "${sum}",
  "installed_at": "${now}",
  "panel_version": "${pv}",
  "files": ["resources/views/templates/wrapper.blade.php", "resources/views/layouts/admin.blade.php", "public/themes/nebula"]
}
JSON
    safe_install_file "$PANEL/$STATE_FILE" "$tmp" 600
    rm -f "$tmp"
}

read_state() {
    local key val
    regular_file "$PANEL/$STATE_FILE" || return 1
    key="$1"
    [[ "$key" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    val="$(sed -n "s/.*\"${key}\": *\"\([^\"]*\)\".*/\1/p" "$PANEL/$STATE_FILE" | head -n1 || true)"
    sanitize_text "$val"
}

# -----------------------------------------------------------------------------
# CLI-Helfer
# -----------------------------------------------------------------------------
# Flags, die nebula update wieder an den Installer gibt. Leer, wenn nicht gesetzt.
cli_pin_args() {
    if [ "${TAG_REQUESTED:-0}" = "1" ]; then
        printf '%s\n' --tag
        printf '%s\n' "$BRANCH"
    elif [ "${BRANCH_REQUESTED:-0}" = "1" ]; then
        printf '%s\n' --branch
        printf '%s\n' "$BRANCH"
    fi
    # Summe ohne feste Ref wuerde jedes spaetere Update unbrauchbar machen.
    if [ -n "${CHECKSUM:-}" ] && { [ "${TAG_REQUESTED:-0}" = "1" ] || [ "${BRANCH_REQUESTED:-0}" = "1" ]; }; then
        printf '%s\n' --checksum
        printf '%s\n' "$(printf '%s' "$CHECKSUM" | tr 'A-F' 'a-f')"
    fi
}

install_cli() {
    [ "$DO_CLI" = "1" ] || return 0
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry-run]%s CLI nach %s installieren\n' "$C_DIM" "$C_RESET" "$CLI_PATH"
        return 0
    fi
    swap_lib_dir "$SRC"

    local qlib qpanel clitemp pin_ref="" pin_sum="" qref qsum
    printf -v qlib '%q' "$LIB_DIR"
    printf -v qpanel '%q' "$PANEL"
    if [ "${TAG_REQUESTED:-0}" = "1" ]; then
        printf -v qref '%q' "$BRANCH"
        pin_ref="--tag $qref"
    elif [ "${BRANCH_REQUESTED:-0}" = "1" ]; then
        printf -v qref '%q' "$BRANCH"
        pin_ref="--branch $qref"
    fi
    if [ -n "${CHECKSUM:-}" ] && [ -n "$pin_ref" ]; then
        printf -v qsum '%q' "$(printf '%s' "$CHECKSUM" | tr 'A-F' 'a-f')"
        pin_sum="--checksum $qsum"
    fi
    clitemp="$(mktemp "$(dirname "$CLI_PATH")/.nebula-cli.XXXXXX")"
    cat > "$clitemp" <<CLI
#!/usr/bin/env bash
# Nebula Theme – Verwaltungsbefehl
set -euo pipefail
LIB=$qlib
PANEL_ARG=(--path $qpanel)
case "\${1:-help}" in
    install)   shift; exec bash "\$LIB/install.sh" --install   "\${PANEL_ARG[@]}" $pin_ref $pin_sum "\$@" ;;
    update)    shift; exec bash "\$LIB/install.sh" --update    "\${PANEL_ARG[@]}" $pin_ref $pin_sum "\$@" ;;
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
    real_dir "$(dirname "$CLI_PATH")" || die "CLI-Verzeichnis fehlt."
    if [ "$(id -u)" = "0" ]; then
        [ "$(stat -c '%u' "$(dirname "$CLI_PATH")")" = "0" ] || die "CLI-Verzeichnis gehoert nicht root."
    fi
    real_dir "$(dirname "$CLI_PATH")" || die "CLI-Verzeichnis unsicher."
    fd_py rename-into "$(dirname "$CLI_PATH")" "$(basename "$CLI_PATH")" "$clitemp" \
        || die "CLI-Befehl konnte nicht ersetzt werden."
    ok "Befehl installiert: ${C_B}nebula${C_RESET}"
}

# -----------------------------------------------------------------------------
# Installation
# -----------------------------------------------------------------------------
do_install() {
    step "1/6  Panel pruefen"
    local pv
    pv="$(panel_version)"
    info "Pfad:    $(sanitize_text "$PANEL")"
    info "Version: $(sanitize_text "${pv:-unbekannt}")"
    info "Web-User: $(sanitize_text "$(web_user)"):$(sanitize_text "$(web_group)")"

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

    confirm "Nebula in '$(sanitize_text "$PANEL")' installieren?" || { info "Abgebrochen."; exit 0; }
    prepare_panel_writes

    step "2/6  Backup anlegen"
    make_backup

    step "3/6  Theme bauen"
    local build_dir asset
    build_dir="$(private_workdir)"
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
    restore_sealed_dirs

    printf '\n  %s%s ist aktiv.%s\n\n' "$C_OK$C_B" "$THEME_NAME" "$C_RESET"
    printf '  %sStrg + K%s          Befehlspalette – Server suchen, Aktionen ausloesen\n' "$C_B" "$C_RESET"
    printf '  %sStrg + B%s          Seitenschiene ein- und ausklappen\n' "$C_B" "$C_RESET"
    printf '  %sStrg + Umschalt+D%s Mini-Konsole (bleibt beim Reiterwechsel offen)\n' "$C_B" "$C_RESET"
    printf '  %sStrg + /%s          Alle Tastenkuerzel\n' "$C_B" "$C_RESET"
    printf '  %sZahnrad%s           Unten rechts: Farben, Layout, Module, Warnregeln\n' "$C_B" "$C_RESET"
    printf '\n  %sBrowser-Cache leeren bzw. mit Strg+F5 neu laden.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sEntfernen jederzeit mit:%s nebula uninstall\n\n' "$C_DIM" "$C_RESET"
}

remove_lib_dir() {
    local parent
    parent="$(dirname "$LIB_DIR")"
    real_dir "$parent" || die "CLI-Elternverzeichnis unsicher."
    if [ "$(id -u)" = "0" ]; then
        [ "$(stat -c '%u' "$parent")" = "0" ] || die "CLI-Elternverzeichnis gehoert nicht root."
    fi
    if [ ! -e "$LIB_DIR" ] && [ ! -L "$LIB_DIR" ]; then
        return 0
    fi
    real_dir "$parent" || die "CLI-Elternverzeichnis unsicher."
    if [ -L "$LIB_DIR" ]; then
        fd_py unlink-child "$parent" "$(basename "$LIB_DIR")" || die "CLI-Symlink konnte nicht entfernt werden."
        return 0
    fi
    real_dir "$LIB_DIR" || die "CLI-Verzeichnis ist kein echtes Verzeichnis."
    real_dir "$parent" || die "CLI-Elternverzeichnis unsicher."
    fd_py unlink-child "$parent" "$(basename "$LIB_DIR")" || die "CLI-Verzeichnis konnte nicht entfernt werden."
}

# -----------------------------------------------------------------------------
# Deinstallation
# -----------------------------------------------------------------------------
do_uninstall() {
    step "Nebula entfernen"
    info "Panel: $(sanitize_text "$PANEL")"
    confirm "Theme aus '$(sanitize_text "$PANEL")' entfernen?" || { info "Abgebrochen."; exit 0; }
    prepare_panel_writes

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
        real_dir "$(dirname "$CLI_PATH")" || die "CLI-Verzeichnis unsicher."
        rm -f -- "$CLI_PATH"
        remove_lib_dir
    fi

    restore_sealed_dirs
    printf '\n  %sNebula-Dateien sind entfernt.%s\n' "$C_OK" "$C_RESET"
    printf '  Besitzer, Gruppe und Rechte der Verzeichnisse sind wieder wie vor diesem Lauf.\n'
    printf '  storage/ und bootstrap/cache wurden nicht angefasst.\n'
    printf '  %sPanel-Upgrade:%s php artisan p:upgrade --user=www-data --group=www-data\n' "$C_DIM" "$C_RESET"
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
    info "Panel:          $(sanitize_text "$PANEL")"
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
        info "Letztes Backup: $(sanitize_text "$(head -n 1 "$BACKUP_ROOT/latest" 2>/dev/null || true)")"
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
require_python3
trap finish_exit EXIT

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
