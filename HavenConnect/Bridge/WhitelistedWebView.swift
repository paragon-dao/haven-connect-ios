import SwiftUI
import WebKit

/// WKWebView that only loads whitelisted Paragon network URLs.
///
/// Security model (per panel verdict):
/// - Polyfill ONLY injected on approved domains (AppRegistry.allowedHosts)
/// - Navigation to non-whitelisted URLs is blocked
/// - BLE data from GATT health profiles is automatically written to HealthKit
struct WhitelistedWebView: UIViewRepresentable {
    let url: String
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var healthKit: HealthKitManager

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Inject Web Bluetooth polyfill
        let script = WKUserScript(
            source: WebBluetoothPolyfill.javascript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        let weakHandler = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(weakHandler, name: "havenBLE")

        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Load the approved URL
        if let loadURL = URL(string: url) {
            webView.load(URLRequest(url: loadURL))
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No URL bar updates — URL is fixed from the launcher
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(deviceManager: deviceManager, healthKit: healthKit)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let deviceManager: DeviceManager
        let healthKit: HealthKitManager
        var webView: WKWebView?
        let bleManager = BLEManager()

        // Accumulate RR intervals for HRV calculation
        private var rrAccumulator: [Double] = []
        private var lastHRVWrite: Date = .distantPast

        init(deviceManager: DeviceManager, healthKit: HealthKitManager) {
            self.deviceManager = deviceManager
            self.healthKit = healthKit
            super.init()
            bleManager.delegate = self

            // Wire up disconnect requests from the Devices tab
            deviceManager.onDisconnectRequest = { [weak self] deviceId in
                self?.bleManager.disconnect(deviceId: deviceId)
            }
        }

        // MARK: - WKNavigationDelegate

        /// Block navigation to non-whitelisted URLs.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                if AppRegistry.isAllowed(url) {
                    decisionHandler(.allow)
                } else {
                    // Open external URLs in Safari instead
                    if navigationAction.navigationType == .linkActivated {
                        UIApplication.shared.open(url)
                    }
                    decisionHandler(.cancel)
                }
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // No URL bar to update — intentionally empty
        }

        // MARK: - WKScriptMessageHandler (BLE Bridge)

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "requestDevice":
                let filters = body["filters"] as? [[String: Any]]
                bleManager.requestDevice(filters: filters)

            case "connect":
                if let deviceId = body["deviceId"] as? String {
                    bleManager.connect(deviceId: deviceId)
                }

            case "disconnect":
                if let deviceId = body["deviceId"] as? String {
                    bleManager.disconnect(deviceId: deviceId)
                }

            case "readCharacteristic":
                if let deviceId = body["deviceId"] as? String,
                   let serviceUUID = body["serviceUUID"] as? String,
                   let charUUID = body["characteristicUUID"] as? String {
                    bleManager.readCharacteristic(deviceId: deviceId, serviceUUID: serviceUUID, characteristicUUID: charUUID)
                }

            case "startNotifications":
                if let deviceId = body["deviceId"] as? String,
                   let serviceUUID = body["serviceUUID"] as? String,
                   let charUUID = body["characteristicUUID"] as? String {
                    bleManager.startNotifications(deviceId: deviceId, serviceUUID: serviceUUID, characteristicUUID: charUUID)
                }

            case "stopNotifications":
                if let deviceId = body["deviceId"] as? String,
                   let serviceUUID = body["serviceUUID"] as? String,
                   let charUUID = body["characteristicUUID"] as? String {
                    bleManager.stopNotifications(deviceId: deviceId, serviceUUID: serviceUUID, characteristicUUID: charUUID)
                }

            case "writeCharacteristic":
                if let deviceId = body["deviceId"] as? String,
                   let serviceUUID = body["serviceUUID"] as? String,
                   let charUUID = body["characteristicUUID"] as? String,
                   let value = body["value"] as? [UInt8] {
                    bleManager.writeCharacteristic(
                        deviceId: deviceId,
                        serviceUUID: serviceUUID,
                        characteristicUUID: charUUID,
                        value: Data(value)
                    )
                }

            default:
                break
            }
        }

        // MARK: - HealthKit auto-write from BLE data

        /// Automatically write recognized BLE health data to HealthKit.
        private func processHealthData(serviceUUID: String, characteristicUUID: String, data: Data) {
            guard let dataType = GATTProfiles.identifyCharacteristic(
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID
            ) else { return }

            switch dataType {
            case .heartRate:
                if let reading = GATTProfiles.parseHeartRate(data: data) {
                    healthKit.writeHeartRate(bpm: Double(reading.bpm))

                    // Accumulate RR intervals for HRV
                    rrAccumulator.append(contentsOf: reading.rrIntervals)
                    // Write HRV every 30 seconds if we have enough data
                    if rrAccumulator.count >= 5,
                       Date().timeIntervalSince(lastHRVWrite) >= 30 {
                        let mean = rrAccumulator.reduce(0, +) / Double(rrAccumulator.count)
                        let variance = rrAccumulator.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rrAccumulator.count)
                        let sdnn = variance.squareRoot()
                        healthKit.writeHRV(ms: sdnn)
                        rrAccumulator.removeAll()
                        lastHRVWrite = Date()
                    }
                }

            case .spo2:
                if let spo2 = GATTProfiles.parseSpO2(data: data) {
                    healthKit.writeSpO2(percentage: spo2)
                }

            case .temperature, .battery:
                break // Not writing these to HealthKit yet
            }
        }
    }
}

// MARK: - BLEManagerDelegate

extension WhitelistedWebView.Coordinator: BLEManagerDelegate {
    func bleManager(_ manager: BLEManager, didDiscoverDevice device: BLEDevice) {
        let js = "window.__havenBLE.onDeviceDiscovered({id:\(escapeJS(device.id)),name:\(escapeJS(device.name ?? "Unknown")),rssi:\(device.rssi)});"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didConnect deviceId: String, name: String?) {
        let js = "window.__havenBLE.onConnected(\(escapeJS(deviceId)));"
        DispatchQueue.main.async {
            self.deviceManager.addDevice(id: deviceId, name: name ?? deviceId)
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didDisconnect deviceId: String) {
        let js = "window.__havenBLE.onDisconnected(\(escapeJS(deviceId)));"
        DispatchQueue.main.async {
            self.deviceManager.removeDevice(id: deviceId)
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didServicesReady deviceId: String) {
        let js = "window.__havenBLE.onServicesReady(\(escapeJS(deviceId)));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didReceiveData data: Data, characteristicUUID: String, deviceId: String) {
        let bytes = Array(data)
        let js = "window.__havenBLE.onCharacteristicValueChanged(\(escapeJS(deviceId)),\(escapeJS(characteristicUUID)),new Uint8Array([\(bytes.map(String.init).joined(separator: ","))]));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
        }

        // Auto-write to HealthKit if this is a recognized health characteristic
        // We need the service UUID — use a best-guess based on the characteristic
        let serviceGuess: String
        let charUpper = characteristicUUID.uppercased()
        if charUpper.contains("2A37") { serviceGuess = "180D" }
        else if charUpper.contains("2A5E") { serviceGuess = "1822" }
        else if charUpper.contains("2A1C") { serviceGuess = "1809" }
        else if charUpper.contains("2A19") { serviceGuess = "180F" }
        else { serviceGuess = "" }

        if !serviceGuess.isEmpty {
            processHealthData(serviceUUID: serviceGuess, characteristicUUID: characteristicUUID, data: data)
        }
    }

    func bleManager(_ manager: BLEManager, didReadValue data: Data, characteristicUUID: String, deviceId: String) {
        bleManager(manager, didReceiveData: data, characteristicUUID: characteristicUUID, deviceId: deviceId)
    }

    func bleManager(_ manager: BLEManager, didError error: String) {
        let js = "window.__havenBLE.onError(\(escapeJS(error)));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
        }
    }

    private func escapeJS(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        escaped = escaped.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        escaped = escaped.replacingOccurrences(of: "</", with: "<\\/")
        return "'\(escaped)'"
    }
}

// MARK: - WeakScriptMessageHandler

/// Prevents the WKUserContentController retain cycle.
/// WKUserContentController holds message handlers strongly. Without this wrapper,
/// the Coordinator (which holds the WKWebView) would never be deallocated.
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
