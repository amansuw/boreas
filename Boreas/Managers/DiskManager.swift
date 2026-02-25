import Foundation
import Combine
import IOKit

class DiskManager: ObservableObject {
    var disks: [DiskInfo] = []
    var io = DiskIO()
    var topProcesses: [TopProcess] = []

    // Pre-allocated buffers — reused every poll to avoid heap churn
    private var pidBuffer = [Int32](repeating: 0, count: 2048)
    private var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

    // Previous I/O counters for delta
    private var prevReadBytes: UInt64 = 0
    private var prevWriteBytes: UInt64 = 0
    private var prevTimestamp: Date?

    init() {
    }

    deinit {
    }

    // MARK: - Compute / Apply

    func computeIO() -> DiskIO {
        readDiskIO()
    }

    func applyIO(_ io: DiskIO) {
        self.io = io
        objectWillChange.send()
    }

    func computeSpace() -> [DiskInfo] {
        readDiskSpace()
    }

    func applySpace(_ infos: [DiskInfo]) {
        self.disks = infos
        objectWillChange.send()
    }

    private func readDiskSpace() -> [DiskInfo] {
        var result: [DiskInfo] = []

        let fm = FileManager.default
        guard let mountedVolumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
        ], options: [.skipHiddenVolumes]) else {
            return result
        }

        for url in mountedVolumes {
            guard let values = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeIsInternalKey,
            ]) else { continue }

            let name = values.volumeName ?? url.lastPathComponent
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)

            guard total > 0 else { continue }

            result.append(DiskInfo(
                id: url.path,
                name: name,
                totalBytes: total,
                freeBytes: free
            ))
        }

        return result
    }

    // MARK: - Disk I/O via IOKit

    private func readDiskIO() -> DiskIO {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortCompat, matching, &iterator) == KERN_SUCCESS else {
            return DiskIO()
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
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else {
                continue
            }

            if let readBytes = stats["Bytes (Read)"] as? UInt64 {
                totalRead += readBytes
            }
            if let writeBytes = stats["Bytes (Write)"] as? UInt64 {
                totalWrite += writeBytes
            }
        }

        // Calculate delta
        let now = Date()
        var readPerSec: UInt64 = 0
        var writePerSec: UInt64 = 0

        if let prevTime = prevTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 && totalRead >= prevReadBytes && totalWrite >= prevWriteBytes {
                readPerSec = UInt64(Double(totalRead - prevReadBytes) / elapsed)
                writePerSec = UInt64(Double(totalWrite - prevWriteBytes) / elapsed)
            }
        }

        prevReadBytes = totalRead
        prevWriteBytes = totalWrite
        prevTimestamp = now

        return DiskIO(readBytesPerSec: readPerSec, writeBytesPerSec: writePerSec)
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

            // Disk I/O from rusage
            var rusage = rusage_info_v4()
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
                }
            }

            guard rusageResult == 0 else { continue }
            let diskIO = rusage.ri_diskio_bytesread + rusage.ri_diskio_byteswritten
            guard diskIO > 0 else { continue }

            processes.append(TopProcess(
                id: pid,
                name: name,
                value: Double(diskIO),
                formattedValue: ByteFormatter.formatSpeed(diskIO / 5) // rough per-second estimate
            ))
        }

        processes.sort { $0.value > $1.value }
        return Array(processes.prefix(limit))
    }
}

private let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0
    }
}()
