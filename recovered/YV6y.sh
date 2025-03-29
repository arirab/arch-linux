#!/bin/bash

set -e
trap 'echo "[!] Cleanup failed. Check commands manually."; exit 1' ERR

echo -e "\n[⚠] This will reset all partitions, volumes, and crypto mappings for a fresh Arch install."
read -rp "Enter the target disk to clean (e.g., /dev/nvme0n1): " DISK

if [[ ! -b "$DISK" ]]; then
  echo "[!] Invalid block device: $DISK"
  exit 1
fi

echo -e "\n[*] Unmounting everything from /mnt..."
umount -R /mnt 2>/dev/null || echo "Nothing mounted."

echo "[*] Turning off swap..."
swapoff -a || true

echo "[*] Closing any LUKS mappings..."
cryptsetup close cryptarch 2>/dev/null || echo "No LUKS mapping found."

echo "[*] Deactivating any LVM volume groups..."
vgchange -an vg0 2>/dev/null || echo "No LVM VG active."

echo -e "\n[!!] This will wipe ALL partition signatures on $DISK!"
read -rp "Type 'YES' to wipe $DISK: " confirm
if [[ "$confirm" == "YES" ]]; then
  echo "[*] Wiping filesystem signatures..."
  wipefs -a "$DISK"
  echo "[✓] $DISK wiped clean."
else
  echo "[✗] Wipe cancelled."
fi

echo -e "\n[✓] Cleanup complete. You may now re-run your installer."