#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST=${1:-}
die(){ echo "FAIL $1" >&2; exit 1; }
[[ -n "$MANIFEST" && -f "$MANIFEST" ]] || die manifest
command -v jsonschema >/dev/null || die jsonschema
jsonschema -i "$MANIFEST" "$ROOT_DIR/schemas/local-ai-runtime-build-manifest.schema.json" >/dev/null || die schema
python3 - "$MANIFEST" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d['source']['commit']=='6a1a922d269908a29cbd4b49c27e6a8e7fd10fae'; assert d['target']['architecture']=='aarch64'; assert 'GGML_CUDA=ON' in d['build']['flags']; assert all(not x['path'].startswith('/') and '..' not in x['path'] for x in d['artifacts']); print('RUNTIME_BUILD_MANIFEST=PASS')
PY
echo LOCAL_AI_RUNTIME_BUILD_CONTRACT=PASS
