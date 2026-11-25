#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
WALLPAPER_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Wallpapers"
FEDORA_VER="$(rpm -E %fedora)"

if [[ "$EUID" -eq 0 ]]; then
    echo "Do not run as root." >&2
    exit 1
fi

sudo -v

# 1. Base setup & directories
sudo dnf upgrade -y
sudo dnf install -y xdg-user-dirs fontconfig curl pciutils
xdg-user-dirs-update
mkdir -p "$CONFIG_DIR" "$HOME/.icons" "$HOME/.icons/default" "$CONFIG_DIR/gtk-3.0" "$WALLPAPER_DIR"

# 2. Repositories
rpm -q rpmfusion-free-release >/dev/null 2>&1 ||
    sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm"

rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 ||
    sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

[[ -f /etc/yum.repos.d/librewolf.repo ]] ||
    sudo dnf config-manager addrepo --overwrite \
        --from-repofile=https://repo.librewolf.net/librewolf.repo

sudo dnf copr enable -y imput/helium
sudo dnf copr enable -y yselkowitz/nwg-shell

if ! rpm -q terra-release >/dev/null 2>&1 && [[ ! -f /etc/yum.repos.d/terra.repo ]]; then
    sudo dnf install -y --nogpgcheck \
        --repofrompath="terra,https://repos.fyralabs.com/terra${FEDORA_VER}" \
        terra-release
fi

sudo dnf config-manager setopt terra.exclude="librewolf*"

# 3. Multimedia & graphics hardware acceleration
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia --exclude=PackageKit-gstreamer-plugin
sudo dnf install -y libavcodec-freeworld gstreamer1-plugins-bad-free-extras gstreamer1-plugins-ugly --skip-unavailable

# Mesa VA-API freeworld (parallel install, not swap)
sudo dnf install -y mesa-va-drivers-freeworld --skip-unavailable

# Vulkan video acceleration for AMD / Mesa
if lspci | grep -qiE 'VGA|3D|Display' && lspci | grep -qiE 'AMD|ATI|Radeon'; then
    sudo dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing --skip-unavailable ||
        sudo dnf install -y mesa-vulkan-drivers-freeworld --skip-unavailable
fi

# Intel media driver for hardware VA-API on modern Intel GPUs
if lspci | grep -qiE 'VGA|3D|Display' && lspci | grep -qi 'Intel'; then
    sudo dnf install -y intel-media-driver --skip-unavailable
fi

# 4. Applications
PACKAGES=(
    thunar foot sway ly fish starship fastfetch btop
    qbittorrent qt5ct qt6ct celluloid steam nwg-look
    eog ristretto librewolf helium-bin adw-gtk3-theme
    noctalia inkscape
)
sudo dnf install -y "${PACKAGES[@]}"

# 5. Display manager (ly on tty2)
sudo systemctl disable --now getty@tty2.service 2>/dev/null || true
sudo systemctl enable ly@tty2.service

# 6. Fonts
if [[ -d "$REPO_DIR/font" ]]; then
    sudo mkdir -p /usr/local/share/fonts
    sudo cp -a "$REPO_DIR/font/." /usr/local/share/fonts/
    sudo fc-cache -f
fi

# 7. Dotfiles & assets
[[ -f "$REPO_DIR/.bashrc" ]] && cp -f "$REPO_DIR/.bashrc" "$HOME/.bashrc"
[[ -d "$REPO_DIR/.config" ]] && cp -a "$REPO_DIR/.config/." "$CONFIG_DIR/"
[[ -d "$REPO_DIR/.icons" ]] && cp -a "$REPO_DIR/.icons/." "$HOME/.icons/"
[[ -d "$REPO_DIR/wallpapers" ]] && cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DIR/"

# 8. GTK & cursor defaults
# cat > "$CONFIG_DIR/gtk-3.0/settings.ini" <<'EOF'
# [Settings]
# gtk-icon-theme-name=TokyoNight-SE
# gtk-cursor-theme-name=BreezeX-Dark
# gtk-font-name=Iosevka Nerd Font 12.5
# EOF

# cat > "$HOME/.icons/default/index.theme" <<'EOF'
# [Icon Theme]
# Name=Default
# Inherits=BreezeX-Dark
# EOF

# if command -v gsettings >/dev/null 2>&1; then
#     gsettings set org.gnome.desktop.interface icon-theme "TokyoNight-SE" || true
#     gsettings set org.gnome.desktop.interface cursor-theme "BreezeX-Dark" || true
#     gsettings set org.gnome.desktop.interface font-name "Iosevka Nerd Font 12.5" || true
#     gsettings set org.gnome.desktop.interface monospace-font-name "Iosevka Nerd Font 12.5" || true
# fi

# 9. Default shell
if FISH_PATH="$(command -v fish)"; then
    grep -Fxq "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
    if [[ "${SHELL:-}" != "$FISH_PATH" ]]; then
        sudo usermod -s "$FISH_PATH" "$USER"
    fi
fi

echo "Done. Reboot or log out to apply changes."
