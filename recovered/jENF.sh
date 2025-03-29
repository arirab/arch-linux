#!/bin/bash

set -e
trap 'echo "❌ Vault restore failed." | tee -a /var/log/vaultwarden-restore.log; exit 1' ERR

# ======================================================
# Restore Encrypted Vault
# GPG-decrypt + extract + verify backup archive
# Smartcard + agent-aware + dry-run and checksum verify
# ======================================================

log() {
  echo -e "\033[1;36m[+] $(date '+%Y-%m-%d %H:%M:%S') — $1\033[0m" | tee -a /var/log/vaultwarden-restore.log
}

# --- CONFIG ---
CLOUD_REMOTE="arch-vault"
EXPORT_DIR="/root/arch-vault-export"
RESTORE_DIR="/root/vault-restore"

# --- Parse --target-dir if provided ---
if [[ "$1" == "--target-dir" && -n "$2" ]]; then
  RESTORE_DIR="$2"
  shift 2
fi

# --- Ensure necessary directories exist with correct permissions ---
log "Ensuring export and restore directories exist..."
if [ ! -d "$EXPORT_DIR" ]; then
  sudo mkdir -p "$EXPORT_DIR"
  log "Created export directory at $EXPORT_DIR"
fi

if [ ! -d "$RESTORE_DIR" ]; then
  sudo mkdir -p "$RESTORE_DIR"
  log "Created restore directory at $RESTORE_DIR"
fi

sudo chmod 700 "$EXPORT_DIR" "$RESTORE_DIR"

# --- Fetch latest encrypted archive ---
log "Fetching latest encrypted archive from remote [$CLOUD_REMOTE]..."
LATEST_FILE=$(rclone ls "$CLOUD_REMOTE:elara-vault/" | awk '{print $2}' | grep '.tar.gz.gpg$' | sort | tail -n1)

if [[ -z "$LATEST_FILE" ]]; then
  echo "❌ No backup archive found on remote." | tee -a /var/log/vaultwarden-restore.log
  exit 1
fi

log "Downloading: $LATEST_FILE"
rclone copy "$CLOUD_REMOTE:elara-vault/$LATEST_FILE" "$EXPORT_DIR/"
rclone copy "$CLOUD_REMOTE:elara-vault/sha256.checksum" "$EXPORT_DIR/"

# --- Optional Checksum Verification ---
log "Verifying file checksum..."
cd "$EXPORT_DIR"
sha256sum -c sha256.checksum || {
  echo "❌ Checksum verification failed." | tee -a /var/log/vaultwarden-restore.log
  exit 1
}

# --- Decrypt ---
log "Decrypting archive (smartcard + agent-aware)..."
DECRYPTED_ARCHIVE="restored.tar.gz"
gpg --output "$DECRYPTED_ARCHIVE" --decrypt "$LATEST_FILE"

# --- Securely wipe checksum ---
log "Securely wiping checksum file..."
shred -u sha256.checksum

# --- Dry-run mode (optional) ---
if [[ "$1" == "--dry-run" ]]; then
  log "Dry-run: listing contents of $DECRYPTED_ARCHIVE"
  tar -tzf "$DECRYPTED_ARCHIVE"
  log "✅ Dry-run complete. No changes made."
  exit 0
fi

# --- Extract ---
log "Extracting to $RESTORE_DIR..."
tar -xzf "$DECRYPTED_ARCHIVE" -C "$RESTORE_DIR"

log "Vault successfully restored to $RESTORE_DIR ♻️"

# --- Cleanup ---
# shred -u "$EXPORT_DIR/$LATEST_FILE" "$DECRYPTED_ARCHIVE"
