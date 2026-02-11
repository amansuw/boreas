import Foundation

struct FanProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var mode: ProfileMode
    var manualSpeedPercentage: Double?
    var curve: FanCurve?
    var isBuiltIn: Bool

    enum ProfileMode: String, Codable {
        case automatic
        case manual
        case curve
    }

    init(id: UUID = UUID(), name: String, mode: ProfileMode, manualSpeedPercentage: Double? = nil, curve: FanCurve? = nil, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.mode = mode
        self.manualSpeedPercentage = manualSpeedPercentage
        self.curve = curve
        self.isBuiltIn = isBuiltIn
    }

    static var builtInProfiles: [FanProfile] {
        [
            FanProfile(
                name: "Silent",
                mode: .curve,
                curve: FanCurve(name: "Silent", points: [
                    CurvePoint(temperature: 30, fanSpeed: 0),
                    CurvePoint(temperature: 50, fanSpeed: 0),
                    CurvePoint(temperature: 65, fanSpeed: 20),
                    CurvePoint(temperature: 75, fanSpeed: 40),
                    CurvePoint(temperature: 85, fanSpeed: 60),
                    CurvePoint(temperature: 95, fanSpeed: 80),
                    CurvePoint(temperature: 100, fanSpeed: 100),
                ]),
                isBuiltIn: true
            ),
            FanProfile(
                name: "Default",
                mode: .automatic,
                isBuiltIn: true
            ),
            FanProfile(
                name: "Balanced",
                mode: .curve,
                curve: FanCurve(name: "Balanced", points: [
                    CurvePoint(temperature: 30, fanSpeed: 10),
                    CurvePoint(temperature: 45, fanSpeed: 20),
                    CurvePoint(temperature: 55, fanSpeed: 35),
                    CurvePoint(temperature: 65, fanSpeed: 55),
                    CurvePoint(temperature: 75, fanSpeed: 75),
                    CurvePoint(temperature: 85, fanSpeed: 90),
                    CurvePoint(temperature: 95, fanSpeed: 100),
                ]),
                isBuiltIn: true
            ),
            FanProfile(
                name: "Performance",
                mode: .curve,
                curve: FanCurve(name: "Performance", points: [
                    CurvePoint(temperature: 30, fanSpeed: 25),
                    CurvePoint(temperature: 40, fanSpeed: 35),
                    CurvePoint(temperature: 50, fanSpeed: 50),
                    CurvePoint(temperature: 60, fanSpeed: 70),
                    CurvePoint(temperature: 70, fanSpeed: 85),
                    CurvePoint(temperature: 80, fanSpeed: 95),
                    CurvePoint(temperature: 90, fanSpeed: 100),
                ]),
                isBuiltIn: true
            ),
            FanProfile(
                name: "Max",
                mode: .manual,
                manualSpeedPercentage: 100,
                isBuiltIn: true
            ),
        ]
    }
}
