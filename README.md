# CoreBluetooth-MCP

A native macOS MCP server for Bluetooth Low Energy testing, with first-class support for FTMS (Fitness Machine Service) devices like bike trainers and smart bikes.

Built with Swift and CoreBluetooth. No Node.js, Python, or external dependencies.

## Features

### Core BLE Tools
- `ble_scan` - Scan for nearby BLE devices with optional name/service filters
- `ble_connect` - Connect to a device by name or UUID
- `ble_disconnect` - Disconnect from the current device
- `ble_status` - Show connection state, device info, and signal strength
- `ble_services` - List all services on connected device
- `ble_characteristics` - List characteristics with properties (read/write/notify)

### Generic BLE Operations
- `ble_read` - Read any characteristic by UUID with auto-decoding
- `ble_write` - Write hex bytes or text to any characteristic
- `ble_subscribe` - Subscribe to notifications from any characteristic
- `ble_unsubscribe` - Stop notifications
- `ble_battery` - Read battery level (if available)
- `ble_device_info` - Read manufacturer, model, serial, firmware

### FTMS Discovery
- `ftms_discover` - Scan specifically for FTMS devices (service UUID 0x1826)
- `ftms_info` - Read FTMS Feature characteristic to show supported features

### FTMS Data
- `ftms_read` - Single reading of Indoor Bike Data (power, cadence, speed)
- `ftms_subscribe` - Stream notifications with min/max/avg stats
- `ftms_unsubscribe` - Stop streaming
- `ftms_monitor` - Timed monitoring session with summary statistics

### FTMS Control
- `ftms_request_control` - Request control of the fitness machine
- `ftms_set_power` - Set target power in watts
- `ftms_start` - Start/resume workout
- `ftms_stop` - Stop/pause workout
- `ftms_reset` - Reset the device

### Advanced
- `ftms_test_sequence` - Automated validation: request control, set power levels, verify readings
- `ftms_log_start` / `ftms_log_stop` - Log notifications to CSV
- `ftms_raw_read` / `ftms_raw_write` - Raw characteristic access for debugging

## Installation

### Option 1: Mint (Recommended for Swift developers)

```bash
# Install Mint if you don't have it
brew install mint

# Install CoreBluetooth-MCP
mint install bmdragos/CoreBluetooth-MCP
```

Binary installs to `~/.mint/bin/corebluetooth-mcp`

### Option 2: Build from source

```bash
git clone https://github.com/bmdragos/CoreBluetooth-MCP.git
cd CoreBluetooth-MCP
swift build -c release

# Optional: copy to a permanent location
cp .build/release/corebluetooth-mcp /usr/local/bin/
```

## Configure Claude Code

Add to your `~/.claude/settings.json` or project `.mcp.json`:

```json
{
  "mcpServers": {
    "corebluetooth-mcp": {
      "type": "stdio",
      "command": "~/.mint/bin/corebluetooth-mcp"
    }
  }
}
```

Or if you built from source:

```json
{
  "mcpServers": {
    "corebluetooth-mcp": {
      "type": "stdio",
      "command": "/usr/local/bin/corebluetooth-mcp"
    }
  }
}
```

Then run `/mcp` in Claude Code to connect.

## Usage Examples

### Discover and connect to an FTMS device

```
> ftms_discover
Found 1 device(s):
  Lode Bike (CC77AB70-...) RSSI: -36 dBm [Services: 1826]

> ble_connect identifier="Lode Bike"
Connected to Lode Bike

> ftms_info
Supported features: Target Power, Indoor Bike Data
```

### Monitor power output

```
> ftms_subscribe samples=10
Collected 10 samples in 5.2s

Power: 98W - 102W (avg: 100W)
Cadence: 88 - 92 rpm (avg: 90 rpm)

Last reading: 101W @ 91rpm
```

### Control target power

```
> ftms_request_control
Control granted

> ftms_set_power watts=150
Target power set to 150W

> ftms_read
Power: 150 W
Cadence: 85 rpm
```

### Run automated test sequence

```
> ftms_test_sequence power_low=100 power_high=200
═══════════════════════════════════════
  FTMS Test Sequence Results
═══════════════════════════════════════

✓ Request Control: OK
✓ Set 100W: Command sent
✓ Read @ 100W: 100W @ 88rpm
✓ Set 200W: Command sent
✓ Read @ 200W: 199W @ 92rpm

═══════════════════════════════════════
Result: 5/5 steps passed
Status: ALL TESTS PASSED ✓
```

## Requirements

- macOS 13.0+
- Xcode 15+ / Swift 5.9+
- Bluetooth hardware

## Why CoreBluetooth?

- **Native performance** - No bridging overhead, direct CoreBluetooth access
- **No dependencies** - Single binary, no npm/pip/runtime needed
- **Inline testing** - Test BLE firmware without leaving your IDE
- **FTMS-first** - Purpose-built for fitness device development

## License

MIT
