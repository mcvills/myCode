{
  flake,
  inputs,
  ...
}: {
  flake.nixosConfigurations = {
    # ── Dell XPS 9500 (bare-metal / VM) ───────────────────────────────────────
    xps9500 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs flake;};
      modules = [
        # ── Hardware ──────────────────────────────────────────────────────────
        inputs.nixos-hardware.nixosModules.dell-xps-15-9500
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence

        # ── Host-specific ─────────────────────────────────────────────────────
        ../hosts/xps9500/default.nix

        # ── System modules ────────────────────────────────────────────────────
        ../modules/system/boot.nix
        ../modules/system/kernel.nix
        ../modules/system/locale.nix
        ../modules/system/networking.nix
        ../modules/system/security.nix
        ../modules/system/services.nix
        ../modules/system/fonts.nix
        ../modules/system/nix.nix
        ../modules/system/users.nix

        # ── Hardware modules ──────────────────────────────────────────────────
        ../modules/hardware/nvidia.nix
        ../modules/hardware/audio.nix
        ../modules/hardware/power.nix
        ../modules/hardware/bluetooth.nix

        # ── Desktop modules ───────────────────────────────────────────────────
        ../modules/desktop/hyprland.nix
        ../modules/desktop/gnome.nix
        ../modules/desktop/display-manager.nix
        ../modules/desktop/portals.nix

        # ── Programs ──────────────────────────────────────────────────────────
        ../modules/programs/common.nix

        # ── Home Manager (system-level integration) ───────────────────────────
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {inherit inputs flake;};
            users.nixuser = import ../home/default.nix;
          };
        }

        # ── Stylix theming ────────────────────────────────────────────────────
        inputs.stylix.nixosModules.stylix
      ];
    };
  };
}
