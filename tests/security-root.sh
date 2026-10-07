#!/usr/bin/env bash
# Laeuft als root: Besitzer-Wiederherstellung, fremde UID, renameat2-Rennen.
set -euo pipefail
[ "$(id -u)" = "0" ] || { printf 'FAIL not root\n' >&2; exit 1; }

ROOT="${1:?}"
export PTD_SELFTEST=1
set --
# shellcheck disable=SC1091
source "$ROOT/install.sh"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

as_www() {
    if command -v runuser >/dev/null 2>&1; then
        runuser -u www-data -- "$@"
    else
        sudo -n -u www-data -- "$@"
    fi
}

tmp="$(mktemp -d)"
export PTD_SEAL_JOURNAL="$tmp/seal.journal"
race_pid=""
cleanup() {
    if [ -n "$race_pid" ]; then
        kill "$race_pid" 2>/dev/null || true
        wait "$race_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT

panel="$tmp/panel"
mkdir -p "$panel/resources/views/templates" "$panel/resources/views/layouts" \
    "$panel/public/themes" "$panel/storage" "$panel/bootstrap/cache"
printf 'x\n' > "$panel/artisan"
chmod 751 "$panel/resources"
chmod 750 "$panel/public"
chown root:www-data "$panel/public"
printf 'SECRET\n' > "$panel/.env"
chown root:www-data "$panel/.env"
chmod 640 "$panel/.env"
gid="$(id -g www-data)"
PANEL="$panel"
prepare_panel_writes >/dev/null
[ "$(stat -c '%a' "$panel/public")" = "755" ] || fail "seal mode $(stat -c '%a' "$panel/public")"
[ "$(stat -c '%u' "$panel/public")" = "0" ] || fail "seal uid"
[ -f "$PTD_SEAL_JOURNAL" ] || fail "seal journal was not written"
# Naechster Lauf ohne Speicher: nur das Protokoll setzt Besitzer und Modus zurueck.
SEAL_RELS=()
SEAL_DEVS=()
SEAL_INOS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
recover_seal_journal
[ ! -e "$PTD_SEAL_JOURNAL" ] || fail "seal journal survived recovery"
[ "$(stat -c '%a' "$panel/public")" = "750" ] || fail "public mode $(stat -c '%a' "$panel/public")"
[ "$(stat -c '%u:%g' "$panel/public")" = "0:$gid" ] || fail "public owner $(stat -c '%u:%g' "$panel/public")"
[ "$(stat -c '%a' "$panel/resources")" = "751" ] || fail "resources mode $(stat -c '%a' "$panel/resources")"
[ "$(stat -c '%a' "$panel/.env")" = "640" ] || fail ".env mode $(stat -c '%a' "$panel/.env")"
if su -s /bin/sh nobody -c "test -r $(printf '%q' "$panel/.env")"; then
    fail ".env is readable by nobody"
fi

printf 'blade\n' > "$panel/$WRAPPER_REL"
chown "$(id -u nobody):$(id -g nobody)" "$panel/$WRAPPER_REL"
uid_err="$(snapshot_panel_files "$tmp/snap-uid" "$WRAPPER_REL" 2>&1 || true)"
printf '%s\n' "$uid_err" | grep -q uid || fail "foreign uid snapshot accepted: $uid_err"
rm -f "$panel/$WRAPPER_REL"
printf 'blade\n' > "$panel/$WRAPPER_REL"
chown root:root "$panel/$WRAPPER_REL"
ln "$panel/$WRAPPER_REL" "$tmp/hl-extra"
hl_err="$(snapshot_panel_files "$tmp/snap-hl" "$WRAPPER_REL" 2>&1 || true)"
printf '%s\n' "$hl_err" | grep -q hardlink || fail "hardlink snapshot accepted: $hl_err"
rm -f "$tmp/hl-extra"
chown www-data:www-data "$panel/$WRAPPER_REL" "$panel/storage"
mkdir -p "$tmp/snap-ok"
snapshot_panel_files "$tmp/snap-ok" "$WRAPPER_REL" || fail "www-data blade rejected"
grep -qx 'blade' "$tmp/snap-ok/$WRAPPER_REL" || fail "snapshot missed blade"

# --no-cli darf eine nicht-root-eigene Quelle nicht bauen.
l3="$(env -u PTD_SELFTEST timeout 20 bash "$ROOT/install.sh" --no-cli --yes --path "$tmp/not-a-panel" </dev/null 2>&1 || true)"
printf '%s\n' "$l3" | grep -q 'gehoert nicht root' || fail "no-cli accepted a user-owned source: $l3"

# Positiver Tausch, solange public noch www-data gehoert. Danach das Siegel.
chmod 755 "$tmp" "$panel"
mkdir -p "$panel/public/themes" "$panel/public/themes-decoy"
printf 'real\n' > "$panel/public/themes/marker"
printf 'decoy\n' > "$panel/public/themes-decoy/marker"
chown -R www-data:www-data "$panel/public"
chmod 755 "$panel/public" "$panel/public/themes" "$panel/public/themes-decoy"
cat > "$tmp/race.py" <<'PY'
import ctypes
import sys
import time

libc = ctypes.CDLL(None, use_errno=True)
libc.renameat2.argtypes = [
    ctypes.c_int, ctypes.c_char_p,
    ctypes.c_int, ctypes.c_char_p,
    ctypes.c_uint,
]
libc.renameat2.restype = ctypes.c_int
AT_FDCWD = -100
EXCHANGE = 2


def once():
    ctypes.set_errno(0)
    rc = libc.renameat2(AT_FDCWD, b"themes", AT_FDCWD, b"themes-decoy", EXCHANGE)
    return rc, ctypes.get_errno()


if sys.argv[1] == "once":
    rc, err = once()
    if rc != 0:
        sys.stderr.write("exchange failed %s\n" % err)
        raise SystemExit(1)
    rc, err = once()
    if rc != 0:
        sys.stderr.write("swap-back failed %s\n" % err)
        raise SystemExit(1)
    sys.stdout.write("ok\n")
else:
    end = time.time() + 1.5
    ok = eperm = other = 0
    while time.time() < end:
        rc, err = once()
        if rc == 0:
            ok += 1
            once()
        elif err in (1, 13):
            eperm += 1
        else:
            other += 1
    sys.stdout.write("%s %s %s\n" % (ok, eperm, other))
PY
chmod 755 "$tmp/race.py"
# shellcheck disable=SC2016 # $1/$2 gehoeren zum inneren bash -c.
as_www bash -c 'cd "$1" && exec /usr/bin/python3 "$2" once' bash "$panel/public" "$tmp/race.py" \
    >/dev/null || fail "unsealed renameat2 exchange failed"
grep -qx 'real' "$panel/public/themes/marker" || fail "positive exchange did not swap back"

PANEL="$panel"
prepare_panel_writes >/dev/null
themes_ino="$(stat -c '%i' "$panel/public/themes")"
# shellcheck disable=SC2016 # $1/$2 gehoeren zum inneren bash -c.
as_www bash -c 'cd "$1" && exec /usr/bin/python3 "$2" loop' bash "$panel/public" "$tmp/race.py" \
    >"$tmp/race.out" 2>"$tmp/race.err" &
race_pid=$!
printf 'payload\n' > "$tmp/payload"
fd_py publish-file "$panel" "public/themes/payload.txt" "$tmp/payload"
wait "$race_pid"
race_pid=""
read -r ok_n eperm_n other_n < "$tmp/race.out"
[ "$ok_n" = "0" ] || fail "sealed exchange succeeded $ok_n times ($(cat "$tmp/race.err" 2>/dev/null || true))"
[ "$eperm_n" -gt 0 ] || fail "sealed exchange produced no EPERM (other=$other_n err=$(cat "$tmp/race.err" 2>/dev/null || true))"
[ "$(stat -c '%i' "$panel/public/themes")" = "$themes_ino" ] || fail "themes inode changed during the race"
grep -qx 'payload' "$panel/public/themes/payload.txt" || fail "payload missed the real themes directory"
[ ! -e "$panel/public/themes-decoy/payload.txt" ] || fail "payload landed in the decoy"
grep -qx 'real' "$panel/public/themes/marker" || fail "real marker moved"
grep -qx 'decoy' "$panel/public/themes-decoy/marker" || fail "decoy marker moved"
restore_sealed_dirs
