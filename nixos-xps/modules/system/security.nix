{pkgs, ...}: {
  # ── Sudo ─────────────────────────────────────────────────────────────────────
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    extraConfig = ''
      Defaults lecture = never
      Defaults pwfeedback
    '';
  };

  # ── PAM / Keyring ────────────────────────────────────────────────────────────
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # ── Kernel hardening ─────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.default.log_martians" = true;
  };

  # ── AppArmor ─────────────────────────────────────────────────────────────────
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = false;
  };
}
