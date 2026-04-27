# Hyprland — primary compositor
{
  inputs,
  pkgs,
  ...
}: {
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
    xwayland.enable = true;
  };

  # ── Supporting services ──────────────────────────────────────────────────────
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  # ── Environment packages needed system-wide for Hyprland ─────────────────────
  environment.systemPackages = with pkgs; [
    # Wayland utils
    wl-clipboard
    wl-clip-persist
    cliphist
    # Screenshot
    grimblast
    swappy
    # Screen lock
    swaylock-effects
    swayidle
    # Notifications
    dunst
    libnotify
    # App launcher
    rofi-wayland
    # Wallpaper
    swww
    # Bar
    waybar
    # Status / systray
    networkmanagerapplet
    # OSD
    swayosd
    # Colour picker
    hyprpicker
  ];

  # ── Polkit (needed for privilege escalation in Wayland) ──────────────────────
  security.polkit.enable = true;
  systemd.user.services.polkit-gnome-authentication-agent = {
    description = "polkit-gnome-authentication-agent";
    wantedBy = ["graphical-session.target"];
    wants = ["graphical-session.target"];
    after = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };
}
