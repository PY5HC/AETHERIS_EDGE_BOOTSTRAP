#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
require_value(){ [ -n "$2" ] || { echo "ERROR: empty discovery value: $1" >&2; exit 1; }; }
require_executable(){ [ -n "$2" ] && [ -x "$2" ] || { echo "ERROR: executable unavailable: $1" >&2; exit 1; }; }

validate_identity_render(){
    local identity_file="$1"
    python3 - "$identity_file" <<'PY_IDENTITY'
import sys

expected = {
    'AETHERIS_NODE_ID', 'AETHERIS_NODE_ROLE', 'AETHERIS_NODE_CLASS',
    'AETHERIS_PLATFORM', 'AETHERIS_HOSTNAME', 'AETHERIS_MACHINE_ID',
    'AETHERIS_ARCH', 'AETHERIS_KERNEL', 'AETHERIS_OS',
    'AETHERIS_L4T_RELEASE', 'AETHERIS_JETPACK_RELEASE',
    'AETHERIS_POWER_PROFILE', 'AETHERIS_BOOT_PROFILE',
}
values = {}
for raw_line in open(sys.argv[1], encoding='utf-8'):
    line = raw_line.rstrip('\n')
    if not line:
        continue
    if '=' not in line:
        raise SystemExit('malformed identity line')
    key, value = line.split('=', 1)
    if key in values:
        raise SystemExit('duplicate identity key')
    if key not in expected:
        raise SystemExit('unknown identity key')
    if not value or '{{' in value or '}}' in value:
        raise SystemExit('empty or unresolved identity value')
    values[key] = value
if set(values) != expected or len(values) != 13:
    raise SystemExit('identity exact key set mismatch')
PY_IDENTITY
}

# Explicit repository-test hook: production default continues to discover, render,
# and then mutate only after all validation succeeds.
if [ -n "${AETHERIS_VALIDATE_IDENTITY_FILE:-}" ]; then
    validate_identity_render "$AETHERIS_VALIDATE_IDENTITY_FILE"
    exit 0
fi
NODE_ID="${AETHERIS_NODE_ID:-$(hostname)}"; NODE_ROLE="${AETHERIS_NODE_ROLE:-edge-compute}"; NODE_CLASS="${AETHERIS_NODE_CLASS:-jetson}"
MACHINE_ID="$(cat /etc/machine-id)"; HOSTNAME_NOW="$(hostname)"; ARCH="$(uname -m)"; KERNEL="$(uname -r)"
[ -r /etc/os-release ] || { echo "ERROR: /etc/os-release unreadable" >&2; exit 1; }; . /etc/os-release
require_value OS_ID "${ID:-}"; require_value OS_VERSION_ID "${VERSION_ID:-}"; OS="${ID}-${VERSION_ID}"
require_executable nvpmodel /usr/sbin/nvpmodel
POWER_QUERY="$(/usr/sbin/nvpmodel -q 2>/dev/null)" || { echo "ERROR: nvpmodel read-only query failed" >&2; exit 1; }
POWER_PROFILE="$(printf '%s\n' "$POWER_QUERY"|sed -n 's/^NV Power Mode:[[:space:]]*\([^[:space:]].*\)$/\1/p'|head -n1)"; POWER_PROFILE_ID="$(printf '%s\n' "$POWER_QUERY"|sed -n 's/^[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p'|head -n1)"
require_value POWER_PROFILE "$POWER_PROFILE"; require_value POWER_PROFILE_ID "$POWER_PROFILE_ID"
BOOT_TARGET="$(systemctl get-default 2>/dev/null)" || { echo "ERROR: systemctl get-default failed" >&2; exit 1; }; require_value BOOT_TARGET "$BOOT_TARGET"
[ "$BOOT_TARGET" = multi-user.target ] || { echo "ERROR: unsupported boot target $BOOT_TARGET" >&2; exit 1; }; BOOT_PROFILE=headless-conservative
[ -r /proc/device-tree/model ] || { echo "ERROR: device-tree model unreadable" >&2; exit 1; }; MODEL="$(tr -d '\000' </proc/device-tree/model)"; ML="$(printf '%s' "$MODEL"|tr '[:upper:]' '[:lower:]')"
[[ "$ML" == *jetson*orin\ nano* && "$ML" == *super* ]] || { echo "ERROR: unsupported platform model $MODEL" >&2; exit 1; }; DETECTED_PLATFORM=jetson-orin-nano-super
[ -z "${AETHERIS_PLATFORM:-}" ] || [ "$AETHERIS_PLATFORM" = "$DETECTED_PLATFORM" ] || { echo "ERROR: platform override mismatch" >&2; exit 1; }; PLATFORM="$DETECTED_PLATFORM"
[ "$ARCH" = aarch64 ] || { echo "ERROR: unsupported architecture $ARCH" >&2; exit 1; }
[ -r /etc/nv_tegra_release ] || { echo "ERROR: L4T release file unreadable" >&2; exit 1; }; L4T_RELEASE="$(sed -n 's/^# R\([0-9][0-9]*\).*REVISION: \([0-9.][0-9.]*\).*/\1.\2/p' /etc/nv_tegra_release|head -n1)"; require_value L4T_RELEASE "$L4T_RELEASE"
NVCC_BIN=""; [ -x /usr/local/cuda/bin/nvcc ] && NVCC_BIN=/usr/local/cuda/bin/nvcc; [ -n "$NVCC_BIN" ] || NVCC_BIN="$(command -v nvcc||true)"; require_executable nvcc "$NVCC_BIN"
CUDA_VERSION="$($NVCC_BIN --version 2>/dev/null|sed -n 's/.*release \([0-9.]*\).*/\1/p'|head -n1)"
package_version(){ dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null|head -n1|cut -d- -f1|cut -d+ -f1; }
CUDNN_VERSION="$(package_version libcudnn9-cuda-13)"; TENSORRT_VERSION="$(package_version libnvinfer10)"; VPI_VERSION="$(package_version libnvvpi4)"; JETPACK_RELEASE="$(package_version nvidia-jetpack)"
for v in CUDA_VERSION CUDNN_VERSION TENSORRT_VERSION VPI_VERSION JETPACK_RELEASE; do require_value "$v" "${!v}"; done
NVIDIA_CTK_BIN="$(command -v nvidia-ctk||true)"; require_executable nvidia-ctk "$NVIDIA_CTK_BIN"; CDI_OUTPUT="$($NVIDIA_CTK_BIN cdi list 2>/dev/null)" || { echo "ERROR: CDI enumeration failed" >&2; exit 1; }; printf '%s\n' "$CDI_OUTPUT"|grep -q nvidia.com/gpu || { echo "ERROR: no NVIDIA CDI devices" >&2; exit 1; }
DOCKER_BIN="$(command -v docker||true)"; require_executable docker "$DOCKER_BIN"; systemctl is-active --quiet docker || { echo "ERROR: docker service unavailable" >&2; exit 1; }
for v in NODE_ID NODE_ROLE NODE_CLASS MACHINE_ID HOSTNAME_NOW KERNEL; do require_value "$v" "${!v}"; done
render_template(){ local src="$1" dst="$2"; env NODE_ID="$NODE_ID" NODE_ROLE="$NODE_ROLE" NODE_CLASS="$NODE_CLASS" PLATFORM="$PLATFORM" HOSTNAME="$HOSTNAME_NOW" MACHINE_ID="$MACHINE_ID" ARCH="$ARCH" KERNEL="$KERNEL" OS="$OS" L4T_RELEASE="$L4T_RELEASE" JETPACK_RELEASE="$JETPACK_RELEASE" POWER_PROFILE="$POWER_PROFILE" BOOT_PROFILE="$BOOT_PROFILE" CUDA_VERSION="$CUDA_VERSION" CUDNN_VERSION="$CUDNN_VERSION" TENSORRT_VERSION="$TENSORRT_VERSION" VPI_VERSION="$VPI_VERSION" python3 - "$src" "$dst" <<'PY2'
import os,pathlib,sys
src,dst=map(pathlib.Path,sys.argv[1:]); text=src.read_text(); names='NODE_ID NODE_ROLE NODE_CLASS PLATFORM HOSTNAME MACHINE_ID ARCH KERNEL OS L4T_RELEASE JETPACK_RELEASE POWER_PROFILE BOOT_PROFILE CUDA_VERSION CUDNN_VERSION TENSORRT_VERSION VPI_VERSION'.split()
for n in names:
 v=os.environ[n]
 if not v: raise SystemExit('empty render value '+n)
 text=text.replace('{{'+n+'}}',v)
if '{{' in text or '}}' in text: raise SystemExit('unresolved template placeholder')
dst.write_text(text)
PY2
}
TMP_IDENTITY="$(mktemp)"; TMP_CAPABILITIES="$(mktemp)"; trap 'rm -f "$TMP_IDENTITY" "$TMP_CAPABILITIES"' EXIT
render_template "$ROOT_DIR/templates/node-identity.env.template" "$TMP_IDENTITY"; render_template "$ROOT_DIR/templates/capabilities.json.template" "$TMP_CAPABILITIES"
python3 -m json.tool "$TMP_CAPABILITIES" >/dev/null
! grep -REq '\{\{[^}]+\}\}' "$TMP_IDENTITY" "$TMP_CAPABILITIES"
validate_identity_render "$TMP_IDENTITY"
# Discovery/rendering/validation complete: persistent mutation starts here.
if [ "${AETHERIS_VALIDATE_ONLY:-0}" = 1 ]; then
    echo "AETHERIS validation-only PASS"
    exit 0
fi
getent group aetheris >/dev/null 2>&1 || groupadd --system aetheris
install -d -o root -g aetheris -m 0750 /etc/aetheris /etc/aetheris/node; install -d -o root -g aetheris -m 0755 /opt/aetheris /opt/aetheris/releases /opt/aetheris/current; install -d -o root -g aetheris -m 0750 /var/lib/aetheris /var/lib/aetheris/node /var/log/aetheris
install -o root -g root -m 0644 "$ROOT_DIR/files/usr/lib/tmpfiles.d/aetheris.conf" /usr/lib/tmpfiles.d/aetheris.conf; systemd-tmpfiles --create /usr/lib/tmpfiles.d/aetheris.conf
install -o root -g aetheris -m 0640 "$TMP_IDENTITY" /etc/aetheris/node/identity.env; install -o root -g aetheris -m 0640 "$TMP_CAPABILITIES" /etc/aetheris/node/capabilities.json
echo 'AETHERIS node contract applied'
