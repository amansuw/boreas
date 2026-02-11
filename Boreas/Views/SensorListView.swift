import SwiftUI

struct SensorListView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @State private var selectedCategory: SensorCategory? = nil
    @State private var searchText = ""

    var filteredReadings: [SensorReading] {
        var readings = sensorManager.readings

        if let category = selectedCategory {
            readings = readings.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            readings = readings.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.key.localizedCaseInsensitiveContains(searchText)
            }
        }

        return readings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sensors")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(sensorManager.readings.count) sensors detected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        sensorManager.discoverSensors()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search sensors...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    // Category filter
                    Picker("Category", selection: $selectedCategory) {
                        Text("All").tag(nil as SensorCategory?)
                        ForEach(SensorCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category as SensorCategory?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)
                }
            }
            .padding()

            Divider()

            // Sensor List
            if sensorManager.isDiscovering {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Discovering sensors...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Enumerating all SMC keys on this Mac")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredReadings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sensor.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No sensors found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Try running the app with elevated privileges or check SMC access.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Group by category
                        ForEach(SensorCategory.allCases) { category in
                            let categoryReadings = filteredReadings.filter { $0.category == category }
                            if !categoryReadings.isEmpty {
                                SensorCategorySection(
                                    category: category,
                                    readings: categoryReadings
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sensor Category Section

struct SensorCategorySection: View {
    let category: SensorCategory
    let readings: [SensorReading]
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Section Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text(category.rawValue)
                        .font(.headline)
                    Text("(\(readings.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(readings) { reading in
                        SensorRow(reading: reading)
                        if reading.id != readings.last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Sensor Row

struct SensorRow: View {
    let reading: SensorReading

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.name)
                    .font(.callout)
                Text(reading.key)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            Text(reading.formattedValue)
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.rounded)
                .foregroundStyle(valueColor(reading))

            // Visual indicator for temperatures
            if reading.category == .temperature {
                TemperatureBar(value: reading.value, maxValue: 105)
                    .frame(width: 60, height: 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    private func valueColor(_ reading: SensorReading) -> Color {
        guard reading.category == .temperature else { return .primary }
        if reading.value < 45 { return .green }
        if reading.value < 65 { return .yellow }
        if reading.value < 80 { return .orange }
        return .red
    }
}

// MARK: - Temperature Bar

struct TemperatureBar: View {
    let value: Double
    let maxValue: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geometry.size.width * CGFloat(min(value / maxValue, 1.0)))
            }
        }
    }

    private var barColor: Color {
        let ratio = value / maxValue
        if ratio < 0.4 { return .green }
        if ratio < 0.6 { return .yellow }
        if ratio < 0.8 { return .orange }
        return .red
    }
}
