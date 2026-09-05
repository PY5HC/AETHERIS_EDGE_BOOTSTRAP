#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST=${1:-}
die(){ echo "FAIL $1" >&2; exit 1; }
[[ -n "$MANIFEST" && -f "$MANIFEST" ]] || die manifest
command -v jsonschema >/dev/null || die jsonschema
command -v jq >/dev/null || die jq
command -v sha256sum >/dev/null || die sha256sum
command -v readelf >/dev/null || die readelf
jsonschema -i "$MANIFEST" "$ROOT_DIR/schemas/local-ai-runtime-build-manifest.schema.json" >/dev/null || die schema
python3 - "$MANIFEST" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d['source']['commit']=='6a1a922d269908a29cbd4b49c27e6a8e7fd10fae'; assert d['target']['architecture']=='aarch64'; assert 'GGML_CUDA=ON' in d['build']['flags']; assert 'LLAMA_BUILD_TOOLS=ON' in d['build']['flags']; assert 'LLAMA_BUILD_EXAMPLES=OFF' in d['build']['flags']; assert 'FILE_PREFIX_MAP=SOURCE' in d['build']['flags']; assert all(not x['path'].startswith('/') and '..' not in x['path'] for x in d['artifacts']+d['libraries']); print('RUNTIME_BUILD_MANIFEST=PASS')
PY
RUNTIME_ROOT="$(cd "$(dirname "$MANIFEST")/.." && pwd)"
while IFS=$'\t' read -r relative_path expected_hash; do
  artifact="$RUNTIME_ROOT/$relative_path"
  [[ -f "$artifact" ]] || die "missing:$relative_path"
  [[ "$(sha256sum "$artifact" | awk '{print $1}')" == "$expected_hash" ]] || die "hash:$relative_path"
done < <(jq -r '.artifacts[], .libraries[] | [.path,.sha256] | @tsv' "$MANIFEST")
while IFS= read -r executable_path; do
  executable="$RUNTIME_ROOT/$executable_path"
  readelf -h "$executable" | grep -Fq 'AArch64' || die "architecture:$executable_path"
  readelf -d "$executable" | grep -Fq "\$ORIGIN" || die "non-relocatable:$executable_path"
done < <(jq -r '.artifacts[] | select(.executable == true) | .path' "$MANIFEST")
echo LOCAL_AI_RUNTIME_BUILD_CONTRACT=PASS
