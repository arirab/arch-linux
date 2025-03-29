#!/bin/bash

set -e

# ======================================================
# 🔐 Elara AppArmor Core Setup — 70-apparmor-core.sh
# Installs AppArmor + auditing support, enables services
# Includes Loki/Grafana/Discord hook segment for later integration
# ======================================================

log() {
  echo -e "\033[1;34m[+] $1\033[0m"
}

# ---------------------------------------------
# Step 1: Install AppArmor and Tools
# ---------------------------------------------
log "Installing AppArmor, utilities, and auditd..."
sudo pacman -S --noconfirm --needed \
  apparmor apparmor-utils audit

# ---------------------------------------------
# Step 2: Enable AppArmor and Auditd
# ---------------------------------------------
log "Enabling AppArmor and auditd systemd services..."
sudo systemctl enable --now apparmor
sudo systemctl enable --now auditd

# ---------------------------------------------
# Step 3: Test AppArmor Functionality
# ---------------------------------------------
log "Verifying AppArmor status..."
sudo aa-status || echo "⚠️ AppArmor not fully loaded — check dmesg or reboot."

# ---------------------------------------------
# Step 4: (Optional) Send Discord Summary for Loki Dashboard Integration
# ---------------------------------------------
DISCORD_WEBHOOK="/etc/discord-webhook-url.txt"
if [[ -f "$DISCORD_WEBHOOK" ]]; then
  log "Sending AppArmor status to Discord (for Loki Grafana dashboard)..."
  VIOLATIONS=$(sudo ausearch -m AVC -ts recent | tail -n 5 | sed 's/"/\\"/g')

  curl -H "Content-Type: application/json" \
       -d "{\"content\": \"🔐 **AppArmor Status Report**\nRecent Violations:\n$VIOLATIONS\"}" \
       $(cat "$DISCORD_WEBHOOK") || true
fi

log "✅ AppArmor base setup complete. Run 90-apparmor-profiles.sh to apply custom profiles."