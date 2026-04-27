#!/usr/bin/env bash
set -euo pipefail
sudo -i bash -c '
  nix-shell -p exfatprogs ntfs3g unzip --run "bash -lc '\''
    mkdir -p /mnt/scripts
    for p in /dev/disk/by-label/Ventoy /dev/disk/by-label/VENTOY /dev/disk/by-label/ventoy; do
      [ -e \"$p\" ] && mount -o ro \"$p\" /mnt/scripts && break
    done
    mountpoint -q /mnt/scripts || for d in $(lsblk -rpno NAME,FSTYPE | awk '\''\''\''$2==\"exfat\"||$2==\"ntfs\"||$2==\"vfat\"{print $1}'\''\''\''); do
      mount -o ro \"$d\" /mnt/scripts && break
    done
    ls -lah /mnt/scripts
  '\''"
'
