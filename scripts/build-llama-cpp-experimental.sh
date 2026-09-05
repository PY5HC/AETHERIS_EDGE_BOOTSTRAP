#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR=${SOURCE_DIR:-}
BUILD_ROOT=${BUILD_ROOT:-}
RUNTIME_ROOT=${RUNTIME_ROOT:-}
EXPECTED_COMMIT=6a1a922d269908a29cbd4b49c27e6a8e7fd10fae
UPSTREAM_URL=https://github.com/ggml-org/llama.cpp.git
die(){ echo "FAIL $1" >&2; exit 1; }
[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.git" ]] || die source-dir
[[ -n "$BUILD_ROOT" && -n "$RUNTIME_ROOT" ]] || die output-required
[[ "$BUILD_ROOT" != /opt/aetheris* && "$BUILD_ROOT" != /etc/aetheris* && "$BUILD_ROOT" != /var/lib/aetheris* && "$BUILD_ROOT" != /run/aetheris* ]] || die live-build-output
[[ "$RUNTIME_ROOT" != /opt/aetheris* && "$RUNTIME_ROOT" != /etc/aetheris* && "$RUNTIME_ROOT" != /var/lib/aetheris* && "$RUNTIME_ROOT" != /run/aetheris* ]] || die live-output
command -v cmake >/dev/null || die cmake
command -v git >/dev/null || die git
command -v jq >/dev/null || die jq
[[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] || die source-commit
[[ "$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null)" == "$UPSTREAM_URL" ]] || die source-origin
[[ "$(uname -m)" == aarch64 ]] || die architecture
[[ ! -e "$RUNTIME_ROOT" ]] || die runtime-root-preexists
mkdir -p "$BUILD_ROOT" "$RUNTIME_ROOT/bin" "$RUNTIME_ROOT/metadata"
FLAGS=(-DGGML_CUDA=ON -DGGML_NATIVE=OFF -DCMAKE_CUDA_ARCHITECTURES=87 -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_TOOLS=OFF)
cmake -S "$SOURCE_DIR" -B "$BUILD_ROOT" "${FLAGS[@]}"
cmake --build "$BUILD_ROOT" --parallel "${BUILD_JOBS:-2}"
for name in llama-cli llama-server; do
  source_artifact="$BUILD_ROOT/bin/$name"
  [[ -x "$source_artifact" ]] || die "missing-$name"
  cp --preserve=mode "$source_artifact" "$RUNTIME_ROOT/bin/$name"
done
chmod 0750 "$RUNTIME_ROOT/bin/llama-cli" "$RUNTIME_ROOT/bin/llama-server"
CLI_HASH=$(sha256sum "$RUNTIME_ROOT/bin/llama-cli" | awk '{print $1}')
SERVER_HASH=$(sha256sum "$RUNTIME_ROOT/bin/llama-server" | awk '{print $1}')
CUDA_VERSION=$(nvcc --version 2>/dev/null | sed -n 's/.*release \([^,]*\),.*/\1/p')
[[ -n "$CUDA_VERSION" ]] || CUDA_VERSION=NOT_VERIFIED
jq -n --arg commit "$EXPECTED_COMMIT" --arg date "$(git -C "$SOURCE_DIR" show -s --format=%cI HEAD)" --arg arch "$(uname -m)" --arg cuda "$CUDA_VERSION" --arg cli "$CLI_HASH" --arg server "$SERVER_HASH" '{schema_version:"1.0",runtime:"llama.cpp",source:{url:"https://github.com/ggml-org/llama.cpp.git",commit:$commit,commit_date:$date,license:"MIT"},target:{architecture:$arch,platform:"Jetson Orin Nano Super"},toolchain:{compiler:"gcc",compiler_version:"recorded-at-build",cmake:"recorded-at-build",cuda:$cuda},build:{system:"cmake",flags:["GGML_CUDA=ON","GGML_NATIVE=OFF","CMAKE_CUDA_ARCHITECTURES=87","CMAKE_BUILD_TYPE=Release","LLAMA_BUILD_UI=OFF","LLAMA_USE_PREBUILT_UI=OFF","LLAMA_BUILD_TESTS=OFF","LLAMA_BUILD_EXAMPLES=ON","LLAMA_BUILD_SERVER=ON","LLAMA_BUILD_APP=OFF","LLAMA_BUILD_TOOLS=OFF"]},artifacts:[{path:"bin/llama-cli",sha256:$cli,executable:true},{path:"bin/llama-server",sha256:$server,executable:true}]}' > "$RUNTIME_ROOT/metadata/runtime-build-manifest.json"
echo "BUILD_MANIFEST=$RUNTIME_ROOT/metadata/runtime-build-manifest.json"
echo BUILD_COMPLETE=PASS
