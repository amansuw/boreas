import SwiftUI
import Charts

struct NetworkView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @State private var historyRange: HistoryRange = .fiveMinutes

    private var filteredHistory: [NetworkSnapshot] {
        guard let window = historyRange.window else { return networkManager.history }
        let cutoff = Date().addingTimeInterval(-window)
        return networkManager.history.filter { $0.timestamp >= cutoff }
    }

    private var chartXDomain: ClosedRange<Date> {
        if let window = historyRange.window {
            let end = Date()
            return end.addingTimeInterval(-window)...end
        }
        if let first = networkManager.history.first?.timestamp,
           let last = networkManager.history.last?.timestamp, first != last {
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
                        Text("Network")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        if let iface = networkManager.stats.activeInterface {
                            Text("\(iface.displayName) (\(iface.id))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No active interface")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(networkManager.stats.activeInterface?.isUp == true ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(networkManager.stats.activeInterface?.isUp == true ? "UP" : "DOWN")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal)

                // Speed cards
                HStack(spacing: 12) {
                    SpeedCard(
                        title: "Download",
                        speed: networkManager.stats.downloadBytesPerSec,
                        icon: "arrow.down.circle.fill",
                        color: .blue,
                        total: networkManager.stats.totalDownload
                    )
                    SpeedCard(
                        title: "Upload",
                        speed: networkManager.stats.uploadBytesPerSec,
                        icon: "arrow.up.circle.fill",
                        color: .green,
                        total: networkManager.stats.totalUpload
                    )
                }
                .padding(.horizontal)

                // Traffic History
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.blue)
                        Text("Traffic History")
                            .font(.headline)
                        Spacer()
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
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Speed", Double(sample.downloadBytesPerSec) / 1024)
                            )
                            .foregroundStyle(by: .value("Direction", "Download"))

                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Speed", Double(sample.uploadBytesPerSec) / 1024)
                            )
                            .foregroundStyle(by: .value("Direction", "Upload"))
                        }
                        .chartForegroundStyleScale([
                            "Download": Color.blue,
                            "Upload": Color.green,
                        ])
                        .chartXScale(domain: chartXDomain)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(String(format: "%.0f KB/s", v))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartLegend(position: .bottom, spacing: 8)
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

                // Interface Details
                if let iface = networkManager.stats.activeInterface {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundStyle(.blue)
                            Text("Interface")
                                .font(.headline)
                            Spacer()
                        }

                        VStack(spacing: 6) {
                            NetworkDetailRow(label: "Interface", value: "\(iface.displayName) (\(iface.id))")
                            NetworkDetailRow(label: "Status", value: iface.isUp ? "UP" : "DOWN")
                            if !iface.macAddress.isEmpty {
                                NetworkDetailRow(label: "Physical Address", value: iface.macAddress)
                            }
                            if !iface.speed.isEmpty {
                                NetworkDetailRow(label: "Speed", value: iface.speed)
                            }
                            if !networkManager.stats.dnsServers.isEmpty {
                                NetworkDetailRow(label: "DNS Server", value: networkManager.stats.dnsServers.joined(separator: ", "))
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // IPs
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.purple)
                        Text("IP Addresses")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(spacing: 6) {
                        NetworkDetailRow(label: "Local IP", value: networkManager.stats.activeInterface?.localIP ?? "N/A")
                        NetworkDetailRow(label: "Public IP", value: networkManager.stats.publicIP.isEmpty ? "Fetching..." : networkManager.stats.publicIP)
                        if !networkManager.stats.publicIPv6.isEmpty {
                            NetworkDetailRow(label: "Public IPv6", value: networkManager.stats.publicIPv6)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Totals
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundStyle(.orange)
                        Text("Session Totals")
                            .font(.headline)
                        Spacer()
                    }
                    VStack(spacing: 6) {
                        NetworkDetailRow(label: "Total Download", value: ByteFormatter.format(networkManager.stats.totalDownload))
                        NetworkDetailRow(label: "Total Upload", value: ByteFormatter.format(networkManager.stats.totalUpload))
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

// MARK: - Speed Card

struct SpeedCard: View {
    let title: String
    let speed: UInt64
    let icon: String
    let color: Color
    let total: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(ByteFormatter.formatSpeed(speed))
                .font(.title2)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(color)
            Text("Total: \(ByteFormatter.format(total))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Network Detail Row

struct NetworkDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.rounded)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}
