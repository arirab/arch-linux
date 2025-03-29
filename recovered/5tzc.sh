#!/bin/bash

set -e

# ---------------------------------------------
# 00-user-creation.sh
# Step 2: Create User with Full Privileges
# ---------------------------------------------

USERNAME="rock"

log() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

if ! id "$USERNAME" &>/dev/null; then
  log "Creating user '$USERNAME' with full privileges..."
  sudo useradd -m -G wheel,users,audio,video,storage,network -s /bin/zsh "$USERNAME"
  echo "$USERNAME:changeme" | sudo chpasswd
else
  log "User '$USERNAME' already exists. Skipping creation."
fi

# Add secure sudoers rule via sudoers.d
log "Granting secure sudo privileges to '$USERNAME'..."
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-rock > /dev/null
sudo chmod 440 /etc/sudoers.d/99-rock

# ---------------------------------------------
# Step 3: Sudoers Tweaks (No Password for Wheel)
# ---------------------------------------------
log "Tweaking sudoers: Allow wheel group passwordless sudo..."
if ! sudo grep -q '^%wheel ALL=(ALL:ALL) NOPASSWD: ALL' /etc/sudoers; then
  echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers > /dev/null
fi

# ---------------------------------------------
# Step 4: Harden Root Access
# ---------------------------------------------
log "Locking root account (disable password login)..."
sudo passwd -l root

# ---------------------------------------------
# Step 5: SSH Hardening
# ---------------------------------------------
log "Applying SSH security settings..."
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

log "✅ User & hostname setup complete. Login as '$USERNAME'."
log "🛑 Default password is 'changeme'. Change it immediately!"
