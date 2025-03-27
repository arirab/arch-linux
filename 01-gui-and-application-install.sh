#!/bin/bash

set -e
trap 'echo "[!] GUI and Application Installation Failed. See /var/log/gui-and-application-install.log for details."; exit 1' ERR

# Redirect all output to a log file for debugging
exec > >(tee -a /var/log/gui-and-application-install.log) 2>&1

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

echo -e "\n Starting GUI & Application Setup..."

# === Prompt for Username (Required for chsh, docker group, etc.)
read -rp "Enter your username for GUI setup: " TARGET_USER

# === Validate User Exists
id "$TARGET_USER" &>/dev/null || {
  echo "[!] User $TARGET_USER does not exist. Please create it first."
  exit 1
}

USER_HOME=$(eval echo "~$TARGET_USER")

# =============================
# Install yay & Enable Multilib
# =============================
log "Installing yay AUR helper and enabling multilib..."
sudo pacman -Syu --noconfirm

cd /tmp
[[ -d yay ]] && rm -rf yay
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sudo sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf

if ! grep -q "^ParallelDownloads" /etc/pacman.conf; then
  echo "ParallelDownloads = 10" | sudo tee -a /etc/pacman.conf
else
  sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
fi

sudo sed -i '/^\[options\]/a IgnorePkg = linux linux-headers linux-lts linux-lts-headers linux-firmware nvidia* cuda' /etc/pacman.conf

yay -Syu --noconfirm

# =============================
# Install GNOME Desktop
# =============================
log "Installing GNOME Desktop Environment..."
yay -S --noconfirm --needed gnome gnome-tweaks gnome-shell-extensions \
  gnome-browser-connector gdm xdg-desktop-portal-gnome

sudo systemctl enable gdm

# Wayland config (optional but good practice)
sudo mkdir -p /etc/gdm
echo -e "[daemon]\nWaylandEnable=true" | sudo tee /etc/gdm/custom.conf

# Enable NetworkManager (in case not already enabled)
sudo systemctl enable --now NetworkManager || true

# ============================
# Install Fonts, Icons, Themes
# ============================
log "Installing fonts and themes..."
yay -S --noconfirm --needed ttf-jetbrains-mono-nerd ttf-firacode-nerd ttf-font-awesome \
  papirus-icon-theme adw-gtk3 bibata-cursor-theme

# =======================
# Flatpak + Flathub Setup
# =======================
log "Enabling Flatpak + Flathub support..."
sudo pacman -S --noconfirm flatpak xdg-user-dirs
sudo -u "$TARGET_USER" xdg-user-dirs-update
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# GNOME Software Center Plugin (optional)
yay -S --noconfirm --needed gnome-software-packagekit-plugin

# ================================================
# Enhanced Terminal Setup (Zsh + Starship + Kitty)
# ================================================
log "Installing Zsh, Starship, Kitty and plugins..."
yay -S --noconfirm --needed zsh starship kitty fastfetch zsh-autosuggestions zsh-syntax-highlighting
chsh -s /bin/zsh "$TARGET_USER"

mkdir -p "$USER_HOME/.config"

cat > "$USER_HOME/.zshrc" <<EOF
export EDITOR=nvim
export STARSHIP_CONFIG="\$HOME/.config/starship.toml"
eval "\$(starship init zsh)"
autoload -Uz compinit && compinit

# Zsh Plugins
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.zshrc"

mkdir -p "$USER_HOME/.config"

mkdir -p "$USER_HOME/.config/starship.toml"
cat > "$USER_HOME/.config/starship.toml" <<EOF
add_newline = false

[character]
success_symbol = "[➜](green)"
error_symbol = "[✗](red)"

[time]
disabled = false
format = " [\[$time\]](blue)"
EOF
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/starship.toml"

mkdir -p "$USER_HOME/.config/kitty"
cat > "$USER_HOME/.config/kitty/kitty.conf" <<EOF
font_family JetBrainsMono Nerd Font
bold_font auto
italic_font auto
font_size 12.0
enable_audio_bell no
scrollback_lines 10000
tab_bar_edge top
background_opacity 0.95
EOF
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/kitty"

# =====================
# Autostart App Entries
# =====================
log "Creating autostart .desktop entries..."
mkdir -p "$USER_HOME/.config/autostart"

for app in spotify telegram-desktop discord; do
  cat > "$USER_HOME/.config/autostart/$app.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$app
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=$(echo $app | sed 's/-desktop//' | awk '{print toupper(substr(\$0,1,1)) substr(\$0,2)}')
EOF
done
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/autostart"

# ==============================================
# Essential Applications (Browsers, IDEs, Tools)
# ==============================================
log "Installing essential desktop applications..."
yay -S --noconfirm --needed \
  firefox brave-bin google-chrome microsoft-edge-stable-bin \
  discord zoom teams-for-linux \
  code sublime-text-4 \
  docker docker-compose \
  vmware-workstation \
  gh kubectl helm minikube terraform ansible aws-cli

sudo systemctl enable --now docker
sudo usermod -aG docker "$TARGET_USER"

# ====================================
# Dotfile Manager Stub (chezmoi-ready)
# ====================================
log "chezmoi or dotbot can be used to sync dotfiles."
echo "To use chezmoi: yay -S chezmoi && chezmoi init --apply <your-private-repo>"

# ==============
# --- Reboot ---
# ==============
log "GNOME Desktop environment + application setup complete."
read -rp " Reboot now to start GNOME? [y/N]: " reboot
if [[ "$reboot" =~ ^[Yy]$ ]]; then
  sudo reboot
else
  echo -e "\n[\u2713] All done! You can now login to GNOME."
  echo "To reboot: sudo reboot"
fi
