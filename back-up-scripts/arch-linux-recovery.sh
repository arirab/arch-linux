#!/bin/bash
# Save as /mnt/boot/arch-recovery.sh or /mnt/root/arch-recovery.sh

CRYPT_NAME="cryptarch"
VG_NAME="vg0"
DISK="/dev/nvme0n1"

echo "[*] Unlocking LUKS container..."
cryptsetup open ${DISK}p2 $CRYPT_NAME || exit 1

echo "[*] Activating LVM volumes..."
vgchange -ay || exit 1

echo "[*] Mounting root filesystem..."
mount -o subvol=@ /dev/$VG_NAME/root /mnt

echo "[*] Mounting subvolumes..."
mount -o subvol=@home /dev/$VG_NAME/root /mnt/home
mount -o subvol=@var /dev/$VG_NAME/root /mnt/var
mount -o subvol=@tmp /dev/$VG_NAME/root /mnt/tmp
mount -o subvol=@snapshots /dev/$VG_NAME/root /mnt/.snapshots

echo "[*] Mounting EFI partition..."
mount ${DISK}p1 /mnt/boot

echo "[*] Enabling swap..."
swapon /dev/$VG_NAME/swap

echo "[*] Entering chroot..."
arch-chroot /mnt
