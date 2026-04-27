# Display manager settings shared between Hyprland and GNOME
{...}: {
  # GDM is used as fallback when switching to GNOME session
  services.xserver.displayManager.gdm = {
    enable = false;   # tuigreet is primary; flip to true for GNOME-only mode
    wayland = true;
  };
}
