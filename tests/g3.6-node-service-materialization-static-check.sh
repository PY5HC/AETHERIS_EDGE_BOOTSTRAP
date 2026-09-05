#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "FAIL $1" >&2; exit 1; }
for file in "$ROOT_DIR/scripts/render-node-service-contract.sh" "$ROOT_DIR/scripts/verify-node-service-materialization.sh"; do bash -n "$file" || fail syntax; done
M="$ROOT_DIR/scripts/materialize-node-agent-release.sh"
bash -n "$M" || fail materializer-syntax
T="$ROOT_DIR/templates/aetheris-node.service.g3.6.template"
D="$ROOT_DIR/docs/G3.6-node-service-materialization.md"
for needle in 'User=aetheris-node' 'Group=aetheris' 'RuntimeDirectory=aetheris/aetheris-node' 'RuntimeDirectoryMode=0750' 'StateDirectory=aetheris/node/aetheris-node' 'StateDirectoryMode=0750' 'Restart=on-failure' 'RestartSec=10s' 'StartLimitIntervalSec=60s' 'StartLimitBurst=5' 'StandardOutput=journal' 'StandardError=journal' 'EnvironmentFile=/etc/aetheris/node/identity.env'; do grep -Fqx "$needle" "$T" || fail "template $needle"; done
grep -Fq '127.0.0.1' "$T" || fail loopback
grep -Fq 'activation' "$D" || true
! grep -Eq 'docker\.sock|DeviceAllow=|DevicePolicy=|^PrivateDevices=yes$|^User=root$|^Group=docker$|/home/py5hc|machine-id|aetheris-edge-02' "$T" || fail unsafe-template
! grep -Eq 'systemctl (enable|start|restart|daemon-reload)|useradd|groupadd|mkdir|chown|chmod|apt|nvpmodel[[:space:]]+(-m|-f|--force)' "$ROOT_DIR/scripts/render-node-service-contract.sh" "$ROOT_DIR/scripts/verify-node-service-materialization.sh" || fail live-mutation
! grep -Eq 'useradd|groupadd|docker\.sock|nvpmodel[[:space:]]+(-m|-f|--force)|sudoers|NOPASSWD' "$M" || fail forbidden-authority
grep -Fq 'AETHERIS_LIVE_APPLY=YES' "$M" || fail explicit-live-gate
grep -Fq 'release-already-present' "$M" || fail immutable-release
grep -Fq 'nvpmodel -q' "$M" || fail power-preflight
grep -Fq 'nvidia-ctk cdi list' "$M" || fail cdi-preflight
grep -Fq 'failed-units' "$M" || fail failed-unit-preflight
for pair in '100644 docs/G3.6-node-service-materialization.md' '100644 templates/aetheris-node.service.g3.6.template' '100755 scripts/render-node-service-contract.sh' '100755 scripts/verify-node-service-materialization.sh' '100755 scripts/materialize-node-agent-release.sh' '100755 tests/g3.6-node-service-materialization-static-check.sh'; do set -- $pair; mode=$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR==1{print $1}'); [ "$mode" = "$1" ] || fail "mode $2"; done
echo G3_6_NODE_SERVICE_MATERIALIZATION_STATIC_CHECK=PASS
