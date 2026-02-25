import SwiftUI
import Charts

struct RAMView: View {
    @EnvironmentObject var ramManager: RAMManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(ByteFormatter.format(ramManager.memory.total) + " Total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Pressure badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(pressureColor)
                            .frame(width: 8, height: 8)
                        Text("Pressure: \(pressureLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal)

                // Gauge + Breakdown
                HStack(spacing: 16) {
                    // Gauge
                    RAMGaugeView(percent: ramManager.memory.usagePercent)
                        .frame(width: 160, height: 160)

                    // Breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        MemoryRow(label: "Used", value: ramManager.memory.used, color: .blue)
                        MemoryRow(label: "App", value: ramManager.memory.app, color: .cyan)
                        MemoryRow(label: "Wired", value: ramManager.memory.wired, color: .orange)
                        MemoryRow(label: "Compressed", value: ramManager.memory.compressed, color: .purple)
                        MemoryRow(label: "Free", value: ramManager.memory.free, color: .gray)
                        Divider()
                        MemoryRow(label: "Swap", value: ramManager.memory.swap, color: .red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Memory breakdown bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "memorychip")
                            .foregroundStyle(.blue)
                        Text("Memory Composition")
                            .font(.headline)
                        Spacer()
                    }
                    MemoryCompositionBar(memory: ramManager.memory)
                        .frame(height: 24)
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
                        Text(String(format: "%.0f%%", ramManager.memory.usagePercent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if ramManager.usageHistory.count >= 2 {
                        Chart(ramManager.usageHistory) { sample in
                            AreaMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Usage", sample.usagePercent)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Usage", sample.usagePercent)
                            )
                            .foregroundStyle(.purple)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        .chartYScale(domain: 0...100)
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

                // Top Processes
                TopProcessesCard(title: "Top Memory Processes", icon: "memorychip", processes: ramManager.topProcesses)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pressureColor: Color {
        switch ramManager.memory.pressureLevel {
        case 1: return .green
        case 2: return .yellow
        default: return .red
        }
    }

    private var pressureLabel: String {
        switch ramManager.memory.pressureLevel {
        case 1: return "Normal"
        case 2: return "Warning"
        default: return "Critical"
        }
    }
}

// MARK: - RAM Gauge

struct RAMGaugeView: View {
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
                Text("RAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gaugeColor: Color {
        if percent < 50 { return .green }
        if percent < 75 { return .yellow }
        if percent < 90 { return .orange }
        return .red
    }
}

// MARK: - Memory Row

struct MemoryRow: View {
    let label: String
    let value: UInt64
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(ByteFormatter.format(value))
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.rounded)
        }
    }
}

// MARK: - Memory Composition Bar

struct MemoryCompositionBar: View {
    let memory: MemoryBreakdown

    var body: some View {
        GeometryReader { geo in
            let total = Double(memory.total)
            guard total > 0 else { return AnyView(EmptyView()) }

            let appW = geo.size.width * CGFloat(Double(memory.app) / total)
            let wiredW = geo.size.width * CGFloat(Double(memory.wired) / total)
            let compW = geo.size.width * CGFloat(Double(memory.compressed) / total)
            let freeW = max(0, geo.size.width - appW - wiredW - compW)

            return AnyView(
                HStack(spacing: 0) {
                    Rectangle().fill(Color.cyan).frame(width: appW)
                    Rectangle().fill(Color.orange).frame(width: wiredW)
                    Rectangle().fill(Color.purple).frame(width: compW)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: freeW)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            )
        }
    }
}
