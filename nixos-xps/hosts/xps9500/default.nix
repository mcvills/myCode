{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  # ── Identity ────────────────────────────────────────────────────────────────
  networking.hostName = "xps9500";

  # ── Disko disk layout (BTRFS + snapper) ─────────────────────────────────────
  imports = [
    ./disk-config.nix
    ./hardware-quirks.nix
  ];

  # ── State version — pin to initial install NixOS version ────────────────────
  system.stateVersion = "25.11";
}
