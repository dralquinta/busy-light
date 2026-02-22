# WLED Network Module Testing Guide

**Version:** 1.0  
**Last Updated:** February 22, 2026  
**Target Platform:** macOS 14+ (Tahoe)

## Overview

This document provides comprehensive testing procedures for the BusyLight WLED network module. The testing covers all 6 presence states, multi-device scenarios, connection resilience, and edge cases.

### Purpose

- Validate WLED HTTP JSON API integration
- Verify preset activation for all presence states
- Test multi-device broadcasting functionality
- Validate health monitoring and automatic recovery
- Ensure Bonjour/mDNS discovery works correctly

### Prerequisites

- macOS 14+ with Xcode Command Line Tools installed
- ESP32 device with WLED firmware flashed
- Network access (same LAN/VLAN as test devices)
- Basic understanding of Terminal commands
- BusyLight macOS agent built from source

## Test Environment Setup

### Hardware Requirements

- **Test Mac**: macOS 14+ (Tahoe or newer)
- **WLED Device(s)**: 1-3 ESP32 devices with WS2812 LED matrix
- **Network**: 2.4GHz WiFi network (ESP32 doesn't support 5GHz)
- **Power**: USB power adapters (5V, 2A minimum)

### Software Requirements

```bash
# Clone repository
git checkout 9-wled-http-communication-layer
cd /Users/dralquinta/Documents/DevOps/busy-light

# Build agent
./build.sh

# Verify build
ls -lh BusyLight.app
```

### Network Topology

```
┌─────────────┐
│   Router    │
│  192.168.1.1│
└──────┬──────┘
       │
   ┌───┴────┬────────┬────────┐
   │        │        │        │
┌──▼──┐  ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
│ Mac │  │WLED1│  │WLED2│  │WLED3│
│Test │  │ :100│  │ :101│  │ :102│
└─────┘  └─────┘  └─────┘  └─────┘
```

**Requirements:**
- All devices on same subnet
- No VLAN isolation between Mac and WLED devices
- Firewall allows HTTP port 80 traffic
- mDNS/Bonjour not blocked by router

### WLED Firmware Installation

1. Navigate to https://install.wled.me/ in Chrome/Edge
2. Connect ESP32 via USB-C cable
3. Click "Install" → Select "WLED 0.15.0" or latest stable
4. Choose "ESP32" from board dropdown
5. Click "Install" and wait for completion (2-3 minutes)
6. Device creates "WLED-AP" WiFi network on first boot

### Initial WLED Configuration

For each WLED device:

```
1. Connect to "WLED-AP" WiFi (password: wled1234)
2. Browser opens automatically to setup page (or navigate to 4.3.2.1)
3. Enter your WiFi credentials
4. Configure LED settings:
   - LED Count: 64 (for 8x8 matrix)
   - LED Type: WS2812B
   - Data GPIO: 2 (or 16, depending on wiring)
   - Color Order: GRB (typical)
5. Click "Save & Reboot"
6. Note device IP address from router DHCP table
```

## Preset Configuration

### Accessing WLED Web Interface

```bash
# Find your WLED device IP
# Option 1: Check router DHCP leases
# Option 2: Use WLED mobile app
# Option 3: Use nmap to scan network

# Access web interface
open http://192.168.1.100
```

### Creating All 6 Required Presets

#### Preset 1: Available (Green Solid)

1. In WLED interface, select color picker
2. Set color to pure green: `#00FF00` or RGB(0, 255, 0)
3. Set effect: "Solid"
4. Set brightness: 75% (191)
5. Click "Save Preset"
6. Enter slot: **1**
7. Name: "Available"
8. Click "Save"

#### Preset 2: Tentative (Yellow Breathe)

1. Set color: Yellow/Amber `#FFA500` or RGB(255, 165, 0)
2. Set effect: "Breathe"
3. Set speed: 128 (medium)
4. Set brightness: 50% (127)
5. Save to slot: **2**
6. Name: "Tentative"

#### Preset 3: Busy (Red Solid)

1. Set color: Pure red `#FF0000` or RGB(255, 0, 0)
2. Set effect: "Solid"
3. Set brightness: 75% (191)
4. Save to slot: **3**
5. Name: "Busy"

#### Preset 4: Away (Blue Fade)

1. Set color: Blue `#0000FF` or RGB(0, 0, 255)
2. Set effect: "Fade"
3. Set speed: 128
4. Set brightness: 30% (76)
5. Save to slot: **4**
6. Name: "Away"

#### Preset 5: Unknown (White Blink)

1. Set color: White `#FFFFFF` or RGB(255, 255, 255)
2. Set effect: "Blink"
3. Set speed: 100
4. Set brightness: 40% (102)
5. Save to slot: **5**
6. Name: "Unknown"

#### Preset 6: Off (LEDs Off)

1. Turn off light (click power button)
2. Set brightness: 0%
3. Save to slot: **6**
4. Name: "Off"

### Verifying Presets

Test each preset manually in WLED interface:

```bash
# Via curl (replace IP with your device)
curl -X POST "http://192.168.1.100/json/state" \
  -H "Content-Type: application/json" \
  -d '{"ps":1,"v":true}'

# Verify response shows correct preset
# Expected: {"on":true,"bri":191,"ps":1,...}
```

Test all 6 presets (1-6) to ensure they work correctly.

## Agent Configuration

### Configure Preset IDs

```bash
# Set WLED preset mappings
defaults write com.busylight.agent app.wled_preset_available -int 1
defaults write com.busylight.agent app.wled_preset_tentative -int 2
defaults write com.busylight.agent app.wled_preset_busy -int 3
defaults write com.busylight.agent app.wled_preset_away -int 4
defaults write com.busylight.agent app.wled_preset_unknown -int 5
defaults write com.busylight.agent app.wled_preset_off -int 6
```

### Configure Network

```bash
# Option 1: Enable discovery (recommended)
defaults write com.busylight.agent app.wled_enable_discovery -bool true

# Option 2: Manual IP configuration
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100"

# Option 3: Multiple devices
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100" "192.168.1.101" "192.168.1.102"

# Configure port (optional, default is 80)
defaults write com.busylight.agent app.device_network_port -int 80

# Configure timeouts
defaults write com.busylight.agent app.wled_http_timeout -int 500
defaults write com.busylight.agent app.wled_health_check_interval -int 10
```

### Launch Agent

```bash
# From build directory
cd /Users/dralquinta/Documents/DevOps/busy-light
open BusyLight.app

# Check menu bar for BusyLight icon
# Initial device status should show "Devices: X online"
```

## Test Cases

---

### Test Case 1: Available Preset Activation

**Objective:** Verify preset 1 (Available - Green) activates correctly.

**Preconditions:**
- Agent running and device(s) online
- Preset 1 configured as described above

**Test Steps:**

1. Press hotkey: **Ctrl+Cmd+1**
2. Observe LED matrix immediately
3. Check menu bar status
4. Verify logs

**Expected Results:**
- ✅ LED matrix displays solid green color
- ✅ Brightness at 75%
- ✅ Menu bar shows "Available" status
- ✅ Device status: "Devices: 1 online ●"

**Log Verification:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' --level debug
```

Expected log entries:
```
network_client.send_state [state=available preset=1 device_count=1]
http.post.state.success [address=192.168.1.100 port=80 preset=1 latency_ms=125]
network_client.send.success [device=WLED-Office preset=1 state=available response_preset=1 device_on=true]
```

**Pass Criteria:**
- Preset activates within 500ms
- HTTP response confirms ps=1
- No errors logged
- Visual matches expected color/brightness

---

### Test Case 2: Tentative Preset Activation

**Objective:** Verify preset 2 (Tentative - Yellow Breathe) with calendar trigger.

**Preconditions:**
- Calendar permission granted
- Tentative calendar event created

**Test Steps:**

1. Create calendar event:
   - Title: "Team Sync (Tentative)"
   - Time: Current time + 1 minute to now + 30 minutes
   - Status: **Tentative** (not confirmed)
2. Wait for agent to detect event (automatic scan)
3. Observe LED matrix
4. Verify no redundant requests sent

**Expected Results:**
- ✅ LED matrix displays yellow/amber color
- ✅ Breathing effect visible
- ✅ Menu bar shows "Tentative ●"
- ✅ Calendar status: "Tentative ●"

**Deduplication Verification:**

```bash
# Trigger manual calendar scan multiple times
# Click menu bar → "Scan Calendars Now" × 3

# Check logs - should see deduplication
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "duplicate"
```

Expected: `network_client.send.skipped.duplicate [device=WLED-Office preset=2]`

**Pass Criteria:**
- Single HTTP request sent initially
- Subsequent scans skip sending (deduplicated)
- LED breathes smoothly without flicker

---

### Test Case 3: Busy Preset Activation

**Objective:** Verify preset 3 (Busy - Red Solid) via hotkey.

**Preconditions:**
- Agent in any state except busy

**Test Steps:**

1. Press hotkey: **Ctrl+Cmd+3**
2. Measure response time (stopwatch or feel)
3. Observe LED matrix
4. Check transition smoothness

**Expected Results:**
- ✅ LED matrix displays solid red
- ✅ Transition within 500ms
- ✅ Menu bar shows "Busy"
- ✅ State persists for 30 minutes (manual override timeout)

**Latency Measurement:**

```bash
# Monitor latency in logs
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "latency_ms"
```

Expected: `http.post.state.success [...latency_ms=120]` (< 500ms)

**Pass Criteria:**
- Response time < 500ms
- Solid red color at 75% brightness
- Manual override expires after 30 minutes

---

### Test Case 4: Away Preset Activation

**Objective:** Verify preset 4 (Away - Blue Fade) via system trigger.

**Preconditions:**
- Agent running with system monitor active

**Test Steps:**

1. Lock Mac screen (Ctrl+Cmd+Q)
2. Wait 5 seconds
3. Observe LED matrix
4. Unlock screen
5. Observe state returns to previous (Available/Busy/etc.)

**Expected Results:**
- ✅ LED matrix displays blue color
- ✅ Fade effect active
- ✅ Brightness at 30% (dimmer for away)
- ✅ Menu bar shows "Away"
- ✅ Returns to previous state on unlock

**System Event Verification:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent"' | grep "system"
```

Expected:
```
system.presence.away [screen_locked=true]
network_client.send_state [state=away preset=4]
system.presence.returned
network_client.send_state [state=available preset=1]
```

**Pass Criteria:**
- Away state activates on screen lock
- Previous state restored on unlock
- No manual intervention required

---

### Test Case 5: Unknown Preset Activation

**Objective:** Verify preset 5 (Unknown - White Blink) on startup.

**Preconditions:**
- Agent not running
- No calendar events (or permission denied)

**Test Steps:**

1. Quit BusyLight.app if running
2. Delete calendar authorization:
   ```bash
   tccutil reset Calendar com.busylight.agent
   ```
3. Launch BusyLight.app
4. Observe initial LED state
5. Deny calendar permission when prompted

**Expected Results:**
- ✅ LED matrix displays white color
- ✅ Blink effect visible
- ✅ Menu bar shows "Unknown"
- ✅ Calendar status: "Permission denied"

**Initialization Sequence:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent"' | grep "initialize"
```

Expected:
```
state.machine.initialize [initial_state=unknown]
network_client.send_state [state=unknown preset=5]
```

**Pass Criteria:**
- Unknown state shown immediately on launch
- White blinking visible
- Transitions to Available once calendar permission granted

---

### Test Case 6: Off Preset Activation

**Objective:** Verify preset 6 (Off - LEDs Off) via operating mode.

**Preconditions:**
- Agent running in any state

**Test Steps:**

1. Click menu bar icon
2. Select "Turn Off" (or press Ctrl+Cmd+5)
3. Observe LED matrix turns completely off
4. Verify state persists across app restarts
5. Resume with Ctrl+Cmd+4

**Expected Results:**
- ✅ All LEDs turn off immediately
- ✅ Menu bar shows "Off"
- ✅ Calendar scanning disabled
- ✅ Hotkeys still responsive
- ✅ Resume returns to previous calendar-driven state

**Persistence Verification:**

```bash
# Check saved state
defaults read com.busylight.agent app.presence_state

# Should show: "off"

# Restart agent
killall BusyLight
open BusyLight.app

# Verify LEDs remain off after restart
```

**Pass Criteria:**
- LEDs turn completely off (no residual glow)
- State persists across restarts
- Resume function works correctly

---

### Test Case 7: Connection Resilience

**Objective:** Verify offline detection and automatic recovery.

**Preconditions:**
- Agent running with 1+ devices online

**Test Steps:**

1. Note current online device count
2. Physically disconnect WLED device WiFi:
   - Unplug power, or
   - Navigate to WLED → WiFi Settings → Disconnect
3. Wait 10-15 seconds
4. Check menu bar device status
5. Reconnect device
6. Wait for automatic recovery (10-20 seconds)
7. Verify state re-synchronized

**Expected Results:**
- ✅ Offline detected within 10-15 seconds
- ✅ Menu bar updates: "Devices: 0 online, 1 offline"
- ✅ Agent continues operating normally
- ✅ Automatic reconnection within 10-20 seconds
- ✅ Current state re-sent to device immediately

**Health Check Monitoring:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "health"
```

Expected sequence:
```
network_client.health.check [device_count=1]
network_client.health.transition [device=WLED-Office transition=online→offline]
# Wait 10 seconds
network_client.health.transition [device=WLED-Office transition=offline→online]
network_client.send_state [state=busy preset=3]  # Re-sync current state
```

**Pass Criteria:**
- Offline detection within 15 seconds
- No crashes or errors
- Automatic recovery without user intervention
- State synchronized immediately after recovery

---

### Test Case 8: Multi-Device Broadcasting

**Objective:** Verify simultaneous control of multiple WLED devices.

**Preconditions:**
- 2+ WLED devices configured and online
- Both configured in agent

**Test Steps:**

1. Configure multiple devices:
   ```bash
   defaults write com.busylight.agent app.device_network_addresses \
     -array "192.168.1.100" "192.168.1.101"
   ```
2. Restart agent
3. Verify menu bar shows: "Devices: 2 online ●"
4. Press Ctrl+Cmd+1 (Available)
5. Observe **both** LED matrices simultaneously
6. Check logs for parallel execution

**Expected Results:**
- ✅ Both devices change to green simultaneously
- ✅ Menu bar shows: "Devices: 2 online ●"
- ✅ Tooltip shows individual device details
- ✅ No sequential delay between devices

**Parallel Execution Verification:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' > /tmp/network.log &
# Press hotkey
sleep 2
killall log

# Check timestamps - should be within ~50ms
grep "http.post.state.success" /tmp/network.log
```

Expected: Both requests logged with nearly identical timestamps (parallel execution confirmed).

**Individual Status Tracking:**

Hover over "Devices: 2 online" in menu bar:

```
WLED Devices:
  ● WLED-Office (192.168.1.100:80)
  ● WLED-Desk (192.168.1.101:80)
```

**Pass Criteria:**
- Both devices activate simultaneously (< 50ms difference)
- Individual device status tracked
- Tooltip shows per-device details

---

### Test Case 9: Full State Transition Cycle

**Objective:** Verify all 6 states transition correctly in sequence.

**Preconditions:**
- Agent running with calendar access
- All 6 presets configured

**Test Steps:**

1. **Available** → Press Ctrl+Cmd+1
   - Verify: Green solid
2. **Tentative** → Create tentative event
   - Verify: Yellow breathe
3. **Busy** → Press Ctrl+Cmd+3
   - Verify: Red solid  
4. **Away** → Lock screen
   - Verify: Blue fade
5. Unlock screen → Returns to Busy (manual override active)
6. **Off** → Press Ctrl+Cmd+5
   - Verify: LEDs off
7. **Resume** → Press Ctrl+Cmd+4
   - Verify: Returns to calendar-driven state
8. Delete calendar events → **Unknown**
   - Verify: White blink

**Expected Results:**
- ✅ All 6 states activate correctly
- ✅ No skipped transitions
- ✅ No double-activations
- ✅ Smooth transitions without errors

**Deduplication Check:**

```bash
# Count unique HTTP requests sent
log stream --predicate 'subsystem == "com.busylight.agent.network"' | \
  grep "http.post.state.success" | wc -l
```

Expected: Exactly 8 requests (one per transition, no duplicates).

**Pass Criteria:**
- All 6 states visually confirmed
- Transitions occur within 500ms each
- No redundant HTTP requests
- Logs show clean state machine progression

---

### Test Case 10: Discovery and Fallback

**Objective:** Verify Bonjour/mDNS discovery and manual IP fallback.

**Preconditions:**
- Fresh agent installation
- WLED device on network

**Test Steps:**

**Part A: Bonjour Discovery**

1. Enable discovery:
   ```bash
   defaults write com.busylight.agent app.wled_enable_discovery -bool true
   defaults delete com.busylight.agent app.device_network_addresses
   ```
2. Launch agent
3. Wait 5 seconds
4. Check menu bar device count

Expected: "Devices: 1 online ●" (device auto-discovered)

**Part B: Discovery Filtering**

1. Add non-WLED HTTP service to network (e.g., Apache server)
2. Restart agent
3. Verify only WLED devices discovered

**Part C: Manual IP Fallback**

1. Disable discovery:
   ```bash
   defaults write com.busylight.agent app.wled_enable_discovery -bool false
   ```
2. Configure manual IP:
   ```bash
   defaults write com.busylight.agent app.device_network_addresses \
     -array "192.168.1.100"
   ```
3. Restart agent
4. Verify device still controlled

**Part D: Mixed Configuration**

1. Enable discovery:
   ```bash
   defaults write com.busylight.agent app.wled_enable_discovery -bool true
   ```
2. Keep manual IP configured
3. Restart agent
4. Verify both discovery and manual IPs merged (no duplicates)

**Discovery Log Verification:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "discovery"
```

Expected:
```
discovery.started [timeout=5.0]
discovery.service.found [name=WLED-Office type=_http._tcp.]
discovery.service.resolved [name=WLED-Office hostname=wled-office.local port=80]
discovery.wled.verified [name=WLED-Office address=192.168.1.100 version=0.15.0]
discovery.completed [devices_found=1]
```

**Pass Criteria:**
- Bonjour discovers WLED devices automatically
- Only WLED devices included (HTTP services filtered)
- Manual IP works when discovery disabled
- Mixed mode merges without duplicates

---

### Test Case 11: Error Handling and Retry Logic

**Objective:** Verify exponential backoff retry and error logging.

**Preconditions:**
- Agent running
- WLED device powered on

**Test Steps:**

1. Note current device state
2. During state change, **unplug device immediately**
3. Observe retry attempts in logs
4. Verify agent remains operational
5. Plug device back in
6. Verify recovery

**Expected Results:**
- ✅ 3 retry attempts logged
- ✅ Exponential backoff delays: 100ms, 200ms, 400ms
- ✅ Agent does not crash
- ✅ Error logged appropriately
- ✅ Device marked offline after retries exhausted

**Retry Log Verification:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' --level debug
```

Expected sequence:
```
http.post.state.success [device=WLED-Office preset=3]  # Initial request
# Unplug device here
network_client.send_state [state=available preset=1]    # New state change
http.request.retry [url=http://192.168.1.100/json/state attempt=1 next_delay_ms=100]
http.request.retry [url=http://192.168.1.100/json/state attempt=2 next_delay_ms=200]
http.request.retry [url=http://192.168.1.100/json/state attempt=3 next_delay_ms=400]
http.request.failed.max_retries [attempts=3 error=The operation couldn't be completed]
network_client.send.failed [device=WLED-Office error=timeout]
```

**Non-Fatal Behavior Verification:**

- Agent menu bar still responsive
- Other devices (if configured) still controlled
- Calendar scanning continues
- Hotkeys still work

**Pass Criteria:**
- Exactly 3 retry attempts
- Delays match exponential backoff (100, 200, 400 ms)
- No crashes or hangs
- Error logged with full context

---

### Test Case 12: Health Check Polling

**Objective:** Verify periodic `/json/info` polling and status updates.

**Preconditions:**
- Agent running with health check interval = 10 seconds

**Test Steps:**

1. Enable debug logging:
   ```bash
   log stream --predicate 'subsystem == "com.busylight.agent.network"' --level debug > /tmp/health.log &
   ```
2. Wait 60 seconds (6 health check cycles)
3. Stop logging
4. Analyze health check frequency

**Expected Results:**
- ✅ Health check every ~10 seconds
- ✅ Device info retrieved successfully
- ✅ Online status maintained
- ✅ Metadata updated (uptime, name, version)

**Frequency Analysis:**

```bash
grep "network_client.health.check" /tmp/health.log

# Count checks in 60 seconds
grep -c "network_client.health.check" /tmp/health.log
# Expected: 6 checks (every 10 seconds)
```

**Metadata Verification:**

```bash
grep "http.get.info.success" /tmp/health.log | tail -1
```

Expected fields: `address, port, name, version, latency_ms`

**Device Info Inspection:**

Check actual device info returned:

```bash
curl -s http://192.168.1.100/json/info | jq '.'
```

Verify agent logs match actual device data.

**Pass Criteria:**
- Health checks occur every 10 seconds (±1 second tolerance)
- All checks succeed for online device
- Device metadata accurately retrieved
- UI callback invoked on status changes only (not every poll)

---

## Diagnostic Log Verification

### Streaming Logs

**All Network Events:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' --level debug
```

**All Agent Events:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent"' --level debug
```

**Specific Event Filter:**

```bash
# Connection events only
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "connect"

# State transitions only
log stream --predicate 'subsystem == "com.busylight.agent"' | grep "state"

# HTTP errors only
log stream --predicate 'subsystem == "com.busylight.agent.network"' | grep "failed"
```

### Expected Log Entry Formats

**Successful Preset Activation:**

```
network_client.send_state [state=available preset=1 device_count=1]
http.post.state.success [address=192.168.1.100 port=80 preset=1 latency_ms=120]
network_client.send.success [device=WLED-Office preset=1 state=available response_preset=1 device_on=true]
```

**Device Discovery:**

```
discovery.started [timeout=5.0]
discovery.service.found [name=WLED-Office type=_http._tcp. domain=local.]
discovery.service.resolved [name=WLED-Office hostname=wled-office.local. port=80]
discovery.wled.verified [name=WLED-Office address=192.168.1.100 port=80 version=0.15.0 mac=aabbccddeeff]
discovery.completed [devices_found=1]
```

**Health Check:**

```
network_client.health.check [device_count=1]
http.get.info.success [address=192.168.1.100 port=80 name=WLED-Office version=0.15.0 latency_ms=45]
```

**Connection Failure:**

```
http.request.retry [url=http://192.168.1.100/json/state method=POST attempt=1 next_delay_ms=100 error=The operation couldn't be completed]
http.request.failed.max_retries [url=http://192.168.1.100/json/state method=POST attempts=3 error=timeout]
network_client.send.failed [device=WLED-Office preset=1 state=available error=timeout]
```

### Performance Metrics

**Typical Latency Values:**

| Operation | Expected Latency | Threshold |
|-----------|------------------|-----------|
| Preset activation | 50-150ms | < 500ms |
| Device info retrieval | 30-80ms | < 500ms |
| Discovery (full cycle) | 3-5 seconds | < 10s |
| Health check | 30-100ms | < 1s |

**Monitoring Latency:**

```bash
log stream --predicate 'subsystem == "com.busylight.agent.network"' | \
  grep "latency_ms" | \
  awk -F'latency_ms=' '{print $2}' | \
  awk -F']' '{print $1}'
```

## Pass/Fail Criteria

### Overall Test Suite

**Pass Requirements:**
- ✅ All 12 test cases pass
- ✅ All 6 presets activate correctly
- ✅ No crashes or hangs during testing
- ✅ Error logs show appropriate context
- ✅ Performance meets latency thresholds

**Fail Conditions:**
- ❌ Any preset fails to activate
- ❌ Agent crashes during normal operation
- ❌ Latency exceeds 500ms consistently
- ❌ Health check not functioning
- ❌ Discovery fails to find devices

### Individual Test Case Criteria

Each test case has specific pass/fail criteria listed in its section. General requirements:

- **Functional**: Feature works as specified
- **Performance**: Meets latency requirements
- **Reliability**: No intermittent failures
- **Logging**: Appropriate events logged
- **UI**: Correct status displayed

## Known Limitations

### Network Constraints

1. **5GHz WiFi**: ESP32 only supports 2.4GHz networks
2. **VLAN Isolation**: Discovery fails across VLAN boundaries
3. **Corporate Firewalls**: May block mDNS or HTTP traffic
4. **VPN Networks**: Discovery may not work through VPN
5. **Subnet Range**: Discovery limited to local subnet

### Device Constraints

1. **Maximum Devices**: Tested up to 10 simultaneous devices
2. **Preset Limit**: WLED supports presets 1-250
3. **Firmware Version**: Tested with WLED 0.14.0 - 0.15.3
4. **HTTP Only**: HTTPS not supported by standard WLED firmware
5. **No Authentication**: WLED API has no built-in authentication

### Agent Constraints

1. **Manual Testing Only**: No automated test harness currently
2. **macOS 14+ Required**: Older versions not tested
3. **Calendar Permission**: Required for tentative/busy calendar states
4. **Accessibility Permission**: Required for global hotkeys

## Troubleshooting Guide

### Device Not Discovered

**Symptoms:** Menu bar shows "Devices: None configured" despite WLED online.

**Solutions:**

1. Verify same network:
   ```bash
   ping 192.168.1.100
   ```

2. Check mDNS resolution:
   ```bash
   dns-sd -B _http._tcp.
   ```

3. Manually configure IP:
   ```bash
   defaults write com.busylight.agent app.device_network_addresses \
     -array "192.168.1.100"
   ```

4. Check firewall:
   - System Settings → Network → Firewall
   - Allow BusyLight.app

### Preset Not Activating

**Symptoms:** LED doesn't change when state changes.

**Solutions:**

1. Test preset manually in WLED interface
2. Verify preset ID exists:
   ```bash
   curl http://192.168.1.100/json/state
   # Look for "ps" field
   ```

3. Check configuration:
   ```bash
   defaults read com.busylight.agent | grep wled_preset
   ```

4. Verify HTTP API not disabled in WLED settings

### High Latency

**Symptoms:** Slow response time (> 500ms consistently).

**Solutions:**

1. Move device closer to router
2. Check WiFi signal strength in WLED interface
3. Reduce health check frequency:
   ```bash
   defaults write com.busylight.agent app.wled_health_check_interval -int 30
   ```

4. Check network congestion
5. Consider wired Ethernet adapter for ESP32

### Connection Drops

**Symptoms:** Device frequently goes offline/online.

**Solutions:**

1. Check power supply (ensure 2A minimum)
2. Improve WiFi coverage
3. Set static IP in router DHCP reservation
4. Check for WiFi interference (microwaves, bluetooth)
5. Update WLED firmware to latest stable

### Logs Not Appearing

**Symptoms:** `log stream` shows no output.

**Solutions:**

1. Verify subsystem name:
   ```bash
   log show --predicate 'subsystem CONTAINS "busylight"' --last 1m
   ```

2. Check log level:
   ```bash
   sudo log config --subsystem com.busylight.agent --mode level:debug
   ```

3. Build with debug configuration:
   ```bash
   ./build.sh
   ```

## Mock Server Testing (Optional)

For automated or offline testing, create a Python Flask mock server:

```python
# mock_wled.py
from flask import Flask, request, jsonify
app = Flask(__name__)

current_preset = 0

@app.route('/json/state', methods=['POST'])
def set_state():
    global current_preset
    data = request.json
    current_preset = data.get('ps', 0)
    
    return jsonify({
        "on": True,
        "bri": 127,
        "ps": current_preset
    })

@app.route('/json/info', methods=['GET'])
def get_info():
    return jsonify({
        "ver": "0.15.0-mock",
        "name": "WLED-Mock",
        "uptime": 3600,
        "ip": "127.0.0.1",
        "mac": "000000000000"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**Run Mock Server:**

```bash
# Install Flask
pip3 install flask

# Run server
python3 mock_wled.py

# Configure agent to use mock
defaults write com.busylight.agent app.device_network_addresses \
  -array "localhost"
defaults write com.busylight.agent app.device_network_port -int 8080
```

## Test Report Template

```markdown
# WLED Network Module Test Report

**Date:** YYYY-MM-DD
**Tester:** [Name]
**Agent Version:** [Git commit or version]
**WLED Firmware:** [Version]
**macOS Version:** [Version]

## Test Environment
- Mac Model: [Model]
- macOS: [Version]
- WLED Devices: [Count]
- Network: [2.4GHz/5GHz, Router model]

## Test Results Summary
- Total Tests: 12
- Passed: [X]
- Failed: [Y]
- Skipped: [Z]

## Individual Test Results

### Test 1: Available Preset
- Status: ✅ PASS / ❌ FAIL
- Notes: [Any observations]

[Repeat for all 12 tests]

## Performance Metrics
- Average Latency: [X]ms
- Discovery Time: [X]s
- Health Check Interval: [X]s

## Issues Found
1. [Issue description]
2. [Issue description]

## Recommendations
- [Recommendation 1]
- [Recommendation 2]
```

## References

- [WLED JSON API Documentation](https://kno.wled.ge/interfaces/json-api/)
- [Network Integration README](../macos-agent/network/README.md)
- [Hardware Assembly Guide](module-assembly.md)
- [BusyLight Main README](../README.md)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-22 | Initial comprehensive testing guide |

---

**Document Status:** ✅ Complete  
**Maintainer:** BusyLight Development Team  
**Last Review:** February 22, 2026
