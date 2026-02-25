import Foundation

// MARK: - Top Process

struct TopProcess: Identifiable {
    let id: Int32 // pid
    let name: String
    let value: Double // usage % or bytes depending on context
    let formattedValue: String
}

// MARK: - CPU

struct CPUUsage {
    var system: Double = 0      // %
    var user: Double = 0        // %
    var idle: Double = 0        // %
    var total: Double = 0       // %

    var efficiencyCores: Double = 0  // avg % across E-cores
    var performanceCores: Double = 0 // avg % across P-cores

    struct CoreUsage: Identifiable {
        let id: Int
        let usage: Double       // %
        let isEfficiency: Bool
    }
    var perCore: [CoreUsage] = []
}

struct CPUFrequency {
    var allCores: Int = 0        // MHz
    var efficiencyCores: Int = 0 // MHz
    var performanceCores: Int = 0 // MHz
}

struct LoadAverage {
    var oneMinute: Double = 0
    var fiveMinute: Double = 0
    var fifteenMinute: Double = 0
}

// MARK: - GPU

struct GPUUsage {
    var modelName: String = "Unknown"
    var utilization: Double = 0       // overall %
    var renderUtilization: Double = 0 // %
    var tilerUtilization: Double = 0  // %
}

// MARK: - Memory

struct MemoryBreakdown {
    var total: UInt64 = 0       // bytes
    var used: UInt64 = 0        // bytes
    var app: UInt64 = 0         // bytes
    var wired: UInt64 = 0       // bytes
    var compressed: UInt64 = 0  // bytes
    var free: UInt64 = 0        // bytes
    var swap: UInt64 = 0        // bytes
    var pressureLevel: Int = 0  // 1 = normal, 2 = warning, 4 = critical

    var usagePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

// MARK: - Disk

struct DiskInfo: Identifiable {
    let id: String          // mount point
    let name: String        // e.g. "Macintosh HD"
    let totalBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 { totalBytes - freeBytes }
    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

struct DiskIO {
    var readBytesPerSec: UInt64 = 0
    var writeBytesPerSec: UInt64 = 0
}

// MARK: - Network

struct NetworkInterface: Identifiable {
    let id: String          // interface name, e.g. "en0"
    var displayName: String = ""
    var macAddress: String = ""
    var speed: String = ""  // e.g. "1000 Mbit"
    var localIP: String = ""
    var ipv6: String = ""
    var isUp: Bool = false
}

struct NetworkStats {
    var downloadBytesPerSec: UInt64 = 0
    var uploadBytesPerSec: UInt64 = 0
    var totalDownload: UInt64 = 0
    var totalUpload: UInt64 = 0
    var latencyMs: Double = 0
    var jitterMs: Double = 0
    var publicIP: String = ""
    var publicIPv6: String = ""
    var dnsServers: [String] = []
    var activeInterface: NetworkInterface?
}

struct NetworkSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let downloadBytesPerSec: UInt64
    let uploadBytesPerSec: UInt64
}

// MARK: - Battery

struct BatteryInfo {
    var level: Double = 0           // 0-100 %
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var source: String = "Battery"  // "AC Power" or "Battery"
    var timeRemaining: Int = -1     // minutes, -1 = calculating
    var healthPercent: Double = 0   // %
    var designCapacity: Int = 0     // mAh
    var maxCapacity: Int = 0        // mAh
    var currentCapacity: Int = 0    // mAh
    var cycleCount: Int = 0
    var power: Double = 0           // W
    var temperature: Double = 0     // °C
    var voltage: Double = 0         // V
    var adapterWatts: Int = 0       // W
    var adapterCurrent: Int = 0     // mA
    var adapterVoltage: Int = 0     // mV
    var hasBattery: Bool = false
}

// MARK: - Formatting Helpers

enum ByteFormatter {
    static func format(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        return String(format: "%.0f KB", kb)
    }

    static func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let gb = Double(bytesPerSec) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB/s", gb)
        }
        let mb = Double(bytesPerSec) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = Double(bytesPerSec) / 1024
        return String(format: "%.1f KB/s", kb)
    }
}
