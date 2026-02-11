import SwiftUI

struct FanControlView: View {
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var sensorManager: SensorManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fan Control")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Manually control fan speeds")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Admin Access Warning
                if !fanManager.hasWriteAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Admin Access Required")
                                .font(.headline)
                            Text("Fan control requires elevated privileges to write to SMC.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if fanManager.isRequestingAccess {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Grant Access") {
                                fanManager.requestAdminAccess()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Control Mode Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Control Mode")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(FanControlMode.allCases) { mode in
                            ControlModeButton(
                                mode: mode,
                                isSelected: fanManager.controlMode == mode
                            ) {
                                fanManager.setControlMode(mode)
                            }
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Manual Speed Control
                if fanManager.controlMode == .manual {
                    ManualSpeedSection()
                }

                // Individual Fan Controls
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fan Status")
                        .font(.headline)
                        .padding(.horizontal)

                    if fanManager.fans.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "fan.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("No fans detected")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("Ensure the app has the required permissions to access SMC.\nTry running with sudo or installing the helper tool.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 30)
                            Spacer()
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    } else {
                        ForEach(fanManager.fans) { fan in
                            IndividualFanControl(fan: fan)
                                .padding(.horizontal)
                        }
                    }
                }

                // Warning
                if fanManager.controlMode != .automatic {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Manual fan control overrides macOS automatic management. Fans will reset to automatic when the app quits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Control Mode Button

struct ControlModeButton: View {
    let mode: FanControlMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                Text(mode.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}

// MARK: - Manual Speed Section

struct ManualSpeedSection: View {
    @EnvironmentObject var fanManager: FanManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("All Fans Speed")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", fanManager.manualSpeedPercentage))
                    .font(.title2)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(.blue)
            }

            Slider(
                value: Binding(
                    get: { fanManager.manualSpeedPercentage },
                    set: { fanManager.setManualSpeed(percentage: $0) }
                ),
                in: 0...100,
                step: 1
            )
            .tint(.blue)

            HStack {
                Text("0%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("25%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("50%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("75%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("100%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { preset in
                    Button("\(preset)%") {
                        fanManager.setManualSpeed(percentage: Double(preset))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Individual Fan Control

struct IndividualFanControl: View {
    let fan: FanInfo
    @EnvironmentObject var fanManager: FanManager
    @State private var individualSpeed: Double = 50

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "fan.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(fan.currentSpeed > 0 ? 360 : 0))
                    .animation(
                        fan.currentSpeed > 0
                            ? .linear(duration: max(0.3, 3000 / fan.currentSpeed)).repeatForever(autoreverses: false)
                            : .default,
                        value: fan.currentSpeed > 0
                    )

                VStack(alignment: .leading) {
                    Text(fan.name)
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label(String(format: "%.0f RPM", fan.currentSpeed), systemImage: "gauge")
                        Label(String(format: "%.0f%%", fan.speedPercentage), systemImage: "percent")
                        Label(fan.isManual ? "Manual" : "Auto", systemImage: fan.isManual ? "hand.raised" : "gearshape")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(String(format: "%.0f", fan.currentSpeed))
                        .font(.title)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    Text("RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: max(0, min(fan.speedPercentage, 100)), total: 100)
                .tint(speedColor(max(0, fan.speedPercentage)))

            HStack {
                Text(String(format: "Min: %.0f RPM", fan.minSpeed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "Target: %.0f RPM", fan.targetSpeed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "Max: %.0f RPM", fan.maxSpeed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func speedColor(_ percentage: Double) -> Color {
        if percentage < 30 { return .green }
        if percentage < 60 { return .yellow }
        if percentage < 80 { return .orange }
        return .red
    }
}
