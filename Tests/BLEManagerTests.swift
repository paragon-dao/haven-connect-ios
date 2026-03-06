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

    // MARK: - BrowserViewModel

    func testViewModelDefaultState() {
        let vm = BrowserViewModel()
        XCTAssertEqual(vm.urlText, "https://paragondao.org")
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.isSecure)
        XCTAssertNil(vm.connectedDeviceName)
        XCTAssertFalse(vm.navigationRequested)
        XCTAssertTrue(vm.connectedDevices.isEmpty)
        XCTAssertNil(vm.disconnectRequested)
    }

    func testViewModelNavigateSetsFlag() {
        let vm = BrowserViewModel()
        vm.navigate()
        XCTAssertTrue(vm.navigationRequested)
    }

    // MARK: - Multi-Peripheral Management

    func testViewModelAddConnectedDevice() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        XCTAssertEqual(vm.connectedDevices.count, 1)
        XCTAssertEqual(vm.connectedDevices[0].id, "device-1")
        XCTAssertEqual(vm.connectedDevices[0].name, "Polar H10")
    }

    func testViewModelAddMultipleDevices() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        vm.addConnectedDevice(id: "device-2", name: "Muse S")
        XCTAssertEqual(vm.connectedDevices.count, 2)
    }

    func testViewModelNoDuplicateDevices() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        XCTAssertEqual(vm.connectedDevices.count, 1, "Should not add duplicate device")
    }

    func testViewModelRemoveConnectedDevice() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        vm.addConnectedDevice(id: "device-2", name: "Muse S")
        vm.removeConnectedDevice(id: "device-1")
        XCTAssertEqual(vm.connectedDevices.count, 1)
        XCTAssertEqual(vm.connectedDevices[0].id, "device-2")
    }

    func testViewModelRemoveNonexistentDeviceIsNoOp() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        vm.removeConnectedDevice(id: "nonexistent")
        XCTAssertEqual(vm.connectedDevices.count, 1)
    }

    func testViewModelConnectedDeviceNameReturnsFirst() {
        let vm = BrowserViewModel()
        vm.addConnectedDevice(id: "device-1", name: "Polar H10")
        vm.addConnectedDevice(id: "device-2", name: "Muse S")
        XCTAssertEqual(vm.connectedDeviceName, "Polar H10")
    }

    func testViewModelConnectedDeviceNameNilWhenEmpty() {
        let vm = BrowserViewModel()
        XCTAssertNil(vm.connectedDeviceName)
    }

    func testViewModelRequestDisconnect() {
        let vm = BrowserViewModel()
        vm.requestDisconnect(deviceId: "device-1")
        XCTAssertEqual(vm.disconnectRequested, "device-1")
    }

    // MARK: - ConnectedDevice

    func testConnectedDeviceIdentifiable() {
        let d1 = ConnectedDevice(id: "abc", name: "Test")
        let d2 = ConnectedDevice(id: "abc", name: "Different Name")
        XCTAssertEqual(d1.id, d2.id)
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
