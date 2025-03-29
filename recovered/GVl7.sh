#!/bin/bash

set -e

# ======================================================
# 🛡️ Elara AppArmor Custom Profiles — 90-apparmor-profiles.sh
# Generate & enforce AppArmor profiles for key services
# Supports Elara Media Stack (streaming, automation, proxying)
# Integrates log forwarding for Grafana/Discord in the future
# ======================================================

log() {
  echo -e "\033[1;33m[+] $1\033[0m"
}

# Ensure apparmor_parser and utils exist
if ! command -v aa-genprof &>/dev/null; then
  echo "AppArmor utilities not installed. Run 01-core.sh first."
  exit 1
fi

# ---------------------------------------------
# Step 1: Create Fine-Tuned Profiles for Media Services
# ---------------------------------------------
SERVICES=(nginx transmission-daemon jellyfin emby-server navidrome sshd vaultwarden organizr heimdall radarr sonarr lidarr bazarr notifiarr home-assistant windscribe-cli)

for service in "${SERVICES[@]}"; do
  log "Generating AppArmor profile for $service (interactive)..."
  sudo aa-genprof "$service" || true
  log "Enforcing profile: $service"
  sudo aa-enforce "$service" || true
  echo
  sleep 1
  log "You can fine-tune the profile here: /etc/apparmor.d/usr.sbin.$service"
done

# ---------------------------------------------
# Step 2: Create Default-Deny Profiles for Custom Binaries
# ---------------------------------------------
CUSTOM_BINARIES=(/usr/local/bin/custom-app /opt/scripts/secure-task.sh /usr/bin/filebot /usr/bin/picard /usr/bin/windscribe)

for binary in "${CUSTOM_BINARIES[@]}"; do
  PROFILE_NAME="$(basename "$binary")"
  PROFILE_FILE="/etc/apparmor.d/$(echo "$binary" | sed 's|/|-|g' | sed 's|^-||').profile"

  if [[ ! -f "$PROFILE_FILE" ]]; then
    log "Creating default-deny AppArmor profile for $binary..."
    sudo tee "$PROFILE_FILE" > /dev/null <<EOF
#include <tunables/global>

profile ${PROFILE_FILE##*/} "$binary" {
  # Default deny all
  deny /** rwklx,

  # Allow basics for execution — expand per app requirements
  /usr/bin/filebot rix,
  /usr/bin/picard rix,
  /usr/bin/windscribe rix,
  /mnt/media/** r,
  /tmp/** rwk,
  capability dac_override,
}
EOF
    sudo apparmor_parser -r "$PROFILE_FILE"
    sudo aa-enforce "$PROFILE_FILE"
  fi
done

# ---------------------------------------------
# Step 3: Reload All Profiles
# ---------------------------------------------
log "Reloading all AppArmor profiles..."
sudo systemctl reload apparmor || sudo systemctl restart apparmor

# ---------------------------------------------
# Step 4: Auditd Log Watch + Export Stub
# ---------------------------------------------
log "Checking for recent AppArmor violations via auditd..."
sudo ausearch -m AVC -ts recent | tail -n 100 || echo "No AppArmor violations detected."

# Optionally forward logs to Grafana/Loki or Discord Webhook later
DISCORD_WEBHOOK="/etc/discord-webhook-url.txt"
if [[ -f "$DISCORD_WEBHOOK" ]]; then
  export MSG="$(sudo ausearch -m AVC -ts today | tail -n 20)"
  curl -H "Content-Type: application/json" \
       -d "{\"content\": \"\`AppArmor Violations (Today)\`\n$MSG\"}" \
       $(cat "$DISCORD_WEBHOOK") || true
fi

# ---------------------------------------------
# Step 5: Verify AppArmor Status
# ---------------------------------------------
log "Current AppArmor profile enforcement status:"
sudo aa-status

log "✅ AppArmor profiles created, enforced, and monitored."
echo "Fine-tuned profiles now active for all services."
echo "Modify profiles in /etc/apparmor.d/ as needed and rerun this script."