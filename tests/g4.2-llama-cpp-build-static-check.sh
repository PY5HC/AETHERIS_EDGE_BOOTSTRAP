#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL $1" >&2; exit 1; }
APPLY="$ROOT_DIR/scripts/build-llama-cpp-experimental.sh"
VERIFY="$ROOT_DIR/scripts/verify-local-ai-runtime-build.sh"
bash -n "$APPLY" "$VERIFY" || fail syntax
shellcheck "$APPLY" "$VERIFY" || fail shellcheck
grep -Fq 'EXPECTED_COMMIT=6a1a922d269908a29cbd4b49c27e6a8e7fd10fae' "$APPLY" || fail pin
grep -Fq -- '-DGGML_CUDA=ON' "$APPLY" || fail cuda
grep -Fq -- '-DCMAKE_CUDA_ARCHITECTURES=87' "$APPLY" || fail cuda-arch
grep -Fq -- '-DLLAMA_USE_PREBUILT_UI=OFF' "$APPLY" || fail unpinned-ui
grep -Eq 'RUNTIME_ROOT.*(/opt/aetheris|/etc/aetheris)' "$APPLY" || fail live-output-guard
grep -Eq 'BUILD_ROOT.*(/opt/aetheris|/etc/aetheris|/var/lib/aetheris|/run/aetheris)' "$APPLY" || fail live-build-output-guard
! grep -Eq 'systemctl|useradd|groupadd|docker\.sock|nvpmodel[[:space:]]+(-m|-f|--force)|apt([[:space:]]|$)' "$APPLY" "$VERIFY" || fail mutation
! grep -Eq 'mkdir[^\n]*(/opt/aetheris|/etc/aetheris|/var/lib/aetheris|/run/aetheris)|cp[^\n]*(/opt/aetheris|/etc/aetheris|/var/lib/aetheris|/run/aetheris)' "$APPLY" "$VERIFY" || fail authority
python3 - "$ROOT_DIR/schemas/local-ai-runtime-build-manifest.schema.json" <<'PY'
import json,sys
from jsonschema import Draft202012Validator
s=json.load(open(sys.argv[1])); record={'schema_version':'1.0','runtime':'llama.cpp','source':{'url':'https://github.com/ggml-org/llama.cpp.git','commit':'a'*40,'commit_date':'2026-01-01T00:00:00Z','license':'MIT'},'target':{'architecture':'aarch64','platform':'fixture'},'toolchain':{'compiler':'gcc','compiler_version':'13','cmake':'3','cuda':'13'},'build':{'system':'cmake','flags':['GGML_CUDA=ON']},'artifacts':[{'path':'bin/llama-cli','sha256':'b'*64,'executable':True}]}; assert not list(Draft202012Validator(s).iter_errors(record)); print('MANIFEST_SCHEMA_FIXTURES=PASS')
PY
while read -r mode path; do actual=$(git -C "$ROOT_DIR" ls-files --stage -- "$path" | awk 'NR==1{print $1}'); [ "$actual" = "$mode" ] || fail "mode:$path"; done <<'EOF'
100644 docs/G4.2-llama-cpp-build.md
100644 schemas/local-ai-runtime-build-manifest.schema.json
100755 scripts/build-llama-cpp-experimental.sh
100755 scripts/verify-local-ai-runtime-build.sh
100755 tests/g4.2-llama-cpp-build-static-check.sh
EOF
echo G4_2_LLAMA_CPP_BUILD_STATIC_CHECK=PASS
