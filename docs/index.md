---
layout: default
title: BusyLight — Physical Presence Indicator for Remote Workers
description: A macOS menu bar agent and ESP32/WLED LED light that signals your availability to everyone at home — automatically, privately, and beautifully.
---

# 💡 BusyLight

**A physical presence light for your home office — driven by your macOS calendar, powered by open hardware.**

---

## The Problem

Working from home is increasingly common. But one challenge rarely discussed is this: **the people who share your home have no way of knowing whether you are available or not**.

Your calendar knows you are in a meeting. Your colleagues see your status in Slack. But your partner, children, or housemates? They have no signal. They cannot see your calendar. They cannot know that the next 45 minutes are critical.

The result is interruptions — during client calls, during deep focus sessions, during important decisions. These interruptions are not anyone's fault. They happen because **there is no physical signal** for your availability.

---

## The Solution

BusyLight is a small, self-contained Wi-Fi LED device that sits anywhere in your home and communicates your availability with light:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Available — come in, no problem |
| 🟡 Yellow | Tentative — might be a moment, knock first |
| 🔴 Red | Busy / In a Meeting — please do not interrupt |
| 🔵 Blue | Away — stepped out |
| ⚫ Off | Not active |

The light updates automatically from your macOS calendar. When a meeting starts, the light turns red. When the meeting ends, it returns to green. No manual intervention needed.

You can also override the light instantly using keyboard shortcuts or a Stream Deck button — useful for focus sessions, sensitive calls, or any time you need immediate control.

---

## Why Physical?

Software presence indicators — Slack statuses, Teams availability dots — are invisible to people who are not looking at those apps. A physical light is universally readable, at a glance, from anywhere in a room.

It requires no apps. No screens. No explanation. A red light means busy. Everyone understands.

---

## The Philosophy

BusyLight is designed around three core values:

**Local-first privacy**: Your calendar data never leaves your machine. The macOS agent reads your calendar locally and communicates with the device over your home Wi-Fi. No cloud. No external accounts. No subscriptions.

**Open hardware and software**: The device runs [WLED](https://github.com/wled/WLED), a widely-used open-source LED firmware. The macOS agent is open-source Swift. Everything is inspectable, modifiable, and hackable.

**Respectful simplicity**: The light is a signal, not a surveillance tool. It communicates one thing — availability — clearly and without complexity.

---

## How It Works

```
Your Calendar  ──►  macOS Agent  ──(HTTP JSON)──►  WLED (ESP32)  ──►  LED Light
                        │
                   Hotkeys / Stream Deck
                   (manual override)
```

1. The **macOS agent** runs in your menu bar and reads your calendar every minute.
2. It resolves your current presence state using a priority-based state machine.
3. It sends the resolved state to the **WLED device** via its HTTP JSON API.
4. The **ESP32 microcontroller** runs WLED firmware, which translates the command into a color and animation on your LED matrix or strip.

---

## Understanding the Hardware Layer (WLED and ESP32)

The physical device is built on two open-source components:

### ESP32

The [ESP32](https://www.espressif.com/en/products/socs/esp32) is a low-cost, Wi-Fi-enabled microcontroller widely used in DIY projects. It connects to your home Wi-Fi network and acts as the bridge between the macOS agent and the LED hardware.

### WLED

[WLED](https://github.com/wled/WLED) is an open-source firmware for ESP32 (and ESP8266) that provides full control over addressable LED strips and matrices. It includes:

- A web-based configuration interface
- A REST/JSON API for remote control
- Support for presets, animations, and color palettes
- An active community and comprehensive documentation

**This project does not replace WLED. It builds on top of it.**

The macOS agent communicates with WLED using its standard HTTP JSON API. WLED handles all hardware communication and pixel rendering. The agent simply instructs WLED which preset to activate.

### Essential WLED Resources

Before building the hardware, you must read:

- 📖 **WLED Documentation**: [https://github.com/wled/WLED](https://github.com/wled/WLED)
- 🔧 **WLED Web Installer** (flash firmware in-browser): [https://install.wled.me/](https://install.wled.me/)

See [Hardware Setup Guide](hardware.md) for BusyLight-specific wiring and configuration.

---

## Understanding the Software Layer (macOS Agent)

The macOS agent is a native Swift application that runs in your menu bar. It:

- Reads your macOS calendar events using EventKit
- Resolves your current presence state using a priority-based state machine
- Sends HTTP JSON commands to your WLED device
- Responds to global keyboard shortcuts for manual override
- Persists state across application restarts and system sleep

See [Software Documentation](software.md) for full details.

---

## Installation Overview

### Hardware Setup (ESP32 + WLED)

1. Purchase an ESP32 development board
2. Connect an addressable LED strip (e.g., WS2812B) to the appropriate GPIO pin
3. Flash WLED firmware using the [web installer](https://install.wled.me/)
4. Configure your Wi-Fi credentials and LED settings via the WLED web interface
5. Create presets for each presence state

→ Full details: [Hardware Setup Guide](hardware.md)

### Software Setup (macOS Agent)

1. Clone this repository
2. Build the app: `./build.sh`
3. Grant Accessibility and Calendar permissions
4. Configure the WLED device IP address in the app settings (or rely on Bonjour auto-discovery)

→ Full details: [Software Documentation](software.md) · [WLED WLAN Support](wled-wlan-support.md)

---

## Architecture

For a detailed architecture overview, component breakdown, and communication protocol documentation, see [Architecture Overview](architecture.md).

---

## Support the Project

BusyLight is free and open-source. If it helps you protect your focus time and improve your home office boundaries, please consider supporting its development.

[![Ko-fi](https://img.shields.io/badge/Support%20on-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/dralquinta)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/dralquinta)

---

[Architecture](architecture.md) · [Hardware Setup](hardware.md) · [Software Docs](software.md) · [GitHub Repository](https://github.com/dralquinta/busy-light)
