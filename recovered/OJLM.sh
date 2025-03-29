#!/bin/bash

set -e

# ======================================================
# ⚙️ Elara Arch Core Setup — 3-security-hardening.sh
# Hostname, NTP, security, pacman tuning, base essentials
# AppArmor setup moved to 70-apparmor-core.sh
# ======================================================

log() {
  echo -e "\033[1;34m[+] $1\033[0m"
}

USERNAME="rock"
HOSTNAME="v01dsh3ll"
FQDN="voidshell.arirab.com"

# ---------------------------------------------
# Step 1: Set Hostname & Domain
# ---------------------------------------------
log "Setting hostname to $HOSTNAME and domain to $FQDN..."
echo "$HOSTNAME" | sudo tee /etc/hostname

sudo tee /etc/hosts > /dev/null <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       $FQDN $HOSTNAME
EOF

# ---------------------------------------------
# Step 2: Enable NTP Sync
# ---------------------------------------------
log "Enabling NTP (time synchronization)..."
sudo timedatectl set-ntp true
sudo systemctl enable systemd-timesyncd
sudo systemctl start systemd-timesyncd
log "System time synced: $(timedatectl | grep 'System clock synchronized')"

# ---------------------------------------------
# Step 3: Update System & Install Core Packages
# ---------------------------------------------
log "Updating system packages..."
sudo pacman -Syu --noconfirm

log "Installing core packages and security tools..."
sudo pacman -S --noconfirm --needed \
  base-devel git curl wget \
  ufw fail2ban openssh gnupg haveged \
  htop btop neofetch lsb-release rsync \
  zip unzip p7zip tar \
  net-tools lsof jq bash-completion \
  fzf ripgrep bat tree tldr \
  reflector zsh sudo man-db \
  which pkgfile patch make strace \
  usbutils pciutils dmidecode \
  nfs-utils gvfs gvfs-smb \
  xdg-utils xdg-user-dirs \
  nano vim \
  lynis clamav audit

# ---------------------------------------------
# Step 4: Enable Security Services
# ---------------------------------------------
log "Enabling and configuring UFW firewall (including VMware/NAT/VPN)..."
sudo systemctl enable --now ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from 192.168.0.0/16  # Allow LAN access (e.g., VMware NAT, VPNs)
sudo ufw allow in on lo  # Allow loopback

log "Enabling fail2ban, haveged, sshd..."
sudo systemctl enable --now fail2ban
sudo systemctl enable --now haveged
sudo systemctl enable --now sshd

# ---------------------------------------------
# Step 5: Configure Bonus Security Tools
# ---------------------------------------------
log "Running initial Lynis security audit..."
sudo lynis audit system --quick || true

log "Setting up ClamAV (virus scanner)..."
sudo freshclam || true
sudo systemctl enable --now clamav-freshclam

log "Enabling auditd for system activity logging..."
sudo systemctl enable --now auditd

# ---------------------------------------------
# Step 6: Kernel Sysctl Hardening
# ---------------------------------------------
log "Applying kernel sysctl hardening..."
sudo tee /etc/sysctl.d/99-elara.conf > /dev/null <<EOF
# Disable IPv6 (system-wide)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore broadcast pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Enable execshield and address space layout randomization (ASLR)
kernel.randomize_va_space = 2

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
EOF

sudo sysctl --system

# ---------------------------------------------
# Step 4: Harden Root Access
# ---------------------------------------------
log "Locking root account (disable password login)..."
sudo passwd -l root

# ---------------------------------------------
# Step 5: SSH Hardening
# ---------------------------------------------
log "Applying SSH security settings..."
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

log " User & hostname setup complete. Login as '$USERNAME'."
log " Default password is 'changeme'. Change it immediately!"


# ---------------------------------------------
# Step 8: Pacman.conf Tweaks
# ---------------------------------------------
log "Optimizing /etc/pacman.conf..."
sudo sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf

if ! grep -q "^ParallelDownloads" /etc/pacman.conf; then
  echo "ParallelDownloads = 10" | sudo tee -a /etc/pacman.conf
else
  sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
fi

sudo sed -i '/^\[options\]/a IgnorePkg = linux linux-headers linux-lts linux-lts-headers linux-firmware nvidia* cuda' /etc/pacman.conf

# ---------------------------------------------
# Step 9: Reflector Mirror Optimization
# ---------------------------------------------
COUNTRY="India"  # <- Change this to your actual country for best results
log "Refreshing mirrorlist with top 10 HTTPS mirrors in $COUNTRY..."
sudo reflector --country "$COUNTRY" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

log "✅ Core system setup complete. Continue to networking and AppArmor setup."