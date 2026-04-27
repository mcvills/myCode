#!/usr/bin/env bash
# test-vm.sh — Build and boot this config in a QEMU VM (no real hardware needed)
# Useful for validating changes before applying to real XPS 9500
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_RAM="${VM_RAM:-4096}"     # MiB
VM_CORES="${VM_CORES:-4}"

info "Building NixOS VM from flake..."
nix build "$FLAKE_DIR#nixosConfigurations.xps9500.config.system.build.vm" \
  --show-trace \
  -o /tmp/nixos-xps-vm

success "VM built. Starting QEMU..."
info "RAM: ${VM_RAM}MiB | Cores: ${VM_CORES}"
info "Close QEMU window or press Ctrl-A X to exit"

QEMU_OPTS="-m ${VM_RAM} -smp ${VM_CORES} -enable-kvm"

# Disable NVIDIA in VM (no GPU passthrough)
export NIXOS_QEMU_OPTS="$QEMU_OPTS"

/tmp/nixos-xps-vm/bin/run-*-vm
