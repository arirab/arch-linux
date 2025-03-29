#!/bin/bash

set -e
trap 'echo "[!] Install failed. See /root/arch-install-error.log for details."; exit 1' ERR

LOG_FILE="/root/arch-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ========== USER PROMPTS ==========
echo -e "\n Welcome to Arch Installer"
read -rp " Enter hostname [v01dsh3ll]: " HOSTNAME
HOSTNAME=${HOSTNAME:-v01dsh3ll}

read -rp " Enter target disk [/dev/nvme0n1]: " DISK
DISK=${DISK:-/dev/nvme0n1}

read -rp " Enter keyfile path [/root/secrets/crypto_keyfile.bin]: " KEYFILE
KEYFILE=${KEYFILE:-/root/secrets/crypto_keyfile.bin}

read -rp " Enter timezone [America/Denver]: " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Denver}

read -rp " Enter keyboard layout [us]: " KEYMAP
KEYMAP=${KEYMAP:-us}

CRYPT_NAME="cryptarch"
VG_NAME="vg0"
EFI_SIZE="1024MiB"
LUKS_TYPE="luks2"

# ========== PARTITION ==========
echo -e "\n[+] Partitioning $DISK..."
parted "$DISK" --script mklabel gpt \
  mkpart ESP fat32 1MiB "$EFI_SIZE" \
  set 1 esp on \
  mkpart primary "$EFI_SIZE" 100%

EFI_PART="${DISK}p1"
LUKS_PART="${DISK}p2"
mkfs.fat -F32 "$EFI_PART"

# ========== ENCRYPTION ==========
echo -e "\n[+] Encrypting root partition..."
read -srp " Enter LUKS Passphrase [default: Encryption-Password]: " luks_passphrase
luks_passphrase=${luks_passphrase:-Encryption-Password}
echo
echo -n "$luks_passphrase" | cryptsetup luksFormat --type "$LUKS_TYPE" --pbkdf pbkdf2 --key-file=- "$LUKS_PART"
echo -n "$luks_passphrase" | cryptsetup open --key-file=- "$LUKS_PART" "$CRYPT_NAME"

# ========== LVM ==========
pvcreate /dev/mapper/$CRYPT_NAME
vgcreate $VG_NAME /dev/mapper/$CRYPT_NAME
lvcreate -L 8G $VG_NAME -n swap
lvcreate -l 100%FREE $VG_NAME -n root

# ========== FILESYSTEMS ==========
mkswap "/dev/$VG_NAME/swap"
mkfs.btrfs -f "/dev/$VG_NAME/root"

# ========== BTRFS SUBVOLUMES ==========
mount "/dev/$VG_NAME/root" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
umount /mnt

# ========== MOUNTING ==========
mount -o compress=zstd,subvol=@ /dev/$VG_NAME/root /mnt
mkdir -p /mnt/{home,var,tmp,efi,.snapshots}
mount -o compress=zstd,subvol=@home /dev/$VG_NAME/root /mnt/home
mount -o compress=zstd,subvol=@var /dev/$VG_NAME/root /mnt/var
mount -o compress=zstd,subvol=@tmp /dev/$VG_NAME/root /mnt/tmp
mount -o compress=zstd,subvol=@snapshots /dev/$VG_NAME/root /mnt/.snapshots
mount "$EFI_PART" /mnt/efi
swapon "/dev/$VG_NAME/swap"

# ========== BASE INSTALL ==========
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers \
  linux-firmware lvm2 sudo vim btrfs-progs grub efibootmgr networkmanager \
  dhcpcd wpa_supplicant iwd amd-ucode snapper snap-pac grub-btrfs

genfstab -U /mnt >> /mnt/etc/fstab

[[ -f ./01-user-creation.sh ]] && cp ./01-user-creation.sh /mnt/root/ && chmod +x /mnt/root/01-user-creation.sh

# ========== CHROOT SETUP ==========
arch-chroot /mnt /bin/bash <<EOF
mkdir -p \$(dirname "$KEYFILE")
dd if=/dev/urandom of="$KEYFILE" bs=1 count=64
chmod 600 "$KEYFILE"
cryptsetup luksAddKey "$LUKS_PART" "$KEYFILE"

echo "$CRYPT_NAME UUID=\$(blkid -s UUID -o value $LUKS_PART) $KEYFILE luks" >> /etc/crypttab

sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
echo "FILES=($KEYFILE)" >> /etc/mkinitcpio.conf
mkinitcpio -P

sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$(blkid -s UUID -o value $LUKS_PART):$CRYPT_NAME root=/dev/$VG_NAME/root cryptkey=rootfs:$KEYFILE\"|" /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
echo "GRUB_DEFAULT=saved" >> /etc/default/grub
echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

systemctl enable NetworkManager

chmod 750 /.snapshots
chown :wheel /.snapshots
snapper -c root create-config /
# Configure Snapper retention policy
sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_MIN_AGE=.*/NUMBER_MIN_AGE="1800"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="50"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="10"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="10"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer
systemctl enable --now grub-btrfs.path
EOF

# ========== SET ROOT PASSWORD MANUALLY ==========
echo -e "\n[!] Entering chroot to set root password manually..."
arch-chroot /mnt /bin/bash -c "passwd"

# ========== FINALIZE ==========
umount -R /mnt
swapoff "/dev/$VG_NAME/swap"

echo -e "\n[\u2713] Installation Complete"
echo "Run /root/01-user-creation.sh after reboot."
echo "To reboot now: sudo reboot"