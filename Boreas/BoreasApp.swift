import SwiftUI
import Combine

struct BoreasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Boreas", id: "main") {
            ContentView()
                .environmentObject(appDelegate.sensorManager)
                .environmentObject(appDelegate.fanManager)
                .environmentObject(appDelegate.profileManager)
                .environmentObject(appDelegate.cpuManager)
                .environmentObject(appDelegate.ramManager)
                .environmentObject(appDelegate.gpuManager)
                .environmentObject(appDelegate.batteryManager)
                .environmentObject(appDelegate.networkManager)
                .environmentObject(appDelegate.diskManager)
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1050, height: 750)
    }
}

// MARK: - Colored menu bar icon (NSStatusItem, like Stats app)
// NSStatusItem with NSHostingView renders real SwiftUI with colors,
// unlike MenuBarExtra which forces template (monochrome) rendering.

struct StatusBarIconView: View {
    @ObservedObject var fanManager: FanManager

    // private var iconSpeed: Speed {
    //     // White: curve cooldown (takes absolute priority)
    //     if fanManager.isCurveCooldownActive { return .1 }
    //     // Also show white while yielding control/unlocking
    //     if fanManager.isYielding { return .1 }

    //     let pct = max(0, fanManager.averageSpeedPercentage)
    //     switch pct {
    //     case 0:
    //         return .gray    // idle
    //     case ..<20:
    //         return .blue
    //     case ..<40:
    //         return .green
    //     case ..<60:
    //         return .yellow
    //     case ..<80:
    //         return .orange
    //     default:
    //         return .red
    //     }
    // }

    private var iconColor: Color {
        // White: curve cooldown (takes absolute priority)
        if fanManager.isCurveCooldownActive { return .white }
        // Also show white while yielding control/unlocking
        if fanManager.isYielding { return .white }

        let pct = max(0, fanManager.averageSpeedPercentage)
        switch pct {
        case 0:
            return .gray    // idle
        case ..<20:
            return .blue
        case ..<40:
            return .green
        case ..<60:
            return .yellow
        case ..<80:
            return .orange
        default:
            return .red
        }
    }

    private var isSpinning: Bool { fanManager.shouldSpinIcon }
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "fan.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .rotationEffect(.degrees(rotation))
                .animation(isSpinning
                           ? .linear(duration: 2).repeatForever(autoreverses: false)
                           : .default,
                           value: rotation)
        }
        .frame(height: 30)
        .onAppear {
            if isSpinning { rotation = 180 }
        }
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                rotation = 180
            } else {
                rotation = 0
            }
        }
    }
}

// MARK: - SMC Daemon
// Persistent root daemon that handles ALL SMC reads + writes.
// Installed once as a LaunchDaemon — no password needed after first install.
// Protocol:
//   WRITE <key> <hex-bytes...>\n → OK | ERR <msg>
//   READ <key>\n                → VAL <double> | RAW <type> <hex> | ERR <msg>

class SMCDaemon {
    // Well-known paths for daemon mode
    static let cmdPath = "/tmp/boreas-smc-cmd"
    static let rspPath = "/tmp/boreas-smc-rsp"
    static let readyPath = "/tmp/boreas-smc-ready"
    static let logPath = "/tmp/boreas-daemon.log"

    // LaunchDaemon install paths
    static let daemonLabel = "com.boreas.smchelper"
    static let binaryPath = "/Library/PrivilegedHelperTools/com.boreas.smchelper"
    static let plistPath = "/Library/LaunchDaemons/com.boreas.smchelper.plist"

    // Legacy mode paths
    static var legacyFifoDir: String = "/tmp/"

    // MARK: - Daemon lifecycle

    /// Run as persistent daemon — loops forever, reconnects after client disconnect
    static func runPersistent() {
        log("Daemon starting — uid=\(getuid()), euid=\(geteuid()), pid=\(getpid())")
        let smc = SMCKit.shared
        log("SMC open: \(smc.isOpen)")

        while true {
            // Create fresh FIFOs each cycle
            cleanupFIFOs(cmd: cmdPath, rsp: rspPath, ready: readyPath)
            mkfifo(cmdPath, 0o666)
            mkfifo(rspPath, 0o666)
            // Root's umask may strip write bits — force world read/write
            chmod(cmdPath, 0o666)
            chmod(rspPath, 0o666)
            FileManager.default.createFile(atPath: readyPath, contents: nil)
            log("FIFOs ready, waiting for client...")

            handleSession(cmd: cmdPath, rsp: rspPath, smc: smc)

            log("Client disconnected, waiting for reconnect...")
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Run as one-shot helper (legacy mode — exits on disconnect)
    static func runOnce() {
        let cmd = legacyFifoDir + "boreas-smc-cmd"
        let rsp = legacyFifoDir + "boreas-smc-rsp"
        let ready = legacyFifoDir + "boreas-smc-ready"

        log("Helper starting — uid=\(getuid()), euid=\(geteuid()), pid=\(getpid())")
        let smc = SMCKit.shared
        log("SMC open: \(smc.isOpen)")

        FileManager.default.createFile(atPath: ready, contents: nil)
        handleSession(cmd: cmd, rsp: rsp, smc: smc)
        log("Helper exiting")
    }

    // MARK: - Session handling

    private static func handleSession(cmd cmdPath: String, rsp rspPath: String, smc: SMCKit) {
        log("Opening cmd FIFO...")
        let cmdFd = Darwin.open(cmdPath, O_RDONLY)
        guard cmdFd >= 0 else { log("FATAL: cmd FIFO open failed"); return }

        log("Opening rsp FIFO...")
        let rspFd = Darwin.open(rspPath, O_WRONLY)
        guard rspFd >= 0 else { log("FATAL: rsp FIFO open failed"); Darwin.close(cmdFd); return }

        log("Client connected")

        var buffer = Data()
        var readBuf = [UInt8](repeating: 0, count: 1024)

        while true {
            let n = Darwin.read(cmdFd, &readBuf, readBuf.count)
            if n <= 0 { break }
            buffer.append(contentsOf: readBuf[0..<n])

            while let nlRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<nlRange.lowerBound]
                buffer.removeSubrange(buffer.startIndex...nlRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !line.isEmpty else { continue }

                let response = processCommand(line, smc: smc)

                let rspData = (response + "\n").data(using: .utf8)!
                rspData.withUnsafeBytes { ptr in
                    _ = Darwin.write(rspFd, ptr.baseAddress!, ptr.count)
                }
            }
        }

        Darwin.close(cmdFd)
        Darwin.close(rspFd)
    }

    // MARK: - Command processing

    private static func processCommand(_ line: String, smc: SMCKit) -> String {
        let parts = line.split(separator: " ")
        guard !parts.isEmpty else { return "ERR empty" }

        switch String(parts[0]) {
        case "WRITE":
            guard parts.count >= 3 else { return "ERR write_args" }
            let key = String(parts[1])
            let hexBytes = parts[2...].compactMap { UInt8($0, radix: 16) }
            let result = smc.writeKey(key, bytes: hexBytes)
            log("WRITE \(key) [\(hexBytes.map { String(format: "%02X", $0) }.joined(separator: " "))] → \(result)")
            return result ? "OK" : "ERR write_failed"

        case "READ":
            guard parts.count >= 2 else { return "ERR read_args" }
            let key = String(parts[1])
            guard let val = smc.readKey(key) else { return "ERR read_nil" }
            let hexBytes = val.bytes.prefix(Int(val.dataSize)).map { String(format: "%02X", $0) }.joined(separator: " ")
            let dt = val.dataType.trimmingCharacters(in: .whitespaces)
            if let decoded = smc.decodeValue(val) {
                log("READ \(key) → \(dt) [\(hexBytes)] = \(decoded)")
                return "VAL \(decoded)"
            }
            log("READ \(key) → \(dt) [\(hexBytes)] (no decode)")
            return "RAW \(dt) \(hexBytes)"

        default:
            return "ERR unknown_cmd"
        }
    }

    // MARK: - Installation

    static func isDaemonRunning() -> Bool {
        FileManager.default.fileExists(atPath: readyPath)
    }

    static func isDaemonInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// Install the daemon as a LaunchDaemon. Prompts for admin password ONCE.
    /// Points plist directly at the binary inside the app bundle (dylibs are co-located).
    static func installDaemon() -> Bool {
        guard let execPath = Bundle.main.executablePath else { return false }

        let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(daemonLabel)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(execPath)</string>
        <string>--smc-daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>\(logPath)</string>
    <key>StandardErrorPath</key>
    <string>\(logPath)</string>
</dict>
</plist>
"""

        let tmpPlist = NSTemporaryDirectory() + "com.boreas.smchelper.plist"
        try? plistContent.write(toFile: tmpPlist, atomically: true, encoding: .utf8)

        // Only install the plist — no binary copying needed since we point at the app bundle
        let script = """
        do shell script "cp '\(tmpPlist)' '\(plistPath)' && \
        chmod 644 '\(plistPath)' && \
        launchctl bootout system/\(daemonLabel) 2>/dev/null; \
        launchctl bootstrap system '\(plistPath)'" with administrator privileges
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]

        do {
            try proc.run()
            proc.waitUntilExit()
            let ok = proc.terminationStatus == 0
            log("Daemon install: \(ok ? "SUCCESS" : "FAILED") (exit=\(proc.terminationStatus))")
            return ok
        } catch {
            log("Daemon install error: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    static func prepareLegacyFIFOs() {
        let cmd = legacyFifoDir + "boreas-smc-cmd"
        let rsp = legacyFifoDir + "boreas-smc-rsp"
        let ready = legacyFifoDir + "boreas-smc-ready"
        cleanupFIFOs(cmd: cmd, rsp: rsp, ready: ready)
        mkfifo(cmd, 0o666)
        mkfifo(rsp, 0o666)
        print("SMCDaemon: FIFOs created at \(cmd)")
    }

    static func cleanupFIFOs(cmd: String, rsp: String, ready: String) {
        unlink(cmd)
        unlink(rsp)
        unlink(ready)
    }

    private static func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let sensorManager = SensorManager()
    let fanManager = FanManager()
    let profileManager = ProfileManager()
    let cpuManager = CPUManager()
    let ramManager = RAMManager()
    let gpuManager = GPUManager()
    let batteryManager = BatteryManager()
    let networkManager = NetworkManager()
    let diskManager = DiskManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hostingView: NSHostingView<StatusBarIconView>?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        FanManager.shared?.shutdownHelper()
        SMCKit.shared.resetAllFansToAutomatic()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        // Embed a colored SwiftUI view directly in the status bar button
        let iconView = StatusBarIconView(fanManager: fanManager)
        let hosting = NSHostingView(rootView: iconView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        self.hostingView = hosting

        button.action = #selector(togglePopover)
        button.target = self

        // Popover with MenuBarView content
        let menuBarView = MenuBarView()
            .environmentObject(sensorManager)
            .environmentObject(fanManager)
            .environmentObject(profileManager)
            .environmentObject(cpuManager)
            .environmentObject(ramManager)
            .environmentObject(gpuManager)
            .environmentObject(batteryManager)
            .environmentObject(networkManager)
            .environmentObject(diskManager)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Dismiss popover when clicking outside
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
