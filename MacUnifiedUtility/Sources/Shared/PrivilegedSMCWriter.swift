import Foundation
import Security

/// Attempts to write an SMC charge-limit value with elevated privileges.
///
/// First tries a direct write via the existing `SMCKit` connection. If that
/// fails (typical when the process is not running as root), it requests
/// administrator authorisation through the standard macOS password dialog
/// and then retries the write. On hardware or firmware that actively blocks
/// the `BCLM` key, the write will still fail even with authorisation.
enum PrivilegedSMCWriter {

    // MARK: - Result

    struct WriteResult {
        let success: Bool
        let error: String?
    }

    // MARK: - Public API

    /// Write `percent` to SMC key `BCLM`, escalating privileges if needed.
    ///
    /// - Parameters:
    ///   - percent: Target charge limit (0–100).
    ///   - smcKit: An existing `SMCKit` connection, or `nil` to create a new one.
    /// - Returns: A `WriteResult` indicating success and an optional error message.
    @MainActor
    static func writeChargeLimit(_ percent: Int, using smcKit: SMCKit?) -> WriteResult {
        guard percent >= 0, percent <= 100 else {
            return WriteResult(success: false, error: "Charge limit must be between 0 and 100.")
        }

        // Attempt unprivileged write first (succeeds when sandbox is off and
        // firmware allows it).
        if let smc = smcKit, smc.writeChargeLimitPercent(percent) {
            return WriteResult(success: true, error: nil)
        }

        // Request administrator authorisation — shows the macOS password dialog.
        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let auth = authRef else {
            return WriteResult(success: false, error: "Could not create an authorisation request.")
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        let rightName = "com.macunifiedutility.smcwrite"
        let authStatus: OSStatus = rightName.withCString { namePtr in
            var item = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                return AuthorizationCopyRights(auth, &rights, nil, flags, nil)
            }
        }

        switch authStatus {
        case errAuthorizationSuccess:
            break
        case errAuthorizationCanceled:
            return WriteResult(success: false, error: "Authorisation was cancelled.")
        default:
            return WriteResult(
                success: false,
                error: "Authorisation failed (error \(authStatus))."
            )
        }

        // Retry the write after authorisation. On some systems, having an
        // admin session token is sufficient for IOKit to allow the write.
        if let smc = smcKit, smc.writeChargeLimitPercent(percent) {
            return WriteResult(success: true, error: nil)
        }

        // If a fresh SMCKit connection also fails, the firmware is blocking
        // the write regardless of user privileges.
        if let freshSMC = SMCKit(), freshSMC.writeChargeLimitPercent(percent) {
            return WriteResult(success: true, error: nil)
        }

        return WriteResult(
            success: false,
            error: "Could not write charge limit to SMC. " +
                   "Writing to BCLM requires root-level access that cannot be " +
                   "obtained through standard authorisation. " +
                   "This feature may not be supported on your hardware."
        )
    }
}
