#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  warn "Do not run this script as root; run it as your normal user (sudo will be used when needed)."
  exit 1
fi

# Refresh sudo upfront and keep it alive in the background while dnf runs
sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" 2>/dev/null || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

log "1. Installing and updating xdg-user-dirs..."
sudo dnf install -y xdg-user-dirs
xdg-user-dirs-update

if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]]; then
  # shellcheck disable=SC1090
  source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
fi

PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
WALLPAPER_DEST="$PICTURES_DIR/Wallpapers"

log "2. Enabling repositories and multimedia codecs..."
FEDORA_VER="$(rpm -E %fedora)"
REPOS_CHANGED=false

# RPM Fusion (required for steam and freeworld media packages)
RPMFUSION_PKGS=()
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  RPMFUSION_PKGS+=("https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm")
fi
if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  RPMFUSION_PKGS+=("https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm")
fi
if [[ "${#RPMFUSION_PKGS[@]}" -gt 0 ]]; then
  sudo dnf install -y "${RPMFUSION_PKGS[@]}"
  REPOS_CHANGED=true
else
  log "RPM Fusion repositories already installed, skipping."
fi

# LibreWolf repository
if [[ ! -f /etc/yum.repos.d/librewolf.repo ]]; then
  sudo dnf config-manager addrepo --overwrite --from-repofile=https://repo.librewolf.net/librewolf.repo
  REPOS_CHANGED=true
else
  log "LibreWolf repository already configured, skipping."
fi

# COPR repositories (dnf copr creates _copr:copr.fedorainfracloud.org:<owner>:<project>.repo)
enable_copr_if_missing() {
  local spec="$1"
  local repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${spec/\//:}.repo"
  if [[ ! -f "$repo_file" ]]; then
    sudo dnf copr enable -y "$spec"
    REPOS_CHANGED=true
  else
    log "COPR ${spec} already enabled, skipping."
  fi
}

enable_copr_if_missing "imput/helium"
enable_copr_if_missing "yselkowitz/nwg-shell"

# Terra repository
if ! rpm -q terra-release >/dev/null 2>&1 && [[ ! -f /etc/yum.repos.d/terra.repo ]]; then
  sudo dnf install -y --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
    terra-release
  REPOS_CHANGED=true
else
  log "Terra repository already configured, skipping."
fi
sudo dnf config-manager setopt terra.exclude="librewolf*"

if [[ "$REPOS_CHANGED" == true ]]; then
  sudo dnf makecache -y
fi

# Multimedia & hardware acceleration
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing --skip-unavailable || true
sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing --skip-unavailable || true

log "3. Installing packages..."
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

log "4. Enabling ly on tty2..."
sudo systemctl disable --now getty@tty2.service 2>/dev/null || true
if systemctl list-unit-files 'ly@*.service' --no-legend 2>/dev/null | grep -q '^ly@'; then
  # Template unit (e.g. ly@.service in newer ly releases)
  sudo systemctl disable ly.service 2>/dev/null || true
  sudo systemctl enable ly@tty2.service
else
  # Standalone ly.service: configure tty = 2 in /etc/ly/config.ini if present
  if [[ -f /etc/ly/config.ini ]]; then
    if grep -qE '^\s*#?\s*tty\s*=' /etc/ly/config.ini; then
      sudo sed -i -E 's/^\s*#?\s*tty\s*=.*/tty = 2/' /etc/ly/config.ini
    else
      printf '\ntty = 2\n' | sudo tee -a /etc/ly/config.ini >/dev/null
    fi
  fi
  sudo systemctl enable ly.service
fi

log "5. Backing up existing configs and copying dotfiles..."
mkdir -p "$HOME/.config" "$WALLPAPER_DEST" "$BACKUP_DIR"

if [[ -f "$REPO_DIR/.bashrc" ]]; then
  [[ -e "$HOME/.bashrc" ]] && cp -a "$HOME/.bashrc" "$BACKUP_DIR/.bashrc"
  cp -f "$REPO_DIR/.bashrc" "$HOME/.bashrc"
fi

if [[ -d "$REPO_DIR/.config" ]]; then
  mkdir -p "$BACKUP_DIR/.config"
  cp -a "$HOME/.config/." "$BACKUP_DIR/.config/" 2>/dev/null || true
  cp -a "$REPO_DIR/.config/." "$HOME/.config/"
fi

if [[ -d "$REPO_DIR/wallpapers" ]]; then
  cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DEST/"
fi

# Clean up backup dir if nothing was backed up
rmdir "$BACKUP_DIR" 2>/dev/null || log "Existing dotfiles backed up to: $BACKUP_DIR"

log "Done! Switch to tty2 (Ctrl+Alt+F2) or reboot to use ly."
