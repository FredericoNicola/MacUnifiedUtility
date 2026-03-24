import Foundation
import Combine
import IOKit

/// Read-only sensor monitor.
///
/// Polls SMC temperature / voltage / power / fan sensors, plus HID sensors
/// on Apple Silicon and IOReport power readings (arm64 only), on a repeating
/// timer. Publishes a flat list of ``Sensor_p`` values and a computed summary
/// string for the menu-bar popover.
@MainActor
final class ThermalMonitor: ObservableObject {

    // MARK: - Published State

    /// All active sensors, updated on each poll.
    @Published var sensors: [any Sensor_p] = []

    /// `true` while SMC is available and polling is running.
    @Published var isMonitoring = false

    /// Non-nil when SMC is unavailable.
    @Published var unavailableReason: String?

    /// The poll interval in seconds (default 5 s).
    @Published var pollInterval: Double = 5 {
        didSet { restartTimerIfNeeded() }
    }

    // MARK: - Convenience

    /// A short summary suitable for the menu-bar popover status row.
    var cpuTemperatureSummary: String {
        let cpuSensors = sensors.filter { $0.group == .CPU && $0.type == .temperature }
        if let avg = cpuSensors.first(where: { $0.key == "Average CPU" }) {
            return String(format: "%.1f °C", avg.value)
        }
        if let first = cpuSensors.first(where: { !$0.isComputed }) {
            return String(format: "%.1f °C", first.value)
        }
        return unavailableReason != nil ? "Unavailable" : "–"
    }

    /// Sensors grouped by ``SensorGroup`` in display order.
    var groupedSensors: [(group: SensorGroup, sensors: [any Sensor_p])] {
        let order: [SensorGroup] = [.CPU, .GPU, .system, .sensor, .hid, .unknown]
        return order.compactMap { group in
            let list = sensors.filter { $0.group == group }
            return list.isEmpty ? nil : (group: group, sensors: list)
        }
    }

    // MARK: - Private

    private var smcHelper: SMCHelper?
    private var timer: Timer?

    // IOReport state (Apple Silicon power, arm64 only)
    private var ioChannels: CFMutableDictionary?
    private var ioSubscription: IOReportSubscriptionRef?
    private var ioPrevious: (cpu: Double, gpu: Double, ane: Double, ram: Double, pci: Double) = (0, 0, 0, 0, 0)
    private var ioPreviousDate: Date?

    // MARK: - Init

    init() {
        connect()
    }

    // MARK: - Public API

    func startMonitoring() {
        guard smcHelper != nil, !isMonitoring else { return }
        isMonitoring = true
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    /// Retry the SMC connection after a settings change (e.g., disabling App Sandbox).
    func retryConnection() {
        stopMonitoring()
        smcHelper = nil
        connect()
    }

    // MARK: - Connection

    private func connect() {
        smcHelper = SMCHelper()
        if smcHelper == nil {
            unavailableReason = """
                Unable to connect to the SMC temperature service. \
                This is usually caused by App Sandbox being enabled. \
                Disable "App Sandbox" in Signing & Capabilities and relaunch the app. \
                Temperature monitoring is only available on real Apple hardware.
                """
        } else {
            unavailableReason = nil
            setupIOReport()
            sensors = buildSensorList()
            if !sensors.isEmpty {
                startMonitoring()
            } else {
                unavailableReason = """
                    SMC connected but no sensors were found. \
                    This may indicate the app needs to run without App Sandbox, \
                    or your hardware uses different sensor types.
                    """
            }
        }
    }

    // MARK: - Sensor List Construction

    /// Build the initial sensor list by matching SMC-available keys against
    /// SensorsList, then appending unknown T/V/P/I keys, fans, HID sensors
    /// (arm64 only), and computed aggregates.
    private func buildSensorList() -> [any Sensor_p] {
        guard let smc = smcHelper else { return [] }

        let platform = Platform.current
        var available = smc.getAllKeys()

        // Filter SensorsList to platform-relevant entries.
        var candidates = SensorsList
        if let p = platform {
            candidates = candidates.filter { $0.platforms.contains(p) }
        }

        // Filter available keys to sensor-relevant prefixes.
        available = available.filter {
            switch $0.prefix(1) {
            case "T", "V", "P", "I": return true
            default: return false
            }
        }

        var list: [any Sensor_p] = []

        // 1. Exact-match candidates.
        for s in candidates where !s.key.contains("%") {
            if let idx = available.firstIndex(where: { $0 == s.key }) {
                var sensor = s
                if let v = smc.getValue(s.key) { sensor.value = v }
                list.append(sensor)
                available.remove(at: idx)
            }
        }

        // 2. Wildcard candidates (key contains %).
        for s in candidates where s.key.contains("%") {
            var index = 1
            for i in 0..<10 {
                let key = s.key.replacingOccurrences(of: "%", with: "\(i)")
                if let idx = available.firstIndex(where: { $0 == key }) {
                    var sensor = s.copy()
                    sensor.key   = key
                    sensor.name  = s.name.replacingOccurrences(of: "%", with: "\(index)")
                    if let v = smc.getValue(key) { sensor.value = v }
                    list.append(sensor)
                    available.remove(at: idx)
                    index += 1
                }
            }
        }

        // 3. Remaining unknown keys → group .unknown.
        for key in available {
            let type: SensorType
            switch key.prefix(1) {
            case "T": type = .temperature
            case "V": type = .voltage
            case "P": type = .power
            case "I": type = .current
            default:  continue
            }
            var sensor = Sensor(key: key, name: key, group: .unknown, type: type, platforms: [])
            if let v = smc.getValue(key) { sensor.value = v }
            list.append(sensor)
        }

        // 4. Fans. FNum is always a whole-number count, so truncating to Int is safe.
        if let fanCount = smc.getValue("FNum").map({ Int($0) }), fanCount > 0, fanCount <= 16 {
            list += loadFans(fanCount, smc: smc)
        }

        // Plausibility filter.
        list = list.filter { s in
            switch s.type {
            case .temperature: return s.value > 0 && s.value <= 110
            case .current:     return s.value < 100
            default:           return true
            }
        }

        // 5. HID sensors (Apple Silicon only).
        #if arch(arm64)
        list += initHIDSensors()
        list += initIOSensors()
        #endif

        // 6. Computed aggregates.
        list += buildComputedSensors(from: list)

        return list.sorted {
            // Sort within group: computed last, then by name.
            if $0.group.rawValue != $1.group.rawValue { return $0.group.rawValue < $1.group.rawValue }
            if $0.isComputed != $1.isComputed { return !$0.isComputed }
            return $0.name < $1.name
        }
    }

    // MARK: - Fan reading

    private func loadFans(_ count: Int, smc: SMCHelper) -> [Fan] {
        var fans: [Fan] = []
        for i in 0..<count {
            let name = smc.getStringValue("F\(i)ID") ?? "Fan #\(i)"
            let mode = readFanMode(i, smc: smc)
            fans.append(Fan(
                id: i,
                key: "F\(i)Ac",
                name: name,
                minSpeed: smc.getValue("F\(i)Mn") ?? 1,
                maxSpeed: smc.getValue("F\(i)Mx") ?? 1,
                value: smc.getValue("F\(i)Ac") ?? 0,
                mode: mode
            ))
        }
        return fans
    }

    private func readFanMode(_ id: Int, smc: SMCHelper) -> FanMode {
        #if arch(arm64)
        // Apple Silicon: F%dMd – 0=auto, 1=manual
        if let v = smc.getValue(smc.fanModeKey(id)) {
            return Int(v) == 1 ? .forced : .automatic
        }
        return .automatic
        #else
        // Intel: FS! bitmask – bit(id) set → forced
        if let v = smc.getValue("FS! ") {
            let mask = Int(v)
            if mask == 0 { return .automatic }
            return (mask & (1 << id)) != 0 ? .forced : .automatic
        }
        return .automatic
        #endif
    }

    // MARK: - HID sensors (Apple Silicon)

    #if arch(arm64)
    private func initHIDSensors() -> [Sensor] {
        var list: [Sensor] = []
        let types: [(Int32, Int32, Int32, SensorType)] = [
            (0xff00, 0x0005, kIOHIDEventTypeTemperature, .temperature),
            (0xff08, 0x0003, kIOHIDEventTypePower,       .voltage),
        ]
        for (page, usage, eventType, sensorType) in types {
            guard let dict = AppleSiliconSensors(page, usage, eventType) else { continue }
            for (rawKey, rawVal) in dict {
                guard let key = rawKey as? String, let val = rawVal as? Double else { continue }
                guard val >= 0, val < 300 else { continue }
                let name = resolveHIDName(key: key, type: sensorType)
                list.append(Sensor(key: key, name: name, value: val,
                                   group: .hid, type: sensorType, platforms: Platform.all))
            }
        }
        // Average / Hottest SOC
        let soc = list.filter { $0.key.hasPrefix("SOC MTR Temp") }.map { $0.value }
        if !soc.isEmpty {
            let avg = soc.reduce(0, +) / Double(soc.count)
            list.append(Sensor(key: "Average SOC", name: "Average SOC", value: avg,
                               group: .hid, type: .temperature, platforms: Platform.all))
            if let mx = soc.max() {
                list.append(Sensor(key: "Hottest SOC", name: "Hottest SOC", value: mx,
                                   group: .hid, type: .temperature, platforms: Platform.all))
            }
        }
        return list.sorted { $0.key.lowercased() < $1.key.lowercased() }
    }

    private func resolveHIDName(key: String, type: SensorType) -> String {
        for s in HIDSensorsList {
            if s.key.contains("%") {
                var index = 1
                for i in 0..<64 {
                    if s.key.replacingOccurrences(of: "%", with: "\(i)") == key {
                        return s.name.replacingOccurrences(of: "%", with: "\(index)")
                    }
                    index += 1
                }
            } else if s.key == key {
                return s.name
            }
        }
        return key
    }
    #endif

    // MARK: - IOReport power (Apple Silicon)

    private func setupIOReport() {
        #if arch(arm64)
        guard let ch = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?
                .takeRetainedValue() else { return }
        let size = CFDictionaryGetCount(ch)
        guard let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, ch) else { return }
        ioChannels = mutable
        var dict: Unmanaged<CFMutableDictionary>?
        ioSubscription = IOReportCreateSubscription(nil, mutable, &dict, 0, nil)
        dict?.release()
        #endif
    }

    #if arch(arm64)
    private func initIOSensors() -> [Sensor] {
        guard let (cpu, gpu, ane, ram, pci) = sampleIOReport() else { return [] }
        return [
            Sensor(key: "CPU Power", name: "CPU Power", value: cpu, group: .CPU,    type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "GPU Power", name: "GPU Power", value: gpu, group: .GPU,    type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "ANE Power", name: "ANE Power", value: ane, group: .system, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "RAM Power", name: "RAM Power", value: ram, group: .system, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "PCI Power", name: "PCI Power", value: pci, group: .system, type: .power, platforms: Platform.apple, isComputed: true),
        ]
    }

    private func sampleIOReport() -> (Double, Double, Double, Double, Double)? {
        guard let sub = ioSubscription, let ch = ioChannels,
              let sample = IOReportCreateSamples(sub, ch, nil)?.takeRetainedValue(),
              let dict = sample as? [String: Any],
              let items = dict["IOReportChannels"] as? CFArray else { return nil }

        var current = ioPrevious
        for i in 0..<CFArrayGetCount(items) {
            guard let ptr = CFArrayGetValueAtIndex(items, i) else { continue }
            let item = unsafeBitCast(ptr, to: CFDictionary.self)
            guard let group   = IOReportChannelGetGroup(item)?.takeUnretainedValue() as? String,
                  group == "Energy Model",
                  let channel = IOReportChannelGetChannelName(item)?.takeUnretainedValue() as? String,
                  let unit    = IOReportChannelGetUnitLabel(item)?.takeUnretainedValue() as? String
            else { continue }

            let raw = Double(IOReportSimpleGetIntegerValue(item, 0))
            let joules = raw.toJoules(unit: unit)

            if channel.hasSuffix("CPU Energy")      { current.cpu = joules }
            else if channel.hasSuffix("GPU Energy") { current.gpu = joules }
            else if channel.hasPrefix("ANE")        { current.ane = joules }
            else if channel.hasPrefix("DRAM")       { current.ram = joules }
            else if channel.hasPrefix("PCI") && channel.hasSuffix("Energy") { current.pci = joules }
        }

        let now = Date()
        defer {
            ioPrevious = current
            ioPreviousDate = now
        }
        guard let prev = ioPreviousDate, ioPrevious.cpu != 0 else { return nil }
        let elapsed = now.timeIntervalSince(prev)
        guard elapsed > 0 else { return nil }

        return (
            (current.cpu - ioPrevious.cpu) / elapsed,
            (current.gpu - ioPrevious.gpu) / elapsed,
            (current.ane - ioPrevious.ane) / elapsed,
            (current.ram - ioPrevious.ram) / elapsed,
            (current.pci - ioPrevious.pci) / elapsed
        )
    }
    #endif

    // MARK: - Computed aggregates

    private func buildComputedSensors(from list: [any Sensor_p]) -> [any Sensor_p] {
        var result: [any Sensor_p] = []

        var cpuTemps = list.filter { $0.group == .CPU && $0.type == .temperature && $0.average }.map { $0.value }
        var gpuTemps = list.filter { $0.group == .GPU && $0.type == .temperature && $0.average }.map { $0.value }

        #if arch(arm64)
        cpuTemps += list.filter { $0.key.hasPrefix("pACC MTR Temp") || $0.key.hasPrefix("eACC MTR Temp") }.map { $0.value }
        gpuTemps += list.filter { $0.key.hasPrefix("GPU MTR Temp") }.map { $0.value }
        #endif

        if !cpuTemps.isEmpty {
            let avg = cpuTemps.reduce(0, +) / Double(cpuTemps.count)
            result.append(Sensor(key: "Average CPU", name: "Average CPU", value: avg,
                                 group: .CPU, type: .temperature, platforms: Platform.all, isComputed: true))
            if let mx = cpuTemps.max() {
                result.append(Sensor(key: "Hottest CPU", name: "Hottest CPU", value: mx,
                                     group: .CPU, type: .temperature, platforms: Platform.all, isComputed: true))
            }
        }
        if !gpuTemps.isEmpty {
            let avg = gpuTemps.reduce(0, +) / Double(gpuTemps.count)
            result.append(Sensor(key: "Average GPU", name: "Average GPU", value: avg,
                                 group: .GPU, type: .temperature, platforms: Platform.all, isComputed: true))
            if let mx = gpuTemps.max() {
                result.append(Sensor(key: "Hottest GPU", name: "Hottest GPU", value: mx,
                                     group: .GPU, type: .temperature, platforms: Platform.all, isComputed: true))
            }
        }

        let fans = list.filter { $0.type == .fan && !$0.isComputed }
        if fans.count > 1, let fastest = fans.max(by: { $0.value < $1.value }) as? Fan {
            result.append(Fan(id: -1, key: "Fastest fan", name: "Fastest fan",
                              minSpeed: fastest.minSpeed, maxSpeed: fastest.maxSpeed,
                              value: fastest.value, mode: .automatic, isComputed: true))
        }

        if list.contains(where: { $0.key == "PSTR" }) {
            result.append(Sensor(key: "Total System Consumption", name: "Total System Consumption",
                                 value: 0, group: .sensor, type: .energy, platforms: Platform.all, isComputed: true))
            result.append(Sensor(key: "Average System Total", name: "Average System Total",
                                 value: 0, group: .sensor, type: .power, platforms: Platform.all, isComputed: true))
        }

        return result
    }

    // MARK: - Poll

    private func poll() {
        guard let smc = smcHelper else { return }

        for i in sensors.indices {
            guard !sensors[i].isComputed else { continue }
            guard sensors[i].group != .hid else { continue }

            if var fan = sensors[i] as? Fan {
                fan.value   = smc.getValue(fan.key) ?? fan.value
                fan.mode    = readFanMode(fan.id, smc: smc)
                sensors[i]  = fan
                continue
            }
            guard var sensor = sensors[i] as? Sensor else { continue }

            var newVal = smc.getValue(sensor.key) ?? sensor.value
            // Guard against broken M2 CPU sensor readings where the SMC
            // transiently reports implausible values (< 10 °C or > 120 °C).
            // Retain the previous reading rather than propagating noise.
            let minPlausibleCpuTemp: Double = 10
            let maxPlausibleCpuTemp: Double = 120
            if sensor.type == .temperature, sensor.group == .CPU,
               newVal < minPlausibleCpuTemp || newVal > maxPlausibleCpuTemp {
                newVal = sensor.value
            }
            sensor.value = newVal
            sensors[i] = sensor
        }

        // HID update (Apple Silicon).
        #if arch(arm64)
        let hidTypes: [(Int32, Int32, Int32, SensorType)] = [
            (0xff00, 0x0005, kIOHIDEventTypeTemperature, .temperature),
            (0xff08, 0x0003, kIOHIDEventTypePower,       .voltage),
        ]
        for (page, usage, eventType, _) in hidTypes {
            guard let dict = AppleSiliconSensors(page, usage, eventType) else { continue }
            for (rawKey, rawVal) in dict {
                guard let key = rawKey as? String, let val = rawVal as? Double,
                      val >= 0, val < 300 else { continue }
                if let idx = sensors.firstIndex(where: { $0.group == .hid && $0.key == key }) {
                    if var s = sensors[idx] as? Sensor {
                        s.value = val
                        sensors[idx] = s
                    }
                }
            }
        }
        // Recompute SOC averages.
        let socVals = sensors.filter { $0.key.hasPrefix("SOC MTR Temp") }.map { $0.value }
        if !socVals.isEmpty {
            if let idx = sensors.firstIndex(where: { $0.key == "Average SOC" }),
               var s = sensors[idx] as? Sensor {
                s.value = socVals.reduce(0, +) / Double(socVals.count); sensors[idx] = s
            }
            if let mx = socVals.max(),
               let idx = sensors.firstIndex(where: { $0.key == "Hottest SOC" }),
               var s = sensors[idx] as? Sensor {
                s.value = mx; sensors[idx] = s
            }
        }

        // IOReport power update.
        if let (cpu, gpu, ane, ram, pci) = sampleIOReport() {
            let updates: [(String, Double)] = [
                ("CPU Power", cpu), ("GPU Power", gpu),
                ("ANE Power", ane), ("RAM Power", ram), ("PCI Power", pci),
            ]
            for (key, val) in updates {
                if let idx = sensors.firstIndex(where: { $0.key == key }),
                   var s = sensors[idx] as? Sensor {
                    s.value = val; sensors[idx] = s
                }
            }
        }
        #endif

        // Recompute CPU / GPU averages.
        var cpuVals = sensors.filter { $0.group == .CPU && $0.type == .temperature && $0.average }.map { $0.value }
        var gpuVals = sensors.filter { $0.group == .GPU && $0.type == .temperature && $0.average }.map { $0.value }
        #if arch(arm64)
        cpuVals += sensors.filter { $0.key.hasPrefix("pACC MTR Temp") || $0.key.hasPrefix("eACC MTR Temp") }.map { $0.value }
        gpuVals += sensors.filter { $0.key.hasPrefix("GPU MTR Temp") }.map { $0.value }
        #endif
        updateComputed(key: "Average CPU", value: cpuVals.isEmpty ? nil : cpuVals.reduce(0, +) / Double(cpuVals.count))
        updateComputed(key: "Hottest CPU", value: cpuVals.max())
        updateComputed(key: "Average GPU", value: gpuVals.isEmpty ? nil : gpuVals.reduce(0, +) / Double(gpuVals.count))
        updateComputed(key: "Hottest GPU", value: gpuVals.max())

        // Fastest fan (when > 1 fan).
        let fanList = sensors.filter { $0.type == .fan && !$0.isComputed }
        if fanList.count > 1, let fastest = fanList.max(by: { $0.value < $1.value }) as? Fan,
           let idx = sensors.firstIndex(where: { $0.key == "Fastest fan" }),
           var s = sensors[idx] as? Fan {
            s.value = fastest.value; s.minSpeed = fastest.minSpeed; s.maxSpeed = fastest.maxSpeed
            sensors[idx] = s
        }

        // DC In voltage / current cleanup.
        filterLow(key: "VD0R", threshold: 0.4)
        filterLow(key: "ID0R", threshold: 0.05)

        if sensors.isEmpty {
            unavailableReason = """
                SMC connected but no sensors responded. \
                This may indicate the app needs to run without App Sandbox.
                """
            stopMonitoring()
        } else {
            unavailableReason = nil
        }
    }

    private func updateComputed(key: String, value: Double?) {
        guard let v = value,
              let idx = sensors.firstIndex(where: { $0.key == key }),
              var s = sensors[idx] as? Sensor else { return }
        s.value = v
        sensors[idx] = s
    }

    private func filterLow(key: String, threshold: Double) {
        guard let idx = sensors.firstIndex(where: { $0.key == key }),
              var s = sensors[idx] as? Sensor,
              s.value < threshold else { return }
        s.value = 0
        sensors[idx] = s
    }

    // MARK: - Timer

    private func restartTimerIfNeeded() {
        guard isMonitoring else { return }
        stopMonitoring()
        startMonitoring()
    }
}

// MARK: - Double energy-unit helper

private extension Double {
    /// Convert a raw IOReport cumulative energy integer to Joules.
    func toJoules(unit: String) -> Double {
        switch unit {
        case "mJ":  return self * 0.001
        case "µJ", "uJ": return self * 0.000_001
        case "nJ":  return self * 0.000_000_001
        default:    return self
        }
    }
}
