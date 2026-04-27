# NixOS XPS 9500 Flake Installer v4

Boot NixOS 25.11 graphical ISO or minimal ISO.

Preflight:

```bash
sudo -i
bash install-nixos-xps9500-v4.sh --preflight
```

Install on Dell XPS 9500:

```bash
sudo -i
TARGET_DISK=/dev/nvme0n1 PROFILE=xps9500 WIPE_DISK=true bash install-nixos-xps9500-v4.sh
```

Install in VM:

```bash
sudo -i
TARGET_DISK=/dev/vda PROFILE=vm HOSTNAME=nixos-vm WIPE_DISK=true bash install-nixos-xps9500-v4.sh
```

This wipes the target disk. Snapper snapshots preserve future system states, not pre-install files.
