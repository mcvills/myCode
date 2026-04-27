# GNOME — backup / fallback desktop
{pkgs, ...}: {
  services.xserver = {
    enable = true;
    desktopManager.gnome.enable = true;
  };

  # ── Remove GNOME bloat ──────────────────────────────────────────────────────
  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    gnome-maps
    gnome-weather
    gnome-contacts
    gnome-music
    totem
    yelp
    epiphany
    geary
    evince
  ];

  # ── Useful GNOME extensions ─────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    gnomeExtensions.dash-to-dock
    gnomeExtensions.appindicator
    gnomeExtensions.blur-my-shell
    gnomeExtensions.just-perfection
    gnomeExtensions.pop-shell
    gnomeExtensions.user-themes
    gnome-tweaks
  ];
}
