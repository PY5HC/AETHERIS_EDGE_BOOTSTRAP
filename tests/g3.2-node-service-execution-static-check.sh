#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.2-node-service-execution-contract.md"
TEMPLATE="$ROOT_DIR/templates/aetheris-node.service.template"
VERIFY="$ROOT_DIR/scripts/verify-node-service-contract.sh"
fail() { echo "FAIL $1" >&2; exit 1; }
pass() { echo "PASS $1"; }

bash -n "$VERIFY" || fail syntax
"$VERIFY" >/dev/null || fail verifier

for needle in \
  'User=aetheris-node' 'Group=aetheris' 'RuntimeDirectory=aetheris/aetheris-node' \
  'RuntimeDirectoryMode=0750' 'StateDirectory=aetheris/node/aetheris-node' \
  'StateDirectoryMode=0750' 'Restart=on-failure' 'RestartSec=10s' \
  'StartLimitIntervalSec=60s' 'StartLimitBurst=5' 'journald' \
  'AETHERIS_NODE_AGENT' '4cbea2ff1018a604cfa6b063545efc155e70fc5b'; do
  grep -Fq "$needle" "$DOC" || fail "doc $needle"
done

grep -Fqx 'ExecStart=@AETHERIS_NODE_EXECSTART@' "$TEMPLATE" || fail unresolved-token
grep -Fqx 'ConditionPathIsExecutable=@AETHERIS_NODE_EXECSTART@' "$TEMPLATE" || fail unresolved-condition
! grep -Eq '^ExecStart=[^@/]' "$TEMPLATE" || fail nonabsolute-exec
! grep -Eq 'docker\.sock|^User=root$|^Group=docker$|^SupplementaryGroups=|^DeviceAllow=|^DevicePolicy=|^PrivateDevices=yes|^LogsDirectory=' "$TEMPLATE" || fail forbidden-policy
! grep -Eq '/home/py5hc|machine-id|aetheris-edge-02' "$TEMPLATE" "$VERIFY" || fail machine-specific-template
! grep -Eq 'useradd|groupadd|usermod|systemctl (enable|start|restart|daemon-reload)|apt|dpkg|nvpmodel|tmpfiles --create|chown|chmod|mkdir' "$VERIFY" || fail verifier-mutation

for section in '[Unit]' '[Service]'; do grep -Fq "$section" "$TEMPLATE" || fail "section $section"; done
unit_line=$(grep -n '^StartLimitIntervalSec=' "$TEMPLATE" | cut -d: -f1)
service_line=$(grep -n '^\[Service\]' "$TEMPLATE" | cut -d: -f1)
[ "$unit_line" -lt "$service_line" ] || fail start-limit-section
restart_line=$(grep -n '^Restart=' "$TEMPLATE" | cut -d: -f1)
[ "$restart_line" -gt "$service_line" ] || fail restart-section

fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
run_reject() {
  local name="$1" expression="$2" fixture="$fixture_dir/$1.service"
  cp "$TEMPLATE" "$fixture"
  sed -i "$expression" "$fixture"
  if AETHERIS_NODE_CONTRACT_FILE="$fixture" "$VERIFY" >/dev/null 2>&1; then
    fail "fixture accepted: $name"
  fi
}
run_reject wrong-user 's/^User=aetheris-node$/User=wrong-user/'
run_reject wrong-group 's/^Group=aetheris$/Group=wrong-group/'
run_reject root-user 's/^User=aetheris-node$/User=root/'
run_reject docker-group 's/^Group=aetheris$/Group=docker/'
run_reject supplementary 's/^Group=aetheris$/Group=aetheris\nSupplementaryGroups=video/'
run_reject wrong-runtime 's#^RuntimeDirectory=.*#RuntimeDirectory=wrong/leaf#'
run_reject wrong-state 's#^StateDirectory=.*#StateDirectory=wrong/leaf#'
run_reject wrong-restart 's/^Restart=on-failure$/Restart=always/'
run_reject wrong-start-limit 's/^StartLimitBurst=5$/StartLimitBurst=1/'
run_reject unresolved-render 's#^ConditionPathIsExecutable=.*#ConditionPathIsExecutable=/opt/aetheris/releases/r1/bin/aetheris-node#; s#^ExecStart=.*#ExecStart=@AETHERIS_NODE_EXECSTART@#'
run_reject missing-executable 's#^ConditionPathIsExecutable=.*#ConditionPathIsExecutable=/opt/aetheris/releases/r1/bin/aetheris-node#; s#^ExecStart=.*#ExecStart=/opt/aetheris/releases/r1/bin/aetheris-node#'
run_reject relative-executable 's#^ConditionPathIsExecutable=.*#ConditionPathIsExecutable=relative/node#; s#^ExecStart=.*#ExecStart=relative/node#'
run_reject home-executable 's#^ConditionPathIsExecutable=.*#ConditionPathIsExecutable=/home/agent/node#; s#^ExecStart=.*#ExecStart=/home/agent/node#'
run_reject device-policy 's/^UMask=0027$/DevicePolicy=closed\nUMask=0027/'
pass 'production verifier negative fixtures'
git_mode() { local expected="$1" path="$2" actual; actual=$(git -C "$ROOT_DIR" ls-files --stage -- "$path" | awk 'NR==1 {print $1}'); [ "$actual" = "$expected" ]; }
git_mode 100644 docs/G3.2-node-service-execution-contract.md && \
git_mode 100644 templates/aetheris-node.service.template && \
git_mode 100755 scripts/verify-node-service-contract.sh && \
git_mode 100755 tests/g3.2-node-service-execution-static-check.sh || fail git-modes
pass 'canonical Git modes'
echo G3_2_NODE_SERVICE_EXECUTION_STATIC_CHECK=PASS
