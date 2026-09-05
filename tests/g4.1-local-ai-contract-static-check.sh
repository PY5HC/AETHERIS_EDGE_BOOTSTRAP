#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL $1" >&2; exit 1; }
VERIFY="$ROOT_DIR/scripts/verify-local-ai-contract.sh"
bash -n "$VERIFY" || fail syntax
"$VERIFY" || fail verifier
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
model=json.loads((root/"schemas/local-ai-model-record.schema.json").read_text())
bench=json.loads((root/"schemas/local-ai-benchmark-record.schema.json").read_text())
caps=json.loads((root/"schemas/local-ai-runtime-capabilities.schema.json").read_text())
assert model["additionalProperties"] is False and bench["additionalProperties"] is False and caps["additionalProperties"] is False
assert model["properties"]["model_role"]["items"]["enum"] == ["generation","embedding","reranking","classification","experimental"]
assert caps["properties"]["capabilities"]["properties"]["generation"]["type"] == "boolean"
assert caps["properties"]["capabilities"]["properties"]["embedding"]["type"] == "boolean"
template=(root/"templates/local-ai-model-record.json.template").read_text()
assert "sha256:@ARTIFACT_DIGEST@" in template and "sha256:@MODEL_DIGEST@" in template
PY
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
cp "$ROOT_DIR/schemas/local-ai-model-record.schema.json" "$fixture_dir/model.json"
python3 - "$fixture_dir/model.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["unknown"]=True
json.dump(d,open(p,"w"))
PY
! grep -Fq '"unknown"' "$ROOT_DIR/schemas/local-ai-model-record.schema.json" || fail schema-fixture-isolation
! grep -Eq 'useradd|groupadd|systemctl[[:space:]]+(start|stop|restart|enable|disable|daemon-reload)|docker\.sock|nvpmodel[[:space:]]+(-m|-f|--force)|chmod|chown|apt([[:space:]]|$)|/home/py5hc|machine-id' "$ROOT_DIR/templates/local-ai-model-record.json.template" "$ROOT_DIR/docs/G4.1-local-ai-contract.md" || fail mutation-security
while read -r expected_mode expected_path; do mode=$(git -C "$ROOT_DIR" ls-files --stage -- "$expected_path" | awk 'NR==1{print $1}'); [ "$mode" = "$expected_mode" ] || fail "mode:$expected_path"; done <<'EOF'
100644 docs/G4.1-local-ai-contract.md
100644 schemas/local-ai-model-record.schema.json
100644 schemas/local-ai-benchmark-record.schema.json
100644 schemas/local-ai-runtime-capabilities.schema.json
100644 templates/local-ai-model-record.json.template
100755 scripts/verify-local-ai-contract.sh
100755 tests/g4.1-local-ai-contract-static-check.sh
EOF
printf 'G4_1_LOCAL_AI_CONTRACT_STATIC_CHECK=PASS\n'
