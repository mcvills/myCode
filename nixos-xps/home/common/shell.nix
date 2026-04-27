{pkgs, ...}: {
  # ── Fish shell ───────────────────────────────────────────────────────────────
  programs.fish = {
    enable = true;
    shellAliases = {
      # Modern CLI replacements
      ls    = "eza --icons --group-directories-first";
      ll    = "eza -l --icons --group-directories-first --git";
      la    = "eza -la --icons --group-directories-first --git";
      lt    = "eza --tree --icons --level=2";
      cat   = "bat";
      grep  = "rg";
      find  = "fd";
      cd    = "z";
      top   = "btop";
      # Nix shortcuts
      nrs   = "nh os switch --hostname xps9500 /etc/nixos";
      nrb   = "nh os boot --hostname xps9500 /etc/nixos";
      nfu   = "nix flake update /etc/nixos";
      ngc   = "nix-collect-garbage -d";
      nsearch = "nix search nixpkgs";
      # Git
      gs    = "git status";
      ga    = "git add";
      gc    = "git commit";
      gp    = "git push";
      gl    = "git log --oneline --graph --decorate";
      # System
      ff    = "fastfetch";
      sysinfo = "fastfetch";
    };
    interactiveShellInit = ''
      # Zoxide init
      zoxide init fish | source
      # Atuin (better shell history)
      atuin init fish | source
      # Fastfetch on new terminal (suppress in sub-shells)
      if status is-login
        fastfetch
      end
      # Suppress greeting
      set -g fish_greeting ""
    '';
    functions = {
      # Quick nix shell
      ns = {
        body = "nix shell nixpkgs#$argv[1]";
        description = "Quickly enter a nix shell with a package";
      };
      # GPU-offloaded run
      gpu = {
        body = "nvidia-offload $argv";
        description = "Run with NVIDIA GPU";
      };
    };
  };

  # ── Starship prompt ──────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    settings = {
      format = ''
[╭─](bold #cba6f7)$username$hostname$directory$git_branch$git_status$nix_shell$python$nodejs$rust$golang
[╰─](bold #cba6f7)$character'';
      character = {
        success_symbol = "[❯](bold #a6e3a1)";
        error_symbol   = "[❯](bold #f38ba8)";
      };
      username = {
        style_user = "bold #89b4fa";
        style_root = "bold #f38ba8";
        format = "[$user]($style) ";
        show_always = false;
      };
      hostname = {
        style = "bold #fab387";
        format = "[@$hostname]($style) ";
        ssh_only = true;
      };
      directory = {
        style = "bold #cba6f7";
        truncation_length = 4;
        truncate_to_repo = true;
      };
      git_branch = {
        symbol = " ";
        style = "bold #f38ba8";
      };
      git_status = {
        style = "bold #f9e2af";
      };
      nix_shell = {
        symbol = "󱄅 ";
        style = "bold #89dceb";
        format = "[$symbol$state]($style) ";
      };
    };
  };

  # ── Atuin (shell history) ────────────────────────────────────────────────────
  programs.atuin = {
    enable = true;
    flags = ["--disable-up-arrow"];
    settings = {
      auto_sync = false;
      update_check = false;
      style = "compact";
    };
  };

  # ── Zoxide ───────────────────────────────────────────────────────────────────
  programs.zoxide.enable = true;

  # ── Direnv ───────────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── Bat ──────────────────────────────────────────────────────────────────────
  programs.bat = {
    enable = true;
    config = {
      theme = "Catppuccin Mocha";
      style = "numbers,changes,header";
    };
    themes = {
      "Catppuccin Mocha" = {
        src = pkgs.fetchFromGitHub {
          owner = "catppuccin";
          repo = "bat";
          rev = "d714cc1d358ea51bfc02550dabab693f70cccea0";
          sha256 = "sha256-Q5B4NDrfCIK3UAMs94vdXnR42k4AXCqZz6sRn8bzmf4=";
        };
        file = "themes/Catppuccin Mocha.tmTheme";
      };
    };
  };

  # ── FZF ──────────────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    colors = {
      "bg+"    = "#313244";
      "bg"     = "#1e1e2e";
      "spinner"= "#f5e0dc";
      "hl"     = "#f38ba8";
      "fg"     = "#cdd6f4";
      "header" = "#f38ba8";
      "info"   = "#cba6f7";
      "pointer"= "#f5e0dc";
      "marker" = "#f5e0dc";
      "fg+"    = "#cdd6f4";
      "prompt" = "#cba6f7";
      "hl+"    = "#f38ba8";
    };
  };
}
