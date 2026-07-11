#!/usr/bin/env bash
# Tars up all persistent config/data for the stack. Meant to be run from cron.
# Usage: ./scripts/backup.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BACKUP_DIR="backups"
KEEP=7
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="${BACKUP_DIR}/home-tools-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

tar -czf "$ARCHIVE" \
  --exclude='mosquitto/log' \
  config/homeassistant \
  mosquitto/config mosquitto/data \
  pihole \
  uptime-kuma \
  portainer \
  .env

echo "Wrote $ARCHIVE"

# Keep only the most recent $KEEP backups
ls -1t "${BACKUP_DIR}"/home-tools-*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm --
