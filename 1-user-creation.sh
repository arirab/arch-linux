#!/bin/bash

set -e
trap 'echo "[!] User Creation Failled. See /var/log/user-creation.log for details."; exit 1' ERR

# Redirect all output to a log file for debugging
exec > >(tee -a /var/log/user-creation.log) 2>&1

# ==================================
# User Creation Script
# Creates a user with full sudo privileges
# ==================================

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

# --- Prompt for Username ---
read -rp "Enter desired username: " USERNAME

# --- Prompt for Password ---
read -rsp "Enter password for $USERNAME: " USER_PASS
echo
read -rsp "Confirm password: " USER_PASS_CONFIRM
echo

if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
  echo " Passwords do not match. Aborting."
  exit 1
fi

# --- Create User ---
if ! id "$USERNAME" &>/dev/null; then
  log "Creating user '$USERNAME' with full privileges..."
  sudo useradd -m -G wheel,users,audio,video,storage,network -s /bin/zsh "$USERNAME"
  echo "$USERNAME:$USER_PASS" | sudo chpasswd
else
  log "User '$USERNAME' already exists. Skipping creation."
fi

# --- Sudoers ---
log "Granting secure sudo privileges to '$USERNAME'..."
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-$USERNAME > /dev/null
sudo chmod 440 /etc/sudoers.d/99-$USERNAME

# --- Wheel Group Defaults ---
log "Ensuring wheel group has passwordless sudo..."
if ! sudo grep -q '^%wheel ALL=(ALL:ALL) NOPASSWD: ALL' /etc/sudoers; then
  echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers > /dev/null
fi

# --- Reboot Prompt ---
echo -e "\n User setup complete."
read -rp "Would you like to reboot now? (y/N): " REBOOT
if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
  log "Rebooting..."
  sudo reboot
else
  echo "You can reboot later with: sudo reboot"
fi
