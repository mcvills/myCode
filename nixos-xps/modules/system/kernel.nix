{
  pkgs,
  lib,
  ...
}: {
  # ── Kernel ──────────────────────────────────────────────────────────────────
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Kernel sysctl tweaks ────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # Network
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    # Virtual memory
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    # File watches (for apps like VS Code / Cursor)
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  # ── Zram swap (fast compressed RAM swap) ────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };
}
