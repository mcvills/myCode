{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      name = "nixos-xps-devshell";
      packages = with pkgs; [
        git
        nil          # Nix LSP
        alejandra    # Nix formatter
        statix       # Nix linter
        deadnix      # Dead-code finder
        nixd         # Nix language server (alternative)
        nvd          # Nix diff
        nix-tree     # Dependency visualiser
        disko        # Disk partitioning
        age          # Encryption for secrets
        sops         # Secret management
      ];
      shellHook = ''
        echo "🔥 NixOS XPS 9500 dev-shell ready"
        echo "   Format  : alejandra ."
        echo "   Lint    : statix check ."
        echo "   Build   : nixos-rebuild build --flake .#xps9500"
      '';
    };
  };
}
