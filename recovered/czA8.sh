#!/bin/bash

set -e
trap 'echo "[!] Cleanup failed. Check commands manually."; exit 1' ERR

echo -e "\n[!] This will reset all partitions, volumes, and crypto mappings for a fresh Arch install."
read -rp "Enter the target disk to clean (e.g., /dev/nvme0n1): " DISK

# Sanity check
if [[ ! -b "$DISK" ]]; then
  echo "[!] Invalid block device: $DISK"
  exit 1
fi

# Unmount all
echo "[*] Unmounting everything from /mnt..."
umount -R /mnt 2>/dev/null || echo "Nothing mounted."

# Disable swap
echo "[*] Turning off swap..."
swapoff -a || true

# Close all LUKS mappings
echo "[*] Closing any LUKS mappings..."
for mapper in $(ls /dev/mapper 2>/dev/null | grep -vE '^control$'); do
  cryptsetup close "$mapper" 2>/dev/null || true
done

# Deactivate all LVM
echo "[*] Deactivating any LVM volume groups..."
vgchange -an || true

# Detach any remaining device-mapper nodes
echo "[*] Removing leftover device-mapper volumes..."
dmsetup ls --target crypt | awk '{print $1}' | xargs -r -n1 dmsetup remove || true

# Force kill any busy holders
echo "[*] Forcing cleanup of partitions under $DISK..."
for dev in $(lsblk -lnpo NAME | grep "$DISK" | tac); do
  umount "$dev" 2>/dev/null || true
  cryptsetup close "$(basename "$dev")" 2>/dev/null || true
  dmsetup remove "$(basename "$dev")" 2>/dev/null || true
done

# Confirm wipe
echo -e "\n[!!!] This will wipe ALL partition signatures on $DISK!"
read -rp "Type 'YES' to wipe $DISK: " confirm
if [[ "$confirm" != "YES" ]]; then
  echo "Aborted."
  exit 0
fi

# Final wipe
echo "[*] Wiping filesystem signatures..."
wipefs -a "$DISK"

echo -e "\n[✔] Cleanup complete. Disk is now clean."