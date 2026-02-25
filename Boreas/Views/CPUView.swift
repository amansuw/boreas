import SwiftUI
import Charts

struct CPUView: View {
    @EnvironmentObject var cpuManager: CPUManager
    @State private var historyRange: HistoryRange = .fiveMinutes

    private var filteredHistory: [CPUManager.CPUUsageSnapshot] {
        guard let window = historyRange.window else { return cpuManager.usageHistory }
        let cutoff = Date().addingTimeInterval(-window)
        return cpuManager.usageHistory.filter { $0.timestamp >= cutoff }
    }

    private var chartXDomain: ClosedRange<Date> {
        if let window = historyRange.window {
            let end = Date()
            return end.addingTimeInterval(-window)...end
        }
        if let first = cpuManager.usageHistory.first?.timestamp,
           let last = cpuManager.usageHistory.last?.timestamp, first != last {
            return first...last
        }
        let end = Date()
        return end.addingTimeInterval(-60)...end
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CPU")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(cpuManager.totalCores) cores (\(cpuManager.pCores) P + \(cpuManager.eCores) E)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Uptime badge
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Up \(cpuManager.formattedUptime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal)

                // Top row: gauge + summary stats
                HStack(spacing: 16) {
                    // Usage gauge
                    CPUGaugeView(usage: cpuManager.usage)
                        .frame(width: 160, height: 160)

                    // Summary stats
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            MiniStatCard(title: "System", value: String(format: "%.0f%%", cpuManager.usage.system), color: .red)
                            MiniStatCard(title: "User", value: String(format: "%.0f%%", cpuManager.usage.user), color: .blue)
                            MiniStatCard(title: "Idle", value: String(format: "%.0f%%", cpuManager.usage.idle), color: .gray)
                        }
                        HStack(spacing: 12) {
                            MiniStatCard(title: "E-Cores", value: String(format: "%.0f%%", cpuManager.usage.efficiencyCores), color: .green)
                            MiniStatCard(title: "P-Cores", value: String(format: "%.0f%%", cpuManager.usage.performanceCores), color: .orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Per-core bars
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.blue)
                        Text("Per-Core Usage")
                            .font(.headline)
                        Spacer()
                    }

                    let cores = cpuManager.usage.perCore
                    let pCoresList = cores.filter { !$0.isEfficiency }
                    let eCoresList = cores.filter { $0.isEfficiency }

                    if !pCoresList.isEmpty {
                        Text("Performance Cores")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(pCoresList.count, 6)), spacing: 4) {
                            ForEach(pCoresList) { core in
                                CoreBarView(core: core)
                            }
                        }
                    }

                    if !eCoresList.isEmpty {
                        Text("Efficiency Cores")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(eCoresList.count, 6)), spacing: 4) {
                            ForEach(eCoresList) { core in
                                CoreBarView(core: core)
                            }
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Usage History Chart
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.blue)
                        Text("Usage History")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", cpuManager.usage.total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text("Range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Range", selection: $historyRange) {
                            ForEach(HistoryRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if filteredHistory.count >= 2 {
                        Chart(filteredHistory) { sample in
                            AreaMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Usage", sample.total)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Usage", sample.total)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        .chartYScale(domain: 0...100)
                        .chartXScale(domain: chartXDomain)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                                AxisValueLabel {
                                    Text("\(value.as(Int.self) ?? 0)%")
                                        .font(.caption2)
                                }
                            }
                        }
                        .frame(height: 120)
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("Collecting data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 120)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Load Average + Frequency
                HStack(spacing: 12) {
                    // Load Average
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .foregroundStyle(.orange)
                            Text("Average Load")
                                .font(.headline)
                        }
                        VStack(spacing: 6) {
                            LoadRow(label: "1 minute", value: cpuManager.loadAverage.oneMinute)
                            LoadRow(label: "5 minutes", value: cpuManager.loadAverage.fiveMinute)
                            LoadRow(label: "15 minutes", value: cpuManager.loadAverage.fifteenMinute)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Frequency
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundStyle(.purple)
                            Text("Frequency")
                                .font(.headline)
                        }
                        VStack(spacing: 6) {
                            FreqRow(label: "All Cores", value: cpuManager.frequency.allCores)
                            FreqRow(label: "E-Cores", value: cpuManager.frequency.efficiencyCores)
                            FreqRow(label: "P-Cores", value: cpuManager.frequency.performanceCores)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Top Processes
                TopProcessesCard(title: "Top CPU Processes", icon: "cpu", processes: cpuManager.topProcesses)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - CPU Gauge

struct CPUGaugeView: View {
    let usage: CPUUsage

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 12)

            Circle()
                .trim(from: 0, to: min(usage.total / 100, 1))
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: usage.total)

            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", usage.total))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gaugeColor: Color {
        if usage.total < 30 { return .green }
        if usage.total < 60 { return .yellow }
        if usage.total < 80 { return .orange }
        return .red
    }
}

// MARK: - Core Bar

struct CoreBarView: View {
    let core: CPUUsage.CoreUsage

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(height: geo.size.height * CGFloat(min(core.usage / 100, 1)))
                }
            }
            .frame(height: 40)

            Text(String(format: "%.0f", core.usage))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var barColor: Color {
        if core.usage < 30 { return .green }
        if core.usage < 60 { return .yellow }
        if core.usage < 80 { return .orange }
        return .red
    }
}

// MARK: - Mini Stat Card

struct MiniStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Load Row

struct LoadRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f", value))
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.rounded)
        }
    }
}

// MARK: - Freq Row

struct FreqRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if value > 0 {
                Text("\(value) MHz")
                    .font(.callout)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
            } else {
                Text("N/A")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Top Processes Card (Reusable)

struct TopProcessesCard: View {
    let title: String
    let icon: String
    let processes: [TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(processes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if processes.isEmpty {
                Text("No processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(processes) { proc in
                    HStack {
                        Text(proc.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(proc.formattedValue)
                            .font(.callout)
                            .fontWeight(.medium)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    if proc.id != processes.last?.id {
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
