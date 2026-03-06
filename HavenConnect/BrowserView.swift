import SwiftUI

/// Main browser view — URL bar + WKWebView with BLE bridge.
///
/// This is NOT a general-purpose browser. It's a health companion
/// that connects BLE medical devices to web-based health apps.
struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // URL bar
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(viewModel.isSecure ? .green : .gray)
                    .font(.system(size: 12))

                TextField("Enter health app URL", text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit { viewModel.navigate() }

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button(action: { viewModel.navigate() }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            // BLE status bar — shows all connected devices
            if !viewModel.connectedDevices.isEmpty {
                VStack(spacing: 2) {
                    ForEach(viewModel.connectedDevices, id: \.id) { device in
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                            Text(device.name)
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .lineLimit(1)
                            Spacer()
                            Button("Disconnect") {
                                viewModel.requestDisconnect(deviceId: device.id)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
            }

            // Web content
            WebViewRepresentable(viewModel: viewModel)
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct ConnectedDevice: Identifiable {
    let id: String
    let name: String
}

class BrowserViewModel: ObservableObject {
    @Published var urlText: String = "https://paragondao.org"
    @Published var isLoading: Bool = false
    @Published var isSecure: Bool = true
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var navigationRequested: Bool = false
    @Published var disconnectRequested: String? = nil

    // Legacy computed property for backward compatibility with status checks
    var connectedDeviceName: String? {
        connectedDevices.first?.name
    }

    func navigate() {
        navigationRequested = true
        objectWillChange.send()
    }

    func addConnectedDevice(id: String, name: String) {
        if !connectedDevices.contains(where: { $0.id == id }) {
            connectedDevices.append(ConnectedDevice(id: id, name: name))
        }
    }

    func removeConnectedDevice(id: String) {
        connectedDevices.removeAll { $0.id == id }
    }

    func requestDisconnect(deviceId: String) {
        disconnectRequested = deviceId
        objectWillChange.send()
    }
}
