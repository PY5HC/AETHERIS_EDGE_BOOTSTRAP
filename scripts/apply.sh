#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
BACKUP="/var/lib/aetheris-edge-patches/headless-cdi-${STAMP}"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

install -d -m 0755 "$BACKUP"
install -d -m 0755 /etc/nvidia-container-toolkit
install -d -m 0755 /etc/systemd/system/nvidia-cdi-refresh.service.d
install -d -m 0755 /usr/local/libexec/aetheris-edge

for f in \
    /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env \
    /etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf \
    /usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable
do
    if [[ -e "$f" ]]; then
        cp -a --parents "$f" "$BACKUP"
    fi
done

cat >"$BACKUP/metadata.txt" <<EOF
applied_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname=$(hostname)
kernel=$(uname -r)
default_target_before=$(systemctl get-default)
EOF

install -m 0644 \
    "$ROOT/files/etc/nvidia-container-toolkit/nvidia-cdi-refresh.env" \
    /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env

install -m 0644 \
    "$ROOT/files/etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf" \
    /etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf

install -m 0755 \
    "$ROOT/files/usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable" \
    /usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable

systemctl set-default multi-user.target
systemctl daemon-reload

echo
echo "AETHERIS patch applied."
echo "Backup: $BACKUP"
echo "Reboot is required for persistence validation."
