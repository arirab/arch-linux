#!/bin/bash

set -e
trap 'echo "[!] User creation failed. See /var/log/user-creation.log for details."; exit 1' ERR

# Redirect all output to a log file for debugging
exec > >(tee -a /var/log/user-creation.log) 2>&1

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

echo -e "\n Welcome to user creation setup"

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
  useradd -m -G wheel,audio,video,storage,network,power -s /bin/zsh "$USERNAME"
  echo "$USERNAME:$USER_PASS" | chpasswd
else
  log "User '$USERNAME' already exists. Skipping creation."
fi

# --- Sudoers ---
log "Granting sudo privileges to '$USERNAME'..."
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" > "/etc/sudoers.d/99-$USERNAME"
chmod 440 "/etc/sudoers.d/99-$USERNAME"

# --- Wheel Group Defaults ---
if ! grep -q '^%wheel ALL=(ALL:ALL) NOPASSWD: ALL' /etc/sudoers; then
  log "Enabling wheel group sudoers override..."
  echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi

# --- Success ---
log "User setup complete."
echo
read -rp "Would you like to reboot now? (y/N): " REBOOT
if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
  log "Rebooting..."
  reboot
else
  echo "You can reboot later with: sudo reboot"
fi
