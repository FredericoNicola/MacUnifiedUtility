import Foundation

/// The helper tool runs as root (installed via SMJobBless) and performs
/// privileged SMC operations on behalf of the main app via XPC.
class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        newConnection.exportedObject = HelperToolService()
        newConnection.resume()
        return true
    }
}

class HelperToolService: NSObject, PrivilegedHelperProtocol {
    func writeChargeLimitToSMC(percent: Int, withReply reply: @escaping (Bool, String?) -> Void) {
        // Open SMC connection as root
        guard let smc = SMCKit() else {
            reply(false, "Could not open SMC connection from helper tool.")
            return
        }
        let success = smc.writeChargeLimitPercent(percent)
        if success {
            reply(true, nil)
        } else {
            reply(false, "SMC write failed. The BCLM key may not be supported on this hardware.")
        }
    }

    func getHelperVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
}

let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "com.macunifiedutility.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
