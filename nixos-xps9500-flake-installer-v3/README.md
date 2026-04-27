# NixOS XPS 9500 Flake Installer V3

V3 adds live-ISO preflight checks, readable TTY font setup, physical/VM detection, Ventoy auto-mounting to `/mnt/scripts`, network validation, and optional `gum`/`figlet` when available.

## Preflight

```bash
sudo -i
/mnt/scripts/install-nixos-xps9500-v3.sh --preflight
```

## Manual Ventoy mount, if needed

```bash
mkdir -p /mnt/scripts
mount -t exfat /dev/sda1 /mnt/scripts
```

## Install on Dell XPS 9500

```bash
TARGET_DISK=/dev/nvme0n1 PROFILE=xps9500 WIPE_DISK=true /mnt/scripts/install-nixos-xps9500-v3.sh
```

## Install in VM

```bash
TARGET_DISK=/dev/vda PROFILE=vm HOSTNAME=nixos-vm WIPE_DISK=true /mnt/scripts/install-nixos-xps9500-v3.sh
```

`WIPE_DISK=true` is destructive. Snapper preserves future snapshots after install; it does not preserve pre-install data.
