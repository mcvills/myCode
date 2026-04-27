{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixvim.homeManagerModules.nixvim

    ./hyprland/default.nix
    ./common/shell.nix
    ./common/git.nix
    ./common/fastfetch.nix
    ./common/ghostty.nix
    ./common/nvim.nix
    ./common/stylix.nix
  ];

  home = {
    username = "nixuser";
    homeDirectory = "/home/nixuser";
    stateVersion = "25.11";

    # ── Home packages (user-level) ───────────────────────────────────────────
    packages = with pkgs; [
      # Productivity
      keepassxc
      libreoffice-fresh
      obsidian
      gimp
      # Media
      mpv
      yt-dlp
      # Browser
      brave
      # Dev tools
      nodejs_22
      python3
      rustup
      go
      # Shell extras
      starship
      atuin        # shell history sync
      tlrc         # tldr pages
      glow         # markdown in terminal
      hexyl
      hyperfine
      # Wayland extras
      wl-clipboard
    ];
  };

  # ── Allow unfree in home-manager ─────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # ── XDG dirs ─────────────────────────────────────────────────────────────────
  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };

  programs.home-manager.enable = true;
}
