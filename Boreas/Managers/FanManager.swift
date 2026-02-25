import Foundation
import Combine
import AppKit

struct FanInfo: Identifiable {
    let id: Int
    let index: Int
    var currentSpeed: Double
    var minSpeed: Double
    var maxSpeed: Double
    var targetSpeed: Double
    var isManual: Bool
    var selectedSpeedLabel: String = "Auto"

    var speedPercentage: Double {
        guard maxSpeed > minSpeed else { return 0 }
        return max(0, ((currentSpeed - minSpeed) / (maxSpeed - minSpeed)) * 100.0)
    }

    var isIdle: Bool {
        currentSpeed <= minSpeed
    }

    var name: String {
        switch index {
        case 0: return "Left Fan"
        case 1: return "Right Fan"
        default: return "Fan \(index + 1)"
        }
    }
}

enum FanControlMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual = "Manual"
    case curve = "Fan Curve"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .automatic: return "gearshape"
        case .manual: return "slider.horizontal.3"
        case .curve: return "chart.xyaxis.line"
        }
    }
}

class FanManager: ObservableObject {
    static weak var shared: FanManager?

    var fans: [FanInfo] = []
    @Published var controlMode: FanControlMode = .automatic
    @Published var manualSpeedPercentage: Double = 50.0
    @Published var isControlActive = false
    @Published var hasWriteAccess = false
    @Published var isRequestingAccess = false
    @Published var isYielding = false
    @Published private(set) var isCurveCooldownActive = false

    /// Average current speed as percentage of range (min→max) across all fans
    /// Ensures idle (min RPM) maps to 0% for correct icon coloring.
    var averageSpeedPercentage: Double {
        let pairs = fans.compactMap { fan -> Double? in
            guard fan.maxSpeed > fan.minSpeed else { return nil }
            let normalized = (fan.currentSpeed - fan.minSpeed) / (fan.maxSpeed - fan.minSpeed)
            return max(0, min(1, normalized)) * 100.0
        }
        guard !pairs.isEmpty else { return 0 }
        return pairs.reduce(0, +) / Double(pairs.count)
    }

    /// Whether the menu bar icon should animate (spin)
    var shouldSpinIcon: Bool {
        return averageSpeedPercentage > 0 || isCurveCooldownActive
    }

    /// Active fan curve + temperature callback for periodic re-evaluation
    var activeCurve: FanCurve?
    var curveTemperatureProvider: (() -> Double)?

    /// Hysteresis: prevent rapid on/off toggling at curve threshold
    private var curveFansForced = false
    private var lastCurveModeTransition: Date = .distantPast
    private var lastCurveAboveZero: Date = .distantPast
    private let curveModeTransitionCooldown: TimeInterval = 30

    private let smc = SMCKit.shared

    private func setCurveCooldown(_ value: Bool) {
        DispatchQueue.main.async { self.isCurveCooldownActive = value }
    }

    private var helperRunning = false
    private var helperProcess: Process?
    private var cmdFd: Int32 = -1  // Persistent cmd FIFO fd
    private var rspFd: Int32 = -1  // Persistent rsp FIFO fd
    private let helperQueue = DispatchQueue(label: "com.boreas.helper", qos: .userInitiated)
    private var rspBuffer = Data()

    init() {
        FanManager.shared = self
        discoverFans()
        hasWriteAccess = smc.testWriteAccess()
    }

    deinit {
        shutdownHelper()
    }

    // MARK: - Daemon Connection

    /// Called on app launch — connects to existing daemon or installs it (one-time password)
    func requestAdminAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true

        helperQueue.async { [weak self] in
            guard let self = self else { return }

            self.closePersistentFDs()

            // Step 1: Try connecting to existing daemon (no password needed)
            if SMCDaemon.isDaemonRunning() {
                self.log.log("Daemon already running, connecting...")
                if self.connectToFIFOs(cmd: SMCDaemon.cmdPath, rsp: SMCDaemon.rspPath) {
                    self.onDaemonConnected()
                    return
                }
                self.log.log("Failed to connect to running daemon", level: .warn)
            }

            // Step 2: If daemon is installed but not running, wait a moment
            if SMCDaemon.isDaemonInstalled() {
                self.log.log("Daemon installed but not ready, waiting...")
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline {
                    if SMCDaemon.isDaemonRunning() {
                        if self.connectToFIFOs(cmd: SMCDaemon.cmdPath, rsp: SMCDaemon.rspPath) {
                            self.onDaemonConnected()
                            return
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }

            // Step 3: Install daemon (one-time password prompt)
            self.log.log("Installing daemon (one-time admin password)...")
            let installed = SMCDaemon.installDaemon()
            guard installed else {
                self.log.log("Daemon installation failed or cancelled", level: .error)
                DispatchQueue.main.async {
                    self.isRequestingAccess = false

                    // Fallback: try legacy osascript helper
                    self.launchLegacyHelper()
                }
                return
            }

            // Wait for daemon to start
            self.log.log("Daemon installed, waiting for it to start...")
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if SMCDaemon.isDaemonRunning() {
                    if self.connectToFIFOs(cmd: SMCDaemon.cmdPath, rsp: SMCDaemon.rspPath) {
                        self.onDaemonConnected()
                        return
                    }
                }
                Thread.sleep(forTimeInterval: 0.5)
            }

            self.log.log("Daemon failed to start after installation", level: .error)
            DispatchQueue.main.async { self.isRequestingAccess = false }
        }
    }

    /// Legacy fallback: launch helper via osascript (requires password every time)
    private func launchLegacyHelper() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true

        helperQueue.async { [weak self] in
            guard let self = self, let execPath = Bundle.main.executablePath else {
                DispatchQueue.main.async { self?.isRequestingAccess = false }
                return
            }

            SMCDaemon.prepareLegacyFIFOs()
            let fifoDir = SMCDaemon.legacyFifoDir

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e",
                "do shell script \"\\\"\(execPath)\\\" --smc-helper \\\"\(fifoDir)\\\"\" with administrator privileges"]

            do {
                try proc.run()
                self.helperProcess = proc
            } catch {
                self.log.log("Legacy helper launch failed: \(error)", level: .error)
                DispatchQueue.main.async { self.isRequestingAccess = false }
                return
            }

            let readyPath = fifoDir + "boreas-smc-ready"
            let cmdPath = fifoDir + "boreas-smc-cmd"
            let rspPath = fifoDir + "boreas-smc-rsp"

            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: readyPath) {
                    if self.connectToFIFOs(cmd: cmdPath, rsp: rspPath) {
                        self.onDaemonConnected()
                        return
                    }
                }
                Thread.sleep(forTimeInterval: 0.2)
            }

            proc.terminate()
            self.log.log("Legacy helper timeout", level: .error)
            DispatchQueue.main.async { self.isRequestingAccess = false }
        }
    }

    private func connectToFIFOs(cmd cmdPath: String, rsp rspPath: String) -> Bool {
        self.cmdFd = Darwin.open(cmdPath, O_WRONLY)
        guard self.cmdFd >= 0 else { return false }

        self.rspFd = Darwin.open(rspPath, O_RDONLY)
        guard self.rspFd >= 0 else {
            Darwin.close(self.cmdFd); self.cmdFd = -1
            return false
        }

        self.helperRunning = true
        self.rspBuffer = Data()
        return true
    }

    private func onDaemonConnected() {
        self.log.log("Connected to daemon")

        // Reset all fans to auto (recovers from crashed sessions)
        let numFans = self.smc.getNumberOfFans()
        var allOk = true
        for i in 0..<numFans {
            let r = self.setFanModeWrite(fanIndex: i, mode: .automatic)
            self.log.log("Reset fan \(i) to auto: \(r)", level: r ? .info : .error)
            if !r { allOk = false }
        }

        // DIAGNOSTIC: Read back fan keys through daemon (root) to verify
        for i in 0..<numFans {
            let mdVal = self.privilegedRead(key: "F\(i)Md")
            let tgVal = self.privilegedRead(key: "F\(i)Tg")
            let mnVal = self.privilegedRead(key: "F\(i)Mn")
            let acVal = self.privilegedRead(key: "F\(i)Ac")
            self.log.log("DIAG Fan\(i): Md=\(mdVal ?? "nil") Tg=\(tgVal ?? "nil") Mn=\(mnVal ?? "nil") Ac=\(acVal ?? "nil")")
        }

        self.log.log("Daemon ready, all fans reset: \(allOk)")

        DispatchQueue.main.async {
            self.hasWriteAccess = allOk
            self.isRequestingAccess = false

            if allOk && self.controlMode == .manual {
                self.applyManualSpeed()
            }
        }
    }

    private func closePersistentFDs() {
        if cmdFd >= 0 { Darwin.close(cmdFd); cmdFd = -1 }
        if rspFd >= 0 { Darwin.close(rspFd); rspFd = -1 }
    }

    func shutdownHelper() {
        // Restore thermalmonitord control before disconnecting
        if forceTestModeActive && helperRunning {
            _ = smcWrite(key: "Ftst", bytes: [0x00])
            forceTestModeActive = false
        }
        helperRunning = false
        closePersistentFDs()
        if let proc = helperProcess, proc.isRunning {
            proc.terminate()
        }
        helperProcess = nil
    }

    /// Send a command to the daemon and get the response line
    private func sendCommand(_ command: String, timeout: TimeInterval = 5) -> String? {
        guard helperRunning, cmdFd >= 0, rspFd >= 0 else { return nil }

        let cmdBytes = Array((command + "\n").utf8)
        let written = cmdBytes.withUnsafeBufferPointer { ptr -> Int in
            Darwin.write(cmdFd, ptr.baseAddress!, ptr.count)
        }
        guard written > 0 else {
            log.log("FIFO write failed (errno=\(errno)), daemon died", level: .error)
            helperRunning = false
            DispatchQueue.main.async { self.hasWriteAccess = false }
            return nil
        }

        var buf = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let nlRange = rspBuffer.range(of: Data([0x0A])) {
                let lineData = rspBuffer[rspBuffer.startIndex..<nlRange.lowerBound]
                rspBuffer.removeSubrange(rspBuffer.startIndex...nlRange.lowerBound)
                return String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let n = Darwin.read(rspFd, &buf, buf.count)
            if n <= 0 {
                log.log("FIFO read failed, daemon died", level: .error)
                helperRunning = false
                DispatchQueue.main.async { self.hasWriteAccess = false }
                return nil
            }
            rspBuffer.append(contentsOf: buf[0..<n])
        }

        log.log("Command timeout: \(command)", level: .error)
        return nil
    }

    /// Write to SMC via daemon
    private func privilegedWrite(key: String, bytes: [UInt8]) -> Bool {
        let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let response = sendCommand("WRITE \(key) \(hexStr)")
        return response?.hasPrefix("OK") ?? false
    }

    /// Read an SMC key via daemon (root connection) — returns the response string
    private func privilegedRead(key: String) -> String? {
        guard let response = sendCommand("READ \(key)") else { return nil }
        if response.hasPrefix("VAL ") {
            return String(response.dropFirst(4))
        }
        if response.hasPrefix("RAW ") {
            return String(response.dropFirst(4))
        }
        return nil
    }

    /// Read an SMC key via daemon and decode as Double
    private func privilegedReadDouble(key: String) -> Double? {
        guard let response = sendCommand("READ \(key)") else { return nil }
        if response.hasPrefix("VAL ") {
            return Double(response.dropFirst(4).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Write to SMC - uses helper if available, direct otherwise
    private func smcWrite(key: String, bytes: [UInt8]) -> Bool {
        if helperRunning {
            return privilegedWrite(key: key, bytes: bytes)
        }
        return smc.writeKey(key, bytes: bytes)
    }

    private let log = LogManager.shared
    private var forceTestModeActive = false

    private func setYielding(_ value: Bool) {
        DispatchQueue.main.async { self.isYielding = value }
    }

    // MARK: - Apple Silicon thermalmonitord Unlock

    /// Write Ftst=1 to unlock thermalmonitord, then wait for it to yield control.
    /// On Apple Silicon, thermalmonitord holds fans in Mode 3 ("System Mode") and
    /// silently ignores writes to F{n}Md/F{n}Tg unless Ftst is set to 1 first.
    private func ensureForceTestMode() {
        guard !forceTestModeActive else { return }

        setYielding(true)
        let r = smcWrite(key: "Ftst", bytes: [0x01])
        log.log("Ftst=1 (unlock thermalmonitord) → \(r)")

        guard r else {
            log.log("Ftst write failed — fan control may not work", level: .error)
            setYielding(false)
            return
        }

        // thermalmonitord takes 3-6 seconds to yield after Ftst=1.
        // Retry reading F0Md until it changes from 3 (system mode) to confirm yield.
        log.log("Waiting for thermalmonitord to yield...")
        for attempt in 1...12 {
            Thread.sleep(forTimeInterval: 0.5)
            if let mdVal = privilegedRead(key: "F0Md") {
                log.log("  attempt \(attempt): F0Md=\(mdVal)")
                // thermalmonitord has released if mode is no longer 3
                if let v = Double(mdVal), v != 3.0 {
                    log.log("thermalmonitord yielded after \(attempt * 500)ms")
                    // Stabilization: wait for thermalmonitord to fully settle,
                    // then re-assert Ftst=1 to lock it out
                    Thread.sleep(forTimeInterval: 1.0)
                    _ = smcWrite(key: "Ftst", bytes: [0x01])
                    log.log("Ftst=1 re-asserted after yield")
                    forceTestModeActive = true
                    setYielding(false)
                    return
                }
            }
            // Also try writing F0Md=1 to see if it sticks
            _ = smcWrite(key: "F0Md", bytes: [0x01])
        }

        // Even if mode didn't visibly change, Ftst=1 was written — proceed
        log.log("thermalmonitord yield timeout — proceeding anyway")
        forceTestModeActive = true
        setYielding(false)
    }

    /// Write Ftst=0 to restore thermalmonitord system control
    private func disableForceTestMode() {
        guard forceTestModeActive else { return }
        let r = smcWrite(key: "Ftst", bytes: [0x00])
        log.log("Ftst=0 (restore system control) → \(r)")
        forceTestModeActive = false
    }

    /// Set fan mode — unlocks thermalmonitord first on Apple Silicon
    private func setFanModeWrite(fanIndex: Int, mode: FanMode) -> Bool {
        // On Apple Silicon, must unlock thermalmonitord before forced mode writes
        if mode == .forced {
            ensureForceTestMode()
        }

        var success = false

        // Write F{n}Md (per-fan mode key)
        let modeKey = "F\(fanIndex)Md"
        if let val = smc.readKey(modeKey) {
            var modeBytes = [UInt8](repeating: 0, count: Int(val.dataSize))
            modeBytes[0] = UInt8(mode.rawValue)
            let r = smcWrite(key: modeKey, bytes: modeBytes)
            log.log("Fan\(fanIndex) mode \(modeKey)=\(mode.rawValue) size=\(val.dataSize) → \(r)", level: r ? .info : .error)
            if r { success = true }
        }

        // ALSO write FS! bitmask (required on some Apple Silicon)
        if let val = smc.readKey("FS! ") {
            let current = Int(smc.decodeValue(val) ?? 0)
            let newMode = mode == .forced ? (current | (1 << fanIndex)) : (current & ~(1 << fanIndex))
            let fsBytes: [UInt8] = val.dataSize == 2 ? [UInt8(newMode >> 8), UInt8(newMode & 0xFF)] : [UInt8(newMode)]
            let r = smcWrite(key: "FS! ", bytes: fsBytes)
            log.log("Fan\(fanIndex) FS!=\(fsBytes.map { String(format: "%02X", $0) }.joined()) → \(r)", level: r ? .info : .error)
            if r { success = true }
        }

        return success
    }

    /// Set fan target speed — writes BOTH F{n}Tg AND F{n}Mn for Apple Silicon
    private func setFanTargetWrite(fanIndex: Int, speed: Double) -> Bool {
        var success = false
        let tgKey = "F\(fanIndex)Tg"
        let mnKey = "F\(fanIndex)Mn"

        // Encode speed bytes based on data type
        func encodeSpeed(_ key: String) -> [UInt8]? {
            guard let val = smc.readKey(key) else { return nil }
            let dt = val.dataType.trimmingCharacters(in: .whitespaces)
            if dt == "flt" {
                let f = Float(speed)
                return withUnsafeBytes(of: f) { Array($0) }
            } else {
                let s = Int(speed)
                return [UInt8(s >> 6), UInt8((s << 2) ^ ((s >> 6) << 8))]
            }
        }

        // Write target speed
        if let bytes = encodeSpeed(tgKey) {
            let r = smcWrite(key: tgKey, bytes: bytes)
            log.log("Fan\(fanIndex) \(tgKey)=\(speed) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " ")) → \(r)", level: r ? .info : .error)
            if r { success = true }
        }

        // Also write minimum speed (forces fan to at least this speed on Apple Silicon)
        if let bytes = encodeSpeed(mnKey) {
            let r = smcWrite(key: mnKey, bytes: bytes)
            log.log("Fan\(fanIndex) \(mnKey)=\(speed) → \(r)", level: r ? .info : .debug)
            if r { success = true }
        }

        return success
    }

    // MARK: - Fan Discovery & Monitoring

    func discoverFans() {
        let numFans = smc.getNumberOfFans()
        var discoveredFans: [FanInfo] = []

        for i in 0..<numFans {
            let current = smc.getFanCurrentSpeed(fanIndex: i)
            let min = smc.getFanMinSpeed(fanIndex: i)
            let max = smc.getFanMaxSpeed(fanIndex: i)
            let target = smc.getFanTargetSpeed(fanIndex: i)
            print("FanManager: Fan\(i) — current=\(current as Any) min=\(min as Any) max=\(max as Any) target=\(target as Any)")

            discoveredFans.append(FanInfo(
                id: i, index: i,
                currentSpeed: current ?? 0, minSpeed: min ?? 0,
                maxSpeed: max ?? 6500, targetSpeed: target ?? (current ?? 0),
                isManual: false
            ))
        }

        DispatchQueue.main.async {
            self.fans = discoveredFans
        }
    }

    // MARK: - Compute / Apply
    // Fan readings use helperQueue for privileged reads, so helper path
    // dispatches to main on its own. Non-helper path returns results for batching.

    /// Pending fan speeds set by helperQueue (applied in next coordinator main.async)
    private var pendingFanSpeeds: [(Int, Double)]?

    func computeReadings() {
        let fansCopy = fans
        guard !fansCopy.isEmpty else { return }

        if helperRunning {
            helperQueue.async { [weak self] in
                guard let self = self else { return }
                var speeds = [(Int, Double)]()
                for i in 0..<fansCopy.count {
                    let key = "F\(fansCopy[i].index)Ac"
                    if let speed = self.privilegedReadDouble(key: key) {
                        speeds.append((i, speed))
                    }
                }
                self.pendingFanSpeeds = speeds
            }
        } else {
            var speeds = [(Int, Double)]()
            for i in 0..<fansCopy.count {
                if let current = smc.getFanCurrentSpeed(fanIndex: fansCopy[i].index) {
                    speeds.append((i, current))
                }
            }
            pendingFanSpeeds = speeds
        }

        reevaluateCurveIfNeeded()
    }

    func applyReadings() {
        guard let speeds = pendingFanSpeeds else { return }
        pendingFanSpeeds = nil
        for (i, speed) in speeds {
            if i < fans.count {
                fans[i].currentSpeed = speed
            }
        }
        objectWillChange.send()
    }

    private func reevaluateCurveIfNeeded() {
        guard controlMode == .curve,
              let curve = activeCurve,
              let tempProvider = curveTemperatureProvider else { return }
        let temp = tempProvider()
        guard temp > 0 else { return }
        applyFanCurveSpeed(temperature: temp, curve: curve)
    }

    // MARK: - Fan Control

    func setControlMode(_ mode: FanControlMode) {
        controlMode = mode
        switch mode {
        case .automatic:
            activeCurve = nil
            curveFansForced = false
            lastCurveModeTransition = .distantPast
            lastCurveAboveZero = .distantPast
            setCurveCooldown(false)
            resetToAutomatic()
            isControlActive = false
        case .manual:
            activeCurve = nil
            curveFansForced = false
            lastCurveModeTransition = .distantPast
            lastCurveAboveZero = .distantPast
            setCurveCooldown(false)
            isControlActive = true
            applyManualSpeed()
        case .curve:
            curveFansForced = false
            lastCurveModeTransition = .distantPast
            lastCurveAboveZero = .distantPast
            setCurveCooldown(false)
            isControlActive = true
        }
    }

    func setManualSpeed(percentage: Double) {
        manualSpeedPercentage = percentage
        if controlMode == .manual {
            applyManualSpeed()
        }
    }

    func setFanSpeed(fanIndex: Int, percentage: Double) {
        guard fanIndex < fans.count else { return }
        let fan = fans[fanIndex]
        let speed = fan.minSpeed + (fan.maxSpeed - fan.minSpeed) * (percentage / 100.0)
        let label = percentage == 100 ? "Max" : "\(Int(percentage))%"

        helperQueue.async { [weak self] in
            guard let self = self else { return }
            _ = self.setFanModeWrite(fanIndex: fan.index, mode: .forced)
            _ = self.setFanTargetWrite(fanIndex: fan.index, speed: speed)

            // Verify writes by reading back through daemon
            let mdVal = self.privilegedRead(key: "F\(fan.index)Md")
            let tgVal = self.privilegedRead(key: "F\(fan.index)Tg")
            let acVal = self.privilegedRead(key: "F\(fan.index)Ac")
            self.log.log("VERIFY Fan\(fan.index) after write: Md=\(mdVal ?? "nil") Tg=\(tgVal ?? "nil") Ac=\(acVal ?? "nil")")

            DispatchQueue.main.async {
                if fanIndex < self.fans.count {
                    self.fans[fanIndex].targetSpeed = speed
                    self.fans[fanIndex].isManual = true
                    self.fans[fanIndex].selectedSpeedLabel = label
                }
            }
        }
    }

    func setFanSpeed(fanIndex: Int, mode: FanMode) {
        guard fanIndex < fans.count else { return }
        let fan = fans[fanIndex]

        helperQueue.async { [weak self] in
            guard let self = self else { return }
            _ = self.setFanModeWrite(fanIndex: fan.index, mode: mode)

            // If setting to auto, also restore original minimum speed
            if mode == .automatic {
                let origMin = fan.minSpeed
                if let val = self.smc.readKey("F\(fan.index)Mn") {
                    let dt = val.dataType.trimmingCharacters(in: .whitespaces)
                    let bytes: [UInt8]
                    if dt == "flt" {
                        let f = Float(origMin)
                        bytes = withUnsafeBytes(of: f) { Array($0) }
                    } else {
                        let s = Int(origMin)
                        bytes = [UInt8(s >> 6), UInt8((s << 2) ^ ((s >> 6) << 8))]
                    }
                    _ = self.smcWrite(key: "F\(fan.index)Mn", bytes: bytes)
                }
            }

            DispatchQueue.main.async {
                if fanIndex < self.fans.count {
                    self.fans[fanIndex].isManual = (mode == .forced)
                    self.fans[fanIndex].selectedSpeedLabel = "Auto"
                }
            }
        }
    }

    // MARK: - Unified Fan Control (affects all fans)

    /// Computed label when all fans share the same speed label
    var unifiedSpeedLabel: String {
        let labels = Set(fans.map(\.selectedSpeedLabel))
        return labels.count == 1 ? (labels.first ?? "Auto") : ""
    }

    /// Set all fans to the same percentage
    func setAllFansSpeed(percentage: Double) {
        let label = percentage == 100 ? "Max" : "\(Int(percentage))%"
        let fansCopy = fans
        helperQueue.async { [weak self] in
            guard let self = self else { return }

            // Write mode + target for all fans, with retry if thermalmonitord overrides
            for retry in 0..<3 {
                for (i, fan) in fansCopy.enumerated() {
                    let speed = fan.minSpeed + (fan.maxSpeed - fan.minSpeed) * (percentage / 100.0)
                    _ = self.setFanModeWrite(fanIndex: fan.index, mode: .forced)
                    _ = self.setFanTargetWrite(fanIndex: fan.index, speed: speed)
                    DispatchQueue.main.async {
                        if i < self.fans.count {
                            self.fans[i].targetSpeed = speed
                            self.fans[i].isManual = true
                            self.fans[i].selectedSpeedLabel = label
                        }
                    }
                }

                // Verify writes stuck
                Thread.sleep(forTimeInterval: 0.3)
                if let mdVal = self.privilegedRead(key: "F0Md"),
                   let v = Double(mdVal), v == 1.0 {
                    self.log.log("setAllFansSpeed: writes verified (retry=\(retry))")
                    break
                }
                self.log.log("setAllFansSpeed: mode reverted, re-asserting Ftst=1 (retry=\(retry))")
                _ = self.smcWrite(key: "Ftst", bytes: [0x01])
                Thread.sleep(forTimeInterval: 0.5)
                self.forceTestModeActive = false  // force re-unlock
            }
        }
    }

    /// Set all fans to automatic
    func setAllFansAuto() {
        resetToAutomatic()
    }

    func applyManualSpeed() {
        let fansCopy = fans
        let pct = manualSpeedPercentage
        helperQueue.async { [weak self] in
            guard let self = self else { return }

            for retry in 0..<3 {
                for (i, fan) in fansCopy.enumerated() {
                    let speed = fan.minSpeed + (fan.maxSpeed - fan.minSpeed) * (pct / 100.0)
                    _ = self.setFanModeWrite(fanIndex: fan.index, mode: .forced)
                    _ = self.setFanTargetWrite(fanIndex: fan.index, speed: speed)

                    DispatchQueue.main.async {
                        if i < self.fans.count {
                            self.fans[i].targetSpeed = speed
                            self.fans[i].isManual = true
                        }
                    }
                }

                // Verify writes stuck
                Thread.sleep(forTimeInterval: 0.3)
                if let mdVal = self.privilegedRead(key: "F0Md"),
                   let v = Double(mdVal), v == 1.0 {
                    self.log.log("applyManualSpeed: writes verified (retry=\(retry))")
                    break
                }
                self.log.log("applyManualSpeed: mode reverted, re-asserting Ftst=1 (retry=\(retry))")
                _ = self.smcWrite(key: "Ftst", bytes: [0x01])
                Thread.sleep(forTimeInterval: 0.5)
                self.forceTestModeActive = false
            }
        }
    }

    func applyFanCurveSpeed(temperature: Double, curve: FanCurve, allowImmediateOff: Bool = false) {
        let percentage = curve.speedForTemperature(temperature)
        let fansCopy = fans
        let now = Date()

        // Track last time curve demanded >0%
        if percentage > 0 {
            lastCurveAboveZero = now
            setCurveCooldown(false)
        }

        // Off logic: require cooldown since last above-zero demand
        if percentage <= 0 {
            let sinceLastAbove = now.timeIntervalSince(lastCurveAboveZero)
            // Allow immediate off on activation, otherwise require cooldown if we were forced
            if allowImmediateOff || curveFansForced {
                if allowImmediateOff || sinceLastAbove >= curveModeTransitionCooldown {
                    curveFansForced = false
                    lastCurveModeTransition = now
                    resetToAutomatic()
                    DispatchQueue.main.async { self.controlMode = .curve }
                    setCurveCooldown(false)
                } else {
                    setCurveCooldown(true)
                }
            } else {
                setCurveCooldown(false)
            }
            return
        }

        // On logic: immediate transition to forced when curve > 0
        if !curveFansForced {
            curveFansForced = true
            lastCurveModeTransition = now
        }
        setCurveCooldown(false)

        // Already forced — update speed at normal frequency
        helperQueue.async { [weak self] in
            guard let self = self else { return }

            for retry in 0..<3 {
                for (i, fan) in fansCopy.enumerated() {
                    let speed = fan.minSpeed + (fan.maxSpeed - fan.minSpeed) * (percentage / 100.0)
                    _ = self.setFanModeWrite(fanIndex: fan.index, mode: .forced)
                    _ = self.setFanTargetWrite(fanIndex: fan.index, speed: speed)

                    DispatchQueue.main.async {
                        if i < self.fans.count {
                            self.fans[i].targetSpeed = speed
                            self.fans[i].isManual = true
                        }
                    }
                }

                // Verify writes stuck
                Thread.sleep(forTimeInterval: 0.3)
                if let mdVal = self.privilegedRead(key: "F0Md"),
                   let v = Double(mdVal), v == 1.0 {
                    self.log.log("applyFanCurveSpeed: writes verified (retry=\(retry))")
                    break
                }
                self.log.log("applyFanCurveSpeed: mode reverted, re-asserting Ftst=1 (retry=\(retry))")
                _ = self.smcWrite(key: "Ftst", bytes: [0x01])
                Thread.sleep(forTimeInterval: 0.5)
                self.forceTestModeActive = false
            }
        }
    }

    func resetToAutomatic() {
        let fansCopy = fans
        helperQueue.async { [weak self] in
            guard let self = self else { return }

            // Disable force test mode first — thermalmonitord resumes control
            self.disableForceTestMode()

            for fan in fansCopy {
                _ = self.setFanModeWrite(fanIndex: fan.index, mode: .automatic)
            }
            if let val = self.smc.readKey("FS! ") {
                let zeros = [UInt8](repeating: 0, count: Int(val.dataSize))
                _ = self.smcWrite(key: "FS! ", bytes: zeros)
            }
        }
        for i in 0..<fans.count {
            DispatchQueue.main.async {
                if i < self.fans.count {
                    self.fans[i].isManual = false
                    self.fans[i].selectedSpeedLabel = "Auto"
                }
            }
        }
    }
}
