#!/bin/bash
set -e
trap 'echo "[!] Install failed. See /root/arch-install-error.log for details."; exit 1' ERR

LOG_FILE="/root/arch-install-error.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- USER PROMPTS ---
echo -e "\n Welcome to Arch Linux Installer (systemd-boot version)"

read -rp " Enter Username [Default: rock]: " USERNAME
USERNAME=${USERNAME:-rock}
read -rp " Enter Hostname [Default: v01dsh3ll]: " HOSTNAME
HOSTNAME=${HOSTNAME:-v01dsh3ll}
read -rp " Enter Target Disk [Default: /dev/nvme0n1]: " DISK
DISK=${DISK:-/dev/nvme0n1}
read -rp " Enter Timezone [Default: America/Denver]: " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Denver}
read -rp " Enter Keyboard Layout [Default: us]: " KEYMAP
KEYMAP=${KEYMAP:-us}
read -rp " Enter LUKS Container Name [Default: cryptarch]: " CRYPT_NAME
CRYPT_NAME=${CRYPT_NAME:-cryptarch}
read -rp " Enter LVM Volume Group Name [Default: vg0]: " VG_NAME
VG_NAME=${VG_NAME:-vg0}
read -rp " Enter EFI Partition Size [Default: 1024MiB]: " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-1024MiB}

LUKS_TYPE="luks2"

# --- PARTITION ---
echo -e "\n[+] Partitioning $DISK..."
parted "$DISK" --script mklabel gpt \
  mkpart ESP fat32 1MiB "$EFI_SIZE" \
  set 1 esp on \
  mkpart primary "$EFI_SIZE" 100%

EFI_PART="${DISK}p1"
LUKS_PART="${DISK}p2"
if mountpoint -q "$EFI_PART"; then
  echo "[!] $EFI_PART is already mounted. Aborting for safety."
  exit 1
fi
mkfs.fat -F32 "$EFI_PART"

# --- ENCRYPTION ---
echo -e "\n[+] Encrypting root partition..."
read -srp " Enter LUKS Passphrase [Default: Encryption-Password]: " luks_passphrase
luks_passphrase=${luks_passphrase:-Encryption-Password}
echo
echo -n "$luks_passphrase" | cryptsetup luksFormat --type "$LUKS_TYPE" --pbkdf pbkdf2 --key-file=- "$LUKS_PART"
echo -n "$luks_passphrase" | cryptsetup open --key-file=- "$LUKS_PART" "$CRYPT_NAME"

# --- LVM ---
pvcreate /dev/mapper/$CRYPT_NAME
vgcreate $VG_NAME /dev/mapper/$CRYPT_NAME
lvcreate -L 8G $VG_NAME -n swap
lvcreate -l 100%FREE $VG_NAME -n root

# --- FILESYSTEMS ---
mkswap "/dev/$VG_NAME/swap"
mkfs.btrfs -f "/dev/$VG_NAME/root"

# --- BTRFS SUBVOLUMES ---
mount "/dev/$VG_NAME/root" /mnt
for subvol in @ @home @var @tmp @snapshots; do
  btrfs subvolume create "/mnt/$subvol"
done
umount /mnt

# --- MOUNTING ---
mount -o compress=zstd,subvol=@ "/dev/$VG_NAME/root" /mnt
mkdir -p /mnt/{home,var,tmp,boot,.snapshots}
mount -o compress=zstd,subvol=@home "/dev/$VG_NAME/root" /mnt/home
mount -o compress=zstd,subvol=@var "/dev/$VG_NAME/root" /mnt/var
mount -o compress=zstd,subvol=@tmp "/dev/$VG_NAME/root" /mnt/tmp
mount -o compress=zstd,subvol=@snapshots "/dev/$VG_NAME/root" /mnt/.snapshots
mount "$EFI_PART" /mnt/boot

swapon "/dev/$VG_NAME/swap"

# --- BASE INSTALL ---
pacstrap /mnt base base-devel linux-lts linux-lts-headers \
  linux-firmware lvm2 sudo vim btrfs-progs networkmanager \
  dhcpcd wpa_supplicant iwd amd-ucode snapper snap-pac zsh

genfstab -U /mnt >> /mnt/etc/fstab

# Export variables to file
cat <<EOF > /mnt/root/installer-vars.sh
LUKS_PART="${DISK}p2"
CRYPT_NAME="$CRYPT_NAME"
VG_NAME="$VG_NAME"
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
KEYMAP="$KEYMAP"
USERNAME="$USERNAME"
luks_passphrase="$luks_passphrase"
EOF

# --- CHROOT SETUP ---
arch-chroot /mnt /bin/bash <<'EOF'
set -e

source /root/installer-vars.sh

# --- Initramfs ---
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-encrypt block lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# --- systemd-boot Setup ---
bootctl install
UUID=$(blkid -s UUID -o value "$LUKS_PART")

cat <<BOOT > /boot/loader/entries/arch.conf
title   Arch Linux (LTS)
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options rd.luks.name=$UUID=$CRYPT_NAME root=/dev/mapper/$VG_NAME-root rootflags=subvol=@ quiet rw
BOOT

cat <<CONF > /boot/loader/loader.conf
default arch.conf
timeout 3
console-mode max
editor no
CONF

# --- Localization and Hostname ---
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# --- Create User ---
useradd -m -G wheel,audio,video,storage,network,power -s /bin/zsh "$USERNAME"
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-$USERNAME
chmod 440 /etc/sudoers.d/99-$USERNAME
EOF

# --- FINAL STEPS ---
echo -e "\n[\u2713] Installation Complete (systemd-boot)"
echo -e "========================================="
echo -e " 1. Enter chroot by running arch-chroot /mnt /bin/bash"
echo -e " 2. Run: passwd && passwd $USERNAME"
echo -e " 3. Exit out from chroot and Unmount /mnt and then reboot!"
echo -e " 4. After reboot run 'systemctl enable NetworkManager'"
echo -e "========================================="