import XCTest
@testable import HavenConnect

/// Tests for BLEManager — verifies correct device targeting and delegate routing.
final class BLEManagerTests: XCTestCase {

    // MARK: - BLEDevice

    func testBLEDeviceStoresAllFields() {
        let device = BLEDevice(id: "ABC-123", name: "Polar H10", rssi: -65)
        XCTAssertEqual(device.id, "ABC-123")
        XCTAssertEqual(device.name, "Polar H10")
        XCTAssertEqual(device.rssi, -65)
    }

    func testBLEDeviceHandlesNilName() {
        let device = BLEDevice(id: "DEF-456", name: nil, rssi: -80)
        XCTAssertNil(device.name)
    }

    func testBLEDeviceHandlesExtremeRSSI() {
        let weak = BLEDevice(id: "1", name: nil, rssi: -127)
        let strong = BLEDevice(id: "2", name: nil, rssi: 0)
        XCTAssertEqual(weak.rssi, -127)
        XCTAssertEqual(strong.rssi, 0)
    }

    // MARK: - BLEManager Initialization

    func testBLEManagerDelegateStartsNil() {
        let manager = BLEManager()
        XCTAssertNil(manager.delegate)
    }

    func testBLEManagerAcceptsDelegate() {
        let manager = BLEManager()
        let mock = MockBLEManagerDelegate()
        manager.delegate = mock
        XCTAssertNotNil(manager.delegate)
    }

    func testBLEManagerConnectedDeviceIdsStartsEmpty() {
        let manager = BLEManager()
        XCTAssertTrue(manager.connectedDeviceIds.isEmpty)
    }

    // MARK: - PeripheralDelegate

    func testPeripheralDelegateStoresDeviceId() {
        let manager = BLEManager()
        let pd = PeripheralDelegate(manager: manager, deviceId: "test-device-123")
        XCTAssertEqual(pd.deviceId, "test-device-123")
    }

    func testPeripheralDelegateHoldsWeakManagerReference() {
        var manager: BLEManager? = BLEManager()
        let pd = PeripheralDelegate(manager: manager!, deviceId: "test")
        manager = nil
        // manager is weak — should be nil after deallocation
        XCTAssertNil(pd.manager)
    }

    // MARK: - DeviceManager

    func testDeviceManagerStartsEmpty() {
        let dm = DeviceManager()
        XCTAssertTrue(dm.connectedDevices.isEmpty)
    }

    func testDeviceManagerAddDevice() {
        let dm = DeviceManager()
        dm.addDevice(id: "device-1", name: "Polar H10")
        XCTAssertEqual(dm.connectedDevices.count, 1)
        XCTAssertEqual(dm.connectedDevices[0].id, "device-1")
        XCTAssertEqual(dm.connectedDevices[0].name, "Polar H10")
    }

    func testDeviceManagerAddMultipleDevices() {
        let dm = DeviceManager()
        dm.addDevice(id: "device-1", name: "Polar H10")
        dm.addDevice(id: "device-2", name: "Muse S")
        XCTAssertEqual(dm.connectedDevices.count, 2)
    }

    func testDeviceManagerNoDuplicateDevices() {
        let dm = DeviceManager()
        dm.addDevice(id: "device-1", name: "Polar H10")
        dm.addDevice(id: "device-1", name: "Polar H10")
        XCTAssertEqual(dm.connectedDevices.count, 1, "Should not add duplicate device")
    }

    func testDeviceManagerRemoveDevice() {
        let dm = DeviceManager()
        dm.addDevice(id: "device-1", name: "Polar H10")
        dm.addDevice(id: "device-2", name: "Muse S")
        dm.removeDevice(id: "device-1")
        XCTAssertEqual(dm.connectedDevices.count, 1)
        XCTAssertEqual(dm.connectedDevices[0].id, "device-2")
    }

    func testDeviceManagerRemoveNonexistentDeviceIsNoOp() {
        let dm = DeviceManager()
        dm.addDevice(id: "device-1", name: "Polar H10")
        dm.removeDevice(id: "nonexistent")
        XCTAssertEqual(dm.connectedDevices.count, 1)
    }

    func testDeviceManagerDisconnectCallback() {
        let dm = DeviceManager()
        var disconnectedId: String?
        dm.onDisconnectRequest = { id in disconnectedId = id }
        dm.requestDisconnect(deviceId: "device-1")
        XCTAssertEqual(disconnectedId, "device-1")
    }

    // MARK: - ManagedDevice

    func testManagedDeviceIdentifiable() {
        let d1 = ManagedDevice(id: "abc", name: "Test")
        let d2 = ManagedDevice(id: "abc", name: "Different Name")
        XCTAssertEqual(d1.id, d2.id)
    }

    // MARK: - AppRegistry

    func testAppRegistryHasApps() {
        XCTAssertGreaterThanOrEqual(AppRegistry.apps.count, 3, "Must have at least 3 apps for App Store review")
    }

    func testAppRegistryAllowsRegisteredHosts() {
        for app in AppRegistry.apps {
            let url = URL(string: app.url)!
            XCTAssertTrue(AppRegistry.isAllowed(url), "\(app.name) URL must be allowed")
        }
    }

    func testAppRegistryBlocksUnknownHosts() {
        let evil = URL(string: "https://evil.com/steal-data")!
        XCTAssertFalse(AppRegistry.isAllowed(evil), "Unknown hosts must be blocked")
    }

    func testAppRegistryBlocksGoogleDotCom() {
        let google = URL(string: "https://google.com")!
        XCTAssertFalse(AppRegistry.isAllowed(google), "google.com must be blocked")
    }

    // MARK: - GATT Profiles

    func testParseHeartRate8Bit() {
        // Flags: 0x00 (8-bit HR), HR: 72 bpm
        let data = Data([0x00, 72])
        let reading = GATTProfiles.parseHeartRate(data: data)
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.bpm, 72)
    }

    func testParseHeartRate16Bit() {
        // Flags: 0x01 (16-bit HR), HR: 300 bpm (little-endian: 0x2C, 0x01)
        let data = Data([0x01, 0x2C, 0x01])
        let reading = GATTProfiles.parseHeartRate(data: data)
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.bpm, 300)
    }

    func testParseHeartRateTooShort() {
        let data = Data([0x00])
        XCTAssertNil(GATTProfiles.parseHeartRate(data: data))
    }

    func testParseBatteryLevel() {
        let data = Data([85])
        XCTAssertEqual(GATTProfiles.parseBatteryLevel(data: data), 85)
    }

    func testIdentifyHeartRateCharacteristic() {
        let type = GATTProfiles.identifyCharacteristic(serviceUUID: "180D", characteristicUUID: "2A37")
        XCTAssertEqual(type, .heartRate)
    }

    func testIdentifySpO2Characteristic() {
        let type = GATTProfiles.identifyCharacteristic(serviceUUID: "1822", characteristicUUID: "2A5E")
        XCTAssertEqual(type, .spo2)
    }

    func testIdentifyUnknownCharacteristic() {
        let type = GATTProfiles.identifyCharacteristic(serviceUUID: "FFFF", characteristicUUID: "FFFF")
        XCTAssertNil(type)
    }
}

// MARK: - Mock Delegate

class MockBLEManagerDelegate: BLEManagerDelegate {
    var discoveredDevices: [BLEDevice] = []
    var connectedDeviceIds: [String] = []
    var disconnectedDeviceIds: [String] = []
    var receivedErrors: [String] = []
    var receivedData: [(Data, String, String)] = []
    var servicesReadyDeviceIds: [String] = []

    func bleManager(_ manager: BLEManager, didDiscoverDevice device: BLEDevice) {
        discoveredDevices.append(device)
    }

    func bleManager(_ manager: BLEManager, didConnect deviceId: String, name: String?) {
        connectedDeviceIds.append(deviceId)
    }

    func bleManager(_ manager: BLEManager, didDisconnect deviceId: String) {
        disconnectedDeviceIds.append(deviceId)
    }

    func bleManager(_ manager: BLEManager, didReceiveData data: Data, characteristicUUID: String, deviceId: String) {
        receivedData.append((data, characteristicUUID, deviceId))
    }

    func bleManager(_ manager: BLEManager, didReadValue data: Data, characteristicUUID: String, deviceId: String) {
        receivedData.append((data, characteristicUUID, deviceId))
    }

    func bleManager(_ manager: BLEManager, didServicesReady deviceId: String) {
        servicesReadyDeviceIds.append(deviceId)
    }

    func bleManager(_ manager: BLEManager, didError error: String) {
        receivedErrors.append(error)
    }
}
