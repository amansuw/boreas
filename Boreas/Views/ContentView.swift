import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case cpu = "CPU"
    case gpu = "GPU"
    case ram = "Memory"
    case disk = "Disk"
    case network = "Network"
    case battery = "Battery"
    case fanControl = "Fan Control"
    case fanCurve = "Fan Curve"
    case sensors = "Sensors"
    case profiles = "Profiles"
    case debug = "Debug"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d.top.filled"
        case .ram: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100percent"
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
    @EnvironmentObject var cpuManager: CPUManager
    @EnvironmentObject var ramManager: RAMManager
    @EnvironmentObject var gpuManager: GPUManager
    @EnvironmentObject var batteryManager: BatteryManager
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var diskManager: DiskManager

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
                case .cpu:
                    CPUView()
                case .gpu:
                    GPUView()
                case .ram:
                    RAMView()
                case .disk:
                    DiskView()
                case .network:
                    NetworkView()
                case .battery:
                    BatteryView()
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
