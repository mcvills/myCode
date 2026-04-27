#!/usr/bin/env bash
#===============================================================================
# NixOS Flake Installer V2 - Dell XPS 9500 / VM + Ventoy-aware
# BTRFS + Snapper + Hyprland + GNOME fallback + NVIDIA profile
# Run from the official NixOS installer ISO/live environment.
#===============================================================================
set -Eeuo pipefail

#------------------------------- USER VARIABLES --------------------------------
HOSTNAME="${HOSTNAME:-xps9500}"
USERNAME="${USERNAME:-dana}"
FULL_NAME="${FULL_NAME:-Dana}"
TIMEZONE="${TIMEZONE:-America/New_York}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"

TARGET_DISK="${TARGET_DISK:-/dev/nvme0n1}"   # VM examples: /dev/vda, /dev/sda
PROFILE="${PROFILE:-auto}"                   # auto, xps9500, or vm
NIXPKGS_BRANCH="${NIXPKGS_BRANCH:-nixos-25.11}"
WIPE_DISK="${WIPE_DISK:-false}"              # must be true to continue
INITIAL_PASSWORD="${INITIAL_PASSWORD:-changeme}"

# Ventoy / live ISO helper settings
VENTOY_MOUNT="${VENTOY_MOUNT:-/mnt/scripts}"
AUTO_MOUNT_VENTOY="${AUTO_MOUNT_VENTOY:-true}"
LOCAL_WORKDIR="${LOCAL_WORKDIR:-/root/nixos-installer-v3}"
CONSOLE_FONT="${CONSOLE_FONT:-ter-v36n}"
LOG_FILE="${LOG_FILE:-/tmp/nixos-xps9500-installer-v3.log}"
LIVE_DEPS=(bash coreutils util-linux findutils gnugrep gawk gnused gptfdisk parted dosfstools btrfs-progs exfatprogs ntfs3g pciutils usbutils iproute2 curl wget git unzip zip jq)

C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[0;36m'; C_MAG='\033[0;35m'; C_BOLD='\033[1m'
info(){ echo -e "${C_CYAN}INFO${C_RESET}  $*"; }
success(){ echo -e "${C_GREEN}OK${C_RESET}    $*"; }
warn(){ echo -e "${C_YELLOW}WARN${C_RESET}  $*"; }
fail(){ echo -e "${C_RED}FAIL${C_RESET}  $*"; exit 1; }

banner(){
  clear || true
  echo -e "${C_MAG}${C_BOLD}"
  cat <<'EOF'
 _   _ _      ___  ____    _____ _       _        ___           _        _ _           
| \ | (_)_  _/ _ \/ ___|  |  ___| | __ _| | _____|_ _|_ __  ___| |_ __ _| | | ___ _ __ 
|  \| | \ \/ / | | \___ \  | |_  | |/ _` | |/ / _ \| || '_ \/ __| __/ _` | | |/ _ \ '__|
| |\  | |>  <| |_| |___) | |  _| | | (_| |   <  __/| || | | \__ \ || (_| | | |  __/ |   
|_| \_|_/_/\_\\___/|____/  |_|   |_|\__,_|_|\_\___|___|_| |_|___/\__\__,_|_|_|\___|_|   
EOF
  echo -e "${C_RESET}"
}

need_root(){ [[ $EUID -eq 0 ]] || fail "Run as root from the NixOS live ISO: sudo -i"; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

cmd_exists(){ command -v "" >/dev/null 2>&1; }
set_readable_console(){ loadkeys "$KEYMAP" >/dev/null 2>&1 || true; if cmd_exists setfont; then setfont "$CONSOLE_FONT" >/dev/null 2>&1 && success "Console font set to ${CONSOLE_FONT}." || warn "Could not set console font ${CONSOLE_FONT}; continuing."; fi; }
network_ok(){ ip route get 1.1.1.1 >/dev/null 2>&1 && ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; }
detect_machine_type(){ local virt="none"; if cmd_exists systemd-detect-virt; then virt="$(systemd-detect-virt 2>/dev/null || true)"; fi; if [[ -n "$virt" && "$virt" != "none" ]]; then DETECTED_MACHINE="virtual"; else DETECTED_MACHINE="physical"; fi; success "Machine type detected: ${DETECTED_MACHINE}${virt:+ (${virt})}."; }
detect_profile_auto(){ detect_machine_type; if [[ "${PROFILE}" == "auto" ]]; then if [[ "$DETECTED_MACHINE" == "virtual" ]]; then PROFILE="vm"; else PROFILE="xps9500"; fi; success "PROFILE=auto resolved to PROFILE=${PROFILE}."; fi; }
network_preflight(){ info "Network summary:"; ip -br link || true; ip -br addr || true; if network_ok; then success "Network test passed."; else warn "Network test failed. Try dhcpcd, USB tethering, or Ethernet."; fi; }
preflight(){ set_readable_console; detect_profile_auto; detect_summary; network_preflight; if [[ "$AUTO_MOUNT_VENTOY" == "true" ]]; then mount_ventoy || warn "Ventoy auto-mount failed; manual: mkdir -p ${VENTOY_MOUNT}; mount -t exfat /dev/sdX1 ${VENTOY_MOUNT}"; fi; info "Variables: HOSTNAME=${HOSTNAME} USERNAME=${USERNAME} TARGET_DISK=${TARGET_DISK} PROFILE=${PROFILE} VENTOY_MOUNT=${VENTOY_MOUNT} WIPE_DISK=${WIPE_DISK}"; }
usage(){ cat <<EOF
Usage:
  ./install-nixos-xps9500-v3.sh [option]
  ./install-nixos-xps9500-v3.sh --mount-ventoy
  ./install-nixos-xps9500-v3.sh --copy-self

Install:
  TARGET_DISK=/dev/nvme0n1 PROFILE=xps9500 WIPE_DISK=true ./install-nixos-xps9500-v3.sh
  TARGET_DISK=/dev/vda PROFILE=vm HOSTNAME=nixos-vm WIPE_DISK=true ./install-nixos-xps9500-v3.sh
EOF
}
bootstrap_live_deps(){
  if [[ "${NIXOS_INSTALLER_DEPS_READY:-false}" == "true" ]]; then return 0; fi
  if ! cmd_exists mount.exfat || ! cmd_exists sgdisk || ! cmd_exists mkfs.btrfs || ! cmd_exists unzip; then
    network_ok || fail "Network is required to fetch missing live ISO dependencies. Connect Ethernet/USB tethering and run dhcpcd, then retry."
    info "Bootstrapping live ISO dependencies with nix-shell."
    export NIX_CONFIG="experimental-features = nix-command flakes"
    exec nix-shell -p "${LIVE_DEPS[@]}" --run "NIXOS_INSTALLER_DEPS_READY=true bash '$0' $*"
  fi
}
mount_one_partition(){
  local dev="$1" fstype
  mkdir -p "$VENTOY_MOUNT"
  fstype="$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
  info "Trying ${dev} (${fstype:-unknown}) -> ${VENTOY_MOUNT}."
  case "$fstype" in
    exfat) mount -t exfat -o ro "$dev" "$VENTOY_MOUNT" ;;
    ntfs) mount -t ntfs3 -o ro "$dev" "$VENTOY_MOUNT" 2>/dev/null || mount -t ntfs-3g -o ro "$dev" "$VENTOY_MOUNT" ;;
    vfat) mount -t vfat -o ro "$dev" "$VENTOY_MOUNT" ;;
    *) mount -o ro "$dev" "$VENTOY_MOUNT" ;;
  esac
}
mount_ventoy(){
  if mountpoint -q "$VENTOY_MOUNT"; then success "${VENTOY_MOUNT} is already mounted."; return 0; fi
  info "Searching for Ventoy/script partition."
  lsblk -o NAME,FSTYPE,LABEL,SIZE,MODEL,MOUNTPOINTS || true
  local candidates=()
  for label in Ventoy VENTOY ventoy; do [[ -e "/dev/disk/by-label/$label" ]] && candidates+=("/dev/disk/by-label/$label"); done
  while read -r dev type fstype label rest; do
    [[ "$type" == "part" ]] || continue
    [[ "$dev" == ${TARGET_DISK}* ]] && continue
    [[ "$fstype" =~ ^(exfat|ntfs|vfat|ext4|btrfs)$ ]] && candidates+=("$dev")
  done < <(lsblk -rpno NAME,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS)
  local dev
  for dev in "${candidates[@]}"; do
    if mount_one_partition "$dev"; then
      if find "$VENTOY_MOUNT" -maxdepth 4 \( -name '*.sh' -o -name '*.zip' -o -name 'flake.nix' \) | grep -q .; then
        success "Mounted scripts partition at ${VENTOY_MOUNT}."
        find "$VENTOY_MOUNT" -maxdepth 2 -type f \( -name '*.sh' -o -name '*.zip' -o -name 'README.md' \) -print | sed 's/^/  - /'
        return 0
      fi
      warn "Mounted ${dev}, but no installer files were found. Trying next candidate."
      umount "$VENTOY_MOUNT" || true
    fi
  done
  fail "Could not auto-mount Ventoy. Manually run: mkdir -p ${VENTOY_MOUNT}; mount /dev/sdX2 ${VENTOY_MOUNT}"
}
copy_self_from_ventoy(){
  mount_ventoy
  mkdir -p "$LOCAL_WORKDIR"
  cp -a "$VENTOY_MOUNT"/*nixos* "$LOCAL_WORKDIR/" 2>/dev/null || true
  cp -a "$VENTOY_MOUNT"/*.sh "$LOCAL_WORKDIR/" 2>/dev/null || true
  chmod +x "$LOCAL_WORKDIR"/*.sh 2>/dev/null || true
  success "Copied available installer files to ${LOCAL_WORKDIR}."
  ls -lah "$LOCAL_WORKDIR"
}


confirm_destruction(){
  echo
  warn "This will ERASE and repartition: ${TARGET_DISK}"
  warn "PROFILE=${PROFILE}; HOSTNAME=${HOSTNAME}; USERNAME=${USERNAME}; NIXPKGS=${NIXPKGS_BRANCH}"
  [[ "${WIPE_DISK}" == "true" ]] || fail "Refusing to continue. Re-run with WIPE_DISK=true after verifying TARGET_DISK."
  read -r -p "Type ERASE-${TARGET_DISK} to continue: " ans
  [[ "$ans" == "ERASE-${TARGET_DISK}" ]] || fail "Confirmation did not match. Aborted."
}

detect_summary(){
  info "Detected disks:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,MOUNTPOINTS
  echo
  info "GPU summary:"
  lspci | grep -Ei 'vga|3d|display|nvidia|intel' || true
  echo
  info "Network summary:"
  ip -br addr || true
}

partition_btrfs(){
  info "Unmounting previous /mnt mounts if present."
  swapoff -a || true
  for mp in /mnt/home/*/.snapshots /mnt/.snapshots /mnt/var/cache /mnt/var/log /mnt/nix /mnt/home /mnt/boot /mnt; do
    [[ "" == "" ]] && continue
    umount "" 2>/dev/null || true
  done

  info "Creating GPT: EFI + BTRFS root on ${TARGET_DISK}."
  wipefs -af "$TARGET_DISK"
  sgdisk --zap-all "$TARGET_DISK"
  sgdisk -n1:1MiB:+1GiB -t1:EF00 -c1:EFI "$TARGET_DISK"
  sgdisk -n2:0:0      -t2:8300 -c2:NIXOS-BTRFS "$TARGET_DISK"
  partprobe "$TARGET_DISK"
  sleep 2

  if [[ "$TARGET_DISK" =~ nvme|mmcblk ]]; then
    EFI_PART="${TARGET_DISK}p1"; ROOT_PART="${TARGET_DISK}p2"
  else
    EFI_PART="${TARGET_DISK}1"; ROOT_PART="${TARGET_DISK}2"
  fi

  mkfs.fat -F32 -n EFI "$EFI_PART"
  mkfs.btrfs -f -L nixos "$ROOT_PART"

  mount "$ROOT_PART" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@nix
  btrfs subvolume create /mnt/@log
  btrfs subvolume create /mnt/@cache
  btrfs subvolume create /mnt/@snapshots
  btrfs subvolume create /mnt/@home-snapshots
  umount /mnt

  local opts="noatime,compress=zstd:3,ssd,discard=async,space_cache=v2"
  mount -o "${opts},subvol=@" "$ROOT_PART" /mnt
  mkdir -p /mnt/{boot,home,nix,var/log,var/cache,.snapshots}
  mount -o "${opts},subvol=@home" "$ROOT_PART" /mnt/home
  mount -o "${opts},subvol=@nix" "$ROOT_PART" /mnt/nix
  mount -o "${opts},subvol=@log" "$ROOT_PART" /mnt/var/log
  mount -o "${opts},subvol=@cache" "$ROOT_PART" /mnt/var/cache
  mount -o "${opts},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
  mkdir -p "/mnt/home/${USERNAME}/.snapshots"
  mount -o "${opts},subvol=@home-snapshots" "$ROOT_PART" "/mnt/home/${USERNAME}/.snapshots"
  mount "$EFI_PART" /mnt/boot
}

write_flake(){
  info "Writing modular flake to /mnt/etc/nixos."
  mkdir -p /mnt/etc/nixos/{hosts/${HOSTNAME},modules/{desktop,hardware,system,users},home/${USERNAME}}
  nixos-generate-config --root /mnt
  cp /mnt/etc/nixos/hardware-configuration.nix "/mnt/etc/nixos/hosts/${HOSTNAME}/hardware-configuration.nix"

cat > /mnt/etc/nixos/flake.nix <<EOF
{
  description = "Modern NixOS flake for Dell XPS 9500 / VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/${NIXPKGS_BRANCH}";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.url = "github:hyprwm/Hyprland";
  };

  outputs = { self, nixpkgs, home-manager, hyprland, ... }@inputs:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
  in {
    nixosConfigurations.${HOSTNAME} = lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; username = "${USERNAME}"; hostname = "${HOSTNAME}"; profile = "${PROFILE}"; };
      modules = [
        ./hosts/${HOSTNAME}/configuration.nix
        home-manager.nixosModules.home-manager
        hyprland.nixosModules.default
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${USERNAME} = import ./home/${USERNAME}/home.nix;
          home-manager.extraSpecialArgs = { inherit inputs; username = "${USERNAME}"; };
        }
      ];
    };
  };
}
EOF

cat > "/mnt/etc/nixos/hosts/${HOSTNAME}/configuration.nix" <<EOF
{ config, pkgs, lib, inputs, username, hostname, profile, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/system/base.nix
    ../../modules/system/btrfs-snapper.nix
    ../../modules/users/${USERNAME}.nix
    ../../modules/desktop/gnome.nix
    ../../modules/desktop/hyprland.nix
  ] ++ lib.optionals (profile == "xps9500") [
    ../../modules/hardware/xps9500-nvidia.nix
  ] ++ lib.optionals (profile == "vm") [
    ../../modules/hardware/vm.nix
  ];

  networking.hostName = hostname;
  system.stateVersion = "25.11";
}
EOF

cat > /mnt/etc/nixos/modules/system/base.nix <<EOF
{ config, pkgs, lib, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 14d"; };
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "${TIMEZONE}";
  i18n.defaultLocale = "${LOCALE}";
  console.keyMap = "${KEYMAP}";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkks.linuxPackages_latest;

  networking.networkmanager.enable = true;
  services.fwupd.enable = true;
  services.printing.enable = true;
  services.flatpak.enable = true;
  security.polkit.enable = true;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono nerd-fonts.fira-code nerd-fonts.hack
    noto-fonts noto-fonts-cjk-sans noto-fonts-emoji
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };

  programs.zsh.enable = true;
  programs.nix-ld.enable = true;
  programs.dconf.enable = true;

  environment.systemPackages = with pkgs; [
    git curl wget unzip zip p7zip rsync jq yq tree htop btop fastfetch
    pciutils usbutils lshw parted gptfdisk btrfs-progs snapper exfatprogs ntfs3g
    vim neovim nil nixfmt-rfc-style alejandra statix deadnix
    ghostty keepassxc libreoffice-qt obsidian gimp brave mpv
    wl-clipboard cliphist grim slurp swappy waybar rofi-wayland mako swww
    networkmanagerapplet blueman brightnessctl playerctl pavucontrol
  ] ++ lib.optionals (builtins.hasAttr "code-cursor" pkgs) [ pkgs.code-cursor ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk xdg-desktop-portal-hyprland ];
  };
}
EOF
  sed -i 's/pkks/pkgs/g' /mnt/etc/nixos/modules/system/base.nix

cat > /mnt/etc/nixos/modules/system/btrfs-snapper.nix <<EOF
{ config, pkgs, lib, ... }:
{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  services.snapper = {
    snapshotRootOnBoot = true;
    configs = {
      root = {
        SUBVOLUME = "/";
        ALLOW_USERS = [ "${USERNAME}" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        NUMBER_CLEANUP = true;
        NUMBER_LIMIT = 20;
        TIMELINE_LIMIT_HOURLY = 10;
        TIMELINE_LIMIT_DAILY = 10;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 1;
      };
      home = {
        SUBVOLUME = "/home/${USERNAME}";
        ALLOW_USERS = [ "${USERNAME}" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        NUMBER_CLEANUP = true;
        NUMBER_LIMIT = 20;
        TIMELINE_LIMIT_HOURLY = 10;
        TIMELINE_LIMIT_DAILY = 10;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /.snapshots 0755 root root -"
    "d /home/${USERNAME}/.snapshots 0755 ${USERNAME} users -"
  ];
}
EOF

cat > "/mnt/etc/nixos/modules/users/${USERNAME}.nix" <<EOF
{ config, pkgs, ... }:
{
  users.users.${USERNAME} = {
    isNormalUser = true;
    description = "${FULL_NAME}";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "lp" "scanner" ];
    shell = pkgs.zsh;
    initialPassword = "${INITIAL_PASSWORD}";
  };
}
EOF

cat > /mnt/etc/nixos/modules/desktop/gnome.nix <<'EOF'
{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.excludePackages = with pkgs; [ xterm ];
  environment.gnome.excludePackages = with pkgs; [ gnome-tour epiphany geary ];
}
EOF

cat > /mnt/etc/nixos/modules/desktop/hyprland.nix <<'EOF'
{ pkgs, inputs, ... }:
{
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    xwayland.enable = true;
  };
}
EOF

cat > /mnt/etc/nixos/modules/hardware/xps9500-nvidia.nix <<'EOF'
{ config, pkgs, lib, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  services.thermald.enable = true;
  services.power-profiles-daemon.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
}
EOF

cat > /mnt/etc/nixos/modules/hardware/vm.nix <<'EOF'
{ pkgs, ... }:
{
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  hardware.graphics.enable = true;
}
EOF

cat > "/mnt/etc/nixos/home/${USERNAME}/home.nix" <<EOF
{ config, pkgs, username, ... }:
{
  home.username = username;
  home.homeDirectory = "/home/" + username;
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "${FULL_NAME}";
    userEmail = "${USERNAME}@localhost";
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ll = "ls -lah --color=auto";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#${HOSTNAME}";
      testbuild = "sudo nixos-rebuild test --flake /etc/nixos#${HOSTNAME}";
      nup = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#${HOSTNAME}";
      snaps = "snapper list && snapper -c home list";
    };
    initContent = ''
      fastfetch 2>/dev/null || true
      PROMPT='%F{cyan}%n%f@%F{magenta}%m%f:%F{green}%~%f %# '
    '';
  };

  programs.starship.enable = true;

  programs.ghostty = {
    enable = true;
    settings = {
      theme = "catppuccin-mocha";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
      window-padding-x = 8;
      window-padding-y = 8;
      background-opacity = 0.94;
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraPackages = with pkgs; [ ripgrep fd gcc gnumake nodejs python3 lua-language-server pyright bash-language-server yaml-language-server nil nixfmt-rfc-style ];
  };

  xdg.configFile."nvim/init.lua".text = ''
    vim.g.mapleader = " "
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.termguicolors = true
    vim.opt.expandtab = true
    vim.opt.shiftwidth = 2
    vim.opt.tabstop = 2
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
      vim.fn.system({"git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath})
    end
    vim.opt.rtp:prepend(lazypath)
    require("lazy").setup({
      { "catppuccin/nvim", name = "catppuccin", priority = 1000, config = function() vim.cmd.colorscheme("catppuccin-mocha") end },
      { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
      { "nvim-lualine/lualine.nvim", config = true },
      { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
      { "neovim/nvim-lspconfig" },
    })
    local lspconfig = require("lspconfig")
    for _, server in ipairs({"nil_ls", "pyright", "bashls", "yamlls", "lua_ls"}) do
      lspconfig[server].setup({})
    end
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = ",preferred,auto,1";
      exec-once = [ "waybar" "mako" "nm-applet --indicator" ];
      input = { kb_layout = "us"; touchpad.natural_scroll = true; };
      general = { gaps_in = 5; gaps_out = 12; border_size = 2; layout = "dwindle"; };
      decoration = { rounding = 12; blur.enabled = true; shadow.enabled = true; };
      animations = {
        enabled = true;
        bezier = [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };
      "\$mod" = "SUPER";
      bind = [
        "\$mod, Return, exec, ghostty"
        "\$mod, B, exec, brave"
        "\$mod, E, exec, nautilus"
        "\$mod, D, exec, rofi -show drun"
        "\$mod, Q, killactive"
        "\$mod, F, fullscreen"
        "\$mod SHIFT, E, exit"
      ];
    };
  };
}
EOF
}

install_system(){
  nix --extra-experimental-features 'nix-command flakes' flake check /mnt/etc/nixos || warn "flake check reported warnings/errors; install will still attempt to continue."
  nixos-install --flake "/mnt/etc/nixos#${HOSTNAME}" --no-root-passwd
}

main(){
  : > ""
  need_root
  set_readable_console
  banner
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --mount-ventoy) bootstrap_live_deps "$@"; mount_ventoy; exit 0 ;;
    --copy-self) bootstrap_live_deps ""; copy_self_from_ventoy; exit 0 ;;
    --preflight) bootstrap_live_deps "$@"; preflight; exit 0 ;;
  esac
  preflight
  bootstrap_live_deps ""
  for c in lsblk sgdisk wipefs mkfs.btrfs mkfs.fat btrfs nixos-generate-config nixos-install nix lspci ip; do need_cmd "$c"; done
  detect_summary
  confirm_destruction
  partition_btrfs
  write_flake
  install_system
  success "Install complete. Reboot, login as ${USERNAME}, password ${INITIAL_PASSWORD}, then run passwd."
}
main "$@"
