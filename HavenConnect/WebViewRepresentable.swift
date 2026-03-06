import SwiftUI
import WebKit

/// WKWebView wrapper that injects the Web Bluetooth polyfill.
///
/// Uses Apple's own WKWebView (WebKit engine) + CoreBluetooth.
/// The polyfill intercepts navigator.bluetooth calls from web pages
/// and routes them through the native BLE bridge.
struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Inject Web Bluetooth polyfill before page loads
        let polyfill = WebBluetoothPolyfill.javascript
        let script = WKUserScript(
            source: polyfill,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        // Use a weak message handler wrapper to avoid WKUserContentController retain cycle.
        // WKUserContentController retains its message handlers strongly, which creates a
        // retain cycle: WKWebView -> config -> contentController -> coordinator -> webView.
        let weakHandler = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(weakHandler, name: "havenBLE")

        // Allow media (microphone for breathing capture)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Load default URL
        if let url = URL(string: viewModel.urlText) {
            webView.load(URLRequest(url: url))
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only navigate when the user explicitly submitted a new URL.
        // This prevents loops: didFinish updates urlText -> updateUIView fires -> re-navigates.
        guard viewModel.navigationRequested else { return }
        viewModel.navigationRequested = false

        var urlString = viewModel.urlText
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var viewModel: BrowserViewModel
        var webView: WKWebView?
        let bleManager = BLEManager()

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
            super.init()
            bleManager.delegate = self
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                if let url = webView.url {
                    self.viewModel.urlText = url.absoluteString
                    self.viewModel.isSecure = url.scheme == "https"
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
            }
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

// MARK: - BLEManagerDelegate

extension WebViewRepresentable.Coordinator: BLEManagerDelegate {
    func bleManager(_ manager: BLEManager, didDiscoverDevice device: BLEDevice) {
        let js = """
        window.__havenBLE.onDeviceDiscovered({
            id: \(escapeJS(device.id)),
            name: \(escapeJS(device.name ?? "Unknown")),
            rssi: \(device.rssi)
        });
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didConnect deviceId: String, name: String?) {
        let js = "window.__havenBLE.onConnected(\(escapeJS(deviceId)));"
        DispatchQueue.main.async {
            self.viewModel.connectedDeviceName = name ?? deviceId
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didDisconnect deviceId: String) {
        let js = "window.__havenBLE.onDisconnected(\(escapeJS(deviceId)));"
        DispatchQueue.main.async {
            self.viewModel.connectedDeviceName = nil
            self.webView?.evaluateJavaScript(js)
        }
    }

    func bleManager(_ manager: BLEManager, didReceiveData data: Data, characteristicUUID: String, deviceId: String) {
        let bytes = Array(data)
        let js = """
        window.__havenBLE.onCharacteristicValueChanged(
            \(escapeJS(deviceId)),
            \(escapeJS(characteristicUUID)),
            new Uint8Array([\(bytes.map(String.init).joined(separator: ","))])
        );
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js)
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

    /// Escape a string for safe interpolation into JavaScript.
    /// Prevents XSS from malicious BLE device names or error messages.
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
