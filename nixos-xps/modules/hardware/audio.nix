{pkgs, ...}: {
  # ── Disable PulseAudio (replaced by PipeWire) ────────────────────────────────
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # ── PipeWire ─────────────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;

    extraConfig.pipewire."92-low-latency" = {
      context.properties = {
        default.clock.rate = 48000;
        default.clock.quantum = 32;
        default.clock.min-quantum = 32;
        default.clock.max-quantum = 32;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    pavucontrol   # GUI volume mixer
    helvum        # PipeWire patchbay
    easyeffects   # DSP / EQ
  ];
}
