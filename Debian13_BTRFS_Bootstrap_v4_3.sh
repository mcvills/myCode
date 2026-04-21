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
#
# WARNING: This script DESTROYS all data on the selected disk.

set -euo pipefail
IFS=$'\n\t'

START_EPOCH="$(date +%s)"

########################################
# Defaults
########################################
DEBIAN_RELEASE="trixie"
TIMEZONE="America/Chicago"
HOSTNAME="debian13"
USERNAME=""
TARGET="/target"
LOG_FILE="/var/log/debian13-bootstrap.log"
PING_IP="1.1.1.1"
PING_DNS="deb.debian.org"
DRY_RUN=false
TARGET_DISK=""
SCRIPT_NAME="$(basename "$0")"

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

# Detected environment
SYSTEM_TYPE="unknown"
ACTIVE_INTERFACE=""
ACTIVE_INTERFACE_NAME=""
ACTIVE_IP_ADDRESS=""
ACTIVE_CIDR=""
ACTIVE_GATEWAY=""
ACTIVE_DNS_SERVERS=""
ACTIVE_SEARCH_DOMAIN=""
NVIDIA_GPU_PRESENT=false
NVIDIA_GPU_MODEL=""

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
  --help                    Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --disk) TARGET_DISK="$2"; shift 2 ;;
            --hostname) HOSTNAME="$2"; shift 2 ;;
            --username) USERNAME="$2"; shift 2 ;;
            --timezone) TIMEZONE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --static-ip) STATIC_IP_ENABLED=true; shift ;;
            --interface) STATIC_INTERFACE="$2"; shift 2 ;;
            --ip-address) IP_ADDRESS="$2"; shift 2 ;;
            --gateway) GATEWAY="$2"; shift 2 ;;
            --dns-server) DNS_SERVER="$2"; shift 2 ;;
            --domain) DOMAIN="$2"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

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

get_default_username() {
    local candidate=""

    candidate="${SUDO_USER:-}"
    if [[ -n "$candidate" && "$candidate" != "root" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    candidate="$(logname 2>/dev/null || true)"
    if [[ -n "$candidate" && "$candidate" != "root" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    printf 'sysadmin'
}

prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local reply=""

    if [[ -n "$default_value" ]]; then
        read -r -p "${prompt_text} [${default_value}]: " reply
        printf '%s' "${reply:-$default_value}"
    else
        read -r -p "${prompt_text}: " reply
        printf '%s' "$reply"
    fi
}

preflight_summary() {
    INFO "Preflight summary"
    echo "  Live kernel:     $(uname -r)" | tee -a "$LOG_FILE"
    echo "  Architecture:    $(uname -m)" | tee -a "$LOG_FILE"
    echo "  Memory:          $(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)" | tee -a "$LOG_FILE"
    echo "  System type:     ${SYSTEM_TYPE}" | tee -a "$LOG_FILE"
    echo "  Target disk:     ${TARGET_DISK:-<not selected yet>}" | tee -a "$LOG_FILE"
    echo "  Active iface:    ${ACTIVE_INTERFACE:-<not detected>}" | tee -a "$LOG_FILE"
    echo "  Interface desc:  ${ACTIVE_INTERFACE_NAME:-<not detected>}" | tee -a "$LOG_FILE"
    echo "  Active CIDR:     ${ACTIVE_CIDR:-<not detected>}" | tee -a "$LOG_FILE"
    echo "  Active gateway:  ${ACTIVE_GATEWAY:-<not detected>}" | tee -a "$LOG_FILE"
    echo "  Active DNS:      ${ACTIVE_DNS_SERVERS:-<not detected>}" | tee -a "$LOG_FILE"
    echo "  Search domain:   ${ACTIVE_SEARCH_DOMAIN:-<not detected>}" | tee -a "$LOG_FILE"
    if [[ "$NVIDIA_GPU_PRESENT" == true ]]; then
        echo "  NVIDIA GPU:      ${NVIDIA_GPU_MODEL}" | tee -a "$LOG_FILE"
    else
        echo "  NVIDIA GPU:      not detected" | tee -a "$LOG_FILE"
    fi
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
        blockdev partx systemctl timeout ip lspci hostnamectl resolvectl
    do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]})); then
        WARN "Missing commands detected: ${missing[*]}"
        run_visible "Running apt-get update in live environment" apt-get update
        run_visible "Installing live environment dependencies" \
            apt-get install -y \
            parted dosfstools btrfs-progs debootstrap arch-install-scripts \
            gdisk efibootmgr git make lvm2 util-linux coreutils systemd pciutils iproute2
    else
        SUCCESS "Required live-environment tools already available"
    fi
}

########################################
# Disk / network detection
########################################
detect_system_context() {
    INFO "Detecting live environment context..."

    if systemd-detect-virt -q; then
        SYSTEM_TYPE="virtual"
    else
        SYSTEM_TYPE="physical"
    fi

    ACTIVE_INTERFACE="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"

    if [[ -n "$ACTIVE_INTERFACE" ]]; then
        ACTIVE_CIDR="$(ip -o -4 addr show dev "$ACTIVE_INTERFACE" scope global | awk '{print $4; exit}' || true)"
        ACTIVE_IP_ADDRESS="${ACTIVE_CIDR%%/*}"
        ACTIVE_GATEWAY="$(ip route | awk '/^default/ {print $3; exit}' || true)"
        ACTIVE_INTERFACE_NAME="$(cat "/sys/class/net/${ACTIVE_INTERFACE}/ifalias" 2>/dev/null || true)"
        [[ -n "$ACTIVE_INTERFACE_NAME" ]] || ACTIVE_INTERFACE_NAME="$(basename "$(readlink -f "/sys/class/net/${ACTIVE_INTERFACE}/device/driver" 2>/dev/null || echo "$ACTIVE_INTERFACE")")"
        [[ "$ACTIVE_INTERFACE_NAME" == "$ACTIVE_INTERFACE" ]] && ACTIVE_INTERFACE_NAME="$(cat "/sys/class/net/${ACTIVE_INTERFACE}/device/modalias" 2>/dev/null || true)"
        [[ -n "$ACTIVE_INTERFACE_NAME" ]] || ACTIVE_INTERFACE_NAME="$ACTIVE_INTERFACE"
    fi

    if command -v resolvectl >/dev/null 2>&1 && [[ -n "$ACTIVE_INTERFACE" ]]; then
        ACTIVE_DNS_SERVERS="$(resolvectl dns "$ACTIVE_INTERFACE" 2>/dev/null | sed 's/^.*: //' | xargs echo -n || true)"
        ACTIVE_SEARCH_DOMAIN="$(resolvectl domain "$ACTIVE_INTERFACE" 2>/dev/null | sed 's/^.*: //' | xargs echo -n || true)"
    fi

    if [[ -z "$ACTIVE_DNS_SERVERS" && -f /etc/resolv.conf ]]; then
        ACTIVE_DNS_SERVERS="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | xargs echo -n || true)"
    fi

    if [[ -z "$ACTIVE_SEARCH_DOMAIN" && -f /etc/resolv.conf ]]; then
        ACTIVE_SEARCH_DOMAIN="$(awk '/^(search|domain)/ {for(i=2;i<=NF;i++) print $i}' /etc/resolv.conf | xargs echo -n || true)"
    fi

    if command -v lspci >/dev/null 2>&1; then
        NVIDIA_GPU_MODEL="$(lspci 2>/dev/null | grep -i 'nvidia' | head -n1 | sed 's/^[^:]*: //' || true)"
        if [[ -n "$NVIDIA_GPU_MODEL" ]]; then
            NVIDIA_GPU_PRESENT=true
        fi
    fi

    [[ -n "$HOSTNAME" && "$HOSTNAME" != "debian13" ]] || HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || echo debian13)"
    [[ -n "$HOSTNAME" && "$HOSTNAME" != "(none)" ]] || HOSTNAME="debian13"
    [[ -n "$USERNAME" ]] || USERNAME="$(get_default_username)"

    SUCCESS "Live environment detection complete"
}

collect_install_preferences() {
    INFO "Reviewing detected defaults for hostname, username, and network..."

    if [[ -z "$HOSTNAME" || "$HOSTNAME" == "localhost" || "$HOSTNAME" == "debian" ]]; then
        HOSTNAME="debian13"
    fi

    if [[ -z "$USERNAME" || "$USERNAME" == "root" ]]; then
        USERNAME="$(get_default_username)"
    fi

    if [[ -t 0 ]]; then
        HOSTNAME="$(prompt_with_default "Hostname" "$HOSTNAME")"
        USERNAME="$(prompt_with_default "Admin username" "$USERNAME")"

        if [[ "$STATIC_IP_ENABLED" != true ]]; then
            local use_static=""
            if [[ -n "$ACTIVE_CIDR" && -n "$ACTIVE_GATEWAY" ]]; then
                read -r -p "Configure static IP using detected live values? [y/N]: " use_static
                if [[ "$use_static" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    STATIC_IP_ENABLED=true
                fi
            fi
        fi
    fi

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        [[ -n "$STATIC_INTERFACE" ]] || STATIC_INTERFACE="$ACTIVE_INTERFACE"
        [[ -n "$IP_ADDRESS" ]] || IP_ADDRESS="$ACTIVE_CIDR"
        [[ -n "$GATEWAY" ]] || GATEWAY="$ACTIVE_GATEWAY"
        [[ -n "$DNS_SERVER" ]] || DNS_SERVER="$ACTIVE_DNS_SERVERS"
        [[ -n "$DOMAIN" ]] || DOMAIN="$ACTIVE_SEARCH_DOMAIN"

        if [[ -t 0 ]]; then
            STATIC_INTERFACE="$(prompt_with_default "Static interface" "$STATIC_INTERFACE")"
            IP_ADDRESS="$(prompt_with_default "Static IP/CIDR" "$IP_ADDRESS")"
            GATEWAY="$(prompt_with_default "Gateway" "$GATEWAY")"
            DNS_SERVER="$(prompt_with_default "DNS server(s)" "$DNS_SERVER")"
            DOMAIN="$(prompt_with_default "Search domain" "$DOMAIN")"
        fi
    fi

    [[ -n "$HOSTNAME" ]] || die "Hostname cannot be empty"
    [[ -n "$USERNAME" ]] || die "Username cannot be empty"

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        [[ -n "$STATIC_INTERFACE" && -n "$IP_ADDRESS" && -n "$GATEWAY" && -n "$DNS_SERVER" ]] || \
            die "Static IP mode requires interface, IP address, gateway, and DNS server"
    fi
}

detect_disks() {
    INFO "Available disks:"
    lsblk -d -e7 -o NAME,SIZE,MODEL,TYPE | tee -a "$LOG_FILE"

    if [[ -z "$TARGET_DISK" ]]; then
        mapfile -t disks < <(lsblk -d -n -e7 -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
        [[ ${#disks[@]} -gt 0 ]] || die "No target disks found."

        echo
        local i=1
        for d in "${disks[@]}"; do
            echo "[$i] $d"
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

    INFO "Detecting network interface..."

    if [[ -n "$ACTIVE_INTERFACE" ]]; then
        STATIC_INTERFACE="$ACTIVE_INTERFACE"
        SUCCESS "Detected active interface: $STATIC_INTERFACE"
        return 0
    fi

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
    echo "  Disk:            ${TARGET_DISK}"
    echo "  EFI:             ${EFI_PART} (1 GiB FAT32)"
    echo "  LVM PV:          ${LVM_PART}"
    echo "  VG/LV:           ${VG_NAME}/${LV_NAME}"
    echo "  Root device:     ${ROOT_SPEC}"
    echo "  Hostname:        ${HOSTNAME}"
    echo "  Username:        ${USERNAME}"
    echo "  System type:     ${SYSTEM_TYPE}"
    echo "  Live iface:      ${ACTIVE_INTERFACE:-<not detected>}"
    echo "  Live iface desc: ${ACTIVE_INTERFACE_NAME:-<not detected>}"
    echo "  Live IP/CIDR:    ${ACTIVE_CIDR:-<not detected>}"
    echo "  Live gateway:    ${ACTIVE_GATEWAY:-<not detected>}"
    echo "  Timezone:        ${TIMEZONE}"
    echo "  Release:         ${DEBIAN_RELEASE}"
    echo "  Target mount:    ${TARGET}"
    echo "  Dry run:         ${DRY_RUN}"
    echo "  APT format:      deb822"
    echo "  Log file:        ${LOG_FILE}"
    if [[ "$NVIDIA_GPU_PRESENT" == true ]]; then
        echo "  NVIDIA GPU:      ${NVIDIA_GPU_MODEL}"
    else
        echo "  NVIDIA GPU:      not detected"
    fi

    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        echo "  Static IP:       enabled"
        echo "  Interface:       ${STATIC_INTERFACE}"
        echo "  Address:         ${IP_ADDRESS}"
        echo "  Gateway:         ${GATEWAY}"
        echo "  DNS:             ${DNS_SERVER}"
        echo "  Domain:          ${DOMAIN:-<none>}"
    else
        echo "  Static IP:       disabled"
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

write_target_fstab() {
    INFO "Writing target /etc/fstab from host environment..."
    [[ "$DRY_RUN" == true ]] && return 0

    mkdir -p "$TARGET/etc"
    cat > "$TARGET/etc/fstab" <<EOF
${ROOT_SPEC} /           btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@           0 0
${ROOT_SPEC} /.snapshots btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@snapshots  0 0
${ROOT_SPEC} /home       btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@home       0 0
${ROOT_SPEC} /var/log    btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@log        0 0
${ROOT_SPEC} /var/cache  btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@cache      0 0
${ROOT_SPEC} /var/tmp    btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@tmp        0 0
${ROOT_SPEC} /opt        btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@opt        0 0
${EFI_PART}  /boot/efi   vfat   umask=0077                                                                  0 1
EOF

    SUCCESS "Target /etc/fstab written"
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
    cat > "$TARGET/root/bootstrap-chroot-noninteractive.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

exec >>/var/log/debian13-bootstrap.log 2>&1

HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
TIMEZONE="${TIMEZONE}"
ROOT_SPEC="${ROOT_SPEC}"
EFI_PART="${EFI_PART}"
STATIC_IP_ENABLED="${STATIC_IP_ENABLED}"
STATIC_INTERFACE="${STATIC_INTERFACE}"
IP_ADDRESS="${IP_ADDRESS}"
GATEWAY="${GATEWAY}"
DNS_SERVER="${DNS_SERVER}"
DOMAIN="${DOMAIN}"
CUSTOM_PS1=$(printf '%q' "$CUSTOM_PS1")
GRUB_BTRFS_REPO="${GRUB_BTRFS_REPO}"
GRUB_BTRFS_BRANCH="${GRUB_BTRFS_BRANCH}"
NVIDIA_GPU_PRESENT="${NVIDIA_GPU_PRESENT}"
NVIDIA_GPU_MODEL="${NVIDIA_GPU_MODEL}"
CHROOT_SUCCESS_FILE="/root/bootstrap-chroot-noninteractive.done"

chroot_error() {
    local line="$1"
    echo "[ERROR] Non-interactive chroot failed at line \${line}"
    exit 1
}
trap 'chroot_error \$LINENO' ERR

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

if [[ "\$NVIDIA_GPU_PRESENT" == "true" ]]; then
    echo "[INFO] NVIDIA GPU detected: \$NVIDIA_GPU_MODEL"
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

append_line_if_missing /root/.bashrc "$CUSTOM_PS1"

if ! id -u "\$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo "\$USERNAME"
fi

touch "/home/\$USERNAME/.bashrc"
chown "\$USERNAME:\$USERNAME" "/home/\$USERNAME/.bashrc"
append_line_if_missing "/home/\$USERNAME/.bashrc" "$CUSTOM_PS1"

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
    sed -i 's|^#\\?GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/usr/sbin/grub-mkconfig|g' /etc/default/grub-btrfs/config || true
    sed -i 's|^#\\?GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"|g' /etc/default/grub-btrfs/config || true
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

cat > /etc/fstab <<FEOF
${ROOT_SPEC} /           btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@           0 0
${ROOT_SPEC} /.snapshots btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@snapshots  0 0
${ROOT_SPEC} /home       btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@home       0 0
${ROOT_SPEC} /var/log    btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@log        0 0
${ROOT_SPEC} /var/cache  btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@cache      0 0
${ROOT_SPEC} /var/tmp    btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@tmp        0 0
${ROOT_SPEC} /opt        btrfs  noatime,space_cache=v2,compress=zstd:1,ssd,discard=async,subvol=@opt        0 0
${EFI_PART}  /boot/efi   vfat   umask=0077                                                                  0 1
FEOF

test -f /var/log/debian13-bootstrap.log || touch /var/log/debian13-bootstrap.log
touch "\$CHROOT_SUCCESS_FILE"
EOF

    cat > "$TARGET/root/bootstrap-chroot-interactive.sh" <<EOF
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
EOF

    chmod +x "$TARGET/root/bootstrap-chroot-noninteractive.sh"
    chmod +x "$TARGET/root/bootstrap-chroot-interactive.sh"
}

run_chroot_config() {
    INFO "Running chroot configuration..."
    [[ "$DRY_RUN" == true ]] && return 0

    write_chroot_scripts

    run_visible "Running non-interactive chroot setup in ${TARGET}" \
        chroot "$TARGET" /usr/bin/env bash /root/bootstrap-chroot-noninteractive.sh

    [[ -f "$TARGET/root/bootstrap-chroot-noninteractive.done" ]] || die "Non-interactive chroot did not complete successfully."
    SUCCESS "Non-interactive chroot setup complete"

    INFO "Launching interactive password setup..."
    INFO "Password prompts will appear directly on your terminal."

    echo "[INFO] Starting interactive password phase" >>"$LOG_FILE"

    chroot "$TARGET" /usr/bin/env TERM="${TERM:-linux}" HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash /root/bootstrap-chroot-interactive.sh < /dev/tty > /dev/tty 2> /dev/tty

    echo "[SUCCESS] Interactive password phase completed" >>"$LOG_FILE"
    SUCCESS "Interactive password setup complete"

    rm -f "$TARGET/root/bootstrap-chroot-noninteractive.sh"
    rm -f "$TARGET/root/bootstrap-chroot-noninteractive.done"
    rm -f "$TARGET/root/bootstrap-chroot-interactive.sh"
    SUCCESS "Chroot configuration complete"
}

########################################
# Validation / summary
########################################
post_install_validation() {
    INFO "Running post-install validation..."
    [[ "$DRY_RUN" == true ]] && return 0

    test -f "$TARGET/var/log/debian13-bootstrap.log" && SUCCESS "Installed system log file present" || WARN "Installed system log file missing"
    test -f "$TARGET/etc/apt/sources.list.d/debian.sources" && SUCCESS "deb822 sources present" || WARN "deb822 sources missing"
    grep -Fq "$ROOT_SPEC /" "$TARGET/etc/fstab" && SUCCESS "fstab uses $ROOT_SPEC" || WARN "fstab does not reference $ROOT_SPEC"
    test -f "$TARGET/root/.bashrc" && grep -Fq "export PS1=" "$TARGET/root/.bashrc" && SUCCESS "Root .bashrc prompt configured" || WARN "Root .bashrc prompt missing"
    test -f "$TARGET/home/$USERNAME/.bashrc" && grep -Fq "export PS1=" "$TARGET/home/$USERNAME/.bashrc" && SUCCESS "User .bashrc prompt configured" || WARN "User .bashrc prompt missing"
    test -f "$TARGET/boot/grub/grub.cfg" && SUCCESS "GRUB config exists" || WARN "GRUB config missing"
    test -f "$TARGET/boot/grub/grub-btrfs.cfg" && SUCCESS "grub-btrfs.cfg exists" || WARN "grub-btrfs.cfg missing (may appear after first usable snapshot/boot)"
    if [[ "$STATIC_IP_ENABLED" == true ]]; then
        test -f "$TARGET/etc/network/interfaces" && SUCCESS "Static IP interfaces file created" || WARN "Static IP interfaces file missing"
    fi
}

show_summary() {
    INFO "Installation summary"
    echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "Disk:              $TARGET_DISK" | tee -a "$LOG_FILE"
    echo "EFI partition:     $EFI_PART" | tee -a "$LOG_FILE"
    echo "LVM partition:     $LVM_PART" | tee -a "$LOG_FILE"
    echo "Root device:       $ROOT_SPEC" | tee -a "$LOG_FILE"
    echo "Target:            $TARGET" | tee -a "$LOG_FILE"
    echo "Hostname:          $HOSTNAME" | tee -a "$LOG_FILE"
    echo "Username:          $USERNAME" | tee -a "$LOG_FILE"
    echo "Timezone:          $TIMEZONE" | tee -a "$LOG_FILE"
    echo "Release:           $DEBIAN_RELEASE" | tee -a "$LOG_FILE"
    echo "System type:       $SYSTEM_TYPE" | tee -a "$LOG_FILE"
    echo "Live interface:    ${ACTIVE_INTERFACE:-<not detected>}" | tee -a "$LOG_FILE"
    echo "Interface desc:    ${ACTIVE_INTERFACE_NAME:-<not detected>}" | tee -a "$LOG_FILE"
    echo "Live IP/CIDR:      ${ACTIVE_CIDR:-<not detected>}" | tee -a "$LOG_FILE"
    echo "Live gateway:      ${ACTIVE_GATEWAY:-<not detected>}" | tee -a "$LOG_FILE"
    echo "Live DNS:          ${ACTIVE_DNS_SERVERS:-<not detected>}" | tee -a "$LOG_FILE"
    echo "Log file:          $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Installed log:     $TARGET/var/log/debian13-bootstrap.log" | tee -a "$LOG_FILE"
    echo "Dry run:           $DRY_RUN" | tee -a "$LOG_FILE"
    if [[ "$NVIDIA_GPU_PRESENT" == true ]]; then
        echo "NVIDIA GPU:        $NVIDIA_GPU_MODEL" | tee -a "$LOG_FILE"
    else
        echo "NVIDIA GPU:        not detected" | tee -a "$LOG_FILE"
    fi
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
    SUCCESS "Bootstrap completed"
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
    check_uefi
    check_connectivity
    install_live_dependencies
    detect_system_context
    detect_disks
    collect_install_preferences
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
    write_target_fstab
    prepare_chroot
    run_chroot_config
    post_install_validation
    show_summary
    finish_message
}

main "$@"
