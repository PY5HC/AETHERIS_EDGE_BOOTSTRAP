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
for needle in 'PY5HC/AETHERIS_NODE_AGENT' 'CURRENT_V1=DIRECTORY' 'FUTURE_MODEL=SYMLINK' 'MIGRATION_REQUIRED=YES' '/opt/aetheris/releases/<release-id>' 'artifact hash' 'readiness' 'rollback'; do grep -Fqi "$needle" "$DOC" || fail "doc $needle"; done
grep -Fq '"additionalProperties": false' "$SCHEMA" || fail strict-schema
grep -Fq '"requires_hash_verification": true' "$TEMPLATE" || fail activation
! grep -Eq '/home/py5hc|aetheris-edge-02|machine-id|docker\.sock|DeviceAllow|nvpmodel[[:space:]]+(-m|-f|--force)' "$DOC" "$SCHEMA" "$TEMPLATE" "$VERIFY" || fail machine-specific-or-privileged
fixture_dir=$(mktemp -d); trap 'rm -rf "$fixture_dir"' EXIT
rendered="$fixture_dir/manifest.json"
sed -e 's/@RELEASE_ID@/20260904-node-agent-r1/' -e 's/@SOURCE_COMMIT@/4cbea2ff1018a604cfa6b063545efc155e70fc5b/' -e 's/@BUILD_TIMESTAMP_UTC@/2026-09-04T20:30:00Z/' -e 's/@PYTHON_VERSION@/3.11.9/' -e 's/@PACKAGE_VERSION@/0.1.0/' -e 's/@ARTIFACT_KIND@/wheel/' -e 's/@ARTIFACT_SHA256@/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' -e 's/@DEPENDENCY_PROVENANCE@/locked-hashes/' -e 's/@LOCK_REFERENCE@/requirements.lock/' -e 's#@ENTRYPOINT_RELATIVE_PATH@#bin/aetheris-node#' -e 's/@RUNNER_KIND@/project-runner/' -e 's#@LIVENESS_PATH@#/api/v1/health#' -e 's#@READINESS_PATH@#/api/v1/health#' "$TEMPLATE" > "$rendered"
AETHERIS_RELEASE_MANIFEST="$rendered" "$VERIFY" >/dev/null || fail rendered-valid
cp "$rendered" "$fixture_dir/bad.json"; sed -i 's/"repository": "PY5HC\/AETHERIS_NODE_AGENT"/"repository": "other"/' "$fixture_dir/bad.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/bad.json" "$VERIFY" >/dev/null 2>&1; then fail wrong-repository-accepted; fi
cp "$rendered" "$fixture_dir/unknown.json"; sed -i 's/"schema_version": "1.0"/"unknown": true, "schema_version": "1.0"/' "$fixture_dir/unknown.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/unknown.json" "$VERIFY" >/dev/null 2>&1; then fail unknown-key-accepted; fi
cp "$rendered" "$fixture_dir/hash.json"; sed -i 's/"sha256": "[a-f0-9]*"/"sha256": "bad"/' "$fixture_dir/hash.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/hash.json" "$VERIFY" >/dev/null 2>&1; then fail bad-hash-accepted; fi
cp "$rendered" "$fixture_dir/path.json"; sed -i 's#"relative_path": "bin/aetheris-node"#"relative_path": "/usr/local/bin/node"#' "$fixture_dir/path.json"
if AETHERIS_RELEASE_MANIFEST="$fixture_dir/path.json" "$VERIFY" >/dev/null 2>&1; then fail unsafe-path-accepted; fi
pass 'manifest positive and negative fixtures'
for pair in '100644 docs/G3.3-governed-node-agent-release-model.md' '100644 schemas/node-agent-release-manifest.schema.json' '100644 templates/node-agent-release-manifest.json.template' '100755 scripts/verify-node-agent-release-contract.sh' '100755 tests/g3.3-node-agent-release-contract-static-check.sh'; do set -- $pair; actual=$(git -C "$ROOT_DIR" ls-files --stage -- "$2" | awk 'NR==1{print $1}'); [ "$actual" = "$1" ] || fail "mode $2"; done
pass 'canonical Git modes'
echo G3_3_NODE_AGENT_RELEASE_CONTRACT_STATIC_CHECK=PASS
