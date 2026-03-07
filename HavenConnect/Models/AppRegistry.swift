import Foundation

/// Registry of approved Paragon network health apps.
///
/// Only apps in this registry can be launched in Haven Connect.
/// This is the whitelist — the polyfill only injects on these domains.
enum AppRegistry {

    /// All approved health apps in the Paragon network.
    ///
    /// RULE: Every app MUST require BLE. If it works in Safari without
    /// a Bluetooth device, it doesn't belong here. The BLE bridge is
    /// Haven Connect's reason to exist — without it, Apple asks
    /// "why isn't this in Safari?" and rejects us under Guideline 4.2.
    static let apps: [HealthApp] = [
        HealthApp(
            id: "heart-rate-monitor",
            name: "Heart Rate Monitor",
            description: "Connect a BLE heart rate strap to track HR and HRV in real time. Data syncs to Apple Health automatically.",
            url: "https://apps.paragondao.org/heartrate",
            iconSystemName: "heart.fill",
            category: .heartRate,

        ),
        HealthApp(
            id: "motion-gait",
            name: "Gait Analysis",
            description: "Pair a BLE motion sensor to analyze walking patterns, stride symmetry, and fall risk over time.",
            url: "https://apps.paragondao.org/gait",
            iconSystemName: "figure.walk",
            category: .movement,

        ),
        HealthApp(
            id: "pulse-oximeter",
            name: "Pulse Oximeter",
            description: "Connect a BLE pulse oximeter to monitor SpO2 and heart rate. Data syncs to Apple Health automatically.",
            url: "https://apps.paragondao.org/spo2",
            iconSystemName: "lungs.fill",
            category: .heartRate,

        ),
        HealthApp(
            id: "breathing-coherence",
            name: "Breathing Coherence",
            description: "Pair a BLE heart rate strap to measure breath-heart coherence in real time. Guided breathing with biofeedback.",
            url: "https://apps.paragondao.org/breathing",
            iconSystemName: "wind",
            category: .breathing,

        ),
    ]

    /// Allowed URL hosts — only these domains get the BLE polyfill injected.
    static let allowedHosts: Set<String> = {
        var hosts = Set<String>()
        for app in apps {
            if let url = URL(string: app.url), let host = url.host {
                hosts.insert(host)
            }
        }
        return hosts
    }()

    /// Check if a URL is in the approved whitelist.
    static func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return allowedHosts.contains(host)
    }
}
