{
  inputs,
  pkgs,
  ...
}: {
  home.packages = [inputs.ghostty.packages.${pkgs.system}.default];

  xdg.configFile."ghostty/config".text = ''
    # ── Catppuccin Mocha ──────────────────────────────────────────────────────
    background = 1e1e2e
    foreground = cdd6f4
    cursor-color = f5e0dc
    selection-background = 313244
    selection-foreground = cdd6f4

    palette = 0=#45475a
    palette = 1=#f38ba8
    palette = 2=#a6e3a1
    palette = 3=#f9e2af
    palette = 4=#89b4fa
    palette = 5=#f5c2e7
    palette = 6=#94e2d5
    palette = 7=#bac2de
    palette = 8=#585b70
    palette = 9=#f38ba8
    palette = 10=#a6e3a1
    palette = 11=#f9e2af
    palette = 12=#89b4fa
    palette = 13=#f5c2e7
    palette = 14=#94e2d5
    palette = 15=#a6adc8

    # ── Font ──────────────────────────────────────────────────────────────────
    font-family = JetBrainsMono Nerd Font
    font-size = 13
    font-thicken = true

    # ── Window ────────────────────────────────────────────────────────────────
    window-decoration = false
    window-padding-x = 12
    window-padding-y = 10
    background-opacity = 0.92
    background-blur-radius = 20

    # ── Cursor ────────────────────────────────────────────────────────────────
    cursor-style = block
    cursor-style-blink = true

    # ── Scrollback ────────────────────────────────────────────────────────────
    scrollback-limit = 10000

    # ── Shell ─────────────────────────────────────────────────────────────────
    command = /run/current-system/sw/bin/fish

    # ── Keybindings ───────────────────────────────────────────────────────────
    keybind = ctrl+shift+c=copy_to_clipboard
    keybind = ctrl+shift+v=paste_from_clipboard
    keybind = ctrl+shift+n=new_window
    keybind = ctrl+shift+t=new_tab
    keybind = ctrl+shift+w=close_surface
    keybind = ctrl+equal=increase_font_size:1
    keybind = ctrl+minus=decrease_font_size:1
    keybind = ctrl+zero=reset_font_size

    # ── Misc ──────────────────────────────────────────────────────────────────
    confirm-close-surface = false
    mouse-hide-while-typing = true
    clipboard-read = allow
    clipboard-write = allow
  '';
}
