#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

rm -f /etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf
rm -f /usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable

if [[ -f /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env ]] && \
   [[ "$(tr -d '\r\n' </etc/nvidia-container-toolkit/nvidia-cdi-refresh.env)" == \
      "NVIDIA_CTK_CDI_GENERATE_MODE=csv" ]]; then
    rm -f /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
fi

systemctl set-default graphical.target
systemctl daemon-reload

echo "AETHERIS patch files removed."
echo "Historical backups under /var/lib/aetheris-edge-patches were preserved."
echo "Reboot is recommended."
