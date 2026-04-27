{...}: {
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
      warn-dirty = false;

      # ── Binary caches ─────────────────────────────────────────────────────
      substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeCw="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxRDkznGAi2n8HrMjY1OI="
      ];

      # ── Build performance ─────────────────────────────────────────────────
      max-jobs = "auto";
      cores = 0;
    };

    # Pin nixpkgs in registry for nix run consistency
    registry.nixpkgs.flake = builtins.getFlake "github:NixOS/nixpkgs/nixos-unstable";
    nixPath = ["nixpkgs=flake:nixpkgs"];
  };

  # Allow unfree packages (NVIDIA, Obsidian, etc.)
  nixpkgs.config.allowUnfree = true;
}
