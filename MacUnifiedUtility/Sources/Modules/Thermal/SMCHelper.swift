import Foundation
import IOKit

// MARK: - SMC Helper

/// Low-level read-only helper for Apple System Management Controller (SMC) access.
///
/// Uses IOKit to open a connection to `AppleSMC` and sends SMC sub-commands
/// via `IOConnectCallStructMethod`. Supports reading any numeric sensor type
/// (temperature, voltage, current, power, fan RPM) as well as enumerating
/// all available SMC keys.
///
/// > Important: SMC access requires the app to run without App Sandbox.
final class SMCHelper {

    // MARK: - IOKit Sub-command Selectors

    private static let kSMCHandleYPCEvent: UInt32 = 2  // fixed method selector
    private static let kSMCGetKeyInfo:     UInt32 = 9
    private static let kSMCGetKeyValue:    UInt32 = 5
    private static let kSMCGetKeyFromIndex: UInt32 = 8

    // MARK: - SMC Structures (must match kernel layout exactly)

    struct SMCVersion {
        var major:    CUnsignedChar = 0
        var minor:    CUnsignedChar = 0
        var build:    CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release:  CUnsignedShort = 0
    }

    struct SMCPLimitData {
        var version:   UInt16 = 0
        var length:    UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize:       IOByteCount32 = 0
        var dataType:       UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    struct SMCParamStruct {
        var key:        UInt32 = 0
        var vers:       SMCVersion = SMCVersion()
        var pLimitData: SMCPLimitData = SMCPLimitData()
        var keyInfo:    SMCKeyInfoData = SMCKeyInfoData()
        var result:     UInt8 = 0
        var status:     UInt8 = 0
        var data8:      UInt8 = 0
        var data32:     UInt32 = 0
        var bytes:      (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
             0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    // MARK: - Connection

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public API

    /// Returns all SMC key strings available on this machine (from `#KEY` + index enumeration).
    func getAllKeys() -> [String] {
        var keys: [String] = []

        // Read total key count from the #KEY meta-key.
        guard let count = readRawUInt32(key: "#KEY"), count > 0 else { return keys }

        let cap = min(count, 2_000)
        for i in 0..<cap {
            var inp = SMCParamStruct()
            var out = SMCParamStruct()
            inp.data8  = UInt8(Self.kSMCGetKeyFromIndex)
            inp.data32 = i
            guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { continue }
            let k = decodeKey(out.key)
            if !k.isEmpty { keys.append(k) }
        }
        return keys
    }

    /// Read a numeric value for an arbitrary SMC key. Returns `nil` if the key
    /// does not exist or the data type is not recognised.
    ///
    /// Decoded types:
    /// - `sp78` (0x73703738): signed fixed-point 7.8 → value / 256
    /// - `flt ` (0x666C7420): IEEE 754 single-precision float
    /// - `fpe2` (0x66706532): unsigned fixed-point 14.2 → value / 4
    /// - `ui8 ` (0x75693820): unsigned 8-bit integer
    /// - `ui16` (0x75693136): unsigned 16-bit integer
    /// - `ui32` (0x75693332): unsigned 32-bit integer
    func getValue(_ key: String) -> Double? {
        var inp = SMCParamStruct()
        var out = SMCParamStruct()
        inp.key   = fourCharCode(key)
        inp.data8 = UInt8(Self.kSMCGetKeyInfo)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { return nil }

        let dataType = out.keyInfo.dataType
        inp.keyInfo.dataSize = out.keyInfo.dataSize
        inp.data8 = UInt8(Self.kSMCGetKeyValue)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { return nil }

        return decodeValue(from: out, dataType: dataType)
    }

    /// Read a null-terminated UTF-8 string value for an SMC key (used for fan IDs).
    func getStringValue(_ key: String) -> String? {
        var inp = SMCParamStruct()
        var out = SMCParamStruct()
        inp.key   = fourCharCode(key)
        inp.data8 = UInt8(Self.kSMCGetKeyInfo)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { return nil }

        let size = Int(out.keyInfo.dataSize)
        inp.keyInfo.dataSize = out.keyInfo.dataSize
        inp.data8 = UInt8(Self.kSMCGetKeyValue)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess, size > 0 else { return nil }

        // Extract up to `size` bytes from the bytes tuple.
        let raw = withUnsafeBytes(of: out.bytes) { ptr in
            Array(ptr.prefix(size))
        }
        return String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
    }

    /// Convenience: read a temperature value (°C), returning nil for implausible readings.
    func readTemperature(for key: String) -> Double? {
        guard let v = getValue(key), v > -40, v < 125 else { return nil }
        return v
    }

    /// Returns the appropriate fan-mode SMC key for a given fan index.
    func fanModeKey(_ id: Int) -> String { "F\(id)Md" }

    // MARK: - Private: decode helpers

    private func decodeValue(from output: SMCParamStruct, dataType: UInt32) -> Double? {
        let b = output.bytes
        switch dataType {
        case 0x73703738: // sp78 – signed fixed-point 7.8
            let raw = (Int16(b.0) << 8) | Int16(b.1)
            return Double(raw) / 256.0

        case 0x666C7420: // flt  – IEEE 754 single-precision float (big-endian)
            let u = (UInt32(b.0) << 24) | (UInt32(b.1) << 16)
                  | (UInt32(b.2) << 8)  |  UInt32(b.3)
            return Double(Float(bitPattern: u))

        case 0x66706532: // fpe2 – unsigned fixed-point 14.2
            let raw = (UInt16(b.0) << 8) | UInt16(b.1)
            return Double(raw) / 4.0

        case 0x75693820: // ui8
            return Double(b.0)

        case 0x75693136: // ui16
            let raw = (UInt16(b.0) << 8) | UInt16(b.1)
            return Double(raw)

        case 0x75693332: // ui32
            let raw = (UInt32(b.0) << 24) | (UInt32(b.1) << 16)
                    | (UInt32(b.2) << 8)  |  UInt32(b.3)
            return Double(raw)

        default:
            return nil
        }
    }

    private func readRawUInt32(key: String) -> UInt32? {
        var inp = SMCParamStruct()
        var out = SMCParamStruct()
        inp.key   = fourCharCode(key)
        inp.data8 = UInt8(Self.kSMCGetKeyInfo)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { return nil }
        inp.keyInfo.dataSize = out.keyInfo.dataSize
        inp.data8 = UInt8(Self.kSMCGetKeyValue)
        guard callSMC(input: &inp, output: &out) == kIOReturnSuccess else { return nil }
        let b = out.bytes
        return (UInt32(b.0) << 24) | (UInt32(b.1) << 16) | (UInt32(b.2) << 8) | UInt32(b.3)
    }

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        let inputSize  = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(
            connection, Self.kSMCHandleYPCEvent,
            &input, inputSize, &output, &outputSize
        )
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, byte) in string.utf8.prefix(4).enumerated() {
            result |= UInt32(byte) << UInt32((3 - i) * 8)
        }
        return result
    }

    private func decodeKey(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >>  8) & 0xFF),
            UInt8( code        & 0xFF),
        ]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "" }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
