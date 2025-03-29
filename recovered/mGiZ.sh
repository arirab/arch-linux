#!/bin/bash

set -e

# ===============================================
# --- Graphical User Interface & Applications --- 
# Theming, Terminal Enhancements, Essential Tools
# ===============================================

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

# =============================
# Install yay & Enable Multilib
# =============================
log "Installing yay AUR helper and enabling multilib..."
sudo pacman -Syu --noconfirm

cd ~
if [[ ! -d yay ]]; then
  git clone https://aur.archlinux.org/yay.git
fi
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
yay -S --noconfirm gnome gnome-tweaks gnome-shell-extensions \
  gnome-browser-connector gdm xdg-desktop-portal-gnome

sudo systemctl enable gdm

# ============================
# Install Fonts, Icons, Themes
# ============================
log "Installing fonts and themes..."
yay -S --noconfirm ttf-jetbrains-mono-nerd ttf-firacode-nerd ttf-font-awesome \
  papirus-icon-theme adw-gtk3 bibata-cursor-theme

# =======================
# Flatpak + Flathub Setup
# =======================
log "Enabling Flatpak + Flathub support..."
sudo pacman -S --noconfirm flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# ================================================
# Enhanced Terminal Setup (Zsh + Starship + Kitty)
# ================================================
log "Installing Zsh, Starship, Kitty and plugins..."
yay -S --noconfirm zsh starship kitty fastfetch zsh-autosuggestions zsh-syntax-highlighting
chsh -s /bin/zsh "$USER"

mkdir -p ~/.config

cat > ~/.zshrc <<EOF
export EDITOR=nvim
eval "\$(starship init zsh)"
autoload -Uz compinit && compinit

# Zsh Plugins
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

mkdir -p ~/.config/starship.toml
cat > ~/.config/starship.toml <<EOF
add_newline = false

[character]
success_symbol = "[➜](green)"
error_symbol = "[✗](red)"

[time]
disabled = false
format = "🕒 [\[$time\]](blue)"
EOF

mkdir -p ~/.config/kitty
cat > ~/.config/kitty/kitty.conf <<EOF
font_family JetBrainsMono Nerd Font
font_size 12.0
enable_audio_bell no
scrollback_lines 10000
tab_bar_edge top
background_opacity 0.95
EOF

# =====================
# Autostart App Entries
# =====================
log "Creating autostart .desktop entries..."
mkdir -p ~/.config/autostart

for app in spotify telegram-desktop discord; do
  cat > ~/.config/autostart/$app.desktop <<EOF
[Desktop Entry]
Type=Application
Exec=$app
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=$(echo $app | sed 's/-desktop//' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
EOF
done

# ==============================================
# Essential Applications (Browsers, IDEs, Tools)
# ==============================================
log "Installing essential desktop applications..."
yay -S --noconfirm \
  firefox brave-bin google-chrome microsoft-edge-stable-bin \
  discord zoom teams-for-linux \
  code sublime-text-4 \
  docker docker-compose \
  vmware-workstation \
  gh kubectl helm minikube terraform ansible aws-cli

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

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
  echo " Reboot manually when ready. You're fully set up!"
fi