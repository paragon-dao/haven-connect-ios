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
        let actions = ["readCharacteristic", "writeCharacteristic", "startNotifications", "stopNotifications"]
        for action in actions {
            XCTAssertTrue(js.contains("sendToNative('\(action)'"), "Must send \(action) to native")
        }
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
        XCTAssertTrue(js.contains("value instanceof ArrayBuffer"), "Must handle ArrayBuffer input to writeValue")
        XCTAssertTrue(js.contains("value.buffer"), "Must handle DataView input to writeValue")
    }

    func testPolyfillUsesMapForPendingRequests() {
        XCTAssertTrue(js.contains("new Map()"), "Must use Map for pending requests, not plain object")
    }

    func testPolyfillUsesDOMExceptionForErrors() {
        XCTAssertTrue(js.contains("DOMException"), "Must use DOMException for errors per Web Bluetooth spec")
    }

    func testPolyfillWrapsNativeBridgeInTryCatch() {
        XCTAssertTrue(js.contains("try {") && js.contains("window.webkit.messageHandlers"), "Must wrap native bridge calls in try-catch")
    }

    // MARK: - Promise Timeout

    func testPolyfillDefinesRequestTimeout() {
        XCTAssertTrue(js.contains("REQUEST_TIMEOUT_MS"), "Must define a request timeout constant")
    }

    func testPolyfillTimesOutPendingRequests() {
        XCTAssertTrue(js.contains("setTimeout"), "Must use setTimeout for request timeouts")
        XCTAssertTrue(js.contains("TimeoutError"), "Must use TimeoutError DOMException for timeouts")
    }

    func testPolyfillClearsTimeoutOnResolve() {
        XCTAssertTrue(js.contains("clearTimeout"), "Must clear timeout when request resolves")
    }

    // MARK: - Service Discovery Gating

    func testPolyfillTracksServicesReady() {
        XCTAssertTrue(js.contains("servicesReady"), "Must track service discovery completion state")
    }

    func testPolyfillImplementsOnServicesReady() {
        XCTAssertTrue(js.contains("onServicesReady"), "Must handle onServicesReady callback from native")
    }

    func testPolyfillGatesPrimaryServiceOnDiscovery() {
        // getPrimaryService should wait for services to be discovered
        XCTAssertTrue(js.contains("servicesReady[deviceId]"), "getPrimaryService must check if services are ready")
        XCTAssertTrue(js.contains("type: 'getPrimaryService'"), "Must queue getPrimaryService as pending if not ready")
    }

    // MARK: - Error Recovery

    func testPolyfillRejectsPendingOnDisconnect() {
        // When a device disconnects, all pending requests for that device should be rejected
        XCTAssertTrue(js.contains("Device disconnected"), "Must reject pending requests on disconnect with clear message")
    }

    func testPolyfillRoutesErrorsByType() {
        // Error routing should attempt to match errors to the right request type
        XCTAssertTrue(js.contains("error.indexOf('connect')") || js.contains("error.indexOf('Connection')"),
                       "Must attempt to route connection errors to connect requests")
        XCTAssertTrue(js.contains("error.indexOf('Characteristic')"),
                       "Must attempt to route characteristic errors to read/write requests")
    }

    func testPolyfillClearsServicesReadyOnDisconnect() {
        XCTAssertTrue(js.contains("servicesReady[deviceId] = false"), "Must clear servicesReady on disconnect")
    }
}
