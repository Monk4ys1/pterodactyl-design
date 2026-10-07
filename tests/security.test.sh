#!/usr/bin/env bash
# Prueft die fail-closed Pruefungen des Installers, ohne root und ohne Panel.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

unset PTD_SHA256 || true
PTD_SELFTEST=1
# shellcheck disable=SC1091
source "$ROOT/install.sh"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

valid_ref "HEAD" || fail "HEAD"
valid_ref "main" || fail "main"
valid_ref "claude/pterodactyl-design-features-w3r8mz" || fail "feature-ref"
if valid_ref "../etc"; then fail "dotdot accepted"; fi
if valid_ref "foo/../../bar"; then fail "nested dotdot accepted"; fi
if valid_ref "-rf"; then fail "dash ref accepted"; fi
if valid_ref $'main\nevil'; then fail "newline ref accepted"; fi
if valid_ref "https://evil.example/x"; then fail "url ref accepted"; fi
if valid_ref ""; then fail "empty ref accepted"; fi
if valid_ref "a b"; then fail "space ref accepted"; fi

valid_asset "2.0.0-abc123def0" || fail "asset"
if valid_asset "2.0.0;rm -rf"; then fail "asset metachar accepted"; fi
if valid_asset "../x"; then fail "asset traversal accepted"; fi
if valid_asset ""; then fail "empty asset accepted"; fi

[ "$(json_escape 'a"b')" = 'a\"b' ] || fail "json quote"
[ "$(json_escape $'a\nb')" = 'a\nb' ] || fail "json newline"

# shellcheck disable=SC2016 # Der Wert muss literal bleiben, damit die Expansion getestet wird.
panel='/tmp/$(touch /tmp/pwn-nebula-audit)'
q="$(printf '%q' "$panel")"
got="$(eval "printf '%s' $q")"
[ "$got" = "$panel" ] || fail "printf %q roundtrip"
[ ! -e /tmp/pwn-nebula-audit ] || fail "command substitution executed"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/in/safe"
printf 'ok\n' > "$tmp/in/safe/a.txt"
tar -czf "$tmp/ok.tgz" -C "$tmp/in" safe/a.txt
archive_is_safe "$tmp/ok.tgz" || fail "safe archive rejected"
if member_rejected "theme/"; then fail "directory member rejected"; fi
if member_rejected "public/themes/nebula/"; then fail "nested directory member rejected"; fi
if member_rejected "theme/css/nebula.css"; then fail "file member rejected"; fi
member_rejected "foo//bar" || fail "double slash accepted"
member_rejected "/etc/passwd" || fail "absolute member accepted"
member_rejected "" || fail "empty member accepted"

tar -czf "$tmp/bad.tgz" -C "$tmp/in" --transform='s|^safe/a.txt|../evil.txt|' safe/a.txt
if archive_is_safe "$tmp/bad.tgz"; then fail "traversal archive accepted"; fi

ln -s /tmp "$tmp/in/safe/link"
tar -czf "$tmp/link.tgz" -C "$tmp/in" safe/link
if archive_is_safe "$tmp/link.tgz"; then fail "symlink archive accepted"; fi

if command -v node >/dev/null 2>&1; then
    node "$HERE/security-path.js"
fi

# Explizite Ref: kein stiller Fallback auf HEAD/main/master.
saved_branch="$BRANCH"
saved_explicit="$REF_EXPLICIT"
BRANCH="v2.0.0"
REF_EXPLICIT=1
explicit_refs="$(source_ref_list)"
[ "$explicit_refs" = "v2.0.0" ] || fail "explicit ref fell back: $explicit_refs"
REF_EXPLICIT=0
BRANCH="HEAD"
default_refs="$(source_ref_list)"
printf '%s\n' "$default_refs" | grep -qx 'main' || fail "unpinned install lost main fallback"
printf '%s\n' "$default_refs" | grep -qx 'master' || fail "unpinned install lost master fallback"
BRANCH="$saved_branch"
REF_EXPLICIT="$saved_explicit"

# Installierte Kopie ist keine lokale Quelle.
saved_lib="$LIB_DIR"
LIB_DIR="$ROOT"
source_is_installed_lib || fail "LIB_DIR not treated as installed copy"
LIB_DIR="/usr/local/lib/nebula-theme-not-a-checkout"
if source_is_installed_lib; then fail "checkout treated as installed lib"; fi
LIB_DIR="$saved_lib"

# EXIT-Trap darf unter set -u keine lokale Variable brauchen.
(
    set -u
    SRC_TMP=""
    unset SRC_TARBALL
    cleanup_source
)

if grep -n 'local tarball' "$ROOT/install.sh"; then fail "local tarball still traps"; fi
grep -q 'umask 022' "$ROOT/install.sh" || fail "umask"
grep -q -- '--tlsv1.2' "$ROOT/install.sh" || fail "tls"
grep -q -- '-print0' "$ROOT/install.sh" || fail "print0"
if grep -n 'new RegExp' "$ROOT/theme/js/70-notify.js"; then fail "watcher still compiles RegExp"; fi
grep -q 'webfonts: false' "$ROOT/theme/js/00-boot.js" || fail "webfonts default"

# Symlink-Komponenten im Panel duerfen weder als sicher gelten noch beschrieben werden.
panel="$(realpath -e "$(mktemp -d "$tmp/panel.XXXXXX")")"
outside="$(realpath -e "$(mktemp -d "$tmp/outside.XXXXXX")")"
mkdir -p "$panel/resources/views/templates" "$panel/public/themes/nebula" "$panel/resources/views/layouts"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"
printf 'admin\n' > "$panel/resources/views/layouts/admin.blade.php"
printf 'secret\n' > "$outside/pwned"
PANEL="$panel"
path_is_confined "$WRAPPER_REL" || fail "real blade path rejected"
path_is_confined "public/themes/nebula" || fail "real theme dir rejected"
if path_is_confined "public/../../etc/passwd"; then fail "dotdot path accepted"; fi
if path_is_confined "/etc/passwd"; then fail "absolute path accepted"; fi

rm -f "$panel/resources/views/templates/wrapper.blade.php"
ln -s "$outside/pwned" "$panel/resources/views/templates/wrapper.blade.php"
if path_is_confined "$WRAPPER_REL"; then fail "symlink blade accepted"; fi
rm -f "$panel/resources/views/templates/wrapper.blade.php"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"

rm -rf "$panel/resources/views/templates"
ln -s "$outside" "$panel/resources/views/templates"
if path_is_confined "$WRAPPER_REL"; then fail "symlink templates dir accepted"; fi
rm -f "$panel/resources/views/templates"
mkdir -p "$panel/resources/views/templates"
printf 'blade\n' > "$panel/resources/views/templates/wrapper.blade.php"

printf 'payload\n' > "$tmp/payload"
ln -s "$outside/pwned" "$panel/public/themes/nebula/nebula.css"
if ( PANEL="$panel"; safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload" ) >/dev/null 2>&1; then
    fail "write followed file symlink"
fi
grep -qx 'secret' "$outside/pwned" || fail "symlink target was overwritten"
rm -f "$panel/public/themes/nebula/nebula.css"

rm -rf "$panel/public/themes"
ln -s "$outside" "$panel/public/themes"
if ( PANEL="$panel"; safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload" ) >/dev/null 2>&1; then
    fail "write followed themes symlink"
fi
if [ -e "$outside/nebula.css" ] || [ -e "$outside/nebula/nebula.css" ]; then
    fail "payload landed outside panel"
fi
rm -f "$panel/public/themes"
mkdir -p "$panel/public/themes/nebula"
printf 'old\n' > "$panel/public/themes/nebula/nebula.css"
safe_install_file "$panel/public/themes/nebula/nebula.css" "$tmp/payload"
grep -qx 'payload' "$panel/public/themes/nebula/nebula.css" || fail "confined replace failed"
[ ! -L "$panel/public/themes/nebula/nebula.css" ] || fail "replace left a symlink"

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
fi
grep -qx 'blade' "$panel/resources/views/templates/wrapper.blade.php" || fail "rejected restore already wrote"
rm -f "$extract/public/themes/nebula/evil.php"
restore_members_from "$extract"
grep -qx 'NEW' "$panel/resources/views/templates/wrapper.blade.php" || fail "wrapper not restored"
grep -qx 'css' "$panel/public/themes/nebula/nebula.css" || fail "theme asset not restored"
[ ! -e "$panel/evil.txt" ] || fail "archive root file copied into panel"

rm -rf "$panel/public/themes"
ln -s "$outside" "$panel/public/themes"
if ( PANEL="$panel"; restore_members_from "$extract" ) >/dev/null 2>&1; then
    fail "restore followed themes symlink"
fi
if [ -e "$outside/nebula/nebula.css" ] || [ -e "$outside/nebula.css" ]; then
    fail "restore wrote outside panel"
fi
grep -qx 'secret' "$outside/pwned" || fail "restore clobbered outside file"

# nebula update darf LIB_DIR nicht leeren, wenn die Kopie fehlschlaegt oder die Quelle sie selbst ist.
libparent="$(mktemp -d "$tmp/libparent.XXXXXX")"
lib="$libparent/nebula-theme"
mkdir -p "$lib"
printf 'KEEP\n' > "$lib/marker"
bad="$(mktemp -d "$tmp/badsrc.XXXXXX")"
if ( LIB_DIR="$lib"; swap_lib_dir "$bad" ) >/dev/null 2>&1; then
    fail "incomplete lib swap succeeded"
fi
[ -f "$lib/marker" ] || fail "failed swap removed LIB_DIR"
src="$(mktemp -d "$tmp/goodsrc.XXXXXX")"
mkdir -p "$src/theme/css" "$src/scripts"
printf '#!/bin/sh\n' > "$src/install.sh"
printf '#!/bin/sh\n' > "$src/scripts/build.sh"
printf '{}\n' > "$src/theme.json"
printf '2\n' > "$src/VERSION"
printf 'css\n' > "$src/theme/css/a.css"
( LIB_DIR="$lib"; swap_lib_dir "$src" )
[ -f "$lib/install.sh" ] || fail "swap missing install.sh"
[ -f "$lib/theme/css/a.css" ] || fail "swap missing theme"
[ ! -e "$lib/marker" ] || fail "old lib dir survived swap"
if ( LIB_DIR="$lib"; swap_lib_dir "$lib" ) >/dev/null 2>&1; then
    fail "self swap succeeded"
fi
if [ ! -f "$lib/install.sh" ] || [ ! -f "$lib/theme/css/a.css" ]; then
    fail "self swap emptied LIB_DIR"
fi

state_panel="$(realpath -e "$(mktemp -d "$tmp/state.XXXXXX")")"
state_src="$(mktemp -d "$tmp/statesrc.XXXXXX")"
printf '2.0.0\n' > "$state_src/VERSION"
PANEL="$state_panel"
SRC="$state_src"
write_state "2.0.0-abc123def0"
[ -f "$state_panel/.nebula-install.json" ] || fail "state file missing"
[ ! -L "$state_panel/.nebula-install.json" ] || fail "state file is a symlink"
[ "$(stat -c '%a' "$state_panel/.nebula-install.json")" = "600" ] || fail "state file mode"
[ "$(read_state version)" = "2.0.0" ] || fail "state version"
[ "$(read_state asset_version)" = "2.0.0-abc123def0" ] || fail "state asset"
rm -f "$state_panel/.nebula-install.json"
ln -s "$outside/pwned" "$state_panel/.nebula-install.json"
if ( PANEL="$state_panel"; SRC="$state_src"; write_state "2.0.0-abc123def0" ) >/dev/null 2>&1; then
    fail "state write followed symlink"
fi
grep -qx 'secret' "$outside/pwned" || fail "state symlink target overwritten"

# Zwischenablage: 0700, selbes Dateisystem, nicht im Verzeichnis das www-data beschreiben kann.
rm -rf "$panel/public/themes"
mkdir -p "$panel/public/themes/nebula"
printf 'old\n' > "$panel/public/themes/nebula/nebula.css"
PANEL="$panel"
if require_same_device / /proc; then fail "cross-device accepted"; fi
require_same_device / /tmp || fail "same device rejected"
stage_probe="$(open_private_stage "$panel/public/themes/nebula")"
require_same_device "$stage_probe" "$panel/public/themes/nebula" || fail "stage left the destination filesystem"
[ "$(stat -c '%a' "$stage_probe")" = "700" ] || fail "stage mode"
case "$stage_probe" in
    "$panel/public/themes/nebula"|"$panel/public/themes/nebula"/*) fail "stage created inside the writable directory" ;;
esac
close_private_stage "$stage_probe"
chmod 777 "$panel/public/themes/nebula" "$panel/public/themes" "$panel/public" "$panel"
stage_probe="$(open_private_stage "$panel/public/themes/nebula")"
case "$stage_probe" in
    "$panel/public/themes/nebula"|"$panel/public/themes/nebula"/*) fail "stage stayed inside a world-writable directory" ;;
esac
require_same_device "$stage_probe" "$panel/public/themes/nebula" || fail "world-writable dest changed filesystem"
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
grep -qx 'payload' "$panel/public/themes/nebula/nebula.css" || fail "staged install missed the panel file"
[ ! -L "$panel/public/themes/nebula/nebula.css" ] || fail "installed file is a symlink"
grep -qx 'secret' "$outside/pwned" || fail "temp symlink swap wrote outside the panel"

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
fi
grep -qx 'victim' "$leak_out/nebula/nebula.css" || fail "publish_file removed or replaced the outside file"
grep -qx 'secret' "$leak_out/pwned" || fail "publish_file clobbered the outside file"

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
fi
[ ! -d "$tree_out/nebula" ] || fail "theme dir leaked through a symlinked parent"
grep -qx 'secret' "$tree_out/pwned" || fail "theme publish clobbered the outside file"

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
fi
[ ! -L "$reset_panel/public/themes" ] || fail "safe_reset left public/themes as a symlink"
[ -d "$reset_panel/public/themes/nebula" ] || fail "safe_reset did not create the theme directory"
[ ! -e "$reset_out/nebula" ] || fail "safe_reset created a theme directory outside the panel"
grep -qx 'secret' "$reset_out/pwned" || fail "safe_reset_theme_dir clobbered the outside file"
grep -qx 'keep' "$reset_out/keep-me" || fail "safe_reset_theme_dir removed an outside file"

if [ "$(stat -c '%d' /)" != "$(stat -c '%d' /dev/shm)" ]; then
    shm_file="$(mktemp --tmpdir=/dev/shm nebula-cross.XXXXXX)"
    printf 'x\n' > "$shm_file"
    PANEL="$panel"
    mkdir -p "$panel/public/themes/nebula"
    if publish_file "$shm_file" "$panel/public/themes/nebula/cross.css" "public/themes/nebula/cross.css"; then
        fail "cross-device publish succeeded"
    fi
    [ ! -e "$panel/public/themes/nebula/cross.css" ] || fail "cross-device publish created the destination"
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
fi
h_after="$(stat -c '%u %g %a' "$h_out/pwned" "$h_out/nebula/nebula.css")"
[ "$h_before" = "$h_after" ] || fail "ownership step changed a file outside the panel"
grep -qx 'victim' "$h_out/pwned" || fail "outside sentinel content changed"
grep -qx 'owned' "$h_out/nebula/nebula.css" || fail "outside asset content changed"

fn_body() {
    awk -v name="$1" 'BEGIN{p=0} $0 ~ "^" name "\\(\\)"{p=1} p{print} p && /^}$/{exit}' "$ROOT/install.sh"
}
printf '%s\n' "$(fn_body install_built_assets)" | grep -E 'chown|chmod' && fail "install_built_assets still chowns the published tree"
printf '%s\n' "$(fn_body write_state)" | grep -n 'chmod' && fail "write_state still chmods the panel path"
printf '%s\n' "$(fn_body publish_file)" | grep -E 'rm -f|rmdir' && fail "publish_file still removes the destination"
printf '%s\n' "$(fn_body publish_tree_dir)" | grep -n 'rmdir' && fail "publish_tree_dir still removes the destination"

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
[ ! -s "$chmod_log" ] || fail "write_state chmod on the panel state file: $(cat "$chmod_log")"
[ "$(stat -c '%a' "$state_panel/$STATE_FILE")" = "600" ] || fail "state mode without post-chmod"

# Backup liest eine private Kopie, keinen Symlink aus dem Web-Baum.
bak_panel="$(realpath -e "$(mktemp -d "$tmp/bakpanel.XXXXXX")")"
bak_out="$(realpath -e "$(mktemp -d "$tmp/bakout.XXXXXX")")"
mkdir -p "$bak_panel/resources/views/templates" "$bak_panel/public/themes/nebula"
printf 'BLADE\n' > "$bak_panel/$WRAPPER_REL"
printf 'CSS\n' > "$bak_panel/$THEME_REL/nebula.css"
printf 'secret\n' > "$bak_out/pwned"
PANEL="$bak_panel"
snap="$(mktemp -d "$tmp/snap.XXXXXX")"
snapshot_panel_files "$snap" "$WRAPPER_REL" "$THEME_REL" || fail "snapshot rejected a clean tree"
grep -qx 'BLADE' "$snap/$WRAPPER_REL" || fail "snapshot missed blade"
grep -qx 'CSS' "$snap/$THEME_REL/nebula.css" || fail "snapshot missed css"
if grep -R -q 'secret' "$snap"; then fail "snapshot copied outside content"; fi
rm -rf "$bak_panel/public/themes"
ln -s "$bak_out" "$bak_panel/public/themes"
snap2="$(mktemp -d "$tmp/snap2.XXXXXX")"
if snapshot_panel_files "$snap2" "$THEME_REL"; then fail "snapshot followed themes symlink"; fi
if grep -R -q 'secret' "$snap2" 2>/dev/null; then fail "snapshot stored the symlink target"; fi

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
tar -tzf "$archive" | grep -q 'nebula.css' || fail "backup archive missed theme"
if tar -xOf "$archive" | grep -q 'secret'; then fail "backup archive contains outside bytes"; fi
BACKUP_ROOT="$saved_backup"
DO_BACKUP="$saved_do_backup"

# Pruefsumme, Tag, Ausgabe, Besitzer, Elternverzeichnisse.
blob="$(mktemp)"
printf 'abc\n' > "$blob"
good_sum="$(sha256sum "$blob" | awk '{print $1}')"
CHECKSUM="$good_sum"
checksum_matches "$blob" || fail "checksum match rejected"
if [ "${good_sum: -1}" = "0" ]; then
    CHECKSUM="${good_sum%?}1"
else
    CHECKSUM="${good_sum%?}0"
fi
if checksum_matches "$blob"; then fail "checksum mismatch accepted"; fi
CHECKSUM=""
valid_checksum "$good_sum" || fail "valid checksum rejected"
if valid_checksum "xyz"; then fail "short checksum accepted"; fi
# ESC und CR fallen weg; die restlichen Zeichen sind kein Steuerbefehl mehr.
[ "$(sanitize_text $'ab\033[2Jc\r')" = 'ab[2Jc' ] || fail "control characters survived"
parents_root_owned /usr/bin || fail "root-owned parents rejected"
if parents_root_owned "$tmp/not-a-panel"; then fail "user-owned parent accepted"; fi
if tree_owned_by_root "$tmp"; then fail "user tree treated as root-owned"; fi
grep -q 'SRC_ROOT/source.tar.gz' "$ROOT/install.sh" || fail "tarball not kept in a private directory"
if grep -n 'SRC_TARBALL=' "$ROOT/install.sh" | grep -v 'source.tar.gz' | grep -q mktemp; then
    fail "tarball recreated via mktemp in /tmp"
fi
grep -q -- '--pty' "$ROOT/install.sh" || fail "runuser without a private pty"
PTD_SELFTEST=1 bash "$ROOT/install.sh" --tag v1.2.3 --checksum "$good_sum" || fail "tag and checksum flags rejected"
if PTD_SELFTEST=1 bash "$ROOT/install.sh" --checksum xyz >/dev/null 2>&1; then fail "bad checksum flag accepted"; fi

# Vorhandenes Fremdverzeichnis darf beim Reset nicht geloescht werden.
pre_panel="$(realpath -e "$(mktemp -d "$tmp/prepanel.XXXXXX")")"
pre_out="$(realpath -e "$(mktemp -d "$tmp/preout.XXXXXX")")"
mkdir -p "$pre_panel/public" "$pre_out/nebula"
printf 'stay\n' > "$pre_out/nebula/keep"
ln -s "$pre_out" "$pre_panel/public/themes"
if ( PANEL="$pre_panel"; safe_reset_theme_dir ) >/dev/null 2>&1; then
    fail "safe_reset accepted a symlinked themes directory"
fi
grep -qx 'stay' "$pre_out/nebula/keep" || fail "safe_reset deleted an outside theme tree"

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
grep -qx 'payload' "$race_panel/public/themes/nebula/nebula.css" || fail "hooked publish missed the panel file"
[ ! -L "$race_panel/public/themes" ] || fail "hooked publish turned themes into a symlink"
grep -qx 'secret' "$race_out/pwned" || fail "hooked publish clobbered the outside file"
grep -qx 'keep' "$race_out/nebula/keep" || fail "hooked publish removed the outside tree"

(
    race_env
    discard_panel_path "$race_panel/public/themes/nebula" "public/themes/nebula"
) >/dev/null
[ ! -e "$race_panel/public/themes/nebula" ] || fail "hooked discard left the theme directory"
[ ! -L "$race_panel/public/themes" ] || fail "hooked discard turned themes into a symlink"
grep -qx 'keep' "$race_out/nebula/keep" || fail "hooked rm -rf deleted the outside tree"

mkdir -p "$race_panel/public/themes/nebula"
printf 'CSS\n' > "$race_panel/public/themes/nebula/nebula.css"
snap_race="$(mktemp -d "$tmp/snaprace.XXXXXX")"
(
    race_env
    snapshot_panel_files "$snap_race" "$WRAPPER_REL" "$THEME_REL"
) || fail "hooked snapshot failed"
grep -qx 'BLADE' "$snap_race/$WRAPPER_REL" || fail "hooked snapshot missed blade"
grep -qx 'CSS' "$snap_race/$THEME_REL/nebula.css" || fail "hooked snapshot missed css"
grep -qx 'keep' "$race_out/nebula/keep" || fail "hooked backup copy deleted the outside tree"
if grep -R -q 'secret' "$snap_race"; then fail "hooked snapshot stored outside bytes"; fi

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
grep -qx 'built' "$race_panel/public/themes/nebula/nebula.css" || fail "hooked asset publish missed css"
[ ! -L "$race_panel/public/themes" ] || fail "hooked asset publish left a symlink"
[ ! -e "$race_out/nebula/nebula.css" ] || fail "hooked asset publish wrote outside"
grep -qx 'keep' "$race_out/nebula/keep" || fail "hooked asset publish deleted the outside tree"
if grep -E '^(cp|mv|rm) ' "$race_log" | grep -F "$race_panel/public/themes/nebula" >/dev/null; then
    fail "published path was passed to cp/mv/rm: $(grep -F "$race_panel/public/themes/nebula" "$race_log")"
fi

# Schon vorher getauschter Parent: rm folgt ihm nicht.
rm -rf "$race_panel/public/themes"
ln -s "$race_out" "$race_panel/public/themes"
if discard_panel_path "$race_panel/public/themes/nebula" "public/themes/nebula"; then
    fail "discard followed a themes symlink"
fi
grep -qx 'keep' "$race_out/nebula/keep" || fail "symlink discard deleted the outside tree"
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
fi
seal_after="$(stat -c '%a %u' "$seal_out")"
[ "$seal_before" = "$seal_after" ] || fail "seal chmod followed the themes symlink"
rm -f "$race_panel/public/themes"
mkdir -p "$race_panel/public/themes"
PANEL="$race_panel"
prepare_panel_writes >/dev/null
if [ ! -d "$race_panel/public/themes" ] || [ -L "$race_panel/public/themes" ]; then
    fail "seal did not leave a real themes directory"
fi
if [ ! -d "$race_panel/resources/views/layouts" ] || [ -L "$race_panel/resources/views/layouts" ]; then
    fail "seal missed layouts"
fi
[ "$(stat -c '%a' "$race_panel/public")" = "755" ] || fail "public was not sealed to 0755"
[ "$(stat -c '%a' "$race_panel")" = "755" ] || fail "panel root was not sealed to 0755"

# Echte Archive: git archive und eine codeload-Huelle mit Top-Level-Verzeichnis.
if command -v git >/dev/null 2>&1; then
    git -C "$ROOT" archive --format=tar.gz -o "$tmp/git-head.tgz" HEAD
    archive_is_safe "$tmp/git-head.tgz" || fail "real git archive rejected"
    code_top="$(mktemp -d "$tmp/codeload.XXXXXX")"
    mkdir -p "$code_top/Monk4ys1-pterodactyl-design-deadbeef"
    tar -xzf "$tmp/git-head.tgz" -C "$code_top/Monk4ys1-pterodactyl-design-deadbeef"
    tar -czf "$tmp/codeload.tgz" -C "$code_top" Monk4ys1-pterodactyl-design-deadbeef
    archive_is_safe "$tmp/codeload.tgz" || fail "codeload-style archive rejected"
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
archive_is_safe "$restore_archive" || fail "backup archive rejected"
restore_extract="$(mktemp -d "$tmp/restore-extract.XXXXXX")"
tar -xzf "$restore_archive" -C "$restore_extract"
printf 'MUT\n' > "$restore_panel/$THEME_REL/nebula.css"
printf 'MUT\n' > "$restore_panel/$WRAPPER_REL"
restore_members_from "$restore_extract"
grep -qx 'CSS' "$restore_panel/$THEME_REL/nebula.css" || fail "restore did not return css"
grep -qx 'BLADE' "$restore_panel/$WRAPPER_REL" || fail "restore did not return blade"
BACKUP_ROOT="$saved_backup"
DO_BACKUP="$saved_do_backup"

if mode_go_writable 755; then fail "0755 treated as group or other writable"; fi
mode_go_writable 775 || fail "0775 not treated as group writable"
mode_go_writable 757 || fail "0757 not treated as other writable"
if ( fail_if_many_panels /var/www/pterodactyl /srv/pterodactyl ) >/dev/null 2>&1; then
    fail "two autodetect hits accepted"
fi
fail_if_many_panels /var/www/pterodactyl
advice="$( ( panel_parent_advice /var/www/pterodactyl ) 2>&1 || true )"
printf '%s\n' "$advice" | grep -q 'chown root:root /var/www' || fail "autodetect advice missing chown"
printf '%s\n' "$advice" | grep -q 'chmod 755 /var/www' || fail "autodetect advice missing chmod"

saved_tag="${TAG_REQUESTED:-0}"
saved_branch="$BRANCH"
saved_sum="${CHECKSUM:-}"
TAG_REQUESTED=1
first_url="$(source_archive_urls v2.0.0 | head -n 1)"
case "$first_url" in
    */refs/tags/v2.0.0) ;;
    *) fail "tag download does not try refs/tags first: $first_url" ;;
esac
TAG_REQUESTED=0
first_url="$(source_archive_urls main | head -n 1)"
case "$first_url" in
    */refs/heads/main) ;;
    *) fail "branch download does not try refs/heads first: $first_url" ;;
esac
if ( CHECKSUM="$good_sum"; TAG_REQUESTED=0; resolve_source ) >/dev/null 2>&1; then
    fail "local checkout accepted --checksum"
fi
if ( CHECKSUM=""; TAG_REQUESTED=1; BRANCH="v2.0.0"; resolve_source ) >/dev/null 2>&1; then
    fail "local checkout accepted --tag"
fi
TAG_REQUESTED=1
BRANCH="v2.0.0"
CHECKSUM="$good_sum"
pin_out="$(cli_pin_args)"
printf '%s\n' "$pin_out" | grep -qx -- '--tag' || fail "cli pin missing --tag"
printf '%s\n' "$pin_out" | grep -qx 'v2.0.0' || fail "cli pin missing tag value"
printf '%s\n' "$pin_out" | grep -qx -- '--checksum' || fail "cli pin missing --checksum"
printf '%s\n' "$pin_out" | grep -qx "$good_sum" || fail "cli pin missing checksum"
TAG_REQUESTED=0
CHECKSUM=""
[ -z "$(cli_pin_args)" ] || fail "cli pin set without tag or checksum"
TAG_REQUESTED="$saved_tag"
BRANCH="$saved_branch"
CHECKSUM="$saved_sum"

if grep -n -- '--reference' "$ROOT/install.sh"; then
    fail "installer still takes ownership from the destination"
fi

bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/build.sh"
bash -n "$ROOT/uninstall.sh"

echo "security ok"
