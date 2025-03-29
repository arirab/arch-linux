#!/bin/bash

set -e  # Exit on error

echo "==============================="
echo " NVIDIA Driver Auto-Installer "
echo "==============================="

# ===================================
# Prerequisite Checks
# ===================================

# --- Check if yay is installed ---
if ! command -v yay &> /dev/null; then
  echo "❌ Error: yay is not installed. Please install yay first."
  exit 1
fi

# --- Check if run as root (warn but don't exit) ---
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Note: Some steps require root. You'll be prompted for sudo access."
fi

# =======================
# Install NVIDIA Packages
# =======================
echo "[1/7] Installing NVIDIA drivers..."

yay -S --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings

# ======================
# Enable DRM KMS in GRUB
# ======================
echo "[2/7] Enabling DRM Kernel Mode Setting in GRUB..."

GRUB_FILE="/etc/default/grub"
if ! grep -q "nvidia-drm.modeset=1" $GRUB_FILE; then
  sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 nvidia-drm.modeset=1 nvidia-drm.fbdev=1"/' $GRUB_FILE
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  echo "✅ GRUB updated."
else
  echo "ℹ️  DRM KMS already configured in GRUB."
fi

# ====================
# Configure mkinitcpio
# ====================
echo "[3/7] Configuring mkinitcpio for NVIDIA..."

sudo sed -i '/^MODULES=/ s/(/(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
sudo sed -i '/^HOOKS=/ s/kms //' /etc/mkinitcpio.conf
sudo mkinitcpio -P
echo "✅ mkinitcpio regenerated."

# ==================
# Set up Pacman Hook
# ==================
echo "[4/7] Setting up Pacman hook for NVIDIA rebuild..."

cd "$HOME"
HOOK_FILE="nvidia.hook"

wget -q --show-progress https://raw.githubusercontent.com/korvahannu/arch-nvidia-drivers-installation-guide/main/nvidia.hook

# --- Validate hook file ---
if [[ ! -f $HOOK_FILE ]]; then
  echo "❌ Failed to download nvidia.hook. Aborting."
  exit 1
fi

# --- Customize hook ---
sudo sed -i 's/Target=nvidia/Target=nvidia-open-dkms/' $HOOK_FILE
sudo sed -i '/Target=linux/a Target=linux-lts' $HOOK_FILE
sudo sed -i 's|Exec=.*|Exec=/usr/bin/mkinitcpio -P \&\& /usr/bin/lsmod | grep nvidia \&\& /usr/bin/nvidia-smi \&\& /usr/bin/nvidia-smi -q | grep "Persistence Mode"|' $HOOK_FILE

# --- Install hook ---
sudo mkdir -p /etc/pacman.d/hooks
sudo mv "$HOOK_FILE" /etc/pacman.d/hooks/

echo "✅ Pacman hook installed."

# =======================
# Enable Persistence Mode
# =======================
echo "[5/7] Enabling NVIDIA Persistence Mode..."

sudo tee /etc/systemd/system/nvidia-persistence.service > /dev/null <<EOF
[Unit]
Description=NVIDIA Persistence Mode
After=multi-user.target

[Service]
ExecStart=/usr/bin/nvidia-smi -pm 1
RemainAfterExit=yes
ExecStop=/bin/true
Type=simple

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable nvidia-persistence
sudo systemctl start nvidia-persistence
echo "✅ Persistence mode enabled."

# ==========================
# Load NVIDIA Kernel Modules
# ==========================
echo "[6/7] Loading NVIDIA kernel modules..."

echo "nvidia" | sudo tee /etc/modules-load.d/nvidia.conf > /dev/null
sudo modprobe nvidia || true
echo "✅ NVIDIA module loaded."

# =============
# Reboot Prompt
# =============
echo "[7/7] Setup complete."

read -rp "Reboot now to apply changes? [y/N]: " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
  sudo reboot
else
  echo "Reboot skipped. Please reboot manually when ready."
fi