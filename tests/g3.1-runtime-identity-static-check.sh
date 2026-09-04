#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT_DIR/scripts/apply-node-runtime-identity.sh"
VERIFY="$ROOT_DIR/scripts/verify-node-runtime-identity.sh"
DOC="$ROOT_DIR/docs/G3.1-runtime-identity-materialization.md"
fail(){ echo "FAIL $*" >&2; exit 1; }
pass(){ echo "PASS $*"; }

for f in "$APPLY" "$VERIFY" "$ROOT_DIR/tests/g3.1-runtime-identity-static-check.sh"; do bash -n "$f" || fail "syntax $f"; done
pass 'shell syntax'
for needle in aetheris-node 'primary group: aetheris' '/usr/sbin/nologin' '/nonexistent' 'supplementary groups: none' 'sudo: none' 'Docker group: none' 'PERMISSION_DENIED' 'LOCKED=PASS' 'NOT_VERIFIED' '/run/aetheris/aetheris-node' '/var/lib/aetheris/node/aetheris-node'; do
    grep -qF "$needle" "$DOC" "$APPLY" "$VERIFY" || fail "contract text $needle"
done
pass 'account contract'
! rg -n '(^|[[:space:]])(usermod|groupmod|groupadd|systemctl[[:space:]]+(enable|start|restart|daemon-reload)|tmpfiles[[:space:]]+--create|docker\.sock|DeviceAllow|DevicePolicy|PrivateDevices=yes|nvpmodel[[:space:]]+(-m|-f|--force)|apt([[:space:]]|$)|dpkg[[:space:]]+-i|mkdir .*aetheris-node|chmod .*aetheris-node|chown .*aetheris-node)' "$APPLY" "$VERIFY" >/dev/null || fail 'forbidden mutation logic'
! grep -qE '^[[:space:]]*useradd ' "$VERIFY" || fail 'verifier creates account'
! grep -qE '^[[:space:]]*useradd .*--uid|^[[:space:]]*useradd .* -u ' "$APPLY" || fail 'fixed UID'
pass 'mutation/security boundary'
grep -qF 'useradd --system --no-user-group --gid' "$APPLY" && grep -qF -- '--no-create-home' "$APPLY" && grep -qF -- "--password '!'" "$APPLY" || fail 'explicit account command'
grep -qF 'validate_preconditions' "$APPLY" || fail 'validation function'
line_validate="$(grep -n '^validate_preconditions$' "$APPLY" | tail -n1 | cut -d: -f1)"
line_useradd="$(grep -n '^useradd ' "$APPLY" | cut -d: -f1)"
[ "$line_validate" -lt "$line_useradd" ] || fail 'fail-before-mutation ordering'
pass 'fail-before-mutation ordering'

git_mode(){ local actual; actual="$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR==1{print $1}')"; [ "$actual" = "$1" ]; }
git_mode 100644 docs/G3.1-runtime-identity-materialization.md || fail 'doc Git mode'
git_mode 100755 scripts/apply-node-runtime-identity.sh || fail 'apply Git mode'
git_mode 100755 scripts/verify-node-runtime-identity.sh || fail 'verify Git mode'
git_mode 100755 tests/g3.1-runtime-identity-static-check.sh || fail 'test Git mode'
pass 'canonical Git modes'

# A temporary fake root plus command shims exercises the production precondition
# boundary. No shim can mutate the real account database or governed paths.
fixture="$(mktemp -d)"; bin="$fixture/bin"; log="$fixture/useradd.log"
mkdir -p "$bin" "$fixture/etc/aetheris/node" "$fixture/opt/aetheris/releases" "$fixture/opt/aetheris/current" "$fixture/var/lib/aetheris/node" "$fixture/var/log/aetheris" "$fixture/run/aetheris" "$fixture/etc/systemd/system" "$fixture/usr/lib/systemd/system" "$fixture/lib/systemd/system"
trap 'rm -rf "$fixture"' EXIT
for d in etc/aetheris etc/aetheris/node opt/aetheris opt/aetheris/releases opt/aetheris/current var/lib/aetheris var/lib/aetheris/node var/log/aetheris run/aetheris; do :; done
printf '%s\n' '#!/usr/bin/env bash' 'path="${@: -1}"' 'if [[ "${DENY_NODE:-0}" = 1 && "$path" = *"/etc/aetheris/node" ]]; then echo "stat: Permission denied" >&2; exit 1; fi' 'case "$path" in *etc/aetheris/node|*/var/lib/aetheris|*/var/lib/aetheris/node|*/var/log/aetheris|*/etc/aetheris) echo "root:aetheris 750" ;; */opt/aetheris|*/opt/aetheris/releases|*/opt/aetheris/current) echo "root:aetheris 755" ;; */run/aetheris) echo "root:aetheris 755" ;; *) if [ -e "$path" ]; then echo "root:aetheris 755"; else echo "stat: No such file or directory" >&2; exit 1; fi ;; esac' > "$bin/stat"
printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = group ] && [ "$2" = aetheris ]; then echo aetheris:x:979:; exit 0; fi' 'if [ "$1" = group ] && [ "$2" = docker ]; then echo docker:x:111:; exit 0; fi' 'if [ "$1" = group ] && [ "$2" = aetheris-node ]; then exit 2; fi' 'if [ "$1" = passwd ] && [ "$2" = aetheris-node ] && [ "${ACCOUNT_STATE:-absent}" != absent ]; then echo "aetheris-node:x:995:979::/nonexistent:${ACCOUNT_SHELL:-/usr/sbin/nologin}"; exit 0; fi' 'exit 2' > "$bin/getent"
printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in -G) echo "${ACCOUNT_GROUPS:-979}" ;; -nG) echo "${ACCOUNT_NAMED_GROUPS:-aetheris}" ;; *) exit 0 ;; esac' > "$bin/id"
printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = -S ] && { echo "aetheris-node ${ACCOUNT_PASSWORD_STATE:-L} 2026-09-04 0 99999 7 -1"; exit 0; }' > "$bin/passwd"
printf '%s\n' '#!/usr/bin/env bash' 'printf called > "${AETHERIS_USERADD_LOG}"' 'exit 91' > "$bin/useradd"
chmod +x "$bin"/*
run_apply(){ AETHERIS_RUNTIME_IDENTITY_TEST_MODE=1 AETHERIS_TEST_PATH_PREFIX="$fixture" AETHERIS_TEST_NOLOGIN_PATH="${TEST_NOLOGIN_PATH:-/bin/sh}" AETHERIS_USERADD_LOG="$log" PATH="$bin:/usr/bin:/bin" "$APPLY"; }
expect_reject(){ rm -f "$log"; if run_apply; then fail "accepted $1"; fi; [ ! -e "$log" ] || fail "mutation reached for $1"; }
rm -f "$log"; run_apply || true; [ -e "$log" ] || fail 'valid preconditions did not reach isolated useradd'; pass 'valid absent account reaches only isolated useradd'
ACCOUNT_STATE=mismatch ACCOUNT_SHELL=/bin/bash expect_reject 'mismatched account'
TEST_NOLOGIN_PATH="$fixture/missing-nologin" expect_reject 'missing nologin'
mv "$bin/getent" "$bin/getent.real"; printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = group ] && [ "$2" = aetheris ]; then exit 2; fi' 'exit 2' > "$bin/getent"; chmod +x "$bin/getent"; expect_reject 'missing aetheris group'; mv "$bin/getent.real" "$bin/getent"
mv "$bin/stat" "$bin/stat.real"; printf '%s\n' '#!/usr/bin/env bash' 'echo "stat: Permission denied" >&2; exit 1' > "$bin/stat"; chmod +x "$bin/stat"; expect_reject 'permission denied restricted path'; mv "$bin/stat.real" "$bin/stat"
touch "$fixture/run/aetheris/aetheris-node"; expect_reject 'pre-existing runtime leaf'; rm "$fixture/run/aetheris/aetheris-node"
touch "$fixture/var/lib/aetheris/node/aetheris-node"; expect_reject 'pre-existing state leaf'; rm "$fixture/var/lib/aetheris/node/aetheris-node"
touch "$fixture/etc/systemd/system/aetheris-node.service"; expect_reject 'pre-existing unit'; rm "$fixture/etc/systemd/system/aetheris-node.service"
ACCOUNT_STATE=exact ACCOUNT_SHELL=/bin/sh ACCOUNT_GROUPS=979 ACCOUNT_NAMED_GROUPS=aetheris ACCOUNT_PASSWORD_STATE=L rm -f "$log"; if ! ACCOUNT_STATE=exact ACCOUNT_SHELL=/bin/sh ACCOUNT_GROUPS=979 ACCOUNT_NAMED_GROUPS=aetheris ACCOUNT_PASSWORD_STATE=L run_apply; then fail 'exact existing account was not accepted'; fi
[ ! -e "$log" ] || fail 'semantic no-op invoked useradd'; pass 'exact existing account semantic no-op'
echo PERMISSION_DENIED_REGRESSION=PASS
echo G3_1_RUNTIME_IDENTITY_STATIC_CHECK=PASS
