#!/bin/bash

set -e
trap 'echo "❌ Vault sync failed."; exit 1' ERR

# ======================================================
# Secure Secrets + Keyfile Backup
# GPG-encrypted upload to rclone remote, secure wipe, cron-friendly
# Includes optional keygen + remote setup if missing
# Logs with timestamps + Smartcard + Multi-recipient + CI test stub
# ======================================================

log() {
  echo -e "\033[1;36m[+] $(date '+%Y-%m-%d %H:%M:%S') — $1\033[0m" | tee -a /var/log/vaultwarden-sync.log
}

# --- CONFIG ---
VAULT_DIR="/root/Arch-Vault"
EXPORT_DIR="/root/arch-vault-export"
GPG_RECIPIENTS=("rock@elara.local" "admin@elara.local")
CLOUD_REMOTE="arch-vault"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="vault-$DATE_TAG.tar.gz"
ENCRYPTED_ARCHIVE="$ARCHIVE_NAME.gpg"
LOG_FILE="/var/log/vaultwarden-sync.log"

# --- Pre-checks ---
REQUIRED_PKGS=(gnupg rclone coreutils)
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    log "Installing missing package: $pkg"
    sudo pacman -S --noconfirm --needed "$pkg"
  fi
  command -v "$pkg" &>/dev/null || { echo "❌ Missing tool: $pkg" | tee -a "$LOG_FILE"; exit 1; }
done

# --- Ensure export directory exists ---
log "Ensuring export directory exists..."
if [ ! -d "$EXPORT_DIR" ]; then
  sudo mkdir -p "$EXPORT_DIR"
  sudo chmod 700 "$EXPORT_DIR"
  log "Created export directory at $EXPORT_DIR"
else
  log "Export directory already exists."
fi

# --- First-time GPG keygen for all recipients ---
for RECIPIENT in "${GPG_RECIPIENTS[@]}"; do
  if ! gpg --list-keys "$RECIPIENT" &>/dev/null; then
    log "No GPG key found for $RECIPIENT. Generating now..."
    cat > gpg-batch <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Elara Vault
Name-Email: $RECIPIENT
Expire-Date: 0
%no-protection
%commit
EOF
    gpg --batch --gen-key gpg-batch
    rm gpg-batch
  fi
  log "GPG key for $RECIPIENT verified."
done

# --- First-time rclone remote setup ---
if ! rclone listremotes | grep -q "^$CLOUD_REMOTE:"; then
  log "rclone remote [$CLOUD_REMOTE] not found. Starting setup..."
  rclone config
fi

# --- Create Archive ---
log "Creating compressed archive from $VAULT_DIR..."
tar -czf "$EXPORT_DIR/$ARCHIVE_NAME" -C "$VAULT_DIR" .

# --- Encrypt Archive (Multi-recipient + Smartcard support) ---
log "Encrypting archive with GPG..."
GPG_ARGS=(--yes --output "$EXPORT_DIR/$ENCRYPTED_ARCHIVE" --encrypt)
for RECIPIENT in "${GPG_RECIPIENTS[@]}"; do
  GPG_ARGS+=(--recipient "$RECIPIENT")
done

gpg "${GPG_ARGS[@]}" "$EXPORT_DIR/$ARCHIVE_NAME"

# --- Generate SHA256 Checksum ---
log "Generating SHA256 checksum..."
cd "$EXPORT_DIR"
sha256sum "$ENCRYPTED_ARCHIVE" > sha256.checksum

# --- Secure Wipe Original Tar ---
log "Secure wiping original archive..."
shred -u "$EXPORT_DIR/$ARCHIVE_NAME"

# --- Upload to rclone ---
log "Uploading to rclone remote [$CLOUD_REMOTE]..."
rclone copy "$EXPORT_DIR/$ENCRYPTED_ARCHIVE" "$CLOUD_REMOTE:elara-vault/" --progress
rclone copy "$EXPORT_DIR/sha256.checksum" "$CLOUD_REMOTE:elara-vault/"

# --- Optional: Add to cron ---
log "To automate, add this line to crontab:"
echo "0 3 * * * /root/vaultwarden-sync.sh >> $LOG_FILE 2>&1"

# --- GPG Decryption Info ---
log "To decrypt and restore (smartcard + agent aware):"
echo "gpg --output restored.tar.gz --decrypt $ENCRYPTED_ARCHIVE"
echo "tar -xzf restored.tar.gz -C /restore/location"
echo "(Optional) Use --use-agent or Smartcard for decryption."

# --- CI Sync Test (if running in CI) ---
if [[ "$CI" == "true" ]]; then
  log "CI mode detected. Verifying uploaded file exists on remote..."
  rclone ls "$CLOUD_REMOTE:elara-vault/" | grep "$ENCRYPTED_ARCHIVE" && log "✅ CI upload check passed." || { echo "❌ CI check failed." | tee -a "$LOG_FILE"; exit 1; }
fi

# --- Save Last Backup Timestamp ---
echo "$DATE_TAG" > "$EXPORT_DIR/last_backup.txt"

log "Vault sync complete. Encrypted archive safely uploaded and local copy wiped. Checksum stored 🔐"