# Hyprland home-manager configuration
# Catppuccin Mocha palette
{
  inputs,
  pkgs,
  ...
}: let
  # ── Catppuccin Mocha ───────────────────────────────────────────────────────
  rosewater = "f5e0dc";
  flamingo  = "f2cdcd";
  pink      = "f38ba8";
  mauve     = "cba6f7";
  red       = "f38ba8";
  maroon    = "eba0ac";
  peach     = "fab387";
  yellow    = "f9e2af";
  green     = "a6e3a1";
  teal      = "94e2d5";
  sky       = "89dceb";
  sapphire  = "74c7ec";
  blue      = "89b4fa";
  lavender  = "b4befe";
  text      = "cdd6f4";
  subtext1  = "bac2de";
  subtext0  = "a6adc8";
  overlay2  = "9399b2";
  overlay1  = "7f849c";
  overlay0  = "6c7086";
  surface2  = "585b70";
  surface1  = "45475a";
  surface0  = "313244";
  base      = "1e1e2e";
  mantle    = "181825";
  crust     = "11111b";
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = true;
    systemd.enable = true;

    settings = {
      # ── Monitor ────────────────────────────────────────────────────────────
      monitor = [
        "eDP-1, 1920x1200@60, 0x0, 1.25"  # XPS 9500 internal 4K panel scaled
        ", preferred, auto, 1"             # external monitors auto-detect
      ];

      # ── Startup ────────────────────────────────────────────────────────────
      exec-once = [
        "swww-daemon"
        "swww img ~/.config/hypr/wallpaper.jpg --transition-type wipe --transition-angle 30"
        "waybar"
        "dunst"
        "cliphist"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "/run/current-system/sw/libexec/polkit-gnome-authentication-agent-1"
        "nm-applet --indicator"
        "swayidle -w timeout 300 'swaylock -f' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on'"
      ];

      # ── General ────────────────────────────────────────────────────────────
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(${mauve}ff) rgba(${blue}ff) 45deg";
        "col.inactive_border" = "rgba(${surface1}aa)";
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      # ── Decoration ─────────────────────────────────────────────────────────
      decoration = {
        rounding = 12;
        active_opacity = 1.0;
        inactive_opacity = 0.92;
        fullscreen_opacity = 1.0;
        drop_shadow = true;
        shadow_range = 20;
        shadow_render_power = 3;
        "col.shadow" = "rgba(${crust}ee)";
        blur = {
          enabled = true;
          size = 8;
          passes = 3;
          new_optimizations = true;
          xray = false;
          noise = 0.0117;
          contrast = 0.8916;
          brightness = 0.8172;
          vibrancy = 0.1696;
          popups = true;
        };
      };

      # ── Animations ─────────────────────────────────────────────────────────
      animations = {
        enabled = true;
        bezier = [
          "wind, 0.05, 0.9, 0.1, 1.05"
          "winIn, 0.1, 1.1, 0.1, 1.1"
          "winOut, 0.3, -0.3, 0, 1"
          "liner, 1, 1, 1, 1"
          "md3_standard, 0.2, 0, 0, 1"
          "md3_decel, 0.05, 0.7, 0.1, 1"
          "md3_accel, 0.3, 0, 0.8, 0.15"
          "overshot, 0.05, 0.9, 0.1, 1.1"
          "hyprnostretch, 0.05, 0.9, 0.1, 1.0"
        ];
        animation = [
          "windows, 1, 6, wind, slide"
          "windowsIn, 1, 6, winIn, slide"
          "windowsOut, 1, 5, winOut, slide"
          "windowsMove, 1, 5, wind, slide"
          "border, 1, 1, liner"
          "borderangle, 1, 30, liner, loop"
          "fade, 1, 10, md3_decel"
          "fadeOut, 1, 10, md3_accel"
          "workspaces, 1, 5, overshot, slide"
          "specialWorkspace, 1, 8, md3_decel, slidevert"
        ];
      };

      # ── Input ──────────────────────────────────────────────────────────────
      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
          clickfinger_behavior = true;
          scroll_factor = 0.8;
        };
      };

      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
        workspace_swipe_distance = 300;
        workspace_swipe_invert = true;
        workspace_swipe_min_speed_to_force = 30;
        workspace_swipe_cancel_ratio = 0.5;
        workspace_swipe_create_new = true;
        workspace_swipe_direction_lock = true;
      };

      # ── Layout ─────────────────────────────────────────────────────────────
      dwindle = {
        pseudotile = true;
        preserve_split = true;
        smart_split = true;
      };

      master = {
        new_status = "master";
        mfact = 0.5;
      };

      # ── Misc ───────────────────────────────────────────────────────────────
      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        vfr = true;         # variable frame rate — saves power
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
        animate_manual_resizes = true;
        animate_mouse_windowdragging = true;
      };

      # ── Window rules ───────────────────────────────────────────────────────
      windowrulev2 = [
        # Floating windows
        "float, class:^(pavucontrol)$"
        "float, class:^(blueman-manager)$"
        "float, class:^(nm-connection-editor)$"
        "float, class:^(keepassxc)$, title:^(.*KeePassXC)$"
        "float, class:^(swappy)$"
        "float, title:^(Picture-in-Picture)$"
        "pin, title:^(Picture-in-Picture)$"
        # Center floating
        "center, class:^(pavucontrol)$"
        "center, class:^(blueman-manager)$"
        # Opacity
        "opacity 0.92 0.85, class:^(ghostty)$"
        # NVIDIA / tearing fix
        "immediate, class:^(steam_app_)(.*)$"
        # Obsidian
        "tile, class:^(obsidian)$"
        # KeePassXC password entry
        "stayfocused, title:^(.*KeePassXC.*Auto-Type.*)$"
      ];

      # ── Keybindings ────────────────────────────────────────────────────────
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$fileManager" = "nautilus";
      "$launcher" = "rofi -show drun";
      "$browser" = "brave";
      "$editor" = "nvim";

      bind = [
        # Core
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod SHIFT, Q, exit"
        "$mod, E, exec, $fileManager"
        "$mod, Space, exec, $launcher"
        "$mod, B, exec, $browser"
        "$mod, F, fullscreen"
        "$mod, T, togglefloating"
        "$mod, P, pseudo"
        "$mod, J, togglesplit"
        # Focus movement
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod SHIFT, J, movefocus, d"
        # Window movement
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, L, movewindow, r"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, J, movewindow, d"
        # Workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
        # Special workspace (scratchpad)
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"
        # Scroll workspaces
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
        # Screenshot
        ", Print, exec, grimblast copy area"
        "$mod, Print, exec, grimblast save area ~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png"
        # Clipboard history
        "$mod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        # Lock
        "$mod, Escape, exec, swaylock"
        # Colour picker
        "$mod SHIFT, C, exec, hyprpicker -a"
        # OSD
        "$mod, M, exec, pavucontrol"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
      ];

      bindl = [
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
        ", switch:on:Lid Switch, exec, swaylock -f"
      ];
    };
  };
}
