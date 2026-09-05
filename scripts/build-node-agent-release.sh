#!/usr/bin/env bash
set -euo pipefail

# Clean-room, repository-only release builder. The output is never live
# authority; activation under /opt is a separate governed operation.
SOURCE_DIR="${NODE_AGENT_SOURCE_DIR:-}"
RELEASE_OUTPUT="${AETHERIS_RELEASE_OUTPUT:-}"
RELEASE_ID="${AETHERIS_RELEASE_ID:-}"
EXPECTED_COMMIT="4bb897e6b18644199ac89ad33be9292e7487c37b"
EXPECTED_GOVERNANCE="ff1318cd8f0a9720f66029e3985d1e5854044128"
EXPECTED_LOCK_SHA="ce7d86147a73c9b701f57a0d7e11f968c9df9eae5c0430a3064171df64033b01"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
[ -d "$SOURCE_DIR/.git" ] || fail source-checkout
if [ -z "$RELEASE_OUTPUT" ] || [ -z "$RELEASE_ID" ]; then fail required-input; fi
case "$RELEASE_ID" in *[!A-Za-z0-9._-]*|'') fail release-id;; esac
for tool in git python3 sha256sum install mktemp realpath find tar; do need "$tool"; done
RELEASE_OUTPUT="$(realpath -m "$RELEASE_OUTPUT")"
case "$RELEASE_OUTPUT" in /opt|/opt/*|/etc|/etc/*|/var|/var/*|/run|/run/*|/home|/home/*) fail live-output;; esac
SOURCE_REMOTE="$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
case "$SOURCE_REMOTE" in *PY5HC/AETHERIS_NODE_AGENT*) ;; *) fail source-origin;; esac
SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD)"; [ "$SOURCE_COMMIT" = "$EXPECTED_COMMIT" ] || fail source-commit
[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] || fail source-dirty
[ "$(uname -m)" = aarch64 ] || fail architecture
PYTHON_VERSION="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
python3 - "$PYTHON_VERSION" <<'PY'
import sys
raise SystemExit(0 if tuple(map(int, sys.argv[1].split('.'))) >= (3,11,0) else 1)
PY
[ -f "$SOURCE_DIR/requirements.lock" ] || fail lock-missing
LOCK_SHA="$(sha256sum "$SOURCE_DIR/requirements.lock"|awk '{print $1}')"; [ "$LOCK_SHA" = "$EXPECTED_LOCK_SHA" ] || fail lock-sha
BUILD_DIR="$(mktemp -d)"; trap 'rm -rf "$BUILD_DIR"' EXIT
python3 -m pip wheel --no-deps --wheel-dir "$BUILD_DIR/wheels" "$SOURCE_DIR"
WHEEL="$(find "$BUILD_DIR/wheels" -maxdepth 1 -type f -name 'aetheris_node_agent-*.whl' -print -quit)"; [ -n "$WHEEL" ] || fail wheel
BUILD_RELEASE="$BUILD_DIR/release/$RELEASE_ID"; mkdir -p "$BUILD_RELEASE/metadata" "$BUILD_RELEASE/source"
python3 -m venv --copies "$BUILD_RELEASE/venv"
"$BUILD_RELEASE/venv/bin/python" -m pip install --require-hashes -r "$SOURCE_DIR/requirements.lock"
"$BUILD_RELEASE/venv/bin/python" -m pip install --no-deps "$WHEEL"
git -C "$SOURCE_DIR" archive "$EXPECTED_COMMIT" | tar -x -C "$BUILD_RELEASE/source"
EXEC_REL=venv/bin/aetheris-node-agent; EXEC="$BUILD_RELEASE/$EXEC_REL"; PYTHON_EXEC="$BUILD_RELEASE/venv/bin/python"
[ -x "$EXEC" ] || fail entrypoint
[ -x "$PYTHON_EXEC" ] || fail interpreter
"$PYTHON_EXEC" -c 'import aetheris_node_agent, aetheris_node_agent.runner' || fail runtime-import
cat > "$EXEC" <<'SH'
#!/bin/sh
set -eu
VENV_BIN="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$VENV_BIN/python" -m aetheris_node_agent.runner "$@"
SH
chmod 0755 "$EXEC"
grep -Fqx '#!/bin/sh' "$EXEC" || fail relocatable-shebang
ARTIFACT_NAME="$(basename "$WHEEL")"; install -m 0644 "$SOURCE_DIR/requirements.lock" "$BUILD_RELEASE/metadata/requirements.lock"; install -m 0644 "$WHEEL" "$BUILD_RELEASE/metadata/$ARTIFACT_NAME"
ARTIFACT_SHA="$(sha256sum "$BUILD_RELEASE/metadata/$ARTIFACT_NAME"|awk '{print $1}')"; BUILD_TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; PACKAGE_VERSION="$(python3 - "$SOURCE_DIR/pyproject.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as fh: print(tomllib.load(fh)['project']['version'])
PY
)"
python3 - "$BUILD_RELEASE/manifest.json" <<PY
import json, sys
d={"schema_version":"1.0","release_id":"$RELEASE_ID","repository":"PY5HC/AETHERIS_NODE_AGENT","source_commit":"$SOURCE_COMMIT","build_timestamp_utc":"$BUILD_TIMESTAMP_UTC","architecture":"aarch64","python_version":"$PYTHON_VERSION","package":{"name":"aetheris-node-agent","version":"$PACKAGE_VERSION"},"artifact":{"kind":"wheel","sha256":"$ARTIFACT_SHA","release_root":"/opt/aetheris/releases"},"dependencies":{"provenance":"requirements.lock:$LOCK_SHA","lock_reference":"metadata/requirements.lock"},"entrypoint":{"relative_path":"venv/bin/aetheris-node-agent","runner_kind":"project-runner"},"runtime":{"model":"release-venv","python_executable":"venv/bin/python"},"health":{"liveness_path":"/api/v1/health","readiness_path":"/api/v1/health"},"activation":{"requires_hash_verification":True,"requires_readiness_probe":True,"rollback_release_required":True},"governance":{"repository":"PY5HC/AETHERIS_GOVERNANCE","revision":"$EXPECTED_GOVERNANCE","governance_version":"1.3.0","profile":"NOT_YET_ESTABLISHED","contract_version":"1.0.0"}}
with open(sys.argv[1],'w',encoding='utf-8') as f: json.dump(d,f,indent=2,sort_keys=True); f.write('\\n')
PY
python3 -m json.tool "$BUILD_RELEASE/manifest.json" >/dev/null
mkdir -p "$RELEASE_OUTPUT"; [ ! -e "$RELEASE_OUTPUT/$RELEASE_ID" ] || fail output-exists
cp -a "$BUILD_RELEASE" "$RELEASE_OUTPUT/"
MANIFEST_SHA="$(sha256sum "$RELEASE_OUTPUT/$RELEASE_ID/manifest.json"|awk '{print $1}')"
printf 'RELEASE_BUILD=PASS\nRELEASE_ID=%s\nRELEASE_ROOT=%s\nSOURCE_COMMIT=%s\nPYTHON_VERSION=%s\nLOCK_SHA256=%s\nWHEEL_SHA256=%s\nMANIFEST_SHA256=%s\nENTRYPOINT=%s\nENTRYPOINT_SHEBANG=%s\nRUNTIME_MODEL=release-venv\n' "$RELEASE_ID" "$RELEASE_OUTPUT/$RELEASE_ID" "$SOURCE_COMMIT" "$PYTHON_VERSION" "$LOCK_SHA" "$ARTIFACT_SHA" "$MANIFEST_SHA" "$EXEC_REL" '#!/bin/sh'
