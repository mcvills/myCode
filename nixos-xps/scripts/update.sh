#!/usr/bin/env bash
# update.sh — Update all flake inputs and rebuild
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

FLAKE_DIR="${FLAKE_DIR:-/etc/nixos}"
HOSTNAME="${HOSTNAME:-$(hostname)}"

header() { echo -e "\n${BLUE}━━━ $* ━━━${RESET}\n"; }

header "NixOS Flake Update"

info "Updating flake inputs..."
nix flake update "$FLAKE_DIR" 2>&1 | grep -E "Updated|unchanged|error" || true

header "Building new configuration"
info "Building $HOSTNAME (showing diff)..."

# nh (nix helper) shows a nice diff and handles the switch
if command -v nh &>/dev/null; then
  sudo nh os switch --hostname "$HOSTNAME" "$FLAKE_DIR"
else
  # Fallback to plain nixos-rebuild
  sudo nixos-rebuild switch \
    --flake "$FLAKE_DIR#$HOSTNAME" \
    --show-trace \
    |& nix run nixpkgs#nix-output-monitor
fi

success "System updated!"

# Show generation diff
header "Generation Diff"
nvd diff \
  "$(ls -d /nix/var/nix/profiles/system-*-link | sort -V | tail -2 | head -1)" \
  "$(ls -d /nix/var/nix/profiles/system-*-link | sort -V | tail -1)" \
  2>/dev/null || true

echo ""
info "Snapper pre-post snapshot created automatically by systemd service"
info "View snapshots: snapper -c root list"
