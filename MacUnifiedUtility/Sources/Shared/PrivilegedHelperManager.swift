import Foundation

/// Manages privileged SMC write access.
///
/// Writing to SMC keys like BCLM requires root privileges. This manager
/// provides status information and guidance for obtaining the necessary access.
@MainActor
final class PrivilegedHelperManager: ObservableObject {

    static let shared = PrivilegedHelperManager()

    /// Whether the app currently has root privileges.
    @Published var hasRootAccess: Bool

    /// Last error message from a privileged operation.
    @Published var lastError: String?

    private init() {
        hasRootAccess = (getuid() == 0)
    }

    /// Attempt to relaunch the app with administrator privileges.
    func relaunchWithPrivileges() {
        let appPath = Bundle.main.bundlePath
        let escaped = appPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script  = "do shell script \"open \\\"\(escaped)\\\"\" with administrator privileges"

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let err = error {
                lastError = "Could not relaunch with admin privileges: \(err)"
            } else {
                // The new instance will launch as root; quit this one.
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

