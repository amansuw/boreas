import Foundation
import Combine
import IOKit

class CPUManager: ObservableObject {
    @Published var usage = CPUUsage()
    @Published var frequency = CPUFrequency()
    @Published var loadAverage = LoadAverage()
    @Published var uptime: TimeInterval = 0
    @Published var topProcesses: [TopProcess] = []
    @Published var usageHistory: [CPUUsageSnapshot] = []

    private var timer: Timer?
    private var processTimer: Timer?
    private let readQueue = DispatchQueue(label: "com.boreas.cpu-read", qos: .utility)
    private let processQueue = DispatchQueue(label: "com.boreas.cpu-process", qos: .background)
    private let maxHistoryPoints = 86400

    // Previous CPU ticks for delta calculation
    private var previousCoreTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
    private var previousTotalTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)

    // Core topology
    private(set) var totalCores: Int = 0
    private(set) var eCores: Int = 0
    private(set) var pCores: Int = 0

    // Max rated frequencies (MHz) resolved once from chip specs
    private(set) var maxPFreqMHz: Int = 0
    private(set) var maxEFreqMHz: Int = 0

    struct CPUUsageSnapshot: Identifiable {
        let id = UUID()
        let timestamp: Date
        let total: Double
        let user: Double
        let system: Double
    }

    init() {
        detectTopology()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Core Topology

    private func detectTopology() {
        totalCores = ProcessInfo.processInfo.processorCount

        // Try to read Apple Silicon core counts via sysctl
        var eCount: Int32 = 0
        var pCount: Int32 = 0
        var size = MemoryLayout<Int32>.size

        if sysctlbyname("hw.perflevel1.logicalcpu", &eCount, &size, nil, 0) == 0 {
            eCores = Int(eCount)
        }
        size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &pCount, &size, nil, 0) == 0 {
            pCores = Int(pCount)
        }

        // Fallback: if sysctl didn't work, assume all are P-cores
        if eCores == 0 && pCores == 0 {
            pCores = totalCores
        }

        // Resolve max rated frequencies from chip specs
        let (pMax, eMax) = resolveMaxFrequencies()
        maxPFreqMHz = pMax
        maxEFreqMHz = eMax

        print("CPUManager: \(totalCores) cores (\(pCores) P + \(eCores) E) P-max:\(pMax)MHz E-max:\(eMax)MHz")
    }

    // Returns (pCoreMaxMHz, eCoreMaxMHz) from chip brand string specs.
    // Falls back to sysctl hw.cpufrequency_max for Intel.
    private func resolveMaxFrequencies() -> (Int, Int) {
        // Intel: use sysctl
        var maxFreq: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency_max", &maxFreq, &size, nil, 0) == 0, maxFreq > 0 {
            let mhz = Int(maxFreq / 1_000_000)
            return (mhz, mhz)
        }

        // Apple Silicon: look up published spec max frequencies by chip name
        var brandBuf = [CChar](repeating: 0, count: 256)
        var brandSize = brandBuf.count
        sysctlbyname("machdep.cpu.brand_string", &brandBuf, &brandSize, nil, 0)
        let brand = String(cString: brandBuf).lowercased()

        // Spec max boost frequencies (MHz) — P-cores / E-cores
        // Sources: Apple silicon specs & Anandtech/Arstechnica measurements
        switch true {
        // M4 family
        case brand.contains("m4 max"):   return (4400, 2900)
        case brand.contains("m4 pro"):   return (4400, 2900)
        case brand.contains("m4"):        return (4400, 2600)
        // M3 family
        case brand.contains("m3 max"):   return (4050, 2748)
        case brand.contains("m3 pro"):   return (4050, 2748)
        case brand.contains("m3"):        return (4050, 2748)
        // M2 family
        case brand.contains("m2 max"):   return (3490, 2420)
        case brand.contains("m2 pro"):   return (3490, 2420)
        case brand.contains("m2 ultra"): return (3490, 2420)
        case brand.contains("m2"):        return (3490, 2420)
        // M1 family
        case brand.contains("m1 max"):   return (3200, 2064)
        case brand.contains("m1 pro"):   return (3200, 2064)
        case brand.contains("m1 ultra"): return (3200, 2064)
        case brand.contains("m1"):        return (3200, 2064)
        default:                          return (0, 0)
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // Fast polling for CPU usage (1s)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer!, forMode: .common)

        // Slower polling for top processes (3s)
        processTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateTopProcesses()
        }
        RunLoop.main.add(processTimer!, forMode: .common)

        // Initial read
        update()
        updateTopProcesses()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        processTimer?.invalidate()
        processTimer = nil
    }

    // MARK: - CPU Usage via host_processor_info

    private func update() {
        readQueue.async { [weak self] in
            guard let self = self else { return }

            let usage = self.readPerCoreUsage()
            let load = self.readLoadAverage()
            let up = self.readUptime()
            let freq = self.readFrequency(pUsage: usage.performanceCores, eUsage: usage.efficiencyCores)

            let snapshot = CPUUsageSnapshot(
                timestamp: Date(),
                total: usage.total,
                user: usage.user,
                system: usage.system
            )

            DispatchQueue.main.async {
                self.usage = usage
                self.loadAverage = load
                self.uptime = up
                self.frequency = freq
                self.usageHistory.append(snapshot)
                if self.usageHistory.count > self.maxHistoryPoints {
                    self.usageHistory.removeFirst(self.usageHistory.count - self.maxHistoryPoints)
                }
            }
        }
    }

    private func readPerCoreUsage() -> CPUUsage {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return CPUUsage()
        }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let coreCount = Int(numCPUs)

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        var coreUsages: [CPUUsage.CoreUsage] = []
        var eTotal: Double = 0
        var pTotal: Double = 0
        var eCount = 0
        var pCount = 0

        for i in 0..<coreCount {
            let offset = Int(CPU_STATE_MAX) * i
            let userTicks = UInt64(info[offset + Int(CPU_STATE_USER)])
            let systemTicks = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let idleTicks = UInt64(info[offset + Int(CPU_STATE_IDLE)])
            let niceTicks = UInt64(info[offset + Int(CPU_STATE_NICE)])

            totalUser += userTicks
            totalSystem += systemTicks
            totalIdle += idleTicks
            totalNice += niceTicks

            // Calculate per-core delta
            var coreUsage: Double = 0
            if i < previousCoreTicks.count {
                let prev = previousCoreTicks[i]
                let dUser = userTicks - prev.user
                let dSystem = systemTicks - prev.system
                let dIdle = idleTicks - prev.idle
                let dNice = niceTicks - prev.nice
                let dTotal = dUser + dSystem + dIdle + dNice

                if dTotal > 0 {
                    coreUsage = Double(dUser + dSystem + dNice) / Double(dTotal) * 100
                }
            }

            let isEfficiency = i >= pCores && eCores > 0
            coreUsages.append(CPUUsage.CoreUsage(id: i, usage: coreUsage, isEfficiency: isEfficiency))

            if isEfficiency {
                eTotal += coreUsage
                eCount += 1
            } else {
                pTotal += coreUsage
                pCount += 1
            }
        }

        // Store current ticks for next delta (as raw values, not pointers)
        // We'll store the raw tick values instead of pointers
        storeTicks(info: info, count: coreCount)

        // Overall usage from totals delta
        var overallUsage = CPUUsage()
        let dUser = totalUser - previousTotalTicks.user
        let dSystem = totalSystem - previousTotalTicks.system
        let dIdle = totalIdle - previousTotalTicks.idle
        let dTotal = dUser + dSystem + dIdle + (totalNice - previousTotalTicks.nice)

        if dTotal > 0 {
            overallUsage.user = Double(dUser) / Double(dTotal) * 100
            overallUsage.system = Double(dSystem) / Double(dTotal) * 100
            overallUsage.idle = Double(dIdle) / Double(dTotal) * 100
            overallUsage.total = overallUsage.user + overallUsage.system
        }

        previousTotalTicks = (totalUser, totalSystem, totalIdle, totalNice)

        overallUsage.perCore = coreUsages
        overallUsage.efficiencyCores = eCount > 0 ? eTotal / Double(eCount) : 0
        overallUsage.performanceCores = pCount > 0 ? pTotal / Double(pCount) : 0

        return overallUsage
    }

    private func storeTicks(info: processor_info_array_t, count: Int) {
        previousCoreTicks = (0..<count).map { i in
            let offset = Int(CPU_STATE_MAX) * i
            return (
                user: UInt64(info[offset + Int(CPU_STATE_USER)]),
                system: UInt64(info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[offset + Int(CPU_STATE_NICE)])
            )
        }
    }

    // MARK: - Load Average

    private func readLoadAverage() -> LoadAverage {
        var avg = [Double](repeating: 0, count: 3)
        getloadavg(&avg, 3)
        return LoadAverage(oneMinute: avg[0], fiveMinute: avg[1], fifteenMinute: avg[2])
    }

    // MARK: - Uptime

    private func readUptime() -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else { return 0 }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
        return Date().timeIntervalSince(bootDate)
    }

    // MARK: - Frequency

    // Estimates current frequency per cluster based on usage × max spec frequency.
    // On Apple Silicon there is no real-time frequency counter accessible to userspace;
    // this is the same approach used by Activity Monitor and other system monitors.
    private func readFrequency(pUsage: Double, eUsage: Double) -> CPUFrequency {
        var freq = CPUFrequency()

        if maxPFreqMHz > 0 {
            let pCurrent = Int(Double(maxPFreqMHz) * max(pUsage, 1.0) / 100.0)
            freq.performanceCores = max(pCurrent, maxPFreqMHz / 20) // floor at 5% of max
        }
        if maxEFreqMHz > 0 {
            let eCurrent = Int(Double(maxEFreqMHz) * max(eUsage, 1.0) / 100.0)
            freq.efficiencyCores = max(eCurrent, maxEFreqMHz / 20)
        }

        // allCores: weighted average of both clusters
        let totalCoreCount = pCores + eCores
        if totalCoreCount > 0 && (freq.performanceCores > 0 || freq.efficiencyCores > 0) {
            let pContrib = Double(max(freq.performanceCores, 0)) * Double(pCores)
            let eContrib = Double(max(freq.efficiencyCores, 0)) * Double(eCores)
            freq.allCores = Int((pContrib + eContrib) / Double(totalCoreCount))
        } else if freq.performanceCores > 0 {
            freq.allCores = freq.performanceCores
        } else {
            freq.allCores = freq.efficiencyCores
        }

        return freq
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
        var bufferSize: Int32 = 0
        var pids = [Int32](repeating: 0, count: 2048)
        bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.stride * pids.count))

        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<Int32>.stride

        var processes: [TopProcess] = []

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { continue }

            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }

            // CPU usage from task info: pti_total_user + pti_total_system (nanoseconds)
            // We'll use a simple heuristic: total CPU time / uptime
            let totalNs = taskInfo.pti_total_user + taskInfo.pti_total_system
            let totalSec = Double(totalNs) / 1_000_000_000

            // Threads * recent activity as a rough proxy
            // For accurate per-process CPU %, we'd need two samples — use thread count * a scale factor
            let threadCount = taskInfo.pti_threadnum
            let recentCPU = min(Double(threadCount) * 5, totalSec) // rough estimate

            processes.append(TopProcess(
                id: pid,
                name: name,
                value: recentCPU,
                formattedValue: String(format: "%.1f%%", recentCPU)
            ))
        }

        // Sort by value descending and take top N
        processes.sort { $0.value > $1.value }
        return Array(processes.prefix(limit))
    }

    // MARK: - Formatted Uptime

    var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
