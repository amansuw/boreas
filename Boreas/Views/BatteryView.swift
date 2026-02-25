import SwiftUI

struct BatteryView: View {
    @EnvironmentObject var batteryManager: BatteryManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Battery")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(batteryManager.battery.hasBattery ? batteryManager.battery.source : "No battery detected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if !batteryManager.battery.hasBattery {
                    VStack(spacing: 12) {
                        Image(systemName: "battery.0")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No battery detected")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("This module is only available on MacBooks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    // Battery Level + Status
                    HStack(spacing: 16) {
                        BatteryGaugeView(level: batteryManager.battery.level, isCharging: batteryManager.battery.isCharging)
                            .frame(width: 160, height: 160)

                        VStack(alignment: .leading, spacing: 10) {
                            BatteryDetailRow(label: "Level", value: String(format: "%.0f%%", batteryManager.battery.level))
                            BatteryDetailRow(label: "Source", value: batteryManager.battery.source)
                            BatteryDetailRow(label: "Status", value: chargingStatus)
                            BatteryDetailRow(label: "Power", value: String(format: "%.2f W", batteryManager.battery.power))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Battery Health
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Battery Health")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.0f%%", batteryManager.battery.healthPercent))
                                .font(.title3)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(healthColor)
                        }

                        // Health bar
                        ProgressView(value: min(batteryManager.battery.healthPercent, 100), total: 100)
                            .tint(healthColor)

                        VStack(spacing: 6) {
                            BatteryDetailRow(label: "Design Capacity", value: "\(batteryManager.battery.designCapacity) mAh")
                            BatteryDetailRow(label: "Max Capacity", value: "\(batteryManager.battery.maxCapacity) mAh")
                            BatteryDetailRow(label: "Current Capacity", value: "\(batteryManager.battery.currentCapacity) mAh")
                            BatteryDetailRow(label: "Cycle Count", value: "\(batteryManager.battery.cycleCount)")
                            BatteryDetailRow(label: "Temperature", value: String(format: "%.1f°C", batteryManager.battery.temperature))
                            BatteryDetailRow(label: "Voltage", value: String(format: "%.2f V", batteryManager.battery.voltage))
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Power Adapter
                    if batteryManager.battery.isPluggedIn {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "powerplug.fill")
                                    .foregroundStyle(.green)
                                Text("Power Adapter")
                                    .font(.headline)
                                Spacer()
                            }

                            VStack(spacing: 6) {
                                BatteryDetailRow(label: "Charging", value: batteryManager.battery.isCharging ? "Yes" : "No")
                                BatteryDetailRow(label: "Power", value: "\(batteryManager.battery.adapterWatts) W")
                                BatteryDetailRow(label: "Current", value: "\(batteryManager.battery.adapterCurrent) mA")
                                BatteryDetailRow(label: "Voltage", value: "\(batteryManager.battery.adapterVoltage) mV")
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var chargingStatus: String {
        if batteryManager.battery.isCharging {
            if batteryManager.battery.timeRemaining > 0 {
                return "Charging (\(batteryManager.battery.timeRemaining) min)"
            }
            return "Charging"
        }
        if batteryManager.battery.level >= 100 {
            return "Fully Charged"
        }
        if batteryManager.battery.timeRemaining > 0 {
            let hrs = batteryManager.battery.timeRemaining / 60
            let mins = batteryManager.battery.timeRemaining % 60
            return "Discharging (\(hrs)h \(mins)m)"
        }
        return "On Battery"
    }

    private var healthColor: Color {
        if batteryManager.battery.healthPercent > 80 { return .green }
        if batteryManager.battery.healthPercent > 50 { return .yellow }
        return .red
    }
}

// MARK: - Battery Gauge

struct BatteryGaugeView: View {
    let level: Double
    let isCharging: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(level / 100, 1))
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: level)
            VStack(spacing: 2) {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Text(String(format: "%.0f%%", level))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gaugeColor: Color {
        if level > 50 { return .green }
        if level > 20 { return .yellow }
        return .red
    }
}

// MARK: - Battery Detail Row

struct BatteryDetailRow: View {
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
        }
    }
}
