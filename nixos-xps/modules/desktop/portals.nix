{
  inputs,
  pkgs,
  ...
}: {
  xdg.portal = {
    enable = true;
    extraPortals = [
      inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = ["gtk"];
      hyprland.default = ["hyprland" "gtk"];
    };
  };
}
