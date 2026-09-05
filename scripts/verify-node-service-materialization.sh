#!/usr/bin/env bash
set -euo pipefail
UNIT="${AETHERIS_NODE_UNIT_FILE:-}"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
[ -n "$UNIT" ] && [ -f "$UNIT" ] || fail unit
grep -Fqx 'User=aetheris-node' "$UNIT" || fail user
grep -Fqx 'Group=aetheris' "$UNIT" || fail group
grep -Fqx 'RuntimeDirectory=aetheris/aetheris-node' "$UNIT" || fail runtime
grep -Fqx 'RuntimeDirectoryMode=0750' "$UNIT" || fail runtime-mode
grep -Fqx 'StateDirectory=aetheris/node/aetheris-node' "$UNIT" || fail state
grep -Fqx 'StateDirectoryMode=0750' "$UNIT" || fail state-mode
grep -Fqx 'Restart=on-failure' "$UNIT" || fail restart
grep -Fqx 'RestartSec=10s' "$UNIT" || fail restart-sec
grep -Fqx 'StartLimitIntervalSec=60s' "$UNIT" || fail limit-interval
grep -Fqx 'StartLimitBurst=5' "$UNIT" || fail limit-burst
grep -Fqx 'StandardOutput=journal' "$UNIT" || fail stdout
grep -Fqx 'StandardError=journal' "$UNIT" || fail stderr
grep -Fqx 'Environment=AETHERIS_NODE_BIND_HOST=127.0.0.1' "$UNIT" || fail bind
exec_path="$(awk -F= '$1=="ExecStart"{print substr($0,index($0,"=")+1); exit}' "$UNIT")"
grep -Fqx "ConditionPathExists=$exec_path" "$UNIT" || fail condition
grep -Fqx 'WantedBy=multi-user.target' "$UNIT" || fail install-target
[[ "$exec_path" = /opt/aetheris/releases/*/venv/bin/* ]] || fail exec-path
[ -x "$exec_path" ] || fail exec-missing
! grep -Eq '@|docker\.sock|^User=root$|^Group=docker$|^SupplementaryGroups=|DeviceAllow=|DevicePolicy=|^PrivateDevices=yes$|LogsDirectory=|/home/|/usr/local/bin/' "$UNIT" || fail unsafe-authority
printf 'G3_6_NODE_SERVICE_VERIFY=PASS\n'
