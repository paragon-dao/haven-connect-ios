import SwiftUI

@main
struct HavenConnectApp: App {
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var healthKit = HealthKitManager()
    @State private var selectedApp: HealthApp?

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main tab interface
                TabView {
                    LauncherView(selectedApp: $selectedApp)
                        .tabItem {
                            Image(systemName: "square.grid.2x2")
                            Text("Apps")
                        }

                    DevicesView(deviceManager: deviceManager)
                        .tabItem {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Devices")
                        }

                    HealthSummaryView(healthKit: healthKit)
                        .tabItem {
                            Image(systemName: "heart.text.square")
                            Text("Health")
                        }
                }
                .preferredColorScheme(.dark)

                // Full-screen app overlay when a health app is launched
                if let app = selectedApp {
                    AppWebView(
                        app: app,
                        onDismiss: { selectedApp = nil },
                        deviceManager: deviceManager,
                        healthKit: healthKit
                    )
                    .transition(.move(edge: .trailing))
                    .preferredColorScheme(.dark)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedApp != nil)
            .onAppear {
                healthKit.requestAuthorization()
            }
        }
    }
}
