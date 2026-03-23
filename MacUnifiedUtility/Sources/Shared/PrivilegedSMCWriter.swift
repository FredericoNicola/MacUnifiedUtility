import Foundation

/// Attempts to write an SMC charge-limit value, with clear feedback
/// about privilege requirements.
enum PrivilegedSMCWriter {

    // MARK: - Result

    struct WriteResult {
        let success: Bool
        let error: String?
        let needsPrivileges: Bool
    }

    // MARK: - Public API

    /// Write `percent` to SMC key `BCLM`.
    ///
    /// - Parameters:
    ///   - percent: Target charge limit (0–100).
    ///   - smcKit: An existing `SMCKit` connection, or `nil`.
    /// - Returns: A `WriteResult` indicating success, an optional error message,
    ///            and whether elevated privileges are required.
    @MainActor
    static func writeChargeLimit(_ percent: Int, using smcKit: SMCKit?) -> WriteResult {
        guard percent >= 0, percent <= 100 else {
            return WriteResult(success: false,
                               error: "Charge limit must be between 0 and 100.",
                               needsPrivileges: false)
        }

        // Try direct write (succeeds when running as root or firmware allows it).
        if let smc = smcKit, smc.writeChargeLimitPercent(percent) {
            return WriteResult(success: true, error: nil, needsPrivileges: false)
        }

        // Direct write failed.
        if getuid() == 0 {
            // We're root but the write still failed — hardware may not support BCLM.
            return WriteResult(
                success: false,
                error: "SMC write failed. The BCLM key may not be supported on this hardware.",
                needsPrivileges: false
            )
        }

        // Not root — needs elevation.
        return WriteResult(
            success: false,
            error: "Writing to the BCLM SMC key requires administrator privileges.",
            needsPrivileges: true
        )
    }
}
