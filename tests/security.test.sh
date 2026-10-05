#!/usr/bin/env bash
# Prueft die fail-closed Pruefungen des Installers, ohne root und ohne Panel.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

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

# Datei, deren Elternverzeichnis beim rename schon ein Symlink ist, wird wieder entfernt.
leak_out="$(realpath -e "$(mktemp -d "$tmp/leak.XXXXXX")")"
leak_panel="$(realpath -e "$(mktemp -d "$tmp/leakpanel.XXXXXX")")"
mkdir -p "$leak_panel/public" "$leak_out/nebula"
printf 'secret\n' > "$leak_out/pwned"
printf 'payload\n' > "$leak_out/staged-src"
ln -s "$leak_out" "$leak_panel/public/themes"
PANEL="$leak_panel"
staged_file="$(mktemp)"
printf 'payload\n' > "$staged_file"
if publish_file "$staged_file" "$leak_panel/public/themes/nebula/nebula.css" "public/themes/nebula/nebula.css"; then
    fail "publish_file accepted a symlinked parent"
fi
if [ -e "$leak_out/nebula/nebula.css" ] || [ -e "$leak_out/nebula.css" ]; then
    fail "publish_file left a file outside the panel"
fi
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

# safe_reset_theme_dir selbst: mv sieht ein echtes public/themes, der Aufruf tauscht es vorher aus.
reset_panel="$(realpath -e "$(mktemp -d "$tmp/resetpanel.XXXXXX")")"
reset_out="$(realpath -e "$(mktemp -d "$tmp/resetout.XXXXXX")")"
mkdir -p "$reset_panel/public/themes"
printf 'secret\n' > "$reset_out/pwned"
PANEL="$reset_panel"
if (
    # shellcheck disable=SC2030,SC2031
    PATH="$wrap:$PATH"
    ATTACK_PARENT="$reset_panel/public/themes"
    ATTACK_TARGET="$reset_panel/public/themes/nebula"
    ATTACK_OUT="$reset_out"
    export PATH ATTACK_PARENT ATTACK_TARGET ATTACK_OUT
    safe_reset_theme_dir
) >/dev/null 2>&1; then
    fail "safe_reset_theme_dir kept a directory created through a swapped parent"
fi
[ ! -d "$reset_out/nebula" ] || fail "safe_reset_theme_dir leaked the theme directory"
grep -qx 'secret' "$reset_out/pwned" || fail "safe_reset_theme_dir clobbered the outside file"

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

bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/build.sh"
bash -n "$ROOT/uninstall.sh"

echo "security ok"
