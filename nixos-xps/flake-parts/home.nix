{
  flake,
  inputs,
  ...
}: {
  # Standalone home-manager configurations (useful for non-NixOS or CI)
  flake.homeConfigurations = {
    "nixuser@xps9500" = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      extraSpecialArgs = {inherit inputs flake;};
      modules = [../home/default.nix];
    };
  };
}
