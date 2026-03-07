import HealthKit
import Foundation

/// Manages HealthKit read/write for BLE health data.
///
/// Writes heart rate, HRV, and SpO2 samples from BLE devices
/// to Apple Health. This is the key native feature that justifies
/// Haven Connect's existence beyond a web wrapper.
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var recentSamples: [HealthSample] = []

    /// Types we write to HealthKit from BLE devices.
    private let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.oxygenSaturation),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.respiratoryRate),
    ]

    /// Types we read back for the health summary screen.
    private var readTypes: Set<HKObjectType> {
        Set(writeTypes.map { $0 as HKObjectType })
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() {
        guard isAvailable else { return }

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.fetchRecentSamples()
                }
            }
        }
    }

    // MARK: - Write samples from BLE data

    func writeHeartRate(bpm: Double, date: Date = Date()) {
        let type = HKQuantityType(.heartRate)
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        save(sample, label: "Heart Rate", value: bpm, unit: "bpm")
    }

    func writeHRV(ms: Double, date: Date = Date()) {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let quantity = HKQuantity(unit: .secondUnit(with: .milli), doubleValue: ms)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        save(sample, label: "HRV", value: ms, unit: "ms")
    }

    func writeSpO2(percentage: Double, date: Date = Date()) {
        let type = HKQuantityType(.oxygenSaturation)
        let quantity = HKQuantity(unit: .percent(), doubleValue: percentage / 100.0)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        save(sample, label: "SpO2", value: percentage, unit: "%")
    }

    func writeRespiratoryRate(breathsPerMinute: Double, date: Date = Date()) {
        let type = HKQuantityType(.respiratoryRate)
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: breathsPerMinute)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        save(sample, label: "Respiratory Rate", value: breathsPerMinute, unit: "brpm")
    }

    private func save(_ sample: HKQuantitySample, label: String, value: Double, unit: String) {
        healthStore.save(sample) { [weak self] success, error in
            if success {
                DispatchQueue.main.async {
                    let entry = HealthSample(
                        id: UUID().uuidString,
                        label: label,
                        value: value,
                        unit: unit,
                        date: sample.startDate
                    )
                    self?.recentSamples.insert(entry, at: 0)
                    if (self?.recentSamples.count ?? 0) > 50 {
                        self?.recentSamples.removeLast()
                    }
                }
            }
        }
    }

    // MARK: - Read recent samples for summary screen

    func fetchRecentSamples() {
        let types: [(HKQuantityType, String, String, HKUnit)] = [
            (HKQuantityType(.heartRate), "Heart Rate", "bpm", HKUnit.count().unitDivided(by: .minute())),
            (HKQuantityType(.heartRateVariabilitySDNN), "HRV", "ms", .secondUnit(with: .milli)),
            (HKQuantityType(.oxygenSaturation), "SpO2", "%", .percent()),
        ]

        for (type, label, unitLabel, unit) in types {
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 5, sortDescriptors: [sort]) { [weak self] _, results, _ in
                guard let samples = results as? [HKQuantitySample] else { return }
                DispatchQueue.main.async {
                    for sample in samples {
                        var value = sample.quantity.doubleValue(for: unit)
                        if unitLabel == "%" { value *= 100 }
                        let entry = HealthSample(
                            id: sample.uuid.uuidString,
                            label: label,
                            value: value,
                            unit: unitLabel,
                            date: sample.startDate
                        )
                        if !(self?.recentSamples.contains(where: { $0.id == entry.id }) ?? true) {
                            self?.recentSamples.append(entry)
                        }
                    }
                    self?.recentSamples.sort { $0.date > $1.date }
                }
            }
            healthStore.execute(query)
        }
    }
}

/// A simplified health sample for display in the summary screen.
struct HealthSample: Identifiable {
    let id: String
    let label: String
    let value: Double
    let unit: String
    let date: Date
}
