import Foundation
import Combine
import Dispatch

class RAMManager: ObservableObject {
    var memory = MemoryBreakdown()
    var topProcesses: [TopProcess] = []
    var usageHistory: [RAMSnapshot] = []

    private let maxHistoryPoints = 120

    // Pre-allocated buffers — reused every poll to avoid heap churn
    private var pidBuffer = [Int32](repeating: 0, count: 2048)
    private var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

    // Kernel memory pressure tracking
    private var pressureSource: DispatchSourceMemoryPressure?
    private var currentPressureLevel: Int = 1 // 1=normal, 2=warning, 4=critical

    struct RAMSnapshot: Identifiable {
        private static var counter: Int = 0
        let id: Int
        let timestamp: Date
        let usagePercent: Double
        let pressure: Int

        init(timestamp: Date, usagePercent: Double, pressure: Int) {
            RAMSnapshot.counter += 1
            self.id = RAMSnapshot.counter
            self.timestamp = timestamp
            self.usagePercent = usagePercent
            self.pressure = pressure
        }
    }

    init() {
        setupMemoryPressureMonitoring()
    }

    deinit {
        pressureSource?.cancel()
        pressureSource = nil
    }
    
    // MARK: - Memory Pressure Monitoring (Kernel API)
    
    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            
            if event.contains(.critical) {
                self.currentPressureLevel = 4
            } else if event.contains(.warning) {
                self.currentPressureLevel = 2
            } else {
                self.currentPressureLevel = 1
            }
        }
        
        source.resume()
        pressureSource = source
    }

    // MARK: - Compute / Apply

    struct FastResult {
        let memory: MemoryBreakdown
        let snapshot: RAMSnapshot
    }

    func computeMemory() -> FastResult {
        let mem = readMemory()
        let snapshot = RAMSnapshot(timestamp: Date(), usagePercent: mem.usagePercent, pressure: mem.pressureLevel)
        return FastResult(memory: mem, snapshot: snapshot)
    }

    func applyMemory(_ r: FastResult) {
        memory = r.memory
        usageHistory.append(r.snapshot)
        if usageHistory.count > maxHistoryPoints {
            usageHistory.removeSubrange(0..<(usageHistory.count - maxHistoryPoints))
        }
        objectWillChange.send()
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

        // CORRECT memory calculation for macOS:
        // Used = App + Wired + Compressed (actual memory in use)
        // NOT total - free (which incorrectly includes file cache as "used")
        mem.used = mem.app + mem.wired + mem.compressed

        // Swap
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            mem.swap = UInt64(swapUsage.xsu_used)
        }

        // Use kernel memory pressure level from dispatch source (accurate)
        // instead of free ratio heuristic (always shows critical on macOS)
        mem.pressureLevel = currentPressureLevel

        return mem
    }

    func computeProcesses() -> [TopProcess] {
        readTopProcesses(limit: 8)
    }

    func applyProcesses(_ procs: [TopProcess]) {
        topProcesses = procs
        objectWillChange.send()
    }

    private func readTopProcesses(limit: Int) -> [TopProcess] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pidBuffer, Int32(MemoryLayout<Int32>.stride * pidBuffer.count))
        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<Int32>.stride

        var processes: [TopProcess] = []
        processes.reserveCapacity(min(count, 64))

        for i in 0..<count {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { continue }

            nameBuffer[0] = 0
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
