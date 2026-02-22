---
layout: default
title: Hardware Setup — BusyLight
description: How to build the BusyLight physical device using ESP32 and WLED firmware.
---

# Hardware Setup (WLED and ESP32)

This guide covers the hardware component of BusyLight: an ESP32 microcontroller running WLED firmware, connected to an addressable LED strip or matrix.

> **Before you start**: This guide assumes you are comfortable with basic electronics. You will need to read the official WLED documentation in parallel with this guide. BusyLight uses WLED as its device runtime — this guide focuses only on BusyLight-specific configuration.

---

## Required Reading: Official WLED Documentation

This project builds on top of WLED. You **must** read the official WLED documentation to understand firmware installation, pin configuration, and the JSON API:

- 📖 **WLED GitHub**: [https://github.com/wled/WLED](https://github.com/wled/WLED)
- 🔧 **WLED Web Installer**: [https://install.wled.me/](https://install.wled.me/)
- 📚 **WLED Wiki**: [https://kno.wled.ge/](https://kno.wled.ge/)

---

## Why WLED?

WLED was chosen as the device firmware because:

- It provides a mature, well-documented HTTP JSON API that the macOS agent uses to control the light.
- It handles all low-level LED hardware communication, freeing this project from needing to write or maintain firmware.
- It has an active community and is widely deployed in DIY projects.
- It supports presets — named configurations of colors and animations — which map directly to BusyLight presence states.
- It runs on widely available, low-cost ESP32 hardware.

---

## Hardware Requirements

> **Detailed step-by-step assembly instructions**: See [Hardware Module Assembly Guide](module-assembly.md).

| Component | Specification | Est. Cost (USD) |
|-----------|--------------|-----------------|
| ESP32 Dev Board | USB Type-C, Wi-Fi/Bluetooth | ~$8 |
| WS2812 LED Matrix | 8×8 (64 LEDs), NeoPixel-compatible | ~$7 |
| Dupont Cables | Female-Female, 10 cm, 40-pack | ~$2 |
| Enclosure | 100×100×62 mm, weatherproof | ~$3 |
| USB-C Cable + 5V 2A Power Adapter | Data + power | ~$5 |
| **Total** | | **~$25 USD** |

> **Note**: ESP32 supports **2.4 GHz Wi-Fi only**. 5 GHz networks are not supported.

---

## Step 1: Flash WLED Firmware

Use the WLED web installer to flash firmware directly from your browser — no additional tools required:

1. Open [https://install.wled.me/](https://install.wled.me/) in a Chromium-based browser (Chrome, Edge).
2. Connect your ESP32 board via USB.
3. Click **Install** and select your board's serial port.
4. Wait for flashing to complete.
5. When prompted, enter your Wi-Fi credentials to connect the device to your home network.

> **Note**: Ensure your ESP32 is not connected to any LED hardware during flashing to avoid power issues.

---

## Step 2: Connect the LED Hardware

After flashing, connect your LED strip to the ESP32:

| ESP32 Pin | Wire Color | LED Matrix Pin | Function |
|-----------|------------|----------------|----------|
| 5V | Red | VCC / 5V | Power supply |
| GND | Black | GND | Ground return |
| GPIO 2 | Yellow | DIN | Data input |

- **Data pin**: Connect the LED matrix DIN pad to GPIO 2 (WLED default). This can be changed in WLED's LED settings.
- **Power**: For an 8×8 matrix at typical brightness, USB power from the ESP32 is sufficient. For full-brightness operation, use a dedicated 5V 2A supply.
- **Ground**: Ensure common ground between the ESP32 and the power supply.

> **⚠️ Check polarity before powering on!** Reversed 5V/GND connections can permanently damage components.

Refer to the detailed wiring diagrams in [module-assembly.md](module-assembly.md).

---

## Step 3: Configure WLED

Once your device is connected to Wi-Fi:

1. Open a browser and navigate to the WLED device's IP address (shown in your router's DHCP table, or via the WLED mobile app).
2. Complete the LED configuration:
   - LED Type: **WS2812B** (or compatible SK6812)
   - LED Count: **64** (8×8 matrix)
   - Data GPIO: **2** (default)
   - Color Order: **GRB** (typical for WS2812B)
3. Configure your time zone and NTP server (optional but recommended).

---

## Step 4: Create BusyLight Presets

BusyLight uses WLED presets to represent each presence state. Create the following presets in WLED's Presets panel:

| Preset ID | Name | Color / Animation | Presence State |
|-----------|------|-------------------|----------------|
| 1 | Available | Green solid (`#00FF00`), 75% brightness | Available |
| 2 | Tentative | Yellow/Amber breathe (`#FFA500`), 50% brightness | Tentative |
| 3 | Busy | Red solid (`#FF0000`), 75% brightness | Busy / In Meeting |
| 4 | Away | Blue fade (`#0000FF`), 30% brightness | Away |
| 5 | Unknown | White blink (`#FFFFFF`), 40% brightness | Unknown / Disconnected |
| 6 | Off | All LEDs off (brightness 0%) | Off / Inactive |

The macOS agent calls WLED's JSON API with a preset ID to change the light state. You may customize colors and animations to your preference — only the preset IDs need to match what the agent expects.

> **Tip**: The "Breathe" effect for Tentative and "Fade" for Away give each state a distinct rhythm that is recognisable from a distance even when you can't see the color clearly.

---

## Step 5: Note Your Device IP Address

The macOS agent needs the WLED device's IP address to communicate with it. By default, the agent uses **Bonjour/mDNS discovery** (`_http._tcp`) to find WLED devices automatically — no manual IP configuration needed if your router does not block mDNS.

If auto-discovery doesn't work (e.g., on networks with VLAN isolation), assign a static IP to your ESP32 in your router's DHCP settings and configure it manually:

```bash
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100"
```

See [Software Documentation](software.md) for all configuration options.

---

## WLED JSON API Reference

The macOS agent communicates with WLED using its standard JSON API. The two endpoints used are:

**Activate a preset:**
```
POST http://<device-ip>/json/state
Content-Type: application/json

{"ps": 1, "v": true}
```

Response: `{"on": true, "bri": 191, "ps": 1, ...}`

**Read device info (health check):**
```
GET http://<device-ip>/json/info
```

Full WLED API documentation: [https://kno.wled.ge/interfaces/json-api/](https://kno.wled.ge/interfaces/json-api/)

---

## Troubleshooting

**Device not appearing on network**: Ensure WLED was flashed successfully and Wi-Fi credentials were entered correctly. Check your router's DHCP client list. Confirm you are on a 2.4 GHz network.

**LEDs not lighting up**: Verify wiring (data pin GPIO 2, power 5V, ground) and ensure LED type and count are configured correctly in WLED.

**macOS agent cannot reach device**: Confirm the device IP and ensure both your Mac and the ESP32 are on the same subnet. Try disabling Bonjour discovery and configuring the IP manually.

**Preset not activating**: Verify preset IDs 1–6 exist in WLED and test each manually via the WLED web interface or curl before running the agent.

For full testing procedures, see [WLED Network Module Testing Guide](module-testing.md).

---

[← Back to Docs Home](index.md) · [Software Documentation →](software.md) · [Architecture →](architecture.md) · [Assembly Guide →](module-assembly.md)
