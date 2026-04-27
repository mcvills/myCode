# Declarative disk layout via disko
# Partition scheme:
#   /dev/disk/by-id/... (set DISK in install script)
#   ├── 1 GiB   EFI  (FAT32)
#   ├── 4 GiB   SWAP (encrypted)
#   └── rest    LUKS → BTRFS
#                 @         /
#                 @home     /home
#                 @nix      /nix
#                 @log      /var/log
#                 @snapshots /.snapshots
#                 @persist  /persist   ← impermanence
{lib, ...}: let
  # Override at install time: DISK=/dev/nvme0n1 nixos-install …
  disk = lib.mkDefault "/dev/nvme0n1";
in {
  disko.devices = {
    disk.main = {
      device = disk;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # ── EFI System Partition ───────────────────────────────────────────
          ESP = {
            priority = 1;
            name = "ESP";
            start = "1MiB";
            end = "1GiB";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["fmask=0077" "dmask=0077"];
            };
          };

          # ── Encrypted BTRFS ────────────────────────────────────────────────
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
              };
              passwordFile = "/tmp/disk.key"; # provided by install script
              content = {
                type = "btrfs";
                extraArgs = ["-L" "nixos" "-f"];
                subvolumes = {
                  # ── Root (ephemeral with impermanence) ─────────────────────
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Home ───────────────────────────────────────────────────
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Nix store (never snapshotted, huge) ────────────────────
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Logs ───────────────────────────────────────────────────
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Snapper snapshots ──────────────────────────────────────
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Persistent state (impermanence) ────────────────────────
                  "@persist" = {
                    mountpoint = "/persist";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  # ── Swap (file inside BTRFS — CoW disabled at mkfs) ────────
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = ["noatime"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # ── Swap file ───────────────────────────────────────────────────────────────
  swapDevices = [{device = "/swap/swapfile"; size = 16 * 1024;}]; # 16 GiB

  # ── Impermanence: whitelist persistent paths ─────────────────────────────────
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/etc/ssh"
      "/var/lib/bluetooth"
      "/var/lib/systemd/coredump"
      "/var/lib/NetworkManager"
      "/var/db/sudo"
    ];
    files = [
      "/etc/machine-id"
      "/etc/adjtime"
    ];
  };
}
