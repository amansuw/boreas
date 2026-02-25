import SwiftUI

struct DiskView: View {
    @EnvironmentObject var diskManager: DiskManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disk")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(diskManager.disks.count) volume\(diskManager.disks.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // I/O Speed cards
                HStack(spacing: 12) {
                    SpeedCard(
                        title: "Read",
                        speed: diskManager.io.readBytesPerSec,
                        icon: "arrow.down.doc.fill",
                        color: .blue,
                        total: 0
                    )
                    SpeedCard(
                        title: "Write",
                        speed: diskManager.io.writeBytesPerSec,
                        icon: "arrow.up.doc.fill",
                        color: .orange,
                        total: 0
                    )
                }
                .padding(.horizontal)

                // Volume cards
                ForEach(diskManager.disks) { disk in
                    DiskVolumeCard(disk: disk)
                        .padding(.horizontal)
                }

                // Top Processes
                if !diskManager.topProcesses.isEmpty {
                    TopProcessesCard(title: "Top Disk Processes", icon: "internaldrive", processes: diskManager.topProcesses)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Disk Volume Card

struct DiskVolumeCard: View {
    let disk: DiskInfo

    var body: some View {
        HStack(spacing: 16) {
            // Gauge
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(disk.usagePercent / 100, 1))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", disk.usagePercent))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Disk")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text(disk.name)
                    .font(.headline)

                // Storage bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(gaugeColor)
                            .frame(width: geo.size.width * CGFloat(min(disk.usagePercent / 100, 1)))
                    }
                }
                .frame(height: 8)

                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(gaugeColor).frame(width: 6, height: 6)
                        Text("Used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.format(disk.usedBytes))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                        Text("Free")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.format(disk.freeBytes))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var gaugeColor: Color {
        if disk.usagePercent < 60 { return .blue }
        if disk.usagePercent < 80 { return .yellow }
        if disk.usagePercent < 90 { return .orange }
        return .red
    }
}
