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

  # `|| true` matters: once `head -c 16` has read enough bytes it closes the pipe,
  # which sends tr a SIGPIPE and makes it exit non-zero -- under `pipefail` that
  # fails the whole pipeline (and aborts the script under `set -e`) even though the
  # captured output is correct.
  generated_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)
  sed -i "s/^PIHOLE_WEBPASSWORD=.*/PIHOLE_WEBPASSWORD=${generated_password}/" .env

  echo "Generated Pi-hole admin password: ${generated_password}  (also saved in .env)"
  echo "Detected Pi IP for PI_STATIC_IP: ${detected_ip:-<none found, edit .env manually>}"
  echo "Review/edit .env now if anything needs changing (timezone, IP, password), then re-run ./install.sh."
else
  log ".env already exists, using it as-is"
fi

# --- 3b. Ensure newer vars exist in .env (for stacks set up before they were added) --
if ! grep -q '^SPEEDTEST_APP_KEY=' .env; then
  echo 'SPEEDTEST_APP_KEY=' >> .env
fi
if [[ -z "$(grep '^SPEEDTEST_APP_KEY=' .env | cut -d= -f2-)" ]]; then
  log "Generating a Speedtest Tracker APP_KEY"
  app_key="base64:$(openssl rand -base64 32)"
  # `|` appears in base64, so use a sed delimiter that can't collide with it
  sed -i "s#^SPEEDTEST_APP_KEY=.*#SPEEDTEST_APP_KEY=${app_key}#" .env
fi
grep -q '^WG_SERVERURL=' .env || echo 'WG_SERVERURL=auto' >> .env
grep -q '^WG_PEERS=' .env || echo 'WG_PEERS=phone,laptop' >> .env

# --- 4. Data directories ---------------------------------------------------
mkdir -p config/homeassistant \
         mosquitto/data mosquitto/log \
         pihole/etc-pihole pihole/etc-dnsmasq.d \
         uptime-kuma portainer eufy-security-ws \
         esphome zigbee2mqtt/data \
         vaultwarden speedtest-tracker mealie wireguard

# --- 5. Friendly local hostnames, served by Pi-hole's DNS -------------------
# shellcheck disable=SC1091
set -a; source .env; set +a

if [[ -n "${PI_STATIC_IP:-}" ]]; then
  log "Adding friendly local hostnames to Pi-hole (dash, ha, pihole, status, portainer, cameras)"
  custom_list="pihole/etc-pihole/custom.list"
  touch "$custom_list"
  for name in dash ha pihole status portainer cameras vault speed meals; do
    sed -i "/[[:space:]]${name}\$/d" "$custom_list"
    echo "${PI_STATIC_IP} ${name}" >> "$custom_list"
  done
else
  echo "PI_STATIC_IP is not set in .env, skipping friendly hostnames. Set it and re-run." >&2
fi

# --- 6. Bring the stack up -------------------------------------------------
log "Pulling images"
docker compose pull

log "Starting services"
docker compose up -d
docker compose restart pihole >/dev/null 2>&1 || true # pick up custom.list if pihole was already running

pi_ip=$(hostname -I | awk '{print $1}')
cat <<EOF

Stack is up. Give Home Assistant a minute to finish its first boot, then visit:

  Dashboard        http://dash/            (once your router/devices use Pi-hole as DNS)
  Home Assistant   http://ha:8123/          or http://${pi_ip}:8123
  Pi-hole admin    http://pihole:8080/admin or http://${pi_ip}:8080/admin
  Uptime Kuma      http://status:3001/      or http://${pi_ip}:3001
  Portainer        http://portainer:9000/   or http://${pi_ip}:9000
  Eufy bridge      http://cameras:3000/     or http://${pi_ip}:3000
  Vaultwarden      http://vault:8222/       or http://${pi_ip}:8222
  Speedtest        http://speed:8765/       or http://${pi_ip}:8765
  Mealie           http://meals:9925/       or http://${pi_ip}:9925
  MQTT broker      ${pi_ip}:1883

WireGuard VPN configs (scan the QR codes with the WireGuard phone app):
  docker exec wireguard /app/show-peer phone   # or: laptop, etc.

See README.md for next steps (setting Pi-hole as your router's DNS, backups, adding more services).
EOF
