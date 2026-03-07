import SwiftUI

/// Main launcher — curated grid of Paragon network health apps.
///
/// This replaces the URL bar. Users tap an app card to launch it
/// inside Haven Connect with BLE bridging active.
struct LauncherView: View {
    @Binding var selectedApp: HealthApp?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Network status
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("Paragon Network")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(AppRegistry.apps.count) apps")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // App grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppRegistry.apps) { app in
                            AppCardView(app: app) {
                                selectedApp = app
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Haven Connect")
        }
    }
}

/// Card for a single health app in the launcher grid.
struct AppCardView: View {
    let app: HealthApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: app.iconSystemName)
                        .font(.system(size: 24))
                        .foregroundColor(categoryColor)
                        .frame(width: 40, height: 40)
                        .background(categoryColor.opacity(0.15))
                        .cornerRadius(10)

                    Spacer()

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(app.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(app.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(app.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.1))
                        .cornerRadius(4)
                    Spacer()
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch app.category {
        case .breathing: return .blue
        case .heartRate: return .red
        case .movement: return .green
        case .neural: return .purple
        }
    }
}
