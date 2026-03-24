import Foundation

/// A snapshot of the Mac's battery and power source state.
/// Mirrors the pattern from rurza/BatFi `BatFiKit/Sources/AppShared/PowerState.swift`.
struct PowerState: Equatable {
    let batteryLevel: Int            // 0–100
    let isCharging: Bool
    let powerSource: String          // e.g. "AC Power" or "Battery Power"
    let timeToEmpty: Int             // minutes; -1 = unknown/unlimited
    let timeToFullCharge: Int        // minutes; -1 = unknown/not applicable
    let cycleCount: Int
    let batteryHealth: Int?          // percentage (0–100) from system_profiler; nil = unknown or desktop
    let batteryTemperature: Double   // °C (VirtualTemperature / 100)
    let chargerConnected: Bool
    let optimizedBatteryChargingEngaged: Bool
    let designCapacity: Int?         // mAh from AppleSmartBattery
    let maxCapacity: Int?            // mAh from AppleSmartBattery
    let currentCapacity: Int?        // mAh from AppleSmartBattery
    let voltage: Double?             // mV from AppleSmartBattery
    let amperage: Double?            // mA from AppleSmartBattery (negative = discharging)

    /// Human-readable time description.
    var timeDescription: String {
        if isCharging {
            if timeToFullCharge <= 0 { return "Calculating…" }
            let h = timeToFullCharge / 60
            let m = timeToFullCharge % 60
            return h > 0 ? "\(h)h \(m)m until full" : "\(m)m until full"
        } else {
            if timeToEmpty <= 0 { return "Calculating…" }
            let h = timeToEmpty / 60
            let m = timeToEmpty % 60
            return h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
        }
    }
}
