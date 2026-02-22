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

| Component | Description |
|-----------|-------------|
| ESP32 development board | Any standard ESP32 board (e.g., ESP32-WROOM, LILYGO T-Display) |
| Addressable LED strip | WS2812B, SK6812, or compatible. Number of pixels depends on your enclosure design. |
| Power supply | 5V USB or dedicated 5V supply (check LED strip current requirements) |
| Data wire | Connect LED strip data pin to ESP32 GPIO (default: GPIO 2 in WLED) |
| Enclosure | See `specs/` for hardware enclosure specifications |

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

- **Data pin**: Connect the LED strip's data input to GPIO 2 (WLED default). This can be changed in WLED's LED settings.
- **Power**: Power the LED strip according to its specifications. For strips with many pixels, use a dedicated 5V power supply rather than USB power from the ESP32.
- **Ground**: Ensure common ground between the ESP32 and the LED strip power supply.

Refer to the wiring diagrams in `specs/HARDWARE TASK.pdf` for BusyLight-specific enclosure wiring.

---

## Step 3: Configure WLED

Once your device is connected to Wi-Fi:

1. Open a browser and navigate to the WLED device's IP address (shown in your router's DHCP table, or via the WLED mobile app).
2. Complete the LED configuration:
   - Set the LED type (e.g., WS2812B)
   - Set the number of LEDs
   - Set the GPIO data pin
3. Configure your time zone and NTP server (optional but recommended).

---

## Step 4: Create BusyLight Presets

BusyLight uses WLED presets to represent each presence state. Create the following presets in WLED's Presets panel:

| Preset ID | Name | Color / Animation | Presence State |
|-----------|------|-------------------|----------------|
| 1 | Available | Solid green | Available |
| 2 | Tentative | Solid yellow | Tentative |
| 3 | Busy | Solid red (or pulsing red) | Busy / In Meeting |
| 4 | Away | Solid blue | Away |
| 5 | Off | All LEDs off | Off / Inactive |
| 6 | Unknown | Solid white (dim) | Unknown / Disconnected |

The macOS agent calls WLED's JSON API with a preset ID to change the light state. You may customize colors and animations to your preference — only the preset IDs need to match what the agent expects.

> **Tip**: Use WLED's animation features (breathing, pulsing) for the Busy state to make it more visually distinct from a distance.

---

## Step 5: Note Your Device IP Address

The macOS agent needs the WLED device's IP address to communicate with it.

Assign a static IP address to your ESP32 in your router's DHCP settings (recommended) or configure a static IP directly in WLED's network settings. This prevents the IP from changing after router restarts.

---

## WLED JSON API Reference

The macOS agent communicates with WLED using its standard JSON API. The primary endpoint used is:

```
POST http://<device-ip>/json/state
```

Example payload to activate preset 1 (Available):

```json
{
  "ps": 1
}
```

Full WLED API documentation: [https://kno.wled.ge/interfaces/json-api/](https://kno.wled.ge/interfaces/json-api/)

---

## Troubleshooting

**Device not appearing on network**: Ensure WLED was flashed successfully and Wi-Fi credentials were entered correctly. Check your router's DHCP client list.

**LEDs not lighting up**: Verify wiring (data pin, power, ground) and ensure the LED type and GPIO pin are configured correctly in WLED's LED settings.

**macOS agent cannot reach device**: Confirm the device IP address and ensure both your Mac and the ESP32 are on the same Wi-Fi network.

**Preset not activating**: Verify preset IDs in WLED match the IDs expected by the macOS agent configuration.

---

[← Back to Docs Home](index.md) · [Software Documentation →](software.md) · [Architecture →](architecture.md)
