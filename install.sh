#!/usr/bin/env bash
# One-shot installer for the home-tools stack on a Raspberry Pi (Debian/Raspberry Pi OS).
# Safe to re-run: it skips steps that are already done.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

log() { printf '\n==> %s\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer targets Raspberry Pi OS (Linux). Aborting." >&2
  exit 1
fi

# --- 1. Docker ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "Added $USER to the docker group. Log out and back in (or reboot) before running docker without sudo."
else
  log "Docker already installed, skipping"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin not found even after Docker install. Please install it manually and re-run." >&2
  exit 1
fi

# --- 2. Free up port 53 for Pi-hole -------------------------------------
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  if ! grep -q '^DNSStubListener=no' /etc/systemd/resolved.conf 2>/dev/null; then
    log "Disabling systemd-resolved's DNS stub listener so Pi-hole can bind port 53"
    sudo sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
    grep -q '^DNSStubListener=no' /etc/systemd/resolved.conf || echo 'DNSStubListener=no' | sudo tee -a /etc/systemd/resolved.conf >/dev/null
    sudo rm -f /etc/resolv.conf
    echo 'nameserver 127.0.0.1' | sudo tee /etc/resolv.conf >/dev/null
    sudo systemctl restart systemd-resolved
  fi
fi

# --- 3. .env -------------------------------------------------------------
if [[ ! -f .env ]]; then
  log "Creating .env from .env.example"
  cp .env.example .env

  detected_ip=$(hostname -I | awk '{print $1}')
  if [[ -n "$detected_ip" ]]; then
    sed -i "s/^PI_STATIC_IP=.*/PI_STATIC_IP=${detected_ip}/" .env
  fi

  generated_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
  sed -i "s/^PIHOLE_WEBPASSWORD=.*/PIHOLE_WEBPASSWORD=${generated_password}/" .env

  echo "Generated Pi-hole admin password: ${generated_password}  (also saved in .env)"
  echo "Detected Pi IP for PI_STATIC_IP: ${detected_ip:-<none found, edit .env manually>}"
  echo "Review/edit .env now if anything needs changing (timezone, IP, password), then re-run ./install.sh."
else
  log ".env already exists, using it as-is"
fi

# --- 4. Data directories ---------------------------------------------------
mkdir -p config/homeassistant \
         mosquitto/data mosquitto/log \
         pihole/etc-pihole pihole/etc-dnsmasq.d \
         uptime-kuma portainer eufy-security-ws

# --- 5. Bring the stack up -------------------------------------------------
log "Pulling images"
docker compose pull

log "Starting services"
docker compose up -d

pi_ip=$(hostname -I | awk '{print $1}')
cat <<EOF

Stack is up. Give Home Assistant a minute to finish its first boot, then visit:

  Home Assistant   http://${pi_ip}:8123
  Pi-hole admin    http://${pi_ip}:8080/admin
  Uptime Kuma      http://${pi_ip}:3001
  Portainer        http://${pi_ip}:9000
  MQTT broker      ${pi_ip}:1883

See README.md for next steps (setting Pi-hole as your router's DNS, backups, adding more services).
EOF
