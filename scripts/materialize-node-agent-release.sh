#!/usr/bin/env bash
set -Eeuo pipefail

# First-release materializer. Validation-only is the default. Live execution
# requires AETHERIS_LIVE_APPLY=YES and an authenticated interactive sudo.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_RELEASE="${AETHERIS_STAGED_RELEASE:-}"
LIVE_APPLY="${AETHERIS_LIVE_APPLY:-NO}"
CONVERGENCE="${AETHERIS_CONVERGENCE:-NO}"
EXPECTED_BOOTSTRAP_MAIN="56ab37d5d216c9fab26f97487068d22d8e706286"
AUTHORITY_TAG="g3.6-final-materializer"
EXPECTED_MANIFEST_SHA="ffc06dd03e387ee234951926fe0e22822bc3f9cd4365c6548dca639c85bd6daa"
EXPECTED_RELEASE_ID="20260905-node-agent-r5"
EXPECTED_LOCK_SHA="ce7d86147a73c9b701f57a0d7e11f968c9df9eae5c0430a3064171df64033b01"
UNIT_PATH=/etc/systemd/system/aetheris-node.service
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
for tool in git python3 sha256sum awk sudo sed find mktemp; do need "$tool"; done
[ -d "$STAGED_RELEASE" ] || fail staged-release
[ -f "$STAGED_RELEASE/manifest.json" ] || fail staged-manifest
[ "$(git -C "$ROOT_DIR" branch --show-current)" = main ] || fail repository-branch
CURRENT_HEAD="$(git -C "$ROOT_DIR" rev-parse HEAD)"
if git -C "$ROOT_DIR" rev-parse --verify -q "refs/tags/$AUTHORITY_TAG^{commit}" >/dev/null; then
  git -C "$ROOT_DIR" fetch --quiet origin main || fail remote-authority-fetch
  [ "$CURRENT_HEAD" = "$(git -C "$ROOT_DIR" rev-parse origin/main)" ] || fail repository-remote-mismatch
  AUTHORITY_DELTA="$(git -C "$ROOT_DIR" diff --name-only "$AUTHORITY_TAG^{commit}" "$CURRENT_HEAD")"
  EXPECTED_AUTHORITY_DELTA=$'docs/G3.6-node-service-materialization.md\nschemas/node-agent-release-manifest.schema.json\nscripts/build-node-agent-release.sh\nscripts/materialize-node-agent-release.sh\nscripts/render-node-service-contract.sh\nscripts/verify-node-service-materialization.sh\ntemplates/aetheris-node.service.g3.6.template\ntemplates/node-agent-release-manifest.json.template\ntests/g3.3-node-agent-release-contract-static-check.sh\ntests/g3.6-node-service-materialization-static-check.sh'
  [ "$AUTHORITY_DELTA" = "$EXPECTED_AUTHORITY_DELTA" ] || fail repository-authority-delta
else
  [ "$CURRENT_HEAD" = "$EXPECTED_BOOTSTRAP_MAIN" ] || fail repository-authority
fi
[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ] || fail repository-dirty
MANIFEST="$STAGED_RELEASE/manifest.json"
MANIFEST_SHA="$(sha256sum "$MANIFEST" | awk '{print $1}')"
[ "$MANIFEST_SHA" = "$EXPECTED_MANIFEST_SHA" ] || fail manifest-sha
readarray -t FACTS < <(python3 - "$MANIFEST" <<'PY'
import json, re, sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
def req(v, name):
    if not isinstance(v, str) or not v: raise SystemExit(name)
if d.get('schema_version') != '1.0': raise SystemExit('schema')
if d.get('repository') != 'PY5HC/AETHERIS_NODE_AGENT': raise SystemExit('repository')
if d.get('source_commit') != '4bb897e6b18644199ac89ad33be9292e7487c37b': raise SystemExit('source')
if d.get('architecture') != 'aarch64': raise SystemExit('architecture')
if d.get('package') != {'name':'aetheris-node-agent','version':'0.1.0'}: raise SystemExit('package')
g=d.get('governance',{})
if g != {'repository':'PY5HC/AETHERIS_GOVERNANCE','revision':'ff1318cd8f0a9720f66029e3985d1e5854044128','governance_version':'1.3.0','profile':'NOT_YET_ESTABLISHED','contract_version':'1.0.0'}: raise SystemExit('governance')
rid=d.get('release_id','')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}',rid): raise SystemExit('release-id')
rel=d.get('entrypoint',{}).get('relative_path','')
if not re.fullmatch(r'(?:bin|venv/bin)/[A-Za-z0-9._/-]+',rel) or '..' in rel: raise SystemExit('entrypoint')
if d.get('entrypoint', {}).get('runner_kind') != 'project-runner': raise SystemExit('runner')
if d.get('runtime') != {'model':'release-venv','python_executable':'venv/bin/python','executables':['venv/bin/aetheris-node-agent','venv/bin/python','venv/bin/python3','venv/bin/python3.12']}: raise SystemExit('runtime')
if d.get('artifact',{}).get('release_root') != '/opt/aetheris/releases': raise SystemExit('release-root')
if d.get('health',{}).get('liveness_path') != '/api/v1/health' or d.get('health',{}).get('readiness_path') != '/api/v1/health': raise SystemExit('health')
if d.get('activation') != {'requires_hash_verification':True,'requires_readiness_probe':True,'rollback_release_required':True}: raise SystemExit('activation')
print(rid); print(rel); print(d['artifact']['sha256']); print(d['dependencies']['provenance']); print(*d['runtime']['executables'], sep='\n')
PY
) || fail manifest-semantics
RELEASE_ID="${FACTS[0]}"; EXEC_REL="${FACTS[1]}"; EXPECTED_ARTIFACT_SHA="${FACTS[2]}"; LOCK_PROVENANCE="${FACTS[3]}"; EXECUTABLES=("${FACTS[@]:4}")
[ "$RELEASE_ID" = "$EXPECTED_RELEASE_ID" ] || fail release-id-authority
WHEEL="$(find "$STAGED_RELEASE/metadata" -maxdepth 1 -type f -name '*.whl' -print -quit)"; [ -n "$WHEEL" ] || fail wheel
[ "$(sha256sum "$WHEEL" | awk '{print $1}')" = "$EXPECTED_ARTIFACT_SHA" ] || fail artifact-sha
LOCK="$STAGED_RELEASE/metadata/requirements.lock"; [ -f "$LOCK" ] || fail lock
[ "$LOCK_PROVENANCE" = "requirements.lock:$EXPECTED_LOCK_SHA" ] || fail lock-provenance
[ "$(sha256sum "$LOCK" | awk '{print $1}')" = "$EXPECTED_LOCK_SHA" ] || fail lock-sha
[ -x "$STAGED_RELEASE/$EXEC_REL" ] || fail staged-entrypoint
RELEASE_ROOT="/opt/aetheris/releases/$RELEASE_ID"
UNIT_TMP="$(mktemp --suffix=.service)"; REPORT="${AETHERIS_REPORT_PATH:-/tmp/aetheris-g3.6-live-apply-$(date -u +%Y%m%dT%H%M%SZ).report}"; STAGING_ROOT=""; RELEASE_PROMOTED=NO; UNIT_INSTALLED=NO; UNIT_ENABLED=NO; SERVICE_STARTED=NO; SERVICE_STOPPED=NO; UNIT_DISABLED=NO; UNIT_REMOVED=NO; STATE_PREEXISTING=NO; RUNTIME_PREEXISTING=NO; STATE_ACTION=NOT_NEEDED; RUNTIME_ACTION=NOT_NEEDED; RELEASE_PRESERVED=NO
rollback(){
  set +e
  [ -n "$STAGING_ROOT" ] && sudo rm -rf -- "$STAGING_ROOT"
  if [ "$RELEASE_PROMOTED" = YES ] || [ "$UNIT_INSTALLED" = YES ]; then
    if sudo systemctl is-active --quiet aetheris-node.service; then sudo systemctl stop aetheris-node.service; SERVICE_STOPPED=YES; fi
  fi
  if [ "$UNIT_INSTALLED" = YES ] && sudo systemctl is-enabled --quiet aetheris-node.service; then sudo systemctl disable aetheris-node.service; UNIT_DISABLED=YES; fi
  if [ "$UNIT_INSTALLED" = YES ] && sudo test -f "$UNIT_PATH" && [ "$(sudo sha256sum "$UNIT_PATH" | awk '{print $1}')" = "$UNIT_TMP_SHA" ]; then sudo rm -f -- "$UNIT_PATH"; UNIT_REMOVED=YES; fi
  if [ "$UNIT_INSTALLED" = YES ] || [ "$UNIT_ENABLED" = YES ]; then sudo systemctl daemon-reload; fi
  if [ "$UNIT_INSTALLED" = YES ]; then sudo systemctl reset-failed aetheris-node.service; fi
  if [ "$RUNTIME_PREEXISTING" = NO ] && sudo test -d /run/aetheris/aetheris-node; then
    if [ -z "$(sudo find /run/aetheris/aetheris-node -mindepth 1 -print -quit)" ]; then sudo rmdir /run/aetheris/aetheris-node; RUNTIME_ACTION=REMOVED_EMPTY_TRANSACTION_LEAF; else RUNTIME_ACTION=RETAINED_NONEMPTY_REVIEW_REQUIRED; fi
  fi
  if [ "$STATE_PREEXISTING" = NO ] && sudo test -d /var/lib/aetheris/node/aetheris-node; then
    if [ -z "$(sudo find /var/lib/aetheris/node/aetheris-node -mindepth 1 -print -quit)" ]; then sudo rmdir /var/lib/aetheris/node/aetheris-node; STATE_ACTION=REMOVED_EMPTY_TRANSACTION_LEAF; else STATE_ACTION=RETAINED_NONEMPTY_REVIEW_REQUIRED; fi
  fi
  [ "$RELEASE_PROMOTED" = YES ] && RELEASE_PRESERVED=YES
  PLATFORM_REGRESSION=NOT_APPLICABLE
  if [ "$RELEASE_PROMOTED" = YES ] || [ "$UNIT_INSTALLED" = YES ]; then
    PLATFORM_REGRESSION=PASS
    sudo systemctl is-active --quiet aetheris-node.service && PLATFORM_REGRESSION=FAIL
    sudo systemctl is-enabled --quiet aetheris-node.service && PLATFORM_REGRESSION=FAIL
    sudo test -e "$UNIT_PATH" && [ "$UNIT_REMOVED" = YES ] && PLATFORM_REGRESSION=FAIL
    [ -e /run/aetheris/aetheris-node ] && PLATFORM_REGRESSION=FAIL
    [ -n "$(sudo systemctl --failed --no-legend --plain)" ] && PLATFORM_REGRESSION=FAIL
    sudo ss -ltnH | grep -Eq '[[:space:]](:|\])8000[[:space:]]' && PLATFORM_REGRESSION=FAIL
    sudo sha256sum /etc/aetheris/node/identity.env | grep -Fq 9cc789d4df7aaea3849628c19a7f58bce7622f4bb7e859327f859ae6cadd676e || PLATFORM_REGRESSION=FAIL
    sudo sha256sum /etc/aetheris/node/capabilities.json | grep -Fq 3ede11bbbdd1075516ae93b6d700eca52c8d1591401b5753eea72b8e8e0c8acb || PLATFORM_REGRESSION=FAIL
    sudo sha256sum /usr/lib/tmpfiles.d/aetheris.conf | grep -Fq d9375b8fd53be99eee8bc6bcde02663c540408983f88eedba4eb13c97bc0991d || PLATFORM_REGRESSION=FAIL
    sudo /usr/sbin/nvpmodel -q 2>/dev/null | grep -Fq 'NV Power Mode: MAXN_SUPER' || PLATFORM_REGRESSION=FAIL
    sudo /usr/sbin/nvpmodel -q 2>/dev/null | grep -Eq '^2$' || PLATFORM_REGRESSION=FAIL
    sudo nvidia-ctk cdi list 2>/dev/null | grep -Eq '^nvidia\.com/gpu=' || PLATFORM_REGRESSION=FAIL
    [ "$STATE_ACTION" = RETAINED_NONEMPTY_REVIEW_REQUIRED ] && PLATFORM_REGRESSION=FAIL
    [ "$RUNTIME_ACTION" = RETAINED_NONEMPTY_REVIEW_REQUIRED ] && PLATFORM_REGRESSION=FAIL
  fi
  ROLLBACK_RESULT=PASS
  [ "$UNIT_INSTALLED" = YES ] && [ "$UNIT_REMOVED" != YES ] && ROLLBACK_RESULT=REVIEW_REQUIRED
  [ "$PLATFORM_REGRESSION" = FAIL ] && ROLLBACK_RESULT=FAIL
  printf 'ROLLBACK_TRIGGER=%s\nRELEASE_PROMOTED=%s\nSERVICE_STARTED=%s\nSERVICE_STOPPED=%s\nUNIT_DISABLED=%s\nUNIT_REMOVED=%s\nSTATE_ACTION=%s\nRUNTIME_ACTION=%s\nPLATFORM_REGRESSION=%s\nRELEASE_PRESERVED=%s\nROLLBACK_RESULT=%s\n' "$ROLLBACK_TRIGGER" "$RELEASE_PROMOTED" "$SERVICE_STARTED" "$SERVICE_STOPPED" "$UNIT_DISABLED" "$UNIT_REMOVED" "$STATE_ACTION" "$RUNTIME_ACTION" "$PLATFORM_REGRESSION" "$RELEASE_PRESERVED" "$ROLLBACK_RESULT" | tee -a "$REPORT"
  rm -f "$UNIT_TMP"
}
on_error(){ rc=$?; ROLLBACK_TRIGGER="${ROLLBACK_TRIGGER:-line-$LINENO}"; rollback; exit "$rc"; }
trap on_error ERR
trap 'rm -f "$UNIT_TMP"' EXIT
sed "s#@RELEASE_ROOT@#$RELEASE_ROOT#g; s#@RELEASE_EXECUTABLE@#$RELEASE_ROOT/$EXEC_REL#g" "$ROOT_DIR/templates/aetheris-node.service.g3.6.template" > "$UNIT_TMP"
! grep -Fq '@' "$UNIT_TMP" || fail unresolved-unit
grep -Fqx "ExecStart=$RELEASE_ROOT/$EXEC_REL" "$UNIT_TMP" || fail unit-exec
UNIT_TMP_SHA="$(sha256sum "$UNIT_TMP" | awk '{print $1}')"
sudo -v || fail sudo-auth
sudo -n true || fail authenticated-sudo-required
expect_meta(){ [ "$(sudo stat -c '%U:%G %a' "$1")" = "$2" ] || fail "metadata:$1"; }
expect_meta /etc/aetheris root:aetheris\ 750; expect_meta /etc/aetheris/node root:aetheris\ 750
expect_meta /opt/aetheris root:aetheris\ 755; expect_meta /opt/aetheris/releases root:aetheris\ 755; expect_meta /opt/aetheris/current root:aetheris\ 755
expect_meta /var/lib/aetheris root:aetheris\ 750; expect_meta /var/lib/aetheris/node root:aetheris\ 750; expect_meta /var/log/aetheris root:aetheris\ 750; expect_meta /run/aetheris root:aetheris\ 755
getent group aetheris >/dev/null || fail aetheris-group
[ "$(id -gn aetheris-node)" = aetheris ] || fail account-group; [ "$(getent passwd aetheris-node|cut -d: -f7)" = /usr/sbin/nologin ] || fail account-shell
[ "$(getent passwd aetheris-node|cut -d: -f6)" = /nonexistent ] || fail account-home; [ "$(id -nG aetheris-node)" = aetheris ] || fail account-groups
if getent group docker | grep -Eq '(^|,)aetheris-node(,|$)'; then fail docker-membership; fi
if sudo systemctl --failed --no-legend --plain | grep -q .; then fail failed-units; fi
POWER_QUERY="$(sudo /usr/sbin/nvpmodel -q 2>/dev/null)" || fail nvpmodel-query; grep -Fq 'NV Power Mode: MAXN_SUPER' <<<"$POWER_QUERY" || fail power-profile; grep -Eq '^2$' <<<"$POWER_QUERY" || fail power-mode
CDI_OUTPUT="$(sudo nvidia-ctk cdi list 2>&1)" || { printf '%s\n' "$CDI_OUTPUT" >&2; fail cdi-query; }
grep -Eq '^nvidia\.com/gpu=' <<<"$CDI_OUTPUT" || { printf '%s\n' "$CDI_OUTPUT" >&2; fail cdi-gpu; }
sudo systemctl get-default | grep -Fxq multi-user.target || fail default-target
[ ! -e /run/aetheris/aetheris-node ] || fail runtime-leaf-present; [ ! -e /var/lib/aetheris/node/aetheris-node ] || fail state-leaf-present
if sudo test -e "$UNIT_PATH"; then fail conflicting-unit; fi
expect_g3_hash(){ [ "$(sudo sha256sum "$1"|awk '{print $1}')" = "$2" ] || fail "hash:$1"; }
expect_g3_hash /etc/aetheris/node/identity.env 9cc789d4df7aaea3849628c19a7f58bce7622f4bb7e859327f859ae6cadd676e
expect_g3_hash /etc/aetheris/node/capabilities.json 3ede11bbbdd1075516ae93b6d700eca52c8d1591401b5753eea72b8e8e0c8acb
expect_g3_hash /usr/lib/tmpfiles.d/aetheris.conf d9375b8fd53be99eee8bc6bcde02663c540408983f88eedba4eb13c97bc0991d
verify_installed(){ local root="$1"; expect_meta "$root" root:aetheris\ 755; expect_meta "$root/manifest.json" root:aetheris\ 640; expect_meta "$root/metadata/requirements.lock" root:aetheris\ 640; [ "$(sudo sha256sum "$root/manifest.json"|awk '{print $1}')" = "$MANIFEST_SHA" ] || fail installed-manifest-sha; [ "$(sudo sha256sum "$root/metadata/requirements.lock"|awk '{print $1}')" = "$EXPECTED_LOCK_SHA" ] || fail installed-lock-sha; [ "$(sudo sha256sum "$root/metadata/$(basename "$WHEEL")"|awk '{print $1}')" = "$EXPECTED_ARTIFACT_SHA" ] || fail installed-artifact-sha; for runtime_exec in "${EXECUTABLES[@]}"; do expect_meta "$root/$runtime_exec" root:aetheris\ 750; sudo test -x "$root/$runtime_exec" || fail "installed-runtime-executable:$runtime_exec"; done; sudo env AETHERIS_RELEASE_MANIFEST="$root/manifest.json" "$ROOT_DIR/scripts/verify-node-agent-release-contract.sh" >/dev/null || fail installed-manifest-semantics; }
if sudo test -e "$RELEASE_ROOT"; then
  [ "$CONVERGENCE" = YES ] || fail release-already-present
  verify_installed "$RELEASE_ROOT"; [ -f "$UNIT_PATH" ] || fail unit-absent-in-convergence
  [ "$(sudo sha256sum "$UNIT_PATH"|awk '{print $1}')" = "$(sha256sum "$UNIT_TMP"|awk '{print $1}')" ] || fail unit-sha
  printf 'CONVERGENCE=PASS\nRELEASE_ID=%s\nREPORT=%s\n' "$RELEASE_ID" "$REPORT" | tee "$REPORT"; exit 0
fi
printf 'UTC=%s\nRELEASE_ID=%s\nSTAGED_RELEASE=%s\nMANIFEST_SHA256=%s\nWHEEL_SHA256=%s\nLOCK_SHA256=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RELEASE_ID" "$STAGED_RELEASE" "$MANIFEST_SHA" "$EXPECTED_ARTIFACT_SHA" "$EXPECTED_LOCK_SHA" | tee "$REPORT"
if [ "$LIVE_APPLY" != YES ]; then printf 'VALIDATION_ONLY=PASS\nLIVE_MUTATION=NOT_PERFORMED\nREPORT=%s\n' "$REPORT"; exit 0; fi
STAGING_ROOT="/opt/aetheris/releases/.staging-$RELEASE_ID-$(date -u +%Y%m%dT%H%M%SZ)-$$"; sudo test ! -e "$STAGING_ROOT" || fail staging-collision
sudo install -d -o root -g aetheris -m 0755 "$STAGING_ROOT"; sudo cp -a "$STAGED_RELEASE"/. "$STAGING_ROOT"/
sudo chown -R root:aetheris "$STAGING_ROOT"; sudo find "$STAGING_ROOT" -type d -exec chmod 0755 {} +; sudo find "$STAGING_ROOT" -type f -exec chmod 0640 {} +; for runtime_exec in "${EXECUTABLES[@]}"; do sudo chmod 0750 "$STAGING_ROOT/$runtime_exec"; done
verify_installed "$STAGING_ROOT"; sudo mv -- "$STAGING_ROOT" "$RELEASE_ROOT"; STAGING_ROOT=""; RELEASE_PROMOTED=YES; verify_installed "$RELEASE_ROOT"
sudo systemd-analyze verify "$UNIT_TMP" || fail unit-verify
for runtime_exec in "${EXECUTABLES[@]}"; do sudo -u aetheris-node env PYTHONDONTWRITEBYTECODE=1 test -x "$RELEASE_ROOT/$runtime_exec" || fail service-user-runtime-executable; done
sudo -u aetheris-node env PYTHONDONTWRITEBYTECODE=1 "$RELEASE_ROOT/venv/bin/python" -c 'import aetheris_node_agent, aetheris_node_agent.runner' || fail service-user-runtime-import
sudo install -o root -g root -m 0644 "$UNIT_TMP" "$UNIT_PATH"; UNIT_INSTALLED=YES; sudo systemctl daemon-reload
[ "$(sudo stat -c '%U:%G %a' "$UNIT_PATH")" = 'root:root 644' ] || fail unit-metadata
[ "$(sudo sha256sum "$UNIT_PATH"|awk '{print $1}')" = "$(sha256sum "$UNIT_TMP"|awk '{print $1}')" ] || fail unit-sha
sudo systemctl enable aetheris-node.service || fail service-enable; UNIT_ENABLED=YES
sudo systemctl start aetheris-node.service || fail service-start; SERVICE_STARTED=YES
sudo systemctl is-active --quiet aetheris-node.service || fail service-inactive; sudo systemctl is-enabled --quiet aetheris-node.service || fail service-disabled
MAIN_PID="$(sudo systemctl show -p MainPID --value aetheris-node.service)"; [ "$MAIN_PID" != 0 ] || fail mainpid
[ "$(sudo ps -o user= -p "$MAIN_PID"|tr -d ' ')" = aetheris-node ] || fail process-user; [ "$(sudo ps -o group= -p "$MAIN_PID"|tr -d ' ')" = aetheris ] || fail process-group
GROUPS_LINE="$(sudo awk '/^Groups:/{print $2}' "/proc/$MAIN_PID/status")"; [ "$GROUPS_LINE" = "$(getent group aetheris|cut -d: -f3)" ] || fail process-groups
sudo ss -ltnH | grep -Eq '[[:space:]]127\.0\.0\.1:8000[[:space:]]' || fail listener; ! sudo ss -ltnH | grep -Eq '[[:space:]](0\.0\.0\.0|\[::\]):8000[[:space:]]' || fail non-loopback-listener
curl --fail --silent http://127.0.0.1:8000/api/v1/health >/dev/null || fail health; curl --fail --silent http://127.0.0.1:8000/api/v1/health >/dev/null || fail readiness
expect_meta /run/aetheris/aetheris-node aetheris-node:aetheris\ 750; expect_meta /var/lib/aetheris/node/aetheris-node aetheris-node:aetheris\ 750
if sudo systemctl --failed --no-legend --plain | grep -q .; then fail post-start-failed-units; fi
sudo journalctl -u aetheris-node.service -n 1 --no-pager | grep -q . || fail journald
expect_g3_hash /etc/aetheris/node/identity.env 9cc789d4df7aaea3849628c19a7f58bce7622f4bb7e859327f859ae6cadd676e
expect_g3_hash /etc/aetheris/node/capabilities.json 3ede11bbbdd1075516ae93b6d700eca52c8d1591401b5753eea72b8e8e0c8acb
expect_g3_hash /usr/lib/tmpfiles.d/aetheris.conf d9375b8fd53be99eee8bc6bcde02663c540408983f88eedba4eb13c97bc0991d
printf 'RELEASE_INSTALLED=YES\nUNIT_INSTALLED=YES\nSERVICE_STARTED=YES\nPOST_START_VALIDATION=PASS\nREPORT=%s\n' "$REPORT" | tee -a "$REPORT"
