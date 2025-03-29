#!/bin/bash

set -e

# ======================================================
# 🌐 Elara Network & VPN Setup — 03-networking.sh
# Hardens DNS config, disables ISP override, sets up Windscribe VPN
# Supports VPN kill switch, Discord alerting, WireGuard config
# ======================================================

log() {
  echo -e "\033[1;36m[+] $1\033[0m"
}

IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
IFACE=${IFACE:-$(ip route get 8.8.8.8 | awk '{print $5; exit}')}
DNS_SERVERS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"
DISCORD_WEBHOOK="/etc/discord-webhook-url.txt"

# ---------------------------------------------
# Step 1: Configure dhcpcd to ignore resolv.conf
# ---------------------------------------------
log "Configuring dhcpcd to stop overwriting DNS settings..."
sudo sed -i "/^interface $IFACE/d" /etc/dhcpcd.conf || true
sudo sed -i "/^static domain_name_servers/d" /etc/dhcpcd.conf || true
sudo sed -i "/^nohook resolv.conf/d" /etc/dhcpcd.conf || true

echo "interface $IFACE
nohook resolv.conf
noipv6
static domain_name_servers=$DNS_SERVERS" | sudo tee -a /etc/dhcpcd.conf

sudo systemctl restart dhcpcd

# ---------------------------------------------
# Step 2: Configure systemd-resolved for DNS
# ---------------------------------------------
log "Configuring systemd-resolved with Google + Cloudflare DNS..."
sudo sed -i '/^DNS=/d' /etc/systemd/resolved.conf
sudo sed -i '/^FallbackDNS=/d' /etc/systemd/resolved.conf

sudo tee /etc/systemd/resolved.conf > /dev/null <<EOF
[Resolve]
DNS=$DNS_SERVERS
FallbackDNS=
EOF

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl enable --now systemd-resolved
sudo systemctl restart systemd-resolved

# ---------------------------------------------
# Step 3: Install Windscribe + Protocol Support
# ---------------------------------------------
log "Installing Windscribe VPN and dependencies..."
sudo pacman -S --noconfirm --needed \
  wireguard-tools stunnel openvpn

if [[ ! -f ~/Downloads/windscribe_*.zst ]]; then
  log "Please download Windscribe package from https://windscribe.com/install/desktop/linux_zst_x64"
  exit 1
fi

sudo pacman -U --noconfirm ~/Downloads/windscribe_*.zst
sudo systemctl enable --now windscribe

log "Please run: windscribe login (manual step required)"
echo "⚠️ After login, run: windscribe connect best && windscribe connect --startup"
echo "Then re-run this script to apply kill switch, alerts, and verify."
exit 1

# ---------------------------------------------
# Step 4: Enable Auto-Connect on Boot (after login)
# ---------------------------------------------
windscribe connect --startup
log "Windscribe set to auto-connect at boot."

# ---------------------------------------------
# Step 5: VPN Kill Switch Detection & UFW Rules
# ---------------------------------------------
VPN_INTERFACE=$(ip link | grep -E 'tun|wg' | awk -F: '{print $2}' | head -n1 | tr -d ' ')
if [[ -n "$VPN_INTERFACE" ]]; then
  log "Detected VPN interface: $VPN_INTERFACE — Applying UFW rules..."
  sudo ufw default deny outgoing
  sudo ufw allow out on "$VPN_INTERFACE" from any to any
  sudo ufw allow out on lo
  sudo ufw enable
else
  log "⚠️ VPN interface not detected. Skipping kill switch rules."
fi

# ---------------------------------------------
# Step 6: Discord Notification for VPN & DNS Info
# ---------------------------------------------
if [[ -f "$DISCORD_WEBHOOK" ]]; then
  log "Sending Discord alert for VPN & DNS status..."
  CURRENT_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
  DNS_INFO=$(resolvectl status | grep 'DNS Servers' | awk -F: '{print $2}' | xargs)

  curl -H "Content-Type: application/json" \
       -d "{\"content\": \"🔐 **VPN Connected**\nIP: $CURRENT_IP\nDNS: $DNS_INFO\nInterface: $VPN_INTERFACE\"}" \
       $(cat "$DISCORD_WEBHOOK") || true
fi

# ---------------------------------------------
# Step 7: (Optional) WireGuard Config Template
# ---------------------------------------------
WG_CONF="/etc/wireguard/wg0.conf"
if [[ ! -f "$WG_CONF" ]]; then
  log "Creating WireGuard config template..."
  sudo tee "$WG_CONF" > /dev/null <<EOF
[Interface]
PrivateKey = <YOUR_PRIVATE_KEY>
Address = 10.0.0.2/24
DNS = $DNS_SERVERS

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <VPN_SERVER_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  sudo chmod 600 "$WG_CONF"
  log "Edit the file at $WG_CONF to finalize your setup."
fi

log "✅ Networking and VPN setup complete with kill switch + alerts ready."
log "🧪 You may now run 04-verify-network.sh to test DNS and VPN integrity."