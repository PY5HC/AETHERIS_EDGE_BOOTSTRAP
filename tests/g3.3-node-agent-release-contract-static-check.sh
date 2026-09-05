#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.3-governed-node-agent-release-model.md"
SCHEMA="$ROOT_DIR/schemas/node-agent-release-manifest.schema.json"
TEMPLATE="$ROOT_DIR/templates/node-agent-release-manifest.json.template"
VERIFY="$ROOT_DIR/scripts/verify-node-agent-release-contract.sh"
fail(){ echo "FAIL $1" >&2; exit 1; }
pass(){ echo "PASS $1"; }
python3 -m json.tool "$SCHEMA" >/dev/null || fail schema
bash -n "$VERIFY" || fail syntax
"$VERIFY" >/dev/null || fail verifier
for needle in 'PY5HC/AETHERIS_NODE_AGENT' '4bb897e6b18644199ac89ad33be9292e7487c37b' 'PY5HC/AETHERIS_GOVERNANCE' 'ff1318cd8f0a9720f66029e3985d1e5854044128' 'NOT_YET_ESTABLISHED' 'CURRENT_V1=DIRECTORY' 'FUTURE_MODEL=SYMLINK' 'MIGRATION_REQUIRED=YES' '/opt/aetheris/releases/<release-id>' 'artifact hash' 'readiness' 'rollback' 'requirements.lock'; do grep -Fqi "$needle" "$DOC" || fail "doc $needle"; done
grep -Fq '"additionalProperties": false' "$SCHEMA" || fail strict-schema
grep -Fq '"requires_hash_verification": true' "$TEMPLATE" || fail activation
! grep -Eq '/home/py5hc|aetheris-edge-02|machine-id|docker\.sock|DeviceAllow|nvpmodel[[:space:]]+(-m|-f|--force)' "$DOC" "$SCHEMA" "$TEMPLATE" "$VERIFY" || fail machine-specific-or-privileged
fixture_dir=$(mktemp -d); trap 'rm -rf "$fixture_dir"' EXIT
rendered="$fixture_dir/manifest.json"
sed -e 's/@RELEASE_ID@/20260904-node-agent-r1/' -e 's/@SOURCE_COMMIT@/4bb897e6b18644199ac89ad33be9292e7487c37b/' -e 's/@BUILD_TIMESTAMP_UTC@/2026-09-04T20:30:00Z/' -e 's/@PYTHON_VERSION@/3.11.9/' -e 's/@PACKAGE_VERSION@/0.1.0/' -e 's/@ARTIFACT_KIND@/wheel/' -e 's/@ARTIFACT_SHA256@/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' -e 's/@DEPENDENCY_PROVENANCE@/locked-hashes/' -e 's/@LOCK_REFERENCE@/requirements.lock/' -e 's#@ENTRYPOINT_RELATIVE_PATH@#bin/aetheris-node#' -e 's/@RUNNER_KIND@/project-runner/' -e 's/@RUNTIME_MODEL@/release-venv/' -e 's#@PYTHON_EXECUTABLE@#venv/bin/python#' -e 's#@LIVENESS_PATH@#/api/v1/health#' -e 's#@READINESS_PATH@#/api/v1/health#' -e 's/@GOVERNANCE_REVISION@/ff1318cd8f0a9720f66029e3985d1e5854044128/' -e 's/@GOVERNANCE_VERSION@/1.3.0/' -e 's/@GOVERNANCE_CONTRACT_VERSION@/1.0.0/' "$TEMPLATE" > "$rendered"
AETHERIS_RELEASE_MANIFEST="$rendered" "$VERIFY" >/dev/null || fail rendered-valid
cp "$rendered" "$fixture_dir/bad.json"; sed -i 's/"repository": "PY5HC\/AETHERIS_NODE_AGENT"/"repository": "other"/' "$fixture_dir/bad.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/bad.json" "$VERIFY" >/dev/null 2>&1; then fail wrong-repository-accepted; fi
cp "$rendered" "$fixture_dir/source.json"; sed -i 's/"source_commit": "[a-f0-9]*"/"source_commit": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"/' "$fixture_dir/source.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/source.json" "$VERIFY" >/dev/null 2>&1; then fail wrong-source-accepted; fi
cp "$rendered" "$fixture_dir/unknown.json"; sed -i 's/"schema_version": "1.0"/"unknown": true, "schema_version": "1.0"/' "$fixture_dir/unknown.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/unknown.json" "$VERIFY" >/dev/null 2>&1; then fail unknown-key-accepted; fi
cp "$rendered" "$fixture_dir/hash.json"; sed -i 's/"sha256": "[a-f0-9]*"/"sha256": "bad"/' "$fixture_dir/hash.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/hash.json" "$VERIFY" >/dev/null 2>&1; then fail bad-hash-accepted; fi
cp "$rendered" "$fixture_dir/path.json"; sed -i 's#"relative_path": "bin/aetheris-node"#"relative_path": "/usr/local/bin/node"#' "$fixture_dir/path.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/path.json" "$VERIFY" >/dev/null 2>&1; then fail unsafe-path-accepted; fi
cp "$rendered" "$fixture_dir/governance.json"; sed -i 's/"revision": "[a-f0-9]*"/"revision": "cccccccccccccccccccccccccccccccccccccccc"/' "$fixture_dir/governance.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/governance.json" "$VERIFY" >/dev/null 2>&1; then fail missing-governance-accepted; fi
pass 'manifest positive and negative fixtures'
for pair in '100644 docs/G3.3-governed-node-agent-release-model.md' '100644 schemas/node-agent-release-manifest.schema.json' '100644 templates/node-agent-release-manifest.json.template' '100755 scripts/verify-node-agent-release-contract.sh' '100755 tests/g3.3-node-agent-release-contract-static-check.sh'; do set -- $pair; actual=$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR==1{print $1}'); [ "$actual" = "$1" ] || fail "mode $2"; done
pass 'canonical Git modes'
BUILDER="$ROOT_DIR/scripts/build-node-agent-release.sh"
[ -x "$BUILDER" ] || fail builder-missing
grep -Fq 'NODE_AGENT_SOURCE_DIR' "$BUILDER" || fail builder-source-input
grep -Fq 'AETHERIS_RELEASE_OUTPUT' "$BUILDER" || fail builder-output-input
grep -Fq 'requirements.lock' "$BUILDER" || fail builder-lock
grep -Fq 'PY5HC/AETHERIS_NODE_AGENT' "$BUILDER" || fail builder-repository
grep -Fq 'EXPECTED_GOVERNANCE' "$BUILDER" || fail builder-governance
grep -Fq '"kind":"wheel"' "$BUILDER" || fail builder-artifact
grep -Fq 'python3 -m pip wheel --no-deps' "$BUILDER" || fail builder-wheel
grep -Fq 'realpath -m' "$BUILDER" || fail builder-path-resolution
grep -Fq 'output-exists' "$BUILDER" || fail builder-immutable-output
grep -Fq 'release-venv' "$BUILDER" || fail builder-runtime-model
grep -Fq 'git -C "$SOURCE_DIR" archive' "$BUILDER" || fail builder-clean-source
grep -Fq 'SOURCE_SNAPSHOT=' "$BUILDER" || fail builder-ephemeral-source
grep -Fq 'executables' "$BUILDER" || fail builder-executable-contract
! grep -Fq 'BUILD_RELEASE/source' "$BUILDER" || fail builder-source-residue
grep -Fq "#!/bin/sh" "$BUILDER" || fail builder-relocatable-launcher
grep -Fq 'python3 -m venv --copies' "$BUILDER" || fail builder-relocatable-venv
grep -Fq 'VENV_BIN=' "$BUILDER" || fail builder-sibling-interpreter-launcher
grep -Fq 'RUNTIME_MODEL=release-venv' "$BUILDER" || fail builder-runtime-output
grep -Fq 'build-path-in-launcher' "$BUILDER" || fail builder-launcher-scan
grep -Fq "! -name 'python[0-9]*'" "$BUILDER" || fail builder-runtime-only-venv
! grep -Eq 'pip install.*--target' "$BUILDER" || fail builder-nonrelocatable-path
grep -Fq 'live-output' "$BUILDER" || fail builder-live-output-guard
if grep -Eq 'systemctl (enable|start|restart|daemon-reload)|useradd|groupadd|docker\.sock|nvpmodel[[:space:]]+(-m|-f|--force)' "$BUILDER"; then fail builder-live-mutation; fi
pass 'repository-only release builder boundary'
actual=$(git -C "$ROOT_DIR" ls-files --stage -- scripts/build-node-agent-release.sh | awk 'NR==1{print $1}')
[ "$actual" = 100755 ] || fail builder-mode
echo G3_3_NODE_AGENT_RELEASE_CONTRACT_STATIC_CHECK=PASS
