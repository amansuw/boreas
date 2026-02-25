import Foundation
import Combine

class RAMManager: ObservableObject {
    @Published var memory = MemoryBreakdown()
    @Published var topProcesses: [TopProcess] = []
    @Published var usageHistory: [RAMSnapshot] = []

    private var timer: Timer?
    private var processTimer: Timer?
    private let readQueue = DispatchQueue(label: "com.boreas.ram-read", qos: .utility)
    private let processQueue = DispatchQueue(label: "com.boreas.ram-process", qos: .background)
    private let maxHistoryPoints = 120

    struct RAMSnapshot: Identifiable {
        let id = UUID()
        let timestamp: Date
        let usagePercent: Double
        let pressure: Int
    }

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer!, forMode: .common)

        processTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateTopProcesses()
        }
        RunLoop.main.add(processTimer!, forMode: .common)

        update()
        updateTopProcesses()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        processTimer?.invalidate()
        processTimer = nil
    }

    // MARK: - Memory Stats

    private func update() {
        readQueue.async { [weak self] in
            guard let self = self else { return }
            let mem = self.readMemory()
            let snapshot = RAMSnapshot(
                timestamp: Date(),
                usagePercent: mem.usagePercent,
                pressure: mem.pressureLevel
            )
            DispatchQueue.main.async {
                self.memory = mem
                self.usageHistory.append(snapshot)
                if self.usageHistory.count > self.maxHistoryPoints {
                    self.usageHistory.removeFirst(self.usageHistory.count - self.maxHistoryPoints)
                }
            }
        }
    }

    private func readMemory() -> MemoryBreakdown {
        var mem = MemoryBreakdown()

        // Total physical memory
        mem.total = ProcessInfo.processInfo.physicalMemory

        // VM statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return mem }

        let pageSize = UInt64(vm_kernel_page_size)

        mem.free = UInt64(vmStats.free_count) * pageSize
        mem.wired = UInt64(vmStats.wire_count) * pageSize
        mem.compressed = UInt64(vmStats.compressor_page_count) * pageSize

        // App memory = internal - purgeable
        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        mem.app = (internalPages - purgeablePages) * pageSize

        mem.used = mem.total - mem.free

        // Swap
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            mem.swap = UInt64(swapUsage.xsu_used)
        }

        // Memory pressure level
        // 1 = normal, 2 = warning, 4 = critical
        // We approximate from free memory ratio
        let freeRatio = Double(mem.free) / Double(mem.total)
        if freeRatio > 0.15 {
            mem.pressureLevel = 1
        } else if freeRatio > 0.05 {
            mem.pressureLevel = 2
        } else {
            mem.pressureLevel = 4
        }

        return mem
    }

    // MARK: - Top Processes

    private func updateTopProcesses() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            let procs = self.readTopProcesses(limit: 8)
            DispatchQueue.main.async {
                self.topProcesses = procs
            }
        }
    }

    private func readTopProcesses(limit: Int) -> [TopProcess] {
        var pids = [Int32](repeating: 0, count: 2048)
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.stride * pids.count))
        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<Int32>.stride

        var processes: [TopProcess] = []

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { continue }

            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }

            let residentBytes = UInt64(taskInfo.pti_resident_size)
            guard residentBytes > 1_048_576 else { continue } // Skip < 1MB

            processes.append(TopProcess(
                id: pid,
                name: name,
                value: Double(residentBytes),
                formattedValue: ByteFormatter.format(residentBytes)
            ))
        }

        processes.sort { $0.value > $1.value }
        return Array(processes.prefix(limit))
    }
}
