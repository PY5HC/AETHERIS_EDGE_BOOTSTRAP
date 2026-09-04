# AETHERIS EDGE — Jetson Orin Nano Super headless + CDI stabilization patch

Reference target: NVIDIA Jetson Orin Nano Super, L4T R39.2 / JetPack 7.2.1, Ubuntu 24.04, NVIDIA Container Toolkit 1.19.1.

## Scope

This bootstrap codifies the configuration validated on `aetheris-edge-02`:

1. switch the default systemd target to `multi-user.target`;
2. force NVIDIA CDI generation to use Jetson CSV discovery;
3. delay CDI generation until the final NVIDIA DRM topology is present and stable;
4. preserve the stock NVIDIA CDI unit and apply a systemd drop-in;
5. provide verification and rollback scripts.

It intentionally does **not** modify `nvpmodel.service`, the generic dnsmasq/ISC DHCP services, NVIDIA packages, kernel modules, firmware, swap, or the selected power mode.

## Why this exists

On the reference node, `nvidia-cdi-refresh.service` ran before the final NVIDIA DRM enumeration completed. The early CDI spec captured a transient `/dev/dri/card0`; after boot stabilized, the real topology was `card1`, `card2`, `renderD128`, `renderD129`. Docker CDI injection then failed because the stale spec referenced a device that no longer existed.

The helper waits for the NVIDIA display DRM path (`platform-13800000.display`) to expose both a card node and a render node, waits for udev to settle, and requires the complete `/dev/dri` node set to remain unchanged across multiple polls before allowing the stock NVIDIA CDI generator to run.

## Apply

```bash
sudo ./scripts/apply.sh
sudo reboot
```

After reconnecting:

```bash
sudo ./scripts/verify.sh
```

## Rollback

```bash
sudo ./scripts/rollback.sh
sudo reboot
```

## Status

- Headless profile: validated.
- CDI CSV discovery: validated.
- Stable-DRM regeneration: validated.
- Persistent boot-ordering remediation: implementation published here, still requires post-patch reboot homologation before PASS.
- `nvpmodel.service`: intentionally out of scope until its separate remediation is validated.
