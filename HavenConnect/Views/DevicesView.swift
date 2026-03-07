import SwiftUI

/// Native device management screen.
///
/// Shows all connected BLE devices with status, signal strength,
/// and disconnect controls. This is one of the required native UI
/// screens for App Store approval (not a WebView).
struct DevicesView: View {
    @ObservedObject var deviceManager: DeviceManager

    var body: some View {
        NavigationView {
            Group {
                if deviceManager.connectedDevices.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Devices Connected")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Open a health experience from the Apps tab\nand pair a Bluetooth device to get started.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        Section {
                            ForEach(deviceManager.connectedDevices) { device in
                                DeviceRow(device: device) {
                                    deviceManager.requestDisconnect(deviceId: device.id)
                                }
                            }
                        } header: {
                            Text("Connected")
                        } footer: {
                            Text("Devices paired through health apps in the Paragon network.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Devices")
        }
    }
}

struct DeviceRow: View {
    let device: ManagedDevice
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 15, weight: .medium))
                Text("Connected")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }

            Spacer()

            Button("Disconnect") {
                onDisconnect()
            }
            .font(.system(size: 13))
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

/// Tracks connected BLE devices across the app.
class DeviceManager: ObservableObject {
    @Published var connectedDevices: [ManagedDevice] = []

    /// Callback to tell the web bridge to disconnect
    var onDisconnectRequest: ((String) -> Void)?

    func addDevice(id: String, name: String) {
        if !connectedDevices.contains(where: { $0.id == id }) {
            connectedDevices.append(ManagedDevice(id: id, name: name))
        }
    }

    func removeDevice(id: String) {
        connectedDevices.removeAll { $0.id == id }
    }

    func requestDisconnect(deviceId: String) {
        onDisconnectRequest?(deviceId)
    }
}

struct ManagedDevice: Identifiable {
    let id: String
    let name: String
}
