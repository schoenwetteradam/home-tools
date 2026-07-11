# home-tools

A self-hosted home automation & network stack for a Raspberry Pi 5 (4GB), run entirely
via Docker Compose:

| Service | What it's for | Default URL |
|---|---|---|
| [Home Assistant](https://www.home-assistant.io/) | Smart-home hub: dashboards, device integrations, automations | `http://<pi-ip>:8123` |
| [Mosquitto](https://mosquitto.org/) | Local MQTT broker for ESPHome, Zigbee2MQTT, Tasmota, or your own DIY sensors | `<pi-ip>:1883` |
| [Pi-hole](https://pi-hole.net/) | Network-wide ad blocking + local DNS | `http://<pi-ip>:8080/admin` |
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Watches your internet connection and LAN devices, alerts you when something goes down | `http://<pi-ip>:3001` |
| [Portainer](https://www.portainer.io/) | Web UI for managing the containers | `http://<pi-ip>:9000` |

This is a starting point, not a fixed design — swap or drop services in `docker-compose.yml`
as your needs become clearer (see "Expanding" below).

## Requirements

- Raspberry Pi 5 (4GB is enough for this stack; leaves some headroom)
- 64-bit Raspberry Pi OS (Bookworm) flashed with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — Lite is fine for a headless setup, enable SSH when flashing
- Pi on your home network, ideally with a **DHCP reservation / static IP** set on your router so Pi-hole's address never changes
- (Optional) a USB Zigbee/Z-Wave dongle if you want to add those devices later

## Quick start

```bash
ssh pi@<pi-ip>
git clone <this-repo-url> home-tools
cd home-tools
./install.sh
```

`install.sh` installs Docker if needed, frees up port 53 from `systemd-resolved` (required
for Pi-hole), generates a `.env` with your Pi's detected IP and a random Pi-hole admin
password, then starts everything. It prints the service URLs and the generated password
when it's done — re-run it any time, it's safe to repeat.

Review `.env` afterwards (timezone, IP, password) and re-run `./install.sh` if you change
anything.

## Making Pi-hole your DNS

For ad-blocking to apply to every device on your network, point your router's DHCP DNS
setting to the Pi's static IP (not just individual devices). Check your router's admin
page for "DNS Server" or "DHCP settings".

## Adding more automation

- **Zigbee2MQTT / ESPHome / Node-RED** can be added as extra services in
  `docker-compose.yml`, all pointed at the same Mosquitto broker (`mosquitto:1883`).
- Home Assistant's config lives in `config/homeassistant/` (created on first boot).
  Edit `configuration.yaml` / `automations.yaml` there directly, or use the Home
  Assistant UI (Settings → Automations).
- Mosquitto defaults to `allow_anonymous true` for simplicity on a trusted home LAN.
  To require a login instead, see the commented instructions in
  `mosquitto/config/mosquitto.conf`.

## Backups

```bash
./scripts/backup.sh
```

Tars up all persistent config/data into `backups/`, keeping the last 7. Add it to cron
for nightly backups:

```
0 3 * * * cd /home/pi/home-tools && ./scripts/backup.sh >> backups/backup.log 2>&1
```

## Updating

```bash
docker compose pull && docker compose up -d
```

## Notes

- `homeassistant` runs with `network_mode: host` and `privileged: true` — host networking
  is needed for device discovery (mDNS/SSDP), and `privileged` gives it access to USB
  devices like Zigbee dongles. Drop `privileged: true` if you don't plan to pass through
  hardware.
- Avoid adding heavier services (Plex/Jellyfin, Frigate NVR) to this same Pi without more
  RAM/storage — the current stack uses roughly 1.5–2GB, leaving limited headroom on a 4GB
  board.
