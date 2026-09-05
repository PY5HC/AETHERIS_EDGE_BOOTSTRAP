#!/usr/bin/env bash
set -euo pipefail

# First-release materializer. It is validation-only unless the caller sets
# AETHERIS_LIVE_APPLY=YES and supplies an authenticated sudo timestamp.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_RELEASE="${AETHERIS_STAGED_RELEASE:-}"
LIVE_APPLY="${AETHERIS_LIVE_APPLY:-NO}"
EXPECTED_SOURCE_COMMIT="4bb897e6b18644199ac89ad33be9292e7487c37b"
EXPECTED_GOVERNANCE_REVISION="ff1318cd8f0a9720f66029e3985d1e5854044128"
EXPECTED_LOCK_SHA="ce7d86147a73c9b701f57a0d7e11f968c9df9eae5c0430a3064171df64033b01"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

[ -n "$STAGED_RELEASE" ] && [ -d "$STAGED_RELEASE" ] || fail staged-release
for tool in git python3 sha256sum awk sudo; do need "$tool"; done
[ "$(git -C "$ROOT_DIR" branch --show-current)" = main ] || fail repository-branch
[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ] || fail repository-dirty
MANIFEST="$STAGED_RELEASE/manifest.json"
[ -f "$MANIFEST" ] || fail staged-manifest
readarray -t FACTS < <(python3 - "$MANIFEST" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
if d.get('schema_version') != '1.0': raise SystemExit('schema')
if d.get('repository') != 'PY5HC/AETHERIS_NODE_AGENT': raise SystemExit('repository')
if d.get('source_commit') != '4bb897e6b18644199ac89ad33be9292e7487c37b': raise SystemExit('source')
if d.get('architecture') != 'aarch64': raise SystemExit('architecture')
if d.get('governance', {}).get('revision') != 'ff1318cd8f0a9720f66029e3985d1e5854044128': raise SystemExit('governance')
if d.get('governance', {}).get('profile') != 'NOT_YET_ESTABLISHED': raise SystemExit('profile')
rid = d.get('release_id', '')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', rid): raise SystemExit('release-id')
rel = d.get('entrypoint', {}).get('relative_path', '')
if not re.fullmatch(r'bin/[A-Za-z0-9._/-]+', rel) or '..' in rel: raise SystemExit('entrypoint')
if d.get('artifact', {}).get('release_root') != '/opt/aetheris/releases': raise SystemExit('release-root')
print(rid); print(rel); print(d['artifact']['sha256']); print(d['dependencies']['provenance'])
PY
) || fail manifest-semantics
RELEASE_ID="${FACTS[0]}"; EXEC_REL="${FACTS[1]}"; EXPECTED_ARTIFACT_SHA="${FACTS[2]}"; LOCK_PROVENANCE="${FACTS[3]}"
WHEEL="$(find "$STAGED_RELEASE/metadata" -maxdepth 1 -type f -name '*.whl' -print -quit)"; [ -n "$WHEEL" ] || fail wheel
[ "$(sha256sum "$WHEEL" | awk '{print $1}')" = "$EXPECTED_ARTIFACT_SHA" ] || fail artifact-sha
LOCK="$STAGED_RELEASE/metadata/requirements.lock"; [ -f "$LOCK" ] || fail lock
case "$LOCK_PROVENANCE" in requirements.lock:$EXPECTED_LOCK_SHA) ;; *) fail lock-provenance;; esac
[ "$(sha256sum "$LOCK" | awk '{print $1}')" = "$EXPECTED_LOCK_SHA" ] || fail lock-sha
EXEC="$STAGED_RELEASE/$EXEC_REL"; [ -x "$EXEC" ] || fail staged-entrypoint
RELEASE_ROOT="/opt/aetheris/releases/$RELEASE_ID"
UNIT_TMP="$(mktemp)"; REPORT="/home/py5hc/aetheris-g3.6-live-apply-$(date -u +%Y%m%dT%H%M%SZ).report"
cleanup(){ rm -f "$UNIT_TMP"; }; trap cleanup EXIT
sed "s#@RELEASE_ROOT@#$RELEASE_ROOT#g; s#@RELEASE_EXECUTABLE@#$RELEASE_ROOT/$EXEC_REL#g" "$ROOT_DIR/templates/aetheris-node.service.g3.6.template" > "$UNIT_TMP"
! grep -Fq '@' "$UNIT_TMP" || fail unresolved-unit
grep -Fqx "ExecStart=$RELEASE_ROOT/$EXEC_REL" "$UNIT_TMP" || fail unit-exec
sudo -n true || fail authenticated-sudo-required
expect_meta(){ [ "$(sudo stat -c '%U:%G %a' "$1")" = "$2" ] || fail "metadata:$1"; }
expect_meta /etc/aetheris root:aetheris\ 750
expect_meta /etc/aetheris/node root:aetheris\ 750
expect_meta /opt/aetheris root:aetheris\ 755
expect_meta /opt/aetheris/releases root:aetheris\ 755
expect_meta /opt/aetheris/current root:aetheris\ 755
expect_meta /var/lib/aetheris root:aetheris\ 750
expect_meta /var/lib/aetheris/node root:aetheris\ 750
expect_meta /var/log/aetheris root:aetheris\ 750
expect_meta /run/aetheris root:aetheris\ 755
getent group aetheris >/dev/null || fail aetheris-group
ACCOUNT_RECORD="$(getent passwd aetheris-node || true)"
[ -n "$ACCOUNT_RECORD" ] || fail runtime-identity-absent
[ "$(id -gn aetheris-node)" = aetheris ] || fail runtime-primary-group
[ "$(getent passwd aetheris-node | cut -d: -f7)" = /usr/sbin/nologin ] || fail runtime-shell
[ "$(getent passwd aetheris-node | cut -d: -f6)" = /nonexistent ] || fail runtime-home
[ "$(id -nG aetheris-node)" = aetheris ] || fail runtime-supplementary-groups
if getent group docker | grep -Eq '(^|,)aetheris-node(,|$)'; then fail docker-membership; fi
if sudo systemctl --failed --no-legend --plain | grep -q .; then fail failed-units; fi
POWER_QUERY="$(sudo /usr/sbin/nvpmodel -q 2>/dev/null)" || fail nvpmodel-query
grep -Fq 'NV Power Mode: MAXN_SUPER' <<<"$POWER_QUERY" || fail power-profile
grep -Eq '^2$' <<<"$POWER_QUERY" || fail power-mode
sudo nvidia-ctk cdi list 2>/dev/null | grep -q NVIDIA || fail cdi
sudo systemctl get-default | grep -Fxq multi-user.target || fail default-target
sudo test -d /etc/aetheris/node || fail config-authority
sudo test -d /opt/aetheris/releases || fail release-authority
sudo test -d /opt/aetheris/current || fail current-directory
[ ! -e /run/aetheris/aetheris-node ] || fail runtime-leaf-present
[ ! -e /var/lib/aetheris/node/aetheris-node ] || fail state-leaf-present
if sudo test -e "$RELEASE_ROOT"; then fail release-already-present; fi
if sudo test -e /etc/systemd/system/aetheris-node.service; then fail conflicting-unit; fi
printf 'UTC=%s\nRELEASE_ID=%s\nSTAGED_RELEASE=%s\nMANIFEST_SHA256=%s\nWHEEL_SHA256=%s\nLOCK_SHA256=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RELEASE_ID" "$STAGED_RELEASE" "$(sha256sum "$MANIFEST" | awk '{print $1}')" "$EXPECTED_ARTIFACT_SHA" "$EXPECTED_LOCK_SHA" | tee "$REPORT"
if [ "$LIVE_APPLY" != YES ]; then printf 'VALIDATION_ONLY=PASS\nLIVE_MUTATION=NOT_PERFORMED\nREPORT=%s\n' "$REPORT"; exit 0; fi
sudo install -d -o root -g aetheris -m 0755 "$RELEASE_ROOT"
sudo cp -a "$STAGED_RELEASE"/. "$RELEASE_ROOT"/
sudo chown -R root:aetheris "$RELEASE_ROOT"
sudo find "$RELEASE_ROOT" -type d -exec chmod 0755 {} +
sudo find "$RELEASE_ROOT" -type f -exec chmod 0640 {} +
sudo chmod 0755 "$RELEASE_ROOT/$EXEC_REL"
sudo install -o root -g root -m 0644 "$UNIT_TMP" /etc/systemd/system/aetheris-node.service
sudo systemctl daemon-reload
sudo systemctl enable --now aetheris-node.service
printf 'RELEASE_INSTALLED=YES\nUNIT_INSTALLED=YES\nSERVICE_STARTED=YES\nREPORT=%s\n' "$REPORT" | tee -a "$REPORT"
