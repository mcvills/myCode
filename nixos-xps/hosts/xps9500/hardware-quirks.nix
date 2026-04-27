# Dell XPS 15 9500 hardware quirks
{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── Kernel modules ──────────────────────────────────────────────────────────
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];

  boot.kernelModules = ["kvm-intel" "i915"];

  # ── i915 / Intel Iris Plus ──────────────────────────────────────────────────
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # VAAPI for Intel
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # ── Thunderbolt ─────────────────────────────────────────────────────────────
  services.hardware.bolt.enable = true;

  # ── SD card reader ──────────────────────────────────────────────────────────
  boot.kernelParams = ["mem_sleep_default=deep"];

  # ── Fan / thermal ───────────────────────────────────────────────────────────
  services.thermald.enable = true;
  services.fwupd.enable = true;  # firmware updates
}
