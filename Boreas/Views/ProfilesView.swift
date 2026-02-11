import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateSheet = false
    @State private var newProfileName = ""
    @State private var newProfileMode: FanProfile.ProfileMode = .curve
    @State private var newProfileSpeed: Double = 50

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profiles")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Manage fan control presets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                // Built-in Profiles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Built-in Presets")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        ForEach(profileManager.profiles.filter(\.isBuiltIn)) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: profileManager.activeProfile?.id == profile.id,
                                onActivate: { activateProfile(profile) },
                                onDelete: nil
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Custom Profiles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Profiles")
                        .font(.headline)
                        .padding(.horizontal)

                    let customProfiles = profileManager.profiles.filter { !$0.isBuiltIn }

                    if customProfiles.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary)
                                Text("No custom profiles")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Create a profile from the Fan Curve editor or click New Profile")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 12) {
                            ForEach(customProfiles) { profile in
                                ProfileCard(
                                    profile: profile,
                                    isActive: profileManager.activeProfile?.id == profile.id,
                                    onActivate: { activateProfile(profile) },
                                    onDelete: { profileManager.deleteProfile(profile) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Active Profile Info
                if let active = profileManager.activeProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Active Profile: \(active.name)")
                                .font(.headline)
                        }

                        switch active.mode {
                        case .automatic:
                            Text("macOS is managing fan speeds automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .manual:
                            if let speed = active.manualSpeedPercentage {
                                Text(String(format: "Fans set to %.0f%% speed.", speed))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .curve:
                            if let curve = active.curve {
                                Text("Fan speed follows a custom curve with \(curve.points.count) control points.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                // Mini curve preview
                                MiniCurvePreview(curve: curve)
                                    .frame(height: 80)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showCreateSheet) {
            CreateProfileSheet(
                name: $newProfileName,
                mode: $newProfileMode,
                speed: $newProfileSpeed
            ) {
                createProfile()
            }
        }
    }

    private func activateProfile(_ profile: FanProfile) {
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

    private func createProfile() {
        var profile = FanProfile(
            name: newProfileName,
            mode: newProfileMode,
            isBuiltIn: false
        )

        switch newProfileMode {
        case .manual:
            profile.manualSpeedPercentage = newProfileSpeed
        case .curve:
            profile.curve = profileManager.customCurve
        case .automatic:
            break
        }

        profileManager.addProfile(profile)
        newProfileName = ""
        showCreateSheet = false
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: FanProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: profileIcon)
                    .font(.title2)
                    .foregroundStyle(profileColor)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let onDelete = onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                Text(profileDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if profile.mode == .curve, let curve = profile.curve {
                MiniCurvePreview(curve: curve)
                    .frame(height: 40)
            }

            Button(isActive ? "Active" : "Activate") {
                onActivate()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isActive)
            .tint(isActive ? .green : .blue)
        }
        .padding()
        .background(
            isActive ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }

    private var profileIcon: String {
        switch profile.name {
        case "Default": return "gearshape.fill"
        case "Silent": return "speaker.slash.fill"
        case "Balanced": return "scale.3d"
        case "Performance": return "bolt.fill"
        case "Max": return "flame.fill"
        default: return "slider.horizontal.3"
        }
    }

    private var profileColor: Color {
        switch profile.name {
        case "Default": return .green
        case "Silent": return .blue
        case "Balanced": return .yellow
        case "Performance": return .orange
        case "Max": return .red
        default: return .purple
        }
    }

    private var profileDescription: String {
        switch profile.mode {
        case .automatic:
            return "macOS automatic fan management"
        case .manual:
            if let speed = profile.manualSpeedPercentage {
                return String(format: "Fixed speed at %.0f%%", speed)
            }
            return "Manual speed control"
        case .curve:
            return "Custom temperature-based curve"
        }
    }
}

// MARK: - Mini Curve Preview

struct MiniCurvePreview: View {
    let curve: FanCurve

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let sorted = curve.sortedPoints
                guard !sorted.isEmpty else { return }

                let width = geometry.size.width
                let height = geometry.size.height

                let firstX = CGFloat((sorted[0].temperature - 20) / 85) * width
                let firstY = height - CGFloat(sorted[0].fanSpeed / 100) * height

                path.move(to: CGPoint(x: firstX, y: firstY))

                for point in sorted.dropFirst() {
                    let x = CGFloat((point.temperature - 20) / 85) * width
                    let y = height - CGFloat(point.fanSpeed / 100) * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.blue, lineWidth: 1.5)
        }
    }
}

// MARK: - Create Profile Sheet

struct CreateProfileSheet: View {
    @Binding var name: String
    @Binding var mode: FanProfile.ProfileMode
    @Binding var speed: Double
    let onCreate: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Profile")
                .font(.headline)

            Form {
                TextField("Profile Name", text: $name)

                Picker("Mode", selection: $mode) {
                    Text("Automatic").tag(FanProfile.ProfileMode.automatic)
                    Text("Manual").tag(FanProfile.ProfileMode.manual)
                    Text("Fan Curve").tag(FanProfile.ProfileMode.curve)
                }

                if mode == .manual {
                    HStack {
                        Text("Fan Speed")
                        Slider(value: $speed, in: 0...100, step: 5)
                        Text(String(format: "%.0f%%", speed))
                            .frame(width: 40)
                    }
                }

                if mode == .curve {
                    Text("This will use the current fan curve from the editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 350, height: 200)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
    }
}
