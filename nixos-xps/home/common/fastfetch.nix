{...}: {
  xdg.configFile."fastfetch/config.jsonc".text = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      "logo": {
        "type": "builtin",
        "source": "NixOS",
        "color": {
          "1": "blue",
          "2": "cyan"
        }
      },
      "display": {
        "separator": "  ",
        "color": {
          "keys": "cyan",
          "title": "blue"
        }
      },
      "modules": [
        {
          "type": "title",
          "color": {
            "user": "blue",
            "at": "white",
            "host": "cyan"
          }
        },
        "separator",
        {
          "type": "os",
          "key": "  OS",
          "keyColor": "blue"
        },
        {
          "type": "kernel",
          "key": "  Kernel",
          "keyColor": "cyan"
        },
        {
          "type": "uptime",
          "key": "  Uptime",
          "keyColor": "blue"
        },
        {
          "type": "packages",
          "key": "  Pkgs",
          "keyColor": "cyan"
        },
        {
          "type": "shell",
          "key": "  Shell",
          "keyColor": "blue"
        },
        {
          "type": "display",
          "key": "  Display",
          "keyColor": "cyan"
        },
        {
          "type": "de",
          "key": "  DE/WM",
          "keyColor": "blue"
        },
        {
          "type": "theme",
          "key": "  Theme",
          "keyColor": "cyan"
        },
        {
          "type": "terminal",
          "key": "  Terminal",
          "keyColor": "blue"
        },
        {
          "type": "cpu",
          "key": "  CPU",
          "keyColor": "cyan"
        },
        {
          "type": "gpu",
          "key": "  GPU",
          "keyColor": "blue"
        },
        {
          "type": "memory",
          "key": "  RAM",
          "keyColor": "cyan"
        },
        {
          "type": "disk",
          "key": "  Disk",
          "keyColor": "blue"
        },
        {
          "type": "battery",
          "key": "  Battery",
          "keyColor": "cyan"
        },
        "separator",
        {
          "type": "colors",
          "paddingLeft": 2,
          "symbol": "circle"
        }
      ]
    }
  '';
}
