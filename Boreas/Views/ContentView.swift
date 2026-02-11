import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case fanControl = "Fan Control"
    case fanCurve = "Fan Curve"
    case sensors = "Sensors"
    case profiles = "Profiles"
    case debug = "Debug"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .fanControl: return "fan.fill"
        case .fanCurve: return "chart.xyaxis.line"
        case .sensors: return "thermometer"
        case .profiles: return "list.bullet.rectangle"
        case .debug: return "ladybug"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem = .dashboard
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var fanManager: FanManager
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(SidebarItem.allCases) { item in
                    Button(action: { selectedItem = item }) {
                        Label(item.rawValue, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedItem {
                case .dashboard:
                    DashboardView()
                case .fanControl:
                    FanControlView()
                case .fanCurve:
                    FanCurveView()
                case .sensors:
                    SensorListView()
                case .profiles:
                    ProfilesView()
                case .debug:
                    DebugView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !fanManager.hasWriteAccess && !fanManager.isRequestingAccess {
                fanManager.requestAdminAccess()
            }
        }
    }
}
