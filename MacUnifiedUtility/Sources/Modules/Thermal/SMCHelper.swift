import Foundation
import IOKit

// MARK: - SMC Key Constants

/// A selection of well-known Apple SMC temperature sensor keys.
/// All keys are 4-character ASCII strings defined by Apple's firmware.
enum SMCTemperatureKey: String, CaseIterable {
    // ── Intel keys ────────────────────────────────
    case cpuProximity   = "TC0P"
    case cpuDie         = "TC0D"
    case gpu            = "TG0D"
    case gpuProximity   = "TG0P"
    case heatsink       = "Th0H"
    case airflowLeft    = "TaLC"
    case airflowRight   = "TaRC"
    case battery        = "TB0T"

    // ── Apple Silicon keys (M1/M2/M3/M4) ─────────
    case apCpuPerf0     = "Tp09"   // CPU performance core 0
    case apCpuPerf1     = "Tp0T"   // CPU performance core 1
    case apCpuEff0      = "Tp01"   // CPU efficiency core 0
    case apCpuEff1      = "Tp05"   // CPU efficiency core 1
    case apGpu0         = "Tg05"   // GPU cluster
    case apSoc0         = "Tp0C"   // SoC (system-on-chip)
    case apMemory       = "Tm02"   // Memory controller
    case apANE          = "Tp2c"   // Apple Neural Engine

    var displayName: String {
        switch self {
        case .cpuProximity:  return "CPU Proximity"
        case .cpuDie:        return "CPU Die"
        case .gpu:           return "GPU Die"
        case .gpuProximity:  return "GPU Proximity"
        case .heatsink:      return "Heatsink"
        case .airflowLeft:   return "Airflow (Left)"
        case .airflowRight:  return "Airflow (Right)"
        case .battery:       return "Battery"
        case .apCpuPerf0:    return "CPU P-Core 0"
        case .apCpuPerf1:    return "CPU P-Core 1"
        case .apCpuEff0:     return "CPU E-Core 0"
        case .apCpuEff1:     return "CPU E-Core 1"
        case .apGpu0:        return "GPU"
        case .apSoc0:        return "SoC"
        case .apMemory:      return "Memory"
        case .apANE:         return "Neural Engine"
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
    // Default zero values allow no-argument initialization: SMCParamStruct()

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
        let inputSize  = MemoryLayout<SMCParamStruct>.stride
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
