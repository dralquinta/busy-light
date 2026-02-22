# WLED Network Integration

This document describes the WLED network layer for the BusyLight macOS agent. The network layer enables communication with WLED-powered LED devices via HTTP JSON API to visualize presence status.

## Overview

The network layer provides:
- **HTTP JSON API client** for WLED firmware communication
- **Bonjour/mDNS device discovery** for zero-configuration setup
- **Multi-device broadcasting** to control multiple LED displays simultaneously
- **Health monitoring** with automatic reconnection
- **Preset-based state mapping** for all 6 presence states

## Architecture

```
┌─────────────────────┐
│ PresenceStateMachine│
└──────────┬──────────┘
           │ onStateChanged
           ▼
    ┌──────────────┐
    │NetworkClient │ ←─ ConfigurationManager
    └──────┬───────┘
           │
     ┌─────┴──────┐
     │            │
     ▼            ▼
┌────────────┐ ┌─────────────┐
│HTTPAdapter │ │DeviceDiscovery│
└────┬───────┘ └──────┬──────┘
     │                │
     ▼                ▼
┌──────────┐    ┌───────────┐
│  WLED    │    │  Bonjour  │
│  Device  │    │  _http._tcp│
└──────────┘    └───────────┘
```

### Components

- **NetworkClient**: Main coordinator, manages device list and broadcasts state changes
- **HTTPAdapter**: HTTP client with retry logic and timeout handling
- **DeviceDiscovery**: Bonjour/mDNS service discovery and WLED verification
- **WLEDTypes**: Data models for API requests/responses and device representation

## WLED JSON API

### Endpoints

#### POST `/json/state` - Activate Preset

Activates a preset by ID to change LED display.

**Request:**
```json
{
  "ps": 1,
  "v": true
}
```

- `ps`: Preset ID (1-250)
- `v`: Return full state response (recommended)

**Response:**
```json
{
  "on": true,
  "bri": 127,
  "ps": 1
}
```

- `on`: Light is on/off
- `bri`: Brightness (0-255)
- `ps`: Active preset ID

#### GET `/json/info` - Device Information

Retrieves device metadata and status.

**Response:**
```json
{
  "ver": "0.15.0",
  "name": "WLED-Office",
  "uptime": 3600,
  "ip": "192.168.1.100",
  "mac": "aabbccddeeff"
}
```

### Default Port

WLED uses port **80** by default (standard HTTP).

## Configuration

### UserDefaults Keys

```bash
# Network addresses (array of IPs)
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100" "192.168.1.101"

# WLED port (default: 80)
defaults write com.busylight.agent app.device_network_port -int 80

# Preset IDs for each presence state
defaults write com.busylight.agent app.wled_preset_available -int 1
defaults write com.busylight.agent app.wled_preset_tentative -int 2
defaults write com.busylight.agent app.wled_preset_busy -int 3
defaults write com.busylight.agent app.wled_preset_away -int 4
defaults write com.busylight.agent app.wled_preset_unknown -int 5
defaults write com.busylight.agent app.wled_preset_off -int 6

# HTTP timeout in milliseconds (default: 500)
defaults write com.busylight.agent app.wled_http_timeout -int 500

# Health check interval in seconds (default: 10)
defaults write com.busylight.agent app.wled_health_check_interval -int 10

# Enable Bonjour discovery (default: true)
defaults write com.busylight.agent app.wled_enable_discovery -bool true
```

### Preset Mapping

Configure WLED presets 1-6 in the device web interface to match these states:

| Presence State | Default Preset ID | Recommended Visual |
|----------------|-------------------|-------------------|
| Available      | 1                 | Green solid       |
| Tentative      | 2                 | Yellow/Amber breathe |
| Busy           | 3                 | Red solid         |
| Away           | 4                 | Blue fade         |
| Unknown        | 5                 | White blink       |
| Off            | 6                 | LEDs off          |

## Device Discovery

### Bonjour/mDNS

The network layer automatically discovers WLED devices on the local network using:

- **Service Type**: `_http._tcp.local.`
- **Verification**: Fetches `/json/info` and checks for WLED version string
- **Timeout**: 5 seconds
- **Resolution**: Resolves hostnames to IP addresses

Discovery can be disabled via configuration if manual IP configuration is preferred.

### Manual Configuration

If discovery is disabled or devices are not found:

1. Find your WLED device IP address (check router DHCP or WLED app)
2. Configure via UserDefaults:
   ```bash
   defaults write com.busylight.agent app.device_network_addresses \
     -array "192.168.1.100"
   ```
3. Restart BusyLight agent

## Multi-Device Broadcasting

The agent broadcasts state changes to **all configured devices simultaneously**:

- Parallel execution using Swift's `TaskGroup`
- Individual success/failure tracking per device
- Continues operating even if some devices are offline
- UI displays aggregate status (X online, Y offline)

### Deduplication

To prevent unnecessary HTTP requests:
- Agent tracks last preset sent to each device
- Skips sending if already in requested state
- Resets on device reconnection to ensure sync

## Health Monitoring

### Polling Mechanism

- Polls all devices every N seconds (configurable, default: 10s)
- Uses `GET /json/info` to verify connectivity
- Updates `isOnline` status and `lastSeen` timestamp
- Triggers UI callback on status transitions

### Automatic Recovery

When a device comes back online:
1. Health check detects device is reachable
2. Status updated to `online`
3. Next state change sends current state to ensure sync
4. UI updates to show device online

## Error Handling

### Retry Logic

Failed HTTP requests are retried with exponential backoff:

| Attempt | Delay   |
|---------|---------|
| 1       | 0ms     |
| 2       | 100ms   |
| 3       | 200ms   |
| 4       | 400ms   |

Maximum 3 retries before giving up.

### Non-Fatal Failures

Network failures are **non-fatal**:
- Agent continues operating normally
- Logs errors for troubleshooting
- UI shows device offline status
- User can continue working

### Error Types

- **Timeout**: Request exceeded configured timeout
- **Device Unavailable**: Host unreachable
- **HTTP Error**: 4xx/5xx status codes
- **JSON Parsing Failed**: Invalid response format
- **Invalid URL**: Malformed address/port

## Logging

All network operations are logged using structured logging:

### Log Categories

```bash
# Stream network logs
log stream --predicate 'subsystem == "com.busylight.agent.network"' --level debug
```

### Log Events

- `network_client.connect.started` - Discovery initiated
- `network_client.connect.discovered` - Devices found via mDNS
- `network_client.connect.manual` - Manual IP added
- `network_client.send_state` - Broadcasting state change
- `network_client.send.success` - Preset activated successfully
- `network_client.send.failed` - Request failed
- `network_client.health.transition` - Device online/offline change
- `http.post.state.success` - HTTP POST succeeded
- `http.request.retry` - Retrying failed request
- `discovery.wled.verified` - WLED device confirmed

### Log Fields

Each log entry includes:
- `address`: Device IP
- `port`: Device port
- `preset`: Preset ID
- `state`: Presence state
- `latency_ms`: Request latency
- `error`: Error description (if failed)

## Testing

For comprehensive testing procedures, see [Testing Documentation](../docs/module-testing.md).

### Quick Test

1. Flash WLED firmware to ESP32 device from https://install.wled.me/
2. Configure 6 presets in WLED web interface
3. Launch BusyLight agent
4. Check menu bar: "Devices: X online"
5. Change presence state via hotkey
6. Verify LED changes color/effect

### Troubleshooting

#### Device Not Discovered

- Ensure device on same network/VLAN
- Check 2.4GHz WiFi (ESP32 doesn't support 5GHz)
- Disable discovery and configure IP manually
- Verify WLED firmware installed correctly

#### Preset Activation Fails

- Check preset IDs 1-6 exist in WLED
- Test manual activation in WLED web UI
- Verify HTTP API not disabled in WLED settings
- Check logs for HTTP error details

#### High Latency

- Move device closer to router
- Check network congestion
- Reduce health check frequency
- Consider wired Ethernet for ESP32

#### Firewall Blocking

- macOS Firewall: Allow BusyLight.app
- Router firewall: Allow HTTP port 80 between devices
- Corporate network: May block mDNS or HTTP

## Implementation Details

### Concurrency Model

- **NetworkClient**: `@MainActor` isolated for callback invocation
- **HTTPAdapter**: `actor` isolated for thread-safe URL session access
- **DeviceDiscovery**: `@MainActor` for NetService delegate compatibility
- **Async/await**: All I/O operations use structured concurrency
- **TaskGroup**: Parallel device operations

### Thread Safety

- All public APIs are `@MainActor` or `actor` isolated
- Data models are `Sendable` (immutable)
- URLSession is thread-safe internally
- Callbacks always dispatched to MainActor

### Memory Management

- Weak references used for callbacks to prevent retain cycles
- Tasks properly cancelled on disconnect
- No retain cycles in delegate patterns

## Future Enhancements

Potential improvements:

- WebSocket support for bidirectional communication
- Device button input handling
- Custom effects via JSON API
- Brightness control based on time of day
- UI for preset configuration (add menu items)
- Static IP assignment via WLED API
- Firmware OTA update integration

## References

- [WLED Project](https://kno.wled.ge/)
- [WLED JSON API Documentation](https://kno.wled.ge/interfaces/json-api/)
- [WLED GitHub Repository](https://github.com/wled/WLED)
- [WLED Web Installer](https://install.wled.me/)
- [Hardware Assembly Guide](../docs/module-assembly.md)
- [Testing Documentation](../docs/module-testing.md)

## Support

For issues or questions:
1. Check logs: `log stream --predicate 'subsystem == "com.busylight.agent"'`
2. Review troubleshooting section above
3. Verify WLED device accessible via web browser
4. Test JSON API manually with curl
5. File GitHub issue with logs and configuration details
