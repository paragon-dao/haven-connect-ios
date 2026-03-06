import SwiftUI

@main
struct HavenConnectApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .preferredColorScheme(.dark)
        }
    }
}
