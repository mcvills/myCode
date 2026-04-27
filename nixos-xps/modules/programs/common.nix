{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ── CLI essentials ───────────────────────────────────────────────────────
    git
    curl
    wget
    ripgrep
    fd
    bat
    eza          # modern ls
    fzf
    jq
    yq
    zoxide
    htop
    btop
    fastfetch    # system info (replaces neofetch)
    tree
    unzip
    zip
    p7zip
    rsync
    file
    which
    man-pages
    man-pages-posix

    # ── Disk / filesystem ────────────────────────────────────────────────────
    btrfs-progs
    compsize    # BTRFS compression ratio
    duf
    dust
    ncdu

    # ── Network ─────────────────────────────────────────────────────────────
    nmap
    dig
    traceroute
    netcat-openbsd

    # ── Nix tooling ─────────────────────────────────────────────────────────
    nix-output-monitor
    nvd
    nh             # nix helper (rebuild with diff)
    nix-tree
    alejandra      # formatter

    # ── GUI apps (system-level) ──────────────────────────────────────────────
    keepassxc
    libreoffice-fresh
    gimp
    mpv
    obsidian
    brave

    # ── Flatpak (for Cursor IDE which has no Nix pkg yet) ────────────────────
    flatpak
  ];

  # ── Snapper ─────────────────────────────────────────────────────────────────
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    configs = {
      root = {
        SUBVOLUME = "/";
        ALLOW_USERS = ["nixuser"];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "10";
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_WEEKLY = "4";
        TIMELINE_LIMIT_MONTHLY = "3";
        TIMELINE_LIMIT_YEARLY = "1";
      };
      home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = ["nixuser"];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "10";
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_WEEKLY = "4";
        TIMELINE_LIMIT_MONTHLY = "6";
        TIMELINE_LIMIT_YEARLY = "2";
      };
    };
  };

  # ── Flatpak (for Cursor IDE) ─────────────────────────────────────────────────
  services.flatpak.enable = true;

  # ── AppImage support ─────────────────────────────────────────────────────────
  boot.binfmt.registrations.appimage = {
    wrapInterpreterInShell = false;
    interpreter = "${pkgs.appimage-run}/bin/appimage-run";
    recognitionType = "magic";
    offset = 0;
    mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
    magicOrExtension = ''\x7fELF....AI\x02'';
  };
}
