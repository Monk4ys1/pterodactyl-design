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

bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/build.sh"
bash -n "$ROOT/uninstall.sh"

echo "security ok"
