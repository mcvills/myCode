#!/usr/bin/env bash
# File: Debian13_BTRFS_Bootstrap_v4_3.sh
# Purpose: Install Debian 13 from Debian Live ISO using:
#   - GPT + UEFI
#   - LVM (VG0/LV0)
#   - Btrfs subvolumes
#   - Snapper
#   - grub-btrfs
#   - zram-tools
#   - deb822 APT sources
#   - NVIDIA GPU detection (auto-installs nvidia-driver when detected)
#   - Auto-detection of active interface, IP address, interface name
#   - Simplified interactive prompts (pre-populates as much as possible)
#
# WARNING: This script DESTROYS all data on the selected disk.

set -euo pipefail
IFS=$'\n\t'

START_EPOCH="$(date +%s)"

########################################
# Defaults
########################################
DEBIAN_RELEASE="trixie"
TIMEZONE="America/New_York"
HOSTNAME="debian13"
USERNAME=""
TARGET="/target"
LOG_FILE="/var/log/debian13-bootstrap.log"
PING_IP="1.1.1.1"
PING_DNS="deb.debian.org"
DRY_RUN=false
TARGET_DISK=""
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="4.3"

# LVM
VG_NAME="VG0"
LV_NAME="LV0"
DM_NAME="${VG_NAME}-${LV_NAME}"

# grub-btrfs
GRUB_BTRFS_REPO="https://github.com/Antynea/grub-btrfs.git"
GRUB_BTRFS_BRANCH="master"

# Static IP
STATIC_IP_ENABLED=false
STATIC_INTERFACE=""
IP_ADDRESS=""
GATEWAY=""
DNS_SERVER=""
DOMAIN=""

# NVIDIA
NVIDIA_GPU_DETECTED=false
NVIDIA_INSTALL=false

# Prompt
CUSTOM_PS1="export PS1='\[\e[32m\][\[\e[m\]\[\e[31m\]\u\[\e[m\]\[\e[33m\]@\[\e[m\]\[\e[32m\]\h\[\e[m\]:\[\e[36m\]\w\[\e[m\]\[\e[32m\]]\[\e[m\]\[\e[32;32m\]\$\[\e[m\] '"

########################################
# Colors
########################################
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
NC="\e[0m"

########################################
# Logging helpers
########################################
SUCCESS() { echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"; }
INFO()    { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
WARN()    { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
ERROR()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
die()     { ERROR "$*"; exit 1; }

run() {
    local desc="$1"
    shift
    INFO "$desc"
    if [[ "$DRY_RUN" == true ]]; then
        printf 'DRY-RUN CMD: ' | tee -a "$LOG_FILE"
        printf '%q ' "$@" | tee -a "$LOG_FILE"
        echo | tee -a "$LOG_FILE"
        return 0
    fi
    "$@" >>"$LOG_FILE" 2>&1
    SUCCESS "$desc"
}

run_visible() {
    local desc="$1"
    shift
    INFO "$desc"
    if [[ "$DRY_RUN" == true ]]; then
        printf 'DRY-RUN CMD: ' | tee -a "$LOG_FILE"
        printf '%q ' "$@" | tee -a "$LOG_FILE"
        echo | tee -a "$LOG_FILE"
        return 0
    fi
    "$@" 2>&1 | tee -a "$LOG_FILE"
    SUCCESS "$desc"
}

########################################
# Cleanup / traps
########################################
cleanup_mounts_quiet() {
    local points=(
        "$TARGET/boot/efi"
        "$TARGET/.snapshots"
        "$TARGET/home"
        "$TARGET/var/log"
        "$TARGET/var/cache"
        "$TARGET/var/tmp"
        "$TARGET/opt"
        "$TARGET/run"
        "$TARGET/proc"
        "$TARGET"
    )

    for p in "${points[@]}"; do
        if mountpoint -q "$p" 2>/dev/null; then
            umount -lf "$p" >/dev/null 2>&1 || true
        fi
    done

    if mountpoint -q "$TARGET/dev" 2>/dev/null; then
        umount -R "$TARGET/dev" >/dev/null 2>&1 || true
    fi
    if mountpoint -q "$TARGET/sys" 2>/dev/null; then
        umount -R "$TARGET/sys" >/dev/null 2>&1 || true
    fi
}

on_error() {
    local line="$1"
    ERROR "Script failed at line $line. Review $LOG_FILE"
    cleanup_mounts_quiet
}
trap 'on_error $LINENO' ERR

########################################
# Usage / args
########################################
usage() {
cat <<EOF
Usage: sudo bash ${SCRIPT_NAME} [options]

Version: ${SCRIPT_VERSION}

Options:
  --disk /dev/sdX           Target disk
  --hostname NAME           Hostname for new system (default: ${HOSTNAME})
  --username NAME           Admin username (default: ${USERNAME})
  --timezone ZONE           Timezone (default: ${TIMEZONE})
  --dry-run                 Preview only
  --static-ip               Enable static IP configuration
  --interface IFACE         Interface name for static IP
  --ip-address ADDR         Static IP address
  --gateway GW              Default gateway
  --dns-server DNS          DNS server
  --domain DOMAIN           DNS search domain
  --nvidia                  Force NVIDIA driver installation
  --help                    Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --disk)       TARGET_DISK="$2"; shift 2 ;;
            --hostname)   HOSTNAME="$2"; shift 2 ;;
            --username)   USERNAME="$2"; shift 2 ;;
            --timezone)   TIMEZONE="$2"; shift 2 ;;
            --dry-run)    DRY_RUN=true; shift ;;
            --static-ip)  STATIC_IP_ENABLED=true; shift ;;
            --interface)  STATIC_INTERFACE="$2"; shift 2 ;;
            --ip-address) IP_ADDRESS="$2"; shift 2 ;;
            --gateway)    GATEWAY="$2"; shift 2 ;;
            --dns-server) DNS_SERVER="$2"; shift 2 ;;
            --domain)     DOMAIN="$2"; shift 2 ;;
            --nvidia)     NVIDIA_INSTALL=true; shift ;;
            --help|-h)    usage; exit 0 ;;
            *)            die "Unknown option: $1" ;;
        esac
    done

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        [[ -n "$IP_ADDRESS" && -n "$GATEWAY" && -n "$DNS_SERVER" ]] || \
            die "Static IP mode requires --ip-address, --gateway, and --dns-server"
    fi
}

########################################
# General helpers
########################################
require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run this script as root."
}

require_timeout() {
    command -v timeout >/dev/null 2>&1 || die "'timeout' command is required but not found."
}

init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    INFO "Logging to $LOG_FILE"
}

format_duration() {
    local elapsed="$1"
    local h=$((elapsed / 3600))
    local m=$(((elapsed % 3600) / 60))
    local s=$((elapsed % 60))
    printf '%02dh:%02dm:%02ds' "$h" "$m" "$s"
}

preflight_summary() {
    INFO "Preflight summary"
    echo "  Script version:  ${SCRIPT_VERSION}" | tee -a "$LOG_FILE"
    echo "  Live kernel:     $(uname -r)" | tee -a "$LOG_FILE"
    echo "  Architecture:    $(uname -m)" | tee -a "$LOG_FILE"
    echo "  Memory:          $(awk '/MemTotal/ {printf "%.1f GiB\n", $2/1024/1024}' /proc/meminfo)" | tee -a "$LOG_FILE"
    echo "  Target disk:     ${TARGET_DISK:-<not selected yet>}" | tee -a "$LOG_FILE"
    echo "  NVIDIA GPU:      ${NVIDIA_GPU_DETECTED}" | tee -a "$LOG_FILE"
    echo "  NVIDIA install:  ${NVIDIA_INSTALL}" | tee -a "$LOG_FILE"
}

check_uefi() {
    INFO "Checking UEFI boot mode..."
    [[ -d /sys/firmware/efi/efivars ]] || die "System is not booted in UEFI mode."
    SUCCESS "UEFI mode confirmed"
}

check_connectivity() {
    INFO "Checking internet connectivity..."
    ping -c 2 -W 3 "$PING_IP" >/dev/null 2>&1 || die "Cannot reach $PING_IP"
    ping -c 2 -W 3 "$PING_DNS" >/dev/null 2>&1 || die "Cannot resolve/reach $PING_DNS"
    SUCCESS "Connectivity looks good"
}

install_live_dependencies() {
    INFO "Checking required tools in the live environment..."
    local missing=()
    local cmd
    for cmd in \
        parted mkfs.vfat mkfs.btrfs debootstrap sgdisk blkid \
        mount umount lsblk awk grep sed ping chroot mountpoint \
        git make findmnt pvcreate vgcreate lvcreate partprobe udevadm \
        vgchange lvchange lvremove vgremove dmsetup wipefs dd \
        blockdev partx systemctl timeout
    do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]})); then
        WARN "Missing commands detected: ${missing[*]}"
        run_visible "Running apt-get update in live environment" apt-get update
        run_visible "Installing live environment dependencies" \
            apt-get install -y \
            parted dosfstools btrfs-progs debootstrap arch-install-scripts \
            gdisk efibootmgr git make lvm2 util-linux coreutils systemd
    else
        SUCCESS "Required live-environment tools already available"
    fi
}

########################################
# NVIDIA GPU Detection  (v4.3 NEW)
########################################
detect_nvidia_gpu() {
    INFO "Scanning for NVIDIA GPU hardware..."

    if lspci 2>/dev/null | grep -qi "NVIDIA"; then
        NVIDIA_GPU_DETECTED=true
        SUCCESS "NVIDIA GPU detected via lspci"
        lspci 2>/dev/null | grep -i "NVIDIA" | tee -a "$LOG_FILE" || true
    elif [[ -d /proc/driver/nvidia ]]; then
        NVIDIA_GPU_DETECTED=true
        SUCCESS "NVIDIA GPU detected via /proc/driver/nvidia"
    else
        NVIDIA_GPU_DETECTED=false
        INFO "No NVIDIA GPU detected"
    fi

    # Auto-enable install flag if GPU found and not already explicitly set
    if [[ "$NVIDIA_GPU_DETECTED" == true && "$NVIDIA_INSTALL" == false ]]; then
        NVIDIA_INSTALL=true
        INFO "NVIDIA GPU detected — nvidia-driver will be installed automatically"
    fi
}

########################################
# Auto-detection of network parameters  (v4.3 NEW)
########################################
auto_detect_network() {
    INFO "Auto-detecting live network configuration..."

    # Detect active interface (interface with default route)
    local detected_iface=""
    detected_iface="$(ip -o route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"

    if [[ -n "$detected_iface" ]]; then
        # Strip any trailing @... (seen on some bond/vlan interfaces)
        detected_iface="${detected_iface%%@*}"
        INFO "Detected active interface: $detected_iface"
        # Only set if not already provided via CLI
        [[ -z "$STATIC_INTERFACE" ]] && STATIC_INTERFACE="$detected_iface"
    fi

    # Detect current IP on that interface
    if [[ -n "$STATIC_INTERFACE" && -z "$IP_ADDRESS" ]]; then
        local detected_ip=""
        detected_ip="$(ip -o -4 addr show dev "$STATIC_INTERFACE" 2>/dev/null \
            | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
        if [[ -n "$detected_ip" ]]; then
            IP_ADDRESS="$detected_ip"
            INFO "Detected IP address: $IP_ADDRESS (on $STATIC_INTERFACE)"
        fi
    fi

    # Detect default gateway
    if [[ -z "$GATEWAY" ]]; then
        local detected_gw=""
        detected_gw="$(ip -o route show default 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' | head -1 || true)"
        if [[ -n "$detected_gw" ]]; then
            GATEWAY="$detected_gw"
            INFO "Detected gateway: $GATEWAY"
        fi
    fi

    # Detect DNS from resolv.conf
    if [[ -z "$DNS_SERVER" ]]; then
        local detected_dns=""
        detected_dns="$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null \
            | awk '{print $2}' || true)"
        if [[ -n "$detected_dns" ]]; then
            DNS_SERVER="$detected_dns"
            INFO "Detected DNS server: $DNS_SERVER"
        fi
    fi

    # Detect search domain from resolv.conf
    if [[ -z "$DOMAIN" ]]; then
        local detected_domain=""
        detected_domain="$(grep -m1 '^search\|^domain' /etc/resolv.conf 2>/dev/null \
            | awk '{print $2}' || true)"
        if [[ -n "$detected_domain" ]]; then
            DOMAIN="$detected_domain"
            INFO "Detected DNS domain: $DOMAIN"
        fi
    fi

    SUCCESS "Network auto-detection complete"
}

########################################
# Interactive prompt — ask only what is needed  (v4.3 NEW)
########################################
interactive_prompt() {
    echo
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Debian 13 Bootstrap v${SCRIPT_VERSION} — Interactive Configuration    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    INFO "Pre-detected values are shown in brackets. Press ENTER to accept."
    echo

    # --- Hostname ---
    local input_hostname
    read -r -p "  Hostname [${HOSTNAME}]: " input_hostname
    [[ -n "$input_hostname" ]] && HOSTNAME="$input_hostname"

    # --- Username ---
    while [[ -z "$USERNAME" ]]; do
        local input_username
        read -r -p "  Admin username (required): " input_username
        input_username="$(echo "$input_username" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
        if [[ -n "$input_username" ]]; then
            USERNAME="$input_username"
        else
            WARN "Username cannot be empty."
        fi
    done

    # --- Timezone ---
    local input_tz
    read -r -p "  Timezone [${TIMEZONE}]: " input_tz
    [[ -n "$input_tz" ]] && TIMEZONE="$input_tz"

    # --- Static IP ---
    echo
    echo -e "  ${YELLOW}Network configuration:${NC}"
    echo "    Detected interface : ${STATIC_INTERFACE:-<none>}"
    echo "    Detected IP        : ${IP_ADDRESS:-<none>}"
    echo "    Detected gateway   : ${GATEWAY:-<none>}"
    echo "    Detected DNS       : ${DNS_SERVER:-<none>}"
    echo "    Detected domain    : ${DOMAIN:-<none>}"
    echo

    if [[ "$STATIC_IP_ENABLED" == false ]]; then
        local input_static
        read -r -p "  Configure static IP for the installed system? [y/N]: " input_static
        if [[ "$input_static" =~ ^[Yy]$ ]]; then
            STATIC_IP_ENABLED=true
        fi
    fi

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        local input_iface
        read -r -p "  Interface [${STATIC_INTERFACE:-eth0}]: " input_iface
        [[ -n "$input_iface" ]] && STATIC_INTERFACE="$input_iface"
        [[ -z "$STATIC_INTERFACE" ]] && STATIC_INTERFACE="eth0"

        local input_ip
        read -r -p "  IP address/prefix (e.g. 192.168.1.10/24) [${IP_ADDRESS:-}]: " input_ip
        [[ -n "$input_ip" ]] && IP_ADDRESS="$input_ip"
        while [[ -z "$IP_ADDRESS" ]]; do
            read -r -p "  IP address (required): " input_ip
            [[ -n "$input_ip" ]] && IP_ADDRESS="$input_ip"
        done

        local input_gw
        read -r -p "  Gateway [${GATEWAY:-}]: " input_gw
        [[ -n "$input_gw" ]] && GATEWAY="$input_gw"
        while [[ -z "$GATEWAY" ]]; do
            read -r -p "  Gateway (required): " input_gw
            [[ -n "$input_gw" ]] && GATEWAY="$input_gw"
        done

        local input_dns
        read -r -p "  DNS server [${DNS_SERVER:-1.1.1.1}]: " input_dns
        [[ -n "$input_dns" ]] && DNS_SERVER="$input_dns"
        [[ -z "$DNS_SERVER" ]] && DNS_SERVER="1.1.1.1"

        local input_domain
        read -r -p "  DNS search domain [${DOMAIN:-}]: " input_domain
        [[ -n "$input_domain" ]] && DOMAIN="$input_domain"
    fi

    # --- NVIDIA ---
    echo
    if [[ "$NVIDIA_GPU_DETECTED" == true ]]; then
        local input_nvidia
        read -r -p "  NVIDIA GPU detected — install nvidia-driver? [Y/n]: " input_nvidia
        if [[ "$input_nvidia" =~ ^[Nn]$ ]]; then
            NVIDIA_INSTALL=false
        else
            NVIDIA_INSTALL=true
        fi
    fi

    echo
    SUCCESS "Interactive configuration complete"
}

########################################
# Disk / network detection
########################################
detect_disks() {
    INFO "Available disks:"
    lsblk -d -e7 -o NAME,SIZE,MODEL,TYPE | tee -a "$LOG_FILE"

    if [[ -z "$TARGET_DISK" ]]; then
        mapfile -t disks < <(lsblk -d -n -e7 -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
        [[ ${#disks[@]} -gt 0 ]] || die "No target disks found."

        echo
        local i=1
        for d in "${disks[@]}"; do
            local size model
            size="$(lsblk -d -n -o SIZE "$d" 2>/dev/null || echo '?')"
            model="$(lsblk -d -n -o MODEL "$d" 2>/dev/null | xargs || echo 'Unknown')"
            echo "[$i] $d   $size   $model"
            ((i++))
        done
        echo
        read -r -p "Select target disk number: " idx
        [[ "$idx" =~ ^[0-9]+$ ]] || die "Invalid selection."
        (( idx >= 1 && idx <= ${#disks[@]} )) || die "Selection out of range."
        TARGET_DISK="${disks[$((idx - 1))]}"
    fi

    [[ -b "$TARGET_DISK" ]] || die "Disk not found: $TARGET_DISK"
    SUCCESS "Selected target disk: $TARGET_DISK"
    lsblk "$TARGET_DISK" | tee -a "$LOG_FILE"
}

detect_active_interface() {
    [[ "$STATIC_IP_ENABLED" == true ]] || return 0
    [[ -n "$STATIC_INTERFACE" ]] && return 0

    INFO "Detecting network interface (fallback)..."

    local route_if=""
    route_if="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"

    mapfile -t nics < <(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | cut -d'@' -f1)

    if [[ -n "$route_if" ]]; then
        STATIC_INTERFACE="$route_if"
        SUCCESS "Detected active interface: $STATIC_INTERFACE"
        return 0
    fi

    if [[ ${#nics[@]} -eq 1 ]]; then
        STATIC_INTERFACE="${nics[0]}"
        SUCCESS "Only one interface found, using: $STATIC_INTERFACE"
        return 0
    fi

    if [[ ${#nics[@]} -gt 1 ]]; then
        WARN "Multiple interfaces detected. Please choose one:"
        local i=1
        for nic in "${nics[@]}"; do
            echo "[$i] $nic"
            ((i++))
        done
        echo
        read -r -p "Select interface number: " idx
        [[ "$idx" =~ ^[0-9]+$ ]] || die "Invalid interface selection."
        (( idx >= 1 && idx <= ${#nics[@]} )) || die "Selection out of range."
        STATIC_INTERFACE="${nics[$((idx - 1))]}"
        SUCCESS "Selected interface: $STATIC_INTERFACE"
        return 0
    fi

    die "Could not determine a usable network interface."
}

set_partition_names() {
    if [[ "$TARGET_DISK" =~ (nvme|mmcblk) ]]; then
        EFI_PART="${TARGET_DISK}p1"
        LVM_PART="${TARGET_DISK}p2"
    else
        EFI_PART="${TARGET_DISK}1"
        LVM_PART="${TARGET_DISK}2"
    fi
    ROOT_SPEC="/dev/mapper/${DM_NAME}"
}

confirm_plan() {
    echo
    WARN "This will erase ALL DATA on ${TARGET_DISK}"
    echo "Plan:"
    echo "  Version:         ${SCRIPT_VERSION}"
    echo "  Disk:            ${TARGET_DISK}"
    echo "  EFI:             ${EFI_PART} (1 GiB FAT32)"
    echo "  LVM PV:          ${LVM_PART}"
    echo "  VG/LV:           ${VG_NAME}/${LV_NAME}"
    echo "  Root device:     ${ROOT_SPEC}"
    echo "  Hostname:        ${HOSTNAME}"
    echo "  Username:        ${USERNAME}"
    echo "  Timezone:        ${TIMEZONE}"
    echo "  Release:         ${DEBIAN_RELEASE}"
    echo "  Target mount:    ${TARGET}"
    echo "  Dry run:         ${DRY_RUN}"
    echo "  APT format:      deb822"
    echo "  Log file:        ${LOG_FILE}"
    echo "  NVIDIA GPU:      ${NVIDIA_GPU_DETECTED}"
    echo "  NVIDIA install:  ${NVIDIA_INSTALL}"

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        echo "  Static IP:       enabled"
        echo "  Interface:       ${STATIC_INTERFACE}"
        echo "  Address:         ${IP_ADDRESS}"
        echo "  Gateway:         ${GATEWAY}"
        echo "  DNS:             ${DNS_SERVER}"
        echo "  Domain:          ${DOMAIN:-<none>}"
    else
        echo "  Static IP:       disabled (NetworkManager)"
    fi

    echo
    read -r -p "Type YES to continue: " answer
    [[ "$answer" == "YES" ]] || die "Aborted by user."
}

########################################
# Disk cleanup / storage preclean
########################################
cleanup_mounts() {
    INFO "Cleaning existing mounts..."
    cleanup_mounts_quiet
    SUCCESS "Mount cleanup complete"
}

stop_lvm_autoactivation() {
    INFO "Stopping LVM/device-mapper autoactivation services..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "  systemctl stop lvm2-monitor.service || true" | tee -a "$LOG_FILE"
        echo "  systemctl stop lvm2-lvmpolld.service || true" | tee -a "$LOG_FILE"
        echo "  systemctl stop dm-event.service || true" | tee -a "$LOG_FILE"
        echo "  systemctl stop dm-event.socket || true" | tee -a "$LOG_FILE"
        echo "  systemctl stop lvm2-lvmpolld.socket || true" | tee -a "$LOG_FILE"
        return 0
    fi

    systemctl stop lvm2-monitor.service 2>/dev/null || true
    systemctl stop lvm2-lvmpolld.service 2>/dev/null || true
    systemctl stop dm-event.service 2>/dev/null || true
    systemctl stop dm-event.socket 2>/dev/null || true
    systemctl stop lvm2-lvmpolld.socket 2>/dev/null || true
    SUCCESS "LVM/device-mapper autoactivation services stopped"
}

is_lv_active() {
    local attrs
    attrs="$(lvs --noheadings -o lv_attr "/dev/${VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -n "$attrs" && "${attrs:4:1}" == "a" ]]
}

preclean_storage_stack() {
    INFO "Pre-cleaning old storage mappings before repartitioning..."

    if [[ "$DRY_RUN" == true ]]; then
        echo "  umount -R ${TARGET} || true" | tee -a "$LOG_FILE"
        echo "  umount ${ROOT_SPEC} || true" | tee -a "$LOG_FILE"
        echo "  umount /dev/${VG_NAME}/${LV_NAME} || true" | tee -a "$LOG_FILE"
        echo "  umount ${LVM_PART} || true" | tee -a "$LOG_FILE"
        echo "  swapoff -a || true" | tee -a "$LOG_FILE"
        echo "  timeout 10 lvchange --config 'activation { udev_sync=0 udev_rules=0 }' -an -f /dev/${VG_NAME}/${LV_NAME} || true" | tee -a "$LOG_FILE"
        echo "  timeout 10 vgchange --config 'activation { udev_sync=0 udev_rules=0 }' -an ${VG_NAME} || true" | tee -a "$LOG_FILE"
        echo "  timeout 10 dmsetup remove -f ${DM_NAME} || true" | tee -a "$LOG_FILE"
        echo "  timeout 10 dmsetup remove_all -f || true" | tee -a "$LOG_FILE"
        echo "  lvremove -f /dev/${VG_NAME}/${LV_NAME} || true" | tee -a "$LOG_FILE"
        echo "  vgremove -f ${VG_NAME} || true" | tee -a "$LOG_FILE"
        echo "  # intentionally skipping pvremove on ${LVM_PART}" | tee -a "$LOG_FILE"
        return 0
    fi

    umount -R "$TARGET" >>"$LOG_FILE" 2>&1 || true
    umount "$ROOT_SPEC" >>"$LOG_FILE" 2>&1 || true
    umount "/dev/${VG_NAME}/${LV_NAME}" >>"$LOG_FILE" 2>&1 || true
    [[ -b "${LVM_PART:-}" ]] && umount "$LVM_PART" >>"$LOG_FILE" 2>&1 || true

    swapoff -a >>"$LOG_FILE" 2>&1 || true

    INFO "Deactivating logical volume if present..."
    timeout 10 lvchange --config 'activation { udev_sync=0 udev_rules=0 }' -an -f "/dev/${VG_NAME}/${LV_NAME}" >>"$LOG_FILE" 2>&1 || true

    INFO "Deactivating volume group if present..."
    timeout 10 vgchange --config 'activation { udev_sync=0 udev_rules=0 }' -an "$VG_NAME" >>"$LOG_FILE" 2>&1 || true

    INFO "Removing device-mapper nodes if present..."
    timeout 10 dmsetup remove -f "$DM_NAME" >>"$LOG_FILE" 2>&1 || true
    timeout 10 dmsetup remove_all -f >>"$LOG_FILE" 2>&1 || true

    if [[ -e "/dev/${VG_NAME}/${LV_NAME}" ]]; then
        INFO "Removing existing logical volume /dev/${VG_NAME}/${LV_NAME} if present..."
        lvremove -f "/dev/${VG_NAME}/${LV_NAME}" >>"$LOG_FILE" 2>&1 || true
    fi

    if vgdisplay "$VG_NAME" >/dev/null 2>&1; then
        INFO "Removing existing volume group ${VG_NAME} if present..."
        vgremove -f "$VG_NAME" >>"$LOG_FILE" 2>&1 || true
    fi

    if [[ -b "${LVM_PART:-}" ]]; then
        INFO "Skipping direct PV metadata removal on ${LVM_PART}; full disk wipe will clear old signatures."
    fi

    blockdev --rereadpt "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partx -u "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partprobe "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    udevadm settle >>"$LOG_FILE" 2>&1 || true
    sleep 2

    SUCCESS "Old storage mappings cleaned"
}

verify_lv_inactive_or_clean() {
    INFO "Verifying old logical volume is inactive..."
    if [[ "$DRY_RUN" == true ]]; then
        SUCCESS "Dry-run: skipping LVM activity verification"
        return 0
    fi

    if lvs "/dev/${VG_NAME}/${LV_NAME}" >/dev/null 2>&1; then
        if is_lv_active; then
            ERROR "Logical volume /dev/${VG_NAME}/${LV_NAME} is still active."
            ERROR "Reboot the Live ISO or manually deactivate it before rerunning."
            exit 1
        else
            SUCCESS "Existing logical volume metadata is present but inactive"
        fi
    else
        SUCCESS "No active logical volume remains"
    fi

    if dmsetup ls 2>/dev/null | grep -q "^${DM_NAME}\$"; then
        ERROR "Device-mapper node ${DM_NAME} is still present."
        ERROR "Reboot the Live ISO or manually remove the mapper before rerunning."
        exit 1
    fi

    SUCCESS "No active mapper device remains for ${DM_NAME}"
}

########################################
# Disk setup
########################################
partition_disk() {
    INFO "Partitioning disk..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "  1. GPT label" | tee -a "$LOG_FILE"
        echo "  2. ${EFI_PART}   1MiB -> 1025MiB   FAT32 EFI" | tee -a "$LOG_FILE"
        echo "  3. ${LVM_PART}   1025MiB -> 100%   LVM PV" | tee -a "$LOG_FILE"
        return 0
    fi

    run_visible "Wiping filesystem signatures on ${TARGET_DISK}" wipefs -af "$TARGET_DISK"
    run_visible "Zapping GPT/MBR metadata on ${TARGET_DISK}" sgdisk --zap-all "$TARGET_DISK"
    run_visible "Zeroing first 100 MiB of ${TARGET_DISK}" dd if=/dev/zero of="$TARGET_DISK" bs=1M count=100 status=progress

    INFO "Refreshing partition table after wipe..."
    blockdev --rereadpt "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partx -u "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partprobe "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    udevadm settle >>"$LOG_FILE" 2>&1 || true
    sleep 2
    SUCCESS "Partition table refresh after wipe complete"

    run "Creating GPT label on ${TARGET_DISK}" parted -s "$TARGET_DISK" mklabel gpt
    run "Creating EFI partition ${EFI_PART}" parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 1025MiB
    run "Setting EFI flag on ${EFI_PART}" parted -s "$TARGET_DISK" set 1 esp on
    run "Creating LVM partition ${LVM_PART}" parted -s "$TARGET_DISK" mkpart ROOT 1025MiB 100%
    run "Setting LVM flag on ${LVM_PART}" parted -s "$TARGET_DISK" set 2 lvm on

    INFO "Refreshing partition table after partition creation..."
    blockdev --rereadpt "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partx -u "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    partprobe "$TARGET_DISK" >>"$LOG_FILE" 2>&1 || true
    udevadm settle >>"$LOG_FILE" 2>&1 || true
    sleep 2
    SUCCESS "Partition table refresh after partition creation complete"

    [[ -b "$EFI_PART" ]] || die "EFI partition not found: $EFI_PART"
    [[ -b "$LVM_PART" ]] || die "LVM partition not found: $LVM_PART"
    SUCCESS "Disk partitioning complete for ${TARGET_DISK}"
}

create_lvm_root() {
    INFO "Creating LVM stack on ${LVM_PART}..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "  pvcreate ${LVM_PART}" | tee -a "$LOG_FILE"
        echo "  vgcreate ${VG_NAME} ${LVM_PART}" | tee -a "$LOG_FILE"
        echo "  lvcreate -n ${LV_NAME} -l 100%FREE ${VG_NAME}" | tee -a "$LOG_FILE"
        return 0
    fi

    run_visible "Creating physical volume on ${LVM_PART}" pvcreate -ff -y "$LVM_PART"
    run_visible "Creating volume group ${VG_NAME}" vgcreate "$VG_NAME" "$LVM_PART"
    run_visible "Creating logical volume ${LV_NAME}" lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"

    [[ -b "$ROOT_SPEC" ]] || die "Root logical volume not found: $ROOT_SPEC"
    SUCCESS "LVM root device ready: $ROOT_SPEC"
}

format_partitions() {
    INFO "Formatting partitions..."
    run_visible "Formatting EFI partition ${EFI_PART}" mkfs.vfat -F32 -n EFI "$EFI_PART"
    run_visible "Formatting root LV ${ROOT_SPEC} as Btrfs" mkfs.btrfs -f -L debian_root "$ROOT_SPEC"
}

########################################
# Btrfs layout
########################################
create_btrfs_subvolumes() {
    INFO "Creating Btrfs subvolumes on ${ROOT_SPEC}..."
    run "Creating target directory ${TARGET}" mkdir -p "$TARGET"
    run "Mounting ${ROOT_SPEC} temporarily at ${TARGET}" mount "$ROOT_SPEC" "$TARGET"

    run_visible "Creating subvolume @" btrfs subvolume create "$TARGET/@"
    run_visible "Creating subvolume @snapshots" btrfs subvolume create "$TARGET/@snapshots"
    run_visible "Creating subvolume @home" btrfs subvolume create "$TARGET/@home"
    run_visible "Creating subvolume @log" btrfs subvolume create "$TARGET/@log"
    run_visible "Creating subvolume @cache" btrfs subvolume create "$TARGET/@cache"
    run_visible "Creating subvolume @tmp" btrfs subvolume create "$TARGET/@tmp"
    run_visible "Creating subvolume @opt" btrfs subvolume create "$TARGET/@opt"

    run "Unmounting temporary root mount ${TARGET}" umount "$TARGET"
    SUCCESS "Btrfs subvolumes created on ${ROOT_SPEC}"
}

mount_target_layout_initial() {
    INFO "Mounting initial target layout under ${TARGET}..."
    INFO "Note: @snapshots is intentionally NOT mounted yet."

    run "Creating target directory ${TARGET}" mkdir -p "$TARGET"
    run "Mounting root subvolume @ on ${TARGET}" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@ "$ROOT_SPEC" "$TARGET"

    run "Creating target directories under ${TARGET}" mkdir -p \
        "$TARGET/boot/efi" \
        "$TARGET/home" \
        "$TARGET/var/log" \
        "$TARGET/var/cache" \
        "$TARGET/var/tmp" \
        "$TARGET/opt"

    run "Mounting @home on ${TARGET}/home" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@home "$ROOT_SPEC" "$TARGET/home"
    run "Mounting @log on ${TARGET}/var/log" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@log "$ROOT_SPEC" "$TARGET/var/log"
    run "Mounting @cache on ${TARGET}/var/cache" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@cache "$ROOT_SPEC" "$TARGET/var/cache"
    run "Mounting @tmp on ${TARGET}/var/tmp" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@tmp "$ROOT_SPEC" "$TARGET/var/tmp"
    run "Mounting @opt on ${TARGET}/opt" \
        mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@opt "$ROOT_SPEC" "$TARGET/opt"
    run "Mounting EFI partition ${EFI_PART} on ${TARGET}/boot/efi" mount "$EFI_PART" "$TARGET/boot/efi"

    mkdir -p "$TARGET/var/log"
    install -m 600 "$LOG_FILE" "$TARGET/var/log/debian13-bootstrap.log"
    SUCCESS "Initial target layout mounted"
}

########################################
# Base install
########################################
bootstrap_base_system() {
    run_visible "Bootstrapping Debian ${DEBIAN_RELEASE} into ${TARGET}" \
        debootstrap --arch amd64 "$DEBIAN_RELEASE" "$TARGET" http://deb.debian.org/debian
}

configure_base_files_initial() {
    INFO "Writing initial base system configuration..."
    [[ "$DRY_RUN" == true ]] && return 0

    echo "$HOSTNAME" > "$TARGET/etc/hostname"

    cat > "$TARGET/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME}

::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    rm -f "$TARGET/etc/apt/sources.list"
    mkdir -p "$TARGET/etc/apt/sources.list.d"

    cat > "$TARGET/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${DEBIAN_RELEASE} ${DEBIAN_RELEASE}-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${DEBIAN_RELEASE}-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    echo "LANG=en_US.UTF-8" > "$TARGET/etc/default/locale"
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "$TARGET/etc/localtime"

    install -m 600 "$LOG_FILE" "$TARGET/var/log/debian13-bootstrap.log"
    SUCCESS "Initial system files written"
}

########################################
# fstab — written from the outer script  (v4.3 FIX)
# Writing fstab here (outside the chroot heredoc) avoids variable
# interpolation issues that cause physical-server deployment failures.
########################################
write_fstab() {
    INFO "Writing /etc/fstab from outer script (v4.3 fix)..."
    [[ "$DRY_RUN" == true ]] && return 0

    cat > "$TARGET/etc/fstab" <<FSTAB_EOF
# /etc/fstab — generated by Debian13_BTRFS_Bootstrap_v${SCRIPT_VERSION}
# <device>         <mountpoint>   <type>  <options>                                                             <dump> <pass>
${ROOT_SPEC}       /              btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@           0 0
${ROOT_SPEC}       /.snapshots    btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@snapshots  0 0
${ROOT_SPEC}       /home          btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@home       0 0
${ROOT_SPEC}       /var/log       btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@log        0 0
${ROOT_SPEC}       /var/cache     btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@cache      0 0
${ROOT_SPEC}       /var/tmp       btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@tmp        0 0
${ROOT_SPEC}       /opt           btrfs   noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@opt        0 0
${EFI_PART}        /boot/efi      vfat    umask=0077                                                                  0 1
FSTAB_EOF

    SUCCESS "fstab written to ${TARGET}/etc/fstab"
    cat "$TARGET/etc/fstab" | tee -a "$LOG_FILE"
}

prepare_chroot() {
    INFO "Preparing chroot under ${TARGET}..."
    [[ "$DRY_RUN" == true ]] && return 0

    run "Mounting proc into ${TARGET}/proc" mount --types proc /proc "$TARGET/proc"
    run "Binding /sys into ${TARGET}/sys" mount --rbind /sys "$TARGET/sys"
    run "Marking ${TARGET}/sys rslave" mount --make-rslave "$TARGET/sys"
    run "Binding /dev into ${TARGET}/dev" mount --rbind /dev "$TARGET/dev"
    run "Marking ${TARGET}/dev rslave" mount --make-rslave "$TARGET/dev"
    run "Binding /run into ${TARGET}/run" mount --bind /run "$TARGET/run"
    run "Marking ${TARGET}/run slave" mount --make-slave "$TARGET/run"
    SUCCESS "Chroot prepared"
}

########################################
# Chroot scripts
########################################
write_chroot_scripts() {
    # Safely export booleans as strings for the chroot shell
    local _nvidia_install="${NVIDIA_INSTALL}"
    local _static_ip="${STATIC_IP_ENABLED}"

    cat > "$TARGET/root/bootstrap-chroot-noninteractive.sh" <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

exec >>/var/log/debian13-bootstrap.log 2>&1

HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
TIMEZONE="${TIMEZONE}"
ROOT_SPEC="${ROOT_SPEC}"
EFI_PART="${EFI_PART}"
STATIC_IP_ENABLED="${_static_ip}"
STATIC_INTERFACE="${STATIC_INTERFACE}"
IP_ADDRESS="${IP_ADDRESS}"
GATEWAY="${GATEWAY}"
DNS_SERVER="${DNS_SERVER}"
DOMAIN="${DOMAIN}"
NVIDIA_INSTALL="${_nvidia_install}"
CUSTOM_PS1=$(printf '%q' "$CUSTOM_PS1")
GRUB_BTRFS_REPO="${GRUB_BTRFS_REPO}"
GRUB_BTRFS_BRANCH="${GRUB_BTRFS_BRANCH}"

append_line_if_missing() {
    local file="\$1"
    local line="\$2"
    touch "\$file"
    grep -Fqx "\$line" "\$file" || echo "\$line" >> "\$file"
}

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    linux-image-amd64 \
    grub-efi-amd64 \
    efibootmgr \
    firmware-linux-free \
    firmware-misc-nonfree \
    btrfs-progs \
    snapper \
    duf \
    bat \
    fastfetch \
    sudo \
    locales \
    console-setup \
    keyboard-configuration \
    openssh-server \
    zram-tools \
    nano \
    vim \
    curl \
    wget \
    git \
    make \
    gawk \
    inotify-tools \
    qemu-guest-agent \
    lvm2

# NVIDIA driver installation (v4.3 NEW)
if [[ "\$NVIDIA_INSTALL" == "true" ]]; then
    echo "[INFO] Installing NVIDIA driver and firmware..." >>/var/log/debian13-bootstrap.log
    apt-get install -y \
        nvidia-driver \
        firmware-misc-nonfree \
        nvidia-kernel-dkms \
        linux-headers-amd64 || {
        echo "[WARN] NVIDIA driver installation encountered issues — continuing" >>/var/log/debian13-bootstrap.log
    }
fi

if [[ "\$STATIC_IP_ENABLED" == "true" ]]; then
    apt-get install -y ifupdown resolvconf
else
    apt-get install -y network-manager
fi

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

echo "\$HOSTNAME" > /etc/hostname

cat > /etc/default/zramswap <<'ZEOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
ZEOF

systemctl enable zramswap || true
systemctl enable ssh || true
systemctl enable qemu-guest-agent || true
systemctl start qemu-guest-agent || true

if grep -qE '^[#[:space:]]*PermitRootLogin' /etc/ssh/sshd_config; then
    sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
else
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
fi

systemctl restart ssh 2>/dev/null || true

if [[ "\$STATIC_IP_ENABLED" == "true" ]]; then
    systemctl disable NetworkManager 2>/dev/null || true
    systemctl stop NetworkManager 2>/dev/null || true

    cat > /etc/network/interfaces <<INTF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug \$STATIC_INTERFACE
iface \$STATIC_INTERFACE inet static
    address \$IP_ADDRESS
    gateway \$GATEWAY
    # dns-* options are implemented by the resolvconf package, if installed
    dns-nameservers \$DNS_SERVER
    dns-search \$DOMAIN
INTF

    systemctl enable networking || true
else
    systemctl enable NetworkManager || true
fi

append_line_if_missing /root/.bashrc "\$CUSTOM_PS1"

if ! id -u "\$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo "\$USERNAME"
fi

touch "/home/\$USERNAME/.bashrc"
chown "\$USERNAME:\$USERNAME" "/home/\$USERNAME/.bashrc"
append_line_if_missing "/home/\$USERNAME/.bashrc" "\$CUSTOM_PS1"

if mountpoint -q /.snapshots; then
    umount /.snapshots
fi
rm -rf /.snapshots

if ! snapper list-configs 2>/dev/null | awk '{print \$1}' | grep -qx root; then
    snapper --no-dbus -c root create-config /
fi

test -f /etc/snapper/configs/root

if mountpoint -q /.snapshots; then
    umount /.snapshots
fi

if btrfs subvolume show /.snapshots >/dev/null 2>&1; then
    btrfs subvolume delete /.snapshots
elif [[ -e /.snapshots ]]; then
    rm -rf /.snapshots
fi

mkdir -p /.snapshots
mount -o noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@snapshots "\$ROOT_SPEC" /.snapshots
chmod 750 /.snapshots || true
chown root:root /.snapshots || true

if ! snapper -c root list | awk 'NR>2 {print \$3}' | grep -qx "baseline-install"; then
    snapper -c root create --description "baseline-install" || true
fi

mountpoint -q /boot/efi || mount /boot/efi || true
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-floppy

rm -rf /usr/local/src/grub-btrfs
git clone --depth 1 --branch "\$GRUB_BTRFS_BRANCH" "\$GRUB_BTRFS_REPO" /usr/local/src/grub-btrfs
make -C /usr/local/src/grub-btrfs install

if [[ -f /etc/default/grub-btrfs/config ]]; then
    sed -i 's|^#\?GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/usr/sbin/grub-mkconfig|g' /etc/default/grub-btrfs/config || true
    sed -i 's|^#\?GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"|g' /etc/default/grub-btrfs/config || true
fi

if [[ -f /usr/lib/systemd/system/grub-btrfs.path ]]; then
    mkdir -p /etc/systemd/system/grub-btrfs.path.d
    cat > /etc/systemd/system/grub-btrfs.path.d/override.conf <<'OVEOF'
[Path]
PathModified=
PathModified=/.snapshots
PathChanged=
PathChanged=/.snapshots
OVEOF
fi

if [[ -f /usr/lib/systemd/system/grub-btrfsd.service ]]; then
    mkdir -p /etc/systemd/system/grub-btrfsd.service.d
    cat > /etc/systemd/system/grub-btrfsd.service.d/override.conf <<'OVEOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots
OVEOF
fi

systemctl daemon-reload || true

[[ -x /etc/grub.d/41_snapshots-btrfs ]] && /etc/grub.d/41_snapshots-btrfs || true
update-grub

systemctl enable grub-btrfs.path 2>/dev/null || true
systemctl enable grub-btrfsd.service 2>/dev/null || true

echo "[INFO] fstab was written by outer script (v4.3) — skipping chroot fstab write" >>/var/log/debian13-bootstrap.log
test -f /etc/fstab || { echo "[ERROR] /etc/fstab is missing!"; exit 1; }
grep -q "@snapshots" /etc/fstab || { echo "[ERROR] /etc/fstab does not contain @snapshots entry!"; exit 1; }

echo "[SUCCESS] Non-interactive chroot phase complete" >>/var/log/debian13-bootstrap.log
CHROOT_EOF

    cat > "$TARGET/root/bootstrap-chroot-interactive.sh" <<INTER_EOF
#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME}"

echo
echo "======================================"
echo " Interactive password configuration"
echo "======================================"
echo

echo "Set root password:"
passwd root

echo
echo "Set password for ${USERNAME}:"
passwd "${USERNAME}"

echo
echo "Password configuration complete."
INTER_EOF

    chmod +x "$TARGET/root/bootstrap-chroot-noninteractive.sh"
    chmod +x "$TARGET/root/bootstrap-chroot-interactive.sh"
}

run_chroot_config() {
    INFO "Running chroot configuration..."
    [[ "$DRY_RUN" == true ]] && return 0

    write_chroot_scripts

    run_visible "Running non-interactive chroot setup in ${TARGET}" \
        chroot "$TARGET" /usr/bin/env bash /root/bootstrap-chroot-noninteractive.sh

    INFO "Launching interactive password setup..."
    INFO "Password prompts will appear directly on your terminal."

    echo "[INFO] Starting interactive password phase" >>"$LOG_FILE"

    chroot "$TARGET" /usr/bin/env TERM="${TERM:-linux}" HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash /root/bootstrap-chroot-interactive.sh < /dev/tty > /dev/tty 2> /dev/tty

    echo "[SUCCESS] Interactive password phase completed" >>"$LOG_FILE"
    SUCCESS "Interactive password setup complete"

    rm -f "$TARGET/root/bootstrap-chroot-noninteractive.sh"
    rm -f "$TARGET/root/bootstrap-chroot-interactive.sh"
    SUCCESS "Chroot configuration complete"
}

########################################
# Validation / summary
########################################
post_install_validation() {
    INFO "Running post-install validation..."
    [[ "$DRY_RUN" == true ]] && return 0

    test -f "$TARGET/var/log/debian13-bootstrap.log"  && SUCCESS "Installed system log file present"  || WARN "Installed system log file missing"
    test -f "$TARGET/etc/apt/sources.list.d/debian.sources" && SUCCESS "deb822 sources present"        || WARN "deb822 sources missing"
    grep -Fq "$ROOT_SPEC /" "$TARGET/etc/fstab"        && SUCCESS "fstab uses $ROOT_SPEC"             || WARN "fstab does not reference $ROOT_SPEC"
    grep -Fq "@snapshots" "$TARGET/etc/fstab"          && SUCCESS "fstab contains @snapshots entry"   || WARN "fstab @snapshots entry missing"
    grep -Fq "@home"      "$TARGET/etc/fstab"          && SUCCESS "fstab contains @home entry"        || WARN "fstab @home entry missing"
    test -f "$TARGET/root/.bashrc" && grep -Fq "export PS1=" "$TARGET/root/.bashrc" \
                                                       && SUCCESS "Root .bashrc prompt configured"     || WARN "Root .bashrc prompt missing"
    test -f "$TARGET/home/$USERNAME/.bashrc" && grep -Fq "export PS1=" "$TARGET/home/$USERNAME/.bashrc" \
                                                       && SUCCESS "User .bashrc prompt configured"     || WARN "User .bashrc prompt missing"
    test -f "$TARGET/boot/grub/grub.cfg"               && SUCCESS "GRUB config exists"                || WARN "GRUB config missing"
    test -f "$TARGET/boot/grub/grub-btrfs.cfg"         && SUCCESS "grub-btrfs.cfg exists"            || WARN "grub-btrfs.cfg missing (may appear after first usable snapshot/boot)"

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        test -f "$TARGET/etc/network/interfaces"       && SUCCESS "Static IP interfaces file created" || WARN "Static IP interfaces file missing"
    fi

    if [[ "$NVIDIA_INSTALL" == true ]]; then
        local nvidia_mod
        nvidia_mod="$(find "$TARGET/lib/modules" -name "nvidia.ko" -o -name "nvidia.ko.xz" 2>/dev/null | head -1 || true)"
        if [[ -n "$nvidia_mod" ]]; then
            SUCCESS "NVIDIA kernel module found: $nvidia_mod"
        else
            WARN "NVIDIA kernel module not found — check chroot log for nvidia-driver install errors"
        fi
    fi
}

show_summary() {
    INFO "Installation summary"
    echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "Script version:    ${SCRIPT_VERSION}" | tee -a "$LOG_FILE"
    echo "Disk:              $TARGET_DISK" | tee -a "$LOG_FILE"
    echo "EFI partition:     $EFI_PART" | tee -a "$LOG_FILE"
    echo "LVM partition:     $LVM_PART" | tee -a "$LOG_FILE"
    echo "Root device:       $ROOT_SPEC" | tee -a "$LOG_FILE"
    echo "Target:            $TARGET" | tee -a "$LOG_FILE"
    echo "Hostname:          $HOSTNAME" | tee -a "$LOG_FILE"
    echo "Username:          $USERNAME" | tee -a "$LOG_FILE"
    echo "Timezone:          $TIMEZONE" | tee -a "$LOG_FILE"
    echo "Release:           $DEBIAN_RELEASE" | tee -a "$LOG_FILE"
    echo "Log file:          $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Installed log:     $TARGET/var/log/debian13-bootstrap.log" | tee -a "$LOG_FILE"
    echo "Dry run:           $DRY_RUN" | tee -a "$LOG_FILE"
    echo "NVIDIA GPU:        $NVIDIA_GPU_DETECTED" | tee -a "$LOG_FILE"
    echo "NVIDIA install:    $NVIDIA_INSTALL" | tee -a "$LOG_FILE"
    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        echo "Static IP:         enabled" | tee -a "$LOG_FILE"
        echo "Interface:         $STATIC_INTERFACE" | tee -a "$LOG_FILE"
        echo "Address:           $IP_ADDRESS" | tee -a "$LOG_FILE"
        echo "Gateway:           $GATEWAY" | tee -a "$LOG_FILE"
        echo "DNS:               $DNS_SERVER" | tee -a "$LOG_FILE"
        echo "Domain:            ${DOMAIN:-<none>}" | tee -a "$LOG_FILE"
    else
        echo "Static IP:         disabled" | tee -a "$LOG_FILE"
    fi
    echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
}

finish_message() {
    local end_epoch elapsed
    end_epoch="$(date +%s)"
    elapsed="$((end_epoch - START_EPOCH))"

    echo
    SUCCESS "Bootstrap v${SCRIPT_VERSION} completed"
    SUCCESS "Elapsed time: $(format_duration "$elapsed")"
    echo
    echo "Recommended checks before reboot:"
    echo "  lsblk -f"
    echo "  pvs"
    echo "  vgs"
    echo "  lvs"
    echo "  cat $TARGET/etc/fstab"
    echo "  cat $TARGET/etc/apt/sources.list.d/debian.sources"
    echo "  tail -100 $TARGET/var/log/debian13-bootstrap.log"
    echo "  chroot $TARGET snapper list-configs"
    echo "  chroot $TARGET snapper -c root list"
    echo "  chroot $TARGET findmnt /.snapshots"
    echo
    echo "After first boot:"
    echo "  sudo systemctl enable grub-btrfs.path 2>/dev/null || true"
    echo "  sudo systemctl start grub-btrfs.path 2>/dev/null || true"
    echo "  sudo systemctl enable grub-btrfsd.service 2>/dev/null || true"
    echo "  sudo systemctl start grub-btrfsd.service 2>/dev/null || true"
    echo "  sudo snapper -c root create --description 'post-boot-test'"
    echo "  sudo /etc/grub.d/41_snapshots-btrfs"
    echo "  sudo update-grub"
    echo
    if [[ "$NVIDIA_INSTALL" == true ]]; then
        echo "NVIDIA post-boot checks:"
        echo "  nvidia-smi"
        echo "  lsmod | grep nvidia"
        echo
    fi
    echo "Then reboot and remove the Live ISO/DVD."
    echo
}

########################################
# Main
########################################
main() {
    parse_args "$@"
    require_root
    require_timeout
    init_log

    # v4.3: run detection before interactive prompts so detected values
    # can be shown as defaults in the prompt
    detect_nvidia_gpu
    auto_detect_network

    check_uefi
    check_connectivity
    install_live_dependencies
    detect_disks

    # v4.3: interactive prompt gathers only what is still missing
    interactive_prompt

    preflight_summary
    set_partition_names
    detect_active_interface
    confirm_plan
    cleanup_mounts
    stop_lvm_autoactivation
    preclean_storage_stack
    verify_lv_inactive_or_clean
    partition_disk
    create_lvm_root

    if [[ "$DRY_RUN" == true ]]; then
        show_summary
        INFO "Dry-run completed. No changes were made."
        exit 0
    fi

    format_partitions
    create_btrfs_subvolumes
    mount_target_layout_initial
    bootstrap_base_system
    configure_base_files_initial

    # v4.3 FIX: write fstab from the outer script before entering chroot
    # This avoids heredoc variable interpolation problems on physical servers
    write_fstab

    prepare_chroot
    run_chroot_config
    post_install_validation
    show_summary
    finish_message
}

main "$@"