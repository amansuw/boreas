import SwiftUI
import Charts

struct GPUView: View {
    @EnvironmentObject var gpuManager: GPUManager
    @State private var historyRange: HistoryRange = .fiveMinutes

    private var filteredHistory: [GPUManager.GPUSnapshot] {
        guard let window = historyRange.window else { return gpuManager.usageHistory }
        let cutoff = Date().addingTimeInterval(-window)
        return gpuManager.usageHistory.filter { $0.timestamp >= cutoff }
    }

    private var chartXDomain: ClosedRange<Date> {
        if let window = historyRange.window {
            let end = Date()
            return end.addingTimeInterval(-window)...end
        }
        if let first = gpuManager.usageHistory.first?.timestamp,
           let last = gpuManager.usageHistory.last?.timestamp, first != last {
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
                        Text("GPU")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(gpuManager.usage.modelName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Gauge + Stats
                HStack(spacing: 16) {
                    GPUGaugeView(percent: gpuManager.usage.utilization)
                        .frame(width: 160, height: 160)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            MiniStatCard(title: "Usage", value: String(format: "%.0f%%", gpuManager.usage.utilization), color: .green)
                            MiniStatCard(title: "Render", value: String(format: "%.0f%%", gpuManager.usage.renderUtilization), color: .cyan)
                            MiniStatCard(title: "Tiler", value: String(format: "%.0f%%", gpuManager.usage.tilerUtilization), color: .purple)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Usage History Chart
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.green)
                        Text("Usage History")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", gpuManager.usage.utilization))
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
                                y: .value("Usage", sample.utilization)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green.opacity(0.3), .green.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Usage", sample.utilization)
                            )
                            .foregroundStyle(.green)
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
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - GPU Gauge

struct GPUGaugeView: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(percent / 100, 1))
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percent)
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", percent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("GPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gaugeColor: Color {
        if percent < 30 { return .green }
        if percent < 60 { return .yellow }
        if percent < 80 { return .orange }
        return .red
    }
}
