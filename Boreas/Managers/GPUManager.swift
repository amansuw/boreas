import Foundation
import Combine
import IOKit

class GPUManager: ObservableObject {
    @Published var usage = GPUUsage()
    @Published var topProcesses: [TopProcess] = []
    @Published var usageHistory: [GPUSnapshot] = []

    private var timer: Timer?
    private let readQueue = DispatchQueue(label: "com.boreas.gpu-read", qos: .utility)
    private let maxHistoryPoints = 86400

    struct GPUSnapshot: Identifiable {
        let id = UUID()
        let timestamp: Date
        let utilization: Double
    }

    init() {
        detectGPUModel()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - GPU Model Detection

    private func detectGPUModel() {
        // Try IORegistry for GPU name
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortCompat, matching, &iterator) == KERN_SUCCESS else {
            fallbackModelName()
            return
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                // Try IOClass or model key
                if let name = dict["CFBundleIdentifier"] as? String {
                    // Extract meaningful name
                    if name.contains("AGX") {
                        // Apple Silicon GPU — get chip name from sysctl
                        fallbackModelName()
                        IOObjectRelease(entry)
                        return
                    }
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        fallbackModelName()
    }

    private func fallbackModelName() {
        var brandStr = [CChar](repeating: 0, count: 256)
        var size = brandStr.count
        if sysctlbyname("machdep.cpu.brand_string", &brandStr, &size, nil, 0) == 0 {
            let brand = String(cString: brandStr)
            // Extract chip name (e.g. "Apple M3 Pro")
            if brand.contains("Apple") {
                usage.modelName = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }

        // Try hw.model
        var model = [CChar](repeating: 0, count: 256)
        size = model.count
        if sysctlbyname("hw.model", &model, &size, nil, 0) == 0 {
            usage.modelName = String(cString: model)
            return
        }

        usage.modelName = "GPU"
    }

    // MARK: - Monitoring

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer!, forMode: .common)
        update()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - GPU Utilization via IOKit

    private func update() {
        readQueue.async { [weak self] in
            guard let self = self else { return }
            let stats = self.readGPUStats()
            let snapshot = GPUSnapshot(
                timestamp: Date(),
                utilization: stats.utilization
            )
            DispatchQueue.main.async {
                self.usage.utilization = stats.utilization
                self.usage.renderUtilization = stats.renderUtilization
                self.usage.tilerUtilization = stats.tilerUtilization
                self.usageHistory.append(snapshot)
                if self.usageHistory.count > self.maxHistoryPoints {
                    self.usageHistory.removeFirst(self.usageHistory.count - self.maxHistoryPoints)
                }
            }
        }
    }

    private func readGPUStats() -> (utilization: Double, renderUtilization: Double, tilerUtilization: Double) {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortCompat, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Look for PerformanceStatistics
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                let deviceUtil = perfStats["Device Utilization %"] as? Int
                    ?? perfStats["GPU Activity(%)"] as? Int
                    ?? 0
                let renderUtil = perfStats["Renderer Utilization %"] as? Int ?? 0
                let tilerUtil = perfStats["Tiler Utilization %"] as? Int ?? 0

                return (Double(deviceUtil), Double(renderUtil), Double(tilerUtil))
            }
        }

        return (0, 0, 0)
    }
}

// Compatibility shim for IOKit main port
private let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0 // kIOMasterPortDefault
    }
}()
