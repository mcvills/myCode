#!/usr/bin/env bash
# post-boot-setup.sh — Run once after first boot as your user
# Installs things that can't be done during nixos-install (Flatpak, etc.)
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

header() { echo -e "\n${BLUE}━━━ $* ━━━${RESET}\n"; }

# Must NOT be root
[[ $EUID -ne 0 ]] || { echo "Run as your regular user, not root!"; exit 1; }

header "Post-boot Setup"

# ── Flatpak / Cursor IDE ──────────────────────────────────────────────────────
info "Adding Flathub repository..."
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

info "Attempting Cursor IDE install via Flatpak..."
if flatpak install --user -y flathub com.cursor.Cursor 2>/dev/null; then
  success "Cursor IDE installed via Flatpak"
else
  warn "Cursor not on Flathub. Downloading AppImage..."
  mkdir -p ~/Applications
  CURSOR_URL=$(curl -sL https://www.cursor.sh/api/download\?platform\=linux\&releaseTrack\=stable \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('downloadUrl',''))" 2>/dev/null || echo "")
  if [[ -n "$CURSOR_URL" ]]; then
    curl -L "$CURSOR_URL" -o ~/Applications/cursor.AppImage
    chmod +x ~/Applications/cursor.AppImage
    # Desktop entry
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/cursor.desktop <<DESK
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec=/home/$USER/Applications/cursor.AppImage --no-sandbox %U
Icon=cursor
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Cursor
DESK
    success "Cursor AppImage installed at ~/Applications/cursor.AppImage"
  else
    warn "Could not auto-download Cursor. Visit https://cursor.sh to download manually."
  fi
fi

# ── Atuin sync setup (optional) ──────────────────────────────────────────────
header "Shell History"
read -rp "Set up Atuin sync? (y/N): " DO_ATUIN
if [[ "${DO_ATUIN,,}" == "y" ]]; then
  atuin register || atuin login
  atuin sync
  success "Atuin configured"
fi

# ── Cachix (optional) ────────────────────────────────────────────────────────
header "Binary Caches"
info "Adding Hyprland cachix (speeds up updates)..."
nix run nixpkgs#cachix -- authtoken "$(read -rp 'Cachix auth token (Enter to skip): '; echo)"
nix run nixpkgs#cachix -- use hyprland 2>/dev/null || true

# ── KeePassXC: set up YubiKey (optional) ─────────────────────────────────────
header "KeePassXC"
if command -v keepassxc &>/dev/null; then
  success "KeePassXC is installed. Open it to create your first database."
fi

# ── Snapper snapshot test ────────────────────────────────────────────────────
header "BTRFS Snapper"
info "Testing snapper (manual snapshot)..."
sudo snapper -c root create --description "post-install" 2>/dev/null && \
  success "Root snapshot created" || warn "Snapper not yet configured (normal on first boot)"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Post-boot setup complete!${RESET}"
echo ""
echo "Apps ready:"
echo "  ghostty    — press Super+Return"
echo "  nvim       — in any terminal, type 'nvim'"
echo "  obsidian   — in rofi (Super+Space) search Obsidian"
echo "  brave      — Super+B"
echo "  keepassxc  — search in rofi"
echo "  cursor     — ~/Applications/cursor.AppImage or flatpak run com.cursor.Cursor"
echo ""
echo "Useful aliases (in fish shell):"
echo "  nrs   — rebuild NixOS switch"
echo "  nfu   — update all flake inputs"
echo "  ff    — fastfetch system info"
echo "  gpu   — run app with NVIDIA GPU"
