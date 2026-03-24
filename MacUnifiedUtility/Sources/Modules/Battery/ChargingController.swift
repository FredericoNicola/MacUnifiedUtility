import Foundation
import Combine

// MARK: - ChargingMode

/// Available SMC-controlled charging modes.
/// Mirrors BatFi's `SMCChargingCommand` from `BatFiKit/Sources/Shared/SMCChargingCommand.swift`.
enum ChargingMode: String, Codable, CaseIterable {
    /// Normal charging — battery charges to 100%.
    case auto
    /// Inhibit charging — stops charging at the current level.
    case inhibitCharging
    /// Force discharge — actively discharges even while plugged in.
    case forceDischarge
    /// System charge limit — uses macOS built-in Optimized Battery Charging (~80%).
    case enableSystemChargeLimit

    var displayName: String {
        switch self {
        case .auto:                   return "Auto"
        case .inhibitCharging:        return "Inhibit"
        case .forceDischarge:         return "Discharge"
        case .enableSystemChargeLimit: return "80% Limit"
        }
    }

    var modeDescription: String {
        switch self {
        case .auto:
            return "Battery charges normally to 100%."
        case .inhibitCharging:
            return "Charging is paused at the current level."
        case .forceDischarge:
            return "Battery actively discharges even while plugged in."
        case .enableSystemChargeLimit:
            return "Uses macOS built-in Optimized Battery Charging (limits to ~80%). Requires macOS Sequoia or later."
        }
    }
}

// MARK: - ChargingController

/// Manages SMC-based charging control via keys CH0I, CH0B, CH0C, and CHWA.
///
/// Mirrors the key combination used by rurza/BatFi's `SMCService.setChargingMode`.
/// Writing to these keys requires the app to run without App Sandbox.
final class ChargingController: ObservableObject {

    // MARK: - Published State

    /// The currently active charging mode.
    @Published private(set) var currentMode: ChargingMode = .auto

    /// `true` when SMC keys are readable and charging control is available.
    @Published private(set) var isAvailable: Bool = false

    // MARK: - Private

    private let smcKit: SMCKit?

    // MARK: - Init / Deinit

    init() {
        smcKit = SMCKit()
        isAvailable = smcKit != nil && canReadChargingKeys()
        if isAvailable {
            currentMode = detectCurrentMode()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            try? self?.setMode(.auto)
        }
    }

    deinit {
        try? setMode(.auto)
    }

    // MARK: - Public API

    /// Apply the given charging mode by writing the appropriate SMC key combination.
    ///
    /// | Mode                    | CH0I | CH0B | CH0C | CHWA |
    /// |-------------------------|------|------|------|------|
    /// | auto                    |  0   |  0   |  0   | off  |
    /// | inhibitCharging         |  0   |  2   |  2   | off  |
    /// | forceDischarge          |  1   |  0   |  0   | off  |
    /// | enableSystemChargeLimit |  0   |  0   |  0   | on   |
    func setMode(_ mode: ChargingMode) throws {
        guard let smc = smcKit else { return }

        switch mode {
        case .auto:
            try smc.writeUInt8("CH0I", value: 0)
            try smc.writeUInt8("CH0B", value: 0)
            try smc.writeUInt8("CH0C", value: 0)
            try smc.writeFlag("CHWA",  value: false)
        case .inhibitCharging:
            try smc.writeUInt8("CH0I", value: 0)
            try smc.writeUInt8("CH0B", value: 2)
            try smc.writeUInt8("CH0C", value: 2)
            try smc.writeFlag("CHWA",  value: false)
        case .forceDischarge:
            try smc.writeUInt8("CH0I", value: 1)
            try smc.writeUInt8("CH0B", value: 0)
            try smc.writeUInt8("CH0C", value: 0)
            try smc.writeFlag("CHWA",  value: false)
        case .enableSystemChargeLimit:
            try smc.writeUInt8("CH0I", value: 0)
            try smc.writeUInt8("CH0B", value: 0)
            try smc.writeUInt8("CH0C", value: 0)
            try smc.writeFlag("CHWA",  value: true)
        }

        currentMode = mode
    }

    // MARK: - Private Helpers

    private func canReadChargingKeys() -> Bool {
        smcKit?.readUInt8("CH0B") != nil
    }

    private func detectCurrentMode() -> ChargingMode {
        guard let smc = smcKit else { return .auto }
        let ch0i = smc.readUInt8("CH0I") ?? 0
        let ch0b = smc.readUInt8("CH0B") ?? 0
        let chwa = smc.readFlag("CHWA")  ?? false

        if ch0i == 1   { return .forceDischarge }
        if chwa        { return .enableSystemChargeLimit }
        if ch0b == 2   { return .inhibitCharging }
        return .auto
    }
}
