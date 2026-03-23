import Foundation
import IOKit

/// Shared SMC communication layer used by ThermalModule and BatteryModule.
///
/// Provides both read and (experimental) write access to the Apple SMC.
///
/// > Warning: Writing to the SMC is experimental and may not work on all
/// > hardware. Always verify the key exists before writing.
final class SMCKit {

    // MARK: - IOKit Selectors

    /// Fixed method index for all SMC operations via IOConnectCallStructMethod.
    /// Sub-commands (GetKeyInfo=9, GetKeyValue=5, SetKeyValue=6) are set in `data8`.
    private static let kSMCHandleYPCEvent: UInt32 = 2

    private static let kSMCGetKeyValue: UInt32 = 5
    private static let kSMCSetKeyValue: UInt32 = 6
    private static let kSMCGetKeyInfo:  UInt32 = 9

    // MARK: - SMC Data Structures

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
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
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

    /// Read a raw double value from an SMC key string.
    func readDouble(key: String) -> Double? {
        var inputStruct  = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key   = fourCharCode(key)
        inputStruct.data8 = UInt8(Self.kSMCGetKeyInfo)

        guard callSMC(input: &inputStruct, output: &outputStruct) == kIOReturnSuccess else {
            return nil
        }

        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8            = UInt8(Self.kSMCGetKeyValue)

        guard callSMC(input: &inputStruct, output: &outputStruct) == kIOReturnSuccess else {
            return nil
        }

        // Decode sp78 fixed-point temperature.
        let b0 = Double(outputStruct.bytes.0)
        let b1 = Double(outputStruct.bytes.1) / 256.0
        return b0 + b1
    }

    /// Experimental: Write a charge-limit percentage to SMC key `BCLM`.
    ///
    /// Returns `true` on apparent success, `false` otherwise.
    /// This uses the `ui8` SMC data type (1-byte unsigned integer).
    @discardableResult
    func writeChargeLimitPercent(_ percent: Int) -> Bool {
        let clampedPercent = min(max(percent, 0), 100)
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        // Key BCLM = Battery Charge Level Maximum
        inputStruct.key             = fourCharCode("BCLM")
        inputStruct.data8           = UInt8(Self.kSMCSetKeyValue)
        inputStruct.keyInfo.dataSize = 1      // ui8 = 1 byte
        inputStruct.bytes.0         = UInt8(clampedPercent)

        let result = callSMC(input: &inputStruct, output: &outputStruct)
        return result == kIOReturnSuccess
    }

    // MARK: - Private Helpers

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        let inputSize  = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        // All SMC operations route through method selector 2 (kSMCHandleYPCEvent).
        // The sub-command (GetKeyInfo, GetKeyValue, SetKeyValue) is encoded in data8.
        return IOConnectCallStructMethod(connection, Self.kSMCHandleYPCEvent, &input, inputSize, &output, &outputSize)
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, byte) in string.utf8.prefix(4).enumerated() {
            result |= UInt32(byte) << UInt32((3 - i) * 8)
        }
        return result
    }
}
