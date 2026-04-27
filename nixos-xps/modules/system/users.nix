{pkgs, ...}: {
  # ── Main user ────────────────────────────────────────────────────────────────
  # Password is set imperatively via `passwd` after install, or use hashedPassword
  users.users.nixuser = {
    isNormalUser = true;
    description = "NixOS User";
    extraGroups = [
      "wheel"          # sudo
      "networkmanager" # manage wifi
      "video"          # backlight
      "audio"          # audio devices
      "docker"         # docker (if enabled)
      "libvirtd"       # VMs
      "input"          # input devices (for Hyprland)
      "plugdev"        # USB devices
    ];
    shell = pkgs.fish;
  };

  # ── Fish shell ───────────────────────────────────────────────────────────────
  programs.fish.enable = true;

  # ── Dconf (GNOME settings persistence) ──────────────────────────────────────
  programs.dconf.enable = true;
}
