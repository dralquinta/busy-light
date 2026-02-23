---
layout: default
title: BusyLight Configuration
---

# Configuration

BusyLight stores settings in macOS `UserDefaults` under the suite `com.busylight.agent`.

## Configure Device Address (Menu Bar)

1. Click the BusyLight icon in the menu bar.
2. Open `Device`.
3. Select `Configure Device Address...`.
4. Enter the WLED IPv4 address (example: `192.168.1.42`).
5. Click `Save`.

The address is applied immediately and persists across restarts.

If no address is configured, the agent will auto-save the first WLED device it discovers.

### Device Status

The `Device` submenu shows:

- `Connected to: <address>`
- `Status: Online | Offline | Unknown`

If the device is unreachable, the status becomes `Offline` and the agent continues retrying the configured address.

## Persistent Keys

- `app.device_network_addresses`: Array of configured WLED addresses.
- `app.device_network_address`: Legacy single address (kept in sync for backward compatibility).
- `app.device_network_port`: WLED HTTP port (default: 80).

## Troubleshooting

- If the address is invalid, BusyLight shows an error and does not save the value.
- To verify settings, run: `defaults read com.busylight.agent`.
- To view logs, use: `log stream --predicate 'subsystem == "com.busylight.agent.*"'`.
