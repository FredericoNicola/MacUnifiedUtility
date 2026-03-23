import Foundation

/// Protocol for XPC communication between the main app and the privileged helper.
@objc protocol PrivilegedHelperProtocol {
    func writeChargeLimitToSMC(percent: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func getHelperVersion(withReply reply: @escaping (String) -> Void)
}
