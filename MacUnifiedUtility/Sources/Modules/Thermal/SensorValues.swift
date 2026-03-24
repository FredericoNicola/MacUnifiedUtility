import Foundation

// MARK: - Enums

/// Logical hardware group a sensor belongs to.
public enum SensorGroup: String, CaseIterable {
    case CPU     = "CPU"
    case GPU     = "GPU"
    case system  = "System"
    case sensor  = "Sensors"
    case hid     = "HID"
    case unknown = "Unknown"
}

/// Physical quantity measured by a sensor.
public enum SensorType: String, CaseIterable {
    case temperature = "Temperature"
    case voltage     = "Voltage"
    case current     = "Current"
    case power       = "Power"
    case energy      = "Energy"
    case fan         = "Fans"
}

/// Fan operating mode.
public enum FanMode: Int, Equatable {
    case automatic = 0
    case forced    = 1
}

// MARK: - Sensor protocol

/// Common interface shared by ``Sensor`` and ``Fan``.
public protocol Sensor_p {
    var key: String { get }
    var name: String { get }
    var value: Double { get set }
    var group: SensorGroup { get }
    var type: SensorType { get }
    var platforms: [Platform] { get }
    var isComputed: Bool { get }
    var average: Bool { get }
    var unit: String { get }
    var formattedValue: String { get }
}

// MARK: - Sensor struct

/// A single sensor reading (temperature, voltage, current, power, or energy).
public struct Sensor: Sensor_p {
    public var key: String
    public var name: String
    public var value: Double = 0
    public var group: SensorGroup
    public var type: SensorType
    public var platforms: [Platform]
    public var isComputed: Bool = false
    public var average: Bool = false

    public var unit: String {
        switch type {
        case .temperature: return "°C"
        case .voltage:     return "V"
        case .current:     return "A"
        case .power:       return "W"
        case .energy:      return "Wh"
        case .fan:         return "RPM"
        }
    }

    public var formattedValue: String {
        switch type {
        case .temperature:
            return String(format: "%.1f °C", value)
        case .voltage:
            let v = value >= 100 ? "\(Int(value))" : String(format: "%.3f", value)
            return "\(v) V"
        case .power, .energy:
            let v = value >= 100 ? "\(Int(value))" : String(format: "%.2f", value)
            return "\(v) \(unit)"
        case .current:
            let v = value >= 100 ? "\(Int(value))" : String(format: "%.2f", value)
            return "\(v) A"
        case .fan:
            return "\(Int(value)) RPM"
        }
    }

    public func copy() -> Sensor {
        Sensor(key: key, name: name, value: value, group: group, type: type,
               platforms: platforms, isComputed: isComputed, average: average)
    }
}

// MARK: - Fan struct

/// A fan sensor with speed range and operating mode.
public struct Fan: Sensor_p {
    public let id: Int
    public var key: String
    public var name: String
    public var minSpeed: Double
    public var maxSpeed: Double
    public var value: Double
    public var mode: FanMode
    public var isComputed: Bool = false

    public var group: SensorGroup  = .sensor
    public var type: SensorType    = .fan
    public var platforms: [Platform] = Platform.all
    public var average: Bool       = false
    public var unit: String        = "RPM"

    public var percentage: Int {
        guard value > 1, maxSpeed > 1 else { return 0 }
        return min(100, (100 * Int(value)) / Int(maxSpeed))
    }

    public var formattedValue: String {
        "\(Int(value)) RPM"
    }
}

// MARK: - Sensor lists
// Source: https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift

internal let SensorsList: [Sensor] = [
    // ── Ambient / Sensor ──────────────────────────────────────────────────
    Sensor(key: "TA%P", name: "Ambient %",        group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "Th%H", name: "Heatpipe %",       group: .sensor, type: .temperature, platforms: [.intel]),
    Sensor(key: "TZ%C", name: "Thermal zone %",   group: .sensor, type: .temperature, platforms: Platform.all),

    // ── CPU (Intel / generic) ─────────────────────────────────────────────
    Sensor(key: "TC0D", name: "CPU diode",          group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TC0E", name: "CPU diode virtual",  group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TC0F", name: "CPU diode filtered", group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TC0H", name: "CPU heatsink",       group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TC0P", name: "CPU proximity",      group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TCAD", name: "CPU package",        group: .CPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TC%c", name: "CPU core %",         group: .CPU, type: .temperature, platforms: Platform.all, average: true),
    Sensor(key: "TC%C", name: "CPU Core %",         group: .CPU, type: .temperature, platforms: Platform.all, average: true),

    // ── GPU (Intel / generic) ─────────────────────────────────────────────
    Sensor(key: "TCGC", name: "GPU Intel Graphics", group: .GPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TG0D", name: "GPU diode",          group: .GPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TGDD", name: "GPU AMD Radeon",     group: .GPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TG0H", name: "GPU heatsink",       group: .GPU, type: .temperature, platforms: Platform.all),
    Sensor(key: "TG0P", name: "GPU proximity",      group: .GPU, type: .temperature, platforms: Platform.all),

    // ── System (common) ───────────────────────────────────────────────────
    Sensor(key: "Tm0P", name: "Mainboard",          group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "Tp0P", name: "Powerboard",         group: .system, type: .temperature, platforms: [.intel]),
    Sensor(key: "TB1T", name: "Battery",            group: .system, type: .temperature, platforms: [.intel]),
    Sensor(key: "TW0P", name: "Airport",            group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TL0P", name: "Display",            group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TI%P", name: "Thunderbolt %",      group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TH%A", name: "Disk % (A)",         group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TH%B", name: "Disk % (B)",         group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TH%C", name: "Disk % (C)",         group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TTLD", name: "Thunderbolt left",   group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TTRD", name: "Thunderbolt right",  group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TN0D", name: "Northbridge diode",  group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TN0H", name: "Northbridge heatsink", group: .system, type: .temperature, platforms: Platform.all),
    Sensor(key: "TN0P", name: "Northbridge proximity", group: .system, type: .temperature, platforms: Platform.all),

    // ── M1 CPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tp09", name: "CPU efficiency core 1", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0T", name: "CPU efficiency core 2", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 3", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0H", name: "CPU performance core 4", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0L", name: "CPU performance core 5", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0P", name: "CPU performance core 6", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 7", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 8", group: .CPU, type: .temperature, platforms: Platform.m1Gen, average: true),

    // ── M1 GPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tg05", name: "GPU 1", group: .GPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0D", name: "GPU 2", group: .GPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0L", name: "GPU 3", group: .GPU, type: .temperature, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0T", name: "GPU 4", group: .GPU, type: .temperature, platforms: Platform.m1Gen, average: true),

    // ── M1 Memory ────────────────────────────────────────────────────────
    Sensor(key: "Tm02", name: "Memory 1", group: .sensor, type: .temperature, platforms: Platform.m1Gen),
    Sensor(key: "Tm06", name: "Memory 2", group: .sensor, type: .temperature, platforms: Platform.m1Gen),
    Sensor(key: "Tm08", name: "Memory 3", group: .sensor, type: .temperature, platforms: Platform.m1Gen),
    Sensor(key: "Tm09", name: "Memory 4", group: .sensor, type: .temperature, platforms: Platform.m1Gen),

    // ── M2 CPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tp1h", name: "CPU efficiency core 1", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1t", name: "CPU efficiency core 2", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1p", name: "CPU efficiency core 3", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1l", name: "CPU efficiency core 4", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp09", name: "CPU performance core 3", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 4", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 5", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 6", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0f", name: "CPU performance core 7", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0j", name: "CPU performance core 8", group: .CPU, type: .temperature, platforms: Platform.m2Gen, average: true),

    // ── M2 GPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tg0f", name: "GPU 1", group: .GPU, type: .temperature, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 2", group: .GPU, type: .temperature, platforms: Platform.m2Gen, average: true),

    // ── M3 CPU ────────────────────────────────────────────────────────────
    Sensor(key: "Te05", name: "CPU efficiency core 1",  group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0L", name: "CPU efficiency core 2",  group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0P", name: "CPU efficiency core 3",  group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0S", name: "CPU efficiency core 4",  group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf04", name: "CPU performance core 1", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf09", name: "CPU performance core 2", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0A", name: "CPU performance core 3", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0B", name: "CPU performance core 4", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0D", name: "CPU performance core 5", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0E", name: "CPU performance core 6", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf44", name: "CPU performance core 7", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf49", name: "CPU performance core 8", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4A", name: "CPU performance core 9", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4B", name: "CPU performance core 10", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4D", name: "CPU performance core 11", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4E", name: "CPU performance core 12", group: .CPU, type: .temperature, platforms: Platform.m3Gen, average: true),

    // ── M3 GPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tf14", name: "GPU 1", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf18", name: "GPU 2", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf19", name: "GPU 3", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf1A", name: "GPU 4", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf24", name: "GPU 5", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf28", name: "GPU 6", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf29", name: "GPU 7", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf2A", name: "GPU 8", group: .GPU, type: .temperature, platforms: Platform.m3Gen, average: true),

    // ── M4 CPU ────────────────────────────────────────────────────────────
    Sensor(key: "Te05", name: "CPU efficiency core 1", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te0S", name: "CPU efficiency core 2", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te09", name: "CPU efficiency core 3", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te0H", name: "CPU efficiency core 4", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp09", name: "CPU performance core 3", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 4", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0V", name: "CPU performance core 5", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0Y", name: "CPU performance core 6", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 7", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0e", name: "CPU performance core 8", group: .CPU, type: .temperature, platforms: Platform.m4Gen, average: true),

    // ── M4 GPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tg0G", name: "GPU 1", group: .GPU, type: .temperature, platforms: [.m4], average: true),
    Sensor(key: "Tg0H", name: "GPU 2", group: .GPU, type: .temperature, platforms: [.m4], average: true),
    Sensor(key: "Tg1U", name: "GPU 1", group: .GPU, type: .temperature, platforms: [.m4Pro, .m4Max, .m4Ultra], average: true),
    Sensor(key: "Tg1k", name: "GPU 2", group: .GPU, type: .temperature, platforms: [.m4Pro, .m4Max, .m4Ultra], average: true),
    Sensor(key: "Tg0K", name: "GPU 3", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0L", name: "GPU 4", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0d", name: "GPU 5", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0e", name: "GPU 6", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 7", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0k", name: "GPU 8", group: .GPU, type: .temperature, platforms: Platform.m4Gen, average: true),

    // ── M4 Memory ────────────────────────────────────────────────────────
    Sensor(key: "Tm0p", name: "Memory Proximity 1", group: .sensor, type: .temperature, platforms: Platform.m4Gen),
    Sensor(key: "Tm1p", name: "Memory Proximity 2", group: .sensor, type: .temperature, platforms: Platform.m4Gen),
    Sensor(key: "Tm2p", name: "Memory Proximity 3", group: .sensor, type: .temperature, platforms: Platform.m4Gen),

    // ── M5 CPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tp00", name: "CPU super core 1",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp04", name: "CPU super core 2",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp08", name: "CPU super core 3",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0C", name: "CPU super core 4",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0G", name: "CPU super core 5",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0K", name: "CPU super core 6",       group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0O", name: "CPU performance core 1", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0R", name: "CPU performance core 2", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0U", name: "CPU performance core 3", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 4", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0a", name: "CPU performance core 5", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0d", name: "CPU performance core 6", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0g", name: "CPU performance core 7", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0j", name: "CPU performance core 8", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0m", name: "CPU performance core 9", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0p", name: "CPU performance core 10", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0u", name: "CPU performance core 11", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0y", name: "CPU performance core 12", group: .CPU, type: .temperature, platforms: Platform.m5Gen, average: true),

    // ── M5 GPU ────────────────────────────────────────────────────────────
    Sensor(key: "Tg0U", name: "GPU 1", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0X", name: "GPU 2", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0d", name: "GPU 3", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0g", name: "GPU 4", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 5", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1Y", name: "GPU 6", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1c", name: "GPU 7", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1g", name: "GPU 8", group: .GPU, type: .temperature, platforms: Platform.m5Gen, average: true),

    // ── Apple Silicon shared ──────────────────────────────────────────────
    Sensor(key: "TaLP", name: "Airflow left",  group: .sensor, type: .temperature, platforms: Platform.apple),
    Sensor(key: "TaRF", name: "Airflow right", group: .sensor, type: .temperature, platforms: Platform.apple),
    Sensor(key: "TH0x", name: "NAND",          group: .system, type: .temperature, platforms: Platform.apple),
    Sensor(key: "TB1T", name: "Battery 1",     group: .system, type: .temperature, platforms: Platform.apple),
    Sensor(key: "TB2T", name: "Battery 2",     group: .system, type: .temperature, platforms: Platform.apple),
    Sensor(key: "TW0P", name: "Airport",       group: .system, type: .temperature, platforms: Platform.apple),

    // ── Voltage ───────────────────────────────────────────────────────────
    Sensor(key: "VCAC", name: "CPU IA",          group: .CPU,    type: .voltage, platforms: Platform.all),
    Sensor(key: "VCSC", name: "CPU System Agent", group: .CPU,   type: .voltage, platforms: Platform.all),
    Sensor(key: "VC%C", name: "CPU Core %",       group: .CPU,   type: .voltage, platforms: Platform.all),
    Sensor(key: "VCTC", name: "GPU Intel Graphics", group: .GPU, type: .voltage, platforms: Platform.all),
    Sensor(key: "VG0C", name: "GPU",              group: .GPU,    type: .voltage, platforms: Platform.all),
    Sensor(key: "VM0R", name: "Memory",           group: .system, type: .voltage, platforms: Platform.all),
    Sensor(key: "Vb0R", name: "CMOS",             group: .system, type: .voltage, platforms: Platform.all),
    Sensor(key: "VD0R", name: "DC In",            group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VP0R", name: "12V rail",         group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "Vp0C", name: "12V vcc",          group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VV2S", name: "3V",               group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VR3R", name: "3.3V",             group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VV1S", name: "5V",               group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VV9S", name: "12V",              group: .sensor, type: .voltage, platforms: Platform.all),
    Sensor(key: "VeES", name: "PCI 12V",          group: .sensor, type: .voltage, platforms: Platform.all),

    // ── Current ───────────────────────────────────────────────────────────
    Sensor(key: "IC0R", name: "CPU High side",     group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "IG0R", name: "GPU High side",     group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "ID0R", name: "DC In",             group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "IBAC", name: "Battery",           group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "IDBR", name: "Brightness",        group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "IU1R", name: "Thunderbolt Left",  group: .sensor, type: .current, platforms: Platform.all),
    Sensor(key: "IU2R", name: "Thunderbolt Right", group: .sensor, type: .current, platforms: Platform.all),

    // ── Power ─────────────────────────────────────────────────────────────
    Sensor(key: "PC0C", name: "CPU Core",               group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCAM", name: "CPU Core (IMON)",        group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCPC", name: "CPU Package",            group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCTR", name: "CPU Total",              group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCPT", name: "CPU Package total",      group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCPR", name: "CPU Package total (SMC)", group: .CPU,   type: .power, platforms: Platform.all),
    Sensor(key: "PC0R", name: "CPU Computing high side", group: .CPU,   type: .power, platforms: Platform.all),
    Sensor(key: "PC0G", name: "CPU GFX",               group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCEC", name: "CPU VccEDRAM",           group: .CPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCPG", name: "GPU Intel Graphics",     group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PG0C", name: "GPU",                    group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PG0R", name: "GPU 1",                  group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PG1R", name: "GPU 2",                  group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCGC", name: "Intel GPU",              group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PCGM", name: "Intel GPU (IMON)",       group: .GPU,    type: .power, platforms: Platform.all),
    Sensor(key: "PC3C", name: "RAM",                    group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PPBR", name: "Battery",                group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PDTR", name: "DC In",                  group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PMTR", name: "Memory Total",           group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PSTR", name: "System Total",           group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PU1R", name: "Thunderbolt Left",       group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PU2R", name: "Thunderbolt Right",      group: .sensor, type: .power, platforms: Platform.all),
    Sensor(key: "PDBR", name: "Power Delivery Brightness", group: .sensor, type: .power,
           platforms: [.m1, .m1Pro, .m1Max, .m1Ultra, .m4, .m4Pro, .m4Max, .m4Ultra]),
]

/// HID sensor name-matching list for Apple Silicon sensors read via IOHIDEventSystem.
internal let HIDSensorsList: [Sensor] = [
    Sensor(key: "pACC MTR Temp Sensor%", name: "CPU performance core %", group: .CPU,    type: .temperature, platforms: Platform.all),
    Sensor(key: "eACC MTR Temp Sensor%", name: "CPU efficiency core %",  group: .CPU,    type: .temperature, platforms: Platform.all),
    Sensor(key: "GPU MTR Temp Sensor%",  name: "GPU core %",             group: .GPU,    type: .temperature, platforms: Platform.all),
    Sensor(key: "SOC MTR Temp Sensor%",  name: "SOC core %",             group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "ANE MTR Temp Sensor%",  name: "Neural engine %",        group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "ISP MTR Temp Sensor%",  name: "Image Signal Processor %", group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "PMGR SOC Die Temp Sensor%", name: "Power manager die %", group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "PMU tdev%",             name: "Power management unit dev %", group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "PMU tdie%",             name: "Power management unit die %", group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "gas gauge battery",     name: "Battery",                group: .sensor, type: .temperature, platforms: Platform.all),
    Sensor(key: "NAND CH% temp",         name: "Disk %",                 group: .sensor, type: .temperature, platforms: Platform.all),
]
