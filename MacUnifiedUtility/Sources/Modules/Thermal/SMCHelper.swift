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

    // ── Apple Silicon – CPU Performance Cores ─────
    case apCpuPerf0     = "Tp09"
    case apCpuPerf1     = "Tp0T"
    case apCpuPerf2     = "Tp0S"
    case apCpuPerf3     = "Tp0R"
    case apCpuPerf4     = "Tp0Q"
    case apCpuPerf5     = "Tp0P"

    // ── Apple Silicon – CPU Efficiency Cores ──────
    case apCpuEff0      = "Tp01"
    case apCpuEff1      = "Tp05"
    case apCpuEff2      = "Tp0D"
    case apCpuEff3      = "Tp0H"

    // ── Apple Silicon – GPU ───────────────────────
    case apGpu0         = "Tg05"
    case apGpu1         = "Tg0D"
    case apGpu2         = "Tg0L"
    case apGpu3         = "Tg0T"

    // ── Apple Silicon – SoC / System ──────────────
    case apSoc0         = "Tp0C"
    case apSoc1         = "Tp0c"

    // ── Apple Silicon – Memory ────────────────────
    case apMemory       = "Tm02"
    case apMemory1      = "TM0P"
    case apMemory2      = "Tm0P"
    case apMemory3      = "Tm1P"

    // ── Apple Silicon – Neural Engine ─────────────
    case apANE          = "Tp2c"

    // ── Apple Silicon – SSD ───────────────────────
    case apSSD          = "Ts0P"
    case apSSD1         = "Ts1P"

    // ── Apple Silicon – Ambient ───────────────────
    case apAmbient      = "Ta0p"
    case apAmbient1     = "TA0P"

    // ── Apple Silicon – Thunderbolt ───────────────
    case apThunderbolt0 = "Th0a"
    case apThunderbolt1 = "Th1a"
    case apThunderbolt2 = "Th2a"

    // ── Apple Silicon – Battery (additional) ──────
    case apBattery1     = "TB1T"
    case apBattery2     = "TB2T"
    case apBatteryExt   = "TBXT"

    // ── Apple Silicon – Power Supply ──────────────
    case apPowerSupply  = "Tp0X"
    case apPowerSupply1 = "Tp0Z"

    var displayName: String {
        switch self {
        // Intel
        case .cpuProximity:    return "CPU Proximity"
        case .cpuDie:          return "CPU Die"
        case .gpu:             return "GPU Die"
        case .gpuProximity:    return "GPU Proximity"
        case .heatsink:        return "Heatsink"
        case .airflowLeft:     return "Airflow (Left)"
        case .airflowRight:    return "Airflow (Right)"
        case .battery:         return "Battery"
        // Apple Silicon – CPU P-Cores
        case .apCpuPerf0:      return "CPU P-Core 0"
        case .apCpuPerf1:      return "CPU P-Core 1"
        case .apCpuPerf2:      return "CPU P-Core 2"
        case .apCpuPerf3:      return "CPU P-Core 3"
        case .apCpuPerf4:      return "CPU P-Core 4"
        case .apCpuPerf5:      return "CPU P-Core 5"
        // Apple Silicon – CPU E-Cores
        case .apCpuEff0:       return "CPU E-Core 0"
        case .apCpuEff1:       return "CPU E-Core 1"
        case .apCpuEff2:       return "CPU E-Core 2"
        case .apCpuEff3:       return "CPU E-Core 3"
        // Apple Silicon – GPU
        case .apGpu0:          return "GPU 0"
        case .apGpu1:          return "GPU 1"
        case .apGpu2:          return "GPU 2"
        case .apGpu3:          return "GPU 3"
        // Apple Silicon – SoC
        case .apSoc0:          return "SoC 0"
        case .apSoc1:          return "SoC 1"
        // Apple Silicon – Memory
        case .apMemory:        return "Memory"
        case .apMemory1:       return "Memory 1"
        case .apMemory2:       return "Memory 2"
        case .apMemory3:       return "Memory 3"
        // Apple Silicon – Neural Engine
        case .apANE:           return "Neural Engine"
        // Apple Silicon – SSD
        case .apSSD:           return "SSD"
        case .apSSD1:          return "SSD 1"
        // Apple Silicon – Ambient
        case .apAmbient:       return "Ambient"
        case .apAmbient1:      return "Ambient 1"
        // Apple Silicon – Thunderbolt
        case .apThunderbolt0:  return "Thunderbolt 0"
        case .apThunderbolt1:  return "Thunderbolt 1"
        case .apThunderbolt2:  return "Thunderbolt 2"
        // Apple Silicon – Battery
        case .apBattery1:      return "Battery 1"
        case .apBattery2:      return "Battery 2"
        case .apBatteryExt:    return "Battery (External)"
        // Apple Silicon – Power Supply
        case .apPowerSupply:   return "Power Supply"
        case .apPowerSupply1:  return "Power Supply 1"
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
    private static let kSMCHandleYPCEvent:   UInt32 = 2

    private static let kSMCUserClientOpen:   UInt32 = 0
    private static let kSMCUserClientClose:  UInt32 = 1
    private static let kSMCGetKeyInfo:       UInt32 = 9
    private static let kSMCGetKeyValue:      UInt32 = 5
    private static let kSMCGetKeyFromIndex:  UInt32 = 8

    /// Maximum number of SMC keys to enumerate during dynamic sensor discovery.
    private static let maxSMCKeyCount:       UInt32 = 1_000

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

    /// Read a temperature value (°C) from an arbitrary 4-character SMC key string.
    /// Useful for probing model-specific keys not covered by the enum.
    /// Returns `nil` if the key is not supported on this machine.
    func readArbitraryTemperature(key: String) -> Double? {
        readTemperature(key: key)
    }

    /// Discover all available temperature sensor keys dynamically.
    ///
    /// Reads the total key count via the `#KEY` meta-key, then iterates through
    /// every key by index using `kSMCGetKeyFromIndex`. Any key whose name starts
    /// with `T` that returns a valid `sp78` temperature reading is included.
    ///
    /// - Returns: An array of `(key, displayName, value)` tuples for all live
    ///            temperature sensors found on this hardware.
    func discoverTemperatureSensors() -> [(key: String, displayName: String, value: Double)] {
        var results: [(key: String, displayName: String, value: Double)] = []

        // Step 1: Get the total number of SMC keys from the #KEY meta-key.
        var countInput  = SMCParamStruct()
        var countOutput = SMCParamStruct()
        countInput.key   = fourCharCode("#KEY")
        countInput.data8 = UInt8(Self.kSMCGetKeyInfo)

        guard callSMC(input: &countInput, output: &countOutput) == kIOReturnSuccess else {
            return results
        }

        // The key count is stored big-endian in the first 4 bytes of the output.
        let keyCount = UInt32(countOutput.bytes.0) << 24
                     | UInt32(countOutput.bytes.1) << 16
                     | UInt32(countOutput.bytes.2) << 8
                     | UInt32(countOutput.bytes.3)

        guard keyCount > 0 else { return results }

        // Step 2: Iterate through all keys by index (cap at maxSMCKeyCount for safety).
        for i in 0..<min(keyCount, Self.maxSMCKeyCount) {
            var indexInput  = SMCParamStruct()
            var indexOutput = SMCParamStruct()
            indexInput.data8  = UInt8(Self.kSMCGetKeyFromIndex)
            indexInput.data32 = i

            guard callSMC(input: &indexInput, output: &indexOutput) == kIOReturnSuccess else {
                continue
            }

            // Decode the 4-char key from the output's `key` field.
            let keyCode = indexOutput.key
            let chars: [Character] = [
                Character(UnicodeScalar(UInt8((keyCode >> 24) & 0xFF))),
                Character(UnicodeScalar(UInt8((keyCode >> 16) & 0xFF))),
                Character(UnicodeScalar(UInt8((keyCode >> 8)  & 0xFF))),
                Character(UnicodeScalar(UInt8( keyCode        & 0xFF)))
            ]
            let keyString = String(chars)

            // Temperature keys start with 'T'.
            guard keyString.hasPrefix("T") else { continue }

            if let temp = readTemperature(key: keyString) {
                let name = SMCTemperatureKey(rawValue: keyString)?.displayName ?? keyString
                results.append((key: keyString, displayName: name, value: temp))
            }
        }

        return results
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
