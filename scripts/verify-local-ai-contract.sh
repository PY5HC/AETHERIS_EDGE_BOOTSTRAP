#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ printf 'FAIL %s\n' "$1" >&2; exit 1; }
for f in docs/G4.1-local-ai-contract.md schemas/local-ai-model-record.schema.json schemas/local-ai-benchmark-record.schema.json schemas/local-ai-runtime-capabilities.schema.json templates/local-ai-model-record.json.template scripts/verify-local-ai-contract.sh tests/g4.1-local-ai-contract-static-check.sh; do
  [ -f "$ROOT_DIR/$f" ] || fail "missing:$f"
done
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
for name in ("local-ai-model-record.schema.json","local-ai-benchmark-record.schema.json","local-ai-runtime-capabilities.schema.json"):
    data=json.loads((root/"schemas"/name).read_text())
    if data.get("additionalProperties") is not False: raise SystemExit("non-strict:"+name)
template=(root/"templates/local-ai-model-record.json.template").read_text()
for token in ("@MODEL_ID@","@MODEL_ROLE@","@UPSTREAM_MODEL@","@ARTIFACT_DIGEST@","@MODEL_DIGEST@","@RUNTIME_BACKEND@","@HARDWARE_CLASS@"):
    if token not in template: raise SystemExit("missing-token:"+token)
doc=(root/"docs/G4.1-local-ai-contract.md").read_text()
for phrase in ("AETHERIS Local AI Contract","LOCAL_AI_SMALL","LOCAL_AI_MEDIUM","LOCAL_AI_EXPERIMENTAL","DISCOVERED","STAGED","VALIDATED","AVAILABLE","ACTIVE","DEGRADED","FAILED","RETIRED","AETHERIS SKY is deferred"):
    if phrase not in doc: raise SystemExit("missing-doc:"+phrase)
for forbidden in ("machine-id","docker.sock","useradd","groupadd","systemctl start","systemctl stop","systemctl restart","nvpmodel -m","nvpmodel -f","--force"):
    if forbidden in template or forbidden in doc: raise SystemExit("unsafe-contract:"+forbidden)
PY
printf 'LOCAL_AI_CONTRACT=PASS\n'
