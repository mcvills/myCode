{
  description = "NixOS config for Dell XPS 9500 — modular, reproducible, NVIDIA-ready";

  inputs = {
    # ── Core ──────────────────────────────────────────────────────────────────
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # tracking 25.11-ish

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # ── Flake-parts (modular composition) ─────────────────────────────────────
    flake-parts.url = "github:hercules-ci/flake-parts";

    # ── Home Manager ──────────────────────────────────────────────────────────
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Hyprland ──────────────────────────────────────────────────────────────
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    # ── Stylix (system-wide theming) ──────────────────────────────────────────
    stylix.url = "github:danth/stylix";

    # ── Nix-colors (base16 palette helper) ────────────────────────────────────
    nix-colors.url = "github:misterio77/nix-colors";

    # ── Impermanence (opt-in state) ───────────────────────────────────────────
    impermanence.url = "github:nix-community/impermanence";

    # ── Disko (declarative disk partitioning) ─────────────────────────────────
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Neovim / nixvim ───────────────────────────────────────────────────────
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Ghostty terminal ──────────────────────────────────────────────────────
    ghostty.url = "github:ghostty-org/ghostty";

    # ── Nur (community packages) ──────────────────────────────────────────────
    nur.url = "github:nix-community/NUR";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      imports = [
        ./flake-parts/nixos.nix
        ./flake-parts/home.nix
        ./flake-parts/devshell.nix
      ];
    };
}
