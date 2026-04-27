# NVIDIA GeForce GTX 1650 Ti (XPS 9500) — PRIME render offload
# Run GPU-accelerated apps with:  nvidia-offload <app>
{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── NVIDIA driver ────────────────────────────────────────────────────────────
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    # Use the production driver (latest stable)
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Required for Wayland
    modesetting.enable = true;

    # Power management (suspend/resume fixes)
    powerManagement = {
      enable = true;
      finegrained = true;  # RTD3 — turn off GPU when idle
    };

    # Kernel open module (Maxwell+ supported; GTX 1650 Ti = Turing ✓)
    open = true;

    # nvidia-settings GUI
    nvidiaSettings = true;

    # ── PRIME offload (Intel iGPU primary, NVIDIA dGPU on demand) ────────────
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;  # adds `nvidia-offload` wrapper
      };
      # Bus IDs — verify with: lspci | grep -E "VGA|3D"
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # ── CUDA / OpenCL ────────────────────────────────────────────────────────────
  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver  # NVENC/NVDEC via VAAPI
  ];

  # ── Environment variables (Wayland + NVIDIA) ─────────────────────────────────
  environment.sessionVariables = {
    # Hyprland / Wayland
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    # Electron apps
    NIXOS_OZONE_WL = "1";
  };

  # ── Kernel params ────────────────────────────────────────────────────────────
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
  ];

  boot.initrd.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
}
