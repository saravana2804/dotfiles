#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "[error] Do not run this script as root." >&2
  exit 1
fi

# Refresh sudo upfront and keep alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

log "1. Updating xdg-user-dirs..."
sudo dnf install -y xdg-user-dirs fontconfig
xdg-user-dirs-update

if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]]; then
  # shellcheck disable=SC1090
  source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
fi
WALLPAPER_DEST="${XDG_PICTURES_DIR:-$HOME/Pictures}/Wallpapers"

log "2. Enabling repositories and multimedia..."
FEDORA_VER="$(rpm -E %fedora)"

rpm -q rpmfusion-free-release >/dev/null 2>&1 || \
  sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm"
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 || \
  sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

[[ -f /etc/yum.repos.d/librewolf.repo ]] || \
  sudo dnf config-manager addrepo --overwrite --from-repofile=https://repo.librewolf.net/librewolf.repo

sudo dnf copr enable -y imput/helium || true
sudo dnf copr enable -y yselkowitz/nwg-shell || true

if ! rpm -q terra-release >/dev/null 2>&1 && [[ ! -f /etc/yum.repos.d/terra.repo ]]; then
  sudo dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" terra-release
fi
sudo dnf config-manager setopt terra.exclude="librewolf*" || true

# Multimedia codecs
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing --skip-unavailable || true
sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing --skip-unavailable || true

log "3. Installing packages..."
BASE_PKGS=(
  thunar foot sway ly fish qbittorrent qt5ct qt6ct celluloid
  steam nwg-look eog ristretto btop librewolf helium-bin adw-gtk3-theme noctalia fastfetch
  inkscape
)
sudo dnf install -y "${BASE_PKGS[@]}"

log "4. Enabling ly display manager..."
sudo systemctl disable --now getty@tty2.service 2>/dev/null || true
if [[ -f /etc/ly/config.ini ]]; then
  sudo sed -i -E 's/^\s*#?\s*tty\s*=.*/tty = 2/' /etc/ly/config.ini
fi
sudo systemctl enable ly.service 2>/dev/null || sudo systemctl enable ly@tty2.service

log "5. Copying fonts to /usr/local/share/fonts/..."
if [[ -d "$REPO_DIR/font" ]]; then
  sudo mkdir -p /usr/local/share/fonts
  sudo cp -a "$REPO_DIR/font/." /usr/local/share/fonts/
  sudo chmod -R a+rX,go-w /usr/local/share/fonts
  sudo fc-cache -f
fi

log "6. Copying dotfiles..."
mkdir -p "$HOME/.config" "$HOME/.icons" "$WALLPAPER_DEST" "$BACKUP_DIR"

# Backup existing configs
[[ -f "$HOME/.bashrc" ]] && cp -a "$HOME/.bashrc" "$BACKUP_DIR/.bashrc"
[[ -d "$HOME/.config" ]] && cp -a "$HOME/.config/." "$BACKUP_DIR/.config/" 2>/dev/null || true
[[ -d "$HOME/.icons" ]] && cp -a "$HOME/.icons/." "$BACKUP_DIR/.icons/" 2>/dev/null || true

# Deploy dotfiles
[[ -f "$REPO_DIR/.bashrc" ]] && cp -f "$REPO_DIR/.bashrc" "$HOME/.bashrc"
[[ -d "$REPO_DIR/.icons" ]] && cp -a "$REPO_DIR/.icons/." "$HOME/.icons/"
[[ -d "$REPO_DIR/.config" ]] && cp -a "$REPO_DIR/.config/." "$HOME/.config/"
[[ -d "$REPO_DIR/wallpapers" ]] && cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DEST/"

rmdir "$BACKUP_DIR" 2>/dev/null || log "Backed up existing files to: $BACKUP_DIR"

log "7. Setting themes (TokyoNight-SE icons, BreezeX-Dark cursor, Iosevka font)..."
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "TokyoNight-SE" || true
  gsettings set org.gnome.desktop.interface cursor-theme "BreezeX-Dark" || true
  gsettings set org.gnome.desktop.interface font-name "Iosevka Nerd Font 12.5" || true
  gsettings set org.gnome.desktop.interface monospace-font-name "Iosevka Nerd Font 12.5" || true
fi

# GTK3 settings
mkdir -p "$HOME/.config/gtk-3.0"
cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-icon-theme-name=TokyoNight-SE
gtk-cursor-theme-name=BreezeX-Dark
gtk-font-name=Iosevka Nerd Font 12.5
EOF

# Default cursor file
mkdir -p "$HOME/.icons/default"
cat <<EOF > "$HOME/.icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=BreezeX-Dark
EOF

# Foot terminal font override
FOOT_INI="$HOME/.config/foot/foot.ini"
if [[ -f "$FOOT_INI" ]]; then
  if grep -qE '^\s*#?\s*font\s*=' "$FOOT_INI"; then
    sed -i -E 's/^\s*#?\s*font\s*=.*/font=Iosevka Nerd Font:size=12.5/' "$FOOT_INI"
  else
    printf '\n[main]\nfont=Iosevka Nerd Font:size=12.5\n' >> "$FOOT_INI"
  fi
fi

log "8. Installing Starship binary & setting Fish as default shell..."
curl -sS https://starship.rs/install.sh | sh -s -- -y

FISH_BIN="$(command -v fish)"
if ! grep -qxF "$FISH_BIN" /etc/shells; then
  printf '%s\n' "$FISH_BIN" | sudo tee -a /etc/shells >/dev/null
fi

if [[ "${SHELL:-}" != "$FISH_BIN" ]]; then
  chsh -s "$FISH_BIN" || sudo usermod -s "$FISH_BIN" "$USER"
fi

log "Done! Log out or reboot to apply your new login shell and themes."
