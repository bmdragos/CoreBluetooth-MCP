# CoreBluetooth-MCP Roadmap

## Planned Features

### BLE Profiles

- [ ] **Heart Rate Service (0x180D)**
  - `hrs_read` - single heart rate reading
  - `hrs_subscribe` - stream heart rate data

- [ ] **Cycling Power Service (0x1818)**
  - `cps_read` - power, cadence, pedal balance
  - `cps_subscribe` - stream power data
  - Useful for standalone power meters

- [x] **Battery Service (0x180F)**
  - `ble_battery` - battery level for any device

- [x] **Device Information Service (0x180A)**
  - `ble_device_info` - manufacturer, model, serial, firmware, hardware revision

### Additional FTMS Controls

- [ ] `ftms_set_resistance` - resistance mode (0-100%)
- [ ] `ftms_set_simulation` - simulation mode (grade %, wind speed, rolling resistance, air resistance)
- [ ] `ftms_set_cadence` - target cadence
- [ ] Support for Indoor Rower Data
- [ ] Support for Treadmill Data

### Generic BLE Operations

- [x] `ble_services` - list all services on connected device
- [x] `ble_characteristics` - list characteristics for a service with properties (read/write/notify)
- [x] `ble_read` - read any characteristic by UUID with auto-decoding
- [x] `ble_write` - write to any characteristic (hex or text)
- [x] `ble_subscribe` - subscribe to notifications from any characteristic
- [x] `ble_unsubscribe` - stop notifications
- [ ] `ble_descriptors` - read characteristic descriptors

### Quality of Life

- [ ] `ble_reconnect` - reconnect to last connected device
- [ ] `ble_rssi` - continuous signal strength monitoring
- [ ] Configurable timeouts on subscribe operations
- [ ] Auto-reconnect option on disconnect

### Data Export

- [ ] Export to FIT file format
- [ ] Export to TCX format
- [ ] Enhanced CSV export options

---

## Completed

- [x] Core BLE (scan, connect, disconnect, status)
- [x] FTMS discovery and feature detection
- [x] FTMS data streaming with statistics
- [x] FTMS power control
- [x] Automated test sequences
- [x] CSV logging
- [x] Raw characteristic read/write
