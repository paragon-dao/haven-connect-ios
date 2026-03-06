import XCTest
@testable import HavenConnect

/// Tests for the Web Bluetooth polyfill JavaScript code.
/// These verify the polyfill string is well-formed and contains
/// all required Web Bluetooth API surface.
final class WebBluetoothPolyfillTests: XCTestCase {

    let js = WebBluetoothPolyfill.javascript

    // MARK: - Polyfill Structure

    func testPolyfillIsNotEmpty() {
        XCTAssertFalse(js.isEmpty, "Polyfill JavaScript must not be empty")
    }

    func testPolyfillIsWrappedInIIFE() {
        XCTAssertTrue(js.hasPrefix("(function()"), "Polyfill must be wrapped in an IIFE")
        XCTAssertTrue(js.hasSuffix("})();"), "Polyfill IIFE must be self-invoking")
    }

    func testPolyfillUsesStrictMode() {
        XCTAssertTrue(js.contains("'use strict'"), "Polyfill must use strict mode")
    }

    // MARK: - Web Bluetooth API Surface

    func testPolyfillInstallsNavigatorBluetooth() {
        XCTAssertTrue(js.contains("navigator.bluetooth ="), "Must install navigator.bluetooth")
    }

    func testPolyfillImplementsRequestDevice() {
        XCTAssertTrue(js.contains("requestDevice"), "Must implement requestDevice")
    }

    func testPolyfillImplementsGetAvailability() {
        XCTAssertTrue(js.contains("getAvailability"), "Must implement getAvailability")
    }

    func testPolyfillImplementsGATTConnect() {
        XCTAssertTrue(js.contains("createGATTServer"), "Must implement GATT server creation")
    }

    func testPolyfillImplementsGetPrimaryService() {
        XCTAssertTrue(js.contains("getPrimaryService"), "Must implement getPrimaryService")
    }

    func testPolyfillImplementsCharacteristicRead() {
        XCTAssertTrue(js.contains("readValue"), "Must implement readValue")
    }

    func testPolyfillImplementsCharacteristicWrite() {
        XCTAssertTrue(js.contains("writeValue"), "Must implement writeValue")
    }

    func testPolyfillImplementsWriteValueWithResponse() {
        XCTAssertTrue(js.contains("writeValueWithResponse"), "Must implement writeValueWithResponse per spec")
    }

    func testPolyfillImplementsWriteValueWithoutResponse() {
        XCTAssertTrue(js.contains("writeValueWithoutResponse"), "Must implement writeValueWithoutResponse per spec")
    }

    func testPolyfillImplementsStartNotifications() {
        XCTAssertTrue(js.contains("startNotifications"), "Must implement startNotifications")
    }

    func testPolyfillImplementsStopNotifications() {
        XCTAssertTrue(js.contains("stopNotifications"), "Must implement stopNotifications")
    }

    func testPolyfillImplementsAddEventListener() {
        XCTAssertTrue(js.contains("addEventListener"), "Must implement addEventListener")
    }

    func testPolyfillImplementsRemoveEventListener() {
        XCTAssertTrue(js.contains("removeEventListener"), "Must implement removeEventListener")
    }

    func testPolyfillImplementsDisconnectEvent() {
        XCTAssertTrue(js.contains("gattserverdisconnected"), "Must dispatch gattserverdisconnected event")
    }

    func testPolyfillImplementsCharacteristicValueChanged() {
        XCTAssertTrue(js.contains("characteristicvaluechanged"), "Must handle characteristicvaluechanged event")
    }

    // MARK: - Native Bridge

    func testPolyfillUsesCorrectMessageHandler() {
        XCTAssertTrue(js.contains("window.webkit.messageHandlers.havenBLE"), "Must use havenBLE message handler")
    }

    func testPolyfillPassesDeviceIdInAllActions() {
        // All BLE operations must include deviceId to target the correct peripheral
        let actions = ["readCharacteristic", "writeCharacteristic", "startNotifications", "stopNotifications"]
        for action in actions {
            // Find the sendToNative call for this action and verify deviceId is included
            XCTAssertTrue(js.contains("sendToNative('\(action)'"), "Must send \(action) to native")
        }
        // Verify deviceId is passed in characteristic operations
        let deviceIdOccurrences = js.components(separatedBy: "deviceId: deviceId").count - 1
        XCTAssertGreaterThanOrEqual(deviceIdOccurrences, 6, "deviceId must be passed in connect, disconnect, read, write, startNotify, stopNotify")
    }

    // MARK: - Security

    func testPolyfillDoesNotOverwriteNativeBluetooth() {
        XCTAssertTrue(js.contains("if (navigator.bluetooth) return"), "Must not overwrite native Web Bluetooth if present")
    }

    func testPolyfillSetsIdentifier() {
        XCTAssertTrue(js.contains("_polyfill: 'haven-connect'"), "Must identify itself as haven-connect polyfill")
    }

    func testPolyfillHandlesArrayBufferAndDataView() {
        // writeValue must handle both ArrayBuffer and DataView (BufferSource per spec)
        XCTAssertTrue(js.contains("value instanceof ArrayBuffer"), "Must handle ArrayBuffer input to writeValue")
        XCTAssertTrue(js.contains("value.buffer"), "Must handle DataView input to writeValue")
    }

    func testPolyfillUsesMapForPendingRequests() {
        // Map provides proper iteration order (insertion order) and O(1) delete
        XCTAssertTrue(js.contains("new Map()"), "Must use Map for pending requests, not plain object")
    }

    func testPolyfillUsesDOMExceptionForErrors() {
        XCTAssertTrue(js.contains("DOMException"), "Must use DOMException for errors per Web Bluetooth spec")
    }

    func testPolyfillWrapsNativeBridgeInTryCatch() {
        XCTAssertTrue(js.contains("try {") && js.contains("window.webkit.messageHandlers"), "Must wrap native bridge calls in try-catch")
    }
}
