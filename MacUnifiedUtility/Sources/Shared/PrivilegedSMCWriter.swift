import Foundation
import Security

/// Attempts to write an SMC charge-limit value with elevated privileges.
///
/// First tries a direct (unprivileged) write. If that fails, uses the
/// SMJobBless privileged helper tool running as root to perform the write.
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

        // Unprivileged write failed — indicate the privileged helper should be used.
        return WriteResult(
            success: false,
            error: nil  // nil error = should try privileged helper
        )
    }

    /// Async version that uses the privileged helper tool for root-level SMC writes.
    @MainActor
    static func writeChargeLimitPrivileged(_ percent: Int, using smcKit: SMCKit?) async -> WriteResult {
        // Try unprivileged first
        let unprivResult = writeChargeLimit(percent, using: smcKit)
        if unprivResult.success {
            return unprivResult
        }

        // Use privileged helper
        let helperResult = await PrivilegedHelperManager.shared.writeChargeLimit(percent)
        return WriteResult(success: helperResult.success, error: helperResult.error)
    }
}
