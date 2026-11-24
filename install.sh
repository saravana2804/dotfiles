
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
WALLPAPER_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Wallpapers"
FEDORA_VER="$(rpm -E %fedora)"

# Root check
if [[ "$EUID" -eq 0 ]]; then
    echo "Do not run as root."
    exit 1
fi

sudo -v

# 1. System preparation
sudo dnf upgrade -y
sudo dnf install -y xdg-user-dirs fontconfig curl
xdg-user-dirs-update

mkdir -p "$CONFIG_DIR" "$HOME/.icons" "$WALLPAPER_DIR"

# 2. Repositories
rpm -q rpmfusion-free-release >/dev/null 2>&1 || \
    sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm"

rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 || \
    sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

[[ -f /etc/yum.repos.d/librewolf.repo ]] || \
    sudo dnf config-manager addrepo --overwrite \
    --from-repofile=https://repo.librewolf.net/librewolf.repo

sudo dnf copr enable -y imput/helium || true
sudo dnf copr enable -y yselkowitz/nwg-shell || true

if ! rpm -q terra-release >/dev/null 2>&1 &&
   [[ ! -f /etc/yum.repos.d/terra.repo ]]; then
    sudo dnf install -y --nogpgcheck \
        --repofrompath="terra,https://repos.fyralabs.com/terra\$releasever" \
        terra-release
fi

sudo dnf config-manager setopt terra.exclude="librewolf*" || true

# 3. Multimedia
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia \
    --setopt=install_weak_deps=False \
    --exclude=PackageKit-gstreamer-plugin

sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld \
    --allowerasing --skip-unavailable || true

sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld \
    --allowerasing --skip-unavailable || true

# 4. Packages
PACKAGES=(
    thunar foot sway ly fish
    qbittorrent qt5ct qt6ct celluloid
    steam nwg-look eog ristretto
    btop librewolf helium-bin
    adw-gtk3-theme noctalia fastfetch
    inkscape starship
)

sudo dnf install -y "${PACKAGES[@]}"

# 5. Ly display manager
sudo systemctl disable getty@tty2.service
sudo systemctl enable ly@tty2.service

# 6. Fonts
if [[ -d "$REPO_DIR/font" ]]; then
    sudo mkdir -p /usr/local/share/fonts
    sudo cp -a "$REPO_DIR/font/." /usr/local/share/fonts/
    sudo fc-cache -f
fi

# 7. Dotfiles
[[ -f "$REPO_DIR/.bashrc" ]] && cp -f "$REPO_DIR/.bashrc" "$HOME/.bashrc"

[[ -d "$REPO_DIR/.config" ]] && cp -a "$REPO_DIR/.config/." "$CONFIG_DIR/"
[[ -d "$REPO_DIR/.icons" ]] && cp -a "$REPO_DIR/.icons/." "$HOME/.icons/"
[[ -d "$REPO_DIR/wallpapers" ]] && cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DIR/"

# 8. Themes
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "TokyoNight-SE" || true
    gsettings set org.gnome.desktop.interface cursor-theme "BreezeX-Dark" || true
    gsettings set org.gnome.desktop.interface font-name "Iosevka Nerd Font 12.5" || true
    gsettings set org.gnome.desktop.interface monospace-font-name "Iosevka Nerd Font 12.5" || true
fi

mkdir -p "$CONFIG_DIR/gtk-3.0" "$HOME/.icons/default"

cat > "$CONFIG_DIR/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-icon-theme-name=TokyoNight-SE
gtk-cursor-theme-name=BreezeX-Dark
gtk-font-name=Iosevka Nerd Font 12.5
EOF

cat > "$HOME/.icons/default/index.theme" <<'EOF'
[Icon Theme]
Name=Default
Inherits=BreezeX-Dark
EOF

# 9. Fish shell
FISH_PATH="$(command -v fish)"

grep -Fxq "$FISH_PATH" /etc/shells ||
    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null

chsh -s "$FISH_PATH"

echo "Installation complete. Log out or reboot."
