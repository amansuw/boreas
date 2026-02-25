import Foundation

enum MonitorQueues {
    static let fast = DispatchQueue(label: "com.boreas.monitor.fast", qos: .utility)
    static let slow = DispatchQueue(label: "com.boreas.monitor.slow", qos: .utility)
}

class MonitorCoordinator {
    weak var cpu: CPUManager?
    weak var ram: RAMManager?
    weak var gpu: GPUManager?
    weak var sensor: SensorManager?
    weak var fan: FanManager?
    weak var network: NetworkManager?
    weak var disk: DiskManager?
    weak var battery: BatteryManager?

    private var fastSource: DispatchSourceTimer?
    private var slowSource: DispatchSourceTimer?

    private var fastTickCount = 0
    private var slowTickCount = 0

    func start() {
        let fast = DispatchSource.makeTimerSource(queue: MonitorQueues.fast)
        fast.schedule(deadline: .now(), repeating: 2.0, leeway: .milliseconds(200))
        fast.setEventHandler { [weak self] in self?.fastTick() }
        fast.resume()
        fastSource = fast

        let slow = DispatchSource.makeTimerSource(queue: MonitorQueues.slow)
        slow.schedule(deadline: .now() + 1.0, repeating: 10.0, leeway: .seconds(1))
        slow.setEventHandler { [weak self] in self?.slowTick() }
        slow.resume()
        slowSource = slow
    }

    func stop() {
        fastSource?.cancel()
        fastSource = nil
        slowSource?.cancel()
        slowSource = nil
    }

    private func fastTick() {
        fastTickCount += 1

        let cpuResult = cpu?.computeUsage()
        let ramResult = ram?.computeMemory()
        let gpuResult = gpu?.computeUsage()
        let netResult = network?.computeStats()
        let diskIOResult = disk?.computeIO()

        fan?.computeReadings()

        // Sensors every 5th fast tick (10s effective at 2s interval)
        var sensorResult: SensorManager.FastResult?
        if fastTickCount % 5 == 0 {
            sensorResult = sensor?.computeReadings()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let r = cpuResult { self.cpu?.applyUsage(r) }
            if let r = ramResult { self.ram?.applyMemory(r) }
            if let r = gpuResult { self.gpu?.applyUsage(r) }
            if let r = netResult { self.network?.applyStats(r) }
            if let r = diskIOResult { self.disk?.applyIO(r) }
            self.fan?.applyReadings()
            if let r = sensorResult { self.sensor?.applyReadings(r) }
        }
    }

    private func slowTick() {
        slowTickCount += 1

        let cpuProcs = cpu?.computeProcesses()
        let ramProcs = ram?.computeProcesses()
        let diskProcs = disk?.computeProcesses()

        // Disk space every 2nd slow tick (20s effective at 10s interval)
        var diskSpace: [DiskInfo]?
        if slowTickCount % 2 == 0 {
            diskSpace = disk?.computeSpace()
        }

        let batteryResult = battery?.computeBattery()

        // Public IP every 6th slow tick (60s effective at 10s interval)
        if slowTickCount % 6 == 0 {
            network?.pollPublicIP()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let p = cpuProcs { self.cpu?.applyProcesses(p) }
            if let p = ramProcs { self.ram?.applyProcesses(p) }
            if let p = diskProcs { self.disk?.applyProcesses(p) }
            if let d = diskSpace { self.disk?.applySpace(d) }
            if let b = batteryResult { self.battery?.applyBattery(b) }
        }
    }
}
