import Foundation
import Combine

/// Read-only temperature monitor.
///
/// Polls all known SMC temperature keys on a repeating timer and publishes
/// the latest readings to the UI.
@MainActor
final class ThermalMonitor: ObservableObject {

    // MARK: - Published State

    /// Current temperature readings for all available sensors (known keys).
    @Published var readings: [TemperatureReading] = []

    /// Temperature readings found via dynamic key discovery (Apple Silicon fallback).
    @Published var dynamicReadings: [DynamicTemperatureReading] = []

    /// `true` while SMC is available and polling is running.
    @Published var isMonitoring = false

    /// Non-nil when SMC is unavailable (e.g., virtual machine, non-Apple hardware).
    @Published var unavailableReason: String?

    /// The poll interval in seconds (default 5 s).
    @Published var pollInterval: Double = 5 {
        didSet { restartTimerIfNeeded() }
    }

    // MARK: - Convenience

    /// A short summary suitable for the menu bar popover status row.
    var cpuTemperatureSummary: String {
        // Check Intel keys first, then Apple Silicon
        let cpuKeys: [SMCTemperatureKey] = [
            .cpuProximity, .cpuDie,       // Intel
            .apCpuPerf0, .apCpuEff0,      // Apple Silicon
            .apSoc0                        // Apple Silicon SoC
        ]
        if let cpu = readings.first(where: { cpuKeys.contains($0.key) }) {
            return cpu.formattedValue
        }
        // Check dynamic readings for CPU-like keys
        if let dynamic = dynamicReadings.first(where: {
            $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tp")
        }) {
            return dynamic.formattedValue
        }
        return unavailableReason != nil ? "Unavailable" : "–"
    }

    // MARK: - Private

    private var smcHelper: SMCHelper?
    private var timer:     Timer?

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

    /// Retry the SMC connection (e.g. after the user disables App Sandbox and relaunches).
    func retryConnection() {
        stopMonitoring()
        smcHelper = nil
        connect()
    }

    // MARK: - Private

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
            startMonitoring()
        }
    }

    private func poll() {
        guard let smc = smcHelper else { return }

        // Try known keys first.
        let knownReadings = SMCTemperatureKey.allCases.compactMap { key -> TemperatureReading? in
            guard let value = smc.temperature(for: key) else { return nil }
            return TemperatureReading(key: key, value: value)
        }

        if !knownReadings.isEmpty {
            readings        = knownReadings
            dynamicReadings = []
            unavailableReason = nil
        } else {
            // Fallback: discover sensors dynamically (handles Apple Silicon models
            // whose keys are not yet in the SMCTemperatureKey enum).
            let discovered = smc.discoverTemperatureSensors()
            if !discovered.isEmpty {
                readings        = []
                dynamicReadings = discovered.map {
                    DynamicTemperatureReading(key: $0.key, displayName: $0.displayName, value: $0.value)
                }
                unavailableReason = nil
            } else {
                readings          = []
                dynamicReadings   = []
                unavailableReason = """
                    SMC connected but no temperature sensors were found. \
                    This may indicate the app needs to run without App Sandbox, \
                    or your hardware uses different sensor types.
                    """
                stopMonitoring()
            }
        }
    }

    private func restartTimerIfNeeded() {
        guard isMonitoring else { return }
        stopMonitoring()
        startMonitoring()
    }
}

// MARK: - Dynamic Temperature Reading

/// A temperature reading discovered at runtime via SMC key enumeration.
struct DynamicTemperatureReading: Identifiable {
    let id          = UUID()
    let key:         String
    let displayName: String
    let value:       Double

    var formattedValue: String {
        String(format: "%.1f °C", value)
    }
}
