#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; APPLY="$ROOT_DIR/scripts/apply-node-contract.sh"; VERIFY="$ROOT_DIR/scripts/verify-node-contract.sh"
pass(){ echo "PASS $1"; }; fail(){ echo "FAIL $1"; exit 1; }
for f in "$APPLY" "$VERIFY" "$ROOT_DIR/tests/g3-node-contract-static-check.sh"; do bash -n "$f"||fail "bash -n $f"; done; pass 'shell syntax'
# Discovery and safety contract assertions.
grep -q '/etc/os-release' "$APPLY" && grep -q 'VERSION_ID' "$APPLY" && pass 'OS discovery source' || fail 'OS discovery source'
! grep -q 's|{{OS}}|ubuntu-24.04' "$APPLY" && pass 'no literal OS rendering' || fail 'literal OS rendering'
grep -q '/usr/sbin/nvpmodel -q' "$APPLY" && pass 'read-only nvpmodel query' || fail 'nvpmodel query'
! grep -Eq 'nvpmodel[[:space:]]+-m|nvpmodel[[:space:]]+-f|nvpmodel.*--force' "$APPLY" && pass 'no nvpmodel mutation flags' || fail 'forbidden nvpmodel mutation'
grep -q 'systemctl get-default' "$APPLY" && grep -q 'unsupported boot target' "$APPLY" && pass 'boot target discovery and rejection' || fail 'boot target contract'
grep -q '/proc/device-tree/model' "$APPLY" && grep -q "tr -d '\\\\000'" "$APPLY" && pass 'device-tree platform detection' || fail 'platform detection'
grep -q 'AETHERIS_PLATFORM.*DETECTED_PLATFORM' "$APPLY" && pass 'platform override mismatch rejection' || fail 'platform override contract'
grep -q 'ARCH.*aarch64\|aarch64.*ARCH' "$APPLY" && pass 'aarch64 validation' || fail 'architecture validation'
grep -q 'unresolved template placeholder' "$APPLY" && pass 'rendered placeholder rejection' || fail 'placeholder rejection'
grep -q 'python3 -m json.tool' "$APPLY" && pass 'rendered capability JSON validation' || fail 'JSON validation'
grep -q 'len(values) != 13' "$APPLY" && grep -q 'set(values) != expected' "$APPLY" && pass 'rendered identity exact key set' || fail 'identity exact key set'
# Verifier semantic coverage.
for needle in 'duplicate identity key' 'set(vals)!=set(keys)' 'D_MACHINE_ID' 'D_OS' 'D_L4T' 'D_JETPACK' 'D_POWER' 'D_BOOT_PROFILE' 'D_PLATFORM' 'capability' 'nvidia.com/gpu' 'systemctl is-active --quiet docker' 'exact tmpfiles content'; do grep -q "$needle" "$VERIFY" || fail "verifier coverage: $needle"; done; pass 'semantic verifier coverage'
grep -q "d /run/aetheris 0755 root aetheris -" "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris.conf" && pass 'exact tmpfiles content' || fail 'tmpfiles content'
grep -q '\[ -d /opt/aetheris/current \]' "$VERIFY" && pass 'current remains directory v1' || fail 'current v1 directory'
! grep -RIEq 'AETHERIS_MACHINE_ID=[0-9a-fA-F]{32}' "$ROOT_DIR/templates" "$ROOT_DIR/scripts" "$ROOT_DIR/files" "$ROOT_DIR/docs" && pass 'no real machine-id leak' || fail 'machine-id leak'
# Rendering fixture: deterministic, complete, valid JSON, no placeholders.
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TMP_DIR"' EXIT
sed -e 's|{{NODE_ID}}|test-edge-node|g' -e 's|{{NODE_ROLE}}|edge-compute|g' -e 's|{{NODE_CLASS}}|jetson|g' -e 's|{{PLATFORM}}|jetson-orin-nano-super|g' -e 's|{{HOSTNAME}}|test-edge-node|g' -e 's|{{MACHINE_ID}}|0123456789abcdef0123456789abcdef|g' -e 's|{{ARCH}}|aarch64|g' -e 's|{{KERNEL}}|test-kernel|g' -e 's|{{OS}}|ubuntu-24.04|g' -e 's|{{L4T_RELEASE}}|39.2.1|g' -e 's|{{JETPACK_RELEASE}}|7.2.1|g' -e 's|{{POWER_PROFILE}}|MAXN_SUPER|g' -e 's|{{BOOT_PROFILE}}|headless-conservative|g' "$ROOT_DIR/templates/node-identity.env.template" >"$TMP_DIR/identity.env"
sed -e 's|{{NODE_ID}}|test-edge-node|g' -e 's|{{NODE_ROLE}}|edge-compute|g' -e 's|{{PLATFORM}}|jetson-orin-nano-super|g' -e 's|{{ARCH}}|aarch64|g' -e 's|{{CUDA_VERSION}}|13.2|g' -e 's|{{CUDNN_VERSION}}|9.20.0.46|g' -e 's|{{TENSORRT_VERSION}}|10.16.2.10|g' -e 's|{{VPI_VERSION}}|4.1.4|g' "$ROOT_DIR/templates/capabilities.json.template" >"$TMP_DIR/capabilities.json"
! grep -REq '\{\{[^}]+\}\}' "$TMP_DIR" && pass 'fixture placeholders rendered' || fail 'fixture placeholders'
python3 -m json.tool "$TMP_DIR/capabilities.json" >/dev/null && pass 'fixture JSON' || fail 'fixture JSON'
# Mutation ordering: all render/validation markers precede first persistent mutation.
first=$(grep -nE 'groupadd|install -d|systemd-tmpfiles' "$APPLY"|head -n1|cut -d: -f1); last=$(grep -n 'python3 -m json.tool' "$APPLY"|tail -n1|cut -d: -f1); [ "$last" -lt "$first" ] && pass 'fail-before-mutation ordering' || fail 'mutation ordering'
# Existing root/minimal-PATH CUDA contract.
grep -q 'NVCC_BIN=""' "$APPLY" && grep -q '/usr/local/cuda/bin/nvcc' "$APPLY" && ! grep -nE '^[[:space:]]*nvcc[[:space:]]+--version' "$APPLY" && pass 'root/minimal-PATH CUDA discovery' || fail 'CUDA discovery'
git_mode_is(){
    local repo="$1" path="$2" expected="$3" actual
    actual="$(git -C "$repo" ls-files --stage -- "$path" | awk 'NR == 1 { print $1 }')"
    [ "$actual" = "$expected" ]
}
for f in docs/G3.0-node-bootstrap-contract.md files/usr/lib/tmpfiles.d/aetheris.conf templates/capabilities.json.template templates/node-identity.env.template; do
    git_mode_is "$ROOT_DIR" "$f" 100644 || fail "Git mode $f"
done
for f in scripts/apply-node-contract.sh scripts/verify-node-contract.sh tests/g3-node-contract-static-check.sh; do
    git_mode_is "$ROOT_DIR" "$f" 100755 || fail "Git mode $f"
done
pass 'canonical Git index modes'
# Runtime permission assertions remain explicit and are independent of checkout modes.
grep -q 'install -o root -g root -m 0644' "$APPLY" || fail 'tmpfiles install mode'
grep -q 'install -o root -g aetheris -m 0640.*TMP_IDENTITY' "$APPLY" || fail 'identity install mode'
grep -q 'install -o root -g aetheris -m 0640.*TMP_CAPABILITIES' "$APPLY" || fail 'capabilities install mode'
pass 'materialization permission contract'
# Isolated index fixtures prove both accepted modes and inverse-mode rejection.
MODE_FIXTURE="$TMP_DIR/mode-fixture"; mkdir "$MODE_FIXTURE"; git -C "$MODE_FIXTURE" init -q; git -C "$MODE_FIXTURE" config user.email test@example.invalid; git -C "$MODE_FIXTURE" config user.name test
: >"$MODE_FIXTURE/nonexec"; : >"$MODE_FIXTURE/executable"; chmod 644 "$MODE_FIXTURE/nonexec"; chmod 755 "$MODE_FIXTURE/executable"; git -C "$MODE_FIXTURE" add nonexec executable
git_mode_is "$MODE_FIXTURE" nonexec 100644 && pass 'fixture 100644 accepted' || fail 'fixture 100644 accepted'
git_mode_is "$MODE_FIXTURE" executable 100755 && pass 'fixture 100755 accepted' || fail 'fixture 100755 accepted'
if git_mode_is "$MODE_FIXTURE" nonexec 100755; then fail 'non-executable 100755 rejected'; else pass 'non-executable 100755 rejected'; fi
if git_mode_is "$MODE_FIXTURE" executable 100644; then fail 'executable 100644 rejected'; else pass 'executable 100644 rejected'; fi
! grep -RIn '[[:blank:]]$' "$ROOT_DIR/docs/G3.0-node-bootstrap-contract.md" "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris.conf" "$ROOT_DIR/scripts/apply-node-contract.sh" "$ROOT_DIR/scripts/verify-node-contract.sh" "$ROOT_DIR/templates/node-identity.env.template" "$ROOT_DIR/templates/capabilities.json.template" "$ROOT_DIR/tests/g3-node-contract-static-check.sh" && pass 'whitespace' || fail 'trailing whitespace'
# Execute the real apply discovery/render/validation path with its explicit
# validation-only boundary; no groupadd/install/tmpfiles operation is reached.
if AETHERIS_VALIDATE_ONLY=1 "$APPLY" >/dev/null; then pass 'real apply render/validation path'; else fail 'real apply render/validation path'; fi

# Exercise the exact validator through the apply script's isolated test hook.
make_identity(){
    local out="$1" count="$2" extra="${3:-}"
    sed 's/{{[^}]*}}/fixture/g' "$ROOT_DIR/templates/node-identity.env.template" >"$out"
    if [ "$count" = 12 ]; then sed -i '$d' "$out"; fi
    if [ "$count" = 14 ]; then printf '%s\n' 'AETHERIS_UNKNOWN=extra' >>"$out"; fi
    if [ "$count" = duplicate ]; then printf '%s\n' 'AETHERIS_NODE_ID=duplicate' >>"$out"; fi
    if [ "$count" = missing ]; then sed -i '1d' "$out"; fi
    if [ "$count" = empty ]; then sed -i '1s/=.*$/=/' "$out"; fi
    if [ "$count" = placeholder ]; then sed -i '1s/=.*$/={{UNRESOLVED}}/' "$out"; fi
}
identity_fixture="$TMP_DIR/identity-fixture.env"; make_identity "$identity_fixture" 13
AETHERIS_VALIDATE_IDENTITY_FILE="$identity_fixture" "$APPLY" >/dev/null && pass 'canonical 13-key identity' || fail 'canonical 13-key identity'
for case_name in 12 14 duplicate missing empty placeholder; do
    make_identity "$identity_fixture" "$case_name"
    if AETHERIS_VALIDATE_IDENTITY_FILE="$identity_fixture" "$APPLY" >/dev/null 2>&1; then fail "$case_name identity rejection"; else pass "$case_name identity rejection"; fi
done

echo G3_NODE_CONTRACT_STATIC_CHECK=PASS
