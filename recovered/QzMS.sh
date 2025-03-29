#!/bin/bash

set -e
trap 'echo "[!] Install failed. See /root/arch-install-error.log for details."; exit 1' ERR

# Log all output
exec > >(tee -a /root/arch-install.log) 2>&1

# ================================================
# Cleanup Mode for Previous Install Traces
# ================================================
if [[ "$1" == "--cleanup" ]]; then
  echo -e "\n[!] Running cleanup routine..."

  echo "[*] Unmounting /mnt if mounted..."
  umount -R /mnt 2>/dev/null || echo "Nothing to unmount"

  echo "[*] Deactivating swap..."
  swapoff -a || true

  echo "[*] Closing any mapped LUKS devices..."
  cryptsetup close cryptarch 2>/dev/null || echo "No LUKS device open"

  echo "[*] Disabling LVM volume group..."
  vgchange -an vg0 2>/dev/null || echo "No active VG found"

  echo -e "\n[!] WARNING: Do you want to wipe filesystem signatures from $DISK? This will destroy any data!"
  read -rp "Type 'YES' to confirm: " confirm
  if [[ "$confirm" == "YES" ]]; then
    echo "[*] Wiping filesystem signatures from $DISK..."
    wipefs -a "$DISK"
  else
    echo "Skipping disk wipe."
  fi

  echo -e "\n Cleanup complete. You can now re-run the installer."
  exit 0
fi

# ===============================================================
#  Arch Linux Installer — Full-disk LUKS2 + LVM + Btrfs + GRUB
# Secure Boot & UKI Ready • TPM Key Unlock • Snapshot-Ready Setup
# ===============================================================

# === USER CONFIG PROMPTS ===
echo -e "\n Welcome to Arch Installer"
read -rp "  Enter hostname: " HOSTNAME
read -rp " Enter target disk (e.g., /dev/nvme0n1) [/dev/nvme0n1]: " DISK
DISK=${DISK:-/dev/nvme0n1}
read -rp " Enter keyfile path [/root/secrets/crypto_keyfile.bin]: " KEYFILE
KEYFILE=${KEYFILE:-/root/secrets/crypto_keyfile.bin}
read -rp " Enter timezone (e.g. America/Denver) [America/Denver]: " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Denver}
read -rp " Enter keyboard layout [us]: " KEYMAP
KEYMAP=${KEYMAP:-us}

CRYPT_NAME="cryptarch"
VG_NAME="vg0"
EFI_SIZE="1024MiB"
LUKS_TYPE="luks2"

# === Prompt for Disk Encryption Passphrase ===
echo -e "\n Enter LUKS disk encryption passphrase:"
read -rs luks_passphrase
echo

# === Enable NTP ===
timedatectl set-ntp true

# === Partitioning Disk ===
echo -e "\n Partitioning $DISK..."
parted $DISK --script mklabel gpt \
  mkpart ESP fat32 1MiB $EFI_SIZE \
  set 1 esp on \
  mkpart primary $EFI_SIZE 100%
EFI_PART="${DISK}p1"
LUKS_PART="${DISK}p2"

# === Format EFI Partition ===
mkfs.fat -F32 $EFI_PART

# === Encrypt and Open LUKS Partition ===
echo -e "\n Encrypting root partition..."
echo -n "$luks_passphrase" | cryptsetup luksFormat --type $LUKS_TYPE --pbkdf pbkdf2 --force-password $LUKS_PART -d -
echo -n "$luks_passphrase" | cryptsetup open $LUKS_PART $CRYPT_NAME -d -

# === Create LVM Volumes ===
pvcreate /dev/mapper/$CRYPT_NAME
vgcreate $VG_NAME /dev/mapper/$CRYPT_NAME
lvcreate -L 8G $VG_NAME -n swap
lvcreate -L 40G $VG_NAME -n root
lvcreate -L 10G $VG_NAME -n tmp
lvcreate -L 40G $VG_NAME -n var
lvcreate -l 100%FREE $VG_NAME -n home

# === Format Filesystems ===
mkswap "/dev/$VG_NAME/swap"
mkfs.btrfs -f "/dev/$VG_NAME/root"
mkfs.btrfs -f "/dev/$VG_NAME/home"
mkfs.btrfs -f "/dev/$VG_NAME/tmp"
mkfs.btrfs -f "/dev/$VG_NAME/var"

# === Mount Volumes + Create Subvolumes ===
mount "/dev/$VG_NAME/root" /mnt
[[ -d /mnt ]] || { echo " Failed to mount /mnt"; exit 1; }

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
umount /mnt

mount -o compress=zstd,subvol=@ /dev/$VG_NAME/root /mnt
mkdir -p /mnt/{home,var,tmp,efi}
[[ -d /mnt/home ]] || { echo " /mnt/home not created!"; exit 1; }

mount -o compress=zstd,subvol=@home /dev/$VG_NAME/home /mnt/home
mount -o compress=zstd,subvol=@var /dev/$VG_NAME/var /mnt/var
mount -o compress=zstd,subvol=@tmp /dev/$VG_NAME/tmp /mnt/tmp
mount $EFI_PART /mnt/efi
swapon "/dev/$VG_NAME/swap"

# === Base Install ===
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers \
  linux-firmware lvm2 sudo vim btrfs-progs grub efibootmgr networkmanager \
  dhcpcd wpa_supplicant iwd

# === fstab ===
genfstab -U /mnt >> /mnt/etc/fstab

# === Copy User Script (Optional) ===
if [[ -f ./01-user-creation.sh ]]; then
  cp ./01-user-creation.sh /mnt/root/
  chmod +x /mnt/root/01-user-creation.sh
fi

# === Enter Chroot ===
arch-chroot /mnt /bin/bash <<EOF
mkdir -p \$(dirname $KEYFILE)
dd if=/dev/urandom of=$KEYFILE bs=1 count=64
chmod 600 $KEYFILE
cryptsetup luksAddKey $LUKS_PART $KEYFILE

echo "$CRYPT_NAME UUID=\\$(blkid -s UUID -o value $LUKS_PART) $KEYFILE luks" >> /etc/crypttab

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
echo "FILES=($KEYFILE)" >> /etc/mkinitcpio.conf
mkinitcpio -P

sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\\$(blkid -s UUID -o value $LUKS_PART):$CRYPT_NAME root=\/dev\/$VG_NAME\/root cryptkey=rootfs:$KEYFILE\"/" /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
echo "GRUB_DEFAULT=saved" >> /etc/default/grub
echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub

pacman -S --noconfirm amd-ucode
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

LTS_ENTRY=\$(grep -E "menuentry 'Arch Linux, with Linux linux-lts'" /boot/grub/grub.cfg | head -n1 | cut -d"'" -f2)
grub-set-default "Advanced options for Arch Linux>\$LTS_ENTRY"

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

systemctl enable NetworkManager

echo -e "\n Set root password:"
passwd

blkid > /root/arch-install-summary.txt
EOF

# === Cleanup ===
echo -e "\n Unmounting filesystems..."
umount -R /mnt
swapoff "/dev/$VG_NAME/swap"

# === Done ===
echo -e "\n Arch base install complete!"
echo " After reboot, run: /root/01-user-creation.sh"
echo -e "To reboot now:\n  sudo reboot"
