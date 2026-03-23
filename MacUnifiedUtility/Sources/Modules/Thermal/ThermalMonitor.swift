import Foundation
import Combine

/// Read-only temperature monitor.
///
/// Polls all known SMC temperature keys on a repeating timer and publishes
/// the latest readings to the UI.
@MainActor
final class ThermalMonitor: ObservableObject {

    // MARK: - Published State

    /// Current temperature readings for all available sensors.
    @Published var readings: [TemperatureReading] = []

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
        if let cpu = readings.first(where: { $0.key == .cpuProximity || $0.key == .cpuDie }) {
            return cpu.formattedValue
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
        let newReadings = SMCTemperatureKey.allCases.compactMap { key -> TemperatureReading? in
            guard let value = smc.temperature(for: key) else { return nil }
            return TemperatureReading(key: key, value: value)
        }

        if newReadings.isEmpty {
            unavailableReason = """
                SMC connected but no sensors responded. \
                On Apple Silicon Macs some sensor keys differ from Intel. \
                The app may need updated sensor keys for your hardware.
                """
            stopMonitoring()
        } else {
            unavailableReason = nil
            readings = newReadings
        }
    }

    private func restartTimerIfNeeded() {
        guard isMonitoring else { return }
        stopMonitoring()
        startMonitoring()
    }
}
