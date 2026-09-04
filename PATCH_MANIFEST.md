# Patch Manifest

## Files installed

- `/etc/nvidia-container-toolkit/nvidia-cdi-refresh.env`
- `/etc/systemd/system/nvidia-cdi-refresh.service.d/10-aetheris-drm-stable.conf`
- `/usr/local/libexec/aetheris-edge/wait-nvidia-drm-stable`

## System state changed

- default systemd target -> `multi-user.target`
- systemd daemon reload

## Explicitly not changed

- `nvpmodel.service`
- NVIDIA packages
- kernel modules
- firmware
- swap
- DNS/DHCP services
- Docker daemon configuration
- NVIDIA stock `nvidia-cdi-refresh.service`
- NVIDIA CSV manifests

## Required validation

After application, reboot and run `sudo ./scripts/verify.sh`.
Persistent remediation is not PASS until the post-reboot verification succeeds.
