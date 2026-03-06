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

            // BLE status bar
            if let deviceName = viewModel.connectedDeviceName {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Connected: \(deviceName)")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Spacer()
                    Button("Disconnect") { viewModel.disconnectDevice() }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
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

class BrowserViewModel: ObservableObject {
    @Published var urlText: String = "https://paragondao.org"
    @Published var isLoading: Bool = false
    @Published var isSecure: Bool = true
    @Published var connectedDeviceName: String? = nil
    @Published var navigationRequested: Bool = false

    func navigate() {
        navigationRequested = true
        objectWillChange.send()
    }

    func disconnectDevice() {
        connectedDeviceName = nil
        objectWillChange.send()
    }
}
