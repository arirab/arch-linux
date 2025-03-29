#!/bin/bash
set -e
trap 'echo "[!] GUI and Application Installation Failed. See /var/log/gui-and-application-install.log for details."; exit 1' ERR
exec > >(tee -a /var/log/gui-and-application-install.log) 2>&1

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

echo -e "\n Starting GNOME Core GUI Setup..."

read -rp "Enter your username for GUI setup: " TARGET_USER
id "$TARGET_USER" &>/dev/null || { echo "[!] User $TARGET_USER does not exist."; exit 1; }

USER_HOME=$(eval echo "~$TARGET_USER")

# ---------------------------------------
# yay bootstrap with retry-safe fallback
# ---------------------------------------
log "Installing yay AUR helper and enabling multilib..."
sudo pacman -Syu --noconfirm --needed git base-devel

if ! command -v yay &>/dev/null; then
  rm -rf /tmp/yay && git clone https://aur.archlinux.org/yay.git /tmp/yay
  pushd /tmp/yay
  makepkg -si --noconfirm
  popd
fi

sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sudo sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf
grep -q "ParallelDownloads" /etc/pacman.conf || echo "ParallelDownloads = 10" | sudo tee -a /etc/pacman.conf

yay -Syu --noconfirm

# ---------------------------------------
# Flatpak + Flathub + XDG Dirs
# ---------------------------------------
log "Setting up Flatpak and user dirs..."
sudo pacman -S --noconfirm flatpak xdg-user-dirs
sudo -u "$TARGET_USER" xdg-user-dirs-update
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

yay -S --noconfirm --needed gnome-software-packagekit-plugin

# ---------------------------------------
# GNOME install + Wayland-safe config
# ---------------------------------------
log "Installing GNOME Desktop Environment..."
yay -S --noconfirm --needed gnome gnome-tweaks gnome-shell-extensions \
  gnome-browser-connector gdm xdg-desktop-portal-gnome

sudo systemctl enable gdm

sudo mkdir -p /etc/gdm
sudo sed -i '/^\[daemon\]/,/^\[.*\]/{s/^WaylandEnable=.*/WaylandEnable=true/; t; aWaylandEnable=true}' /etc/gdm/custom.conf || \
  echo -e "[daemon]\nWaylandEnable=true" | sudo tee -a /etc/gdm/custom.conf

sudo systemctl enable --now NetworkManager || true

# ---------------------------------------
# Fonts, Icons, Themes, Cursors
# ---------------------------------------
log "Installing fonts, icons, and themes..."
yay -S --noconfirm --needed \
  ttf-jetbrains-mono-nerd ttf-firacode-nerd ttf-font-awesome \
  papirus-icon-theme adw-gtk3 bibata-cursor-theme

# ---------------------------------------
# GNOME Look & Behavior Tweaks
# ---------------------------------------
log "Applying GNOME default tweaks..."
sudo -u "$TARGET_USER" dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
sudo -u "$TARGET_USER" dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
sudo -u "$TARGET_USER" dbus-launch gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
sudo -u "$TARGET_USER" dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
sudo -u "$TARGET_USER" dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'

# ---------------------------------------
# Terminal: Zsh, Starship, Kitty + Extras
# ---------------------------------------
log "Installing terminal tools..."
yay -S --noconfirm --needed zsh starship kitty fastfetch zsh-autosuggestions zsh-syntax-highlighting \
  zsh-you-should-use zsh-completions
chsh -s /bin/zsh "$TARGET_USER"

mkdir -p "$USER_HOME/.config" "$USER_HOME/.config/kitty" "$USER_HOME/.config/autostart"

cat > "$USER_HOME/.zshrc" <<EOF
export EDITOR=nvim
export STARSHIP_CONFIG="\$HOME/.config/starship.toml"
eval "\$(starship init zsh)"
autoload -Uz compinit && compinit

# Zsh Plugins
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/you-should-use/you-should-use.plugin.zsh

# ASCII logo on login
fastfetch

# Elara-class aliases
alias gs='git status'
alias gc='git commit -m'
alias gp='git push'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
EOF

cat > "$USER_HOME/.config/starship.toml" <<EOF
add_newline = false
[character]
success_symbol = "[➜](green)"
error_symbol = "[✗](red)"
[time]
disabled = false
format = " [\[\$time\]](blue)"
EOF

cat > "$USER_HOME/.config/kitty/kitty.conf" <<EOF
font_family JetBrainsMono Nerd Font
font_size 12.0
enable_audio_bell no
scrollback_lines 10000
background_opacity 0.95
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config" "$USER_HOME/.zshrc"

# Add GUI recovery shortcut
cat > "$USER_HOME/.config/autostart/gnome-settings.desktop" <<EOF
[Desktop Entry]
Name=GNOME Settings
Exec=gnome-control-center
Type=Application
X-GNOME-Autostart-enabled=true
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/autostart"

# ---------------------------------------
# Final Message
# ---------------------------------------
log "GNOME Core GUI setup complete."
read -rp " Reboot now into GNOME? [y/N]: " reboot
[[ "\$reboot" =~ ^[Yy]$ ]] && sudo reboot || echo -e "\n[✓] Setup done. Reboot when ready."
