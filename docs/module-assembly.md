# BusyLight Hardware Module Assembly Guide

**Document Version:** 1.0  
**Last Updated:** February 22, 2026  
**Skill Level Required:** Beginner-friendly (no soldering required)  
**Estimated Assembly Time:** 30-45 minutes

---

## ⚠️ Safety Warnings

**READ BEFORE STARTING:**

- Handle ESP32 with care - components are sensitive to **static electricity**
- Use only **5V DC power** (not 12V or higher voltage)
- LED brightness can be intense - **photosensitive epilepsy warning**
- Disconnect power before making any modifications
- Ensure adequate ventilation if enclosure gets warm
- Do not operate near water or in humid environments
- USB power supply must provide at least **2A continuous current**

**If you experience any of the following while viewing the LED display, stop immediately:**
- Dizziness, lightheadedness
- Altered vision, eye strain
- Involuntary muscle movements
- Disorientation or confusion

---

## Introduction

### Overview

This guide provides step-by-step instructions for assembling the BusyLight hardware module - a WiFi-enabled RGB LED matrix controlled by the macOS agent via WLED firmware. The completed device displays your presence status (Available, Busy, Away, etc.) using colorful LED patterns.

### What You'll Build

A self-contained USB-powered device featuring:
- ESP32 microcontroller with WiFi connectivity
- 8x8 WS2812 RGB LED matrix (64 addressable LEDs)
- Weatherproof enclosure for desk or wall mounting
- No external dependencies (cloud-free operation)

**[PLACEHOLDER FOR IMAGE: Completed BusyLight device on desk, showing green "Available" status]**

---

## Bill of Materials (BOM)

### Required Components

| Item | Specification | Quantity | Estimated Cost (CLP) | Purchase Link |
|------|--------------|----------|---------------------|---------------|
| ESP32 Dev Board | USB Type-C, WiFi/Bluetooth | 1 | $7,990 | [MercadoLibre](https://www.mercadolibre.cl/esp32-usb-tipo-c-wifi-bluetooth-compatible-con-arduino-ide/p/MLC2056268051) |
| WS2812 LED Matrix | 8x8, 64 LEDs, Neopixel compatible | 1 | $6,990 | [MercadoLibre](https://www.mercadolibre.cl/matriz-led-8x8-ws2812-rgb-programable-64-bits-neopixel/up/MLCU103263848) |
| Dupont Cables | Female-Female, 10cm, 40-pack | 1 pack | $1,990 | [MercadoLibre](https://www.mercadolibre.cl/cables-dupont-40u-protoboard-hembra-hembra-10cm--max-/up/MLCU18010830) |
| Enclosure Box | 100x100x62mm, waterproof, smooth | 1 | $2,290 | [MercadoLibre](https://www.mercadolibre.cl/caja-estanca-lisa-lh-100x100x62-lisa-mgc/up/MLCU18982759) |
| USB-C Cable | Data + Power, 1m minimum | 1 | $1,500 | Local electronics store |
| USB Power Adapter | 5V, 2A minimum (2.4A recommended) | 1 | $2,500 | Local electronics store |
| **Total** | | | **~$23,260 CLP** | **~$25 USD** |

**[PLACEHOLDER FOR IMAGE: All components laid out and labeled]**

### Optional Components

| Item | Purpose | Estimated Cost |
|------|---------|---------------|
| Heat shrink tubing | Cable protection and strain relief | $500 |
| Cable ties (small) | Internal cable management | $300 |
| Double-sided foam tape | Mounting components | $800 |
| M3 screws + nuts | Permanent LED matrix mounting | $400 |
| Cable grommet 8mm | Professional cable exit | $200 |

---

## Tools Required

### Essential (No-Solder Assembly)

- **None** - This assembly can be completed with no tools using Dupont cables

### Recommended

- **Phillips screwdriver** - For enclosure assembly
- **Wire cutters** - For trimming cable ties (optional)
- **Multimeter** - For testing connections (optional but helpful)

### For Enclosure Modification

- **Drill with 8-10mm bit** - For cable exit hole
- **Step drill bit** - For cleaner holes in plastic (recommended)
- **File or sandpaper** - For smoothing drilled edges
- **Measuring tape or ruler** - For marking drill locations
- **Marker or pencil** - For marking drill points

**[PLACEHOLDER FOR IMAGE: Tools laid out on workbench]**

---

## Technical Specifications

### Power Requirements

| Parameter | Specification | Notes |
|-----------|--------------|-------|
| Input Voltage | 5V DC ± 0.25V | Via USB-C |
| Minimum Current | 2A (2000mA) | For full brightness |
| Typical Current | 500-800mA | At 50% brightness |
| Maximum Current | ~3.8A | All LEDs white, 100% (theoretical) |
| Recommended PSU | 5V 2.4A | Provides headroom |

### LED Matrix Specifications

- **Part Number:** WS2812B (or compatible WS2811, SK6812)
- **Configuration:** 8x8 matrix = 64 addressable RGB LEDs
- **Voltage:** 5V DC
- **Current per LED:** ~60mA at full white (20mA × 3 colors)
- **Data Protocol:** Single-wire serial (timing-based)
- **Data Rate:** 800kHz
- **Color Depth:** 24-bit RGB (16.7 million colors)

### ESP32 GPIO Pin Assignments

| Function | Default GPIO | Alternative | Notes |
|----------|-------------|-------------|-------|
| LED Data Out | GPIO 2 | GPIO 16 | Configurable in WLED |
| LED Data | GPIO 2 | GPIO 16 | Configurable in WLED |
| Power (5V) | 5V pin | VIN pin | Either works |
| Ground (GND) | GND pin | Any GND pin | Multiple GND pins available |

**[PLACEHOLDER FOR IMAGE: ESP32 pinout diagram with pins highlighted]**

### WiFi Requirements

- **Frequency:** 2.4GHz (802.11 b/g/n)
- **Security:** WPA2-Personal or WPA3
- **Range:** Typical indoor WiFi range (~30m)
- **Protocol:** HTTP (port 80) for WLED API
- **Discovery:** mDNS/Bonjour (_http._tcp)

---

## Wiring Diagram

### Complete Connection Schematic

```
┌──────────────────┐
│     ESP32        │
│                  │
│  ┌───────────┐   │      ┌────────────────┐
│  │ USB-C Port│◄──┼──────┤ USB-C Cable    │
│  └───────────┘   │      └────────┬───────┘
│                  │               │
│   5V    ●────────┼───RED─────►  ● VCC     │
│                  │          ┌────┴────┐   │
│   GND   ●────────┼───BLACK──► ● GND  │   │
│                  │          │         │   │
│   GPIO2 ●────────┼───YELLOW─► ● DIN  │   │
│   (Data)         │          │  8x8    │   │
└──────────────────┘          │  WS2812 │   │
                               │  Matrix │   │
                               └─────────┘   │
                                             │
                              ┌──────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │ USB Power    │
                       │ Adapter 5V 2A│
                       └──────────────┘
```

### Pin Connection Table

| ESP32 Pin | Wire Color | LED Matrix Pin | Function |
|-----------|------------|----------------|----------|
| 5V | Red | VCC or 5V | Power supply |
| GND | Black | GND | Ground return |
| GPIO 2 | Yellow/Green | DIN | Data input |

**CRITICAL:** Always verify polarity before powering on! Reversed power (5V/GND) can damage components.

**[PLACEHOLDER FOR IMAGE: Detailed wiring schematic with color-coded connections]**

### Data Flow Direction

The WS2812 matrix has directional data flow:

```
    DIN ──► [Matrix] ──► DOUT
    (Input)           (Output)
```

- **DIN:** Connect to ESP32 GPIO pin
- **DOUT:** Optional chaining to additional LED strips (not used)

Look for corner arrow marking on LED matrix PCB indicating data entry point.

**[PLACEHOLDER FOR IMAGE: LED matrix corner showing DIN/DOUT arrows]**

---

## Step-by-Step Assembly Instructions

### Step 1: Prepare Workspace

**Time:** 5 minutes

1. Choose a clean, well-lit workspace
2. Use anti-static mat or touch grounded metal to discharge static
3. Lay out all components for inventory check
4. Ensure adequate lighting and ventilation
5. Have this guide accessible (printed or on second screen)

**Checklist:**
- ✅ Clean, flat surface
- ✅ Good lighting
- ✅ All components present
- ✅ Tools within reach
- ✅ Static-safe environment

**[PLACEHOLDER FOR IMAGE: Organized workspace with components labeled]**

---

### Step 2: Inspect Components

**Time:** 5 minutes

**ESP32 Inspection:**
1. Check USB-C port for damage or bent pins
2. Verify no components are loose or missing
3. Look for any shipping damage or cracks
4. Check pin headers are straight and intact

**LED Matrix Inspection:**
1. Identify corner marking showing data flow direction
2. Check for damaged LEDs (dark spots, cracks)
3. Verify 8x8 configuration (64 LEDs total)
4. Confirm three connection pads labeled: VCC, GND, DIN (or 5V, GND, DI)

**Dupont Cable Inspection:**
1. Select 3 cables from the 40-pack
2. Recommended colors:
   - Red for 5V power
   - Black for GND
   - Yellow or Green for data
3. Check connectors are not damaged or loose

**[PLACEHOLDER FOR IMAGE: ESP32 close-up showing USB-C port and pins]**

**[PLACEHOLDER FOR IMAGE: LED matrix corner marking close-up with DIN labeled]**

---

### Step 3: Connect Power Wires (5V and GND)

**Time:** 5 minutes  
**CRITICAL STEP:** Double-check polarity!

**5V Power Connection:**

1. Select **RED** Dupont cable
2. Identify **5V pin** on ESP32 (usually labeled "5V" or "VIN")
3. Connect one end of red cable to ESP32 5V pin
4. Identify **VCC** or **5V** pad on LED matrix
5. Connect other end of red cable to LED matrix VCC
6. Ensure connection is secure (gentle tug test)

**GND Ground Connection:**

1. Select **BLACK** Dupont cable
2. Identify **GND pin** on ESP32 (usually multiple GND pins available)
3. Connect one end of black cable to ESP32 GND pin
4. Identify **GND** pad on LED matrix
5. Connect other end of black cable to LED matrix GND
6. Ensure connection is secure

**Verification:**
- ✅ Red cable: ESP32 5V ↔ Matrix VCC
- ✅ Black cable: ESP32 GND ↔ Matrix GND
- ✅ No loose connections
- ✅ Correct polarity confirmed

**⚠️ WARNING:** Reversed power connection can permanently damage components!

**[PLACEHOLDER FOR IMAGE: Red power cable connected from ESP32 5V to matrix VCC]**

**[PLACEHOLDER FOR IMAGE: Black ground cable connected from ESP32 GND to matrix GND]**

---

### Step 4: Connect Data Wire

**Time:** 3 minutes

1. Select **YELLOW or GREEN** Dupont cable
2. Identify **GPIO 2** (or GPIO 16) pin on ESP32
   - Usually labeled "D2," "GPIO2," or simply "2"
   - Check ESP32 pinout diagram if unclear
3. Connect one end to ESP32 data pin (GPIO 2)
4. Identify **DIN** (Data In) pad on LED matrix
   - May be labeled "DIN," "DI," or "DATA"
   - Located at corner with directional arrow
5. Connect other end to LED matrix DIN
6. Ensure secure connection

**Data Flow Verification:**
- Data flows from ESP32 → DIN (matrix input)
- DOUT (matrix output) remains unconnected

**Verification:**
- ✅ Data cable: ESP32 GPIO2 ↔ Matrix DIN
- ✅ Correct pin identified on ESP32
- ✅ DIN pin (not DOUT) on matrix
- ✅ Secure connection

**[PLACEHOLDER FOR IMAGE: Yellow data cable connected from ESP32 GPIO2 to matrix DIN]**

**[PLACEHOLDER FOR IMAGE: Close-up of data pin connection on ESP32]**

---

### Step 5: Initial Connectivity Test (Outside Enclosure)

**Time:** 5 minutes  
**IMPORTANT:** Test BEFORE installing in enclosure!

**Visual Inspection:**

1. Triple-check all three connections:
   - Red: 5V to VCC
   - Black: GND to GND
   - Yellow/Green: GPIO2 to DIN
2. Verify no crossed wires
3. Check for secure connections (no loose Dupont connectors)

**Optional Multimeter Test:**

If you have a multimeter:

1. Set to continuity mode (beep test)
2. Test 5V continuity: ESP32 5V pin to Matrix VCC (should beep)
3. Test GND continuity: ESP32 GND to Matrix GND (should beep)
4. Test data continuity: ESP32 GPIO2 to Matrix DIN (should beep)

**Do NOT power on yet** - proceed to firmware flashing first.

**[PLACEHOLDER FOR IMAGE: Complete wired assembly outside enclosure, all three cables visible]**

**[PLACEHOLDER FOR IMAGE: Multimeter testing continuity between ESP32 and matrix]**

---

### Step 6: Flash WLED Firmware

**Time:** 10-15 minutes  
**Prerequisites:** Chrome or Edge browser, internet connection

**Detailed Flashing Process:**

1. **Connect ESP32 to computer:**
   - Use USB-C cable
   - Connect to Mac/PC USB port
   - ESP32 may show power LED when connected

2. **Open WLED Web Installer:**
   - Navigate to: https://install.wled.me/
   - Use Chrome or Microsoft Edge (Firefox/Safari not supported for web install)

3. **Click "Install" button:**
   - Large button at top of page

4. **Select device from dropdown:**
   - Choose "ESP32" (not ESP8266 or ESP8285)
   - If unsure, select "ESP32 (generic)"

5. **Click "Connect" and select serial port:**
   - Browser will show available serial ports
   - Look for entries like:
     - "usbserial-XXXX" (Mac)
     - "CP210x" or "UART" (Mac/Windows)
     - "COMx" (Windows)
   - Select the port and click "Connect"

6. **Click "Install WLED":**
   - Installer will download firmware
   - Upload progress shown (takes 1-2 minutes)
   - Do NOT disconnect during upload

7. **Wait for completion:**
   - "Installation successful" message appears
   - ESP32 will auto-reboot
   - First boot takes 20-30 seconds
   - LED matrix may show random patterns briefly

**Troubleshooting Flashing:**

- **Port not found:** Install CP210x USB driver:
  - https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers
- **Upload failed:** Try different USB cable (must be data-capable)
- **Device not detected:** Press and hold "BOOT" button on ESP32, then click "Connect"

**[PLACEHOLDER FOR IMAGE: WLED web installer page with "Install" button highlighted]**

**[PLACEHOLDER FOR IMAGE: Browser serial port selection dialog]**

**[PLACEHOLDER FOR IMAGE: Successful installation message]**

---

### Step 7: Initial WLED Configuration

**Time:** 10 minutes

**First Power-On:**

1. ESP32 creates **"WLED-AP"** WiFi network
2. Default password: **"wled1234"**
3. Browser should auto-open setup page
4. If not, navigate to: **http://4.3.2.1**

**WiFi Setup:**

1. Connect your Mac/phone to "WLED-AP" network
2. In WLED setup page, click "WiFi Setup"
3. Enter your home/office WiFi credentials:
   - **SSID:** Your network name
   - **Password:** Your WiFi password
4. Click "Save & Reboot"
5. Device disconnects from WLED-AP and connects to your WiFi
6. Note: You may need to rejoin your regular WiFi network

**Finding Device IP Address:**

Method 1: Router admin page
- Log into your router (typically 192.168.1.1)
- Look for DHCP leases or connected devices
- Find device named "WLED-XXXX" or "ESP32"

Method 2: WLE D app (iOS/Android)
- Download "WLED" app from App Store/Play Store
- App auto-discovers devices on network
- Shows IP address and device name

Method 3: Network scanner
```bash
# macOS/Linux
arp -a | grep -i esp32

# Or use nmap
nmap -sn 192.168.1.0/24 | grep -B 2 "ESP"
```

**LED Configuration:**

1. Navigate to device IP in browser: `http://192.168.1.100`
2. Click "Config" → "LED Preferences"
3. Set LED configuration:
   - **LED Count:** 64
   - **LED Type:** WS2812 RGB
   - **Data GPIO:** 2 (or 16 if using alternate pin)
   - **Color Order:** GRB (try RGB if colors wrong)
4. Click "Save"
5. Device reboots

**[PLACEHOLDER FOR IMAGE: WLED WiFi setup page with fields filled]**

**[PLACEHOLDER FOR IMAGE: WLED LED settings page showing 64 LEDs, GPIO 2]**

---

### Step 8: First Power-On Test

**Time:** 5 minutes

**Initial Test:**

1. After configuration reboot, LEDs should illuminate
2. Default: Rainbow animation or similar effect
3. **If no LEDs light up:**
   - Check GPIO pin setting (try 2 vs 16)
   - Check for power connections
   - Verify LED count = 64
   - Check color order setting

**Testing All LEDs:**

1. In WLED interface, click color picker
2. Select white (`#FFFFFF`)
3. Set brightness to 25% (to avoid glare)
4. Click solid effect
5. All 64 LEDs should glow white
6. Inspect for dead or wrong-color LEDs

**Color Order Test:**

If colors are wrong (e.g., red shows as blue):

1. Go to Config → LED Preferences
2. Try different color order settings:
   - GRB (most common for WS2812B)
   - RGB
   - BGR
3. Save and reboot after each change
4. Test with solid red, green, blue to verify

**[PLACEHOLDER FOR IMAGE: LED matrix showing white color test pattern]**

**[PLACEHOLDER FOR IMAGE: WLED interface with color picker and effect selector]**

---

### Step 9: Configure WLED Presets (6 Required)

**Time:** 15 minutes  
**CRITICAL:** All 6 presets required for full BusyLight functionality

Access device at `http://[device-ip]` and create presets:

#### Preset 1: Available (Green Solid)

1. Select color: Pure green `#00FF00`
2. Click "Effects"
3. Select: "Solid"
4. Set brightness slider: 75% (~191)
5. Speed: Not applicable
6. Intensity: Not applicable
7. Click "Save Preset" (bookmark icon)
8. Enter preset slot: **1**
9. Preset name: "Available"
10. Click "Save"

**Visual Result:** Solid bright green

#### Preset 2: Tentative (Yellow Breathe)

1. Color: Amber/Yellow `#FFA500`
2. Effect: "Breathe"
3. Brightness: 50% (~127)
4. Speed: 128 (medium)
5. Save to slot: **2**
6. Name: "Tentative"

**Visual Result:** Yellow pulsing (fades in/out)

#### Preset 3: Busy (Red Solid)

1. Color: Pure red `#FF0000`
2. Effect: "Solid"
3. Brightness: 75% (~191)
4. Save to slot: **3**
5. Name: "Busy"

**Visual Result:** Solid bright red

#### Preset 4: Away (Blue Fade)

1. Color: Blue `#0000FF`
2. Effect: "Fade"
3. Brightness: 30% (~76)
4. Speed: 128
5. Save to slot: **4**
6. Name: "Away"

**Visual Result:** Dim blue fading between levels

#### Preset 5: Unknown (White Blink)

1. Color: White `#FFFFFF`
2. Effect: "Blink"
3. Brightness: 40% (~102)
4. Speed: 100
5. Save to slot: **5**
6. Name: "Unknown"

**Visual Result:** White blinking on/off

#### Preset 6: Off (LEDs Off)

1. Click power button to turn off
2. **OR** set brightness to 0
3. Save to slot: **6**
4. Name: "Off"

**Visual Result:** All LEDs off

**Preset Verification:**

Test each preset:
1. Click preset number (1-6) in WLED interface
2. Verify correct color/effect displays
3. Confirm preset ID shown in URL or status

**[PLACEHOLDER FOR IMAGE: WLED preset configuration page with all fields]**

**[PLACEHOLDER FOR IMAGE: Grid showing all 6 presets with thumbnails]**

---

### Step 10: Test WLED JSON API

**Time:** 5 minutes  
**Purpose:** Verify macOS agent can control device

**Manual API Test (Terminal):**

```bash
# Replace 192.168.1.100 with your device IP

# Test Preset 1 (Available - Green)
curl -X POST "http://192.168.1.100/json/state" \
  -H "Content-Type: application/json" \
  -d '{"ps":1,"v":true}'

# Expected response:
# {"on":true,"bri":191,"ps":1,...}

# Test Preset 3 (Busy - Red)
curl -X POST "http://192.168.1.100/json/state" \
  -H "Content-Type: application/json" \
  -d '{"ps":3,"v":true}'

# Test all 6 presets sequentially
for i in {1..6}; do
  echo "Testing preset $i..."
  curl -s -X POST "http://192.168.1.100/json/state" \
    -H "Content-Type: application/json" \
    -d "{\"ps\":$i,\"v\":true}" | jq '.'
  sleep 2
done
```

**Expected Behavior:**
- LEDs change immediately (< 1 second)
- Response JSON shows `"ps": X` matching requested preset
- No HTTP errors (status 200)

**[PLACEHOLDER FOR IMAGE: Terminal showing successful curl command output]**

---

### Step 11: Prepare Enclosure

**Time:** 10 minutes  
**Tools:** Drill, 8-10mm bit, file/sandpaper

**Determine Cable Exit Location:**

1. Measure enclosure dimensions
2. Mark cable exit point:
   - Typically on side or bottom
   - At least 10mm from edge
   - Avoid screw post locations inside
3. Use marker or center punch for drill point

**Drilling:**

1. Secure enclosure in vise or clamp
2. Start with small pilot hole (3-4mm)
3. Step up to 8-10mm final diameter
   - 8mm: Snug fit for USB-C cable
   - 10mm: Easier routing, allows grommet
4. Drill slowly to avoid cracking plastic
5. Remove burrs with file or sandpaper
6. Test-fit USB-C cable through hole

**Optional: Install Grommet:**

1. Purchase 8mm cable grommet from hardware store
2. Press-fit into drilled hole
3. Provides strain relief and professional appearance

**Clean Enclosure:**

1. Remove all drilling debris
2. Wipe interior with dry cloth
3. Check for sharp edges

**[PLACEHOLDER FOR IMAGE: Enclosure with drill bit positioned at marked point]**

**[PLACEHOLDER FOR IMAGE: Drilled hole with grommet installed]**

**[PLACEHOLDER FOR IMAGE: USB-C cable test-fitted through hole]**

---

### Step 12: Mount LED Matrix in Enclosure

**Time:** 10 minutes

**Positioning:**

1. Orient LED matrix with corner arrow (DIN) facing preferred direction
2. Position against enclosure front (transparent or open side)
3. Center matrix in enclosure
4. Ensure Dupont cables have enough slack to reach ESP32

**Mounting Method Options:**

**Option A: Double-Sided Foam Tape (Recommended)**
- Non-permanent, easy to remove
- Use 3M VHB or similar heavy-duty tape
- Apply 4 strips at corners
- Press firmly for 30 seconds
- Allow to cure for 15 minutes before handling

**Option B: Hot Glue (Semi-Permanent)**
- Apply small dabs at 4 corners only
- Do NOT cover LEDs or circuitry
- Allow to cool completely (5 minutes)
- More effort to remove later

**Option C: M3 Screws (Permanent, Best)**
- Drill 3mm holes in enclosure matching LED matrix mounting holes
- Use M3 × 6mm screws and nuts
- Do not over-tighten (plastic can crack)
- Most secure mounting

**Alignment Verification:**

- ✅ Matrix flush against front panel
- ✅ LEDs facing outward
- ✅ Centered in enclosure
- ✅ Mounting secure (gentle shake test)
- ✅ Wires have slack (not under tension)

**[PLACEHOLDER FOR IMAGE: LED matrix with foam tape applied at corners]**

**[PLACEHOLDER FOR IMAGE: Matrix positioned inside enclosure showing centering]**

**[PLACEHOLDER FOR IMAGE: Three mounting method options side-by-side]**

---

### Step 13: Mount ESP32 in Enclosure

**Time:** 5 minutes

**Positioning Considerations:**

1. Place ESP32 away from LED matrix
   - Avoids electromagnetic interference
   - Provides clearance for heat dissipation
2. Orient USB-C port toward cable exit hole
3. Ensure status LEDs visible (if present)

**Recommended Mounting: Foam Tape**

1. Cut foam tape to fit ESP32 bottom
2. Avoid covering any components
3. Peel backing and press onto enclosure floor
4. Press ESP32 firmly onto tape
5. Hold for 30 seconds

**Alternative: Velcro Strips**

- Allows easy removal for reprogramming
- One side on enclosure, one on ESP32
- Hook side on enclosure (softer side on ESP32)

**Positioning Checklist:**

- ✅ USB-C port accessible from cable hole
- ✅ Dupont cables reach LED matrix easily
- ✅ ESP32 secure but removable if needed
- ✅ No components touching enclosure walls/lid
- ✅ Adequate airflow around ESP32

**[PLACEHOLDER FOR IMAGE: ESP32 positioned in enclosure with foam tape]**

**[PLACEHOLDER FOR IMAGE: Top view showing ESP32 and matrix placement]**

---

### Step 14: Cable Management

**Time:** 5 minutes

**Dupont Cable Routing:**

1. Route cables along enclosure edge
2. Avoid crossing cables over LED matrix face
   - Blocks light output
   - Creates shadows
3. Use gentle curves (no sharp bends)
4. Ensure no pinching when lid closes

**Optional Securing:**

- Small cable ties at enclosure mounting posts
- Small dabs of hot glue (removable)
- Double-sided tape strips

**Cable Organization:**

1. Group the 3 Dupont cables together
2. Twist gently to bundle
3. Leave 2-3cm slack at each connection
4. Route along shortest path from ESP32 to matrix

**Verification:**

- ✅ No cables blocking LEDs
- ✅ Sufficient slack at connections
- ✅ Cables won't pinch when closing enclosure
- ✅ Clean, organized appearance

**[PLACEHOLDER FOR IMAGE: Clean cable routing inside enclosure along edge]**

**[PLACEHOLDER FOR IMAGE: Cables secured with small cable tie]**

---

### Step 15: Route Power Cable

**Time:** 5 minutes

**USB-C Cable Installation:**

1. Feed USB-C cable through drilled hole from outside
2. Pull through until ~10cm slack inside enclosure
3. Leave 5-10cm slack inside (strain relief)
4. Connect to ESP32 USB-C port
5. Ensure connection is secure

**Strain Relief (Optional):**

- Loop cable inside before connecting to ESP32
- Tie small cable tie around bundle to internal anchor point
- Prevents cable pull from disconnecting ESP32

**External Cable:**

- Route cable neatly to power outlet
- Avoid foot traffic areas
- Use cable clips for permanent installations

**[PLACEHOLDER FOR IMAGE: USB-C cable threaded through enclosure hole]**

**[PLACEHOLDER FOR IMAGE: Cable connected to ESP32 with strain relief loop]**

---

### Step 16: Final Assembly Check

**Time:** 5 minutes  
**CRITICAL:** Last chance to catch issues before sealing

**Component Checklist:**

- ✅ LED matrix securely mounted
- ✅ ESP32 securely mounted
- ✅ All 3 Dupont connections secure
- ✅ USB-C cable connected to ESP32
- ✅ No components touching lid area
- ✅ Cables routed cleanly
- ✅ No pinch points

**Final Power-On Test (Before Closing):**

1. Connect USB power adapter to outlet
2. Connect USB-C cable to adapter
3. Verify ESP32 power LED illuminates
4. Check LED matrix displays default pattern
5. If issues, troubleshoot now (easier with open enclosure)

**[PLACEHOLDER FOR IMAGE: Open enclosure with all components installed, ready for test]**

---

### Step 17: Close and Seal Enclosure

**Time:** 10 minutes

**Lid Alignment:**

1. Position enclosure lid carefully
2. Ensure no cables caught between lid and body
3. Align screw holes (if waterproof enclosure)

**Securing Enclosure:**

**For Waterproof Enclosures:**
1. Insert all screws finger-tight
2. Tighten in diagonal pattern (like car lug nuts)
3. Use Phillips screwdriver
4. Tighten until snug - **do NOT over-tighten**
   - Over-tightening can crack plastic
   - Should be firm but not forcing
5. Check rubber gasket is properly seated

**For Standard Enclosures:**
1. Snap lid into place
2. Ensure all clips engaged
3. Test by gentle lifting

**Final Inspection:**

- ✅ All screws tightened evenly
- ✅ Lid flush with body
- ✅ USB-C cable exits cleanly  
- ✅ No gaps around lid (if waterproof)
- ✅ LEDs visible through front

**[PLACEHOLDER FOR IMAGE: Closing enclosure lid, screws visible]**

**[PLACEHOLDER FOR IMAGE: Completed closed enclosure, front view]**

**[PLACEHOLDER FOR IMAGE: Completed closed enclosure, rear view showing cable]**

---

### Step 18: Final Positioning and Testing

**Time:** 10 minutes

**Device Placement:**

Choose location with:
- Good WiFi signal strength
- Visible from your desk/workspace
- Safe from spills or impacts
- Near power outlet
- Not blocking ventilation (back of enclosure)

**Mounting Options:**

**Desk Placement:**
- Place on flat surface
- Use rubber feet or foam pads to prevent sliding
- Angle slightly upward for better visibility (optional riser)

**Wall Mounting:**
- Use Command strips or mounting tape
- Ensure adequate weight rating (device ~200g)
- Position at eye level when seated
- Allow clearance for cable

**Monitor Mounting:**
- Attach to monitor bezel with double-sided tape
- Position at top or side of display
- Ensure doesn't block screen content

**Final Test Sequence:**

1. **Power Test:**
   - Connect to power
   - Verify ESP32 and LED power
   - Check for unusual sounds/smells/heat

2. **WiFi Test:**
   - Verify device on network (ping IP address)
   - Access WLED web interface

3. **Preset Test:**
   - Manually activate each of 6 presets
   - Verify colors/effects correct

4. **Agent Test** (See [Testing Documentation](module-testing.md)):
   - Configure macOS agent
   - Test state changes via hotkeys
   - Verify device responds < 500ms

**[PLACEHOLDER FOR IMAGE: Completed device on desk next to computer]**

**[PLACEHOLDER FOR IMAGE: Device mounted to monitor bezel]**

**[PLACEHOLDER FOR IMAGE: Device showing "Available" green display in operational location]**

---

## Device Information Recording

**Print this label or write on enclosure:**

```
─────────────────────────────────────
 BUSYLIGHT DEVICE INFO
─────────────────────────────────────
 Device Name: ___________________
 IP Address:  ___________________
 MAC Address: ___________________
 WLED Version: __________________
 Assembled:   ___________________
 Location:    ___________________
─────────────────────────────────────
```

**How to Find:**
- IP: Router DHCP page or WLED app
- MAC: WLED web interface → Info
- Version: WLED web interface → Info

**[PLACEHOLDER FOR IMAGE: Example of device label on enclosure]**

---

## Integration with macOS Agent

### Agent Configuration

```bash
# Configure device IP
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100"

# Configure presets
defaults write com.busylight.agent app.wled_preset_available -int 1
defaults write com.busylight.agent app.wled_preset_tentative -int 2
defaults write com.busylight.agent app.wled_preset_busy -int 3
defaults write com.busylight.agent app.wled_preset_away -int 4
defaults write com.busylight.agent app.wled_preset_unknown -int 5
defaults write com.busylight.agent app.wled_preset_off -int 6

# Enable discovery (optional)
defaults write com.busylight.agent app.wled_enable_discovery -bool true
```

### Quick Test

1. Launch BusyLight.app
2. Press Ctrl+Cmd+1 (Available)
3. Verify device shows green
4. Press Ctrl+Cmd+3 (Busy)
5. Verify device shows red

### Comprehensive Testing

See [Testing Documentation](module-testing.md) for full test suite covering:
- All 6 presence states
- Multi-device scenarios
- Connection resilience
- Performance verification

---

## Troubleshooting

### LEDs Don't Light Up

**Check Power:**
```bash
# Measure voltage at LED matrix with multimeter
# Should read ~5V between VCC and GND
```

**Solutions:**
1. Verify USB power supply provides 2A minimum
2. Test different USB cable (must be data-grade, not charge-only)
3. Check Dupont connections are secure:
   - Red: ESP32 5V ↔ Matrix VCC
   - Black: ESP32 GND ↔ Matrix GND
4. Try alternate ESP32 5V pin (some boards have multiple)
5. Check matrix for visible damage

### Wrong Colors or Corrupted Display

**Symptoms:** Colors inverted (red shows as blue) or random patterns

**Solutions:**

1. **Adjust color order:**
   - WLED → Config → LED Preferences
   - Try: GRB, RGB, BGR
   - Save and reboot after each test

2. **Check GPIO pin:**
   - Verify configured pin matches physical connection
   - Try GPIO 2 vs GPIO 16

3. **Data wire quality:**
   - Replace Dupont cable with fresh one
   - Keep data wire < 15cm if possible
   - Some matrices need stronger signal

4. **Level shifter** (advanced):
   - ESP32 outputs 3.3V, WS2812 expects 5V data
   - Usually works, but some matrices are picky
   - Add 74HCT125 level shifter if issues persist

### WiFi Connection Issues

**Symptoms:** Device not joining network or frequently disconnecting

**Solutions:**

1. **Check frequency:**
   - ESP32 only supports 2.4GHz
   - Disable "Band Steering" on router
   - Set 2.4GHz and 5GHz to different SSIDs

2. **Improve signal:**
   - Move device closer to router
   - Check WiFi signal in WLED interface
   - Relocate router or add WiFi extender

3. **Network settings:**
   - Ensure WPA2 security (not WPA3-only)
   - Check MAC filtering not blocking device
   - Verify DHCP enabled

4. **Static IP** (recommended):
   - Set static IP in router DHCP reservation
   - Prevents IP changes after reboot

### Random Flickering

**Symptoms:** LEDs flicker or show brief wrong colors

**Solutions:**

1. **Power supply:**
   - Upgrade to 2.4A or 3A adapter
   - Test with powered USB hub
   - Check for voltage drop with multimeter

2. **Connections:**
   - Reseat all Dupont cables
   - Check for intermittent connection (wiggle test)
   - Replace suspect cables

3. **USB cable:**
   - Use short, thick  USB cable (20AWG or better)
   - Avoid thin charge-only cables
   - Try different cable if available

4. **Capacitor** (advanced):
   - Add 1000µF capacitor across matrix power pins
   - Smooths voltage spikes
   - Solder or use breadboard-friendly cap

### Device Not Discoverable

**Symptoms:** macOS agent shows "Devices: None configured"

**Solutions:**

1. **Network verification:**
   ```bash
   ping 192.168.1.100
   # Should respond
   ```

2. **mDNS test:**
   ```bash
   dns-sd -B _http._tcp.
   # Should show WLED device
   ```

3. **Manual configuration:**
   ```bash
   defaults write com.busylight.agent app.device_network_addresses \
     -array "192.168.1.100"
   ```

4. **Firewall:**
   - System Settings → Network → Firewall
   - Add BusyLight.app to allowed list
   - Or temporarily disable for testing

5. **VLAN isolation:**
   - Check router settings
   - Ensure Mac and ESP32 on same subnet
   - Disable client isolation on WiFi

### Presets Don't Activate

**Symptoms:** Agent sends commands but LEDs don't change

**Solutions:**

1. **Test presets manually:**
   - Open WLED web interface
   - Click preset numbers 1-6
   - If manual works, issue is agent configuration

2. **Verify JSON API:**
   ```bash
   curl -X POST "http://192.168.1.100/json/state" \
     -H "Content-Type: application/json" \
     -d '{"ps":1,"v":true}'
   ```

3. **Check preset IDs:**
   - Presets must exist in slots 1-6
   - Re-save if missing
   - Verify with: `curl http://192.168.1.100/json/state`

4. **Agent configuration:**
   ```bash
   defaults read com.busylight.agent | grep wled_preset
   # Should show 1-6 for each state
   ```

### Excessive Heat

**Symptoms:** Enclosure warm to touch, ESP32 hot

**Solutions:**

1. **Reduce brightness:**
   - Lower preset brightness to 50%
   - Full white at 100% draws max current

2. **Improve ventilation:**
   - Drill small ventilation holes in enclosure
   - Don't cover device with objects
   - Position with open space around it

3. **Check power consumption:**
   - Measure current with USB multimeter
   - Should be < 1A typical, < 2A max
   - If higher, check for shorts

4. **Normal operation:**
   - ESP32 operating temp: up to 85°C
   - Warm is normal, hot-to-touch is concern
   - LEDs generate heat proportional to brightness

---

## Maintenance and Care

### Regular Maintenance

**Monthly:**
- Wipe enclosure with dry cloth
- Check WiFi connectivity
- Verify all presets still work
- Test agent communication

**Every 6 Months:**
- Check Dupont connections (reseat if loose)
- Inspect USB cable for damage
- Review WLED firmware updates
- Clean dust from ventilation areas

### Cleaning

**Enclosure Exterior:**
- Dry microfiber cloth
- Slightly damp cloth for stubborn dirt
- Avoid: Window cleaner, alcohol, solvents

**Do NOT:**
- Spray liquids directly on device
- Use abrasive cleaners
- Submerge in water (even if "waterproof" enclosure)

### Firmware Updates

**WLED OTA Update:**

1. Access WLED web interface
2. Click "Update" → "Manual OTA Update"
3. Upload new `.bin` file from wled.me
4. Wait for upload and reboot
5. Reconfigure LED settings if needed
6. Re-test all 6 presets

**Backup Before Updating:**

1. WLED → Config → Security & Updates
2. Click "Backup Configuration"
3. Save JSON file to computer
4. Restore if update causes issues

### LED Longevity

**Factors Affecting LED Lifespan:**
- **Brightness:** Higher = shorter life
- **Color:** White uses all 3 LEDs (more wear)
- **Temperature:** Cooler = longer life

**Recommendations:**
- Use 50-75% brightness (not 100%)
- Colored states wear less than white
- Ensure adequate ventilation
- Expected life: 30,000-50,000 hours at 50% brightness

---

## Advanced Modifications (Optional)

### Adding External Power Button

**Purpose:** Physical power toggle without web interface

**Components Needed:**
- Momentary push button
- 2× Dupont wires
- GPIO input pin on ESP32

**Implementation:**
1. Connect button between GPIO pin and GND
2. Configure in WLED: Config → LED Preferences → Button Setup
3. Set button action to "Preset cycle" or "On/Off toggle"

### Installing Larger Matrix

**16x16 Matrix (256 LEDs):**
- Requires 5V 4A power supply minimum
- Update LED count in WLED: 256
- Larger enclosure required
- More complex wiring

### Multiple Device Synchronization

**WLED UDP Sync:**
1. Enable in WLED Config → Sync Interfaces
2. Set all devices to same UDP port (21324)
3. Designate one as "Send" and others as "Receive"
4. Changes sync across all devices automatically

### Custom 3D-Printed Diffuser

**Purpose:** Soften LED light, blend colors

**Design Requirements:**
- Fits inside enclosure front
- 2-3mm thick translucent plastic
- Diffusion pattern (cross-hatch or stipple)

**Materials:**
- White PLA or PETG
- Translucent filament (50-70% opacity)

### Battery Pack for Portable Operation

**Components:**
- 5V USB power bank (10,000mAh)
- USB-C to USB-C cable
- Velcro or bracket for mounting

**Runtime:**
- At 50% brightness: ~10-15 hours
- At 100% brightness: ~3-5 hours
- Power bank provides isolation from power surges

---

## Appendices

### Appendix A: ESP32 Pinout Reference

**Common ESP32 DevKit Pinout:**

```
            ┌─────────────┐
            │   USB-C     │
            └──────┬──────┘
                   │
    GND  ●─────────┼─────────● 3.3V
    GPIO36 (SVP) ●─┼─────────● EN
    GPIO39 (SVN) ●─┼─────────● GPIO23
    GPIO34 ●───────┼─────────● GPIO22
    GPIO35 ●───────┼─────────● TX0
    GPIO32 ●───────┼─────────● RX0
    GPIO33 ●───────┼─────────● GPIO21
    GPIO25 ●───────┼─────────● GND
    GPIO26 ●───────┼─────────● GPIO19
    GPIO27 ●───────┼─────────● GPIO18
    GPIO14 ●───────┼─────────● GPIO5
    GPIO12 ●───────┼─────────● GPIO17
    GND ●──────────┼─────────● GPIO16 (RX2)
    GPIO13 ●───────┼─────────● GPIO4
    SCK/GPIO14 ●───┼─────────● GPIO0
    MISO/GPIO12 ●──┼─────────● GPIO2 ◄── Use this for LED data
    MOSI/GPIO13 ●──┼─────────● GPIO15
    CS/GPIO15 ●────┼─────────● 5V (VIN) ◄── Power output
    GND ●──────────┘         ● GND ◄── Ground
```

**[PLACEHOLDER FOR IMAGE: Detailed ESP32 pinout diagram]**

### Appendix B: WS2812 LED Matrix Pinout

**8x8 Matrix Connection Pads:**

```
┌─────────────────┐
│  LED Matrix PCB │
│                 │
│  VCC/5V ●───────┼── Red wire to ESP32 5V
│  GND    ●───────┼── Black wire to ESP32 GND  
│  DIN/DI ●───────┼── Yellow wire to ESP32 GPIO2
│  (DOUT) ●       │    (Optional chaining output)
│                 │
│    ┌─ Arrow     │    ◄── Data flow direction
│    └► indicates │
│       data entry│
└─────────────────┘
```

**[PLACEHOLDER FOR IMAGE: WS2812 matrix pinout close-up photo]**

### Appendix C: WLED Default Configuration

**Factory Default Settings:**

```
LED Configuration:
- Count: 30 (must change to 64)
- GPIO: 2
- Color Order: GRB
- Type: WS2812 RGB

Network:
- AP SSID: WLED-AP
- AP Password: wled1234
- DHCP: Enabled

Effects:
- Default: Rainbow
- Speed: 128
- Intensity: 128
```

### Appendix D: Bill of Materials with SKUs

| Component | Vendor | SKU/Product Code | Unit Price | Notes |
|-----------|--------|------------------|------------|-------|
| ESP32 Type-C | MercadoLibre | MLC2056268051 | $7,990 | Generic ESP32-DevKitC-32D |
| WS2812 8x8 Matrix | MercadoLibre | MLCU103263848 | $6,990 | 64-LED addressable matrix |
| Dupont Cables 40pc | MercadoLibre | MLCU18010830 | $1,990 | Female-female 10cm |
| Enclosure 100mm | MercadoLibre | MLCU18982759 | $2,290 | Waterproof IP65 |
| USB-C Cable 1m | Local | Various | $1,500 | Data-capable required |
| USB Adapter 5V 2A | Local | Various | $2,500 | UL/CE certified recommended |

### Appendix E: Wiring Color Code Standard

**Recommended Dupont Cable Colors:**

| Function | Primary Color | Alternative | Rationale |
|----------|--------------|-------------|-----------|
| Power (+5V) | Red | Orange | Universal positive |
| Ground (GND) | Black | Brown | Universal ground |
| Data Signal | Yellow | Green, White | Signal/logic convention |

**Standard Helps With:**
- Troubleshooting (color-coded connections)
- Documentation photography
- Multi-device consistency
- Reducing errors during assembly

---

## PDF Conversion Instructions

**This document is authored in Markdown format.**

To convert to PDF for printing or distribution:

**Using Pandoc (Recommended):**

```bash
# Install pandoc
brew install pandoc

# Install LaTeX (for PDF engine)
brew install --cask mactex-no-gui

# Convert to PDF
pandoc module-assembly.md \
  -o module-assembly.pdf \
  --pdf-engine=xelatex \
  -V geometry:margin=1in \
  -V fontsize=11pt \
  --toc \
  --toc-depth=2

# With fancy styling
pandoc module-assembly.md \
  -o module-assembly.pdf \
  --pdf-engine=xelatex \
  -V geometry:margin=0.75in \
  -V fontsize=10pt \
  -V colorlinks=true \
  -V linkcolor=blue \
  -V urlcolor=blue \
  --toc \
  --template=eisvogel \
  --listings
```

**Using Online Converter:**
- https://md2pdf.netlify.app/
- https://www.markdowntopdf.com/

**Using VS Code:**
- Install "Markdown PDF" extension
- Open this file
- Right-click → "Markdown PDF: Export (pdf)"

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-22 | BusyLight Team | Initial comprehensive assembly guide with 18 detailed steps and 40+ image placeholders |

---

## Document Status

- **Status:** ✅ Complete (awaiting photography)
- **Images:** 📷 40+ placeholders marked [PLACEHOLDER FOR IMAGE]
- **Maintainer:** BusyLight Development Team
- **Last Review:** February 22, 2026
- **Next Review:** When images added (TBD)

---

## Photography Checklist

For future image capture sessions:

### Required Photos (Priority Order):

**Setup & Components (5 photos):**
- [ ] All components laid out and labeled
- [ ] Organized workspace ready for assembly
- [ ] Tool collection display
- [ ] Completed device in operational location
- [ ] Device mounted on monitor/desk in use

**ESP32 & Wiring (8 photos):**
- [ ] ESP32 pinout diagram (annotated)
- [ ] ESP32 close-up showing USB-C and pins
- [ ] Power cable connection (red, ESP32 5V to matrix VCC)
- [ ] Ground cable connection (black, ESP32 GND to matrix GND)
- [ ] Data cable connection (yellow, ESP32 GPIO2 to matrix DIN)
- [ ] Complete wired assembly outside enclosure
- [ ] Multimeter testing continuity
- [ ] Wiring schematic diagram (illustrated)

**LED Matrix (6 photos):**
- [ ] LED matrix corner marking close-up (DIN arrow)
- [ ] Matrix pinout showing VCC, GND, DIN pads
- [ ] Matrix with foam tape applied
- [ ] Matrix mounted inside enclosure
- [ ] Matrix showing white test pattern
- [ ] All 6 presets displayed (grid layout)

**WLED Software (5 photos):**
- [ ] WLED web installer screenshot
- [ ] Browser serial port selection dialog
- [ ] WiFi setup page with fields filled
- [ ] LED configuration page (64 LEDs, GPIO 2)
- [ ] Preset configuration page

**Enclosure Work (7 photos):**
- [ ] Enclosure drilling operation
- [ ] Drilled hole with grommet installed
- [ ] USB cable test-fit through hole
- [ ] Open enclosure with all components pre-install
- [ ] ESP32 mounting with foam tape
- [ ] Cable routing inside enclosure
- [ ] Closing enclosure lid

**Testing & Final (9 photos):**
- [ ] Terminal showing successful curl command
- [ ] Available (green) state displayed
- [ ] Busy (red) state displayed
- [ ] Away (blue) state displayed
- [ ] Device label example
- [ ] Front view of closed enclosure
- [ ] Rear view showing cable exit
- [ ] Side view showing thickness
- [ ] Device in operational desk location

**Total:** 40 photos needed

---

**READY FOR DISTRIBUTION**

This assembly guide is complete and ready for use. Images can be added incrementally as they become available without affecting the document's usability.
