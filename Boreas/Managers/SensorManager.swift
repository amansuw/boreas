import Foundation

enum HistoryRange: String, CaseIterable, Identifiable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case sixtyMinutes = "60m"
    case max = "Max"

    var id: String { rawValue }

    var window: TimeInterval? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .thirtyMinutes: return 30 * 60
        case .sixtyMinutes: return 60 * 60
        case .max: return nil
        }
    }
}
import Combine

struct TemperatureSnapshot: Identifiable {
    private static var counter: Int = 0
    let id: Int
    let timestamp: Date
    let avgCPU: Double
    let avgGPU: Double
    let maxCPU: Double
    let maxGPU: Double

    init(timestamp: Date, avgCPU: Double, avgGPU: Double, maxCPU: Double, maxGPU: Double) {
        TemperatureSnapshot.counter += 1
        self.id = TemperatureSnapshot.counter
        self.timestamp = timestamp
        self.avgCPU = avgCPU
        self.avgGPU = avgGPU
        self.maxCPU = maxCPU
        self.maxGPU = maxGPU
    }
}

class SensorManager: ObservableObject {
    var readings: [SensorReading] = []
    var temperatureReadings: [SensorReading] = []
    var voltageReadings: [SensorReading] = []
    var currentReadings: [SensorReading] = []
    var powerReadings: [SensorReading] = []
    var isMonitoring = false
    var isDiscovering = true
    var temperatureHistory: [TemperatureSnapshot] = []
    var historyRange: HistoryRange = .max {
        didSet { scheduleFilteredHistoryUpdate() }
    }
    private(set) var filteredHistory: [TemperatureSnapshot] = []

    private let smc = SMCKit.shared
    private var discoveredSensors: [(key: String, name: String, category: SensorCategory)] = []
    private let maxHistoryPoints = 3600
    private var updateCycleCount = 0

    init() {
        discoverSensors()
        updateFilteredHistory()
    }

    deinit {
    }

    // MARK: - Pure Dynamic Discovery

    func discoverSensors() {
        isDiscovering = true

        MonitorQueues.fast.async { [weak self] in
            guard let self = self else { return }

            var sensors: [(key: String, name: String, category: SensorCategory)] = []
            var seenKeys = Set<String>()

            // Enumerate ALL keys from the system
            let keyCount = self.smc.getKeyCount()
            print("SensorManager: Scanning \(keyCount) SMC keys from system...")

            for i in 0..<keyCount {
                guard let key = self.smc.getKeyAtIndex(i) else { continue }
                guard !seenKeys.contains(key) else { continue }

                // Determine category from key prefix
                guard let category = SensorLookup.category(for: key) else { continue }

                // Read the key
                guard let val = self.smc.readKey(key) else { continue }

                // Validate data type for category
                guard SensorLookup.isValidDataType(val.dataType, for: category) else { continue }

                // Skip all-zero bytes (sensor not active)
                let hasNonZero = val.bytes.prefix(Int(val.dataSize)).contains(where: { $0 != 0 })
                guard hasNonZero else { continue }

                // Decode and validate value range
                guard let decoded = self.smc.decodeValue(val),
                      decoded.isFinite,
                      SensorLookup.isReasonableValue(decoded, for: category) else { continue }

                let name = SensorLookup.name(for: key)
                sensors.append((key: key, name: name, category: category))
                seenKeys.insert(key)
            }

            // Sort sensors: by category then by key
            sensors.sort { a, b in
                if a.category.rawValue != b.category.rawValue {
                    return a.category.rawValue < b.category.rawValue
                }
                return a.key < b.key
            }

            print("SensorManager: Discovery complete — \(sensors.count) valid sensors")

            DispatchQueue.main.async {
                self.discoveredSensors = sensors
                self.isDiscovering = false
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Polling (called by MonitorCoordinator on MonitorQueues.fast)

    // MARK: - Compute / Apply

    struct FastResult {
        let all: [SensorReading]
        let temp: [SensorReading]
        let volt: [SensorReading]
        let curr: [SensorReading]
        let pow: [SensorReading]
        let snapshot: TemperatureSnapshot
    }

    // Scratch arrays reused each poll to avoid heap allocations
    private var scratchAll: [SensorReading] = []
    private var scratchTemp: [SensorReading] = []
    private var scratchVolt: [SensorReading] = []
    private var scratchCurr: [SensorReading] = []
    private var scratchPow: [SensorReading] = []

    func computeReadings() -> FastResult? {
        guard !discoveredSensors.isEmpty else { return nil }

        scratchAll.removeAll(keepingCapacity: true)
        scratchTemp.removeAll(keepingCapacity: true)
        scratchVolt.removeAll(keepingCapacity: true)
        scratchCurr.removeAll(keepingCapacity: true)
        scratchPow.removeAll(keepingCapacity: true)

        var cpuTempSum = 0.0, cpuTempMax = 0.0, cpuTempCount = 0
        var gpuTempSum = 0.0, gpuTempMax = 0.0, gpuTempCount = 0

        for sensor in discoveredSensors {
            guard let val = smc.readKey(sensor.key) else { continue }
            guard let value = smc.decodeValue(val),
                  value.isFinite,
                  SensorLookup.isReasonableValue(value, for: sensor.category) else { continue }

            let reading = SensorReading(
                id: sensor.key,
                name: sensor.name,
                category: sensor.category,
                value: value,
                key: sensor.key
            )
            scratchAll.append(reading)

            switch sensor.category {
            case .temperature:
                scratchTemp.append(reading)
                let k = sensor.key
                if k.hasPrefix("TC") || k.hasPrefix("Tc") {
                    cpuTempSum += value; cpuTempMax = max(cpuTempMax, value); cpuTempCount += 1
                } else if k.hasPrefix("TG") || k.hasPrefix("Tg") {
                    gpuTempSum += value; gpuTempMax = max(gpuTempMax, value); gpuTempCount += 1
                }
            case .voltage: scratchVolt.append(reading)
            case .current: scratchCurr.append(reading)
            case .power: scratchPow.append(reading)
            case .fan: break
            }
        }

        let avgCPU = cpuTempCount > 0 ? cpuTempSum / Double(cpuTempCount) : 0
        let avgGPU = gpuTempCount > 0 ? gpuTempSum / Double(gpuTempCount) : 0

        return FastResult(
            all: scratchAll,
            temp: scratchTemp,
            volt: scratchVolt,
            curr: scratchCurr,
            pow: scratchPow,
            snapshot: TemperatureSnapshot(
                timestamp: Date(), avgCPU: avgCPU, avgGPU: avgGPU,
                maxCPU: cpuTempMax, maxGPU: gpuTempMax
            )
        )
    }

    func applyReadings(_ r: FastResult) {
        readings = r.all
        temperatureReadings = r.temp
        voltageReadings = r.volt
        currentReadings = r.curr
        powerReadings = r.pow
        isMonitoring = true
        temperatureHistory.append(r.snapshot)
        if temperatureHistory.count > maxHistoryPoints {
            temperatureHistory.removeSubrange(0..<(temperatureHistory.count - maxHistoryPoints))
        }
        updateCycleCount += 1
        if updateCycleCount % 5 == 0 {
            updateFilteredHistory()
        }
        objectWillChange.send()
    }

    // MARK: - Computed Aggregates

    private func cpuTemps() -> [SensorReading] {
        temperatureReadings.filter {
            $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tc")
        }
    }

    private func gpuTemps() -> [SensorReading] {
        temperatureReadings.filter {
            $0.key.hasPrefix("TG") || $0.key.hasPrefix("Tg")
        }
    }

    var averageCPUTemp: Double {
        let temps = cpuTemps()
        guard !temps.isEmpty else { return 0 }
        return temps.map(\.value).reduce(0, +) / Double(temps.count)
    }

    var hottestCPUTemp: Double {
        cpuTemps().map(\.value).max() ?? 0
    }

    var averageGPUTemp: Double {
        let temps = gpuTemps()
        guard !temps.isEmpty else { return 0 }
        return temps.map(\.value).reduce(0, +) / Double(temps.count)
    }

    var hottestGPUTemp: Double {
        gpuTemps().map(\.value).max() ?? 0
    }

    var cpuCoreCount: Int { cpuTemps().count }
    var gpuCoreCount: Int { gpuTemps().count }

    // MARK: - History helpers

    private func scheduleFilteredHistoryUpdate() {
        // Use Task to defer past the current SwiftUI render pass,
        // preventing "Publishing changes from within view updates" warning.
        Task { @MainActor [weak self] in
            self?.updateFilteredHistory()
        }
    }

    func updateFilteredHistory() {
        let window = historyRange.window
        let base = temperatureHistory
        guard let window else {
            filteredHistory = base
            objectWillChange.send()
            return
        }
        let cutoff = Date().addingTimeInterval(-window)
        filteredHistory = base.filter { $0.timestamp >= cutoff }
        objectWillChange.send()
    }

    // MARK: - Dashboard Curated Sensors

    /// CPU temps for dashboard: only die/core sensors (TC*, Tc*), NOT Tp* thermal zones
    var dashboardCPUTemps: [SensorReading] {
        temperatureReadings.filter {
            $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tc")
        }.sorted { $0.key < $1.key }
    }

    /// GPU temps for dashboard: limited to first 8 sensors
    var dashboardGPUTemps: [SensorReading] {
        let gpuAll = temperatureReadings.filter {
            $0.key.hasPrefix("TG") || $0.key.hasPrefix("Tg")
        }.sorted { $0.key < $1.key }
        return Array(gpuAll.prefix(8))
    }

    /// Key system temps for dashboard: NAND, battery, airflow
    var dashboardSystemTemps: [SensorReading] {
        temperatureReadings.filter {
            $0.key.hasPrefix("TH") || $0.key.hasPrefix("TB") ||
            $0.key.hasPrefix("Ta") || $0.key.hasPrefix("TW")
        }.sorted { $0.key < $1.key }
    }

    // MARK: - Fan Curve Curated Sources

    /// Curated list for fan curve source picker: Airport, NAND avg, Battery avg, CPU Avg/Hot, GPU Avg/Hot
    var fanCurveSources: [SensorReading] {
        var sources: [SensorReading] = []

        func avg(for prefixes: [String]) -> Double? {
            let vals = temperatureReadings.filter { reading in
                prefixes.contains(where: { reading.key.hasPrefix($0) })
            }.map { $0.value }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        func add(key: String, name: String, value: Double?) {
            guard let v = value, v.isFinite else { return }
            sources.append(SensorReading(id: key, name: name, category: .temperature, value: v, key: key))
        }

        // Airport (WiFi) — first TW*
        if let wifi = temperatureReadings.first(where: { $0.key.hasPrefix("TW") }) {
            add(key: "AGG_AIRPORT", name: "Airport", value: wifi.value)
        }

        // NAND average (TH*)
        add(key: "AGG_NAND", name: "NAND Avg", value: avg(for: ["TH"]))

        // Battery average (TB*)
        add(key: "AGG_BATT", name: "Battery Avg", value: avg(for: ["TB"]))

        // CPU Avg / CPU Hottest
        add(key: "AGG_CPU_AVG", name: "CPU Average", value: averageCPUTemp)
        add(key: "AGG_CPU_MAX", name: "CPU Hottest", value: hottestCPUTemp)

        // GPU Avg / GPU Hottest
        add(key: "AGG_GPU_AVG", name: "GPU Average", value: averageGPUTemp)
        add(key: "AGG_GPU_MAX", name: "GPU Hottest", value: hottestGPUTemp)

        return sources
    }
}
