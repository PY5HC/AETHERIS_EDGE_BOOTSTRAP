#!/usr/bin/env bash
set -u

fail=0

check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS  %s\n' "$name"
    else
        printf 'FAIL  %s\n' "$name"
        fail=1
    fi
}

echo "=== AETHERIS EDGE HEADLESS/CDI VERIFY ==="
date -u +"UTC=%Y-%m-%dT%H:%M:%SZ"

check "default target multi-user" test "$(systemctl get-default)" = "multi-user.target"
check "GDM inactive" test "$(systemctl is-active gdm 2>/dev/null)" != "active"
check "CDI env CSV mode" grep -qx 'NVIDIA_CTK_CDI_GENERATE_MODE=csv' /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
check "DRM helper executable" test -x /usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable
check "CDI drop-in present" test -f /etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf

echo
echo "=== DRM ==="
ls -la /dev/dri || true

echo
echo "=== CDI ==="
nvidia-ctk cdi list || fail=1

echo
echo "=== CDI REFERENCES ==="
bad=0
while read -r p; do
    [[ -e "$p" ]] || { echo "STALE_CDI_DEVICE $p"; bad=1; }
done < <(grep -oE '/dev/dri/(card[0-9]+|renderD[0-9]+)' /var/run/cdi/nvidia.yaml 2>/dev/null | sort -u)
[[ "$bad" -eq 0 ]] && echo "PASS  all CDI DRM references exist" || { echo "FAIL  stale CDI DRM reference"; fail=1; }

echo
echo "=== NVIDIA ==="
nvidia-smi || fail=1
nvpmodel -q || true

echo
echo "=== FAILED UNITS ==="
systemctl --failed --no-pager || true

echo
if [[ "$fail" -eq 0 ]]; then
    echo "AETHERIS_EDGE_HEADLESS_CDI_PATCH=PASS"
else
    echo "AETHERIS_EDGE_HEADLESS_CDI_PATCH=FAIL"
fi

exit "$fail"
