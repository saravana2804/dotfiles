#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 1. Installing and updating xdg-user-dirs..."
sudo dnf install -y xdg-user-dirs
xdg-user-dirs-update

PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
WALLPAPER_DEST="$PICTURES_DIR/Wallpapers"

echo "==> 2. Enabling repositories..."
# RPM Fusion (required for steam and media packages)
sudo dnf install -y sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld

# Helium browser COPR
sudo dnf copr enable -y imput/helium

# yselkowitz nwg-shell COPR
sudo dnf copr enable -y yselkowitz/nwg-shell

# Terra repository
sudo dnf install -y --nogpgcheck \
  --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
  terra-release

echo "==> 3. Installing packages..."
BASE_PKGS=(
  thunar
  foot
  sway
  ly
  fish
  qbittorrent
  qt5ct
  qt6ct
  celluloid
  steam
  nwg-looks
  eog
  ristretto
  btop
  librewolf
  helium-bin
  adw-gtk3-theme
  noctalia
)

sudo dnf install -y "${BASE_PKGS[@]}"

echo "==> 4. Copying dotfiles..."
mkdir -p "$HOME/.config" "$WALLPAPER_DEST"

# Copy .bashrc
if [[ -f "$REPO_DIR/.bashrc" ]]; then
  cp -f "$REPO_DIR/.bashrc" "$HOME/.bashrc"
fi

# Copy everything inside .config/ (including dotfiles like .config/.bashrc) to ~/.config/
if [[ -d "$REPO_DIR/.config" ]]; then
  cp -a "$REPO_DIR/.config/." "$HOME/.config/"
fi

# Copy wallpapers
if [[ -d "$REPO_DIR/wallpapers" ]]; then
  cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DEST/"
fi

echo "==> Done!"
