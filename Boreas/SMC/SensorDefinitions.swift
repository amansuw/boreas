import Foundation

// MARK: - Sensor Types

enum SensorCategory: String, CaseIterable, Identifiable {
    case temperature = "Temperature"
    case voltage = "Voltage"
    case current = "Current"
    case power = "Power"
    case fan = "Fan"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature: return "thermometer"
        case .voltage: return "bolt.fill"
        case .current: return "arrow.right.circle.fill"
        case .power: return "powerplug.fill"
        case .fan: return "fan.fill"
        }
    }

    var unit: String {
        switch self {
        case .temperature: return "°C"
        case .voltage: return "V"
        case .current: return "A"
        case .power: return "W"
        case .fan: return "RPM"
        }
    }
}

struct SensorDefinition {
    let key: String
    let name: String
    let category: SensorCategory
}

struct SensorReading: Identifiable {
    let id: String
    let name: String
    let category: SensorCategory
    var value: Double
    let key: String

    var formattedValue: String {
        switch category {
        case .temperature:
            return String(format: "%.1f%@", value, category.unit)
        case .voltage:
            return String(format: "%.3f%@", value, category.unit)
        case .current:
            return String(format: "%.2f%@", value, category.unit)
        case .power:
            return String(format: "%.2f%@", value, category.unit)
        case .fan:
            return String(format: "%.0f %@", value, category.unit)
        }
    }
}

// MARK: - Sensor Lookup & Validation

struct SensorLookup {
    // Friendly names for known SMC keys
    static let friendlyNames: [String: String] = [
        // CPU - Intel
        "TC0P": "CPU Proximity", "TC0D": "CPU Die", "TC0E": "CPU Die 2", "TC0F": "CPU Die 3",
        "TC1C": "CPU Core 1", "TC2C": "CPU Core 2", "TC3C": "CPU Core 3", "TC4C": "CPU Core 4",
        "TC5C": "CPU Core 5", "TC6C": "CPU Core 6", "TC7C": "CPU Core 7", "TC8C": "CPU Core 8",
        // CPU - Apple Silicon Die Sensors
        "TCDX": "CPU Die", "TCHP": "CPU Hotspot",
        "TCMb": "CPU Cluster P", "TCMz": "CPU Cluster E",
        // CPU - Apple Silicon Performance Cores
        "Tc0a": "CPU P-Core 1", "Tc0b": "CPU P-Core 2", "Tc0c": "CPU P-Core 3", "Tc0d": "CPU P-Core 4",
        "Tc0e": "CPU P-Core 5", "Tc0f": "CPU P-Core 6", "Tc0g": "CPU P-Core 7", "Tc0h": "CPU P-Core 8",
        "Tc0p": "CPU P-Core 9", "Tc0q": "CPU P-Core 10", "Tc0r": "CPU P-Core 11", "Tc0s": "CPU P-Core 12",
        // CPU - Apple Silicon Efficiency Cores
        "Tc1a": "CPU E-Core 1", "Tc1b": "CPU E-Core 2", "Tc1c": "CPU E-Core 3", "Tc1d": "CPU E-Core 4",
        "Tc1e": "CPU E-Core 5", "Tc1f": "CPU E-Core 6",
        // GPU
        "TG0P": "GPU Proximity", "TG0D": "GPU Die",
        // Memory
        "TM0P": "Memory Proximity",
        // NAND / Storage
        "TH0A": "NAND", "TH0B": "NAND 2", "TH0a": "NAND 3", "TH0b": "NAND 4",
        // Battery
        "TB0T": "Battery 1", "TB1T": "Battery 2", "TB2T": "Battery 3",
        // Misc
        "TW0P": "Airport", "TaLP": "Airflow Left", "TaRP": "Airflow Right",
        "Ts0P": "Palm Rest 1", "Ts1P": "Palm Rest 2",
        "Th1H": "Heatpipe 1", "Th2H": "Heatpipe 2",
        "TN0P": "Northbridge Proximity",
        // Voltage
        "VC0C": "CPU Core", "VG0C": "GPU", "VM0R": "Memory",
        "VD0R": "DC In", "VP0R": "12V Rail", "VB0R": "Battery", "VBAT": "Battery",
        // Current
        "IC0C": "CPU Core", "IG0C": "GPU", "ID0R": "DC In", "IB0R": "Battery",
        // Power
        "PC0C": "CPU Package", "PCPC": "CPU Package Core", "PCPG": "CPU Package GPU",
        "PCAM": "CPU High Side", "PG0C": "GPU", "PB0R": "Battery",
        "PD0R": "DC In", "PDTR": "DC In Total", "PSTR": "System Total", "PM0R": "Memory",
    ]

    // Valid SMC data types for temperature readings
    static let temperatureDataTypes: Set<String> = ["sp78", "sp87", "sp96", "flt ", "sp3c", "sp4b", "sp5a", "sp69"]

    // Valid SMC data types for voltage/current/power readings
    static let analogDataTypes: Set<String> = [
        "sp78", "sp87", "sp96", "sp3c", "sp4b", "sp5a", "sp69", "sp1e", "spb4", "spf0",
        "flt ", "fpe2", "fp2e", "fp88",
        "ui8 ", "ui16", "ui32", "si8 ", "si16",
        "ioft",
    ]

    // Categorize an SMC key by its 4-char name prefix
    static func category(for key: String) -> SensorCategory? {
        guard key.count >= 2 else { return nil }
        let first = key.first!
        switch first {
        case "T": return .temperature
        case "V": return .voltage
        case "I": return .current
        case "P": return .power
        case "F":
            // Fan keys: F{n}Ac (current), F{n}Mn (min), F{n}Mx (max), F{n}Tg (target)
            let suffix = String(key.suffix(2))
            if suffix == "Ac" || suffix == "Mn" || suffix == "Mx" || suffix == "Tg" {
                return .fan
            }
            return nil
        default: return nil
        }
    }

    // Generate a friendly name from the raw key if no lookup exists
    static func name(for key: String) -> String {
        if let known = friendlyNames[key] { return known }

        // Auto-generate names based on key pattern
        guard key.count == 4 else { return key }
        let prefix = String(key.prefix(2))

        switch prefix {
        case "TC": return "CPU Core \(key.suffix(2))"
        case "Tc":
            let idx = key.suffix(2)
            if key.dropFirst(2).first == "0" { return "CPU P-Core \(idx)" }
            if key.dropFirst(2).first == "1" { return "CPU E-Core \(idx)" }
            return "CPU Core \(idx)"
        case "Tp": return "CPU Thermal \(key.suffix(2))"
        case "TG": return "GPU \(key.suffix(2))"
        case "Tg": return "GPU \(key.suffix(2))"
        case "Tm": return "Memory \(key.suffix(2))"
        case "TH": return "NAND \(key.suffix(2))"
        case "TB": return "Battery \(key.suffix(2))"
        case "TW": return "WiFi \(key.suffix(2))"
        case "Ta": return "Airflow \(key.suffix(2))"
        case "Ts": return "Surface \(key.suffix(2))"
        case "Th": return "Heatpipe \(key.suffix(2))"
        case "TN": return "NAND/ANE \(key.suffix(2))"
        case "TI": return "ISP \(key.suffix(2))"
        case "TT": return "Thunderbolt \(key.suffix(2))"
        case "VC", "VG", "VM", "VD", "VP", "VN", "VB": return "Voltage \(key.suffix(2))"
        case "IC", "IG", "ID", "IB", "IM", "IN", "IT": return "Current \(key.suffix(2))"
        case "PC", "PG", "PB", "PD", "PM", "PN", "PP", "PS": return "Power \(key.suffix(2))"
        default:
            // Fan keys: F{n}Ac, F{n}Mn, F{n}Mx, F{n}Tg
            if key.first == "F" && key.count == 4 {
                let fanIdx = String(key.dropFirst().prefix(1))
                let suffix = String(key.suffix(2))
                let fanName = Int(fanIdx) == 0 ? "Left Fan" : Int(fanIdx) == 1 ? "Right Fan" : "Fan \(fanIdx)"
                switch suffix {
                case "Ac": return "\(fanName) Speed"
                case "Mn": return "\(fanName) Min"
                case "Mx": return "\(fanName) Max"
                case "Tg": return "\(fanName) Target"
                default: return key
                }
            }
            return key
        }
    }

    // Check if a data type is valid for a given category
    static func isValidDataType(_ dataType: String, for category: SensorCategory) -> Bool {
        switch category {
        case .temperature:
            return temperatureDataTypes.contains(dataType)
        case .voltage, .current, .power:
            return analogDataTypes.contains(dataType)
        case .fan:
            return analogDataTypes.contains(dataType)
        }
    }

    // Value range validation per category
    static func isReasonableValue(_ value: Double, for category: SensorCategory) -> Bool {
        switch category {
        case .temperature: return value >= 0 && value < 130
        case .voltage: return value > 0 && value < 25
        case .current: return value > -15 && value < 30
        case .power: return value > -5 && value < 350
        case .fan: return value >= 0 && value < 15000
        }
    }
}
