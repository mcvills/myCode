# NixOS XPS 9500 — Modular Flake Config

> Reproducible NixOS 25.11 (unstable-tracking) for the Dell XPS 15 9500  
> Hyprland (primary) · GNOME (fallback) · BTRFS+Snapper · NVIDIA PRIME · Catppuccin Mocha

---

## Features

| Area | Stack |
|---|---|
| **Compositor** | Hyprland (Wayland) with smooth animations |
| **Fallback DE** | GNOME 47 |
| **Theme** | Catppuccin Mocha (system-wide via Stylix) |
| **Shell** | Fish + Starship + Atuin + Zoxide |
| **Terminal** | Ghostty (GPU-accelerated, blur, opacity) |
| **Editor** | Neovim via nixvim (LSP, Treesitter, Telescope, lazy-style) |
| **Filesystem** | BTRFS with LUKS2 encryption + Snapper hourly snapshots |
| **Boot** | systemd-boot, silent boot, Plymouth splash |
| **GPU** | NVIDIA PRIME offload (GTX 1650 Ti + Intel iGPU) |
| **Audio** | PipeWire (low-latency) |
| **Power** | TLP + fine-grained NVIDIA RTD3 |

## Applications

- **Ghostty** — terminal (from flake input)
- **Neovim** — editor (LSP for Nix, Rust, Python, TS, Go, Bash…)
- **Brave** — browser
- **Obsidian** — notes
- **KeePassXC** — passwords
- **LibreOffice Fresh** — office suite
- **GIMP** — image editing
- **MPV** — media player
- **Cursor IDE** — AI code editor (Flatpak / AppImage via post-boot script)
- **Fastfetch** — system info on terminal open

---

## Quick Start

### Prerequisites (on the live ISO)

Boot the [NixOS 25.11 graphical ISO](https://nixos.org/download/) on your XPS 9500.  
Make sure you're connected to the internet.

```bash
# Enable flakes in the live session
export NIX_CONFIG="experimental-features = nix-command flakes"

# Clone this repo
nix run nixpkgs#git -- clone https://github.com/YOU/nixos-xps
cd nixos-xps

# Run the installer (as root)
sudo bash scripts/install.sh
```

The installer will:
1. **Pre-flight** — verify UEFI, network, tools
2. **Disk** — let you pick a target disk
3. **Partition** — GPT: EFI (1 GiB) + LUKS2 (rest)
4. **BTRFS** — subvolumes: `@` `@home` `@nix` `@log` `@snapshots` `@persist` `@swap`
5. **Install** — `nixos-install` from this flake
6. **Post** — set user password, copy flake to `/etc/nixos`

### After first boot

```bash
bash /etc/nixos/scripts/post-boot-setup.sh
```

This installs Cursor IDE via Flatpak/AppImage and runs optional setup steps.

---

## Customisation

### Change your username / hostname

Edit `modules/system/users.nix` and `hosts/xps9500/default.nix`:

```nix
# users.nix
users.users.yourname = { ... };

# default.nix
networking.hostName = "yourhostname";
```

Update `home/default.nix`:
```nix
home.username = "yourname";
home.homeDirectory = "/home/yourname";
```

Then in `flake-parts/nixos.nix`, update the `users.` key in the home-manager block.

### Change timezone

```nix
# modules/system/locale.nix
time.timeZone = "Europe/London";
```

### NVIDIA Bus IDs

Find yours with:
```bash
lspci | grep -E "VGA|3D"
# 00:02.0 VGA compatible controller: Intel ...
# 01:00.0 3D controller: NVIDIA ...
```

Edit `modules/hardware/nvidia.nix`:
```nix
prime.intelBusId  = "PCI:0:2:0";
prime.nvidiaBusId = "PCI:1:0:0";
```

### Run an app on the NVIDIA GPU

```bash
nvidia-offload brave
gpu mpv video.mkv
```

### Add a new module

```nix
# modules/programs/myapp.nix
{pkgs, ...}: {
  environment.systemPackages = [pkgs.myapp];
}

# Then import it in flake-parts/nixos.nix:
../modules/programs/myapp.nix
```

---

## Disk Layout

```
/dev/nvme0n1
├── nvme0n1p1    1G    FAT32    /boot (EFI)
└── nvme0n1p2    rest  LUKS2
                         └── BTRFS "nixos"
                               ├── @           /
                               ├── @home       /home
                               ├── @nix        /nix
                               ├── @log        /var/log
                               ├── @snapshots  /.snapshots
                               ├── @persist    /persist
                               └── @swap       /swap
```

BTRFS options: `compress=zstd:3` `noatime` `ssd` `space_cache=v2`

### Snapper timeline (root + home)

| Scope | Kept |
|---|---|
| Hourly | 10 |
| Daily | 7 |
| Weekly | 4 |
| Monthly | 3–6 |
| Yearly | 1–2 |

```bash
snapper -c root list           # list snapshots
snapper -c root create --desc "before big change"
snapper -c root diff 1..3      # diff between snapshots
snapper -c root undochange 1..0  # rollback!
```

---

## Updating

```bash
# All flake inputs (nixpkgs, Hyprland, home-manager…)
nfu          # alias for: nix flake update /etc/nixos

# Rebuild and switch (with diff)
nrs          # alias for: nh os switch --hostname xps9500 /etc/nixos

# Or use the script
bash /etc/nixos/scripts/update.sh
```

---

## Test in a VM

No XPS needed to validate changes:

```bash
bash scripts/test-vm.sh
```

Builds a QEMU VM from the flake and boots it. KVM acceleration required.

---

## Key Aliases (Fish)

| Alias | Command |
|---|---|
| `nrs` | nixos-rebuild switch |
| `nrb` | nixos-rebuild boot |
| `nfu` | flake update |
| `ngc` | nix garbage collect |
| `ff` | fastfetch |
| `gpu <app>` | run with NVIDIA |
| `ns <pkg>` | nix shell nixpkgs#pkg |
| `ll` | eza long listing |
| `cat` | bat (syntax-highlighted) |

---

## Hyprland Keybindings

| Key | Action |
|---|---|
| `Super+Return` | Ghostty terminal |
| `Super+Space` | Rofi launcher |
| `Super+Q` | Close window |
| `Super+B` | Brave browser |
| `Super+E` | File manager |
| `Super+F` | Fullscreen |
| `Super+T` | Float toggle |
| `Super+S` | Scratchpad toggle |
| `Super+1–0` | Switch workspace |
| `Super+Shift+1–0` | Move to workspace |
| `Super+H/L/K/J` | Focus direction |
| `Print` | Screenshot (area → clipboard) |
| `Super+Print` | Screenshot (area → file) |
| `Super+V` | Clipboard history (rofi) |
| `Super+Esc` | Lock screen |
| `Super+Shift+C` | Colour picker |

---

## Flake Structure

```
nixos-xps/
├── flake.nix                  # inputs + outputs entrypoint
├── flake-parts/
│   ├── nixos.nix              # NixOS configurations
│   ├── home.nix               # standalone home-manager configs
│   └── devshell.nix           # nix develop shell
├── hosts/
│   └── xps9500/
│       ├── default.nix        # host identity
│       ├── disk-config.nix    # disko BTRFS layout
│       └── hardware-quirks.nix
├── modules/
│   ├── system/                # boot, kernel, locale, networking…
│   ├── hardware/              # nvidia, audio, power, bluetooth
│   ├── desktop/               # hyprland, gnome, portals
│   └── programs/              # system-level packages + snapper
└── home/
    ├── default.nix            # home-manager root
    ├── hyprland/              # hyprland + waybar configs
    └── common/                # shell, nvim, ghostty, fastfetch, git, stylix
```

---

## License

MIT — feel free to fork and adapt.
