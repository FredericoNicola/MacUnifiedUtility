import AppKit
import ApplicationServices

/// Helper for checking and requesting macOS Accessibility permissions.
///
/// CGEvent taps (used by `ScrollManager`) require the app to have
/// Accessibility access granted in System Settings → Privacy & Security →
/// Accessibility.
enum PermissionsHelper {

    // MARK: - Accessibility

    /// Returns `true` if the app currently has Accessibility permission.
    ///
    /// - Parameter promptIfNeeded: When `true`, shows the system prompt asking
    ///   the user to grant Accessibility access if it is not already granted.
    static func isAccessibilityEnabled(promptIfNeeded: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Deep-Link to System Settings

    /// Opens the Accessibility pane in System Settings (macOS 13+) or
    /// System Preferences (macOS 12 and earlier).
    static func openAccessibilitySettings() {
        // Both macOS 13+ (Ventura) and macOS 12 (Monterey) use the same
        // x-apple.systempreferences URL scheme for the Accessibility pane.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
