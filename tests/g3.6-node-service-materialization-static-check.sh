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
grep -Fq 'ConditionPathExists=@RELEASE_EXECUTABLE@' "$T" || fail valid-condition
! grep -Fq 'ConditionPathIsExecutable=' "$T" || fail unsupported-condition
grep -Fq '[Install]' "$T" || fail install-section
grep -Fq 'WantedBy=multi-user.target' "$T" || fail boot-enable
grep -Fq '127.0.0.1' "$T" || fail loopback
grep -Fq 'activation' "$D" || true
! grep -Eq 'docker\.sock|DeviceAllow=|DevicePolicy=|^PrivateDevices=yes$|^User=root$|^Group=docker$|/home/py5hc|machine-id|aetheris-edge-02' "$T" || fail unsafe-template
! grep -Eq 'systemctl (enable|start|restart|daemon-reload)|useradd|groupadd|mkdir|chown|chmod|apt|nvpmodel[[:space:]]+(-m|-f|--force)' "$ROOT_DIR/scripts/render-node-service-contract.sh" "$ROOT_DIR/scripts/verify-node-service-materialization.sh" || fail live-mutation
! grep -Eq 'useradd|groupadd|docker\.sock|nvpmodel[[:space:]]+(-m|-f|--force)|sudoers|NOPASSWD|/home/' "$M" || fail forbidden-authority
grep -Fq 'AETHERIS_LIVE_APPLY=YES' "$M" || fail explicit-live-gate
grep -Fq 'release-already-present' "$M" || fail immutable-release
grep -Fq 'nvpmodel -q' "$M" || fail power-preflight
grep -Fq 'nvidia-ctk cdi list' "$M" || fail cdi-preflight
grep -Fq 'nvidia\.com/gpu=' "$M" || fail cdi-gpu-namespace
! grep -Fq 'grep -q NVIDIA' "$M" || fail cdi-brand-text
grep -Fq 'failed-units' "$M" || fail failed-unit-preflight
grep -Fq 'STAGING_ROOT=' "$M" || fail atomic-staging
grep -Fq 'sudo mv -- "$STAGING_ROOT" "$RELEASE_ROOT"' "$M" || fail atomic-promotion
grep -Fq 'verify_installed' "$M" || fail post-copy-verification
grep -Fq 'EXECUTABLES=' "$M" || fail executable-mode-contract
grep -Fq 'chmod 0750 "$STAGING_ROOT/$runtime_exec"' "$M" || fail executable-mode-preservation
grep -Fq 'sudo -u aetheris-node' "$M" || fail service-user-runtime-probe
grep -Fq 'CONVERGENCE=PASS' "$M" || fail convergence-mode
grep -Fq 'systemd-analyze verify' "$M" || fail unit-prevalidation
grep -Fq 'UNIT_TMP_DIR=' "$M" || fail canonical-unit-temp-directory
grep -Fq 'UNIT_TMP="$UNIT_TMP_DIR/aetheris-node.service"' "$M" || fail canonical-unit-temp-basename
! grep -Fq 'UNIT_TMP="$(mktemp --suffix=.service)"' "$M" || fail anonymous-unit-temp
grep -Fq 'POST_START_VALIDATION=PASS' "$M" || fail post-start-validation
grep -Fq 'UNIT_INSTALLED=YES' "$M" || fail unit-rollback-state
grep -Fq 'journalctl -u aetheris-node.service' "$M" || fail journald-validation
grep -Fq 'non-loopback-listener' "$M" || fail loopback-validation
grep -Fq 'identity.env' "$M" || fail g3-hash-validation
grep -Fq 'AUTHORITY_TAG=' "$M" || fail authority-tag
grep -Fq 'origin/main' "$M" || fail remote-authority
grep -Fq 'repository-authority-delta' "$M" || fail authority-delta
grep -Fq 'UNIT_INSTALLED=YES' "$M" || fail unit-transaction-state
grep -Fq 'sudo rm -f -- "$UNIT_PATH"' "$M" || fail unit-rollback
grep -Fq '20260905-node-agent-r5' "$M" || fail corrected-release-authority
grep -Fq 'ffc06dd03e387ee234951926fe0e22822bc3f9cd4365c6548dca639c85bd6daa' "$M" || fail corrected-manifest-authority
for needle in 'RELEASE_PROMOTED=NO' 'UNIT_ENABLED=NO' 'SERVICE_STARTED=NO' 'UNIT_TMP_SHA=' 'sudo systemctl stop aetheris-node.service' 'sudo systemctl disable aetheris-node.service' 'systemctl is-enabled --quiet aetheris-node.service' 'RELEASE_PRESERVED=YES' 'PLATFORM_REGRESSION=' 'ROLLBACK_RESULT='; do grep -Fq "$needle" "$M" || fail "rollback $needle"; done
for needle in 'fail unit-verify' 'fail service-enable' 'fail service-start' 'listener-timeout' 'health-timeout' 'readiness-timeout' 'run_post_mutation_validation' 'if ! run_post_mutation_validation' 'POST_VALIDATION_FAILURE=' 'CONVERGENCE_TIMEOUT_SEC=' 'CONVERGENCE_POLL_SEC='; do grep -Fq "$needle" "$M" || fail "convergence $needle"; done
! grep -Fq 'fail listener' "$M" || fail instantaneous-listener-failure
! grep -Fq 'fail health' "$M" || fail instantaneous-health-failure
! grep -Fq 'fail readiness' "$M" || fail instantaneous-readiness-failure

cdi_has_gpu(){ printf '%s\n' "$1" | grep -Eq '^nvidia\.com/gpu='; }
cdi_has_gpu $'nvidia.com/gpu=0\nnvidia.com/gpu=all' || fail cdi-positive
cdi_has_gpu $'nvidia.com/pva=0\nnvidia.com/pva=all' && fail cdi-pva-only
cdi_has_gpu $'vendor/gpu=0\nother/device=all' && fail cdi-unrelated
cdi_has_gpu "" && fail cdi-empty-fixture
cdi_query_nonzero(){ return 1; }
if cdi_query_nonzero; then fail cdi-nonzero-fixture; fi
echo PASS CDI GPU namespace fixtures

# Isolated convergence/rollback state-machine fixtures. These model the
# observable systemd/socket/HTTP state and assert final state, rather than
# merely checking that cleanup commands were requested.
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT
fixture_begin(){
  rm -rf -- "$FIXTURE_ROOT/state"
  mkdir -p "$FIXTURE_ROOT/state/runtime" "$FIXTURE_ROOT/state/state"
  : > "$FIXTURE_ROOT/state/active"
  : > "$FIXTURE_ROOT/state/enabled"
  : > "$FIXTURE_ROOT/state/unit"
  : > "$FIXTURE_ROOT/state/link"
  : > "$FIXTURE_ROOT/state/failed"
}
fixture_rollback(){
  if [ "${FIXTURE_CLEANUP_FAIL:-NO}" = YES ]; then
    : > "$FIXTURE_ROOT/state/rollback-failed"
    return 1
  fi
  rm -f "$FIXTURE_ROOT/state/active" "$FIXTURE_ROOT/state/enabled" "$FIXTURE_ROOT/state/unit" "$FIXTURE_ROOT/state/link" "$FIXTURE_ROOT/state/failed"
  rm -rf "$FIXTURE_ROOT/state/runtime" "$FIXTURE_ROOT/state/state"
  return 0
}
fixture_poll(){
  local target="$1" appearance="$2" attempt=0
  while [ "$attempt" -lt 4 ]; do
    attempt=$((attempt + 1))
    if [ "$appearance" = died ] && [ "$attempt" -ge 2 ]; then rm -f "$FIXTURE_ROOT/state/active"; return 2; fi
    if [ "$appearance" = immediate ] || { [ "$appearance" = delayed ] && [ "$attempt" -ge 2 ]; }; then : > "$FIXTURE_ROOT/state/$target"; fi
    [ -e "$FIXTURE_ROOT/state/active" ] || return 2
    [ -e "$FIXTURE_ROOT/state/$target" ] && return 0
  done
  return 1
}
fixture_deploy_case(){
  local listener_mode="$1" health_mode="$2" readiness_mode="$3" expected="$4"
  fixture_begin
  if ! fixture_poll listener "$listener_mode" || ! fixture_poll health "$health_mode" || ! fixture_poll readiness "$readiness_mode"; then
    if fixture_rollback; then [ "$expected" = rollback ] || return 1; else [ "$expected" = rollback-fail ] || return 1; fi
  else
    [ "$expected" = success ] || return 1
    [ ! -e "$FIXTURE_ROOT/state/rollback-failed" ] || return 1
    return 0
  fi
  if [ "$expected" = rollback-fail ]; then
    [ -e "$FIXTURE_ROOT/state/rollback-failed" ] && [ -e "$FIXTURE_ROOT/state/unit" ]
  else
    [ ! -e "$FIXTURE_ROOT/state/active" ] && [ ! -e "$FIXTURE_ROOT/state/enabled" ] && [ ! -e "$FIXTURE_ROOT/state/unit" ] && [ ! -e "$FIXTURE_ROOT/state/link" ]
  fi
}
fixture_deploy_case immediate immediate immediate success || fail fixture-immediate-success
fixture_deploy_case delayed immediate immediate success || fail fixture-delayed-listener
fixture_deploy_case immediate delayed immediate success || fail fixture-delayed-health
fixture_deploy_case immediate immediate delayed success || fail fixture-delayed-readiness
fixture_deploy_case never immediate immediate rollback || fail fixture-listener-timeout
fixture_deploy_case died immediate immediate rollback || fail fixture-service-died
fixture_deploy_case immediate never immediate rollback || fail fixture-health-timeout
fixture_deploy_case immediate immediate never rollback || fail fixture-readiness-timeout
FIXTURE_CLEANUP_FAIL=YES fixture_deploy_case never immediate immediate rollback-fail || fail fixture-rollback-failure
echo PASS convergence final-state fixtures
for pair in '100644 docs/G3.6-node-service-materialization.md' '100644 templates/aetheris-node.service.g3.6.template' '100755 scripts/render-node-service-contract.sh' '100755 scripts/verify-node-service-materialization.sh' '100755 scripts/materialize-node-agent-release.sh' '100755 tests/g3.6-node-service-materialization-static-check.sh'; do set -- $pair; mode=$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR==1{print $1}'); [ "$mode" = "$1" ] || fail "mode $2"; done
echo G3_6_NODE_SERVICE_MATERIALIZATION_STATIC_CHECK=PASS
