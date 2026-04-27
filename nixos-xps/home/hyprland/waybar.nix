{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = [{
      layer = "top";
      position = "top";
      height = 36;
      spacing = 4;
      margin-top = 6;
      margin-left = 10;
      margin-right = 10;

      modules-left = ["hyprland/workspaces" "hyprland/window"];
      modules-center = ["clock"];
      modules-right = [
        "pulseaudio"
        "backlight"
        "battery"
        "network"
        "bluetooth"
        "cpu"
        "memory"
        "tray"
      ];

      "hyprland/workspaces" = {
        format = "{icon}";
        format-icons = {
          "1" = "󰲡";
          "2" = "󰲣";
          "3" = "󰲥";
          "4" = "󰲧";
          "5" = "󰲩";
          default = "󰊠";
          active = "󰮯";
          urgent = "󰀨";
        };
        on-scroll-up = "hyprctl dispatch workspace e+1";
        on-scroll-down = "hyprctl dispatch workspace e-1";
        smooth-scrolling-threshold = 4;
      };

      "hyprland/window" = {
        max-length = 40;
        separate-outputs = true;
      };

      clock = {
        format = "  {:%H:%M}";
        format-alt = "  {:%A, %B %d, %Y}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };

      battery = {
        states = {good = 80; warning = 30; critical = 15;};
        format = "{icon}  {capacity}%";
        format-charging = "󰂄  {capacity}%";
        format-plugged = "󰚥  {capacity}%";
        format-icons = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
      };

      network = {
        format-wifi = "󰖩  {essid}";
        format-ethernet = "󰈀  {ipaddr}";
        format-disconnected = "󰖪  No Network";
        tooltip-format = "{ifname}: {ipaddr}/{cidr} via {gwaddr}";
        on-click = "nm-connection-editor";
      };

      pulseaudio = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟";
        format-icons = {default = ["󰕿" "󰖀" "󰕾"];};
        on-click = "pavucontrol";
      };

      backlight = {
        format = "{icon}  {percent}%";
        format-icons = ["󰃞" "󰃟" "󰃠"];
      };

      bluetooth = {
        format = "󰂯  {status}";
        format-connected = "󰂱  {device_alias}";
        format-connected-battery = "󰂱  {device_alias} {device_battery_percentage}%";
        on-click = "blueman-manager";
      };

      cpu = {
        format = "  {usage}%";
        interval = 2;
        on-click = "ghostty -e btop";
      };

      memory = {
        format = "  {}%";
        on-click = "ghostty -e btop";
      };

      tray = {spacing = 10;};
    }];

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free";
        font-size: 13px;
        min-height: 0;
      }
      window#waybar {
        background: rgba(30, 30, 46, 0.85);
        border-radius: 14px;
        border: 2px solid rgba(203, 166, 247, 0.3);
        color: #cdd6f4;
      }
      .modules-left, .modules-right, .modules-center {
        padding: 0 8px;
      }
      #workspaces button {
        padding: 0 8px;
        color: #6c7086;
        border-radius: 8px;
        transition: all 0.2s;
      }
      #workspaces button.active {
        color: #cba6f7;
        background: rgba(203, 166, 247, 0.15);
      }
      #workspaces button:hover {
        color: #89b4fa;
        background: rgba(137, 180, 250, 0.1);
      }
      #clock { color: #89b4fa; font-weight: bold; }
      #battery.charging { color: #a6e3a1; }
      #battery.warning:not(.charging) { color: #f9e2af; }
      #battery.critical:not(.charging) { color: #f38ba8; animation: blink 0.5s steps(12) infinite; }
      @keyframes blink { to { opacity: 0; } }
      #network.disconnected { color: #f38ba8; }
      #cpu { color: #fab387; }
      #memory { color: #a6e3a1; }
      tooltip {
        background: rgba(30, 30, 46, 0.95);
        border: 1px solid rgba(203, 166, 247, 0.4);
        border-radius: 10px;
      }
    '';
  };
}
