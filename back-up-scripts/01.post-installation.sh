# ================================
# Disable Sleep, Suspend, Hibernate
# ================================
log "Disabling suspend, hibernate, hybrid-sleep..."

sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo mkdir -p /etc/systemd/logind.conf.d
cat <<EOF | sudo tee /etc/systemd/logind.conf.d/ignore-sleep.conf
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleHibernateKey=ignore
EOF

sudo loginctl flush-devices || true

# ================================
# Configuring Snapper
# ================================

#!/bin/bash
set -e

echo "Configuring snapper for the root filesystem..."

# Set permissions on the snapshots directory
chmod 750 /.snapshots
chown :wheel /.snapshots

# Create snapper configuration for the root subvolume
snapper -c root create-config / || true

if [[ -f /etc/snapper/configs/root ]]; then
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
fi

systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

echo "Snapper configuration completed successfully."


# ---------------------------------------
# Browsers, Dev Tools, Cloud Apps
# ---------------------------------------
log "Installing essential applications..."
yay -S --noconfirm --needed \
  firefox brave-bin google-chrome microsoft-edge-stable-bin \
  discord zoom teams-for-linux \
  code sublime-text-4 \
  docker docker-compose \
  vmware-workstation \
  gh kubectl helm minikube terraform ansible aws-cli

sudo systemctl enable --now docker
sudo usermod -aG docker "$TARGET_USER"

# ---------------------------------------
# Autostart Core GUI Apps
# ---------------------------------------
log "Creating autostart entries..."
for app in spotify telegram-desktop discord; do
  cat > "$USER_HOME/.config/autostart/$app.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$app
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=$(echo $app | sed 's/-desktop//' | awk '{print toupper(substr(\$0,1,1)) substr(\$0,2)}')
EOF
done
