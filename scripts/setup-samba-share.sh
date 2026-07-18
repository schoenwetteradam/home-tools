#!/usr/bin/env bash
# Turns space on the external SSD into a network file share (a mini NAS) that Windows,
# phones, and anything else on the LAN can browse and drop files onto -- photos,
# installers, whatever you don't want to keep hunting for random cloud storage for.
#
# Safe to re-run.
# Usage: ./scripts/setup-samba-share.sh [linux-username]   (defaults to the current user)
set -euo pipefail

log() { printf '\n==> %s\n' "$1"; }

USERNAME="${1:-$USER}"
SHARE_DIR="/mnt/ssd/shared"

if ! command -v smbd >/dev/null 2>&1; then
  log "Installing Samba"
  sudo apt-get update -qq
  sudo apt-get install -y samba samba-common-bin
else
  log "Samba already installed, skipping"
fi

log "Creating $SHARE_DIR (photos/, files/, apps/)"
sudo mkdir -p "$SHARE_DIR"/{photos,files,apps}
sudo chown -R "$USERNAME":"$USERNAME" "$SHARE_DIR"

SMB_CONF=/etc/samba/smb.conf
if ! grep -q '^\[shared\]' "$SMB_CONF" 2>/dev/null; then
  log "Adding a [shared] section to $SMB_CONF"
  sudo cp "$SMB_CONF" "${SMB_CONF}.bak"
  cat <<EOF | sudo tee -a "$SMB_CONF" >/dev/null

[shared]
   path = $SHARE_DIR
   browseable = yes
   writable = yes
   guest ok = no
   valid users = $USERNAME
   force user = $USERNAME
   create mask = 0664
   directory mask = 0775
EOF
else
  log "[shared] section already present in $SMB_CONF, leaving it alone"
fi

if sudo pdbedit -L -u "$USERNAME" >/dev/null 2>&1; then
  log "$USERNAME already has a Samba password set, skipping"
else
  log "Setting a Samba password for $USERNAME (separate from your Pi login password)"
  sudo smbpasswd -a "$USERNAME"
fi

log "Restarting Samba"
sudo systemctl enable --now smbd nmbd
sudo systemctl restart smbd nmbd

pi_ip=$(hostname -I | awk '{print $1}')
cat <<EOF

Share is up. Connect to it from:

  Windows   File Explorer -> "This PC" -> right-click -> "Map network drive" -> \\\\${pi_ip}\\shared
  iPhone    Files app -> Browse -> Connect to Server -> smb://${pi_ip}/shared
  Android   Any file manager with "Add network location (SMB)" -> smb://${pi_ip}/shared

Log in with username "$USERNAME" and the Samba password you just set (not your Pi login
password). Folders inside: photos/, files/, apps/ -- rename or add more anytime in
$SHARE_DIR, they show up immediately.
EOF
