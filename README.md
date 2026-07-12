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
| [eufy-security-ws](https://github.com/bropat/eufy-security-ws) | Bridge that lets Home Assistant talk to Eufy Security cameras/doorbells | `http://<pi-ip>:3000` |
| [ESPHome](https://esphome.io/) | Build/flash/manage your own ESP32/ESP8266 sensors | `http://<pi-ip>:6052` |
| [Zigbee2MQTT](https://www.zigbee2mqtt.io/) *(disabled by default)* | Bridges Zigbee devices to MQTT once you have a coordinator dongle | `http://<pi-ip>:8081` |
| [Homepage](https://gethomepage.dev/) | The one link everyone bookmarks — a tap-tile launcher for everything else | `http://dash/` |

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

## One link for the whole family

`install.sh` also adds a few plain hostnames to Pi-hole's DNS (no `.local`, no port
number — those trip up some devices/kids typing them), pointing at the Pi:

| Type this | Gets you |
|---|---|
| `http://dash/` | The Homepage dashboard — tap-tile launcher, the one to bookmark/pin on every phone, tablet, and kid's device |
| `http://ha:8123/` | Home Assistant directly |
| `http://pihole:8080/admin` | Pi-hole admin |
| `http://status:3001/` | Uptime Kuma |
| `http://portainer:9000/` | Portainer |
| `http://cameras:3000/` | Eufy Security bridge |

These only resolve for devices using Pi-hole as their DNS server (see above) — until
that's set on your router, use the `http://<pi-ip>:<port>` forms instead, which always
work.

`http://dash/` needs no login, so it's safe to leave open on a family tablet or put in
kids' bookmarks — it only launches to the other services, each of which keeps its own
login/admin gate (Pi-hole's password, Portainer's account, etc.). Edit the tiles it
shows in `homepage/config/services.yaml`, and its look in `homepage/config/settings.yaml`
(`docker compose restart homepage` after changes).

## Adding more automation

- Home Assistant's config lives in `config/homeassistant/` (created on first boot).
  Edit `configuration.yaml` / `automations.yaml` there directly, or use the Home
  Assistant UI (Settings → Automations).
- Mosquitto defaults to `allow_anonymous true` for simplicity on a trusted home LAN.
  To require a login instead, see the commented instructions in
  `mosquitto/config/mosquitto.conf`.
- **Node-RED** isn't included yet — add it as another service in `docker-compose.yml`
  (image `nodered/node-red`) if/when you want flow-based automations alongside HA's.

### ESPHome (DIY sensors, already running)

ESPHome is enabled by default at `http://<pi-ip>:6052` — it's just a dashboard/compiler,
so it doesn't need any hardware to be present yet. To build a new sensor: write or
generate a YAML config for your ESP32/ESP8266 board through the dashboard, connect the
board via USB to whatever computer you're using to browse to the dashboard, and flash it
(the dashboard uses your browser's Web Serial support for the very first flash). After
that first flash, updates happen over WiFi (OTA) — the ESPHome dashboard finds devices
via mDNS, which is why the container runs with `network_mode: host`.

If you'd rather flash new boards by plugging them straight into the Pi instead of a
laptop, add a `devices:` entry under the `esphome` service in `docker-compose.yml`
pointing at the board's serial port (e.g. `/dev/ttyUSB0:/dev/ttyUSB0`).

ESPHome devices publish sensor data straight to Home Assistant via its API (no MQTT
needed), or to Mosquitto (`mosquitto:1883`) if you prefer MQTT-based sensors instead.

### Zigbee2MQTT (disabled until you have a coordinator dongle)

1. Buy a Zigbee coordinator USB dongle — the [Sonoff Zigbee 3.0 USB Dongle
   Plus](https://www.zigbee2mqtt.io/guide/adapters/) is well-supported and cheap.
2. Plug it into the Pi, then find its stable device path:
   `ls -l /dev/serial/by-id/`
3. `cp zigbee2mqtt/configuration.yaml.example zigbee2mqtt/data/configuration.yaml` and
   edit the `serial.port` value to match your board's container-side path (default
   `/dev/ttyACM0`, matching the mapping below).
4. In `docker-compose.yml`, uncomment the `zigbee2mqtt` service block and replace
   `REPLACE_WITH_YOUR_DONGLE` in its `devices:` line with the by-id path from step 2.
5. `docker compose up -d zigbee2mqtt`, then open `http://<pi-ip>:8081`, flip
   `permit_join` on, and pair your devices.

With `homeassistant.enabled: true` in its config (already set in the template),
Zigbee2MQTT auto-creates Home Assistant entities for anything you pair — no extra HA
config needed.

## Your devices

Setup for each device happens mostly in the Home Assistant UI, not in config files.
Rough order: get the base stack running (above), then work through these.

### Amazon Echo devices
Home Assistant has a native **Alexa Devices** integration (added in HA 2025.6, no HACS
needed): Settings → Devices & Services → Add Integration → "Alexa Devices". Log in with
your Amazon account — it requires 2-step verification via an authenticator app (Amazon
Settings → Login & Security → 2-step verification → Backup methods → Add app). This gets
you TTS/announcements, volume, and media control on your Echoes as native entities.

### Smart plugs / lightbulbs
Not currently in use, so skipped for now. If they come back into use later, let me know
the brand (Philips Hue vs. generic "Amazon" plugs/bulbs) and I'll wire up the right
integration.

### Eufy Security (cameras/doorbell)
Already wired into `docker-compose.yml` as the `eufy-security-ws` bridge container:
1. Fill in `EUFY_USERNAME` / `EUFY_PASSWORD` / `EUFY_COUNTRY` in `.env`, then
   `docker compose up -d eufy-security-ws`.
2. Open `http://<pi-ip>:3000` — if Eufy challenges the login with a CAPTCHA or 2FA code,
   this page is where you resolve it.
3. Run `./scripts/install-hacs.sh` (one-time) to get HACS into Home Assistant, then use
   HACS to install the **Eufy Security** integration
   ([fuatakgun/eufy_security](https://github.com/fuatakgun/eufy_security)) and point it
   at `eufy-security-ws:3000`.

Use a dedicated Eufy account if you can — logging the bridge in can sign your phone app
out.

### MyQ garage door
Chamberlain (MyQ's owner) blocks third-party API access, which is why Home Assistant
[removed its official MyQ integration in 2023](https://www.home-assistant.io/blog/2023/11/06/removal-of-myq-integration/)
and no longer works reliably even with unofficial workarounds. The community-recommended
fix is [ratgdo](https://paulwieland.github.io/ratgdo/) — a small ESPHome-based board that
wires directly into the opener's existing logic board (a few screw terminals, no
soldering) and integrates with Home Assistant fully locally, bypassing MyQ's cloud
entirely. It's about $30 and considered the durable fix rather than a workaround.

### Xbox
Native **Xbox** integration, but Microsoft requires you to register your own Azure/Entra
ID app first:
1. Create an app registration at [portal.azure.com](https://portal.azure.com) (Entra ID
   directory), add a client secret under Certificates & Secrets.
2. In Home Assistant: Settings → Devices & Services → Application Credentials → add the
   Client ID/Secret for "Xbox".
3. Settings → Devices & Services → Add Integration → "Xbox", sign in with the Microsoft
   account tied to your Xboxes.

Gives you power state, currently-playing info, and basic control per console.

### Samsung Smart TV
Native **Samsung Smart TV** integration (2016+ Tizen models): Settings → Devices &
Services → Add Integration → "Samsung Smart TV", enter the TV's IP. Accept the pairing
prompt that appears on the TV screen the first time.

### Drone (DJI Mini 4 Pro)
Not automatable — out of scope. Consumer DJI drones (Mini/Air/Mavic/Neo/Flip/Avata) only
communicate with the DJI Fly app over the remote controller's own radio link; there's no
local API, network interface, or SDK a Pi/Home Assistant could reach. (The one exception
in DJI's lineup is the Tello, which has an open UDP SDK — not applicable here.)

### Amazon Glow
Also out of scope — it's a discontinued, fully closed device tied to the Glow app/Amazon
account with no public API ever offered.

## Monitoring dashboard (Uptime Kuma)

Uptime Kuma doesn't let you pre-configure monitors before its account exists, so:

1. Open `http://<pi-ip>:3001` once and create the admin account through the setup
   wizard.
2. Bulk-create a standard set of monitors (internet, Home Assistant, Pi-hole, Portainer,
   the Eufy bridge, and the MQTT broker) with the helper script:
   ```bash
   python3 -m venv .venv && .venv/bin/pip install uptime-kuma-api
   .venv/bin/python scripts/setup-uptime-kuma.py --username admin
   ```
   It's safe to re-run — it skips monitors that already exist by name.
3. Edit `scripts/setup-uptime-kuma.py` to add your own — e.g. Xbox or the Samsung TVs by
   IP (give them a DHCP reservation on your router first so the IP doesn't drift; note
   consoles/TVs won't reliably answer pings while fully powered off).
4. Configure a notification channel in the Uptime Kuma UI (Settings → Notifications —
   supports push/email/Slack/etc.) and attach it to the monitors you want alerts from.

## Reliability

A Pi running everything off its SD card 24/7 is the single biggest risk to this stack —
constant database writes (Home Assistant's recorder, Pi-hole's FTL DB, Uptime Kuma) wear
SD cards out, and corruption after a power blip is common. With your external USB 3.0
drive attached, fix that first:

### Move Docker + this project onto the external drive

```bash
./scripts/migrate-to-external-drive.sh /dev/sda   # use the whole disk, not a partition
```

This formats *only the drive you name* as ext4, mounts it at `/mnt/ssd`, moves Docker's
data-root there, and copies this project's data over — it never deletes anything on the
SD card, so you can verify the new setup works before tearing down the old copy yourself
(the script prints the exact next steps, including the `docker compose down` /
`docker compose up -d` cutover). It also caps container logs at 10MB × 3 files each, so
runaway logging can't quietly fill the disk.

If you're not sure which device is the drive, run the script with no arguments — it
lists all disks first, and it refuses to touch whatever disk is holding the OS itself.

### Self-healing containers

`docker-compose.yml` now has healthchecks on the services most worth catching if they
hang (Home Assistant, Mosquitto, Pi-hole, Uptime Kuma, Portainer, Homepage), plus an
`autoheal` container that restarts any of them Docker marks unhealthy — this catches a
process that's stuck but still running, which a plain `restart: unless-stopped` won't.
(ESPHome and the Eufy bridge are left out of this — their images don't have a way to
health-check that's reliable enough not to cause false restarts.)

### Hardware watchdog

For the rarer case where the whole OS wedges (not just a container):

```bash
./scripts/enable-watchdog.sh   # then: sudo reboot
```

Configures the Pi 5's hardware watchdog via systemd — if the system ever fully hangs, it
force-reboots instead of sitting dead until someone notices.

## Backups

```bash
./scripts/backup.sh
```

Tars up all persistent config/data into `backups/` (or `$BACKUP_DIR` if set), keeping
the last 7. Add it to cron for nightly backups — point it at the external drive once
you've migrated:

```
0 3 * * * cd /mnt/ssd/home-tools && BACKUP_DIR=/mnt/ssd/backups ./scripts/backup.sh >> /mnt/ssd/backups/backup.log 2>&1
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
  RAM/storage — the current stack (including eufy-security-ws, HACS, and Homepage) uses
  roughly 2–2.5GB, leaving limited headroom on a 4GB board.
