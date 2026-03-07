import Foundation
import CoreBluetooth

/// Known BLE GATT service and characteristic mappings for health devices.
///
/// When a BLE device connects, Haven Connect uses these profiles to
/// identify what data is being transmitted and map it to the correct
/// HealthKit data type. This is accumulated domain knowledge that
/// makes Haven Connect more than a generic BLE bridge.
enum GATTProfiles {

    // MARK: - Standard BLE Health Services (Bluetooth SIG assigned)

    /// Heart Rate Service (0x180D)
    static let heartRateService = CBUUID(string: "180D")
    /// Heart Rate Measurement characteristic (0x2A37)
    static let heartRateMeasurement = CBUUID(string: "2A37")

    /// Health Thermometer Service (0x1809)
    static let healthThermometerService = CBUUID(string: "1809")
    /// Temperature Measurement (0x2A1C)
    static let temperatureMeasurement = CBUUID(string: "2A1C")

    /// Blood Pressure Service (0x1810)
    static let bloodPressureService = CBUUID(string: "1810")
    /// Blood Pressure Measurement (0x2A35)
    static let bloodPressureMeasurement = CBUUID(string: "2A35")

    /// Pulse Oximeter Service (0x1822)
    static let pulseOximeterService = CBUUID(string: "1822")
    /// SpO2 Measurement (0x2A5E)
    static let spo2Measurement = CBUUID(string: "2A5E")

    /// Device Information Service (0x180A)
    static let deviceInfoService = CBUUID(string: "180A")

    /// Battery Service (0x180F)
    static let batteryService = CBUUID(string: "180F")
    /// Battery Level (0x2A19)
    static let batteryLevel = CBUUID(string: "2A19")

    // MARK: - Parsing BLE characteristic data

    /// Parse heart rate from a Heart Rate Measurement characteristic value.
    /// Follows Bluetooth SIG Heart Rate Profile specification.
    static func parseHeartRate(data: Data) -> HeartRateReading? {
        guard data.count >= 2 else { return nil }

        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        let bpm: UInt16
        if is16Bit {
            guard data.count >= 3 else { return nil }
            bpm = UInt16(data[1]) | (UInt16(data[2]) << 8)
        } else {
            bpm = UInt16(data[1])
        }

        // RR intervals (for HRV) start after the HR value
        var rrIntervals: [Double] = []
        let hasRR = (flags & 0x10) != 0
        if hasRR {
            let rrStart = is16Bit ? 3 : 2
            var i = rrStart
            while i + 1 < data.count {
                let rr = UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
                // RR is in 1/1024 seconds, convert to ms
                rrIntervals.append(Double(rr) / 1024.0 * 1000.0)
                i += 2
            }
        }

        return HeartRateReading(bpm: Int(bpm), rrIntervals: rrIntervals)
    }

    /// Parse SpO2 from a PLX Continuous Measurement characteristic.
    static func parseSpO2(data: Data) -> Double? {
        // PLX Continuous Measurement: flags (1 byte) + SpO2 (SFLOAT, 2 bytes)
        guard data.count >= 3 else { return nil }
        let raw = UInt16(data[1]) | (UInt16(data[2]) << 8)
        return sfloatToDouble(raw)
    }

    /// Parse battery level (0-100%).
    static func parseBatteryLevel(data: Data) -> Int? {
        guard data.count >= 1 else { return nil }
        return Int(data[0])
    }

    /// Identify what type of health data a characteristic provides.
    static func identifyCharacteristic(serviceUUID: String, characteristicUUID: String) -> DataType? {
        let service = serviceUUID.uppercased()
        let char = characteristicUUID.uppercased()

        if service.contains("180D") && char.contains("2A37") { return .heartRate }
        if service.contains("1822") && char.contains("2A5E") { return .spo2 }
        if service.contains("1809") && char.contains("2A1C") { return .temperature }
        if service.contains("180F") && char.contains("2A19") { return .battery }

        return nil
    }

    // MARK: - Types

    enum DataType {
        case heartRate
        case spo2
        case temperature
        case battery
    }

    struct HeartRateReading {
        let bpm: Int
        let rrIntervals: [Double]

        /// Calculate SDNN (standard deviation of NN intervals) for HRV.
        /// Requires at least 2 RR intervals.
        var hrvSDNN: Double? {
            guard rrIntervals.count >= 2 else { return nil }
            let mean = rrIntervals.reduce(0, +) / Double(rrIntervals.count)
            let variance = rrIntervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rrIntervals.count)
            return variance.squareRoot()
        }
    }

    // MARK: - Helpers

    /// Convert Bluetooth SFLOAT (16-bit) to Double.
    private static func sfloatToDouble(_ raw: UInt16) -> Double {
        let mantissa = Int16(raw & 0x0FFF)
        let exponent = Int8(Int16(raw >> 12))
        // Handle special values
        if mantissa == 0x07FF { return .nan } // NaN
        if mantissa == 0x0800 { return .nan } // NRes
        // Sign-extend mantissa
        let signedMantissa: Int16
        if mantissa >= 0x0800 {
            signedMantissa = mantissa - 0x1000
        } else {
            signedMantissa = mantissa
        }
        return Double(signedMantissa) * pow(10.0, Double(exponent))
    }
}
