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
assert "sha256:@ARTIFACT_DIGEST@" in template and "sha256:@MODEL_DIGEST@" in template and "@PARAMETER_COUNT@" in template
PY
python3 - "$ROOT_DIR" <<'PY'
import copy, json, sys
from jsonschema import Draft202012Validator
root=sys.argv[1]
schema=json.load(open(root+"/schemas/local-ai-model-record.schema.json"))
record={"schema_version":"1.0","model_id":"fixture-model","model_role":["generation"],"upstream_model":"fixture/upstream","upstream_revision":"rev-1","source_uri":"https://example.invalid/model","license":"fixture-license","artifact_format":"gguf","artifact_digest":"sha256:"+"a"*64,"model_digest":"sha256:"+"b"*64,"parameter_count":1000000,"quantization":"Q4_K_M","runtime_backend":"llama.cpp","runtime_version":"fixture","acquired_at":"2026-09-05T00:00:00Z","validated_at":"2026-09-05T00:00:00Z","hardware_class":"LOCAL_AI_SMALL","validation_status":"VALIDATED"}
validator=Draft202012Validator(schema)
assert not list(validator.iter_errors(record))
unknown=copy.deepcopy(record); unknown["unexpected"]=True
assert list(validator.iter_errors(unknown))
missing=copy.deepcopy(record); del missing["artifact_digest"]
assert list(validator.iter_errors(missing))
bad_digest=copy.deepcopy(record); bad_digest["model_digest"]="sha256:not-a-digest"
assert list(validator.iter_errors(bad_digest))
print("MODEL_SCHEMA_POSITIVE_NEGATIVE_FIXTURES=PASS")
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
