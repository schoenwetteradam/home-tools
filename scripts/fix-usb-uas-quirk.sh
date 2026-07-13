#!/usr/bin/env bash
# Fixes a common Raspberry Pi issue where a USB-SATA/SSD bridge chip doesn't work
# with the kernel's UAS (USB Attached SCSI) driver: the drive connects, then dmesg
# shows uas_eh_device_reset_handler / "Read Capacity failed" / "0-byte physical
# blocks", and the drive shows up as a bogus tiny size in lsblk. The fix is forcing
# the older usb-storage (BOT) driver for that specific device via a kernel quirk.
#
# Usage: ./scripts/fix-usb-uas-quirk.sh <idVendor>:<idProduct>
#   Find these with `lsusb`, or in `dmesg` output (e.g. "idVendor=0bc2, idProduct=ac15").
set -euo pipefail

ID="${1:-}"
if [[ -z "$ID" ]]; then
  echo "Usage: $0 <idVendor>:<idProduct>   e.g. $0 0bc2:ac15" >&2
  echo "Find it with: lsusb" >&2
  exit 1
fi

cmdline=/boot/firmware/cmdline.txt
quirk="usb-storage.quirks=${ID}:u"

if [[ ! -f "$cmdline" ]]; then
  echo "Could not find $cmdline -- is this Raspberry Pi OS Bookworm?" >&2
  exit 1
fi

line_count=$(wc -l < "$cmdline")
if [[ "$line_count" -gt 1 ]]; then
  echo "$cmdline has more than one line, which is unexpected for this file -- not" >&2
  echo "touching it automatically. Edit it by hand instead: append ' $quirk' to" >&2
  echo "the single existing line (cmdline.txt must stay one line or the Pi won't boot)." >&2
  exit 1
fi

if grep -q "usb-storage.quirks=${ID}" "$cmdline"; then
  echo "Quirk for $ID is already set in $cmdline"
else
  sudo cp "$cmdline" "${cmdline}.bak"
  sudo sed -i "s/\$/ ${quirk}/" "$cmdline"
  echo "Added '$quirk' to $cmdline (backup saved as ${cmdline}.bak)"
fi

echo
echo "cmdline.txt must stay a single line -- double check that below, then reboot:"
cat "$cmdline"
echo
echo "Reboot to apply: sudo reboot"
