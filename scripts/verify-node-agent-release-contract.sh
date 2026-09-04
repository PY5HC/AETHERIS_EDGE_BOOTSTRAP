#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.3-governed-node-agent-release-model.md"
SCHEMA="$ROOT_DIR/schemas/node-agent-release-manifest.schema.json"
TEMPLATE="$ROOT_DIR/templates/node-agent-release-manifest.json.template"
MANIFEST="${AETHERIS_RELEASE_MANIFEST:-}"
EXPECTED_SOURCE_COMMIT="${AETHERIS_EXPECTED_SOURCE_COMMIT:-4bb897e6b18644199ac89ad33be9292e7487c37b}"
EXPECTED_GOVERNANCE_REVISION="${AETHERIS_EXPECTED_GOVERNANCE_REVISION:-ff1318cd8f0a9720f66029e3985d1e5854044128}"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
pass(){ printf 'PASS %s\n' "$1"; }
[ -f "$DOC" ] || fail doc
[ -f "$SCHEMA" ] || fail schema
[ -f "$TEMPLATE" ] || fail template
python3 -m json.tool "$SCHEMA" >/dev/null || fail schema-json
grep -Fq 'CURRENT_V1=DIRECTORY' "$DOC" || fail current-directory
grep -Fq 'FUTURE_MODEL=SYMLINK' "$DOC" || fail future-symlink
grep -Fq 'MIGRATION_REQUIRED=YES' "$DOC" || fail migration-boundary
grep -Fq '4bb897e6b18644199ac89ad33be9292e7487c37b' "$DOC" || fail source-authority
grep -Fq 'ff1318cd8f0a9720f66029e3985d1e5854044128' "$DOC" || fail governance-authority
if [ -z "$MANIFEST" ]; then
  pass 'release manifest not materialized'
  printf 'G3_3_RELEASE_CONTRACT_VERIFY=PASS\n'
  exit 0
fi
[ -f "$MANIFEST" ] || fail manifest-path
python3 - "$SCHEMA" "$MANIFEST" "$EXPECTED_SOURCE_COMMIT" "$EXPECTED_GOVERNANCE_REVISION" <<'PY'
import json
import re
import sys

schema = json.load(open(sys.argv[1], encoding="utf-8"))
data = json.load(open(sys.argv[2], encoding="utf-8"))
expected_source = sys.argv[3]
expected_governance = sys.argv[4]

def reject(message):
    raise SystemExit(message)

def check(node, spec, path="$"):
    kind = spec.get("type")
    if kind == "object":
        if not isinstance(node, dict):
            reject(f"{path}: object required")
        if any(key not in node for key in spec.get("required", [])):
            reject(f"{path}: missing required")
        allowed = set(spec.get("properties", {}))
        if spec.get("additionalProperties") is False and set(node) - allowed:
            reject(f"{path}: unknown key")
        for key, child in spec.get("properties", {}).items():
            if key in node:
                check(node[key], child, f"{path}.{key}")
    elif kind == "string":
        if not isinstance(node, str) or len(node) < spec.get("minLength", 0):
            reject(f"{path}: string required")
        if "pattern" in spec and not re.fullmatch(spec["pattern"], node):
            reject(f"{path}: pattern")
    elif kind == "boolean" and not isinstance(node, bool):
        reject(f"{path}: boolean required")
    if "const" in spec and node != spec["const"]:
        reject(f"{path}: constant")
    if "enum" in spec and node not in spec["enum"]:
        reject(f"{path}: enum")

check(data, schema)
if "@" in json.dumps(data):
    reject("unresolved placeholder")
if data["source_commit"] != expected_source:
    reject("source commit is not the validated authority")
governance = data["governance"]
if governance["revision"] != expected_governance:
    reject("governance revision is not the validated authority")
if ".." in data["entrypoint"]["relative_path"]:
    reject("entrypoint traversal")
print("manifest semantic validation PASS")
PY
pass 'release manifest semantics'
printf 'G3_3_RELEASE_CONTRACT_VERIFY=PASS\n'
