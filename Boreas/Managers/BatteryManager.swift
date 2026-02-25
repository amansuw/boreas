import Foundation
import Combine
import IOKit
import IOKit.ps

class BatteryManager: ObservableObject {
    var battery = BatteryInfo()

    init() {
    }

    deinit {
    }

    // MARK: - Compute / Apply

    func computeBattery() -> BatteryInfo {
        readBattery()
    }

    func applyBattery(_ info: BatteryInfo) {
        battery = info
        objectWillChange.send()
    }

    // MARK: - Battery Reading via IOKit

    private func readBattery() -> BatteryInfo {
        var info = BatteryInfo()

        // Check IOPowerSources
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            info.hasBattery = false
            return info
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            info.hasBattery = true

            if let currentCap = desc[kIOPSCurrentCapacityKey] as? Int,
               let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                info.level = Double(currentCap) / Double(maxCap) * 100
            }

            if let isCharging = desc[kIOPSIsChargingKey] as? Bool {
                info.isCharging = isCharging
            }

            if let source = desc[kIOPSPowerSourceStateKey] as? String {
                info.isPluggedIn = source == kIOPSACPowerValue
                info.source = info.isPluggedIn ? "AC Power" : "Battery"
            }

            if let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int {
                info.timeRemaining = timeToFull
            } else if let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int {
                info.timeRemaining = timeToEmpty
            }
        }

        // Read detailed battery info from IORegistry (AppleSmartBattery)
        readSmartBatteryInfo(&info)

        return info
    }

    private func readSmartBatteryInfo(_ info: inout BatteryInfo) {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortCompat, matching, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        // Cycle count
        if let cycles = dict["CycleCount"] as? Int {
            info.cycleCount = cycles
        }

        // Design capacity (mAh)
        if let design = dict["DesignCapacity"] as? Int, design > 0 {
            info.designCapacity = design
        }

        // Max capacity (mAh) — try multiple keys for Apple Silicon compatibility
        if let rawMax = dict["AppleRawMaxCapacity"] as? Int, rawMax > 0 {
            info.maxCapacity = rawMax
        } else if let nominalCap = dict["NominalChargeCapacity"] as? Int, nominalCap > 0 {
            info.maxCapacity = nominalCap
        } else if let maxCap = dict["MaxCapacity"] as? Int, maxCap > 0 {
            info.maxCapacity = maxCap
        }

        // Current capacity (mAh)
        if let currentCap = dict["CurrentCapacity"] as? Int, currentCap > 0 {
            info.currentCapacity = currentCap
        }

        // Health % — only compute if both values are in mAh (> 100 rules out percentage values)
        if info.designCapacity > 100 && info.maxCapacity > 100 {
            info.healthPercent = Double(info.maxCapacity) / Double(info.designCapacity) * 100
        } else if info.designCapacity > 0 && info.maxCapacity > 0 {
            // Fallback: if maxCapacity looks like a percentage already
            if info.maxCapacity <= 100 && info.designCapacity <= 100 {
                info.healthPercent = Double(info.maxCapacity)
            } else {
                info.healthPercent = Double(info.maxCapacity) / Double(info.designCapacity) * 100
            }
        }

        // Temperature (in centi-degrees Celsius)
        if let temp = dict["Temperature"] as? Int {
            info.temperature = Double(temp) / 100.0
        }

        // Voltage (mV)
        if let voltage = dict["Voltage"] as? Int {
            info.voltage = Double(voltage) / 1000.0
        }

        // Instantaneous amperage (mA) — can be negative when discharging
        if let amperage = dict["InstantAmperage"] as? Int {
            let amps = Double(amperage) / 1000.0
            info.power = abs(amps * info.voltage)
        }

        // Adapter info
        if let adapterInfo = dict["AdapterDetails"] as? [String: Any] {
            if let watts = adapterInfo["Watts"] as? Int {
                info.adapterWatts = watts
            }
            if let current = adapterInfo["Current"] as? Int {
                info.adapterCurrent = current
            }
            if let voltage = adapterInfo["Voltage"] as? Int {
                info.adapterVoltage = voltage
            }
        }

        if let isCharging = dict["IsCharging"] as? Bool {
            info.isCharging = isCharging
        }
    }
}

private let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0
    }
}()
