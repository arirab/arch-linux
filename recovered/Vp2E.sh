#!/bin/bash

set -e
trap 'echo "❌ Failed: Check errors above."; exit 1' ERR

# ======================================================
# /Pantheon
# Adds a new disk to the existing encrypted Pantheon Btrfs RAID
# Auto-partition, encrypt, unlock, add to array, balance
# ======================================================

log() {
  echo -e "\033[1;35m[+] $1\033[0m"
}

# --- CONFIG ---
KEYFILE="/root/secrets/crypto_keyfile.bin"
USERNAME="rock"
ARCHIVE_MOUNTPOINT="/Pantheon"

# --- USER INPUT ---
read -rp "Enter new archive disk (e.g., /dev/sdc): " NEW_DISK

if [[ ! -b $NEW_DISK ]]; then
  echo "❌ Disk $NEW_DISK does not exist."; exit 1
fi

PARTITION="${NEW_DISK}1"
MAPPER_NAME="$(basename $NEW_DISK)crypt"

# --- New Partition, Encrypt, Unlock ---
log "Partitioning $NEW_DISK..."
sudo parted "$NEW_DISK" --script mklabel gpt mkpart primary 0% 100%

log "Encrypting $PARTITION with LUKS2..."
sudo cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "$PARTITION" "$KEYFILE"
sudo cryptsetup open "$PARTITION" "$MAPPER_NAME" --key-file "$KEYFILE"

# --- Add to existing Btrfs RAID ---
log "Adding /dev/mapper/$MAPPER_NAME to existing $ARCHIVE_MOUNTPOINT volume..."
sudo btrfs device add -f "/dev/mapper/$MAPPER_NAME" "$ARCHIVE_MOUNTPOINT"
sudo btrfs balance start -dconvert=raid0 -mconvert=raid1 "$ARCHIVE_MOUNTPOINT" || true

# --- Update crypttab + fstab ---
LUKS_UUID=$(blkid -s UUID -o value "$PARTITION")
log "Updating /etc/crypttab and /etc/fstab..."
echo "$MAPPER_NAME UUID=$LUKS_UUID $KEYFILE luks" | sudo tee -a /etc/crypttab

# Only mount via first device still (handled in original fstab)

# --- Rebuild initramfs ---
sudo mkinitcpio -P

log "📀 New disk $NEW_DISK added to Pantheon successfully!"
log "You can verify with: btrfs filesystem show $ARCHIVE_MOUNTPOINT"


