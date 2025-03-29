#!/bin/bash
set -e
trap 'echo "[!] Hyperland Setup Failed. Check logs."; exit 1' ERR

log() {
 echo -e "\033[1;36m[Hyperland] $1\033[0m"
}

read -rp "Enter your username for Hyperland setup: " TARGET_USER
id "$TARGET_USER" &>/dev/null || { echo "[!] User $TARGET_USER does not exist."; exit 1; }
USER_HOME=$(eval echo "~$TARGET_USER")

# Input sudo Password
sudo -v
( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
KEEP_ALIVE_PID=$$


# ===============================================================================
# --- Section 1: Bootstrap + Dependency Setup (pacman config, yay, core apps) ---
# ===============================================================================


# --- Pacman Config Tweaks (Repos + Candy) ---
log "Enabling extra, community, multilib, candy + parallel downloads..."

# Enable multilib repo
sudo sed -i '/^\[multilib\]/,/^Include/ s/^#//' /etc/pacman.conf

# Enable community repo
sudo grep -q "^\[community\]" /etc/pacman.conf || echo -e "\n[community]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf

# Extra repo is enabled by default, but we'll double check
sudo grep -q "^\[extra\]" /etc/pacman.conf || echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf

# Enable colored output and candy
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
sudo grep -q "ILoveCandy" /etc/pacman.conf || echo "ILoveCandy" | sudo tee -a /etc/pacman.conf

# Enable parallel downloads
grep -q "ParallelDownloads" /etc/pacman.conf || echo "ParallelDownloads = 10" | sudo tee -a /etc/pacman.conf

# Refresh everything
sudo pacman -Syyu --noconfirm


# --- Bootstrap yay and configure pacman ---
log "Installing yay AUR helper and enabling multilib..."
sudo pacman -Syu --noconfirm --needed git base-devel

if ! command -v yay &>/dev/null; then
  rm -rf /tmp/yay && git clone --depth=1 https://aur.archlinux.org/yay.git /tmp/yay
  pushd /tmp/yay
  makepkg -si --noconfirm
  popd
fi

yay -Syu --noconfirm

# --- Install ALL required dependencies upfront ---
log "Installing all required packages for full Hyperland system..."

yay -S --noconfirm --needed \
  # --- Hyperland + Core ---
  hyprland-git waybar-hyprland-git rofi-lbonn-wayland-git \
  mako swaylock-effects hyprpaper dunst kitty \
  qt5-wayland qt6-wayland qt5ct qt6ct lxappearance \
  xdg-desktop-portal xdg-desktop-portal-hyprland nwg-look \
  grim slurp wl-clipboard brightnessctl pamixer playerctl \
  pipewire wireplumber \
  sddm sddm-kcm polkit-kde-agent \
  # --- Zsh + Terminal + Enhancements ---
  zsh starship fastfetch zoxide bat ripgrep fzf eza btop \
  zsh-autosuggestions zsh-syntax-highlighting zsh-you-should-use zsh-completions \
  # --- GUI Tools ---
  thunar gvfs gvfs-mtp gvfs-gphoto2 gvfs-afc imv udiskie \
  networkmanager network-manager-applet bluez bluez-utils \
  # --- Clipboard manager ---
  cliphist \
  # --- App store GUI + Flatpak plugin ---
  gnome-software gnome-software-packagekit-plugin \
  # --- Gaming & performance ---
  mangohud gamemode lib32-gamemode \
  # --- Dotfiles & management ---
  chezmoi \
  # --- File Launcer Integration ---
  fd fzf xdg-utils
  

# Flatpak + Flathub
log "Enabling Flatpak + Flathub..."
sudo pacman -S --noconfirm flatpak xdg-user-dirs
sudo -u "$TARGET_USER" xdg-user-dirs-update
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Bitwarden + Calendar + Notes via Flatpak
log "Installing Flatpak apps (Bitwarden, Calendar, Notes)..."
sudo -u "$TARGET_USER" flatpak install -y --noninteractive \
  flathub com.bitwarden.desktop \
  flathub org.gnome.Calendar \
  flathub org.gnome.Notes

log "All dependencies installed successfully!"

# ========================================================================================
# --- Section 2: Structure, Services, & Autostarts (Clipboard, udiskie, Network, SDDM) ---
# ========================================================================================

# --- Creating Directories ---
log "Creating essential folders..."
mkdir -p "$USER_HOME/.config"
mkdir -p "$USER_HOME/.config/hypr"
mkdir -p "$USER_HOME/.config/hyprpaper"
mkdir -p "$USER_HOME/.config/autostart"
mkdir -p "$USER_HOME/.config/kitty"
mkdir -p "$USER_HOME/.config/MangoHUD"
mkdir -p "$USER_HOME/.config/waybar/scripts"
mkdir -p "$USER_HOME/Pictures/Wallpapers"
mkdir -p "$USER_HOME/.config/swaylock"
mkdir -p "$USER_HOME/.local/bin"
mkdir -p "$USER_HOME/.config/rofi"
mkdir -p "$USER_HOME/.config/mako"
mkdir -p "$USER_HOME/.local/share/nvim/colors"
mkdir -p "$USER_HOME/.config/nvim/lua/user"
touch "$USER_HOME/.zshrc"

# --- Enable critical services ---
log "Enabling NetworkManager + Bluetooth + SDDM..."
sudo systemctl enable NetworkManager --now
sudo systemctl enable bluetooth --now
sudo systemctl enable sddm

# --- Clipboard Daemon Autostart ---
log "Autostarting cliphist clipboard daemon..."
grep -q "cliphist daemon" "$USER_HOME/.config/hypr/hyprland.conf" || \
echo "exec-once = cliphist daemon" >> "$USER_HOME/.config/hypr/hyprland.conf"

# --- udiskie (Auto-mount USB + Drive GUI) ---
log "Enabling udiskie mount tray on login..."
grep -q "udiskie --tray" "$USER_HOME/.config/hypr/hyprland.conf" || \
echo "exec-once = udiskie --tray" >> "$USER_HOME/.config/hypr/hyprland.conf"

# --- Flatpak GUI Autostart ---
log "Ensuring GNOME Software starts with session..."
cat > "$USER_HOME/.config/autostart/gnome-software.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Software Center
Exec=gnome-software
X-GNOME-Autostart-enabled=true
EOF

# --- Polkit Agent Autostart (Required for GUI elevation) ---
log "Autostarting Polkit KDE agent..."
cat > "$USER_HOME/.config/autostart/polkit-agent.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Polkit KDE Agent
Exec=polkit-kde-authentication-agent-1
X-GNOME-Autostart-enabled=true
EOF

# ---------------------------------------
# Download Wallpaper (swww / hyprpaper use)
# ---------------------------------------

log "Downloading Wallpapers..."
curl -Lo "$USER_HOME/Pictures/Wallpapers/animated1.jpg" https://images-assets.nasa.gov/image/GRC-2024-C-02645/GRC-2024-C-02645~orig.jpg
curl -Lo "$USER_HOME/Pictures/Wallpapers/swaylock-screen.png" https://images-assets.nasa.gov/image/carina_nebula/carina_nebula~orig.png

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config" "$USER_HOME/.local" "$USER_HOME/.zshrc" "$USER_HOME/Pictures"

log "Folder structure ready, services enabled, autostarts injected."


# ============================================================
# --- Section 3: Hyprland, swww, swaylock, mako, hyprpaper ---
# ============================================================

# --- Hyprland Full Configuration ---

log "Creating Hyprland configuration..."
cat > "$USER_HOME/.config/hypr/hyprland.conf" <<EOF
# ┌──────────────────────────────────────┐
# │     Hyprland Core Config             │
# └──────────────────────────────────────┘

exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = swww init
exec-once = swww img "$USER_HOME/Pictures/Wallpapers/animated1.jpg"
exec-once = hyprpaper &
exec-once = waybar &
exec-once = mako &
exec-once = cliphist daemon
exec-once = udiskie --tray
exec-once = swayidle -w \\
  timeout 300 'swaylock -f' \\
  timeout 600 'hyprctl dispatch dpms off' \\
  resume 'hyprctl dispatch dpms on' \\
  before-sleep 'swaylock -f'
exec-once = polkit-kde-authentication-agent-1

bind = SUPER, D, exec, rofi -show drun
bind = SUPER, S, exec, grim -g "\$(slurp)" - | wl-copy

input {
  kb_layout = us
  follow_mouse = 1
}

general {
  gaps_in = 5
  gaps_out = 20
  border_size = 2
  col.active_border = rgba(ffffff88)
  col.inactive_border = rgba(88888888)
}

animations {
  enabled = yes
  bezier = mycurve, 0.05, 0.9, 0.1, 1
  animation = windows, 1, 7, mycurve
}

decoration {
  rounding = 12
  drop_shadow = yes
  shadow_range = 20
  shadow_render_power = 3
  blur {
    enabled = true
    size = 8
    passes = 2
    new_optimizations = on
  }
}

misc {
  force_default_wallpaper = 0
}
EOF

# --- Swaylock (with Tokyo Night Blur Style) ---
log "Configuring swaylock (blur + themed)..."
cat > "$USER_HOME/.config/swaylock/config" <<EOF
image=$USER_HOME/Pictures/Wallpapers/swaylock-screen.png
font-size=14
inside-color=1e1e2ecc
ring-color=89b4faee
line-color=00000000
key-hl-color=94e2d5ff
bs-hl-color=f38ba8ff
separator-color=00000000
ring-ver-color=a6e3a1ff
ring-wrong-color=f38ba8ff
inside-ver-color=1e1e2ecc
inside-wrong-color=1e1e2ecc
EOF

# PAM fix for swaylock auth
sudo sed -i '/^auth.*pam_deny\.so/i auth    sufficient    pam_unix.so try_first_pass nullok' /etc/pam.d/swaylock || true

# --- Wallpaper Setup via swww + Hyprpaper ---
log "Setting animated wallpaper..."

cat > "$USER_HOME/.config/hyprpaper/hyprpaper.conf" <<EOF
preload = "$USER_HOME/Pictures/Wallpapers/animated1.jpg"
wallpaper = ,"$USER_HOME/Pictures/Wallpapers/animated1.jpg"
EOF

# --- Mako Notifications (Tokyo Night Theme) ---
log "Configuring mako notifications..."
cat > "$USER_HOME/.config/mako/config" <<EOF
background-color=#1e1e2ecc
text-color=#cdd6f4
border-color=#89b4fa
border-size=2
border-radius=10
padding=10
max-history=100
default-timeout=5000
icons=true
anchor=top-right
margin=10
width=400
font=JetBrainsMono Nerd Font 11
EOF

# --- Notify-send Backup Hook (uses Mako) ---

log "Creating backup script with mako notifications..."
cat > "$USER_HOME/.local/bin/backup-system.sh" <<'EOF'
#!/bin/bash
notify-send "Backup Started" "Running system backup..."
# your actual backup logic here
sleep 2
notify-send "Backup Complete" "Your system has been backed up successfully!"
EOF
chmod +x "$USER_HOME/.local/bin/backup-system.sh"

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config" "$USER_HOME/.local" "$USER_HOME/Pictures"

log "Hyprland, swaylock, mako, and hyprpaper fully configured."


# ======================================================
# --- Section 4: Waybar Config + Animated Graph Bars ---
# ======================================================

log "Configuring Waybar with Tokyo Night theme and animated graph bars..."

# --- Waybar Config ---
cat > "$USER_HOME/.config/waybar/config.jsonc" <<EOF
{
  "layer": "top",
  "position": "top",
  "height": 30,
  "margin-top": 5,
  "margin-left": 10,
  "margin-right": 10,

  "modules-left": ["clock"],
  "modules-center": ["hyprland/workspaces"],
  "modules-right": [
    "custom/net-graph",
    "custom/disk-graph",
    "bluetooth",
    "network",
    "vpn",
    "battery",
    "disk",
    "cpu",
    "memory",
    "media-player",
    "pulseaudio"
  ],

  "clock": {
    "format": "%a %b %d %I:%M %p",
    "tooltip-format": "<big>%A %B %d %Y</big>\\n<tt>%H:%M:%S</tt>"
  },
  "battery": {
    "format": "{capacity}%",
    "format-charging": "{capacity}% (charging)",
    "tooltip": true
  },
  "network": {
    "format-wifi": "{essid} ({signalStrength}%)",
    "format-ethernet": "Ethernet",
    "format-disconnected": "No Network",
    "tooltip": true
  },
  "vpn": {
    "format": "VPN: {state}",
    "tooltip": true
  },
  "cpu": {
    "format": "CPU: {usage}%",
    "tooltip": false
  },
  "memory": {
    "format": "RAM: {used:0.1f}G",
    "tooltip": false
  },
  "disk": {
    "format": "Disk: {free} free",
    "tooltip": false,
    "interval": 30
  },
  "media-player": {
    "format": "{artist} - {title}",
    "player": "spotify",
    "on-click": "playerctl play-pause",
    "on-scroll-up": "playerctl next",
    "on-scroll-down": "playerctl previous"
  },
  "pulseaudio": {
    "format": "{volume}%",
    "format-muted": "Muted",
    "tooltip": true
  },
  "bluetooth": {
    "format": "{status}",
    "tooltip": true
  },
  "custom/net-graph": {
    "exec": "$USER_HOME/.config/waybar/scripts/net_io_graph.sh",
    "interval": 2,
    "return-type": "json",
    "tooltip": true
  },
  "custom/disk-graph": {
    "exec": "$USER_HOME/.config/waybar/scripts/disk_io_graph.sh",
    "interval": 2,
    "return-type": "json",
    "tooltip": true
  }
}
EOF

# ----------------------------------------------------------
# --- Section: Waybar Style (Font Awesome Icons via CSS) ---
# ----------------------------------------------------------

cat > "$USER_HOME/.config/waybar/style.css" <<EOF
* {
  font-family: "Font Awesome 6 Free", "Font Awesome 6 Brands", "JetBrainsMono Nerd Font", monospace;
  font-size: 12px;
  color: #c0caf5;
}

window#waybar {
  background-color: rgba(26, 27, 38, 0.9);
  border-radius: 10px;
  border: 1px solid #1a1b26;
}

/* Icon Injection using Font Awesome Glyphs */
#clock::before             { content: "\f017"; color: #a6adc8; } /*  */
#battery::before           { content: "\f240"; color: #9ece6a; } /*  */
#cpu::before               { content: "\f2db"; color: #f7768e; } /*  */
#memory::before            { content: "\f233"; color: #7aa2f7; } /*  */
#network::before           { content: "\f6ff"; color: #73daca; } /*  */
#vpn::before               { content: "\f023"; color: #bb9af7; } /*  */
#disk::before              { content: "\f0a0"; color: #cfc9c2; } /*  */
#pulseaudio::before        { content: "\f028"; color: #e0af68; } /*  */
#bluetooth::before         { content: "\f293"; color: #7dcfff; } /*  */
#media-player::before      { content: "\f1bc"; color: #f4dbd6; } /*  */
#custom-net-graph::before  { content: "\f362"; color: #89b4fa; } /*  */
#custom-disk-graph::before { content: "\f0e4"; color: #f7768e; } /*  */

/* Module Blocks */
#clock,
#network,
#battery,
#pulseaudio,
#cpu,
#memory,
#media-player,
#bluetooth,
#vpn,
#disk,
#custom-disk-graph,
#custom-net-graph {
  padding: 0 10px;
  margin: 0 4px;
  border-radius: 6px;
  background-color: #1f2335;
}

/* Animated Graph Bar Backgrounds */
#custom-net-graph,
#custom-disk-graph {
  transition: all 0.4s ease-in-out;
  color: transparent;
  background-size: 100% 100%;
  background-repeat: no-repeat;
}
#custom-net-graph {
  background-image: linear-gradient(to right, #7dcfff, #1f2335);
}
#custom-disk-graph {
  background-image: linear-gradient(to right, #f7768e, #1f2335);
}
EOF


# --- Disk I/O Graph Script ---
cat > "$USER_HOME/.config/waybar/scripts/disk_io_graph.sh" <<'EOF'
#!/bin/bash
read -r read write <<< $(iostat -d -k 1 2 | awk '/sda/ {getline; print $3, $4}')
printf '{"percentage": %.0f, "alt": "Disk I/O"}\n' "$((read + write))"
EOF
chmod +x "$USER_HOME/.config/waybar/scripts/disk_io_graph.sh"

# --- Net I/O Graph Script ---
cat > "$USER_HOME/.config/waybar/scripts/net_io_graph.sh" <<'EOF'
#!/bin/bash
read rx tx <<< $(ifstat -i $(ip route | awk '/default/ {print $5}') 0.1 1 | awk 'NR==3 {print $1, $2}')
printf '{"percentage": %.0f, "alt": "Net I/O"}\n' "$((rx + tx))"
EOF
chmod +x "$USER_HOME/.config/waybar/scripts/net_io_graph.sh"

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/waybar"

log "Waybar ready: Tokyo Night theme, Font Awesome icons, and animated disk/net graphs."


# ====================================================
# --- Section 5: Rofi + Login + Wallpaper + Polkit ---
# ====================================================


# --- Tokyo Night Rofi Theme ---
log "Applying Rofi theme (Tokyo Night)..."

# Clone only the theme directory from adi1090x/rofi (shallow)
git clone --depth=1 --filter=blob:none https://github.com/adi1090x/rofi.git /tmp/rofi-themes

# Copy the tokyo theme
cp /tmp/rofi-themes/files/style/themes/tokyo.rasi "$USER_HOME/.config/rofi/tokyo.rasi"

# Apply light transparency polish
sed -i '/@import/ a element { background-color: rgba(30, 30, 46, 0.90); border-radius: 10px; blur: true; }' "$USER_HOME/.config/rofi/tokyo.rasi"

# Clean up
rm -rf /tmp/rofi-themes

# --- Rofi Config ---
cat > "$USER_HOME/.config/rofi/config.rasi" <<EOF
configuration {
  modi: "drun";
  font: "JetBrainsMono Nerd Font 12";
  icon-theme: "Papirus";
  show-icons: true;
  theme: "$USER_HOME/.config/rofi/tokyo.rasi";
}
EOF

# --- Blurred Power Menu (Tokyo Night compatible) ---
# Create rofi-power.sh
cat > "$USER_HOME/.local/bin/rofi-power.sh" <<'EOF'
#!/bin/bash

chosen=$(printf "⏻ Power Off\n Reboot\n Lock\n󰗽 Logout\n" | rofi -dmenu -i -theme ~/.config/rofi/power.rasi -p "Power Menu")

case "$chosen" in
  *Power\ Off) systemctl poweroff ;;
  *Reboot) systemctl reboot ;;
  *Lock) swaylock -f ;;
  *Logout) hyprctl dispatch exit ;;
esac
EOF

chmod +x "$USER_HOME/.local/bin/rofi-power.sh"

# --- rofi power.rasi with Blur & Rounded Corners ---

cat > "$USER_HOME/.config/rofi/power.rasi" <<EOF
* {
  font: "JetBrainsMono Nerd Font 13";
  background-color: rgba(30, 30, 46, 0.70);
  text-color: #cdd6f4;
  border-radius: 12px;
  blur: true;
}

window {
  width: 400px;
  location: center;
  border: 2px solid #89b4fa;
  padding: 20px;
}

listview {
  spacing: 12px;
}

element {
  padding: 10px;
  background-color: transparent;
  text-color: inherit;
  border-radius: 8px;
}

element selected {
  background-color: rgba(137, 180, 250, 0.3);
  text-color: #ffffff;
}
EOF

# --- SDDM Autologin Setup ---
log "Configuring SDDM autologin..."
sudo sed -i "/^\[Autologin\]/,/^\[/ s/^User=.*/User=$TARGET_USER/" /etc/sddm.conf \
  || echo -e "[Autologin]\nUser=$TARGET_USER" | sudo tee -a /etc/sddm.conf

# --- Polkit KDE Agent Autostart ---
log "Creating polkit agent autostart entry..."

cat > "$USER_HOME/.config/autostart/polkit-agent.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Polkit KDE Agent
Exec=polkit-kde-authentication-agent-1
X-GNOME-Autostart-enabled=true
EOF

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/rofi" \
  "$USER_HOME/.config/hyprpaper" "$USER_HOME/.config/autostart" \
  "$USER_HOME/Pictures/Wallpapers"

log "Rofi + Wallpaper + Autologin + Polkit config completed."

# ======================================
# --- Section 6: Miscellaneous ---
# ======================================

# --- MangoHUD config ---

cat > "$USER_HOME/.config/MangoHUD/MangoHUD.conf" <<EOF
legacy_layout=0
cpu_stats=1
gpu_stats=1
fps=1
frame_timing=0
position=top-right
background_alpha=0.3
toggle_hud=F12
EOF

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/MangoHUD"

# --- File Launcher Integration (fd + fzf + xdg-open) ---
log "Creating fuzzy file launcher script..."

cat > "$USER_HOME/.local/bin/file-launcher.sh" <<'EOF'
#!/bin/bash
selected=$(fd . ~/ | fzf --preview="bat --style=numbers --color=always --line-range=:500 {}" --height=40% --layout=reverse)
[ -n "$selected" ] && xdg-open "$selected"
EOF

chmod +x "$USER_HOME/.local/bin/file-launcher.sh"

log "Binding SUPER + E to fuzzy file launcher..."
# Inject keybind into Hyprland config (if not already present)
grep -q "file-launcher.sh" "$USER_HOME/.config/hypr/hyprland.conf" || \
echo "bind = SUPER, E, exec, ~/.local/bin/file-launcher.sh" >> "$USER_HOME/.config/hypr/hyprland.conf"

# ===================================
# --- Section 7: IDE and Terminal ---
# ===================================


# ------------------------
# --- Neovim IDE Setup ---
# ------------------------

log "Installing Neovim + Plugins + Tokyo Night config..."
yay -S --needed --noconfirm neovim unzip ripgrep fd nodejs npm \
  lazygit xclip python-pynvim

# --- Create Neovim config structure ---
mkdir -p "$USER_HOME/.config/nvim/lua/user"

# --- init.lua (main entrypoint) ---
cat > "$USER_HOME/.config/nvim/init.lua" << 'EOF'
require("user.options")
require("user.plugins")
require("user.colorscheme")
require("user.lsp")
require("user.cmp")
require("user.treesitter")
require("user.keymaps")
require("user.statusline")
EOF

# --- options.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/options.lua" << 'EOF'
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.mouse = "a"
EOF

# --- plugins.lua (lazy.nvim) ---
cat > "$USER_HOME/.config/nvim/lua/user/plugins.lua" << 'EOF'
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  "folke/tokyonight.nvim",
  "nvim-lua/plenary.nvim",
  "nvim-treesitter/nvim-treesitter",
  "nvim-tree/nvim-tree.lua",
  "neovim/nvim-lspconfig",
  "hrsh7th/nvim-cmp",
  "hrsh7th/cmp-nvim-lsp",
  "L3MON4D3/LuaSnip",
  "saadparwaiz1/cmp_luasnip",
  "nvim-lualine/lualine.nvim",
  "folke/which-key.nvim"
})
EOF

# --- colorscheme.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/colorscheme.lua" << 'EOF'
vim.cmd("colorscheme tokyonight")
EOF

# --- lsp.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/lsp.lua" << 'EOF'
local lspconfig = require("lspconfig")
lspconfig.lua_ls.setup({})
lspconfig.tsserver.setup({})
lspconfig.pyright.setup({})
EOF

# --- cmp.lua (auto-completion) ---
cat > "$USER_HOME/.config/nvim/lua/user/cmp.lua" << 'EOF'
local cmp = require("cmp")
local luasnip = require("luasnip")

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ["<Tab>"] = cmp.mapping.select_next_item(),
    ["<S-Tab>"] = cmp.mapping.select_prev_item(),
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
  }),
  sources = {
    { name = "nvim_lsp" },
    { name = "luasnip" },
  },
})
EOF

# --- treesitter.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/treesitter.lua" << 'EOF'
require("nvim-treesitter.configs").setup({
  ensure_installed = { "lua", "python", "bash", "javascript", "typescript", "json", "html", "css" },
  highlight = { enable = true },
})
EOF

# keymaps.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/keymaps.lua" << 'EOF'
vim.g.mapleader = " "
local keymap = vim.keymap.set

keymap("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle File Explorer" })
require("which-key").setup {}
EOF

# --- statusline.lua ---
cat > "$USER_HOME/.config/nvim/lua/user/statusline.lua" << 'EOF'
require("lualine").setup({
  options = { theme = "tokyonight" }
})
EOF

# --- Tokyo Night Colors ---
log "Downloading Tokyo Night theme..."
git clone --depth=1 --filter=blob:none https://github.com/folke/tokyonight.nvim.git /tmp/tokyonight.nvim
cp -r /tmp/tokyonight.nvim/colors "$USER_HOME/.config/nvim/" || true
rm -rf /tmp/tokyonight.nvim

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/nvim"
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.local/share/nvim"

log "Neovim IDE setup complete. Launch with: nvim"

# -----------------------------------------------------
# --- Terminal Setup: Kitty, Zsh, Starship + Extras ---
# -----------------------------------------------------

log "Configuring Terminal environment (Zsh + Starship + Kitty)..."

# Set Zsh as default shell for the user
chsh -s /bin/zsh "$TARGET_USER"

# --- .zshrc Enhancements ---
cat > "$USER_HOME/.zshrc" <<'EOF'
export EDITOR=nvim
export STARSHIP_CONFIG="\$HOME/.config/starship.toml"
eval "\$(starship init zsh)"
autoload -Uz compinit && compinit

# Zsh Plugins
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/you-should-use/you-should-use.plugin.zsh

# System Overview
fastfetch

# CLI Productivity Aliases
alias ls="eza --icons"
alias cat="bat"
alias top="btop"
eval "\$(zoxide init zsh)"

# Git Shortcuts
alias gs='git status'
alias gc='git commit -m'
alias gp='git push'

# Docker Shortcuts
alias dcu='docker compose up -d'
alias dcd='docker compose down'

# Enable MangoHUD for Vulkan/OpenGL
export MANGOHUD=1
EOF

# --- Starship prompt configuration ---
cat > "$USER_HOME/.config/starship.toml" <<EOF
add_newline = false

[character]
success_symbol = "[➜](green)"
error_symbol = "[✗](red)"

[time]
disabled = false
format = " [\[\$time\]](blue)"
EOF

# --- Kitty Terminal Configuration ---
cat > "$USER_HOME/.config/kitty/kitty.conf" <<EOF
font_family      JetBrainsMono Nerd Font
font_size        12.0
enable_audio_bell no
scrollback_lines 10000
background_opacity 0.95
EOF

# --- Permissions ---
chown -R --no-dereference "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config" "$USER_HOME/.zshrc"


# --- Done ---
log "Hyperland + Full Enhancements ready."
echo -e "\nLog out and select Hyprland in SDDM.\nRule the void, $TARGET_USER.\n"
# Stop sudo keep-alive
kill $KEEP_ALIVE_PID

