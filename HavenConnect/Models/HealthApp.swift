import Foundation

/// A health app in the Paragon network that Haven Connect can launch.
///
/// Every app in Haven Connect requires a BLE device. If it works
/// without Bluetooth, it belongs in Safari, not here.
struct HealthApp: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let url: String
    let iconSystemName: String
    let category: Category

    enum Category: String, Codable, CaseIterable {
        case breathing = "Breathing"
        case heartRate = "Heart Rate"
        case movement = "Movement"
        case neural = "Neural"

        var color: String {
            switch self {
            case .breathing: return "blue"
            case .heartRate: return "red"
            case .movement: return "green"
            case .neural: return "purple"
            }
        }
    }
}
