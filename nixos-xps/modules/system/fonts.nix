{pkgs, ...}: {
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      # ── Coding fonts ─────────────────────────────────────────────────────
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.hack
      nerd-fonts.iosevka
      # ── UI fonts ──────────────────────────────────────────────────────────
      inter
      source-sans-pro
      source-serif-pro
      # ── CJK ───────────────────────────────────────────────────────────────
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      # ── Special ───────────────────────────────────────────────────────────
      font-awesome
      material-design-icons
    ];

    fontconfig = {
      defaultFonts = {
        serif = ["Source Serif Pro" "Noto Serif"];
        sansSerif = ["Inter" "Noto Sans"];
        monospace = ["JetBrainsMono Nerd Font" "Fira Code"];
        emoji = ["Noto Color Emoji"];
      };
      antialias = true;
      hinting = {
        enable = true;
        style = "slight";
      };
      subpixel.rgba = "rgb";
    };
  };
}
