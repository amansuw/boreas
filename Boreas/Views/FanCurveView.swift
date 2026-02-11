import SwiftUI

struct FanCurveView: View {
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var selectedPointId: UUID?
    @State private var showSaveSheet = false
    @State private var newProfileName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fan Curve")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Define temperature-to-fan-speed mapping")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showSaveSheet = true
                    } label: {
                        Label("Save as Profile", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        fanManager.setControlMode(.curve)
                    } label: {
                        Label(
                            fanManager.controlMode == .curve ? "Active" : "Apply",
                            systemImage: fanManager.controlMode == .curve ? "checkmark.circle.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(fanManager.controlMode == .curve ? .green : .blue)
                }
                .padding(.horizontal)

                // Curve Graph
                FanCurveGraph(
                    curve: $profileManager.customCurve,
                    selectedPointId: $selectedPointId,
                    currentTemp: sensorManager.averageCPUTemp
                )
                .frame(height: 350)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Sensor Selection
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature Source")
                            .font(.headline)
                        Text("Select which sensor drives the fan curve")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    let sources = sensorManager.fanCurveSources

                    Picker("Sensor", selection: $profileManager.customCurve.sensorKey) {
                        ForEach(sources) { reading in
                            Text("\(reading.name) (\(reading.formattedValue))")
                                .tag(reading.id)
                        }
                    }
                    .frame(maxWidth: 300)
                    .onAppear {
                        if sources.first(where: { $0.id == profileManager.customCurve.sensorKey }) == nil,
                           let first = sources.first {
                            profileManager.customCurve.sensorKey = first.id
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Point Editor
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Curve Points")
                            .font(.headline)
                        Spacer()
                        Button {
                            addPoint()
                        } label: {
                            Label("Add Point", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Table header
                    HStack {
                        Text("Temperature")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Fan Speed")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("")
                            .frame(width: 30)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    ForEach(profileManager.customCurve.sortedPoints) { point in
                        CurvePointRow(
                            point: point,
                            isSelected: selectedPointId == point.id,
                            canDelete: profileManager.customCurve.points.count > 2,
                            onSelect: { selectedPointId = point.id },
                            onUpdateTemp: { temp in
                                profileManager.customCurve.updatePoint(id: point.id, temperature: temp)
                                profileManager.saveCustomCurve()
                            },
                            onUpdateSpeed: { speed in
                                profileManager.customCurve.updatePoint(id: point.id, fanSpeed: speed)
                                profileManager.saveCustomCurve()
                            },
                            onDelete: {
                                if let index = profileManager.customCurve.points.firstIndex(where: { $0.id == point.id }) {
                                    profileManager.customCurve.removePoint(at: index)
                                    profileManager.saveCustomCurve()
                                }
                            }
                        )
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Current Status
                if fanManager.controlMode == .curve {
                    HStack(spacing: 16) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fan curve is active")
                                .font(.callout)
                                .fontWeight(.medium)
                            let currentSpeed = profileManager.customCurve.speedForTemperature(sensorManager.averageCPUTemp)
                            Text(String(format: "Current temp: %.1f°C → Fan speed: %.0f%%", sensorManager.averageCPUTemp, currentSpeed))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSaveSheet) {
            SaveProfileSheet(name: $newProfileName) {
                let _ = profileManager.createProfileFromCurrentCurve(name: newProfileName)
                newProfileName = ""
                showSaveSheet = false
            }
        }
        .onChange(of: profileManager.customCurve) { _, _ in
            if fanManager.controlMode == .curve {
                fanManager.activeCurve = profileManager.customCurve
                fanManager.curveTemperatureProvider = { [weak sensorManager] in
                    sensorManager?.averageCPUTemp ?? 0
                }
                let temp = sensorManager.averageCPUTemp
                fanManager.applyFanCurveSpeed(temperature: temp, curve: profileManager.customCurve)
            }
        }
    }

    private func addPoint() {
        let sorted = profileManager.customCurve.sortedPoints
        let lastTemp = sorted.last?.temperature ?? 50
        let newTemp = min(lastTemp + 10, 100)
        let newSpeed = min((sorted.last?.fanSpeed ?? 50) + 15, 100)
        let point = CurvePoint(temperature: newTemp, fanSpeed: newSpeed)
        profileManager.customCurve.addPoint(point)
        profileManager.saveCustomCurve()
    }
}

// MARK: - Fan Curve Graph

struct FanCurveGraph: View {
    @Binding var curve: FanCurve
    @Binding var selectedPointId: UUID?
    let currentTemp: Double

    private let tempRange: ClosedRange<Double> = 20...105
    private let speedRange: ClosedRange<Double> = 0...100
    private let gridLines = 5

    var body: some View {
        GeometryReader { geometry in
            let plotArea = CGRect(
                x: 50, y: 20,
                width: geometry.size.width - 70,
                height: geometry.size.height - 50
            )

            ZStack(alignment: .topLeading) {
                // Background grid
                drawGrid(in: plotArea)

                // Axis labels
                drawAxisLabels(in: plotArea)

                // Filled area under curve
                drawFilledArea(in: plotArea)

                // Curve line
                drawCurveLine(in: plotArea)

                // Current temperature indicator
                drawCurrentTempIndicator(in: plotArea)

                // Draggable points
                ForEach(curve.sortedPoints) { point in
                    let pos = pointPosition(point, in: plotArea)
                    Circle()
                        .fill(selectedPointId == point.id ? Color.blue : Color.white)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .position(pos)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    selectedPointId = point.id
                                    let newTemp = positionToTemp(value.location.x, in: plotArea)
                                    let newSpeed = positionToSpeed(value.location.y, in: plotArea)
                                    curve.updatePoint(
                                        id: point.id,
                                        temperature: max(20, min(105, newTemp)),
                                        fanSpeed: max(0, min(100, newSpeed))
                                    )
                                }
                                .onEnded { _ in
                                    // Save after drag ends
                                }
                        )
                        .onTapGesture {
                            selectedPointId = point.id
                        }
                }

                // Point tooltip
                if let selectedId = selectedPointId,
                   let point = curve.points.first(where: { $0.id == selectedId }) {
                    let pos = pointPosition(point, in: plotArea)
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f°C", point.temperature))
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text(String(format: "%.0f%%", point.fanSpeed))
                            .font(.caption2)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .position(x: pos.x, y: pos.y - 30)
                }
            }
        }
    }

    private func drawGrid(in rect: CGRect) -> some View {
        Canvas { context, _ in
            let dashStyle = StrokeStyle(lineWidth: 0.5, dash: [4, 4])

            // Horizontal grid lines
            for i in 0...gridLines {
                let y = rect.minY + rect.height * CGFloat(i) / CGFloat(gridLines)
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.3)), style: dashStyle)
            }

            // Vertical grid lines
            for i in 0...gridLines {
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(gridLines)
                var path = Path()
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(path, with: .color(.secondary.opacity(0.3)), style: dashStyle)
            }

            // Axes
            var xAxis = Path()
            xAxis.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            xAxis.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.stroke(xAxis, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

            var yAxis = Path()
            yAxis.move(to: CGPoint(x: rect.minX, y: rect.minY))
            yAxis.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.stroke(yAxis, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
        }
    }

    private func drawAxisLabels(in rect: CGRect) -> some View {
        ZStack {
            // Y-axis labels (Fan Speed %)
            ForEach(0...gridLines, id: \.self) { i in
                let value = 100.0 - (100.0 * Double(i) / Double(gridLines))
                let y = rect.minY + rect.height * CGFloat(i) / CGFloat(gridLines)
                Text(String(format: "%.0f%%", value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: rect.minX - 25, y: y)
            }

            // X-axis labels (Temperature °C)
            ForEach(0...gridLines, id: \.self) { i in
                let value = tempRange.lowerBound + (tempRange.upperBound - tempRange.lowerBound) * Double(i) / Double(gridLines)
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(gridLines)
                Text(String(format: "%.0f°", value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: x, y: rect.maxY + 15)
            }
        }
    }

    private func drawCurveLine(in rect: CGRect) -> some View {
        Path { path in
            let sorted = curve.sortedPoints
            guard !sorted.isEmpty else { return }

            let firstPos = pointPosition(sorted[0], in: rect)
            path.move(to: firstPos)

            for i in 1..<sorted.count {
                let pos = pointPosition(sorted[i], in: rect)
                path.addLine(to: pos)
            }
        }
        .stroke(Color.blue, lineWidth: 2.5)
    }

    private func drawFilledArea(in rect: CGRect) -> some View {
        Path { path in
            let sorted = curve.sortedPoints
            guard !sorted.isEmpty else { return }

            let firstPos = pointPosition(sorted[0], in: rect)
            path.move(to: CGPoint(x: firstPos.x, y: rect.maxY))
            path.addLine(to: firstPos)

            for i in 1..<sorted.count {
                let pos = pointPosition(sorted[i], in: rect)
                path.addLine(to: pos)
            }

            let lastPos = pointPosition(sorted.last!, in: rect)
            path.addLine(to: CGPoint(x: lastPos.x, y: rect.maxY))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func drawCurrentTempIndicator(in rect: CGRect) -> some View {
        let x = tempToX(currentTemp, in: rect)
        let speed = curve.speedForTemperature(currentTemp)
        let y = speedToY(speed, in: rect)

        return ZStack {
            // Vertical line
            Path { path in
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))

            // Current position dot
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
                .shadow(color: .orange.opacity(0.5), radius: 4)
                .position(x: x, y: y)

            // Label
            Text(String(format: "%.0f°C", currentTemp))
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
                .padding(4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .position(x: x, y: rect.maxY + 30)
        }
    }

    // MARK: - Coordinate Conversion

    private func pointPosition(_ point: CurvePoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: tempToX(point.temperature, in: rect),
            y: speedToY(point.fanSpeed, in: rect)
        )
    }

    private func tempToX(_ temp: Double, in rect: CGRect) -> CGFloat {
        let ratio = (temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
        return rect.minX + rect.width * CGFloat(ratio)
    }

    private func speedToY(_ speed: Double, in rect: CGRect) -> CGFloat {
        let ratio = (speed - speedRange.lowerBound) / (speedRange.upperBound - speedRange.lowerBound)
        return rect.maxY - rect.height * CGFloat(ratio)
    }

    private func positionToTemp(_ x: CGFloat, in rect: CGRect) -> Double {
        let ratio = Double((x - rect.minX) / rect.width)
        return tempRange.lowerBound + (tempRange.upperBound - tempRange.lowerBound) * ratio
    }

    private func positionToSpeed(_ y: CGFloat, in rect: CGRect) -> Double {
        let ratio = Double((rect.maxY - y) / rect.height)
        return speedRange.lowerBound + (speedRange.upperBound - speedRange.lowerBound) * ratio
    }
}

// MARK: - Curve Point Row

struct CurvePointRow: View {
    let point: CurvePoint
    let isSelected: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onUpdateTemp: (Double) -> Void
    let onUpdateSpeed: (Double) -> Void
    let onDelete: () -> Void

    @State private var tempText: String = ""
    @State private var speedText: String = ""

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "thermometer")
                    .foregroundStyle(.orange)
                    .font(.caption)
                TextField("Temp", text: $tempText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit {
                        if let val = Double(tempText) {
                            onUpdateTemp(max(20, min(105, val)))
                        }
                    }
                Text("°C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "fan.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { point.fanSpeed },
                        set: { onUpdateSpeed($0) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .frame(maxWidth: 150)
                Text(String(format: "%.0f%%", point.fanSpeed))
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.3)
            .frame(width: 30)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelect() }
        .onAppear {
            tempText = String(format: "%.0f", point.temperature)
            speedText = String(format: "%.0f", point.fanSpeed)
        }
        .onChange(of: point.temperature) { _, newVal in
            tempText = String(format: "%.0f", newVal)
        }
        .onChange(of: point.fanSpeed) { _, newVal in
            speedText = String(format: "%.0f", newVal)
        }
    }
}

// MARK: - Save Profile Sheet

struct SaveProfileSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Fan Curve as Profile")
                .font(.headline)

            TextField("Profile Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
    }
}
