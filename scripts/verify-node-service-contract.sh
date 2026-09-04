#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.2-node-service-execution-contract.md"
TEMPLATE="$ROOT_DIR/templates/aetheris-node.service.template"
CONTRACT_FILE="${AETHERIS_NODE_CONTRACT_FILE:-$TEMPLATE}"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS %s\n' "$1"; }

[ -f "$DOC" ] || fail 'design document missing'
[ -f "$TEMPLATE" ] || fail 'service template missing'
[ -f "$CONTRACT_FILE" ] || fail 'contract file missing'
[ ! -e "$ROOT_DIR/files/etc/systemd/system/aetheris-node.service" ] || fail 'live unit artifact present'

grep -Fqx 'User=aetheris-node' "$CONTRACT_FILE" || fail 'service user'
grep -Fqx 'Group=aetheris' "$CONTRACT_FILE" || fail 'service group'
grep -Fqx 'RuntimeDirectory=aetheris/aetheris-node' "$CONTRACT_FILE" || fail 'runtime directory'
grep -Fqx 'RuntimeDirectoryMode=0750' "$CONTRACT_FILE" || fail 'runtime mode'
grep -Fqx 'StateDirectory=aetheris/node/aetheris-node' "$CONTRACT_FILE" || fail 'state directory'
grep -Fqx 'StateDirectoryMode=0750' "$CONTRACT_FILE" || fail 'state mode'
grep -Fqx 'Restart=on-failure' "$CONTRACT_FILE" || fail 'restart policy'
grep -Fqx 'RestartSec=10s' "$CONTRACT_FILE" || fail 'restart delay'
grep -Fqx 'StartLimitIntervalSec=60s' "$CONTRACT_FILE" || fail 'start limit interval'
grep -Fqx 'StartLimitBurst=5' "$CONTRACT_FILE" || fail 'start limit burst'
grep -Fqx 'StandardOutput=journal' "$CONTRACT_FILE" || fail 'journal output'
grep -Fqx 'StandardError=journal' "$CONTRACT_FILE" || fail 'journal error'

if [ "$CONTRACT_FILE" = "$TEMPLATE" ]; then
  grep -Fqx 'ExecStart=@AETHERIS_NODE_EXECSTART@' "$CONTRACT_FILE" || fail 'unresolved executable guard'
  grep -Fqx 'ConditionPathIsExecutable=@AETHERIS_NODE_EXECSTART@' "$CONTRACT_FILE" || fail 'executable condition guard'
else
  ! grep -Fq '@AETHERIS_NODE_EXECSTART@' "$CONTRACT_FILE" || fail 'unresolved rendered executable'
  rendered_exec="$(awk -F= '$1 == "ExecStart" { print substr($0, index($0, "=") + 1); exit }' "$CONTRACT_FILE")"
  [[ "$rendered_exec" = /* ]] || fail 'non-absolute executable'
  [[ "$rendered_exec" = /opt/aetheris/releases/* ]] || fail 'executable outside governed releases'
  [ -x "$rendered_exec" ] || fail 'rendered executable missing'
fi
! grep -Eq '^ExecStart=(/home|/usr/local/bin|/tmp|\$|/bin/sh|/bin/bash)' "$CONTRACT_FILE" || fail 'unsafe executable authority'
! grep -Eq 'docker\.sock|^User=root$|^Group=docker$|^SupplementaryGroups=|sudo|DeviceAllow=|DevicePolicy=|^PrivateDevices=yes$|^LogsDirectory=' "$CONTRACT_FILE" || fail 'deferred authority present'

grep -Fq '/opt/aetheris/current' "$DOC" || fail 'release path documentation'
grep -Fq 'remains a directory in v1' "$DOC" || fail 'release directory semantics'
grep -Fq 'journald' "$DOC" || fail 'logging authority'
grep -Fq 'not established' "$DOC" || fail 'unresolved authority documentation'
grep -Fq 'NoNewPrivileges=yes' "$DOC" || fail 'hardening decision'

pass 'service contract is unresolved and non-installable'
printf 'G3_2_NODE_SERVICE_CONTRACT_VERIFY=PASS\n'
