import Foundation
import Security
import ServiceManagement

/// Manages privileged SMC write access via the bundled XPC helper daemon.
///
/// Writing to SMC keys like BCLM requires root privileges. Rather than
/// relaunching the whole app as root (which `open` cannot achieve), this
/// manager installs a launchd daemon via `SMAppService` / `SMJobBless` and
/// communicates with it over XPC.
@MainActor
final class PrivilegedHelperManager: ObservableObject {

    static let shared = PrivilegedHelperManager()

    private static let helperServiceName = "com.macunifiedutility.helper"

    /// `true` when the XPC helper is installed and responding.
    @Published var hasRootAccess: Bool = false

    /// Last error message from a privileged operation.
    @Published var lastError: String?

    /// Live XPC proxy to the privileged helper; non-nil only when connected.
    private(set) var helperProxy: PrivilegedHelperProtocol?

    private var xpcConnection: NSXPCConnection?

    private init() {
        // Attempt to reach an already-installed helper on startup.
        tryConnectToHelper()
    }

    // MARK: - Public API

    /// Install (or re-register) the privileged helper daemon and open an XPC
    /// connection to it. On success `hasRootAccess` becomes `true` and
    /// `helperProxy` is set so that `BatteryManager` can route SMC writes
    /// through the helper.
    func installHelper() {
        lastError = nil
        if #available(macOS 13.0, *) {
            registerWithSMAppService()
        } else {
            installWithSMJobBless()
        }
    }

    // MARK: - SMAppService (macOS 13+)

    @available(macOS 13.0, *)
    private func registerWithSMAppService() {
        let service = SMAppService.daemon(
            plistName: "com.macunifiedutility.helper-Launchd.plist"
        )
        do {
            try service.register()
        } catch {
            // Proceed when the service is already registered or pending approval.
            let status = service.status
            guard status == .enabled || status == .requiresApproval else {
                lastError = "Could not register privileged helper: \(error.localizedDescription)"
                return
            }
        }
        tryConnectToHelper()
    }

    // MARK: - SMJobBless (macOS 10.13 – 12)

    private func installWithSMJobBless() {
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
              let auth = authRef else {
            lastError = "Could not obtain an authorization reference."
            return
        }
        defer { AuthorizationFree(auth, []) }

        var cfError: Unmanaged<CFError>?
        if SMJobBless(kSMJobTypeDaemon,
                      Self.helperServiceName as CFString,
                      auth, &cfError) {
            tryConnectToHelper()
        } else {
            let detail = cfError.map { String(describing: $0.takeRetainedValue()) }
                         ?? "Unknown error"
            lastError = "Could not install privileged helper: \(detail)"
        }
    }

    // MARK: - XPC Connection

    private func tryConnectToHelper() {
        // Tear down any stale connection first.
        xpcConnection?.invalidate()
        xpcConnection = nil
        helperProxy   = nil

        let conn = NSXPCConnection(
            machServiceName: Self.helperServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.xpcConnection = nil
                self?.helperProxy   = nil
                self?.hasRootAccess = false
            }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.hasRootAccess = false
            }
        }
        conn.resume()
        xpcConnection = conn

        // Ping the helper to confirm it is alive before advertising availability.
        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor [weak self] in
                self?.hasRootAccess = false
                self?.lastError = "Could not connect to privileged helper: \(error.localizedDescription)"
            }
        } as? PrivilegedHelperProtocol

        proxy?.getHelperVersion { [weak self] _ in
            Task { @MainActor [weak self] in
                // Store the proxy only after a successful ping response.
                self?.helperProxy   = proxy
                self?.hasRootAccess = true
                self?.lastError     = nil
            }
        }
    }
}

