{pkgs, ...}: {
  # ── SSH ──────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # ── Printing ─────────────────────────────────────────────────────────────────
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # ── Locate / mlocate ─────────────────────────────────────────────────────────
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    localuser = null;
  };

  # ── D-Bus ────────────────────────────────────────────────────────────────────
  services.dbus.enable = true;

  # ── Automatic GC ─────────────────────────────────────────────────────────────
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ── Docker (optional, commented out by default) ───────────────────────────────
  # virtualisation.docker.enable = true;
}
