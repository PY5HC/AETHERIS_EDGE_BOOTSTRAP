#!/usr/bin/env bash
set -euo pipefail

# Build only into an explicitly supplied disposable directory. Activation is
# a separate governed operation and this script cannot target live authorities.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${NODE_AGENT_SOURCE_DIR:-}"
RELEASE_OUTPUT="${AETHERIS_RELEASE_OUTPUT:-}"
EXPECTED_COMMIT="4bb897e6b18644199ac89ad33be9292e7487c37b"
EXPECTED_GOVERNANCE="ff1318cd8f0a9720f66029e3985d1e5854044128"
EXPECTED_LOCK_SHA="ce7d86147a73c9b701f57a0d7e11f968c9df9eae5c0430a3064171df64033b01"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "missing tool: $1"; }

[ -n "$SOURCE_DIR" ] || fail 'NODE_AGENT_SOURCE_DIR is required'
[ -n "$RELEASE_OUTPUT" ] || fail 'AETHERIS_RELEASE_OUTPUT is required'
[ -d "$SOURCE_DIR/.git" ] || fail 'source is not a Git checkout'
case "$RELEASE_OUTPUT" in
  /opt|/opt/*|/etc|/etc/*|/var|/var/*|/run|/run/*|/home|/home/*)
    fail 'release output is a live or user authority path' ;;
esac
case "$RELEASE_OUTPUT" in /*) ;; *) fail 'release output must be absolute';; esac
for tool in git python3 sha256sum install mktemp; do need "$tool"; done
SOURCE_REMOTE="$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
case "$SOURCE_REMOTE" in *PY5HC/AETHERIS_NODE_AGENT*) ;; *) fail 'source origin mismatch';; esac
SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null)" || fail source-commit
[ "$SOURCE_COMMIT" = "$EXPECTED_COMMIT" ] || fail source-commit-mismatch
[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] || fail source-dirty
[ "$(uname -m)" = aarch64 ] || fail architecture
PYTHON_VERSION="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
python3 - "$PYTHON_VERSION" <<'PY'
import sys
raise SystemExit(0 if tuple(map(int, sys.argv[1].split('.'))) >= (3, 11, 0) else 1)
PY
[ -f "$SOURCE_DIR/requirements.lock" ] || fail lock-missing
LOCK_SHA="$(sha256sum "$SOURCE_DIR/requirements.lock" | awk '{print $1}')"
[ "$LOCK_SHA" = "$EXPECTED_LOCK_SHA" ] || fail lock-mismatch
RELEASE_ID="${AETHERIS_RELEASE_ID:-}"
[ -n "$RELEASE_ID" ] || fail release-id-missing
case "$RELEASE_ID" in *[!A-Za-z0-9._-]*) fail release-id-unsafe;; esac
BUILD_DIR="$(mktemp -d)"
cleanup(){ rm -rf "$BUILD_DIR"; }
trap cleanup EXIT
python3 -m pip wheel --no-deps --wheel-dir "$BUILD_DIR/wheels" "$SOURCE_DIR"
WHEEL_PATH="$(find "$BUILD_DIR/wheels" -maxdepth 1 -type f -name 'aetheris_node_agent-*.whl' -print -quit)"
[ -n "$WHEEL_PATH" ] || fail wheel-missing
python3 -m venv "$BUILD_DIR/venv"
"$BUILD_DIR/venv/bin/python" -m pip install --require-hashes -r "$SOURCE_DIR/requirements.lock"
"$BUILD_DIR/venv/bin/python" -m pip install --no-deps "$WHEEL_PATH"
PACKAGE_VERSION="$(python3 - "$SOURCE_DIR/pyproject.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as fh:
    print(tomllib.load(fh)['project']['version'])
PY
)"
EXECUTABLE="$BUILD_DIR/venv/bin/aetheris-node-agent"
[ -x "$EXECUTABLE" ] || fail console-script-missing
mkdir -p "$RELEASE_OUTPUT/$RELEASE_ID"/{bin,metadata,source}
RELEASE_ROOT="$RELEASE_OUTPUT/$RELEASE_ID"
install -m 0755 "$EXECUTABLE" "$RELEASE_ROOT/bin/aetheris-node-agent"
install -m 0644 "$SOURCE_DIR/requirements.lock" "$RELEASE_ROOT/metadata/requirements.lock"
install -m 0644 "$WHEEL_PATH" "$RELEASE_ROOT/metadata/"
cp -a "$SOURCE_DIR"/. "$RELEASE_ROOT/source/"
rm -rf "$RELEASE_ROOT/source/.git"
ARTIFACT_SHA="$(sha256sum "$RELEASE_ROOT/metadata/$(basename "$WHEEL_PATH")" | awk '{print $1}')"
BUILD_TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$RELEASE_ROOT/manifest.json" <<PY
import json, sys
data = {
  "schema_version": "1.0", "release_id": "$RELEASE_ID",
  "repository": "PY5HC/AETHERIS_NODE_AGENT", "source_commit": "$SOURCE_COMMIT",
  "build_timestamp_utc": "$BUILD_TIMESTAMP_UTC", "architecture": "aarch64",
  "python_version": "$PYTHON_VERSION",
  "package": {"name": "aetheris-node-agent", "version": "$PACKAGE_VERSION"},
  "artifact": {"kind": "wheel", "sha256": "$ARTIFACT_SHA", "release_root": "/opt/aetheris/releases"},
  "dependencies": {"provenance": "requirements.lock:$LOCK_SHA", "lock_reference": "metadata/requirements.lock"},
  "entrypoint": {"relative_path": "bin/aetheris-node-agent", "runner_kind": "console-script"},
  "health": {"liveness_path": "/api/v1/health", "readiness_path": "/api/v1/health"},
  "activation": {"requires_hash_verification": True, "requires_readiness_probe": True, "rollback_release_required": True},
  "governance": {"repository": "PY5HC/AETHERIS_GOVERNANCE", "revision": "$EXPECTED_GOVERNANCE", "governance_version": "1.3.0", "profile": "NOT_YET_ESTABLISHED", "contract_version": "1.0.0"}
}
with open(sys.argv[1], 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, sort_keys=True); fh.write('\\n')
PY
python3 -m json.tool "$RELEASE_ROOT/manifest.json" >/dev/null
printf 'RELEASE_BUILD=PASS\nRELEASE_ID=%s\nRELEASE_ROOT=%s\nSOURCE_COMMIT=%s\nLOCK_SHA256=%s\nARTIFACT_SHA256=%s\n' "$RELEASE_ID" "$RELEASE_ROOT" "$SOURCE_COMMIT" "$LOCK_SHA" "$ARTIFACT_SHA"
