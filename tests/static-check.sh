#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/apply.sh"
bash -n "$ROOT/scripts/rollback.sh"
bash -n "$ROOT/scripts/verify.sh"
bash -n "$ROOT/files/usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable"

grep -qx 'NVIDIA_CTK_CDI_GENERATE_MODE=csv' \
    "$ROOT/files/etc/nvidia-container-toolkit/nvidia-cdi-refresh.env"

grep -q '^ExecStartPre=/usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable$' \
    "$ROOT/files/etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf"

echo "STATIC_CHECK=PASS"
