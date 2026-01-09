import Foundation
@preconcurrency import CoreBluetooth

// MARK: - Discovered Device

struct DiscoveredDevice: @unchecked Sendable {
    let peripheral: CBPeripheral
    let name: String?
    let rssi: Int
    let advertisementData: [String: Any]
    let identifier: UUID

    var serviceUUIDs: [CBUUID] {
        advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    }
}

// MARK: - Connection State

enum BLEConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// MARK: - BLE Manager Actor

actor BLEManager {
    private var centralManager: CBCentralManager!
    private var delegate: BLEDelegate!

    private(set) var state: CBManagerState = .unknown
    private(set) var connectionState: BLEConnectionState = .disconnected
    private(set) var connectedPeripheral: CBPeripheral?
    private(set) var discoveredDevices: [UUID: DiscoveredDevice] = [:]
    private(set) var discoveredServices: [CBUUID: CBService] = [:]
    private(set) var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]

    // Subscription state
    private var subscriptions: Set<CBUUID> = []
    private var notificationBuffer: [CBUUID: [Data]] = [:]
    private var notificationContinuations: [CBUUID: AsyncStream<Data>.Continuation] = [:]

    // Logging
    private(set) var isLogging = false
    private var logFileHandle: FileHandle?
    private var logFilePath: String?

    func start() {
        delegate = BLEDelegate(manager: self)
        centralManager = CBCentralManager(delegate: delegate, queue: nil)
    }

    // MARK: - State Updates (called from delegate)

    func updateState(_ newState: CBManagerState) {
        state = newState
    }

    func deviceDiscovered(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let device = DiscoveredDevice(
            peripheral: peripheral,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: rssi.intValue,
            advertisementData: advertisementData,
            identifier: peripheral.identifier
        )
        discoveredDevices[peripheral.identifier] = device
    }

    func didConnect(_ peripheral: CBPeripheral) {
        connectionState = .connected
        connectedPeripheral = peripheral
        peripheral.delegate = delegate
        peripheral.discoverServices(nil)
    }

    func didDisconnect(_ peripheral: CBPeripheral) {
        connectionState = .disconnected
        connectedPeripheral = nil
        discoveredServices.removeAll()
        discoveredCharacteristics.removeAll()
        subscriptions.removeAll()
        notificationBuffer.removeAll()
        for continuation in notificationContinuations.values {
            continuation.finish()
        }
        notificationContinuations.removeAll()
    }

    func didFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
    }

    func didDiscoverServices(_ peripheral: CBPeripheral, services: [CBService]?) {
        guard let services = services else { return }
        for service in services {
            discoveredServices[service.uuid] = service
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func didDiscoverCharacteristics(_ service: CBService, characteristics: [CBCharacteristic]?) {
        guard let characteristics = characteristics else { return }
        for char in characteristics {
            discoveredCharacteristics[char.uuid] = char
        }
    }

    func didUpdateValue(_ characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        // Buffer for polling reads
        if notificationBuffer[characteristic.uuid] == nil {
            notificationBuffer[characteristic.uuid] = []
        }
        notificationBuffer[characteristic.uuid]?.append(data)

        // Keep buffer size manageable
        if notificationBuffer[characteristic.uuid]!.count > 1000 {
            notificationBuffer[characteristic.uuid]?.removeFirst(500)
        }

        // Log if enabled
        if isLogging {
            logData(characteristic: characteristic.uuid, data: data)
        }

        // Push to stream if subscribed
        if let continuation = notificationContinuations[characteristic.uuid] {
            continuation.yield(data)
        }
    }

    func didWriteValue(_ characteristic: CBCharacteristic, error: Error?) {
        // Could track write confirmations if needed
    }

    // MARK: - Scanning

    func scan(duration: TimeInterval = 5.0, serviceUUIDs: [CBUUID]? = nil) async -> [DiscoveredDevice] {
        guard state == .poweredOn else {
            return []
        }

        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        centralManager.stopScan()

        return Array(discoveredDevices.values)
    }

    // MARK: - Connection

    func connect(identifier: UUID) async throws {
        guard state == .poweredOn else {
            throw ToolError("Bluetooth not powered on")
        }

        guard let device = discoveredDevices[identifier] else {
            throw ToolError("Device not found. Run ble_scan first.")
        }

        connectionState = .connecting
        centralManager.connect(device.peripheral, options: nil)

        // Wait for connection (with timeout)
        let startTime = Date()
        while connectionState == .connecting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if Date().timeIntervalSince(startTime) > 10.0 {
                centralManager.cancelPeripheralConnection(device.peripheral)
                connectionState = .disconnected
                throw ToolError("Connection timeout")
            }
        }

        if connectionState != .connected {
            throw ToolError("Failed to connect")
        }

        // Wait for service/characteristic discovery
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s for discovery
    }

    func connect(name: String) async throws {
        guard let device = discoveredDevices.values.first(where: {
            $0.name?.lowercased().contains(name.lowercased()) == true
        }) else {
            throw ToolError("Device '\(name)' not found. Run ble_scan first.")
        }
        try await connect(identifier: device.identifier)
    }

    func disconnect() async {
        guard let peripheral = connectedPeripheral else { return }
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(peripheral)

        // Wait for disconnect
        while connectionState == .disconnecting {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Reading

    func read(characteristicUUID: CBUUID) async throws -> Data {
        guard connectionState == .connected else {
            throw ToolError("Not connected")
        }

        guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
            throw ToolError("Characteristic \(characteristicUUID) not found")
        }

        // Clear buffer for this characteristic
        notificationBuffer[characteristicUUID] = []

        connectedPeripheral?.readValue(for: characteristic)

        // Wait for value (with timeout)
        let startTime = Date()
        while notificationBuffer[characteristicUUID]?.isEmpty ?? true {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if Date().timeIntervalSince(startTime) > 5.0 {
                throw ToolError("Read timeout")
            }
        }

        guard let data = notificationBuffer[characteristicUUID]?.last else {
            throw ToolError("No data received")
        }

        return data
    }

    // MARK: - Writing

    func write(characteristicUUID: CBUUID, data: Data, withResponse: Bool = true) async throws {
        guard connectionState == .connected else {
            throw ToolError("Not connected")
        }

        guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
            throw ToolError("Characteristic \(characteristicUUID) not found")
        }

        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        connectedPeripheral?.writeValue(data, for: characteristic, type: type)

        if withResponse {
            // Give time for write to complete
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Subscriptions

    func subscribe(characteristicUUID: CBUUID) async throws -> AsyncStream<Data> {
        guard connectionState == .connected else {
            throw ToolError("Not connected")
        }

        guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
            throw ToolError("Characteristic \(characteristicUUID) not found")
        }

        subscriptions.insert(characteristicUUID)
        notificationBuffer[characteristicUUID] = []

        let stream = AsyncStream<Data> { continuation in
            Task {
                await self.setNotificationContinuation(characteristicUUID, continuation: continuation)
            }
        }

        connectedPeripheral?.setNotifyValue(true, for: characteristic)

        return stream
    }

    private func setNotificationContinuation(_ uuid: CBUUID, continuation: AsyncStream<Data>.Continuation) {
        notificationContinuations[uuid] = continuation
    }

    func unsubscribe(characteristicUUID: CBUUID) async {
        subscriptions.remove(characteristicUUID)

        if let characteristic = discoveredCharacteristics[characteristicUUID] {
            connectedPeripheral?.setNotifyValue(false, for: characteristic)
        }

        notificationContinuations[characteristicUUID]?.finish()
        notificationContinuations[characteristicUUID] = nil
    }

    func getBufferedNotifications(characteristicUUID: CBUUID) -> [Data] {
        let data = notificationBuffer[characteristicUUID] ?? []
        notificationBuffer[characteristicUUID] = []
        return data
    }

    // MARK: - Device Info

    func getDeviceInfo() -> [String: Any]? {
        guard let peripheral = connectedPeripheral else { return nil }

        return [
            "name": peripheral.name ?? "Unknown",
            "identifier": peripheral.identifier.uuidString,
            "state": connectionState,
            "services": discoveredServices.keys.map { $0.uuidString },
            "characteristics": discoveredCharacteristics.keys.map { $0.uuidString }
        ]
    }

    func getServices() -> [(uuid: CBUUID, characteristics: [CBUUID])] {
        return discoveredServices.values.map { service in
            let charUUIDs = service.characteristics?.map { $0.uuid } ?? []
            return (uuid: service.uuid, characteristics: charUUIDs)
        }
    }

    func getCharacteristics(forService serviceUUID: CBUUID) -> [(uuid: CBUUID, properties: CBCharacteristicProperties)]? {
        guard let service = discoveredServices[serviceUUID] else { return nil }
        return service.characteristics?.map { ($0.uuid, $0.properties) }
    }

    func getAllCharacteristics() -> [(uuid: CBUUID, serviceUUID: CBUUID, properties: CBCharacteristicProperties)] {
        var result: [(uuid: CBUUID, serviceUUID: CBUUID, properties: CBCharacteristicProperties)] = []
        for (serviceUUID, service) in discoveredServices {
            for char in service.characteristics ?? [] {
                result.append((uuid: char.uuid, serviceUUID: serviceUUID, properties: char.properties))
            }
        }
        return result
    }

    func getRSSI() async -> Int? {
        guard let peripheral = connectedPeripheral else { return nil }
        peripheral.readRSSI()
        try? await Task.sleep(nanoseconds: 200_000_000)
        return delegate.lastRSSI
    }

    // MARK: - Logging

    func startLogging(filePath: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: filePath) {
            fileManager.createFile(atPath: filePath, contents: nil)
        }
        logFileHandle = FileHandle(forWritingAtPath: filePath)
        logFileHandle?.seekToEndOfFile()
        logFilePath = filePath
        isLogging = true

        // Write header
        let header = "timestamp,characteristic,hex_data,length\n"
        logFileHandle?.write(header.data(using: .utf8)!)
    }

    func stopLogging() -> String? {
        isLogging = false
        logFileHandle?.closeFile()
        logFileHandle = nil
        let path = logFilePath
        logFilePath = nil
        return path
    }

    private func logData(characteristic: CBUUID, data: Data) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let line = "\(timestamp),\(characteristic.uuidString),\(hex),\(data.count)\n"
        logFileHandle?.write(line.data(using: .utf8)!)
    }
}

// MARK: - CBCentralManager Delegate

class BLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let manager: BLEManager
    var lastRSSI: Int?

    init(manager: BLEManager) {
        self.manager = manager
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { await manager.updateState(central.state) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { await manager.deviceDiscovered(peripheral, advertisementData: advertisementData, rssi: RSSI) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { await manager.didConnect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { await manager.didDisconnect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { await manager.didFailToConnect(peripheral, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { await manager.didDiscoverServices(peripheral, services: peripheral.services) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { await manager.didDiscoverCharacteristics(service, characteristics: service.characteristics) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { await manager.didUpdateValue(characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { await manager.didWriteValue(characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        lastRSSI = RSSI.intValue
    }
}
