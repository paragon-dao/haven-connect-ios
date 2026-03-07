import SwiftUI

/// Native health data summary screen.
///
/// Shows recent health readings written to HealthKit through Haven Connect.
/// This is one of the required native UI screens (not a WebView) for
/// App Store guideline 4.2 compliance.
struct HealthSummaryView: View {
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        NavigationView {
            Group {
                if !healthKit.isAvailable {
                    unavailableView
                } else if !healthKit.isAuthorized {
                    authorizationView
                } else if healthKit.recentSamples.isEmpty {
                    emptyView
                } else {
                    samplesList
                }
            }
            .navigationTitle("Health")
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("HealthKit Not Available")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var authorizationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.6))
            Text("Connect to Apple Health")
                .font(.system(size: 20, weight: .semibold))
            Text("Haven Connect writes heart rate, HRV, and SpO2 data\nfrom your BLE devices directly to Apple Health.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { healthKit.requestAuthorization() }) {
                Text("Enable HealthKit")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Health Data Yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
            Text("Connect a BLE health device through a\nParagon network app to start recording.")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var samplesList: some View {
        List {
            // Latest readings section
            if let latestHR = latestSample(label: "Heart Rate"),
               let latestSpO2 = latestSample(label: "SpO2") {
                Section("Current") {
                    HStack {
                        StatCard(
                            icon: "heart.fill",
                            color: .red,
                            value: String(format: "%.0f", latestHR.value),
                            unit: latestHR.unit,
                            label: "Heart Rate"
                        )
                        StatCard(
                            icon: "lungs.fill",
                            color: .blue,
                            value: String(format: "%.0f", latestSpO2.value),
                            unit: latestSpO2.unit,
                            label: "SpO2"
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            // All recent samples
            Section("Recent Readings") {
                ForEach(healthKit.recentSamples) { sample in
                    HStack {
                        Image(systemName: iconForLabel(sample.label))
                            .foregroundColor(colorForLabel(sample.label))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.label)
                                .font(.system(size: 14, weight: .medium))
                            Text(sample.date, style: .relative)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", sample.value)) \(sample.unit)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(colorForLabel(sample.label))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            healthKit.fetchRecentSamples()
        }
    }

    private func latestSample(label: String) -> HealthSample? {
        healthKit.recentSamples.first { $0.label == label }
    }

    private func iconForLabel(_ label: String) -> String {
        switch label {
        case "Heart Rate": return "heart.fill"
        case "HRV": return "waveform.path.ecg"
        case "SpO2": return "lungs.fill"
        case "Respiratory Rate": return "wind"
        default: return "circle.fill"
        }
    }

    private func colorForLabel(_ label: String) -> Color {
        switch label {
        case "Heart Rate": return .red
        case "HRV": return .purple
        case "SpO2": return .blue
        case "Respiratory Rate": return .teal
        default: return .gray
        }
    }
}

/// Small stat card for the "Current" section.
struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(4)
    }
}
