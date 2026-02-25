import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var cpuManager: CPUManager
    @EnvironmentObject var ramManager: RAMManager
    @EnvironmentObject var gpuManager: GPUManager
    @EnvironmentObject var batteryManager: BatteryManager
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var diskManager: DiskManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(sensorManager.readings.count) sensors · \(fanManager.fans.count) fans")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if let profile = profileManager.activeProfile {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(profileColor(profile))
                                .frame(width: 8, height: 8)
                            Text(profile.name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)

                // System Stats Overview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                        Text("System Overview")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        DashboardGaugeCard(
                            title: "CPU",
                            percent: cpuManager.usage.total,
                            subtitle: String(format: "%.0f%% User · %.0f%% Sys", cpuManager.usage.user, cpuManager.usage.system),
                            icon: "cpu",
                            color: cpuGaugeColor
                        )
                        DashboardGaugeCard(
                            title: "GPU",
                            percent: gpuManager.usage.utilization,
                            subtitle: gpuManager.usage.modelName,
                            icon: "square.3.layers.3d.top.filled",
                            color: gpuGaugeColor
                        )
                        DashboardGaugeCard(
                            title: "RAM",
                            percent: ramManager.memory.usagePercent,
                            subtitle: "\(ByteFormatter.format(ramManager.memory.used)) / \(ByteFormatter.format(ramManager.memory.total))",
                            icon: "memorychip",
                            color: ramGaugeColor
                        )
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        StatCard(
                            title: "Network ↓",
                            value: ByteFormatter.formatSpeed(networkManager.stats.downloadBytesPerSec),
                            icon: "arrow.down.circle.fill",
                            color: .blue
                        )
                        StatCard(
                            title: "Network ↑",
                            value: ByteFormatter.formatSpeed(networkManager.stats.uploadBytesPerSec),
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                        if let disk = diskManager.disks.first {
                            StatCard(
                                title: "Disk",
                                value: String(format: "%.0f%% used", disk.usagePercent),
                                icon: "internaldrive",
                                color: disk.usagePercent > 90 ? .red : disk.usagePercent > 75 ? .orange : .blue
                            )
                        } else {
                            StatCard(
                                title: "Disk",
                                value: "N/A",
                                icon: "internaldrive",
                                color: .gray
                            )
                        }
                    }
                    .padding(.horizontal)

                    if batteryManager.battery.hasBattery {
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Battery",
                                value: String(format: "%.0f%%", batteryManager.battery.level),
                                icon: batteryManager.battery.isCharging ? "battery.100percent.bolt" : "battery.100percent",
                                color: batteryManager.battery.level > 20 ? .green : .red
                            )
                            StatCard(
                                title: "Battery Health",
                                value: String(format: "%.0f%%", batteryManager.battery.healthPercent),
                                icon: "heart.fill",
                                color: batteryManager.battery.healthPercent > 80 ? .green : .yellow
                            )
                        }
                        .padding(.horizontal)
                    }
                }

                // Temperature Overview Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    StatCard(
                        title: "Avg CPU (\(sensorManager.cpuCoreCount) cores)",
                        value: String(format: "%.1f°C", sensorManager.averageCPUTemp),
                        icon: "cpu",
                        color: tempColor(sensorManager.averageCPUTemp)
                    )
                    StatCard(
                        title: "Peak CPU",
                        value: String(format: "%.1f°C", sensorManager.hottestCPUTemp),
                        icon: "flame",
                        color: tempColor(sensorManager.hottestCPUTemp)
                    )
                    StatCard(
                        title: "Avg GPU (\(sensorManager.gpuCoreCount) cores)",
                        value: String(format: "%.1f°C", sensorManager.averageGPUTemp),
                        icon: "square.3.layers.3d.top.filled",
                        color: tempColor(sensorManager.averageGPUTemp)
                    )
                    StatCard(
                        title: "Peak GPU",
                        value: String(format: "%.1f°C", sensorManager.hottestGPUTemp),
                        icon: "flame.fill",
                        color: tempColor(sensorManager.hottestGPUTemp)
                    )
                }
                .padding(.horizontal)

                // Temperature History Chart
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Range", selection: $sensorManager.historyRange) {
                            ForEach(HistoryRange.allCases) { range in
                                Text(range.rawValue)
                                    .tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    TemperatureChartView(
                        history: sensorManager.filteredHistory,
                        range: sensorManager.historyRange,
                        latestSnapshot: sensorManager.temperatureHistory.last
                    )
                }
                .padding(.horizontal)

                // Fan Status — Unified
                UnifiedFanCard()
                    .padding(.horizontal)

                // Temperature Sensors — Curated
                HStack(alignment: .top, spacing: 12) {
                    SensorGroupCard(
                        title: "CPU Temperatures",
                        icon: "cpu",
                        readings: sensorManager.dashboardCPUTemps
                    )

                    SensorGroupCard(
                        title: "GPU Temperatures",
                        icon: "square.3.layers.3d.top.filled",
                        readings: sensorManager.dashboardGPUTemps
                    )
                }
                .padding(.horizontal)

                // System Temps
                if !sensorManager.dashboardSystemTemps.isEmpty {
                    SensorGroupCard(
                        title: "System",
                        icon: "laptopcomputer",
                        readings: sensorManager.dashboardSystemTemps
                    )
                    .padding(.horizontal)
                }

                // Power Overview
                if !sensorManager.powerReadings.isEmpty {
                    SensorGroupCard(
                        title: "Power",
                        icon: "bolt.fill",
                        readings: Array(sensorManager.powerReadings.prefix(10))
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp <= 0 { return .gray }
        if temp < 45 { return .green }
        if temp < 65 { return .yellow }
        if temp < 80 { return .orange }
        return .red
    }

    private func profileColor(_ profile: FanProfile) -> Color {
        switch profile.name {
        case "Silent": return .blue
        case "Default": return .green
        case "Balanced": return .yellow
        case "Performance": return .orange
        case "Max": return .red
        default: return .purple
        }
    }

    private var cpuGaugeColor: Color {
        let v = cpuManager.usage.total
        if v < 30 { return .green }
        if v < 60 { return .yellow }
        if v < 80 { return .orange }
        return .red
    }

    private var gpuGaugeColor: Color {
        let v = gpuManager.usage.utilization
        if v < 30 { return .green }
        if v < 60 { return .yellow }
        if v < 80 { return .orange }
        return .red
    }

    private var ramGaugeColor: Color {
        let v = ramManager.memory.usagePercent
        if v < 50 { return .green }
        if v < 75 { return .yellow }
        if v < 90 { return .orange }
        return .red
    }
}

// MARK: - Dashboard Gauge Card

struct DashboardGaugeCard: View {
    let title: String
    let percent: Double
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(percent / 100, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: percent)
                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Temperature History Chart

struct TemperatureChartView: View {
    let history: [TemperatureSnapshot]
    let range: HistoryRange
    let latestSnapshot: TemperatureSnapshot?

    private struct ChartSample: Identifiable {
        let id: Int
        let timestamp: Date
        let avgCPU: Double
        let maxCPU: Double
        let avgGPU: Double
        let maxGPU: Double

        init(snapshot: TemperatureSnapshot) {
            self.id = snapshot.id
            self.timestamp = snapshot.timestamp
            self.avgCPU = snapshot.avgCPU
            self.maxCPU = snapshot.maxCPU
            self.avgGPU = snapshot.avgGPU
            self.maxGPU = snapshot.maxGPU
        }

        init(id: Int = 0, timestamp: Date, avgCPU: Double, maxCPU: Double, avgGPU: Double, maxGPU: Double) {
            self.id = id
            self.timestamp = timestamp
            self.avgCPU = avgCPU
            self.maxCPU = maxCPU
            self.avgGPU = avgGPU
            self.maxGPU = maxGPU
        }

        func withTimestamp(_ timestamp: Date) -> ChartSample {
            ChartSample(id: id, timestamp: timestamp, avgCPU: avgCPU, maxCPU: maxCPU, avgGPU: avgGPU, maxGPU: maxGPU)
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let temps = history.flatMap { [$0.avgCPU, $0.maxCPU, $0.avgGPU, $0.maxGPU] }
        guard let minVal = temps.min(), let maxVal = temps.max() else { return 0...100 }
        let padding: Double = 8
        let lower = max(0, minVal - padding)
        var upper = maxVal + padding
        if upper - lower < 20 { upper = lower + 20 }
        return lower...upper
    }

    private var chartXDomain: ClosedRange<Date> {
        if let window = range.window {
            let end = Date()
            let start = end.addingTimeInterval(-window)
            return start...end
        }

        if let first = history.first?.timestamp, let last = history.last?.timestamp {
            if first == last {
                let paddedStart = first.addingTimeInterval(-60)
                let paddedEnd = last.addingTimeInterval(60)
                return paddedStart...paddedEnd
            }
            return first...last
        }

        let end = Date()
        return end.addingTimeInterval(-60)...end
    }

    private var chartSamples: [ChartSample] {
        let domain = chartXDomain
        let baselineValue = chartYDomain.lowerBound

        func baselineSample(at timestamp: Date) -> ChartSample {
            ChartSample(
                timestamp: timestamp,
                avgCPU: baselineValue,
                maxCPU: baselineValue,
                avgGPU: baselineValue,
                maxGPU: baselineValue
            )
        }

        if !history.isEmpty {
            var samples: [ChartSample] = []
            let actualSamples = history.map(ChartSample.init)

            if let firstActual = actualSamples.first, firstActual.timestamp > domain.lowerBound {
                samples.append(firstActual.withTimestamp(domain.lowerBound))
            }

            samples.append(contentsOf: actualSamples)

            if let lastActual = actualSamples.last, lastActual.timestamp < domain.upperBound {
                samples.append(lastActual.withTimestamp(domain.upperBound))
            }

            return samples
        }

        if let latestSnapshot {
            let base = ChartSample(snapshot: latestSnapshot)
            return [
                base.withTimestamp(domain.lowerBound),
                base.withTimestamp(domain.upperBound)
            ]
        }

        return [
            baselineSample(at: domain.lowerBound),
            baselineSample(at: domain.upperBound)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.blue)
                Text("Temperature History")
                    .font(.headline)
                Spacer()
                if let last = history.last {
                    Text("CPU \(String(format: "%.0f", last.avgCPU))° · GPU \(String(format: "%.0f", last.avgGPU))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if chartSamples.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        ProgressView()
                        Text("Collecting data...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                Chart(chartSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Temp", sample.avgCPU)
                    )
                    .foregroundStyle(by: .value("Series", "CPU Avg"))

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Temp", sample.maxCPU)
                    )
                    .foregroundStyle(by: .value("Series", "CPU Peak"))
                    .lineStyle(StrokeStyle(dash: [4, 3]))

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Temp", sample.avgGPU)
                    )
                    .foregroundStyle(by: .value("Series", "GPU Avg"))

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Temp", sample.maxGPU)
                    )
                    .foregroundStyle(by: .value("Series", "GPU Peak"))
                    .lineStyle(StrokeStyle(dash: [4, 3]))
                }
                .chartForegroundStyleScale([
                    "CPU Avg": Color.blue,
                    "CPU Peak": Color.blue.opacity(0.5),
                    "GPU Avg": Color.green,
                    "GPU Peak": Color.green.opacity(0.5),
                ])
                .chartYScale(domain: chartYDomain)
                .chartXScale(domain: chartXDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, spacing: 12)
                .frame(height: 180)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Unified Fan Card

struct UnifiedFanCard: View {
    @EnvironmentObject var fanManager: FanManager

    private var avgSpeed: Double {
        guard !fanManager.fans.isEmpty else { return 0 }
        return fanManager.fans.map(\.currentSpeed).reduce(0, +) / Double(fanManager.fans.count)
    }

    private var avgPercentage: Double {
        guard !fanManager.fans.isEmpty else { return 0 }
        return fanManager.fans.map { max(0, $0.speedPercentage) }.reduce(0, +) / Double(fanManager.fans.count)
    }

    private var isManual: Bool {
        fanManager.fans.contains(where: \.isManual)
    }

    private var allIdle: Bool {
        fanManager.fans.allSatisfy(\.isIdle)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Fan RPMs row
            HStack(spacing: 0) {
                ForEach(fanManager.fans) { fan in
                    HStack(spacing: 8) {
                        Image(systemName: "fan.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fan.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(isManual ? "Manual" : "Automatic")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.0f", fan.currentSpeed))
                                .font(.title3)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                            Text("RPM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if fan.id != fanManager.fans.last?.id {
                        Divider().padding(.vertical, 4).padding(.horizontal, 12)
                    }
                }

                if fanManager.fans.isEmpty {
                    HStack {
                        Image(systemName: "fan.slash")
                            .foregroundStyle(.secondary)
                        Text("No fans detected")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Unified speed buttons
            HStack(spacing: 6) {
                FanQuickButton(label: "Auto", isActive: fanManager.unifiedSpeedLabel == "Auto", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansAuto()
                }
                FanQuickButton(label: "25%", isActive: fanManager.unifiedSpeedLabel == "25%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 25)
                }
                FanQuickButton(label: "50%", isActive: fanManager.unifiedSpeedLabel == "50%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 50)
                }
                FanQuickButton(label: "75%", isActive: fanManager.unifiedSpeedLabel == "75%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 75)
                }
                FanQuickButton(label: "Max", isActive: fanManager.unifiedSpeedLabel == "Max", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 100)
                }
            }

            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: max(0, min(avgPercentage, 100)), total: 100)
                    .tint(speedColor(max(0, avgPercentage)))

                if let first = fanManager.fans.first {
                    HStack {
                        Text(String(format: "%.0f", first.minSpeed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(allIdle ? "Idle" : String(format: "%.0f%%", avgPercentage))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f", first.maxSpeed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func speedColor(_ percentage: Double) -> Color {
        if percentage < 30 { return .green }
        if percentage < 60 { return .yellow }
        if percentage < 80 { return .orange }
        return .red
    }
}

struct FanQuickButton: View {
    let label: String
    let isActive: Bool
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    if isLoading && isActive {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .padding(.trailing, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct EmptyFanCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fan.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No fans detected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Run as admin to access SMC")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sensor Group Card

struct SensorGroupCard: View {
    let title: String
    let icon: String
    let readings: [SensorReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(readings.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.bottom, 4)

            if readings.isEmpty {
                Text("No sensors available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(readings) { reading in
                    HStack {
                        Text(reading.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(reading.formattedValue)
                            .font(.callout)
                            .fontWeight(.medium)
                            .fontDesign(.rounded)
                    }
                    if reading.id != readings.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
