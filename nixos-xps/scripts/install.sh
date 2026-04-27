#!/usr/bin/env bash
# =============================================================================
# NixOS XPS 9500 — Automated Installer
# =============================================================================
# Usage:
#   curl -sL https://raw.githubusercontent.com/YOU/nixos-xps/main/scripts/install.sh | bash
#   — OR —
#   git clone https://github.com/YOU/nixos-xps && cd nixos-xps && bash scripts/install.sh
#
# Environment overrides (set before running):
#   DISK          Target disk, e.g. /dev/nvme0n1   (default: auto-detect)
#   USERNAME      Primary user name               (default: nixuser)
#   HOSTNAME      System hostname                 (default: xps9500)
#   TIMEZONE      TZ string                       (default: America/New_York)
#   FLAKE_REPO    GitHub URL to your flake        (default: current dir)
#   SKIP_CONFIRM  Set to 1 to skip prompts        (default: 0)
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
             echo -e "${BOLD}${CYAN}  $*${RESET}"; \
             echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"; }

# ── Configuration ─────────────────────────────────────────────────────────────
USERNAME="${USERNAME:-nixuser}"
HOSTNAME="${HOSTNAME:-xps9500}"
TIMEZONE="${TIMEZONE:-America/New_York}"
SKIP_CONFIRM="${SKIP_CONFIRM:-0}"
FLAKE_DIR="${FLAKE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DISK="${DISK:-}"   # will be auto-detected if empty

# ── Banner ────────────────────────────────────────────────────────────────────
clear
cat <<'EOF'
    _   ___      ____  _____   _____  ________
   / | / (_)  __/ __ \/ ___/  / ___/ / ____/ /
  /  |/ / / |/_/ / / /\__ \   \__ \ / __/ / /
 / /|  / />  </ /_/ /___/ /  ___/ // /___/_/
/_/ |_/_/_/|_|\____//____/  /____//_____(_)

  XPS 9500 Automated Installer
  Hyprland · BTRFS+Snapper · NVIDIA · Flakes
EOF
echo ""

# =============================================================================
# PHASE 1: Pre-flight checks
# =============================================================================
header "Phase 1 — Pre-flight Checks"

# Root check
[[ $EUID -eq 0 ]] || die "Please run as root (or via sudo)"
success "Running as root"

# UEFI check
[[ -d /sys/firmware/efi ]] || die "Not booted in UEFI mode. Reboot with UEFI enabled."
success "UEFI boot detected"

# Network check
info "Checking network connectivity..."
if ! ping -c 1 -W 3 cache.nixos.org &>/dev/null; then
  die "No network. Connect via: nmtui  (or wpa_supplicant for WiFi)"
fi
success "Network is reachable"

# Nix check
if ! command -v nix &>/dev/null; then
  die "Nix not found. Are you booted from the NixOS installer ISO?"
fi
NIX_VERSION=$(nix --version)
success "Nix available: $NIX_VERSION"

# Nix flakes check
if ! nix flake --help &>/dev/null 2>&1; then
  info "Enabling nix flakes for this session..."
  export NIX_CONFIG="experimental-features = nix-command flakes"
fi
success "Nix flakes enabled"

# Required tools check
REQUIRED_TOOLS=(git curl partprobe sgdisk lsblk wipefs cryptsetup btrfs mkfs.vfat)
MISSING=()
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING+=("$tool")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Missing tools: ${MISSING[*]}"
  info "Installing via nix-shell..."
  # On NixOS live ISO, these are already present. On other distros:
  nix-shell -p git curl util-linux gptfdisk cryptsetup btrfs-progs dosfstools --run \
    "bash $0 $*" && exit $?
fi
success "All required tools present"

# Disko check
if ! nix run nixpkgs#disko -- --help &>/dev/null 2>&1; then
  warn "disko not directly runnable, will use nix run during install"
fi

# =============================================================================
# PHASE 2: Disk selection
# =============================================================================
header "Phase 2 — Disk Selection"

if [[ -z "$DISK" ]]; then
  echo -e "${BOLD}Available disks:${RESET}"
  lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -v "^loop\|^sr\|^fd"
  echo ""
  read -rp "Enter target disk (e.g. nvme0n1 or sda): " DISK_INPUT
  DISK="/dev/$DISK_INPUT"
fi

[[ -b "$DISK" ]] || die "Disk $DISK not found or not a block device"
DISK_SIZE=$(lsblk -d -o SIZE -n "$DISK" | tr -d ' ')
DISK_MODEL=$(lsblk -d -o MODEL -n "$DISK" | tr -d '  ')
success "Selected disk: $DISK ($DISK_SIZE — $DISK_MODEL)"

# =============================================================================
# PHASE 3: User configuration
# =============================================================================
header "Phase 3 — User Configuration"

echo -e "${BOLD}Installer Configuration:${RESET}"
echo "  Username : $USERNAME"
echo "  Hostname : $HOSTNAME"
echo "  Timezone : $TIMEZONE"
echo "  Disk     : $DISK ($DISK_SIZE)"
echo "  Flake    : $FLAKE_DIR"
echo ""

# Encryption passphrase
while true; do
  read -rsp "Enter LUKS disk encryption passphrase: " LUKS_PASS; echo
  read -rsp "Confirm passphrase: " LUKS_PASS2; echo
  [[ "$LUKS_PASS" == "$LUKS_PASS2" ]] && break
  error "Passphrases do not match. Try again."
done
success "Encryption passphrase set"

# User password
while true; do
  read -rsp "Enter password for user '$USERNAME': " USER_PASS; echo
  read -rsp "Confirm password: " USER_PASS2; echo
  [[ "$USER_PASS" == "$USER_PASS2" ]] && break
  error "Passwords do not match. Try again."
done
success "User password set"

# Final confirmation
if [[ "$SKIP_CONFIRM" != "1" ]]; then
  echo ""
  echo -e "${RED}${BOLD}⚠  WARNING: This will ERASE all data on $DISK!${RESET}"
  echo -e "${RED}   Model: $DISK_MODEL | Size: $DISK_SIZE${RESET}"
  echo ""
  read -rp "Type 'ERASE' to confirm and proceed: " CONFIRM
  [[ "$CONFIRM" == "ERASE" ]] || die "Aborted."
fi

# =============================================================================
# PHASE 4: Partitioning via disko
# =============================================================================
header "Phase 4 — Partitioning (disko + BTRFS)"

# Write passphrase to temp file for disko LUKS
KEYFILE=$(mktemp /tmp/disk.key.XXXXXX)
echo -n "$LUKS_PASS" > "$KEYFILE"
chmod 600 "$KEYFILE"
trap 'rm -f "$KEYFILE"' EXIT

# Patch disk-config.nix with the actual disk path (disko reads it)
info "Configuring disko for disk: $DISK"
DISK_CONFIG="$FLAKE_DIR/hosts/xps9500/disk-config.nix"
sed -i "s|lib.mkDefault \"/dev/nvme0n1\"|lib.mkDefault \"$DISK\"|g" "$DISK_CONFIG"

# Wipe existing partition table
info "Wiping existing partition table..."
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
partprobe "$DISK"
sleep 2

# Run disko
info "Running disko to create partitions and filesystems..."
nix run github:nix-community/disko -- \
  --mode disko \
  --flake "$FLAKE_DIR#xps9500" \
  2>&1 | grep -v "^$" || true

# Verify mounts
mount | grep -q "/mnt" || die "disko did not mount /mnt. Check errors above."
success "Partitions created and mounted"

# Create swap file (BTRFS swapfile needs special handling)
info "Creating swap file..."
SWAPFILE="/mnt/swap/swapfile"
SWAPSIZE=$((16 * 1024 * 1024))  # 16 GiB in KiB
btrfs filesystem mkswapfile --size 16G --uuid clear "$SWAPFILE"
success "Swap file created"

# ── Snapper base snapshot ─────────────────────────────────────────────────────
# We create the .snapshots subvol structure manually for snapper
info "Preparing snapper snapshot directories..."
mkdir -p /mnt/.snapshots
mkdir -p /mnt/home/.snapshots

# =============================================================================
# PHASE 5: Install NixOS
# =============================================================================
header "Phase 5 — NixOS Installation"

# Copy flake to /mnt/etc/nixos so it persists after reboot
info "Copying flake to /mnt/etc/nixos..."
mkdir -p /mnt/etc/nixos
cp -r "$FLAKE_DIR/." /mnt/etc/nixos/
# Restore original disk path after copy
git -C /mnt/etc/nixos checkout -- hosts/xps9500/disk-config.nix 2>/dev/null || true

# Write the actual disk path into the installed config
sed -i "s|lib.mkDefault \"/dev/nvme0n1\"|lib.mkDefault \"$DISK\"|g" \
  /mnt/etc/nixos/hosts/xps9500/disk-config.nix

info "Running nixos-install..."
nixos-install \
  --root /mnt \
  --no-root-passwd \
  --flake "$FLAKE_DIR#xps9500" \
  --show-trace \
  2>&1 | nix run nixpkgs#nix-output-monitor -- || \
nixos-install \
  --root /mnt \
  --no-root-passwd \
  --flake "$FLAKE_DIR#xps9500" \
  --show-trace

success "NixOS installed"

# =============================================================================
# PHASE 6: Post-install configuration
# =============================================================================
header "Phase 6 — Post-install Setup"

# Set user password
info "Setting password for $USERNAME..."
nixos-enter --root /mnt -- /bin/sh -c \
  "echo '${USERNAME}:${USER_PASS}' | chpasswd"
success "User password set"

# Install Cursor IDE via Flatpak (no Nix package available)
info "Registering Flathub for Cursor IDE installation (runs on first boot)..."
cat > /mnt/etc/nixos/scripts/post-boot-setup.sh <<'POSTBOOT'
#!/usr/bin/env bash
# Run once after first boot as nixuser
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.cursor.Cursor || \
  echo "Cursor IDE not on Flathub yet — download AppImage from https://cursor.sh"
POSTBOOT
chmod +x /mnt/etc/nixos/scripts/post-boot-setup.sh

# Generate hardware configuration for reference
info "Generating hardware-configuration.nix reference..."
nixos-generate-config --root /mnt --dir /tmp/hw-config
cp /tmp/hw-config/hardware-configuration.nix \
   /mnt/etc/nixos/hosts/xps9500/hardware-configuration.nix.reference

# Persist snapper configs
info "Writing snapper configuration..."
mkdir -p /mnt/etc/snapper/configs
# These will be populated by the NixOS module on first boot

# =============================================================================
# Done
# =============================================================================
header "Installation Complete!"

cat <<EOF
${GREEN}${BOLD}✓ NixOS has been installed on $DISK${RESET}

Next steps:
  1.  Reboot:          ${BOLD}reboot${RESET}
  2.  Login as:        ${BOLD}$USERNAME${RESET}
  3.  Install Cursor:  ${BOLD}bash /etc/nixos/scripts/post-boot-setup.sh${RESET}
  4.  Update flake:    ${BOLD}nfu && nrs${RESET}   (aliases set in shell.nix)
  5.  Set git info:    ${BOLD}nvim /etc/nixos/home/common/git.nix${RESET}

${CYAN}Hyprland starts automatically after login.${RESET}
${CYAN}GNOME is available at the login screen as a fallback session.${RESET}

${YELLOW}Tip: Run 'fastfetch' (or just 'ff') for system info${RESET}
EOF

echo ""
read -rp "Press Enter to reboot, or Ctrl-C to cancel..." _
reboot
