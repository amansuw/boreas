import Foundation
import Combine
import SystemConfiguration

class NetworkManager: ObservableObject {
    @Published var stats = NetworkStats()
    @Published var topProcesses: [TopProcess] = []
    @Published var history: [NetworkSnapshot] = []

    private var timer: Timer?
    private var publicIPTimer: Timer?
    private let readQueue = DispatchQueue(label: "com.boreas.network-read", qos: .utility)
    private let maxHistoryPoints = 86400

    // Previous byte counts for delta calculation
    private var prevBytesIn: UInt64 = 0
    private var prevBytesOut: UInt64 = 0
    private var prevTimestamp: Date?

    // Latency tracking
    private var latencySamples: [Double] = []

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

        // Public IP every 60s
        publicIPTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchPublicIP()
        }
        RunLoop.main.add(publicIPTimer!, forMode: .common)

        update()
        fetchPublicIP()
        fetchDNSServers()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        publicIPTimer?.invalidate()
        publicIPTimer = nil
    }

    // MARK: - Network Stats via getifaddrs

    private func update() {
        readQueue.async { [weak self] in
            guard let self = self else { return }

            var totalIn: UInt64 = 0
            var totalOut: UInt64 = 0
            var activeIface: NetworkInterface?

            var ifaddr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
            defer { freeifaddrs(ifaddr) }

            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let addr = ptr {
                let name = String(cString: addr.pointee.ifa_name)
                let flags = Int32(addr.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0

                // Get byte counts from AF_LINK
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) && !isLoopback {
                    addr.pointee.ifa_data.withMemoryRebound(to: if_data.self, capacity: 1) { data in
                        totalIn += UInt64(data.pointee.ifi_ibytes)
                        totalOut += UInt64(data.pointee.ifi_obytes)
                    }
                }

                // Get IP address from AF_INET
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) && isUp && !isLoopback {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: hostname)

                    if !ip.isEmpty && ip != "127.0.0.1" && activeIface == nil {
                        var iface = NetworkInterface(id: name)
                        iface.localIP = ip
                        iface.isUp = isUp
                        iface.displayName = self.interfaceDisplayName(name)

                        // Get MAC address
                        iface.macAddress = self.getMACAddress(for: name, firstAddr: firstAddr)

                        // Get link speed
                        self.getLinkSpeed(for: name, firstAddr: firstAddr, iface: &iface)

                        activeIface = iface
                    }
                }

                // Get IPv6
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET6) && isUp && !isLoopback {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let ip6 = String(cString: hostname)
                    if !ip6.hasPrefix("fe80") && !ip6.isEmpty {
                        activeIface?.ipv6 = ip6
                    }
                }

                ptr = addr.pointee.ifa_next
            }

            // Calculate speed deltas
            let now = Date()
            var dlSpeed: UInt64 = 0
            var ulSpeed: UInt64 = 0

            if let prevTime = self.prevTimestamp {
                let elapsed = now.timeIntervalSince(prevTime)
                if elapsed > 0 && totalIn >= self.prevBytesIn && totalOut >= self.prevBytesOut {
                    dlSpeed = UInt64(Double(totalIn - self.prevBytesIn) / elapsed)
                    ulSpeed = UInt64(Double(totalOut - self.prevBytesOut) / elapsed)
                }
            }

            self.prevBytesIn = totalIn
            self.prevBytesOut = totalOut
            self.prevTimestamp = now

            let snapshot = NetworkSnapshot(
                timestamp: now,
                downloadBytesPerSec: dlSpeed,
                uploadBytesPerSec: ulSpeed
            )

            DispatchQueue.main.async {
                self.stats.downloadBytesPerSec = dlSpeed
                self.stats.uploadBytesPerSec = ulSpeed
                self.stats.totalDownload = totalIn
                self.stats.totalUpload = totalOut
                self.stats.activeInterface = activeIface
                self.history.append(snapshot)
                if self.history.count > self.maxHistoryPoints {
                    self.history.removeFirst(self.history.count - self.maxHistoryPoints)
                }
            }
        }
    }

    // MARK: - Interface helpers

    private func interfaceDisplayName(_ name: String) -> String {
        if name.hasPrefix("en0") { return "Wi-Fi" }
        if name.hasPrefix("en") { return "Ethernet (\(name))" }
        if name.hasPrefix("utun") { return "VPN (\(name))" }
        if name.hasPrefix("bridge") { return "Bridge (\(name))" }
        return name
    }

    private func getMACAddress(for interfaceName: String, firstAddr: UnsafeMutablePointer<ifaddrs>) -> String {
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            if name == interfaceName && addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                var mac = addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl -> String in
                    let addrLen = Int(sdl.pointee.sdl_alen)
                    guard addrLen == 6 else { return "" }
                    let dataStart = withUnsafePointer(to: &sdl.pointee.sdl_data) { ptr in
                        UnsafeRawPointer(ptr).advanced(by: Int(sdl.pointee.sdl_nlen))
                    }
                    let bytes = dataStart.bindMemory(to: UInt8.self, capacity: 6)
                    return (0..<6).map { String(format: "%02x", bytes[$0]) }.joined(separator: ":")
                }
                return mac
            }
            ptr = addr.pointee.ifa_next
        }
        return ""
    }

    private func getLinkSpeed(for interfaceName: String, firstAddr: UnsafeMutablePointer<ifaddrs>, iface: inout NetworkInterface) {
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            if name == interfaceName && addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                addr.pointee.ifa_data.withMemoryRebound(to: if_data.self, capacity: 1) { data in
                    let baudrate = data.pointee.ifi_baudrate
                    if baudrate > 0 {
                        let mbits = baudrate / 1_000_000
                        iface.speed = "\(mbits) Mbit"
                    }
                }
                return
            }
            ptr = addr.pointee.ifa_next
        }
    }

    // MARK: - DNS Servers

    private func fetchDNSServers() {
        readQueue.async { [weak self] in
            guard let self = self else { return }

            var servers: [String] = []

            // Read from SCDynamicStore
            if let store = SCDynamicStoreCreate(nil, "Boreas" as CFString, nil, nil) {
                let key = "State:/Network/Global/DNS" as CFString
                if let dnsDict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                   let addresses = dnsDict["ServerAddresses"] as? [String] {
                    servers = addresses
                }
            }

            DispatchQueue.main.async {
                self.stats.dnsServers = servers
            }
        }
    }

    // MARK: - Public IP

    private func fetchPublicIP() {
        let url = URL(string: "https://api.ipify.org")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let ip = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.stats.publicIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()

        // IPv6
        let url6 = URL(string: "https://api64.ipify.org")!
        URLSession.shared.dataTask(with: url6) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let ip = String(data: data, encoding: .utf8) else { return }
            let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains(":") { // Only set if actually IPv6
                DispatchQueue.main.async {
                    self?.stats.publicIPv6 = trimmed
                }
            }
        }.resume()
    }
}
