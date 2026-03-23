import Foundation
import ServiceManagement
import Security

/// Manages installation and communication with the SMJobBless privileged helper.
@MainActor
final class PrivilegedHelperManager: ObservableObject {

    static let shared = PrivilegedHelperManager()

    static let helperBundleID = "com.macunifiedutility.helper"

    @Published var isHelperInstalled = false
    @Published var lastError: String?

    private var xpcConnection: NSXPCConnection?

    private init() {
        checkHelperStatus()
    }

    // MARK: - Helper Installation

    /// Install the privileged helper via SMJobBless.
    /// Shows the macOS admin password dialog.
    @discardableResult
    func installHelper() -> Bool {
        // Create authorization
        var authRef: AuthorizationRef?
        var authItem = AuthorizationItem(
            name: kSMRightBlessPrivilegedHelper,
            valueLength: 0,
            value: nil,
            flags: 0
        )
        var authRights = AuthorizationRights(count: 1, items: &authItem)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]

        let createStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        guard createStatus == errAuthorizationSuccess else {
            lastError = "Could not create authorization (error \(createStatus))."
            return false
        }
        defer {
            if let auth = authRef {
                AuthorizationFree(auth, [.destroyRights])
            }
        }

        // Bless the helper
        var cfError: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            Self.helperBundleID as CFString,
            authRef,
            &cfError
        )

        if success {
            isHelperInstalled = true
            lastError = nil
            return true
        } else {
            let error = cfError?.takeRetainedValue()
            lastError = "Failed to install helper: \(error?.localizedDescription ?? "unknown error")"
            isHelperInstalled = false
            return false
        }
    }

    // MARK: - Helper Communication

    /// Get an XPC connection to the helper tool.
    func connection() -> NSXPCConnection {
        if let conn = xpcConnection {
            return conn
        }
        let conn = NSXPCConnection(machServiceName: Self.helperBundleID, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.xpcConnection = nil
            }
        }
        conn.resume()
        xpcConnection = conn
        return conn
    }

    /// Write charge limit using the privileged helper.
    func writeChargeLimit(_ percent: Int) async -> (success: Bool, error: String?) {
        // Ensure helper is installed
        if !isHelperInstalled {
            guard installHelper() else {
                return (false, lastError ?? "Helper installation failed.")
            }
        }

        return await withCheckedContinuation { continuation in
            let proxy = connection().remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: (false, "XPC error: \(error.localizedDescription)"))
            } as? PrivilegedHelperProtocol

            proxy?.writeChargeLimitToSMC(percent: percent) { success, error in
                continuation.resume(returning: (success, error))
            }
        }
    }

    // MARK: - Private

    private func checkHelperStatus() {
        // Check if helper is already installed by trying to connect
        let conn = NSXPCConnection(machServiceName: Self.helperBundleID, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.isHelperInstalled = false
                conn.invalidate()
            }
        } as? PrivilegedHelperProtocol

        proxy?.getHelperVersion { [weak self] _ in
            Task { @MainActor in
                self?.isHelperInstalled = true
                conn.invalidate()
            }
        }
    }
}
