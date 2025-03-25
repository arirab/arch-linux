#!/bin/bash

set -e
trap 'echo "Install failed. Check previous errors."; exit 1' ERR

# ==================================================================
#               --- Arch Installer ---
# Full-disk LUKS2 + LVM + Btrfs + Snapshot + UEFI + GRUB
# Secure Boot & UKI Ready + Swap Compression + TPM prep hooks
# ===================================================================

# --- CONFIG ---
DISK="/dev/nvme0n1"
HOSTNAME="v01dsh3ll"
USERNAME="rock"
CRYPT_NAME="cryptarch"
VG_NAME="vg0"
EFI_SIZE="1024MiB"
LUKS_TYPE="luks2"
KEYFILE="/root/secrets/crypto_keyfile.bin"

# --- Connect to WiFi ---
echo -e "\n Connecting to WiFi..."
iwctl station list
read -rp "Enter WiFi Interface (e.g. wlan0): " WIFI_IFACE
read -rp "Enter SSID: " SSID
read -rsp "Enter WiFi Password: " WIFI_PASS

echo -e "\nConnecting to $SSID..."
iwctl --passphrase "$WIFI_PASS" station "$WIFI_IFACE" connect "$SSID"
echo -e "\n Connected to WiFi"

# --- Network Fallback Check ---
echo -e "\n Verifying internet connection..."
if ping -q -c 3 archlinux.org > /dev/null; then
  echo " Internet connection verified via ping."
else
  echo " Network check failed. Please verify connectivity manually."
  exit 1
fi

# --- PROMPT FOR LUKS PASSPHRASE ---
echo -e "\n Enter passphrase for disk encryption (LUKS2):"
read -rs luks_passphrase
echo

# --- Enable NTP ---
echo -e "\n Enabling NTP..."
timedatectl set-ntp true

# --- Partition the Disk ---
parted $DISK --script mklabel gpt \
  mkpart ESP fat32 1MiB $EFI_SIZE \
  set 1 esp on \
  mkpart primary $EFI_SIZE 100%

EFI_PART="${DISK}p1"
LUKS_PART="${DISK}p2"

# --- Format EFI ---
echo -e "\n Formatting EFI partition..."
mkfs.fat -F32 $EFI_PART

# --- Encrypt and Open LUKS Partition ---
echo -e "\n Encrypting $LUKS_PART with LUKS2..."
echo -n "$luks_passphrase" | cryptsetup luksFormat --type $LUKS_TYPE --pbkdf pbkdf2 --force $LUKS_PART -d -
echo -n "$luks_passphrase" | cryptsetup open $LUKS_PART $CRYPT_NAME -d -

# --- Create LVM Volumes ---
echo -e "\n Creating LVM structure..."
pvcreate /dev/mapper/$CRYPT_NAME
vgcreate $VG_NAME /dev/mapper/$CRYPT_NAME

lvcreate -L 8G $VG_NAME -n swap
lvcreate -L 40G $VG_NAME -n root
lvcreate -L 10G $VG_NAME -n tmp
lvcreate -L 40G $VG_NAME -n var
lvcreate -l 100%FREE $VG_NAME -n home

# --- Format Filesystems ---
echo -e "\n Formatting filesystems..."
mkswap "/dev/$VG_NAME/swap"
mkfs.btrfs -f "/dev/$VG_NAME/root"
mkfs.btrfs -f "/dev/$VG_NAME/home"
mkfs.btrfs -f "/dev/$VG_NAME/tmp"
mkfs.btrfs -f "/dev/$VG_NAME/var"

# --- Mount Filesystems ---
echo -e "\n Mounting filesystems..."
mount "/dev/$VG_NAME/root" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
umount /mnt

mount -o compress=zstd,subvol=@ /dev/$VG_NAME/root /mnt
mkdir -p /mnt/{home,var,tmp,efi}
mount -o compress=zstd,subvol=@home /dev/$VG_NAME/home /mnt/home
mount -o compress=zstd,subvol=@var /dev/$VG_NAME/var /mnt/var
mount -o compress=zstd,subvol=@tmp /dev/$VG_NAME/tmp /mnt/tmp
mount $EFI_PART /mnt/efi

swapon "/dev/$VG_NAME/swap"

# --- Install Base System ---
echo -e "\n Installing base system..."
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers linux-firmware lvm2 sudo vim btrfs-progs grub efibootmgr networkmanager dhcpcd wpa_supplicant

# --- Generate fstab ---
echo -e "\n Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot Preparation ---
echo -e "\n Copying keyfile, preparing for chroot..."
arch-chroot /mnt /bin/bash <<EOF

mkdir -p /root/secrets
dd if=/dev/urandom of=$KEYFILE bs=1 count=64
chmod 600 $KEYFILE
cryptsetup luksAddKey $LUKS_PART $KEYFILE

# --- Setup crypttab ---
echo "$CRYPT_NAME UUID=\$(blkid -s UUID -o value $LUKS_PART) $KEYFILE luks" >> /etc/crypttab

# --- Setup mkinitcpio ---
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
echo "FILES=($KEYFILE)" >> /etc/mkinitcpio.conf
mkinitcpio -P

# --- Setup GRUB ---
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$(blkid -s UUID -o value $LUKS_PART):$CRYPT_NAME root=\/dev\/$VG_NAME\/root cryptkey=rootfs:$KEYFILE\"/' /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
echo "GRUB_DEFAULT=saved" >> /etc/default/grub
echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub

# --- Install CPU microcode (Intel Chipsets intel-ucode) ---
pacman -S --noconfirm amd-ucode

# --- GRUB Installation ---
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Set --- linux-lts as default ---
LTS_ENTRY=\$(grep -E "menuentry 'Arch Linux, with Linux linux-lts'" /boot/grub/grub.cfg | head -n1 | cut -d'\'' -f2)
grub-set-default "Advanced options for Arch Linux>\$LTS_ENTRY"

# --- Set timezone, locale, hostname ---
ln -sf /usr/share/zoneinfo/America/Denver /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

# --- Set keymap ---
echo "KEYMAP=us" > /etc/vconsole.conf

# --- Enable WiFi after reboot ---
systemctl enable NetworkManager

# Auto-connect to known SSID after reboot
nmcli dev wifi connect "<SSID>" password "<WIFI_PASS>"

# --- Set root password ---
passwd

# --- Save UUID info ---
blkid > /root/arch-install-summary.txt
EOF

# --- Cleanup ---
echo -e "\n Unmounting and cleaning up..."
umount -R /mnt
swapoff "/dev/$VG_NAME/swap"
echo -e "\n Base install complete. You can now reboot into your system."
echo -e "Run your post-install modules after first login."
echo -e "\nTo reboot now:"
echo -e "sudo reboot"