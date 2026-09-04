#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0
pass(){ echo "PASS $1"; }
fail(){ echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }
check_file(){ [ -f "$1" ] && pass "file $1" || fail "missing file $1"; }
check_absent(){ [ ! -e "$1" ] && pass "absent $1" || fail "premature artifact $1"; }
git_mode_is(){ local actual; actual="$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR == 1 { print $1 }')"; [ "$actual" = "$3" ]; }

check_file "$ROOT_DIR/docs/G3.1-runtime-baseline.md"
check_file "$ROOT_DIR/scripts/verify-node-runtime-baseline.sh"
check_file "$ROOT_DIR/tests/g3.1-runtime-baseline-static-check.sh"
check_file "$ROOT_DIR/docs/G3.0-node-bootstrap-contract.md"
check_file "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris.conf"
check_file "$ROOT_DIR/scripts/apply-node-contract.sh"
check_file "$ROOT_DIR/scripts/verify-node-contract.sh"
check_absent "$ROOT_DIR/files/etc/systemd/system/aetheris-node.service"
check_absent "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris-node.conf"

for f in docs/G3.1-runtime-baseline.md scripts/verify-node-runtime-baseline.sh tests/g3.1-runtime-baseline-static-check.sh; do
    [ -e "$ROOT_DIR/$f" ] || continue
    if [ "$f" = scripts/verify-node-runtime-baseline.sh ] || [ "$f" = tests/g3.1-runtime-baseline-static-check.sh ]; then git_mode_is "$ROOT_DIR" "$f" 100755 || fail "Git mode $f"; else git_mode_is "$ROOT_DIR" "$f" 100644 || fail "Git mode $f"; fi
done

# Runtime identity and service leaves are intentionally not required yet.
if rg -n '^ExecStart=|docker\.sock|^DeviceAllow=|^DevicePolicy=|^PrivateDevices=yes' "$ROOT_DIR/docs/G3.1-runtime-baseline.md" >/dev/null; then
    fail "premature G3.1 implementation directive"
else
    pass "no G3.1 implementation directive"
fi

echo "RUNTIME_BASELINE_VERIFY_RC=$FAILURES"
exit "$FAILURES"
