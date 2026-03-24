import Foundation
import IOKit.ps

/// Reads battery status via IOKit Power Sources and (experimentally) exposes a
/// charge-limit setting through an SMC write.
///
/// > Warning: Setting the charge limit via SMC is **experimental** and
/// > **unsupported by Apple**. The underlying SMC key (`BCLM`) may not exist
/// > on all hardware. Use at your own risk.
@MainActor
final class BatteryManager: ObservableObject {

    // MARK: - Published State

    /// Battery charge percentage (0–100), or `nil` if no battery is present.
    @Published var chargePercent: Int?

    /// Whether the Mac is currently connected to AC power.
    @Published var isPluggedIn = false

    /// Whether the battery is currently charging.
    @Published var isCharging = false

    /// Whether the charge limit feature is enabled (experimental).
    @Published var isChargeLimitEnabled = false {
        didSet { applyChargeLimitIfNeeded() }
    }

    /// The target charge limit (percentage), used when `isChargeLimitEnabled` is true.
    @Published var chargeLimitPercent: Int = 80 {
        didSet {
            if isChargeLimitEnabled {
                applyChargeLimitIfNeeded()
            }
        }
    }

    /// Non-nil when a user-facing error or warning should be shown.
    @Published var lastMessage: String?

    /// Non-nil when an SMC write error occurs.
    @Published var lastError: String?

    // MARK: - Convenience

    var statusSummary: String {
        guard let pct = chargePercent else { return "No Battery" }
        let status = isCharging ? "⚡ Charging" : (isPluggedIn ? "🔌 Plugged In" : "🔋")
        return "\(status) \(pct)%"
    }

    // MARK: - Private

    private var pollingTimer: Timer?
    private var smcKit: SMCKit?

    // MARK: - Init

    init() {
        smcKit = SMCKit()
        refresh()
        startPolling()
    }

    // MARK: - Public API

    /// Re-read the current battery state from IOKit.
    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            chargePercent = nil
            return
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            // Only process internal batteries.
            guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            chargePercent = info[kIOPSCurrentCapacityKey] as? Int
            isPluggedIn   = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            isCharging    = (info[kIOPSIsChargingKey] as? Bool) ?? false
            break
        }
    }

    // MARK: - Private

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Attempt to write the charge limit to SMC key `BCLM`.
    ///
    /// When the privileged XPC helper is connected, the write is routed
    /// through it (runs as root). Otherwise, a direct unprivileged write is
    /// tried; if that also fails, the user is prompted to install the helper.
    ///
    /// > This is experimental and may silently fail on unsupported hardware.
    private func applyChargeLimitIfNeeded() {
        lastError = nil
        guard isChargeLimitEnabled else {
            lastMessage = "Charge limit disabled – battery will charge to 100%."
            _ = PrivilegedSMCWriter.writeChargeLimit(100, using: smcKit)
            return
        }

        let target = chargeLimitPercent

        // Route through the XPC helper when it is connected (runs as root).
        if let proxy = PrivilegedHelperManager.shared.helperProxy {
            proxy.writeChargeLimitToSMC(percent: target) { [weak self] success, errorMessage in
                Task { @MainActor [weak self] in
                    if success {
                        self?.lastMessage = "Charge limit set to \(target)% via privileged helper."
                        self?.lastError   = nil
                    } else {
                        self?.lastError   = errorMessage
                            ?? "Could not write charge limit via privileged helper."
                        self?.lastMessage = nil
                    }
                }
            }
            return
        }

        // Fall back to a direct (unprivileged) write.
        let result = PrivilegedSMCWriter.writeChargeLimit(target, using: smcKit)
        if result.success {
            lastMessage = "Charge limit set to \(target)% via SMC."
        } else if result.needsPrivileges {
            lastError = "Administrator privileges required. Use \"Install Privileged Helper\" in the Battery settings to enable charge limiting."
        } else {
            lastError = result.error
                ?? "Could not write charge limit. This feature may not be supported on your hardware."
        }
    }
}
