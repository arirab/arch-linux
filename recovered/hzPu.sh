#!/bin/bash

set -e

# ======================================================
# 🧪 Elara Network Check — 04. verify-network.sh
# Verifies DNS, VPN, IP, and DNS leak status
# Now with curl fallback and optional Discord ping
# ======================================================

log() {
  echo -e "\033[1;32m[\u2713] $1\033[0m"
}
warn() {
  echo -e "\033[1;31m[\u2717] $1\033[0m"
}

DISCORD_WEBHOOK="/etc/discord-webhook-url.txt"

# Check systemd-resolved status
log "Checking systemd-resolved..."
systemctl is-active systemd-resolved && log "systemd-resolved is active." || warn "systemd-resolved is not active."

# Show current /etc/resolv.conf
log "Current /etc/resolv.conf contents:"
cat /etc/resolv.conf

# Show resolved DNS servers
log "Active DNS servers according to systemd-resolved:"
resolvectl status | grep 'DNS Servers'

# Check external IP (fallback if api.ipify fails)
log "Checking external IP address..."
CURRENT_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
echo "External IP: $CURRENT_IP"

# Check DNS resolution
log "Checking DNS resolution for archlinux.org..."
nslookup archlinux.org 8.8.8.8 || warn "DNS resolution failed."

# Ping test
log "Pinging google.com..."
ping -c 3 google.com || warn "Ping failed."

# VPN check (Windscribe or wg/tun interface)
if ip link | grep -qE 'tun|wg'; then
  VPN_INTERFACE=$(ip link | grep -E 'tun|wg' | awk -F: '{print $2}' | head -n1 | tr -d ' ')
  log "VPN interface $VPN_INTERFACE is present."
else
  VPN_INTERFACE="None"
  warn "No VPN interface detected (tun0/wg0)."
fi

# Discord Notification (Optional)
if [[ -f "$DISCORD_WEBHOOK" ]]; then
  log "Sending VPN & DNS check summary to Discord..."
  DNS_INFO=$(resolvectl status | grep 'DNS Servers' | awk -F: '{print $2}' | xargs)

  curl -H "Content-Type: application/json" \
       -d "{\"content\": \"\ud83e\uddea **Network Verification**\nIP: $CURRENT_IP\nDNS: $DNS_INFO\nVPN Interface: $VPN_INTERFACE\"}" \
       $(cat "$DISCORD_WEBHOOK") || true
fi

log "\u2705 Network verification complete."
echo "Review above output for any issues."