#!/bin/bash

set -e
trap 'echo "❌ Failed: Check errors above."; exit 1' ERR

# ======================================================
# 📀 20-data-archive-setup.sh
# Sets up encrypted /Data (ext4) and /Pantheon (RAID0 Btrfs)
# Auto-unlock with keyfile, ownership, crypttab + fstab entries
# ======================================================

log() {
  echo -e "\033[1;36m[+] $1\033[0m"
}

# Config
KEYFILE="/root/secrets/crypto_keyfile.bin"
DATA_DEV="/dev/sda1"
ARCHIVE_DEVS=(/dev/sdb)
ARCHIVE_NAME="pantheon"
USERNAME="rock"

# ---------------------------------------------
# 1. Setup /Data (1TB) — ext4 + LUKS2
# ---------------------------------------------
log "Setting up /Data encrypted volume..."

sudo parted /dev/sda --script mklabel gpt mkpart primary 0% 100%
sudo cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "$DATA_DEV" "$KEYFILE"
sudo cryptsetup open "$DATA_DEV" data --key-file "$KEYFILE"
sudo mkfs.ext4 /dev/mapper/data

sudo mkdir -p /Data
sudo mount /dev/mapper/data /Data

# Get UUIDs
DATA_LUKS_UUID=$(blkid -s UUID -o value "$DATA_DEV")
DATA_FS_UUID=$(blkid -s UUID -o value /dev/mapper/data)

log "Configuring /etc/crypttab and /etc/fstab for /Data..."
echo "data UUID=$DATA_LUKS_UUID $KEYFILE luks" | sudo tee -a /etc/crypttab
echo "UUID=$DATA_FS_UUID /Data ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

sudo chown -R $USERNAME:users /Data
sudo chmod -R 750 /Data
sudo usermod -aG users $USERNAME

# ---------------------------------------------
# 2. Setup /Pantheon (Encrypted Btrfs RAID0 with LUKS2)
# ---------------------------------------------
log "Setting up /Pantheon RAID0 with Btrfs over LUKS2..."

for dev in "${ARCHIVE_DEVS[@]}"; do
  part="${dev}1"
  sudo parted "$dev" --script mklabel gpt mkpart primary 0% 100%
  sudo cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "$part" "$KEYFILE"
  name="$(basename $dev)crypt"
  sudo cryptsetup open "$part" "$name" --key-file "$KEYFILE"
done

CRYPT_DEVS=()
for dev in "${ARCHIVE_DEVS[@]}"; do
  CRYPT_DEVS+=("/dev/mapper/$(basename $dev)crypt")
done

sudo mkfs.btrfs -f -d raid0 "${CRYPT_DEVS[@]}"

sudo mkdir -p /Pantheon
sudo mount "${CRYPT_DEVS[0]}" /Pantheon

ARCHIVE_UUIDS=()
for dev in "${ARCHIVE_DEVS[@]}"; do
  uuid=$(blkid -s UUID -o value "${dev}1")
  ARCHIVE_UUIDS+=("$uuid")
done

log "Appending /Pantheon unlock entries to crypttab..."
for i in "${!ARCHIVE_UUIDS[@]}"; do
  echo "$(basename ${ARCHIVE_DEVS[$i]})crypt UUID=${ARCHIVE_UUIDS[$i]} $KEYFILE luks" | sudo tee -a /etc/crypttab
  echo "# ${ARCHIVE_DEVS[$i]} added for /Pantheon" | sudo tee -a /etc/crypttab
  echo "# Mapper: $(basename ${ARCHIVE_DEVS[$i]})crypt" | sudo tee -a /etc/crypttab
  echo "" | sudo tee -a /etc/crypttab

  echo "/dev/mapper/$(basename ${ARCHIVE_DEVS[$i]})crypt /Pantheon btrfs defaults,noatime,compress=zstd 0 2" | sudo tee -a /etc/fstab
  break # Only mount from the first for now (Btrfs RAID handles the rest)
done

sudo chown -R $USERNAME:users /Pantheon
sudo chmod -R 750 /Pantheon

# ---------------------------------------------
# 3. Finish & Rebuild Initramfs
# ---------------------------------------------
log "Rebuilding initramfs to include new crypttab entries..."
sudo mkinitcpio -P

# ---------------------------------------------
# 📌 RAID Redundancy Note
# ---------------------------------------------
# We use RAID0 for media data (fast streaming)
# BUT set metadata to RAID1 to protect integrity and prevent FS loss.
# It’s a best-of-both-worlds balance — speed and safety.
#
# Want full speed over everything? Change this line below:
# sudo btrfs balance start -dconvert=raid0 -mconvert=raid0 /Pantheon
#
# But Elara recommends:
sudo btrfs balance start -dconvert=raid0 -mconvert=raid1 /Pantheon || true

log "✅ /Data and /Pantheon volumes are now ready and auto-unlockable at boot."
log "Run 'sudo reboot' and enjoy your fortress of storage."