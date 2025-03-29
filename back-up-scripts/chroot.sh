arch-chroot /mnt /bin/bash <<EOF
set -e

# --- Register Crypto keyfile ---
mkdir -p \$(dirname "$KEYFILE")
dd if=/dev/urandom of="$KEYFILE" bs=1 count=64 status=none
chmod 600 "$KEYFILE"
echo -n "$luks_passphrase" | cryptsetup luksAddKey "$LUKS_PART" --key-file=- "$KEYFILE" || echo "[!] Failed to add keyfile."

echo "$CRYPT_NAME UUID=\$(blkid -s UUID -o value $LUKS_PART) $KEYFILE luks" >> /etc/crypttab

# --- Initramfs and GRUB ---
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
echo "FILES=($KEYFILE)" >> /etc/mkinitcpio.conf
mkinitcpio -P

sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\\\"cryptdevice=UUID=\\\$(blkid -s UUID -o value $LUKS_PART):$CRYPT_NAME root=/dev/$VG_NAME/root cryptkey=rootfs:$KEYFILE\\\"|" /etc/default/grub

echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
echo "GRUB_DEFAULT=saved" >> /etc/default/grub
echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB 
grub-mkconfig -o /boot/grub/grub.cfg

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