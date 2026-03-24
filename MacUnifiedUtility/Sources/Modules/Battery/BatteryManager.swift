import Foundation
import Combine

/// Coordinates battery state reading and SMC-based charging control.
///
/// Rewritten to use `BatteryReader` (event-driven via `IOPSNotificationCreateRunLoopSource`)
/// and `ChargingController` (CH0I / CH0B / CH0C / CHWA SMC keys).
@MainActor
final class BatteryManager: ObservableObject {

    // MARK: - Published State

    /// Full battery + power-source snapshot; `nil` when no battery is present.
    @Published private(set) var powerState: PowerState?

    /// `true` when the Mac has an internal battery (i.e., is a laptop).
    @Published private(set) var isOnLaptop: Bool = false

    /// The currently active SMC charging mode.
    @Published private(set) var chargingMode: ChargingMode = .auto

    /// `true` when SMC charging keys are accessible (app not sandboxed).
    @Published private(set) var chargingControlAvailable: Bool = false

    // MARK: - Convenience

    /// Short human-readable summary shown in the menu-bar popover.
    var statusSummary: String {
        guard let state = powerState else { return "No Battery" }
        let icon = state.isCharging ? "⚡" : (state.chargerConnected ? "🔌" : "🔋")
        return "\(icon) \(state.batteryLevel)%"
    }

    // MARK: - Private

    private let reader     = BatteryReader()
    private let controller = ChargingController()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Wire reader callbacks → published properties.
        reader.onUpdate = { [weak self] state in
            self?.powerState = state
        }
        reader.onLaptopDetected = { [weak self] isLaptop in
            self?.isOnLaptop = isLaptop
        }

        // Mirror controller's published properties.
        controller.$currentMode
            .receive(on: RunLoop.main)
            .assign(to: &$chargingMode)
        controller.$isAvailable
            .receive(on: RunLoop.main)
            .assign(to: &$chargingControlAvailable)

        // Reset to auto on quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setChargingMode(.auto)
        }

        // Initial read.
        reader.refresh()
    }

    // MARK: - Public API

    /// Apply a new SMC charging mode.
    func setChargingMode(_ mode: ChargingMode) {
        try? controller.setMode(mode)
    }
}
