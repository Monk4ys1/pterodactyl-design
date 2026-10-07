#!/usr/bin/env bash
# Prueft die fail-closed Pruefungen des Installers, ohne root und ohne Panel.
# tick schlaegt nicht fehl; A && tick || fail ist hier if/else.
# shellcheck disable=SC2015
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

unset PTD_SHA256 || true
PTD_SELFTEST=1
# shellcheck disable=SC1091
source "$ROOT/install.sh"

PASS=0
FAILS=0
REPORTED=0
tick() { PASS=$((PASS + 1)); }
fail() {
    FAILS=$((FAILS + 1))
    printf 'FAIL %s\n' "$1" >&2
    printf 'Tests: %s bestanden, %s fehlgeschlagen\n' "$PASS" "$FAILS" >&2
    REPORTED=1
    exit 1
}
cleanup() {
    local rc=$?
    if [ -n "${tmp:-}" ]; then
        rm -rf "$tmp"
    fi
    if [ "$REPORTED" != 1 ] && [ "$rc" -ne 0 ]; then
        printf 'Tests: %s bestanden, 1 fehlgeschlagen\n' "$PASS" >&2
    fi
    exit "$rc"
}
trap cleanup EXIT

valid_ref "HEAD" && tick || fail "HEAD"
valid_ref "main" && tick || fail "main"
valid_ref "claude/pterodactyl-design-features-w3r8mz" && tick || fail "feature-ref"
if valid_ref "../etc"; then fail "dotdot accepted"; else tick; fi
if valid_ref "foo/../../bar"; then fail "nested dotdot accepted"; else tick; fi
if valid_ref "-rf"; then fail "dash ref accepted"; else tick; fi
if valid_ref $'main\nevil'; then fail "newline ref accepted"; else tick; fi
if valid_ref "https://evil.example/x"; then fail "url ref accepted"; else tick; fi
if valid_ref ""; then fail "empty ref accepted"; else tick; fi
if valid_ref "a b"; then fail "space ref accepted"; else tick; fi

valid_asset "2.0.0-abc123def0" && tick || fail "asset"
if valid_asset "2.0.0;rm -rf"; then fail "asset metachar accepted"; else tick; fi
if valid_asset "../x"; then fail "asset traversal accepted"; else tick; fi
if valid_asset ""; then fail "empty asset accepted"; else tick; fi

[ "$(json_escape 'a"b')" = 'a\"b' ] && tick || fail "json quote"
[ "$(json_escape $'a\nb')" = 'a\nb' ] && tick || fail "json newline"

# shellcheck disable=SC2016 # Der Wert muss literal bleiben, damit die Expansion getestet wird.
panel='/tmp/$(touch /tmp/pwn-nebula-audit)'
q="$(printf '%q' "$panel")"
got="$(eval "printf '%s' $q")"
[ "$got" = "$panel" ] && tick || fail "printf %q roundtrip"
[ ! -e /tmp/pwn-nebula-audit ] && tick || fail "command substitution executed"

tmp="$(mktemp -d)"
export PTD_SEAL_JOURNAL="$tmp/seal.journal"
mkdir -p "$tmp/in/safe"
printf 'ok\n' > "$tmp/in/safe/a.txt"
tar -czf "$tmp/ok.tgz" -C "$tmp/in" safe/a.txt
archive_is_safe "$tmp/ok.tgz" && tick || fail "safe archive rejected"
if member_rejected "theme/"; then fail "directory member rejected"; else tick; fi
if member_rejected "public/themes/nebula/"; then fail "nested directory member rejected"; else tick; fi
if member_rejected "theme/css/nebula.css"; then fail "file member rejected"; else tick; fi
member_rejected "foo//bar" && tick || fail "double slash accepted"
member_rejected "/etc/passwd" && tick || fail "absolute member accepted"
member_rejected "" && tick || fail "empty member accepted"

tar -czf "$tmp/bad.tgz" -C "$tmp/in" --transform='s|^safe/a.txt|../evil.txt|' safe/a.txt
if archive_is_safe "$tmp/bad.tgz"; then fail "traversal archive accepted"; else tick; fi

ln -s /tmp "$tmp/in/safe/link"
tar -czf "$tmp/link.tgz" -C "$tmp/in" safe/link
if archive_is_safe "$tmp/link.tgz"; then fail "symlink archive accepted"; else tick; fi

if command -v node >/dev/null 2>&1; then
    node "$HERE/security-path.js" && tick || fail "security-path.js"
fi

# Explizite Ref: kein stiller Fallback auf HEAD/main/master.
saved_branch="$BRANCH"
saved_explicit="$REF_EXPLICIT"
BRANCH="v2.0.0"
REF_EXPLICIT=1
explicit_refs="$(source_ref_list)"
[ "$explicit_refs" = "v2.0.0" ] && tick || fail "explicit ref fell back: $explicit_refs"
REF_EXPLICIT=0
BRANCH="HEAD"
default_refs="$(source_ref_list)"
printf '%s\n' "$default_refs" | grep -qx 'main' && tick || fail "unpinned install lost main fallback"
printf '%s\n' "$default_refs" | grep -qx 'master' && tick || fail "unpinned install lost master fallback"
BRANCH="$saved_branch"
REF_EXPLICIT="$saved_explicit"

# Installierte Kopie ist keine lokale Quelle.
saved_lib="$LIB_DIR"
LIB_DIR="$ROOT"
source_is_installed_lib && tick || fail "LIB_DIR not treated as installed copy"
LIB_DIR="/usr/local/lib/nebula-theme-not-a-checkout"
if source_is_installed_lib; then fail "checkout treated as installed lib"; else tick; fi
LIB_DIR="$saved_lib"

# EXIT-Trap darf unter set -u keine lokale Variable brauchen.
(
    set -u
    SRC_TMP=""
    unset SRC_TARBALL
    cleanup_source
)

if grep -n 'local tarball' "$ROOT/install.sh"; then fail "local tarball still traps"; else tick; fi
grep -q 'umask 022' "$ROOT/install.sh" && tick || fail "umask"
grep -q -- '--tlsv1.2' "$ROOT/install.sh" && tick || fail "tls"
grep -q -- '-print0' "$ROOT/install.sh" && tick || fail "print0"
if grep -n 'new RegExp' "$ROOT/theme/js/70-notify.js"; then fail "watcher still compiles RegExp"; else tick; fi
grep -q 'webfonts: false' "$ROOT/theme/js/00-boot.js" && tick || fail "webfonts default"

# Symlink-Komponenten im Panel duerfen weder als sicher gelten noch beschrieben werden.
panel="$(realpath -e "$(mktemp -d "$tmp/panel.XXXXXX")")"
outside="$(realpath -e "$(mktemp -d "$tmp/outside.XXXXXX")")"
mkdir -p "$panel/resources/views/templates" "$panel/public/themes/nebula" "$panel/resources/views/layouts"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"
printf 'admin\n' > "$panel/resources/views/layouts/admin.blade.php"
printf 'secret\n' > "$outside/pwned"
PANEL="$panel"
path_is_confined "$WRAPPER_REL" && tick || fail "real blade path rejected"
path_is_confined "public/themes/nebula" && tick || fail "real theme dir rejected"
if path_is_confined "public/../../etc/passwd"; then fail "dotdot path accepted"; else tick; fi
if path_is_confined "/etc/passwd"; then fail "absolute path accepted"; else tick; fi

rm -f "$panel/resources/views/templates/wrapper.blade.php"
ln -s "$outside/pwned" "$panel/resources/views/templates/wrapper.blade.php"
if path_is_confined "$WRAPPER_REL"; then fail "symlink blade accepted"; else tick; fi
rm -f "$panel/resources/views/templates/wrapper.blade.php"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"

rm -rf "$panel/resources/views/templates"
ln -s "$outside" "$panel/resources/views/templates"
if path_is_confined "$WRAPPER_REL"; then fail "symlink templates dir accepted"; else tick; fi
rm -f "$panel/resources/views/templates"
mkdir -p "$panel/resources/views/templates"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"

printf 'payload\n' > "$tmp/payload"
ln -s "$outside/pwned" "$panel/public/themes/nebula/nebula.css"
if ( PANEL="$panel"; safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload" ) >/dev/null 2>&1; then
    fail "write followed file symlink"
else
    tick
fi
grep -qx 'secret' "$outside/pwned" && tick || fail "symlink target was overwritten"
rm -f "$panel/public/themes/nebula/nebula.css"

rm -rf "$panel/public/themes"
ln -s "$outside" "$panel/public/themes"
if ( PANEL="$panel"; safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload" ) >/dev/null 2>&1; then
    fail "write followed themes symlink"
else
    tick
fi
if [ -e "$outside/nebula.css" ] || [ -e "$outside/nebula/nebula.css" ]; then
    fail "payload landed outside panel"
else
    tick
fi
rm -f "$panel/public/themes"
mkdir -p "$panel/public/themes/nebula"
printf 'old\n' > "$panel/public/themes/nebula/nebula.css"
safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload"
grep -qx 'payload' "$panel/public/themes/nebula/nebula.css" && tick || fail "confined replace failed"
[ ! -L "$panel/public/themes/nebula/nebula.css" ] && tick || fail "replace left a symlink"

# Restore kopiert nur bekannte regulaere Dateien und folgt keinen Panel-Symlinks.
extract="$(mktemp -d "$tmp/extract.XXXXXX")"
mkdir -p "$extract/resources/views/templates" "$extract/resources/views/layouts" "$extract/public/themes/nebula"
printf 'NEW\n' > "$extract/resources/views/templates/wrapper.blade.php"
printf 'ANEW\n' > "$extract/resources/views/layouts/admin.blade.php"
printf 'css\n' > "$extract/public/themes/nebula/nebula.css"
printf 'nope\n' > "$extract/evil.txt"
printf 'nope\n' > "$extract/public/themes/nebula/evil.php"
if ( PANEL="$panel"; restore_members_from "$extract" ) >/dev/null 2>&1; then
    fail "unknown backup asset accepted"
else
    tick
fi
grep -qx 'blade' "$panel/resources/views/templates/wrapper.blade.php" && tick || fail "rejected restore already wrote"
rm -f "$extract/public/themes/nebula/evil.php"
restore_members_from "$extract"
grep -qx 'NEW' "$panel/resources/views/templates/wrapper.blade.php" && tick || fail "wrapper not restored"
grep -qx 'css' "$panel/public/themes/nebula/nebula.css" && tick || fail "theme asset not restored"
[ ! -e "$panel/evil.txt" ] && tick || fail "archive root file copied into panel"

rm -rf "$panel/public/themes"
ln -s "$outside" "$panel/public/themes"
if ( PANEL="$panel"; restore_members_from "$extract" ) >/dev/null 2>&1; then
    fail "restore followed themes symlink"
else
    tick
fi
if [ -e "$outside/nebula/nebula.css" ] || [ -e "$outside/nebula.css" ]; then
    fail "restore wrote outside panel"
else
    tick
fi
grep -qx 'secret' "$outside/pwned" && tick || fail "restore clobbered outside file"

# nebula update darf LIB_DIR nicht leeren, wenn die Kopie fehlschlaegt oder die Quelle sie selbst ist.
libparent="$(mktemp -d "$tmp/libparent.XXXXXX")"
lib="$libparent/nebula-theme"
mkdir -p "$lib"
printf 'KEEP\n' > "$lib/marker"
bad="$(mktemp -d "$tmp/badsrc.XXXXXX")"
if ( LIB_DIR="$lib"; swap_lib_dir "$bad" ) >/dev/null 2>&1; then
    fail "incomplete lib swap succeeded"
else
    tick
fi
[ -f "$lib/marker" ] && tick || fail "failed swap removed LIB_DIR"
src="$(mktemp -d "$tmp/goodsrc.XXXXXX")"
mkdir -p "$src/theme/css" "$src/scripts"
printf '#!/bin/sh\n' > "$src/install.sh"
printf '#!/bin/sh\n' > "$src/scripts/build.sh"
printf '{}\n' > "$src/theme.json"
printf '2\n' > "$src/VERSION"
printf 'css\n' > "$src/theme/css/a.css"
( LIB_DIR="$lib"; swap_lib_dir "$src" )
[ -f "$lib/install.sh" ] && tick || fail "swap missing install.sh"
[ -f "$lib/theme/css/a.css" ] && tick || fail "swap missing theme"
[ ! -e "$lib/marker" ] && tick || fail "old lib dir survived swap"
if ( LIB_DIR="$lib"; swap_lib_dir "$lib" ) >/dev/null 2>&1; then
    fail "self swap succeeded"
else
    tick
fi
if [ ! -f "$lib/install.sh" ] || [ ! -f "$lib/theme/css/a.css" ]; then
    fail "self swap emptied LIB_DIR"
else
    tick
fi

state_panel="$(realpath -e "$(mktemp -d "$tmp/state.XXXXXX")")"
state_src="$(mktemp -d "$tmp/statesrc.XXXXXX")"
printf '2.0.0\n' > "$state_src/VERSION"
PANEL="$state_panel"
SRC="$state_src"
write_state "2.0.0-abc123def0"
[ -f "$state_panel/.nebula-install.json" ] && tick || fail "state file missing"
[ ! -L "$state_panel/.nebula-install.json" ] && tick || fail "state file is a symlink"
[ "$(stat -c '%a' "$state_panel/.nebula-install.json")" = "600" ] && tick || fail "state file mode"
[ "$(read_state version)" = "2.0.0" ] && tick || fail "state version"
[ "$(read_state asset_version)" = "2.0.0-abc123def0" ] && tick || fail "state asset"
rm -f "$state_panel/.nebula-install.json"
ln -s "$outside/pwned" "$state_panel/.nebula-install.json"
if ( PANEL="$state_panel"; SRC="$state_src"; write_state "2.0.0-abc123def0" ) >/dev/null 2>&1; then
    fail "state write followed symlink"
else
    tick
fi
grep -qx 'secret' "$outside/pwned" && tick || fail "state symlink target overwritten"

# Zwischenablage: 0700, selbes Dateisystem, nicht im Verzeichnis das www-data beschreiben kann.
rm -rf "$panel/public/themes"
mkdir -p "$panel/public/themes/nebula"
printf 'old\n' > "$panel/public/themes/nebula/nebula.css"
PANEL="$panel"
if require_same_device / /proc; then fail "cross-device accepted"; else tick; fi
require_same_device / /tmp && tick || fail "same device rejected"
stage_probe="$(open_private_stage "$panel/public/themes/nebula")"
require_same_device "$stage_probe" "$panel/public/themes/nebula" && tick || fail "stage left the destination filesystem"
[ "$(stat -c '%a' "$stage_probe")" = "700" ] && tick || fail "stage mode"
case "$stage_probe" in
    "$panel/public/themes/nebula"|"$panel/public/themes/nebula"/*) fail "stage created inside the writable directory" ;;
esac
tick
close_private_stage "$stage_probe"
chmod 777 "$panel/public/themes/nebula" "$panel/public/themes" "$panel/public" "$panel"
stage_probe="$(open_private_stage "$panel/public/themes/nebula")"
case "$stage_probe" in
    "$panel/public/themes/nebula"|"$panel/public/themes/nebula"/*) fail "stage stayed inside a world-writable directory" ;;
esac
tick
require_same_device "$stage_probe" "$panel/public/themes/nebula" && tick || fail "world-writable dest changed filesystem"
close_private_stage "$stage_probe"
chmod 755 "$panel" "$panel/public" "$panel/public/themes" "$panel/public/themes/nebula"

# cp in das Web-Verzeichnis: ein dort ausgetauschter Symlink darf root nicht nach aussen schreiben lassen.
real_cp="$(command -v cp)"
real_mv="$(command -v mv)"
wrap="$(mktemp -d "$tmp/wrap.XXXXXX")"
cat > "$wrap/cp" <<EOF
#!/bin/bash
dest="\${@: -1}"
if [ -n "\${ATTACK_DIR:-}" ] && [ -n "\${ATTACK_OUT:-}" ]; then
    case "\$dest" in
        "\$ATTACK_DIR"|"\$ATTACK_DIR"/*)
            rm -f -- "\$dest"
            ln -s "\$ATTACK_OUT" "\$dest"
            ;;
    esac
fi
exec ${real_cp} "\$@"
EOF
cat > "$wrap/mv" <<EOF
#!/bin/bash
dest="\${@: -1}"
if [ -n "\${ATTACK_PARENT:-}" ] && [ "\$dest" = "\${ATTACK_TARGET:-}" ]; then
    rm -rf -- "\$ATTACK_PARENT"
    ln -s "\$ATTACK_OUT" "\$ATTACK_PARENT"
fi
exec ${real_mv} "\$@"
EOF
chmod 755 "$wrap/cp" "$wrap/mv"
printf 'payload\n' > "$tmp/payload"
printf 'old\n' > "$panel/public/themes/nebula/nebula.css"
(
    # shellcheck disable=SC2030
    PATH="$wrap:$PATH"
    ATTACK_DIR="$panel/public/themes/nebula"
    ATTACK_OUT="$outside/pwned"
    export PATH ATTACK_DIR ATTACK_OUT
    safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload"
)
grep -qx 'payload' "$panel/public/themes/nebula/nebula.css" && tick || fail "staged install missed the panel file"
[ ! -L "$panel/public/themes/nebula/nebula.css" ] && tick || fail "installed file is a symlink"
grep -qx 'secret' "$outside/pwned" && tick || fail "temp symlink swap wrote outside the panel"

# Symlink-Vorfahr: kein mv, und eine schon vorhandene Datei am Fremdpfad bleibt byte-genau.
leak_out="$(realpath -e "$(mktemp -d "$tmp/leak.XXXXXX")")"
leak_panel="$(realpath -e "$(mktemp -d "$tmp/leakpanel.XXXXXX")")"
mkdir -p "$leak_panel/public" "$leak_out/nebula"
printf 'secret\n' > "$leak_out/pwned"
printf 'victim\n' > "$leak_out/nebula/nebula.css"
printf 'payload\n' > "$leak_out/staged-src"
ln -s "$leak_out" "$leak_panel/public/themes"
PANEL="$leak_panel"
staged_file="$(mktemp)"
printf 'payload\n' > "$staged_file"
if publish_file "$staged_file" "$leak_panel/public/themes/nebula/nebula.css" "public/themes/nebula/nebula.css"; then
    fail "publish_file accepted a symlinked parent"
else
    tick
fi
grep -qx 'victim' "$leak_out/nebula/nebula.css" && tick || fail "publish_file removed or replaced the outside file"
grep -qx 'secret' "$leak_out/pwned" && tick || fail "publish_file clobbered the outside file"

# Theme-Verzeichnis: mkdir/mv durch einen nachtraeglich gesetzten Symlink wird per rmdir entfernt.
tree_panel="$(realpath -e "$(mktemp -d "$tmp/treepanel.XXXXXX")")"
tree_out="$(realpath -e "$(mktemp -d "$tmp/treeout.XXXXXX")")"
mkdir -p "$tree_panel/public"
printf 'secret\n' > "$tree_out/pwned"
ln -s "$tree_out" "$tree_panel/public/themes"
PANEL="$tree_panel"
tree_stage="$(mktemp -d "$tmp/treestage.XXXXXX")"
mkdir -- "$tree_stage/nebula"
if publish_tree_dir "$tree_stage/nebula" "$tree_panel/public/themes/nebula" "public/themes/nebula"; then
    fail "publish_tree_dir accepted a symlinked parent"
else
    tick
fi
[ ! -d "$tree_out/nebula" ] && tick || fail "theme dir leaked through a symlinked parent"
grep -qx 'secret' "$tree_out/pwned" && tick || fail "theme publish clobbered the outside file"

# safe_reset_theme_dir darf mv nicht benutzen. Ein Hook, der den Parent zwischen
# Pruefung und mv tauscht, darf weder ausserhalb anlegen noch das Panel als Symlink lassen.
reset_panel="$(realpath -e "$(mktemp -d "$tmp/resetpanel.XXXXXX")")"
reset_out="$(realpath -e "$(mktemp -d "$tmp/resetout.XXXXXX")")"
mkdir -p "$reset_panel/public/themes"
printf 'secret\n' > "$reset_out/pwned"
printf 'keep\n' > "$reset_out/keep-me"
PANEL="$reset_panel"
if ! (
    # shellcheck disable=SC2030,SC2031
    PATH="$wrap:$PATH"
    ATTACK_PARENT="$reset_panel/public/themes"
    ATTACK_TARGET="$reset_panel/public/themes/nebula"
    ATTACK_OUT="$reset_out"
    export PATH ATTACK_PARENT ATTACK_TARGET ATTACK_OUT
    safe_reset_theme_dir
) >/dev/null 2>&1; then
    fail "safe_reset_theme_dir failed inside a real panel"
else
    tick
fi
[ ! -L "$reset_panel/public/themes" ] && tick || fail "safe_reset left public/themes as a symlink"
[ -d "$reset_panel/public/themes/nebula" ] && tick || fail "safe_reset did not create the theme directory"
[ ! -e "$reset_out/nebula" ] && tick || fail "safe_reset created a theme directory outside the panel"
grep -qx 'secret' "$reset_out/pwned" && tick || fail "safe_reset_theme_dir clobbered the outside file"
grep -qx 'keep' "$reset_out/keep-me" && tick || fail "safe_reset_theme_dir removed an outside file"

if [ "$(stat -c '%d' /)" != "$(stat -c '%d' /dev/shm)" ]; then
    shm_file="$(mktemp --tmpdir=/dev/shm nebula-cross.XXXXXX)"
    printf 'x\n' > "$shm_file"
    PANEL="$panel"
    mkdir -p "$panel/public/themes/nebula"
    if publish_file "$shm_file" "$panel/public/themes/nebula/cross.css" "public/themes/nebula/cross.css"; then
        fail "cross-device publish succeeded"
    else
        tick
    fi
    [ ! -e "$panel/public/themes/nebula/cross.css" ] && tick || fail "cross-device publish created the destination"
    rm -f "$shm_file"
fi

# H1: chown/chmod nach dem Veroeffentlichen darf einem getauschten public/themes nicht folgen.
h_out="$(realpath -e "$(mktemp -d "$tmp/h1out.XXXXXX")")"
h_panel="$(realpath -e "$(mktemp -d "$tmp/h1panel.XXXXXX")")"
mkdir -p "$h_panel/public" "$h_out/nebula"
printf 'victim\n' > "$h_out/pwned"
printf 'owned\n' > "$h_out/nebula/nebula.css"
h_before="$(stat -c '%u %g %a' "$h_out/pwned" "$h_out/nebula/nebula.css")"
ln -s "$h_out" "$h_panel/public/themes"
h_build="$(mktemp -d "$tmp/h1build.XXXXXX")"
printf 'css\n' > "$h_build/nebula.css"
if ( PANEL="$h_panel"; install_built_assets "$h_build" ) >/dev/null 2>&1; then
    fail "install_built_assets followed a swapped themes directory"
else
    tick
fi
h_after="$(stat -c '%u %g %a' "$h_out/pwned" "$h_out/nebula/nebula.css")"
[ "$h_before" = "$h_after" ] && tick || fail "ownership step changed a file outside the panel"
grep -qx 'victim' "$h_out/pwned" && tick || fail "outside sentinel content changed"
grep -qx 'owned' "$h_out/nebula/nebula.css" && tick || fail "outside asset content changed"

fn_body() {
    awk -v name="$1" 'BEGIN{p=0} $0 ~ "^" name "\\(\\)"{p=1} p{print} p && /^}$/{exit}' "$ROOT/install.sh"
}
if printf '%s\n' "$(fn_body install_built_assets)" | grep -E 'chown|chmod'; then fail "install_built_assets still chowns the published tree"; else tick; fi
if printf '%s\n' "$(fn_body write_state)" | grep -n 'chmod'; then fail "write_state still chmods the panel path"; else tick; fi
if printf '%s\n' "$(fn_body publish_file)" | grep -E 'rm -f|rmdir'; then fail "publish_file still removes the destination"; else tick; fi
if printf '%s\n' "$(fn_body publish_tree_dir)" | grep -n 'rmdir'; then fail "publish_tree_dir still removes the destination"; else tick; fi

# chmod am Zustandsdatei-Pfad im Panel ist verboten; Modus kommt aus der Zwischenablage.
chmod_log="$(mktemp)"
real_chmod="$(command -v chmod)"
cat > "$wrap/chmod" <<EOF
#!/bin/bash
for a in "\$@"; do
    case "\$a" in
        "$state_panel/$STATE_FILE")
            printf '%s\n' "\$a" >> "$chmod_log"
            exit 0
            ;;
    esac
done
exec ${real_chmod} "\$@"
EOF
chmod 755 "$wrap/chmod"
(
    # shellcheck disable=SC2030,SC2031
    PATH="$wrap:$PATH"
    PANEL="$state_panel"
    SRC="$state_src"
    rm -f "$state_panel/$STATE_FILE"
    write_state "2.0.0-abc123def0"
)
[ ! -s "$chmod_log" ] && tick || fail "write_state chmod on the panel state file: $(cat "$chmod_log")"
[ "$(stat -c '%a' "$state_panel/$STATE_FILE")" = "600" ] && tick || fail "state mode without post-chmod"

# Backup liest eine private Kopie, keinen Symlink aus dem Web-Baum.
bak_panel="$(realpath -e "$(mktemp -d "$tmp/bakpanel.XXXXXX")")"
bak_out="$(realpath -e "$(mktemp -d "$tmp/bakout.XXXXXX")")"
mkdir -p "$bak_panel/resources/views/templates" "$bak_panel/public/themes/nebula"
printf 'BLADE\n' > "$bak_panel/$WRAPPER_REL"
printf 'CSS\n' > "$bak_panel/$THEME_REL/nebula.css"
printf 'secret\n' > "$bak_out/pwned"
PANEL="$bak_panel"
snap="$(mktemp -d "$tmp/snap.XXXXXX")"
snapshot_panel_files "$snap" "$WRAPPER_REL" "$THEME_REL" && tick || fail "snapshot rejected a clean tree"
grep -qx 'BLADE' "$snap/$WRAPPER_REL" && tick || fail "snapshot missed blade"
grep -qx 'CSS' "$snap/$THEME_REL/nebula.css" && tick || fail "snapshot missed css"
if grep -R -q 'secret' "$snap"; then fail "snapshot copied outside content"; else tick; fi
rm -rf "$bak_panel/public/themes"
ln -s "$bak_out" "$bak_panel/public/themes"
snap2="$(mktemp -d "$tmp/snap2.XXXXXX")"
if snapshot_panel_files "$snap2" "$THEME_REL"; then fail "snapshot followed themes symlink"; else tick; fi
if grep -R -q 'secret' "$snap2" 2>/dev/null; then fail "snapshot stored the symlink target"; else tick; fi

saved_backup="$BACKUP_ROOT"
saved_do_backup="$DO_BACKUP"
BACKUP_ROOT="$tmp/backups/nebula"
DO_BACKUP=1
rm -f "$bak_panel/public/themes"
mkdir -p "$bak_panel/public/themes/nebula"
printf 'CSS\n' > "$bak_panel/$THEME_REL/nebula.css"
PANEL="$bak_panel"
make_backup
archive="$(head -n 1 "$BACKUP_ROOT/latest")"
tar -tzf "$archive" | grep -q 'nebula.css' && tick || fail "backup archive missed theme"
if tar -xOf "$archive" | grep -q 'secret'; then fail "backup archive contains outside bytes"; else tick; fi
BACKUP_ROOT="$saved_backup"
DO_BACKUP="$saved_do_backup"

# Pruefsumme, Tag, Ausgabe, Besitzer, Elternverzeichnisse.
blob="$(mktemp)"
printf 'abc\n' > "$blob"
good_sum="$(sha256sum "$blob" | awk '{print $1}')"
CHECKSUM="$good_sum"
checksum_matches "$blob" && tick || fail "checksum match rejected"
if [ "${good_sum: -1}" = "0" ]; then
    CHECKSUM="${good_sum%?}1"
else
    CHECKSUM="${good_sum%?}0"
fi
if checksum_matches "$blob"; then fail "checksum mismatch accepted"; else tick; fi
CHECKSUM=""
valid_checksum "$good_sum" && tick || fail "valid checksum rejected"
if valid_checksum "xyz"; then fail "short checksum accepted"; else tick; fi
# ESC und CR fallen weg; die restlichen Zeichen sind kein Steuerbefehl mehr.
[ "$(sanitize_text $'ab\033[2Jc\r')" = 'ab[2Jc' ] && tick || fail "control characters survived"
parents_root_owned /usr/bin && tick || fail "root-owned parents rejected"
if parents_root_owned "$tmp/not-a-panel"; then fail "user-owned parent accepted"; else tick; fi
if tree_owned_by_root "$tmp"; then fail "user tree treated as root-owned"; else tick; fi
grep -q 'SRC_ROOT/source.tar.gz' "$ROOT/install.sh" && tick || fail "tarball not kept in a private directory"
if grep -n 'SRC_TARBALL=' "$ROOT/install.sh" | grep -v 'source.tar.gz' | grep -q mktemp; then
    fail "tarball recreated via mktemp in /tmp"
else
    tick
fi
grep -q -- '--pty' "$ROOT/install.sh" && tick || fail "runuser without a private pty"
PTD_SELFTEST=1 bash "$ROOT/install.sh" --tag v1.2.3 --checksum "$good_sum" && tick || fail "tag and checksum flags rejected"
if PTD_SELFTEST=1 bash "$ROOT/install.sh" --checksum xyz >/dev/null 2>&1; then fail "bad checksum flag accepted"; else tick; fi

# Vorhandenes Fremdverzeichnis darf beim Reset nicht geloescht werden.
pre_panel="$(realpath -e "$(mktemp -d "$tmp/prepanel.XXXXXX")")"
pre_out="$(realpath -e "$(mktemp -d "$tmp/preout.XXXXXX")")"
mkdir -p "$pre_panel/public" "$pre_out/nebula"
printf 'stay\n' > "$pre_out/nebula/keep"
ln -s "$pre_out" "$pre_panel/public/themes"
if ( PANEL="$pre_panel"; safe_reset_theme_dir ) >/dev/null 2>&1; then
    fail "safe_reset accepted a symlinked themes directory"
else
    tick
fi
grep -qx 'stay' "$pre_out/nebula/keep" && tick || fail "safe_reset deleted an outside theme tree"

# Tausch-Hook: mv/rm/cp auf dem Panel-Pfad tauschen den Parent, bevor das echte
# Programm laeuft. Publish, rm, Backup und Asset-Publish duerfen den Hook nicht
# ausloesen und nichts ausserhalb anlegen oder loeschen.
race_panel="$(realpath -e "$(mktemp -d "$tmp/racepanel.XXXXXX")")"
race_out="$(realpath -e "$(mktemp -d "$tmp/raceout.XXXXXX")")"
race_wrap="$(mktemp -d "$tmp/racewrap.XXXXXX")"
race_log="$(mktemp)"
mkdir -p "$race_panel/resources/views/templates" "$race_panel/resources/views/layouts" \
    "$race_panel/public/themes/nebula" "$race_out/nebula"
PANEL="$race_panel"
printf 'BLADE\n' > "$race_panel/$WRAPPER_REL"
printf 'OLD\n' > "$race_panel/$THEME_REL/nebula.css"
printf 'secret\n' > "$race_out/pwned"
printf 'keep\n' > "$race_out/nebula/keep"
printf 'payload\n' > "$tmp/payload"
real_cp="$(command -v cp)"
real_mv="$(command -v mv)"
real_rm="$(command -v rm)"
cat > "$race_wrap/cp" <<EOF
#!/bin/bash
printf 'cp %s\n' "\$*" >> "$race_log"
hit=0
for a in "\$@"; do
    case "\$a" in
        "\${ATTACK_PARENT:-}"|"\${ATTACK_TARGET:-}"|"\${ATTACK_TARGET:-}"/*) hit=1 ;;
    esac
done
if [ "\$hit" = "1" ]; then
    ${real_rm} -rf -- "\$ATTACK_PARENT"
    ln -s "\$ATTACK_OUT" "\$ATTACK_PARENT"
fi
exec ${real_cp} "\$@"
EOF
cat > "$race_wrap/mv" <<EOF
#!/bin/bash
printf 'mv %s\n' "\$*" >> "$race_log"
dest="\${@: -1}"
if [ -n "\${ATTACK_PARENT:-}" ] && { [ "\$dest" = "\${ATTACK_TARGET:-}" ] || [ "\$dest" = "\${ATTACK_PARENT:-}" ]; }; then
    ${real_rm} -rf -- "\$ATTACK_PARENT"
    ln -s "\$ATTACK_OUT" "\$ATTACK_PARENT"
fi
exec ${real_mv} "\$@"
EOF
cat > "$race_wrap/rm" <<EOF
#!/bin/bash
printf 'rm %s\n' "\$*" >> "$race_log"
hit=0
for a in "\$@"; do
    case "\$a" in
        "\${ATTACK_PARENT:-}"|"\${ATTACK_TARGET:-}"|"\${ATTACK_TARGET:-}"/*) hit=1 ;;
    esac
done
if [ "\$hit" = "1" ]; then
    ${real_rm} -rf -- "\$ATTACK_PARENT"
    ln -s "\$ATTACK_OUT" "\$ATTACK_PARENT"
    exec ${real_rm} "\$@"
fi
exec ${real_rm} "\$@"
EOF
chmod 755 "$race_wrap/cp" "$race_wrap/mv" "$race_wrap/rm"

race_env() {
    # shellcheck disable=SC2030,SC2031
    PATH="$race_wrap:$PATH"
    ATTACK_PARENT="$race_panel/public/themes"
    ATTACK_TARGET="$race_panel/public/themes/nebula"
    ATTACK_OUT="$race_out"
    export PATH ATTACK_PARENT ATTACK_TARGET ATTACK_OUT
}

(
    race_env
    safe_install_file "$race_panel/public/themes/nebula/nebula.css" "$tmp/payload"
) >/dev/null
grep -qx 'payload' "$race_panel/public/themes/nebula/nebula.css" && tick || fail "hooked publish missed the panel file"
[ ! -L "$race_panel/public/themes" ] && tick || fail "hooked publish turned themes into a symlink"
grep -qx 'secret' "$race_out/pwned" && tick || fail "hooked publish clobbered the outside file"
grep -qx 'keep' "$race_out/nebula/keep" && tick || fail "hooked publish removed the outside tree"

(
    race_env
    discard_panel_path "$race_panel/public/themes/nebula" "public/themes/nebula"
) >/dev/null
[ ! -e "$race_panel/public/themes/nebula" ] && tick || fail "hooked discard left the theme directory"
[ ! -L "$race_panel/public/themes" ] && tick || fail "hooked discard turned themes into a symlink"
grep -qx 'keep' "$race_out/nebula/keep" && tick || fail "hooked rm -rf deleted the outside tree"

mkdir -p "$race_panel/public/themes/nebula"
printf 'CSS\n' > "$race_panel/public/themes/nebula/nebula.css"
snap_race="$(mktemp -d "$tmp/snaprace.XXXXXX")"
(
    race_env
    snapshot_panel_files "$snap_race" "$WRAPPER_REL" "$THEME_REL"
) && tick || fail "hooked snapshot failed"
grep -qx 'BLADE' "$snap_race/$WRAPPER_REL" && tick || fail "hooked snapshot missed blade"
grep -qx 'CSS' "$snap_race/$THEME_REL/nebula.css" && tick || fail "hooked snapshot missed css"
grep -qx 'keep' "$race_out/nebula/keep" && tick || fail "hooked backup copy deleted the outside tree"
if grep -R -q 'secret' "$snap_race"; then fail "hooked snapshot stored outside bytes"; else tick; fi

race_build="$(mktemp -d "$tmp/racebuild.XXXXXX")"
printf 'built\n' > "$race_build/nebula.css"
printf 'built\n' > "$race_build/nebula.js"
printf '{}\n' > "$race_build/theme.json"
printf '2.0.0-abc123def0\n' > "$race_build/ASSET_VERSION"
(
    race_env
    PANEL="$race_panel"
    install_built_assets "$race_build"
) >/dev/null
grep -qx 'built' "$race_panel/public/themes/nebula/nebula.css" && tick || fail "hooked asset publish missed css"
[ ! -L "$race_panel/public/themes" ] && tick || fail "hooked asset publish left a symlink"
[ ! -e "$race_out/nebula/nebula.css" ] && tick || fail "hooked asset publish wrote outside"
grep -qx 'keep' "$race_out/nebula/keep" && tick || fail "hooked asset publish deleted the outside tree"
if grep -E '^(cp|mv|rm) ' "$race_log" | grep -F "$race_panel/public/themes/nebula" >/dev/null; then
    fail "published path was passed to cp/mv/rm: $(grep -F "$race_panel/public/themes/nebula" "$race_log")"
else
    tick
fi

# Schon vorher getauschter Parent: rm folgt ihm nicht.
rm -rf "$race_panel/public/themes"
ln -s "$race_out" "$race_panel/public/themes"
if discard_panel_path "$race_panel/public/themes/nebula" "public/themes/nebula"; then
    fail "discard followed a themes symlink"
else
    tick
fi
grep -qx 'keep' "$race_out/nebula/keep" && tick || fail "symlink discard deleted the outside tree"
rm -f "$race_panel/public/themes"
mkdir -p "$race_panel/public/themes"

# Siegel bricht bei einem Symlink ab und chmod folgt ihm nicht.
seal_out="$(realpath -e "$(mktemp -d "$tmp/sealout.XXXXXX")")"
printf 'x\n' > "$seal_out/marker"
chmod 700 "$seal_out"
seal_before="$(stat -c '%a %u' "$seal_out")"
rm -rf "$race_panel/public/themes"
ln -s "$seal_out" "$race_panel/public/themes"
PANEL="$race_panel"
if ( prepare_panel_writes ) >/dev/null 2>&1; then
    fail "seal accepted a symlinked public/themes"
else
    tick
fi
seal_after="$(stat -c '%a %u' "$seal_out")"
[ "$seal_before" = "$seal_after" ] && tick || fail "seal chmod followed the themes symlink"
rm -f "$race_panel/public/themes"
mkdir -p "$race_panel/public/themes"
PANEL="$race_panel"
prepare_panel_writes >/dev/null
if [ ! -d "$race_panel/public/themes" ] || [ -L "$race_panel/public/themes" ]; then
    fail "seal did not leave a real themes directory"
else
    tick
fi
if [ ! -d "$race_panel/resources/views/layouts" ] || [ -L "$race_panel/resources/views/layouts" ]; then
    fail "seal missed layouts"
else
    tick
fi
[ "$(stat -c '%a' "$race_panel/public")" = "755" ] && tick || fail "public was not sealed to 0755"
[ "$(stat -c '%a' "$race_panel")" = "755" ] && tick || fail "panel root was not sealed to 0755"

# Echte Archive: git archive und eine codeload-Huelle mit Top-Level-Verzeichnis.
if command -v git >/dev/null 2>&1; then
    git -C "$ROOT" archive --format=tar.gz -o "$tmp/git-head.tgz" HEAD
    archive_is_safe "$tmp/git-head.tgz" && tick || fail "real git archive rejected"
    code_top="$(mktemp -d "$tmp/codeload.XXXXXX")"
    mkdir -p "$code_top/Monk4ys1-pterodactyl-design-deadbeef"
    tar -xzf "$tmp/git-head.tgz" -C "$code_top/Monk4ys1-pterodactyl-design-deadbeef"
    tar -czf "$tmp/codeload.tgz" -C "$code_top" Monk4ys1-pterodactyl-design-deadbeef
    archive_is_safe "$tmp/codeload.tgz" && tick || fail "codeload-style archive rejected"
fi

# Backup-Restore nach dem Verzeichnis-Fix: Bytes kommen zurueck.
restore_panel="$(realpath -e "$(mktemp -d "$tmp/restorepanel.XXXXXX")")"
mkdir -p "$restore_panel/resources/views/templates" "$restore_panel/public/themes/nebula"
printf 'BLADE\n' > "$restore_panel/$WRAPPER_REL"
printf 'CSS\n' > "$restore_panel/$THEME_REL/nebula.css"
saved_backup="$BACKUP_ROOT"
saved_do_backup="$DO_BACKUP"
BACKUP_ROOT="$tmp/restore-backups/nebula"
DO_BACKUP=1
PANEL="$restore_panel"
make_backup
restore_archive="$(head -n 1 "$BACKUP_ROOT/latest")"
archive_is_safe "$restore_archive" && tick || fail "backup archive rejected"
restore_extract="$(mktemp -d "$tmp/restore-extract.XXXXXX")"
tar -xzf "$restore_archive" -C "$restore_extract"
printf 'MUT\n' > "$restore_panel/$THEME_REL/nebula.css"
printf 'MUT\n' > "$restore_panel/$WRAPPER_REL"
restore_members_from "$restore_extract"
grep -qx 'CSS' "$restore_panel/$THEME_REL/nebula.css" && tick || fail "restore did not return css"
grep -qx 'BLADE' "$restore_panel/$WRAPPER_REL" && tick || fail "restore did not return blade"
BACKUP_ROOT="$saved_backup"
DO_BACKUP="$saved_do_backup"

if mode_go_writable 755; then fail "0755 treated as group or other writable"; else tick; fi
mode_go_writable 775 && tick || fail "0775 not treated as group writable"
mode_go_writable 757 && tick || fail "0757 not treated as other writable"
if ( fail_if_many_panels /var/www/pterodactyl /srv/pterodactyl ) >/dev/null 2>&1; then
    fail "two autodetect hits accepted"
else
    tick
fi
fail_if_many_panels /var/www/pterodactyl
advice="$( ( panel_parent_advice /var/www/pterodactyl ) 2>&1 || true )"
printf '%s\n' "$advice" | grep -q 'chown root:root /var/www' && tick || fail "autodetect advice missing chown"
printf '%s\n' "$advice" | grep -q 'chmod 755 /var/www' && tick || fail "autodetect advice missing chmod"

saved_tag="${TAG_REQUESTED:-0}"
saved_branch="$BRANCH"
saved_sum="${CHECKSUM:-}"
TAG_REQUESTED=1
first_url="$(source_archive_urls v2.0.0 | head -n 1)"
case "$first_url" in
    */refs/tags/v2.0.0) ;;
    *) fail "tag download does not try refs/tags first: $first_url" ;;
esac
tick
TAG_REQUESTED=0
first_url="$(source_archive_urls main | head -n 1)"
case "$first_url" in
    */refs/heads/main) ;;
    *) fail "branch download does not try refs/heads first: $first_url" ;;
esac
tick
if ( CHECKSUM="$good_sum"; TAG_REQUESTED=0; resolve_source ) >/dev/null 2>&1; then
    fail "local checkout accepted --checksum"
else
    tick
fi
if ( CHECKSUM=""; TAG_REQUESTED=1; BRANCH="v2.0.0"; resolve_source ) >/dev/null 2>&1; then
    fail "local checkout accepted --tag"
else
    tick
fi
TAG_REQUESTED=1
BRANCH="v2.0.0"
CHECKSUM="$good_sum"
pin_out="$(cli_pin_args)"
printf '%s\n' "$pin_out" | grep -qx -- '--tag' && tick || fail "cli pin missing --tag"
printf '%s\n' "$pin_out" | grep -qx 'v2.0.0' && tick || fail "cli pin missing tag value"
printf '%s\n' "$pin_out" | grep -qx -- '--checksum' && tick || fail "cli pin missing --checksum"
printf '%s\n' "$pin_out" | grep -qx "$good_sum" && tick || fail "cli pin missing checksum"
TAG_REQUESTED=0
CHECKSUM=""
[ -z "$(cli_pin_args)" ] && tick || fail "cli pin set without tag or checksum"
TAG_REQUESTED="$saved_tag"
BRANCH="$saved_branch"
CHECKSUM="$saved_sum"

if grep -n -- '--reference' "$ROOT/install.sh"; then
    fail "installer still takes ownership from the destination"
else
    tick
fi

# CWD ist /: der Installer legt ihn nicht auf sys.path (CWE-427).
[ "$(pwd)" = / ] && tick || fail "installer left cwd $(pwd)"
[ "$(installer_dir)" = "$ROOT" ] && tick || fail "installer_dir lost after cd /"

# N9: ctypes.py im CWD und PYTHON* duerfen fd_py nicht erreichen.
pwn="$(mktemp -d "$tmp/pwn.XXXXXX")"
mkdir -p "$pwn/lib"
cat > "$pwn/ctypes.py" <<'PY'
import sys
sys.stderr.write("PWNED\n")
raise SystemExit(86)
PY
cp "$pwn/ctypes.py" "$pwn/lib/ctypes.py"
ctrl="$(cd "$pwn" && /usr/bin/python3 -c 'import ctypes' 2>&1 || true)"
printf '%s\n' "$ctrl" | grep -q PWNED && tick || fail "ctypes fixture did not execute without isolation"
iso="$(
    cd "$pwn" && PYTHONPATH="$pwn/lib" PYTHONSTARTUP="$pwn/ctypes.py" PYTHONSAFEPATH=0 PYTHONHOME="$pwn" \
        fd_py snapshot 2>&1 || true
)"
if printf '%s\n' "$iso" | grep -q PWNED; then
    fail "isolated python executed ctypes.py: $iso"
else
    tick
fi
printf '%s\n' "$iso" | grep -q 'unbekannter befehl' && tick || fail "isolated python did not reach main: $iso"

# N12: python3 vor Quelle, Build und Siegel.
awk '
    /^require_python3\(\)/ { seen_fn=1 }
    /^resolve_source\(\)/ { in_rs=1 }
    in_rs && /require_python3/ { rs=1 }
    in_rs && /^}/ { in_rs=0 }
    /^prepare_panel_writes\(\)/ { in_pw=1 }
    in_pw && /require_python3/ { pw=1 }
    in_pw && /claim_dir/ { if (!pw) exit 1 }
    /^banner$/ { in_main=1 }
    in_main && /require_python3/ && !main_py { main_py=NR }
    in_main && /^[[:space:]]*resolve_source$/ && !main_rs { main_rs=NR }
    END { exit !(seen_fn && rs && pw && main_py && main_rs && main_py < main_rs) }
' "$ROOT/install.sh" && tick || fail "python3 check is not before source, seal, or build"
if awk '/^resolve_source\(\)/{p=1} p && /DO_CLI/{bad=1} p && /tree_owned_by_root/{seen=1} p && /^}/{exit (seen && !bad)?0:1}' "$ROOT/install.sh"; then
    tick
else
    fail "--no-cli still skips the root-owned source check"
fi

# N13: leere Summe, Warnung, Branch-Pin, Summe ohne Ref.
if PTD_SELFTEST=1 bash "$ROOT/install.sh" --checksum '' >/dev/null 2>&1; then
    fail "empty --checksum accepted"
else
    tick
fi
empty_out="$(PTD_SELFTEST=1 bash "$ROOT/install.sh" --checksum '' 2>&1 || true)"
printf '%s\n' "$empty_out" | grep -q 'braucht eine SHA-256' && tick || fail "empty --checksum message: $empty_out"
if PTD_SELFTEST=1 bash "$ROOT/install.sh" --checksum= >/dev/null 2>&1; then
    fail "empty --checksum= accepted"
else
    tick
fi
grep -q 'warn "Keine SHA-256-Pruefsumme gesetzt' "$ROOT/install.sh" && tick || fail "missing checksum is not a warning"
grep -q 'sudo entfernt PTD_SHA256' "$ROOT/install.sh" && tick || fail "sudo PTD_SHA256 hint missing"
saved_tag="${TAG_REQUESTED:-0}"
saved_branch_req="${BRANCH_REQUESTED:-0}"
saved_branch="$BRANCH"
saved_sum="${CHECKSUM:-}"
saved_action="${ACTION:-}"
TAG_REQUESTED=0
BRANCH_REQUESTED=1
BRANCH="feature/nebula"
CHECKSUM="$good_sum"
pin_branch="$(cli_pin_args)"
printf '%s\n' "$pin_branch" | grep -qx -- '--branch' && tick || fail "cli pin missing --branch"
printf '%s\n' "$pin_branch" | grep -qx 'feature/nebula' && tick || fail "cli pin missing branch value"
printf '%s\n' "$pin_branch" | grep -qx -- '--checksum' && tick || fail "cli pin missing checksum for branch"
TAG_REQUESTED=0
BRANCH_REQUESTED=0
CHECKSUM="$good_sum"
[ -z "$(cli_pin_args)" ] && tick || fail "checksum without tag or branch was stored"
if ( ACTION=update; CHECKSUM="$good_sum"; TAG_REQUESTED=0; BRANCH_REQUESTED=0; refuse_checksum_without_ref ) >/dev/null 2>&1; then
    fail "update accepted a checksum without --tag or --branch"
else
    tick
fi
refuse_msg="$( ( ACTION=update; CHECKSUM="$good_sum"; TAG_REQUESTED=0; BRANCH_REQUESTED=0; refuse_checksum_without_ref ) 2>&1 || true )"
printf '%s\n' "$refuse_msg" | grep -q 'ohne --tag oder --branch' && tick || fail "checksum-without-ref message: $refuse_msg"
( ACTION=install; CHECKSUM="$good_sum"; TAG_REQUESTED=0; BRANCH_REQUESTED=0; refuse_checksum_without_ref ) && tick || fail "install with a one-shot checksum was refused"
TAG_REQUESTED="$saved_tag"
BRANCH_REQUESTED="$saved_branch_req"
BRANCH="$saved_branch"
CHECKSUM="$saved_sum"
ACTION="$saved_action"

# N15: Blade-Modus verliert setuid und Schreibrechte fuer Gruppe und Andere.
[ "$(mask_blade_mode 777)" = "644" ] && tick || fail "mode 777 masked to $(mask_blade_mode 777)"
[ "$(mask_blade_mode 640)" = "640" ] && tick || fail "mode 640 changed"
[ "$(mask_blade_mode 755)" = "644" ] && tick || fail "mode 755 masked to $(mask_blade_mode 755)"
[ "$(mask_blade_mode 4755)" = "644" ] && tick || fail "setuid mode masked to $(mask_blade_mode 4755)"
mode_panel="$(mktemp -d "$tmp/modepanel.XXXXXX")"
mkdir -p "$mode_panel/resources/views/templates"
printf 'old\n' > "$mode_panel/$WRAPPER_REL"
chmod 777 "$mode_panel/$WRAPPER_REL"
printf 'new\n' > "$tmp/newblade"
PANEL="$mode_panel"
safe_replace_file "$mode_panel/$WRAPPER_REL" "$tmp/newblade"
[ "$(stat -c '%a' "$mode_panel/$WRAPPER_REL")" = "644" ] && tick || fail "replaced 777 blade mode $(stat -c '%a' "$mode_panel/$WRAPPER_REL")"
chmod 640 "$mode_panel/$WRAPPER_REL"
printf 'newer\n' > "$tmp/newblade"
safe_replace_file "$mode_panel/$WRAPPER_REL" "$tmp/newblade"
[ "$(stat -c '%a' "$mode_panel/$WRAPPER_REL")" = "640" ] && tick || fail "replaced 640 blade mode $(stat -c '%a' "$mode_panel/$WRAPPER_REL")"
grep -qx 'newer' "$mode_panel/$WRAPPER_REL" && tick || fail "blade contents not replaced"

# N14: Hardlink wird nicht ins Backup kopiert.
hl_panel="$(mktemp -d "$tmp/hlpanel.XXXXXX")"
mkdir -p "$hl_panel/resources/views/templates" "$hl_panel/storage"
printf 'blade\n' > "$hl_panel/$WRAPPER_REL"
ln "$hl_panel/$WRAPPER_REL" "$tmp/hl-extra"
PANEL="$hl_panel"
hl_snap="$(mktemp -d "$tmp/hlsnap.XXXXXX")"
if snapshot_panel_files "$hl_snap" "$WRAPPER_REL"; then
    fail "hardlink snapshot accepted"
else
    tick
fi
rm -f "$tmp/hl-extra"
hl_snap2="$(mktemp -d "$tmp/hlsnap2.XXXXXX")"
snapshot_panel_files "$hl_snap2" "$WRAPPER_REL" && tick || fail "unique file rejected after the hardlink was removed"

# N10/N11: Siegel ist voruebergehend, Modus kommt zurueck, .env bleibt 0640.
restore_sealed_dirs
own_panel="$(mktemp -d "$tmp/ownpanel.XXXXXX")"
mkdir -p "$own_panel/resources/views/templates" "$own_panel/resources/views/layouts" \
    "$own_panel/public/themes" "$own_panel/storage"
printf 'secret\n' > "$own_panel/.env"
chmod 640 "$own_panel/.env"
chmod 750 "$own_panel/public"
chmod 701 "$own_panel/resources"
PANEL="$own_panel"
prepare_panel_writes >/dev/null
[ "$(stat -c '%a' "$own_panel/public")" = "755" ] && tick || fail "public not sealed"
[ "$(stat -c '%a' "$own_panel/.env")" = "640" ] && tick || fail ".env mode changed during seal"
restore_sealed_dirs
[ "$(stat -c '%a' "$own_panel/public")" = "750" ] && tick || fail "public mode not restored ($(stat -c '%a' "$own_panel/public"))"
[ "$(stat -c '%a' "$own_panel/resources")" = "701" ] && tick || fail "resources mode not restored"
[ "$(stat -c '%a' "$own_panel/.env")" = "640" ] && tick || fail ".env mode changed during restore"
# Ein ausgetauschtes Verzeichnis wird nicht wiederhergestellt und nicht verfolgt.
outside_mode="$(mktemp -d "$tmp/outsidemode.XXXXXX")"
chmod 700 "$outside_mode"
before_out="$(stat -c '%a %u' "$outside_mode")"
prepare_panel_writes >/dev/null
rm -rf "$own_panel/public/themes"
ln -s "$outside_mode" "$own_panel/public/themes"
restore_sealed_dirs
[ "$(stat -c '%a %u' "$outside_mode")" = "$before_out" ] && tick || fail "restore followed a swapped themes directory"
[ -L "$own_panel/public/themes" ] && tick || fail "restore replaced the symlink with a directory"
SEAL_RELS=()
SEAL_DEVS=()
SEAL_INOS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
SEAL_PANEL=""
rm -f -- "$PTD_SEAL_JOURNAL"

# R3-1: Abbruch nach Teil-Siegel. resources/views ist dann ein Symlink.
# Das Zuruecksetzen darf T/templates nicht anfassen.
part="$(mktemp -d "$tmp/part.XXXXXX")"
part_t="$(mktemp -d "$tmp/part-t.XXXXXX")"
mkdir -p "$part/resources/views/templates" "$part/resources/views/layouts" "$part/public/themes" \
    "$part_t/templates" "$part_t/layouts"
printf 'secret\n' > "$part_t/templates/hook"
chmod 700 "$part_t" "$part_t/templates" "$part_t/layouts"
chmod 701 "$part"
chmod 750 "$part/resources"
part_before="$(stat -c '%a %u' "$part_t/templates" "$part_t/layouts")"
PANEL="$part"
if (
    SEAL_RELS=()
    SEAL_DEVS=()
    SEAL_INOS=()
    SEAL_UIDS=()
    SEAL_GIDS=()
    SEAL_MODES=()
    SEAL_PANEL=""
    # shellcheck disable=SC2030
    PTD_SEAL_JOURNAL="$part/seal.journal"
    trap restore_sealed_dirs EXIT
    PTD_SEAL_BREAK_AFTER=.
    PTD_SEAL_BREAK_LINK=resources/views
    PTD_SEAL_BREAK_TARGET="$part_t"
    prepare_panel_writes
) >/dev/null 2>&1; then
    fail "partial seal accepted a swapped views directory"
else
    tick
fi
[ "$(stat -c '%a' "$part")" = "701" ] && tick || fail "panel mode after partial seal $(stat -c '%a' "$part")"
[ "$(stat -c '%a' "$part/resources")" = "750" ] && tick || fail "resources mode after partial seal $(stat -c '%a' "$part/resources")"
[ -L "$part/resources/views" ] && tick || fail "swapped views directory was replaced"
[ "$(stat -c '%a %u' "$part_t/templates" "$part_t/layouts")" = "$part_before" ] && tick || fail "restore followed the swapped views symlink"
grep -qx 'secret' "$part_t/templates/hook" && tick || fail "target template file changed"
[ ! -e "$part/seal.journal" ] && tick || fail "seal journal survived a complete partial restore"

# Falsche Inode: nicht chmod'en, Eintrag behalten.
mis="$(mktemp -d "$tmp/mis.XXXXXX")"
mkdir -p "$mis/resources/views/templates" "$mis/resources/views/layouts" "$mis/public/themes"
chmod 701 "$mis"
# shellcheck disable=SC2031
saved_journal="$PTD_SEAL_JOURNAL"
PTD_SEAL_JOURNAL="$tmp/mis.journal"
PANEL="$mis"
SEAL_RELS=()
SEAL_DEVS=()
SEAL_INOS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
prepare_panel_writes >/dev/null
[ "$(stat -c '%a' "$mis")" = "755" ] && tick || fail "mismatch fixture was not sealed"
awk -F'|' 'NR>1 { $3=1; print } NR==1 { print }' OFS='|' "$PTD_SEAL_JOURNAL" > "$tmp/mis.bad"
mv -- "$tmp/mis.bad" "$PTD_SEAL_JOURNAL"
chmod 600 "$PTD_SEAL_JOURNAL"
SEAL_RELS=()
SEAL_DEVS=()
SEAL_INOS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
seal_journal_load
restore_sealed_dirs
[ "$(stat -c '%a' "$mis")" = "755" ] && tick || fail "inode mismatch still chmod'd the directory"
[ -f "$PTD_SEAL_JOURNAL" ] && tick || fail "mismatched seal journal was dropped"
SEAL_RELS=()
SEAL_DEVS=()
SEAL_INOS=()
SEAL_UIDS=()
SEAL_GIDS=()
SEAL_MODES=()
rm -f -- "$PTD_SEAL_JOURNAL"
PTD_SEAL_JOURNAL="$saved_journal"

# Falsche Pruefsumme nennt beide Werte. Leeres Build-Verzeichnis wird beim Abbruch entfernt.
grep -q 'SHA-256 stimmt nicht (erwartet' "$ROOT/install.sh" && tick || fail "checksum mismatch message is not specific"
grep -q "trap '' INT TERM HUP" "$ROOT/install.sh" && tick || fail "finish_exit does not ignore INT TERM HUP"
bdir="$(mktemp -d "$tmp/build.XXXXXX")"
printf 'x\n' > "$bdir/leftover"
(
    SEAL_RELS=()
    SEAL_DEVS=()
    SEAL_INOS=()
    SEAL_UIDS=()
    SEAL_GIDS=()
    SEAL_MODES=()
    BUILD_DIR="$bdir"
    finish_exit
)
[ ! -e "$bdir" ] && tick || fail "build dir survived finish_exit"

if sudo -n true 2>/dev/null && id www-data >/dev/null 2>&1; then
    sudo -n bash "$HERE/security-root.sh" "$ROOT" && tick || fail "root ownership, hardlink uid, or renameat2 race"
else
    printf 'skip root race (kein passwortloses sudo)\n'
fi

bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/build.sh"
bash -n "$ROOT/uninstall.sh"

printf 'Tests: %s bestanden, 0 fehlgeschlagen\n' "$PASS"
