import Foundation

/// Platform identifiers used to filter SMC sensor lists to hardware-relevant entries.
/// Mirrors the Platform enum used in exelban/stats for cross-chip sensor coverage.
public enum Platform: String, Codable, Equatable {
    case intel
    case m1, m1Pro, m1Max, m1Ultra
    case m2, m2Pro, m2Max, m2Ultra
    case m3, m3Pro, m3Max, m3Ultra
    case m4, m4Pro, m4Max, m4Ultra
    case m5, m5Pro, m5Max, m5Ultra

    /// Detects the current platform by checking `hw.optional.arm64` and
    /// parsing `machdep.cpu.brand_string` (or `hw.model` as a fallback).
    /// Returns `nil` if the platform cannot be determined (sensors will still
    /// be discovered via dynamic key enumeration).
    public static var current: Platform? {
        var isARM: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &isARM, &size, nil, 0)
        guard isARM != 0 else { return .intel }

        // Apple Silicon: try brand string first (e.g. "Apple M2 Pro")
        var buf = [CChar](repeating: 0, count: 256)
        var bufSize = buf.count
        if sysctlbyname("machdep.cpu.brand_string", &buf, &bufSize, nil, 0) == 0 {
            if let p = Platform.detect(from: String(cString: buf)) { return p }
        }

        // Fallback: hw.model machine identifier (e.g. "Mac14,5")
        bufSize = buf.count
        if sysctlbyname("hw.model", &buf, &bufSize, nil, 0) == 0 {
            if let p = Platform.detectFromModel(String(cString: buf)) { return p }
        }

        return nil  // Unknown Apple Silicon – sensor discovery falls back to all platforms
    }

    // MARK: - Chip string detection (e.g. "Apple M3 Pro")

    private static func detect(from chip: String) -> Platform? {
        let s = chip.lowercased()

        func variant() -> String? {
            if s.contains("ultra") { return "ultra" }
            if s.contains("max")   { return "max" }
            if s.contains("pro")   { return "pro" }
            return nil
        }

        let gens: [(String, Platform, Platform, Platform, Platform)] = [
            ("m5", .m5, .m5Pro, .m5Max, .m5Ultra),
            ("m4", .m4, .m4Pro, .m4Max, .m4Ultra),
            ("m3", .m3, .m3Pro, .m3Max, .m3Ultra),
            ("m2", .m2, .m2Pro, .m2Max, .m2Ultra),
            ("m1", .m1, .m1Pro, .m1Max, .m1Ultra),
        ]
        for (token, base, pro, max, ultra) in gens where s.contains(token) {
            switch variant() {
            case "ultra": return ultra
            case "max":   return max
            case "pro":   return pro
            default:      return base
            }
        }
        return nil
    }

    // MARK: - Machine-model–based detection fallback

    // Partial lookup of known Apple Silicon hw.model identifiers.
    // Only the generation is resolved here; variant (Pro/Max/Ultra) is harder
    // without a full table, so we return the base chip when unsure.
    private static func detectFromModel(_ model: String) -> Platform? {
        // M1 identifiers
        let m1Prefixes = ["MacBookPro17,", "MacBookAir10,", "Macmini9,", "iMac21,", "MacPro8,"]
        // M1 Pro / Max (Mac13 = MacBook Pro 14"/16" M1 Pro/Max)
        let m1ProPrefixes = ["MacBookPro18,", "Mac13,"]
        // M1 Ultra (Mac13,2 = Mac Studio M1 Ultra)
        let m1Ultra = ["Mac13,2"]
        // M2 base
        let m2Prefixes = ["Mac14,2", "Mac14,7", "MacBookAir15,"]
        // M2 Pro / Max
        let m2ProPrefixes = ["Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10", "Mac14,13", "Mac14,14"]
        // M3
        let m3Prefixes = ["Mac15,", "MacBookPro21,"]
        // M4
        let m4Prefixes = ["Mac16,", "MacBookPro22,", "MacBookAir22,"]

        for p in m1Ultra  where model == p          { return .m1Ultra }
        for p in m1ProPrefixes where model.hasPrefix(p) { return .m1Pro }
        for p in m1Prefixes    where model.hasPrefix(p) { return .m1 }
        for p in m2ProPrefixes where model.hasPrefix(p) { return .m2Pro }
        for p in m2Prefixes    where model.hasPrefix(p) { return .m2 }
        for p in m3Prefixes    where model.hasPrefix(p) { return .m3 }
        for p in m4Prefixes    where model.hasPrefix(p) { return .m4 }

        return nil
    }

    // MARK: - Grouped sets

    public static var all:   [Platform] { [.intel] + apple }
    public static var apple: [Platform] { m1Gen + m2Gen + m3Gen + m4Gen + m5Gen }
    public static var m1Gen: [Platform] { [.m1, .m1Pro, .m1Max, .m1Ultra] }
    public static var m2Gen: [Platform] { [.m2, .m2Pro, .m2Max, .m2Ultra] }
    public static var m3Gen: [Platform] { [.m3, .m3Pro, .m3Max, .m3Ultra] }
    public static var m4Gen: [Platform] { [.m4, .m4Pro, .m4Max, .m4Ultra] }
    public static var m5Gen: [Platform] { [.m5, .m5Pro, .m5Max, .m5Ultra] }
}
