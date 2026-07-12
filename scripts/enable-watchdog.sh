#!/usr/bin/env bash
# Enables the Pi 5's hardware watchdog: if the OS itself ever fully hangs (not just a
# container crashing -- Docker's restart policies already handle that), the board
# force-reboots itself instead of staying wedged until someone notices.
set -euo pipefail

boot_config=/boot/firmware/config.txt
if [[ ! -f "$boot_config" ]]; then
  echo "Could not find $boot_config -- is this Raspberry Pi OS Bookworm on a Pi 5?" >&2
  exit 1
fi

if ! grep -q '^dtparam=watchdog=on' "$boot_config"; then
  echo 'dtparam=watchdog=on' | sudo tee -a "$boot_config" >/dev/null
fi

sys_conf=/etc/systemd/system.conf
sudo sed -i 's/^#\?RuntimeWatchdogSec=.*/RuntimeWatchdogSec=15s/' "$sys_conf"
grep -q '^RuntimeWatchdogSec=' "$sys_conf" || echo 'RuntimeWatchdogSec=15s' | sudo tee -a "$sys_conf" >/dev/null
sudo sed -i 's/^#\?RebootWatchdogSec=.*/RebootWatchdogSec=10min/' "$sys_conf"
grep -q '^RebootWatchdogSec=' "$sys_conf" || echo 'RebootWatchdogSec=10min' | sudo tee -a "$sys_conf" >/dev/null

echo "Watchdog configured (systemd will pet it, and force-reboot if the system ever hangs)."
echo "Reboot once to apply: sudo reboot"
