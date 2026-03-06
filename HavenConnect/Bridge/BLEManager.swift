import CoreBluetooth
import Foundation

/// Discovered BLE device info passed to the web layer.
struct BLEDevice {
    let id: String
    let name: String?
    let rssi: Int
}

/// Delegate protocol — WebViewRepresentable.Coordinator implements this
/// to relay BLE events back to the web page via JavaScript.
protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, didDiscoverDevice device: BLEDevice)
    func bleManager(_ manager: BLEManager, didConnect deviceId: String, name: String?)
    func bleManager(_ manager: BLEManager, didDisconnect deviceId: String)
    func bleManager(_ manager: BLEManager, didReceiveData data: Data, characteristicUUID: String, deviceId: String)
    func bleManager(_ manager: BLEManager, didReadValue data: Data, characteristicUUID: String, deviceId: String)
    func bleManager(_ manager: BLEManager, didServicesReady deviceId: String)
    func bleManager(_ manager: BLEManager, didError error: String)
}

/// CoreBluetooth manager — bridges between web page requests and iOS BLE.
///
/// This is the core of Haven Connect. It handles:
/// - Device scanning with service UUID filters
/// - GATT connection and service/characteristic discovery
/// - Read, write, and notify operations
/// - Clean disconnect
///
/// All BLE operations use Apple's CoreBluetooth framework.
/// No private APIs. No hacks. Just the standard Apple BLE stack.
class BLEManager: NSObject {
    weak var delegate: BLEManagerDelegate?

    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var peripheralDelegates: [String: PeripheralDelegate] = [:]
    private var scanFilters: [[String: Any]]?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API (called from web bridge)

    func requestDevice(filters: [[String: Any]]?) {
        guard centralManager.state == .poweredOn else {
            delegate?.bleManager(self, didError: "Bluetooth is not available")
            return
        }

        scanFilters = filters
        discoveredPeripherals.removeAll()

        // Extract service UUIDs from filters
        var serviceUUIDs: [CBUUID]? = nil
        if let filters = filters {
            var uuids: [CBUUID] = []
            for filter in filters {
                if let services = filter["services"] as? [String] {
                    uuids.append(contentsOf: services.map { CBUUID(string: $0) })
                }
            }
            if !uuids.isEmpty { serviceUUIDs = uuids }
        }

        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.centralManager.stopScan()
        }
    }

    func connect(deviceId: String) {
        guard let peripheral = discoveredPeripherals[deviceId] else {
            delegate?.bleManager(self, didError: "Device not found: \(deviceId)")
            return
        }
        centralManager.connect(peripheral, options: nil)

        // CoreBluetooth has no built-in connection timeout — it will try forever.
        // Cancel after 15 seconds if not connected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self else { return }
            if self.connectedPeripherals[deviceId] == nil,
               let p = self.discoveredPeripherals[deviceId] {
                self.centralManager.cancelPeripheralConnection(p)
                self.delegate?.bleManager(self, didError: "Connection timed out")
            }
        }
    }

    func disconnect(deviceId: String) {
        guard let peripheral = connectedPeripherals[deviceId] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func readCharacteristic(deviceId: String, serviceUUID: String, characteristicUUID: String) {
        guard let pd = peripheralDelegates[deviceId] else {
            delegate?.bleManager(self, didError: "Device not connected: \(deviceId)")
            return
        }
        pd.readCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
    }

    func startNotifications(deviceId: String, serviceUUID: String, characteristicUUID: String) {
        guard let pd = peripheralDelegates[deviceId] else {
            delegate?.bleManager(self, didError: "Device not connected: \(deviceId)")
            return
        }
        pd.setNotify(true, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
    }

    func stopNotifications(deviceId: String, serviceUUID: String, characteristicUUID: String) {
        guard let pd = peripheralDelegates[deviceId] else {
            delegate?.bleManager(self, didError: "Device not connected: \(deviceId)")
            return
        }
        pd.setNotify(false, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
    }

    func writeCharacteristic(deviceId: String, serviceUUID: String, characteristicUUID: String, value: Data) {
        guard let pd = peripheralDelegates[deviceId] else {
            delegate?.bleManager(self, didError: "Device not connected: \(deviceId)")
            return
        }
        pd.writeCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID, value: value)
    }

    func disconnectAll() {
        for (_, peripheral) in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    var connectedDeviceIds: [String] {
        Array(connectedPeripherals.keys)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            delegate?.bleManager(self, didError: "Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier.uuidString
        discoveredPeripherals[id] = peripheral

        delegate?.bleManager(self, didDiscoverDevice: BLEDevice(
            id: id,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals[id] = peripheral

        let pd = PeripheralDelegate(manager: self, deviceId: id)
        peripheralDelegates[id] = pd
        peripheral.delegate = pd
        peripheral.discoverServices(nil)

        delegate?.bleManager(self, didConnect: id, name: peripheral.name)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: id)
        peripheralDelegates.removeValue(forKey: id)
        delegate?.bleManager(self, didDisconnect: id)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.bleManager(self, didError: "Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - PeripheralDelegate

/// Handles per-peripheral GATT operations (service/characteristic discovery, read, write, notify).
class PeripheralDelegate: NSObject, CBPeripheralDelegate {
    weak var manager: BLEManager?
    let deviceId: String
    private var characteristics: [String: CBCharacteristic] = [:]
    private var pendingServiceCount: Int = 0

    init(manager: BLEManager, deviceId: String) {
        self.manager = manager
        self.deviceId = deviceId
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            guard let manager = manager else { return }
            manager.delegate?.bleManager(manager, didServicesReady: deviceId)
            return
        }
        pendingServiceCount = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let chars = service.characteristics {
            for char in chars {
                let key = "\(service.uuid.uuidString.lowercased()):\(char.uuid.uuidString.lowercased())"
                characteristics[key] = char
            }
        }
        pendingServiceCount -= 1
        if pendingServiceCount <= 0 {
            guard let manager = manager else { return }
            manager.delegate?.bleManager(manager, didServicesReady: deviceId)
        }
    }

    func readCharacteristic(serviceUUID: String, characteristicUUID: String) {
        let key = "\(serviceUUID.lowercased()):\(characteristicUUID.lowercased())"
        guard let char = characteristics[key],
              let peripheral = char.service?.peripheral else {
            guard let manager = manager else { return }
            manager.delegate?.bleManager(manager, didError: "Characteristic not found: \(characteristicUUID)")
            return
        }
        peripheral.readValue(for: char)
    }

    func setNotify(_ enabled: Bool, serviceUUID: String, characteristicUUID: String) {
        let key = "\(serviceUUID.lowercased()):\(characteristicUUID.lowercased())"
        guard let char = characteristics[key],
              let peripheral = char.service?.peripheral else {
            guard let manager = manager else { return }
            manager.delegate?.bleManager(manager, didError: "Characteristic not found: \(characteristicUUID)")
            return
        }
        peripheral.setNotifyValue(enabled, for: char)
    }

    func writeCharacteristic(serviceUUID: String, characteristicUUID: String, value: Data) {
        let key = "\(serviceUUID.lowercased()):\(characteristicUUID.lowercased())"
        guard let char = characteristics[key],
              let peripheral = char.service?.peripheral else {
            guard let manager = manager else { return }
            manager.delegate?.bleManager(manager, didError: "Characteristic not found: \(characteristicUUID)")
            return
        }
        let type: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(value, for: char, type: type)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let manager = manager else { return }
        manager.delegate?.bleManager(
            manager,
            didReceiveData: data,
            characteristicUUID: characteristic.uuid.uuidString,
            deviceId: deviceId
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error, let manager = manager {
            manager.delegate?.bleManager(manager, didError: "Write failed: \(error.localizedDescription)")
        }
    }
}
