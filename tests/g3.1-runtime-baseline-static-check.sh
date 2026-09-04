#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.1-runtime-baseline.md"
VERIFY="$ROOT_DIR/scripts/verify-node-runtime-baseline.sh"
fail(){ echo "FAIL $1"; exit 1; }
pass(){ echo "PASS $1"; }
for f in "$VERIFY" "$ROOT_DIR/tests/g3.1-runtime-baseline-static-check.sh"; do bash -n "$f" || fail "syntax $f"; done; pass 'shell syntax'
for needle in 'aetheris-node' 'Group=aetheris' 'no interactive login' 'no password' 'no home directory' 'no sudo' 'no Docker group' 'CONFIG_AUTHORITY' 'RELEASE_AUTHORITY' '/var/lib/aetheris/node/aetheris-node' '/run/aetheris/aetheris-node' 'journald' 'filesystem log directory' '/opt/aetheris/current' 'remains a directory' 'deferred' 'Restart=on-failure' 'RestartSec=10s' 'StartLimitIntervalSec=60s' 'StartLimitBurst=5'; do grep -q "$needle" "$DOC" || fail "documentation $needle"; done; pass 'documentation contract'
! grep -q '^ExecStart=' "$DOC" && ! grep -q 'docker\.sock' "$DOC" && ! grep -q '^DeviceAllow=' "$DOC" && ! grep -q '^DevicePolicy=' "$DOC" && ! grep -q '^PrivateDevices=yes' "$DOC" && pass 'deferred service/GPU/Docker policy' || fail 'premature service/GPU/Docker policy'
[ ! -e "$ROOT_DIR/files/etc/systemd/system/aetheris-node.service" ] && [ ! -e "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris-node.conf" ] && pass 'no premature unit or redundant tmpfiles' || fail 'premature G3.1 artifact'
! rg -n 'useradd|groupadd|systemctl (enable|start)' "$ROOT_DIR/docs/G3.1-runtime-baseline.md" "$VERIFY" >/dev/null && pass 'no account/systemd mutation' || fail 'mutation logic'
! rg -n 'docker.sock|DeviceAllow|DevicePolicy|PrivateDevices=yes|/opt/aetheris/current[[:space:]]*->' "$ROOT_DIR/docs/G3.1-runtime-baseline.md" >/dev/null && pass 'no Docker/GPU/release migration authorization' || fail 'premature policy'
# Repository modes are authoritative in Git, not checkout chmod.
git_mode(){ local actual; actual="$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR == 1 { print $1 }')"; [ "$actual" = "$1" ]; }
git_mode 100644 docs/G3.1-runtime-baseline.md && git_mode 100755 scripts/verify-node-runtime-baseline.sh && git_mode 100755 tests/g3.1-runtime-baseline-static-check.sh && pass 'canonical Git modes' || fail 'Git modes'
# Runtime contract preservation in the existing G3.0 apply implementation.
grep -q 'install -o root -g root -m 0644' "$ROOT_DIR/scripts/apply-node-contract.sh" || fail 'tmpfiles materialization mode'
grep -q 'install -o root -g aetheris -m 0640.*TMP_IDENTITY' "$ROOT_DIR/scripts/apply-node-contract.sh" || fail 'identity materialization mode'
grep -q 'install -o root -g aetheris -m 0640.*TMP_CAPABILITIES' "$ROOT_DIR/scripts/apply-node-contract.sh" || fail 'capability materialization mode'
pass 'G3.0 materialization permissions preserved'
"$VERIFY" >/dev/null && pass 'read-only baseline verifier' || fail 'read-only baseline verifier'
! grep -RIn '[[:blank:]]$' "$DOC" "$VERIFY" "$ROOT_DIR/tests/g3.1-runtime-baseline-static-check.sh" && pass 'whitespace' || fail 'trailing whitespace'
echo G3_1_RUNTIME_BASELINE_STATIC_CHECK=PASS
