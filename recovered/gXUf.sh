#!/bin/bash

set -e
trap 'echo -e "\033[1;31m[!] Elara Vault TUI exited with error.\033[0m"' ERR

# ===================================================================
# TUI Wrapper for Vaultwarden Sync/Restore
# Includes GPG keygen, rclone setup, dry-run toggle, last backup info
# ===================================================================

LOG_FILE="/var/log/vaultwarden-tui.log"
VAULT_SYNC_SCRIPT="/root/vaultwarden-sync.sh"
VAULT_RESTORE_SCRIPT="/root/vaultwarden-restore.sh"
EXPORT_DIR="/root/arch-vault-export"
LAST_BACKUP_FILE="$EXPORT_DIR/last_backup.txt"
DRY_RUN=false

# ---- Pretty Logging ----
log() {
  echo -e "\033[1;36m[+] $(date '+%Y-%m-%d %H:%M:%S') — $1\033[0m" | tee -a "$LOG_FILE"
}
warn() {
  echo -e "\033[1;33m[!] $1\033[0m" | tee -a "$LOG_FILE"
}

# ---- Ensure Required Tools ----
REQUIRED_PKGS=(dialog gnupg rclone coreutils)
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    log "Installing missing package: $pkg"
    sudo pacman -S --noconfirm --needed "$pkg"
  fi
  command -v "$pkg" &>/dev/null || { warn "❌ Missing tool: $pkg"; exit 1; }
done

# ---- Auto GPG Keygen ----
GPG_RECIPIENT="rock@elara.local"
if ! gpg --list-keys "$GPG_RECIPIENT" &>/dev/null; then
  log "GPG key for $GPG_RECIPIENT not found. Generating..."
  cat > gpg-batch <<EOF
  Key-Type: RSA
  Key-Length: 4096
  Subkey-Type: RSA
  Subkey-Length: 4096
  Name-Real: Elara Vault
  Name-Email: $GPG_RECIPIENT
  Expire-Date: 0
  %no-protection
  %commit
EOF
  gpg --batch --gen-key gpg-batch && rm gpg-batch
fi

# ---- Auto Rclone Setup ----
RCLONE_REMOTE="arch-vault"
if ! rclone listremotes | grep -q "^$RCLONE_REMOTE:"; then
  log "Setting up rclone remote '$RCLONE_REMOTE'..."
  rclone config
fi

# ---- Menu Loop ----
while true; do
  LAST_BACKUP="(no backups yet)"
  [[ -f "$LAST_BACKUP_FILE" ]] && LAST_BACKUP="$(cat $LAST_BACKUP_FILE)"

  CHOICE=$(dialog --clear \
    --backtitle "Elara Vault Manager" \
    --title "Vault Options" \
    --menu "Last Backup: $LAST_BACKUP\nDry Run Mode: $DRY_RUN\n\nChoose an action:" 18 60 7 \
    1 "🔐 Backup Vault (Encrypted Upload)" \
    2 "📦 Restore Vault (Decrypt + Extract)" \
    3 "🛠 Edit vaultwarden-sync.sh" \
    4 "🛠 Edit vaultwarden-restore.sh" \
    5 "🔄 Toggle Dry-Run Mode" \
    6 "🚪 Exit" \
    3>&1 1>&2 2>&3)

  clear
  case "$CHOICE" in
    1)
      log "Starting encrypted vault backup..."
      bash "$VAULT_SYNC_SCRIPT"
      ;;
    2)
      log "Starting vault restore (dry-run=$DRY_RUN)..."
      if [[ "$DRY_RUN" == "true" ]]; then
        bash "$VAULT_RESTORE_SCRIPT" --dry-run
      else
        bash "$VAULT_RESTORE_SCRIPT"
      fi
      ;;
    3)
      nano "$VAULT_SYNC_SCRIPT"
      ;;
    4)
      nano "$VAULT_RESTORE_SCRIPT"
      ;;
    5)
      DRY_RUN=$([[ "$DRY_RUN" == "false" ]] && echo "true" || echo "false")
      log "Dry-run mode toggled to $DRY_RUN"
      ;;
    6)
      log "Goodbye. Vault TUI closed."
      break
      ;;
    *)
      warn "Invalid option."
      ;;
  esac

done