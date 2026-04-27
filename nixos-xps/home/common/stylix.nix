{pkgs, ...}: {
  stylix = {
    enable = true;
    autoEnable = true;

    # ── Base image (used for wallpaper + color extraction) ───────────────────
    # Replace with your own wallpaper path after install
    image = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/wallpapers/main/landscapes/evening-sky.png";
      sha256 = "sha256-+DP3cJGiHJYGRB0Lr8ph0XVjGJzT1MtOJYiF+cqR1M=";
    };

    # ── Catppuccin Mocha palette (base16) ────────────────────────────────────
    base16Scheme = {
      base00 = "1e1e2e"; # base
      base01 = "181825"; # mantle
      base02 = "313244"; # surface0
      base03 = "45475a"; # surface1
      base04 = "585b70"; # surface2
      base05 = "cdd6f4"; # text
      base06 = "f5e0dc"; # rosewater
      base07 = "b4befe"; # lavender
      base08 = "f38ba8"; # red
      base09 = "fab387"; # peach
      base0A = "f9e2af"; # yellow
      base0B = "a6e3a1"; # green
      base0C = "94e2d5"; # teal
      base0D = "89b4fa"; # blue
      base0E = "cba6f7"; # mauve
      base0F = "f2cdcd"; # flamingo
    };

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      sizes = {
        applications = 11;
        terminal = 13;
        desktop = 11;
      };
    };

    cursor = {
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
      size = 24;
    };

    # ── GTK / Qt theming ─────────────────────────────────────────────────────
    targets.gtk.enable = true;

    opacity = {
      terminal = 0.92;
      popups = 0.90;
    };
  };
}
