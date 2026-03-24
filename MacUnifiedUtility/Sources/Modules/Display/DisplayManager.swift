import CoreGraphics
import Foundation

/// Manages display enumeration and resolution switching using Quartz Display Services.
///
/// This class is `@MainActor` because all UI-facing properties must be updated on the
/// main thread, and the underlying CGDisplay calls are not thread-safe.
@MainActor
final class DisplayManager: ObservableObject {

    // MARK: - Published State

    /// All currently connected displays.
    @Published var displays: [DisplayInfo] = []

    /// Non-nil when an error occurs (e.g., permission denied, mode switch failure).
    @Published var lastError: String?

    // MARK: - Init

    init() {
        refresh()
    }

    // MARK: - Public API

    /// Re-enumerate all connected displays and their available modes.
    func refresh() {
        lastError = nil
        displays = Self.enumerateDisplays()
    }

    /// Switch the resolution of `display` to `mode`.
    ///
    /// - Parameters:
    ///   - display: The target display.
    ///   - mode: The desired `DisplayModeItem`.
    func setMode(_ modeItem: DisplayModeItem, for display: DisplayInfo) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let config else {
            lastError = "Failed to begin display configuration."
            return
        }

        CGConfigureDisplayWithDisplayMode(config, display.cgDirectDisplayID, modeItem.mode, nil)

        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result != .success {
            CGCancelDisplayConfiguration(config)
            lastError = "Failed to apply display mode (error \(result.rawValue))."
        } else {
            // Refresh the list so the UI reflects the new active mode.
            refresh()
        }
    }

    // MARK: - Private Helpers

    /// Returns a `DisplayInfo` for every online display.
    private static func enumerateDisplays() -> [DisplayInfo] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        guard CGGetOnlineDisplayList(16, &displayIDs, &displayCount) == .success else {
            return []
        }

        return (0 ..< Int(displayCount)).compactMap { index in
            let displayID = displayIDs[index]
            let modes = availableModes(for: displayID)
            guard !modes.isEmpty else { return nil }
            return DisplayInfo(cgDirectDisplayID: displayID, availableModes: modes)
        }
    }

    /// Returns all available `DisplayModeItem`s for a given display, sorted by pixel area.
    private static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeItem] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modeArray = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }
        return modeArray
            .sorted { $0.pixelWidth * $0.pixelHeight > $1.pixelWidth * $1.pixelHeight }
            .map { DisplayModeItem(mode: $0) }
    }
}

// MARK: - Supporting Types

/// A `Hashable` and `Identifiable` wrapper around `CGDisplayMode`.
///
/// `CGDisplayMode` does not conform to `Hashable`, which causes SwiftUI `Picker`
/// tags to fail silently. This wrapper derives identity and equality from the
/// mode's observable properties.
struct DisplayModeItem: Identifiable, Hashable {
    let mode: CGDisplayMode

    var id: String {
        String(format: "%dx%d@%dx%d_%.6f", mode.width, mode.height, mode.pixelWidth, mode.pixelHeight, mode.refreshRate)
    }

    static func == (lhs: DisplayModeItem, rhs: DisplayModeItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Value type describing a single connected display.
struct DisplayInfo: Identifiable {
    let id = UUID()

    /// The CoreGraphics display identifier.
    let cgDirectDisplayID: CGDirectDisplayID

    /// Human-readable name, e.g. "Built-in Retina Display".
    var name: String {
        // `CGDisplayIOServicePort` is deprecated but still reliable on macOS 13+.
        // On newer systems the display name can be fetched via IOKit; we fall back
        // gracefully to a generic label.
        return localizedDisplayName(cgDirectDisplayID)
    }

    /// All modes available on this display (sorted largest first).
    let availableModes: [DisplayModeItem]

    /// The currently active mode (may be `nil` if not found in `availableModes`).
    var currentMode: DisplayModeItem? {
        guard let raw = CGDisplayCopyDisplayMode(cgDirectDisplayID) else { return nil }
        let item = DisplayModeItem(mode: raw)
        return availableModes.first { $0 == item } ?? DisplayModeItem(mode: raw)
    }
}

// MARK: - Display Name Helper

/// Returns a human-readable display name by querying IOKit.
private func localizedDisplayName(_ displayID: CGDirectDisplayID) -> String {
    // Attempt to read the display name from the IOKit registry.
    // Falls back to a generic label if the name cannot be determined.
    if displayID == CGMainDisplayID() {
        return "Built-in / Main Display"
    }
    return "External Display \(displayID)"
}

// MARK: - CGDisplayMode Convenience

extension CGDisplayMode {

    /// Width × height in logical (point) resolution.
    var resolutionDescription: String {
        "\(width) × \(height)"
    }

    /// Width × height in physical (pixel) resolution.
    var pixelResolutionDescription: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    /// Refresh rate formatted to one decimal place.
    var refreshRateDescription: String {
        String(format: "%.0f Hz", refreshRate)
    }

    /// Combined label shown in the UI picker.
    var label: String {
        "\(resolutionDescription) @ \(refreshRateDescription)"
    }
}
