#!/usr/bin/env bash
# Moves Docker's data-root and a copy of this project onto an external drive, so the
# SD card stops taking the constant database writes from Home Assistant/Pi-hole/etc.
# (the #1 reliability killer for a 24/7 Pi appliance).
#
# ONLY the drive you name gets formatted/erased. Nothing on the SD card or in the
# current project directory is deleted -- this script copies, it never removes, so you
# can verify the new setup works before tearing down the old one yourself (see the
# printed next steps at the end).
#
# Usage: ./scripts/migrate-to-external-drive.sh /dev/sdX   (the whole disk, e.g. /dev/sda -- NOT a partition like /dev/sda1)
set -euo pipefail

log() { printf '\n==> %s\n' "$1"; }

DEVICE="${1:-}"
MOUNT_POINT="/mnt/ssd"

if [[ -z "$DEVICE" ]]; then
  echo "Usage: $0 /dev/sdX" >&2
  echo >&2
  echo "Available disks:" >&2
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT >&2
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "$DEVICE is not a block device." >&2
  exit 1
fi

root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)
if [[ -n "$root_disk" && "$DEVICE" == "/dev/$root_disk" ]]; then
  echo "$DEVICE appears to hold the Pi's root filesystem (SD card/boot drive). Refusing to touch it." >&2
  exit 1
fi

echo "This will ERASE ALL DATA on $DEVICE:"
lsblk "$DEVICE"
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted, nothing changed."; exit 1; }

for bin in parted rsync; do
  command -v "$bin" >/dev/null 2>&1 || { log "Installing $bin"; sudo apt-get update -qq && sudo apt-get install -y "$bin"; }
done

log "Partitioning and formatting $DEVICE as ext4"
for part in "${DEVICE}"*[0-9]; do
  sudo umount "$part" 2>/dev/null || true
done
sudo parted -s "$DEVICE" mklabel gpt mkpart primary ext4 0% 100%
sudo partprobe "$DEVICE"
sleep 2
partition="${DEVICE}1"
sudo mkfs.ext4 -F -L hometools "$partition"

uuid=$(sudo blkid -s UUID -o value "$partition")
sudo mkdir -p "$MOUNT_POINT"
if ! grep -q "$uuid" /etc/fstab; then
  echo "UUID=$uuid $MOUNT_POINT ext4 defaults,noatime,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
fi
sudo mount -a
log "Mounted $partition at $MOUNT_POINT"

# --- Move Docker's data-root --------------------------------------------
log "Copying Docker's data-root to $MOUNT_POINT/docker (this can take a while)"
sudo systemctl stop docker
sudo mkdir -p "$MOUNT_POINT/docker"
sudo rsync -a /var/lib/docker/ "$MOUNT_POINT/docker/"

daemon_json=/etc/docker/daemon.json
sudo mkdir -p /etc/docker
sudo python3 - "$daemon_json" "$MOUNT_POINT/docker" <<'PYEOF'
import json, os, sys

path, data_root = sys.argv[1], sys.argv[2]
config = {}
if os.path.exists(path):
    content = open(path).read().strip()
    if content:
        config = json.loads(content)

config["data-root"] = data_root
config.setdefault("log-driver", "json-file")
config.setdefault("log-opts", {})
config["log-opts"].setdefault("max-size", "10m")
config["log-opts"].setdefault("max-file", "3")

with open(path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

sudo systemctl start docker
log "Docker now uses $MOUNT_POINT/docker as its data-root, with log rotation capped at 10MB x 3 files per container"
echo "The old data is untouched at /var/lib/docker -- once everything below checks out, reclaim SD card space with: sudo rm -rf /var/lib/docker"

# --- Copy this project's persistent data ---------------------------------
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
new_project_dir="$MOUNT_POINT/home-tools"
log "Copying $project_dir to $new_project_dir"
rsync -a --exclude '.git' "$project_dir/" "$new_project_dir/"

cat <<EOF

Done. Docker's data-root and a copy of this project now live on $MOUNT_POINT.
Nothing on the SD card was deleted -- finish the cutover yourself once you've checked
everything works:

  1. cd $project_dir && docker compose down
  2. cd $new_project_dir && docker compose up -d
  3. Confirm http://dash/ and the rest of the services still work.
  4. Update any cron jobs (e.g. the backup one) to point at $new_project_dir.
  5. Once you're confident, reclaim SD card space:
       sudo rm -rf /var/lib/docker      # old Docker data-root, now unused
       rm -rf $project_dir              # old project copy
EOF
