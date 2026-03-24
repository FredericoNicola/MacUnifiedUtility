import Foundation
import IOKit
import IOKit.ps

/// Reads battery state from IOKit power sources and the AppleSmartBattery registry entry.
///
/// Uses `IOPSNotificationCreateRunLoopSource` for event-driven updates (no polling).
/// Battery health is fetched via `system_profiler SPPowerDataType` and cached for 1 hour.
///
/// All methods must be called on the main thread. The IOPSNotification callback fires
/// on the main run loop, so this invariant is maintained automatically.
final class BatteryReader {

    // MARK: - Callbacks

    /// Called on the main thread whenever the power state changes.
    var onUpdate: ((PowerState?) -> Void)?

    /// Called on the main thread to indicate whether an internal battery is present.
    var onLaptopDetected: ((Bool) -> Void)?

    // MARK: - Private

    private var runLoopSource: CFRunLoopSource?

    /// Cached result from `system_profiler SPPowerDataType`.
    private var lastHealthFetch: Date?
    private var lastHealthValue: Int?

    // MARK: - Init / Deinit

    init() {
        registerForNotifications()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Public API

    /// Re-read power state and fire the callbacks. Dispatches a background health fetch
    /// when the cached value is stale.
    func refresh() {
        onLaptopDetected?(hasInternalBattery())

        let now = Date()
        let isFresh = lastHealthFetch.map { now.timeIntervalSince($0) < 3600 } ?? false
        let cachedHealth: Int? = isFresh ? lastHealthValue : nil

        onUpdate?(readPowerState(batteryHealth: cachedHealth))

        guard !isFresh else { return }

        // Fetch health on a background thread; resume on main actor.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let health = await Task.detached(priority: .background) {
                BatteryReader.fetchBatteryHealthFromSystemProfiler()
            }.value
            self.lastHealthFetch = Date()
            self.lastHealthValue = health
            self.onUpdate?(self.readPowerState(batteryHealth: health))
        }
    }

    // MARK: - Private: Notification Registration

    private func registerForNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource(
            { ctx in
                guard let ctx else { return }
                let reader = Unmanaged<BatteryReader>.fromOpaque(ctx).takeUnretainedValue()
                reader.refresh()
            },
            context
        ).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    // MARK: - Private: Internal Battery Detection

    private func hasInternalBattery() -> Bool {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType { return true }
        }
        return false
    }

    // MARK: - Private: Power State Reading

    private func readPowerState(batteryHealth: Int?) -> PowerState? {
        // ── IOPowerSources ──────────────────────────────────────────────────────
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        var psInfo: [String: Any]?
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
                psInfo = info
                break
            }
        }
        guard let info = psInfo else { return nil }

        let batteryLevel  = info[kIOPSCurrentCapacityKey]       as? Int    ?? 0
        let isCharging    = info[kIOPSIsChargingKey]            as? Bool   ?? false
        let powerSource   = info[kIOPSPowerSourceStateKey]      as? String ?? "Unknown"
        let timeToEmpty   = info[kIOPSTimeToEmptyKey]           as? Int    ?? -1
        let timeToFull    = info[kIOPSTimeToFullChargeKey]      as? Int    ?? -1
        let obcEngaged    = info["Optimized Battery Charging Engaged"] as? Bool ?? false

        // ── AppleSmartBattery ───────────────────────────────────────────────────
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )

        var cycleCount:      Int     = 0
        var batteryTemp:     Double  = 0.0
        var chargerConnected: Bool   = false
        var designCapacity:  Int?
        var maxCapacity:     Int?
        var currentCapacity: Int?
        var voltage:         Double?
        var amperage:        Double?

        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }

            cycleCount       = readInt("CycleCount",              service: service) ?? 0
            chargerConnected = readBool("ExternalConnected",       service: service) ?? false
            designCapacity   = readInt("DesignCapacity",           service: service)
            maxCapacity      = readInt("AppleRawMaxCapacity",      service: service)
            currentCapacity  = readInt("AppleRawCurrentCapacity",  service: service)

            if let raw = readInt("VirtualTemperature", service: service) {
                batteryTemp = Double(raw) / 100.0
            }
            if let v = readInt("Voltage",   service: service) { voltage  = Double(v) }
            if let a = readInt("Amperage",  service: service) { amperage = Double(a) }
        }

        return PowerState(
            batteryLevel:                    batteryLevel,
            isCharging:                      isCharging,
            powerSource:                     powerSource,
            timeToEmpty:                     timeToEmpty,
            timeToFullCharge:                timeToFull,
            cycleCount:                      cycleCount,
            batteryHealth:                   batteryHealth,
            batteryTemperature:              batteryTemp,
            chargerConnected:                chargerConnected,
            optimizedBatteryChargingEngaged: obcEngaged,
            designCapacity:                  designCapacity,
            maxCapacity:                     maxCapacity,
            currentCapacity:                 currentCapacity,
            voltage:                         voltage,
            amperage:                        amperage
        )
    }

    // MARK: - Private: Registry Property Helpers

    private func readInt(_ key: String, service: io_service_t) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        let value = unmanaged.takeRetainedValue()
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private func readBool(_ key: String, service: io_service_t) -> Bool? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        let value = unmanaged.takeRetainedValue()
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    // MARK: - Private: Battery Health via system_profiler

    /// Synchronous; must be called on a background thread.
    private static func fetchBatteryHealthFromSystemProfiler() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments     = ["SPPowerDataType"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data   = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse "Maximum Capacity: XX%" (English locale output from system_profiler)
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Maximum Capacity:") else { continue }
            let parts = trimmed.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let valueString = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "%", with: "")
            if let health = Int(valueString) { return health }
        }
        return nil
    }
}
