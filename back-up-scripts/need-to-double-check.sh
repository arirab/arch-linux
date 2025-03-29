# --- Backup Script with Mako Notification ---
log "Creating backup script with mako notifications..."
mkdir -p "$USER_HOME/.local/bin"

cat > "$USER_HOME/.local/bin/backup-system.sh" <<'EOF'
#!/bin/bash
notify-send "Backup Started" "Running system backup..."

# Your backup logic goes here:
# Example: btrfs subvolume snapshot, restic, rsync, etc.
sleep 2  # Simulated backup task

notify-send "Backup Complete" "Your system has been backed up successfully!"
EOF

chmod +x "$USER_HOME/.local/bin/backup-system.sh"



# ====================================================
# --- Section 8: Dotfiles Backup + Final Polishing ---
# ====================================================

# --- chezmoi Dotfile Sync (Post-install Trigger) ---
log "Setting up chezmoi for dotfile management..."

read -rp "Enter your private dotfiles Git repo (HTTPS or SSH): " DOTFILES_REPO
[[ -z "$DOTFILES_REPO" ]] && { echo "[!] Dotfiles repo cannot be empty. Aborting."; exit 1; }

# Run as the target user
sudo -u "$TARGET_USER" chezmoi init --apply "$DOTFILES_REPO"