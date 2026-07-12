#!/usr/bin/env bash
# Installs HACS (Home Assistant Community Store) into the HA config directory
# without the interactive get.hacs.xyz installer. Needed for the Eufy Security
# custom integration (and anything else not in HA core).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

TARGET="config/homeassistant/custom_components/hacs"
mkdir -p "$TARGET"

download_url=$(curl -fsSL https://api.github.com/repos/hacs/integration/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*hacs.zip"' \
  | cut -d'"' -f4)

if [[ -z "$download_url" ]]; then
  echo "Could not find the latest HACS release asset. Check https://github.com/hacs/integration/releases manually." >&2
  exit 1
fi

tmp_zip=$(mktemp --suffix=.zip)
curl -fsSL "$download_url" -o "$tmp_zip"
unzip -oq "$tmp_zip" -d "$TARGET"
rm -f "$tmp_zip"

cat <<'EOF'

HACS files installed. Next steps:
  1. docker compose restart homeassistant
  2. In the Home Assistant UI: Settings > Devices & Services > Add Integration > HACS
     (this walks you through a GitHub device-code login, one-time)
  3. Once HACS is set up, use it to install "Eufy Security" (fuatakgun/eufy_security) -
     add it as a custom repository if it doesn't show up in the default search.
EOF
