import SwiftUI
import Charts

struct MenuBarView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var profileManager: ProfileManager

    private var chartDomain: ClosedRange<Double> {
        let temps = sensorManager.temperatureHistory.flatMap { [$0.avgCPU, $0.maxCPU, $0.avgGPU, $0.maxGPU] }
        guard let minVal = temps.min(), let maxVal = temps.max() else { return 0...100 }
        let padding: Double = 8
        let lower = max(0, minVal - padding)
        var upper = maxVal + padding
        if upper - lower < 20 { upper = lower + 20 }
        return lower...upper
    }

    var body: some View {
        VStack(spacing: 0) {
            // Temp stat cards — 2x2 compact grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                MiniStatCard(label: "CPU Avg", value: sensorManager.averageCPUTemp, color: tempColor(sensorManager.averageCPUTemp))
                MiniStatCard(label: "GPU Avg", value: sensorManager.averageGPUTemp, color: tempColor(sensorManager.averageGPUTemp))
                MiniStatCard(label: "CPU Peak", value: sensorManager.hottestCPUTemp, color: tempColor(sensorManager.hottestCPUTemp))
                MiniStatCard(label: "GPU Peak", value: sensorManager.hottestGPUTemp, color: tempColor(sensorManager.hottestGPUTemp))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Temperature history chart
            let history = sensorManager.filteredHistory
            if history.count >= 2 {
                VStack(spacing: 4) {
                    // Range picker (compact)
                    Picker("Range", selection: $sensorManager.historyRange) {
                        ForEach(HistoryRange.allCases) { range in
                            Text(range.rawValue)
                                .tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 10)

                    HStack {
                        Text("CPU \(String(format: "%.0f", history.last?.avgCPU ?? 0))° · GPU \(String(format: "%.0f", history.last?.avgGPU ?? 0))°")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)

                    Chart(Array(history.suffix(40))) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.id),
                            y: .value("Temp", snapshot.avgCPU)
                        )
                        .foregroundStyle(by: .value("Series", "CPU Avg"))

                        LineMark(
                            x: .value("Time", snapshot.id),
                            y: .value("Temp", snapshot.maxCPU)
                        )
                        .foregroundStyle(by: .value("Series", "CPU Peak"))
                        .lineStyle(StrokeStyle(dash: [4, 3]))

                        LineMark(
                            x: .value("Time", snapshot.id),
                            y: .value("Temp", snapshot.avgGPU)
                        )
                        .foregroundStyle(by: .value("Series", "GPU Avg"))

                        LineMark(
                            x: .value("Time", snapshot.id),
                            y: .value("Temp", snapshot.maxGPU)
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
                    .chartYScale(domain: chartDomain)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            AxisValueLabel()
                        }
                    }
                    .chartLegend(position: .bottom, spacing: 8)
                    .frame(height: 100)
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 6)
            }

            Divider().padding(.horizontal, 8)

            // Fan RPMs — compact row
            HStack(spacing: 0) {
                ForEach(fanManager.fans) { fan in
                    HStack(spacing: 4) {
                        Image(systemName: "fan.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                        Text(fan.name)
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text(String(format: "%.0f", fan.currentSpeed))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(fan.isManual ? .orange : .primary)
                        Text("RPM")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    if fan.id != fanManager.fans.last?.id {
                        Divider().frame(height: 14).padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider().padding(.horizontal, 8)

            // Fan quick controls — unified
            HStack(spacing: 4) {
                MenuBarFanButton(label: "Auto", isActive: fanManager.unifiedSpeedLabel == "Auto", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansAuto()
                }
                MenuBarFanButton(label: "25%", isActive: fanManager.unifiedSpeedLabel == "25%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 25)
                }
                MenuBarFanButton(label: "50%", isActive: fanManager.unifiedSpeedLabel == "50%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 50)
                }
                MenuBarFanButton(label: "75%", isActive: fanManager.unifiedSpeedLabel == "75%", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 75)
                }
                MenuBarFanButton(label: "Max", isActive: fanManager.unifiedSpeedLabel == "Max", isLoading: fanManager.isYielding) {
                    fanManager.setAllFansSpeed(percentage: 100)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider().padding(.horizontal, 8)

            // Profile quick access
            VStack(spacing: 6) {
                HStack {
                    Text("Profiles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)

                let quickProfiles: [FanProfile] = [
                    profileManager.profiles.first(where: { $0.name == "Default" }),
                    profileManager.profiles.first(where: { $0.name == "Silent" }),
                    profileManager.profiles.first(where: { $0.name == "Max" }),
                    profileManager.latestCustomProfile
                ].compactMap { $0 }

                if quickProfiles.isEmpty {
                    HStack {
                        Text("No profiles")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                } else {
                    HStack(spacing: 6) {
                        ForEach(quickProfiles, id: \.id) { profile in
                            Button(action: { activateProfile(profile) }) {
                                Text(profile.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        (profileManager.activeProfile?.id == profile.id ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08)),
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(profileManager.activeProfile?.id == profile.id ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 4)

            // Actions
            VStack(spacing: 0) {
                Button(action: {
                    // Activate existing main window or create it via the SwiftUI Window scene
                    if let window = NSApp.windows.first(where: {
                        $0.identifier?.rawValue.contains("main") == true ||
                        $0.title == "Boreas"
                    }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    HStack {
                        Text("Open Boreas")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)

                Button(action: {
                    SMCKit.shared.resetAllFansToAutomatic()
                    NSApp.terminate(nil)
                }) {
                    HStack {
                        Text("Quit")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .frame(width: 380)
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp <= 0 { return .gray }
        if temp < 50 { return .green }
        if temp < 70 { return .yellow }
        if temp < 85 { return .orange }
        return .red
    }

    // MARK: - Mini Stat Card for menu bar

    struct MiniStatCard: View {
        let label: String
        let value: Double
        let color: Color

        var body: some View {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f°C", value))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

}

struct MenuBarFanButton: View {
    let label: String
    let isActive: Bool
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isActive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    if isLoading && isActive {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .padding(.trailing, 6)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Profile activation

private extension MenuBarView {
    func activateProfile(_ profile: FanProfile) {
        profileManager.setActiveProfile(profile)

        switch profile.mode {
        case .automatic:
            fanManager.setControlMode(.automatic)
        case .manual:
            if let speed = profile.manualSpeedPercentage {
                fanManager.manualSpeedPercentage = speed
                fanManager.setControlMode(.manual)
            }
        case .curve:
            if let curve = profile.curve {
                profileManager.customCurve = curve
                fanManager.activeCurve = curve
                fanManager.curveTemperatureProvider = { [weak sensorManager] in
                    sensorManager?.averageCPUTemp ?? 0
                }
                fanManager.setControlMode(.curve)
                fanManager.applyFanCurveSpeed(
                    temperature: sensorManager.averageCPUTemp,
                    curve: curve,
                    allowImmediateOff: true
                )
            }
        }
    }
}
