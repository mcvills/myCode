#!/usr/bin/env bash
# NixOS XPS 9500 / VM Flake Installer v4
# Boot from NixOS 25.11 graphical or minimal ISO, then run:
#   bash install-nixos-xps9500-v4.sh --preflight
#   TARGET_DISK=/dev/nvme0n1 PROFILE=xps9500 WIPE_DISK=true bash install-nixos-xps9500-v4.sh

set -Eeuo pipefail

VERSION="4.0"
SCRIPT_NAME="install-nixos-xps9500-v4"
LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME}.log}"
MNT="${MNT:-/mnt}"
SCRIPTS_MOUNT="${SCRIPTS_MOUNT:-/mnt/scripts}"
HOSTNAME="${HOSTNAME:-nixos-xps9500}"
USERNAME="${USERNAME:-dana}"
PROFILE="${PROFILE:-xps9500}"   # xps9500 or vm
TARGET_DISK="${TARGET_DISK:-}"
WIPE_DISK="${WIPE_DISK:-false}"
TIMEZONE="${TIMEZONE:-America/New_York}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"
ENABLE_SWAPFILE="${ENABLE_SWAPFILE:-true}"
SWAP_SIZE="${SWAP_SIZE:-16G}"

# package/UI preferences
PREFER_GUM="${PREFER_GUM:-true}"
PREFER_FIGLET="${PREFER_FIGLET:-true}"
AUTO_NIX_SHELL="${AUTO_NIX_SHELL:-true}"

: > "$LOG_FILE"

C_RESET='\033[0m'; C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'; C_MAGENTA='\033[35m'; C_CYAN='\033[36m'; C_BOLD='\033[1m'

log(){ local level="$1"; shift; local msg="$*"; printf '[%s] %s\n' "$level" "$msg" | tee -a "$LOG_FILE" >&2; }
info(){ printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
success(){ printf "${C_GREEN}[SUCCESS]${C_RESET} %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
warn(){ printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
fail(){ printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

run(){ info "RUN: $*"; "$@" 2>&1 | tee -a "$LOG_FILE"; }
have(){ command -v "$1" >/dev/null 2>&1; }

need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run as root: sudo -i, then bash $0"; }

set_readable_console(){
  if have setfont; then
    for f in ter-v36n ter-v32n ter-v28n ter-v24n; do
      if setfont "$f" >/dev/null 2>&1; then info "Console font set to $f"; return 0; fi
    done
  fi
  true
}

banner(){
  echo
  if [[ "$PREFER_FIGLET" == "true" ]] && have figlet; then
    figlet -w 90 "NixOS V${VERSION}" || true
  else
    printf "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════╗${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}║        NixOS XPS 9500 / VM Flake Installer v%s              ║${C_RESET}\n" "$VERSION"
    printf "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════╝${C_RESET}\n"
  fi
  echo
}

maybe_reexec_with_nix_shell(){
  [[ "$AUTO_NIX_SHELL" == "true" ]] || return 0
  [[ "${IN_NIX_SHELL:-}" == "impure" || "${IN_NIX_SHELL:-}" == "pure" ]] && return 0
  have nix-shell || return 0

  local missing=()
  for c in git curl jq figlet; do have "$c" || missing+=("$c"); done
  if ((${#missing[@]} > 0)); then
    warn "Missing optional tools: ${missing[*]}"
    info "Re-entering nix-shell with installer helper tools."
    exec nix-shell -p bash coreutils gnugrep gawk gnused util-linux git curl jq figlet gum btrfs-progs dosfstools e2fsprogs parted gptfdisk exfatprogs ntfs3g pciutils usbutils fastfetch --run "bash '$0' $*"
  fi
}

detect_machine_type(){
  if have systemd-detect-virt && systemd-detect-virt --quiet; then
    systemd-detect-virt
  elif grep -qiE 'hypervisor|kvm|vmware|virtualbox|qemu' /proc/cpuinfo 2>/dev/null; then
    echo "virtual"
  else
    echo "physical"
  fi
}

network_ok(){
  ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 3 github.com >/dev/null 2>&1
}

show_network_status(){
  info "Network interfaces:"
  ip -brief addr 2>/dev/null | tee -a "$LOG_FILE" || true
  if network_ok; then success "Network connectivity OK"; else warn "Network connectivity FAILED"; fi
}

ventoy_mode_detect(){
  if [[ -e /dev/mapper/ventoy ]] || ls /dev/mapper 2>/dev/null | grep -qi ventoy; then
    warn "Ventoy ISO/device-mapper mode detected. The real USB data partition may be hidden."
    warn "If /mnt/scripts cannot mount, reboot Ventoy and press Ctrl+R -> GRUB2 Mode, or pull scripts from GitHub."
    return 0
  fi
  return 1
}

try_mount_ventoy(){
  mkdir -p "$SCRIPTS_MOUNT"
  mountpoint -q "$SCRIPTS_MOUNT" && { success "Scripts mount already active: $SCRIPTS_MOUNT"; return 0; }
  modprobe exfat >/dev/null 2>&1 || true

  local dev
  for dev in /dev/disk/by-label/VENTOY /dev/disk/by-label/Ventoy /dev/disk/by-label/ventoy; do
    [[ -e "$dev" ]] || continue
    if mount -t exfat "$dev" "$SCRIPTS_MOUNT" 2>>"$LOG_FILE" || mount "$dev" "$SCRIPTS_MOUNT" 2>>"$LOG_FILE"; then
      success "Mounted Ventoy scripts partition at $SCRIPTS_MOUNT from $dev"
      return 0
    fi
  done

  for dev in /dev/disk/by-id/*part1 /dev/sd[a-z]1 /dev/nvme*n*p1; do
    [[ -e "$dev" ]] || continue
    blkid "$dev" 2>/dev/null | grep -qi 'TYPE="exfat"' || continue
    if mount -t exfat "$dev" "$SCRIPTS_MOUNT" 2>>"$LOG_FILE"; then
      success "Mounted exFAT scripts partition at $SCRIPTS_MOUNT from $dev"
      return 0
    fi
  done

  warn "Could not mount Ventoy/scripts partition automatically."
  ventoy_mode_detect || true
  return 1
}

preflight(){
  need_root
  set_readable_console
  banner
  info "Preflight mode only. No disk changes will be made."
  echo
  info "System summary"
  printf '  %-18s %s\n' "Version:" "$VERSION"
  printf '  %-18s %s\n' "Machine type:" "$(detect_machine_type)"
  printf '  %-18s %s\n' "Profile:" "$PROFILE"
  printf '  %-18s %s\n' "Target disk:" "${TARGET_DISK:-not set}"
  printf '  %-18s %s\n' "Hostname:" "$HOSTNAME"
  printf '  %-18s %s\n' "Username:" "$USERNAME"
  printf '  %-18s %s\n' "Log file:" "$LOG_FILE"
  echo

  info "Block devices"
  lsblk -o NAME,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS | tee -a "$LOG_FILE" || true
  echo

  show_network_status
  echo

  if try_mount_ventoy; then
    info "Scripts directory listing:"
    ls -la "$SCRIPTS_MOUNT" | head -80 | tee -a "$LOG_FILE" || true
  fi
  echo

  info "Hardware hints"
  if have lspci; then
    lspci | grep -Ei 'vga|3d|network|wireless|nvidia|intel' | tee -a "$LOG_FILE" || true
  else
    warn "lspci unavailable"
  fi
  echo

  if [[ -n "$TARGET_DISK" && -b "$TARGET_DISK" ]]; then
    success "TARGET_DISK exists: $TARGET_DISK"
  elif [[ -n "$TARGET_DISK" ]]; then
    warn "TARGET_DISK does not exist: $TARGET_DISK"
  else
    warn "TARGET_DISK not set. Example: TARGET_DISK=/dev/nvme0n1"
  fi

  success "Preflight complete."
}

confirm_install(){
  [[ -n "$TARGET_DISK" ]] || fail "TARGET_DISK is not set. Example: TARGET_DISK=/dev/nvme0n1"
  [[ -b "$TARGET_DISK" ]] || fail "TARGET_DISK is not a block device: $TARGET_DISK"
  [[ "$WIPE_DISK" == "true" ]] || fail "Refusing destructive install. Set WIPE_DISK=true to continue."

  echo
  warn "DESTRUCTIVE ACTION: this will wipe and repartition $TARGET_DISK"
  lsblk -o NAME,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS "$TARGET_DISK" || true
  echo
  read -r -p "Type INSTALL to wipe ${TARGET_DISK} and install NixOS: " ans
  [[ "$ans" == "INSTALL" ]] || fail "Install cancelled."
}

partition_disk(){
  info "Partitioning $TARGET_DISK"
  swapoff -a || true
  umount -R "$MNT" 2>/dev/null || true
  # Preserve /mnt/scripts when possible if it got nested under /mnt; users should run script from /root or GitHub clone.
  run sgdisk --zap-all "$TARGET_DISK"
  run sgdisk -n1:1MiB:+1024MiB -t1:EF00 -c1:EFI "$TARGET_DISK"
  run sgdisk -n2:0:0 -t2:8300 -c2:NIXOS "$TARGET_DISK"
  partprobe "$TARGET_DISK" || true
  sleep 2
}

part_path(){
  local disk="$1" num="$2"
  if [[ "$disk" =~ nvme|mmcblk ]]; then echo "${disk}p${num}"; else echo "${disk}${num}"; fi
}

format_mount(){
  local efi rootp
  efi="$(part_path "$TARGET_DISK" 1)"
  rootp="$(part_path "$TARGET_DISK" 2)"
  info "Formatting EFI: $efi"
  run mkfs.fat -F 32 -n EFI "$efi"
  info "Formatting BTRFS root: $rootp"
  run mkfs.btrfs -f -L nixos "$rootp"

  run mount "$rootp" "$MNT"
  for sub in @ @home @nix @log @persist @snapshots; do
    run btrfs subvolume create "$MNT/$sub"
  done
  umount "$MNT"

  local opts="noatime,compress=zstd:1,ssd,discard=async,space_cache=v2"
  run mount -o "$opts,subvol=@" "$rootp" "$MNT"
  mkdir -p "$MNT"/{boot,home,nix,var/log,persist,.snapshots}
  run mount -o "$opts,subvol=@home" "$rootp" "$MNT/home"
  run mount -o "$opts,subvol=@nix" "$rootp" "$MNT/nix"
  run mount -o "$opts,subvol=@log" "$rootp" "$MNT/var/log"
  run mount -o "$opts,subvol=@persist" "$rootp" "$MNT/persist"
  run mount -o "$opts,subvol=@snapshots" "$rootp" "$MNT/.snapshots"
  run mount "$efi" "$MNT/boot"
}

write_flake(){
  info "Writing modular flake configuration"
  mkdir -p "$MNT/etc/nixos/modules" "$MNT/etc/nixos/hosts/$HOSTNAME"
  cat > "$MNT/etc/nixos/flake.nix" <<'NIX'
{
  description = "Modern NixOS flake installer for Dell XPS 9500 and VM profiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = "x86_64-linux";
    mkHost = hostName: profile: username: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit hostName profile username; };
      modules = [
        ./configuration.nix
        ./modules/desktop.nix
        ./modules/packages.nix
        ./modules/snapper.nix
        ./modules/nvidia-xps9500.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = import ./home.nix;
        }
      ];
    };
  in {
    nixosConfigurations.nixos-xps9500 = mkHost "nixos-xps9500" "xps9500" "dana";
    nixosConfigurations.nixos-vm = mkHost "nixos-vm" "vm" "dana";
  };
}
NIX

  cat > "$MNT/etc/nixos/configuration.nix" <<NIX
{ config, pkgs, lib, hostName, profile, username, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "${HOSTNAME}";
  networking.networkmanager.enable = true;
  time.timeZone = "${TIMEZONE}";
  i18n.defaultLocale = "${LOCALE}";
  console.keyMap = "${KEYMAP}";
  console.font = "ter-v32n";

  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;
  services.printing.enable = true;
  services.openssh.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "btrfs" "exfat" "ntfs" ];

  users.users.${USERNAME} = {
    isNormalUser = true;
    description = "${USERNAME}";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
NIX

  cat > "$MNT/etc/nixos/modules/desktop.nix" <<'NIX'
{ config, pkgs, lib, profile, ... }:
{
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.xkb.layout = "us";

  programs.hyprland.enable = true;
  programs.hyprland.xwayland.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-hyprland ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  security.rtkit.enable = true;
}
NIX

  cat > "$MNT/etc/nixos/modules/packages.nix" <<'NIX'
{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    bashInteractive zsh git curl wget jq unzip zip tree htop btop fastfetch pciutils usbutils
    vim neovim lazygit ripgrep fd fzf gcc gnumake python3 nodejs
    ghostty keepassxc libreoffice gimp brave mpv obsidian
    snapper btrfs-progs exfatprogs ntfs3g dosfstools gptfdisk parted
    wl-clipboard cliphist waybar rofi-wayland mako grim slurp swappy hyprpaper hyprlock
  ] ++ lib.optionals (pkgs ? code-cursor) [ pkgs.code-cursor ];

  programs.firefox.enable = true;
  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono nerd-fonts.fira-code noto-fonts noto-fonts-emoji ];
}
NIX

  cat > "$MNT/etc/nixos/modules/snapper.nix" <<'NIX'
{ config, pkgs, lib, ... }:
{
  services.snapper = {
    snapshotRootOnBoot = true;
    configs.root = {
      SUBVOLUME = "/";
      ALLOW_USERS = [ ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      NUMBER_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 10;
      TIMELINE_LIMIT_DAILY = 10;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 6;
      TIMELINE_LIMIT_YEARLY = 1;
    };
  };
}
NIX

  cat > "$MNT/etc/nixos/modules/nvidia-xps9500.nix" <<'NIX'
{ config, pkgs, lib, profile, ... }:
{
  config = lib.mkIf (profile == "xps9500") {
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.graphics.enable = true;
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload.enable = true;
        offload.enableOffloadCmd = true;
        # Dell XPS 15 9500 commonly uses Intel iGPU + NVIDIA dGPU.
        # Verify bus IDs after install with: lspci | grep -E "VGA|3D"
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };
}
NIX

  cat > "$MNT/etc/nixos/home.nix" <<'NIX'
{ config, pkgs, ... }:
{
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.zsh = {
    enable = true;
    shellAliases = {
      ll = "ls -alF";
      gs = "git status";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#$(hostname)";
    };
    initContent = ''
      fastfetch 2>/dev/null || true
    '';
  };
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
NIX
}

generate_hw_config(){
  info "Generating hardware configuration"
  run nixos-generate-config --root "$MNT"
}

install_nixos(){
  local flake_target
  if [[ "$PROFILE" == "vm" ]]; then flake_target="nixos-vm"; else flake_target="nixos-xps9500"; fi
  info "Installing NixOS flake target: $flake_target"
  run nixos-install --flake "$MNT/etc/nixos#$flake_target" --no-root-passwd
}

post_summary(){
  success "Install complete"
  echo
  printf '  %-18s %s\n' "Host:" "$HOSTNAME"
  printf '  %-18s %s\n' "Profile:" "$PROFILE"
  printf '  %-18s %s\n' "Disk:" "$TARGET_DISK"
  printf '  %-18s %s\n' "Config:" "$MNT/etc/nixos"
  printf '  %-18s %s\n' "Log:" "$LOG_FILE"
  echo
  warn "Set the user password after first boot if needed: passwd ${USERNAME}"
  warn "Verify NVIDIA PRIME bus IDs after install: lspci | grep -E 'VGA|3D'"
}

usage(){
  cat <<USAGE
${SCRIPT_NAME} v${VERSION}

Usage:
  bash $0 --preflight
  TARGET_DISK=/dev/nvme0n1 PROFILE=xps9500 WIPE_DISK=true bash $0
  TARGET_DISK=/dev/vda PROFILE=vm HOSTNAME=nixos-vm WIPE_DISK=true bash $0

Environment variables:
  TARGET_DISK       Target disk to wipe/install to
  PROFILE           xps9500 or vm
  HOSTNAME          NixOS hostname
  USERNAME          Normal user to create
  WIPE_DISK=true    Required for destructive install
  AUTO_NIX_SHELL    true/false, default true
USAGE
}

main(){
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --preflight) maybe_reexec_with_nix_shell "$@"; preflight; exit 0 ;;
  esac

  need_root
  maybe_reexec_with_nix_shell "$@"
  set_readable_console
  banner
  show_network_status
  try_mount_ventoy || true
  confirm_install
  partition_disk
  format_mount
  generate_hw_config
  write_flake
  install_nixos
  post_summary
}

main "$@"
