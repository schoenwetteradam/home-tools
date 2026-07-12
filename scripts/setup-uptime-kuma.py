#!/usr/bin/env python3
"""
Bulk-creates a standard set of Uptime Kuma monitors for this stack. Safe to re-run:
skips monitors that already exist (matched by name).

Uptime Kuma has no way to pre-seed its admin account, so first visit
http://<pi-ip>:3001 once and create it through the setup wizard, then run this.

    python3 -m venv .venv && .venv/bin/pip install uptime-kuma-api
    .venv/bin/python scripts/setup-uptime-kuma.py --username admin
"""
import argparse
import getpass

from uptime_kuma_api import MonitorType, UptimeKumaApi

MONITORS = [
    dict(type=MonitorType.PING, name="Internet", hostname="1.1.1.1"),
    dict(type=MonitorType.HTTP, name="Home Assistant", url="http://localhost:8123"),
    dict(type=MonitorType.HTTP, name="Pi-hole", url="http://localhost:8080/admin"),
    dict(type=MonitorType.HTTP, name="Portainer", url="http://localhost:9000"),
    dict(type=MonitorType.HTTP, name="Eufy Security bridge", url="http://localhost:3000"),
    dict(type=MonitorType.PORT, name="MQTT broker", hostname="localhost", port=1883),
    # Xbox/Samsung TV/etc. sleep and won't reliably answer pings when powered off, but
    # it's still handy to see when they're on the network. Fill in real IPs (give them
    # a DHCP reservation on your router first) and uncomment:
    # dict(type=MonitorType.PING, name="Xbox", hostname="192.168.1.50"),
    # dict(type=MonitorType.PING, name="Living Room TV", hostname="192.168.1.51"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:3001")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", help="omit to be prompted (safer than shell history)")
    args = parser.parse_args()
    password = args.password or getpass.getpass("Uptime Kuma password: ")

    with UptimeKumaApi(args.url) as api:
        api.login(args.username, password)
        existing = {m["name"] for m in api.get_monitors()}
        for monitor in MONITORS:
            if monitor["name"] in existing:
                print(f"skip (already exists): {monitor['name']}")
                continue
            api.add_monitor(**monitor)
            print(f"added: {monitor['name']}")


if __name__ == "__main__":
    main()
