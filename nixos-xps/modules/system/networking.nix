# networking.nix
{pkgs, ...}: {
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [];
      allowedUDPPorts = [];
    };
  };
  # WiFi regulatory domain
  hardware.wirelessRegulatoryDatabase = true;
}
