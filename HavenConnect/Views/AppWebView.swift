import SwiftUI

/// Full-screen web view for a launched health app.
///
/// Replaces the old BrowserView. No URL bar. Shows only the
/// approved app with a back button to return to the launcher.
/// BLE polyfill is injected only because this URL is whitelisted.
struct AppWebView: View {
    let app: HealthApp
    let onDismiss: () -> Void
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        VStack(spacing: 0) {
            // App header bar (native, not web)
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Apps")
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.blue)
                }

                Spacer()

                Text(app.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                // Connection indicator
                if !deviceManager.connectedDevices.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("\(deviceManager.connectedDevices.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                } else {
                    // Spacer to balance the back button
                    Text("Apps")
                        .font(.system(size: 15))
                        .foregroundColor(.clear)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))

            Divider()

            // Web content — whitelisted URL only
            WhitelistedWebView(
                url: app.url,
                deviceManager: deviceManager,
                healthKit: healthKit
            )
        }
    }
}
