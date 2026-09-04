#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/G3.3-governed-node-agent-release-model.md"
SCHEMA="$ROOT_DIR/schemas/node-agent-release-manifest.schema.json"
TEMPLATE="$ROOT_DIR/templates/node-agent-release-manifest.json.template"
MANIFEST="${AETHERIS_RELEASE_MANIFEST:-}"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
pass(){ printf 'PASS %s\n' "$1"; }
[ -f "$DOC" ] || fail doc
[ -f "$SCHEMA" ] || fail schema
[ -f "$TEMPLATE" ] || fail template
python3 -m json.tool "$SCHEMA" >/dev/null || fail schema-json
grep -Fq 'CURRENT_V1=DIRECTORY' "$DOC" || fail current-directory
grep -Fq 'FUTURE_MODEL=SYMLINK' "$DOC" || fail future-symlink
grep -Fq 'MIGRATION_REQUIRED=YES' "$DOC" || fail migration-boundary
grep -Fq '4cbea2ff1018a604cfa6b063545efc155e70fc5b' "$DOC" || fail source-authority
if [ -z "$MANIFEST" ]; then
  pass 'release manifest not materialized'
  printf 'G3_3_RELEASE_CONTRACT_VERIFY=PASS\n'
  exit 0
fi
[ -f "$MANIFEST" ] || fail manifest-path
python3 - "$SCHEMA" "$MANIFEST" <<'PY'
import json
import re
import sys

schema = json.load(open(sys.argv[1], encoding="utf-8"))
data = json.load(open(sys.argv[2], encoding="utf-8"))

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
print("manifest semantic validation PASS")
PY
pass 'release manifest semantics'
printf 'G3_3_RELEASE_CONTRACT_VERIFY=PASS\n'
