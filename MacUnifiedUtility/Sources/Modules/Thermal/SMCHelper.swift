import Foundation
import IOKit

// MARK: - SMC Key Constants

/// A selection of well-known Apple SMC temperature sensor keys.
/// All keys are 4-character ASCII strings defined by Apple's firmware.
enum SMCTemperatureKey: String, CaseIterable {
    case cpuProximity   = "TC0P"   // CPU Proximity
    case cpuDie         = "TC0D"   // CPU Die
    case cpuCore0       = "TC0c"   // CPU Core 0 (Apple Silicon style)
    case gpu            = "TG0D"   // GPU Die
    case gpuProximity   = "TG0P"   // GPU Proximity
    case heatsink       = "Th0H"   // Heatsink A
    case airflowLeft    = "TaLC"   // Airflow Left
    case airflowRight   = "TaRC"   // Airflow Right
    case battery        = "TB0T"   // Battery TS0

    var displayName: String {
        switch self {
        case .cpuProximity: return "CPU Proximity"
        case .cpuDie:       return "CPU Die"
        case .cpuCore0:     return "CPU Core 0"
        case .gpu:          return "GPU Die"
        case .gpuProximity: return "GPU Proximity"
        case .heatsink:     return "Heatsink"
        case .airflowLeft:  return "Airflow (Left)"
        case .airflowRight: return "Airflow (Right)"
        case .battery:      return "Battery"
        }
    }
}

// MARK: - SMC Helper

/// Low-level read-only helper for Apple System Management Controller (SMC) access.
///
/// Uses IOKit to open a connection to `AppleSMC` and sends `kSMCGetKeyValue`
/// calls via `IOConnectCallStructMethod`.
///
/// > Important: This class reads SMC data only; it never writes to the SMC.
/// > SMC access requires the app to run without App Sandbox.
final class SMCHelper {

    // MARK: - IOKit Constants

    /// The single method index used for all SMC operations via IOConnectCallStructMethod.
    /// The actual operation (GetKeyInfo, GetKeyValue, SetKeyValue) is encoded in `data8`.
    private static let kSMCHandleYPCEvent: UInt32 = 2

    private static let kSMCUserClientOpen:   UInt32 = 0
    private static let kSMCUserClientClose:  UInt32 = 1
    private static let kSMCGetKeyInfo:       UInt32 = 9
    private static let kSMCGetKeyValue:      UInt32 = 5

    // MARK: - SMC Structures (must match kernel layout exactly)

    struct SMCVersion {
        var major:    CUnsignedChar
        var minor:    CUnsignedChar
        var build:    CUnsignedChar
        var reserved: CUnsignedChar
        var release:  CUnsignedShort
    }

    struct SMCPLimitData {
        var version:   UInt16
        var length:    UInt16
        var cpuPLimit: UInt32
        var gpuPLimit: UInt32
        var memPLimit: UInt32
    }

    struct SMCKeyInfoData {
        var dataSize:       IOByteCount32
        var dataType:       UInt32
        var dataAttributes: UInt8
    }

    struct SMCParamStruct {
        var key:      UInt32
        var vers:     SMCVersion
        var pLimitData: SMCPLimitData
        var keyInfo:  SMCKeyInfoData
        var result:   UInt8
        var status:   UInt8
        var data8:    UInt8
        var data32:   UInt32
        var bytes:    (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    }

    // MARK: - Internal State

    private var connection: io_connect_t = 0

    // MARK: - Lifecycle

    /// Opens a connection to the AppleSMC IOKit service.
    /// Returns `nil` if the service cannot be found (e.g., on non-Apple hardware or VMs).
    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    // MARK: - Public Read API

    /// Read a temperature value (°C) for the given SMC key.
    /// Returns `nil` if the key is not supported on this machine.
    func temperature(for key: SMCTemperatureKey) -> Double? {
        readTemperature(key: key.rawValue)
    }

    // MARK: - Private Helpers

    private func readTemperature(key keyString: String) -> Double? {
        var inputStruct  = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key   = fourCharCode(keyString)
        inputStruct.data8 = UInt8(Self.kSMCGetKeyInfo)

        guard callSMC(input: &inputStruct, output: &outputStruct) == kIOReturnSuccess else {
            return nil
        }

        // Re-use the key info to read the value.
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8            = UInt8(Self.kSMCGetKeyValue)

        guard callSMC(input: &inputStruct, output: &outputStruct) == kIOReturnSuccess else {
            return nil
        }

        // Temperature values are encoded as a fixed-point `sp78` type:
        //   byte[0] is the integer part, byte[1] is the fractional (in 1/256 °C)
        let rawBytes = outputStruct.bytes
        let intPart  = Double(rawBytes.0)
        let fracPart = Double(rawBytes.1) / 256.0
        let celsius  = intPart + fracPart

        // Sanity-check: plausible sensor range −40 … 125 °C
        guard celsius > -40, celsius < 125 else { return nil }
        return celsius
    }

    /// Invoke an SMC operation via IOKit using a fixed method selector.
    /// The operation is determined by the `data8` field in the input struct.
    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        var inputSize  = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        return IOConnectCallStructMethod(
            connection,
            Self.kSMCHandleYPCEvent,   // Method selector 2: handles all SMC sub-commands
            &input,  inputSize,
            &output, &outputSize
        )
    }

    /// Pack a 4-character ASCII string into a `UInt32` big-endian key.
    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for (index, char) in string.utf8.prefix(4).enumerated() {
            result |= UInt32(char) << UInt32((3 - index) * 8)
        }
        return result
    }
}

// MARK: - Temperature Reading

/// A single temperature sensor reading.
struct TemperatureReading: Identifiable {
    let id   = UUID()
    let key:   SMCTemperatureKey
    let value: Double   // °C

    var formattedValue: String {
        String(format: "%.1f °C", value)
    }
}
