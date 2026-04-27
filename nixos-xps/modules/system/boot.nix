{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── Bootloader ──────────────────────────────────────────────────────────────
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;  # keep last 10 generations
      editor = false;           # security: no kernel cmdline editing
    };
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  # ── Plymouth splash ──────────────────────────────────────────────────────────
  boot.plymouth = {
    enable = true;
    theme = "bgrt";  # OEM logo; override in stylix
  };

  # ── Silent boot ─────────────────────────────────────────────────────────────
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
  ];

  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # ── Tmp on tmpfs ─────────────────────────────────────────────────────────────
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "25%";
}
