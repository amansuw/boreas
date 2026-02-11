import Foundation
import Combine

class ProfileManager: ObservableObject {
    @Published var profiles: [FanProfile] = []
    @Published var activeProfile: FanProfile?
    @Published var customCurve: FanCurve = FanCurve()

    var latestCustomProfile: FanProfile? {
        profiles.filter { !$0.isBuiltIn }.last
    }

    private let saveKey = "boreas_profiles"
    private let activeProfileKey = "boreas_active_profile"

    init() {
        loadProfiles()
    }

    func loadProfiles() {
        var allProfiles = FanProfile.builtInProfiles

        if let data = UserDefaults.standard.data(forKey: saveKey),
           let customProfiles = try? JSONDecoder().decode([FanProfile].self, from: data) {
            allProfiles.append(contentsOf: customProfiles)
        }

        profiles = allProfiles

        if let activeId = UserDefaults.standard.string(forKey: activeProfileKey),
           let uuid = UUID(uuidString: activeId),
           let profile = profiles.first(where: { $0.id == uuid }) {
            activeProfile = profile
        } else {
            activeProfile = profiles.first(where: { $0.name == "Default" })
        }

        if let data = UserDefaults.standard.data(forKey: "boreas_custom_curve"),
           let curve = try? JSONDecoder().decode(FanCurve.self, from: data) {
            customCurve = curve
        }
    }

    func saveCustomProfiles() {
        let customProfiles = profiles.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    func saveCustomCurve() {
        if let data = try? JSONEncoder().encode(customCurve) {
            UserDefaults.standard.set(data, forKey: "boreas_custom_curve")
        }
    }

    func setActiveProfile(_ profile: FanProfile) {
        activeProfile = profile
        UserDefaults.standard.set(profile.id.uuidString, forKey: activeProfileKey)
    }

    func addProfile(_ profile: FanProfile) {
        profiles.append(profile)
        saveCustomProfiles()
    }

    func deleteProfile(_ profile: FanProfile) {
        guard !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first(where: { $0.name == "Default" })
        }
        saveCustomProfiles()
    }

    func updateProfile(_ profile: FanProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if activeProfile?.id == profile.id {
                activeProfile = profile
            }
            saveCustomProfiles()
        }
    }

    func createProfileFromCurrentCurve(name: String) -> FanProfile {
        let profile = FanProfile(
            name: name,
            mode: .curve,
            curve: customCurve,
            isBuiltIn: false
        )
        addProfile(profile)
        return profile
    }
}
