import Foundation
import IOKit

// MARK: - SMC Data Types

struct SMCKeyData {
    struct Vers {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers: Vers = Vers()
    var pLimitData: PLimitData = PLimitData()
    var keyInfo: KeyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
               (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

struct SMCVal {
    var key: String
    var dataSize: UInt32
    var dataType: String
    var bytes: [UInt8]

    init(key: String = "", dataSize: UInt32 = 0, dataType: String = "", bytes: [UInt8] = []) {
        self.key = key
        self.dataSize = dataSize
        self.dataType = dataType
        self.bytes = bytes
    }
}

// MARK: - SMC Constants

public enum FanMode: Int, Codable {
    case automatic = 0
    case forced = 1
}

extension Float {
    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }
}

private let kSMCUserClientOpen: UInt32 = 0
private let kSMCUserClientClose: UInt32 = 1
private let kSMCHandleYPCEvent: UInt32 = 2

private let kSMCCmdReadKey: UInt8 = 5
private let kSMCCmdWriteKey: UInt8 = 6
private let kSMCCmdGetKeyFromIndex: UInt8 = 8
private let kSMCCmdGetKeyInfo: UInt8 = 9

// MARK: - SMCKit

class SMCKit {
    static let shared = SMCKit()

    private var connection: io_connect_t = 0
    private(set) var isOpen = false

    private var keyInfoCache: [UInt32: SMCKeyData.KeyInfo] = [:]

    private init() {
        open()
    }

    deinit {
        close()
    }

    // MARK: - Connection

    @discardableResult
    func open() -> Bool {
        guard !isOpen else { return true }

        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0

        let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)
        if matchResult != kIOReturnSuccess {
            print("SMC: Error IOServiceGetMatchingServices: \(String(format: "0x%08X", matchResult))")
            return false
        }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        guard device != 0 else {
            print("SMC: Could not find AppleSMC device")
            return false
        }

        let result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        IOObjectRelease(device)

        if result == kIOReturnSuccess {
            isOpen = true
            print("SMC: Connection opened successfully (struct size: \(MemoryLayout<SMCKeyData>.stride))")
            return true
        }

        print("SMC: Could not open connection: \(String(format: "0x%08X", result))")
        return false
    }

    func close() {
        guard isOpen else { return }
        IOServiceClose(connection)
        isOpen = false
    }

    // MARK: - Key Operations

    private func stringToUInt32(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        let utf8 = Array(str.utf8)
        for i in 0..<min(4, utf8.count) {
            result = (result << 8) | UInt32(utf8[i])
        }
        // Pad with spaces if less than 4 chars
        for _ in utf8.count..<4 {
            result = (result << 8) | UInt32(0x20)
        }
        return result
    }

    private func uint32ToString(_ value: UInt32) -> String {
        var str = ""
        var v = value
        for _ in 0..<4 {
            let byte = UInt8((v >> 24) & 0xFF)
            if byte >= 0x20 && byte < 0x7F {
                str.append(Character(UnicodeScalar(byte)))
            } else {
                str.append("?")
            }
            v <<= 8
        }
        return str
    }

    private func bytesFromTuple(_ tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
                                 count: Int) -> [UInt8] {
        var result = [UInt8]()
        var copy = tuple
        withUnsafePointer(to: &copy) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { bytes in
                for i in 0..<min(count, 32) {
                    result.append(bytes[i])
                }
            }
        }
        return result
    }

    private var kernelSelector: UInt32 = kSMCHandleYPCEvent
    private var selectorProbed = false

    private func probeSelector() {
        guard !selectorProbed else { return }
        selectorProbed = true

        let candidates: [UInt32] = [2, 0, 1, 5]
        let testKeys = ["#KEY", "TC0P", "Tp09"]

        for sel in candidates {
            for testKey in testKeys {
                var testInput = SMCKeyData()
                testInput.key = stringToUInt32(testKey)
                testInput.data8 = kSMCCmdGetKeyInfo

                var testOutput = SMCKeyData()
                let inputSize = MemoryLayout<SMCKeyData>.stride
                var outputSize = MemoryLayout<SMCKeyData>.stride

                let result = IOConnectCallStructMethod(
                    connection, sel, &testInput, inputSize, &testOutput, &outputSize
                )

                if result == kIOReturnSuccess && testOutput.keyInfo.dataSize > 0 {
                    kernelSelector = sel
                    return
                }
            }
        }
    }

    private func callSMC(command: UInt8, inputData: inout SMCKeyData) -> SMCKeyData? {
        guard isOpen else {
            print("SMC: Not connected")
            return nil
        }

        if !selectorProbed {
            probeSelector()
        }

        inputData.data8 = command

        var outputData = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = IOConnectCallStructMethod(
            connection,
            kernelSelector,
            &inputData,
            inputSize,
            &outputData,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            if command == kSMCCmdWriteKey {
                print("SMC: Write failed with error \(String(format: "0x%08X", result))")
            }
            return nil
        }

        return outputData
    }

    func readKey(_ key: String) -> SMCVal? {
        let keyInt = stringToUInt32(key)

        // Step 1: Get key info — use cache to avoid redundant kernel call
        let info: SMCKeyData.KeyInfo
        if let cached = keyInfoCache[keyInt] {
            info = cached
        } else {
            var inputData = SMCKeyData()
            inputData.key = keyInt
            guard let keyInfoResult = callSMC(command: kSMCCmdGetKeyInfo, inputData: &inputData) else {
                return nil
            }
            guard keyInfoResult.keyInfo.dataSize > 0 else { return nil }
            info = keyInfoResult.keyInfo
            keyInfoCache[keyInt] = info
        }

        // Step 2: Read key value
        var readData = SMCKeyData()
        readData.key = keyInt
        readData.keyInfo.dataSize = info.dataSize

        guard let readResult = callSMC(command: kSMCCmdReadKey, inputData: &readData) else {
            return nil
        }

        let dataType = uint32ToString(info.dataType)
        let bytes = bytesFromTuple(readResult.bytes, count: Int(info.dataSize))

        return SMCVal(key: key, dataSize: info.dataSize, dataType: dataType, bytes: bytes)
    }

    func writeKey(_ key: String, bytes: [UInt8]) -> Bool {
        // Step 1: Get key info
        var inputData = SMCKeyData()
        inputData.key = stringToUInt32(key)

        guard let keyInfoResult = callSMC(command: kSMCCmdGetKeyInfo, inputData: &inputData) else {
            print("SMC: writeKey failed to get key info for \(key)")
            return false
        }

        // Step 2: Write key value
        var writeData = SMCKeyData()
        writeData.key = stringToUInt32(key)
        writeData.keyInfo.dataSize = keyInfoResult.keyInfo.dataSize

        var tupleBytes = writeData.bytes
        withUnsafeMutablePointer(to: &tupleBytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { dest in
                for (i, byte) in bytes.enumerated() {
                    if i < 32 {
                        dest[i] = byte
                    }
                }
            }
        }
        writeData.bytes = tupleBytes

        let result = callSMC(command: kSMCCmdWriteKey, inputData: &writeData)
        if result == nil {
            print("SMC: writeKey failed for \(key)")
        }
        return result != nil
    }

    // MARK: - Value Conversion

    func decodeValue(_ val: SMCVal) -> Double? {
        let dt = val.dataType.trimmingCharacters(in: .whitespaces)

        // Float 32-bit (native byte order — little-endian on both Intel and ARM)
        if dt == "flt" && val.bytes.count >= 4 {
            let value = val.bytes.withUnsafeBufferPointer { ptr -> Float in
                ptr.baseAddress!.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
            }
            return Double(value)
        }

        // Signed fixed-point 7.8 (temperature)
        if dt == "sp78" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 256.0
        }

        // Unsigned fixed-point 14.2 (fan speed)
        if dt == "fpe2" && val.bytes.count >= 2 {
            let rawValue = (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1])
            return Double(rawValue) / 4.0
        }

        // Unsigned 8-bit
        if dt == "ui8" && val.bytes.count >= 1 {
            return Double(val.bytes[0])
        }

        // Unsigned 16-bit
        if dt == "ui16" && val.bytes.count >= 2 {
            let rawValue = (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1])
            return Double(rawValue)
        }

        // Unsigned 32-bit
        if dt == "ui32" && val.bytes.count >= 4 {
            let rawValue = UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 |
                           UInt32(val.bytes[2]) << 8 | UInt32(val.bytes[3])
            return Double(rawValue)
        }

        // Signed fixed-point 4.11
        if dt == "sp4b" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 2048.0
        }

        // Signed fixed-point 1.14
        if dt == "sp1e" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 16384.0
        }

        // Signed fixed-point 3.12
        if dt == "sp3c" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 4096.0
        }

        // Signed fixed-point 5.10
        if dt == "sp5a" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 1024.0
        }

        // Signed fixed-point 6.9
        if dt == "sp69" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 512.0
        }

        // Signed fixed-point 8.7
        if dt == "sp87" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue) / 128.0
        }

        // Unsigned fixed-point 8.8
        if dt == "fp88" && val.bytes.count >= 2 {
            let rawValue = (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1])
            return Double(rawValue) / 256.0
        }

        // Signed 8-bit
        if dt == "si8" && val.bytes.count >= 1 {
            return Double(Int8(bitPattern: val.bytes[0]))
        }

        // Signed 16-bit
        if dt == "si16" && val.bytes.count >= 2 {
            let rawValue = (Int16(val.bytes[0]) << 8) | Int16(val.bytes[1])
            return Double(rawValue)
        }

        // ioft - IOFixed float (native byte order)
        if dt == "ioft" && val.bytes.count >= 4 {
            let value = val.bytes.withUnsafeBufferPointer { ptr -> Float in
                ptr.baseAddress!.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
            }
            return Double(value)
        }

        return nil
    }

    func readTemperature(_ key: String) -> Double? {
        guard let val = readKey(key) else { return nil }
        return decodeValue(val)
    }

    func readFloat(_ key: String) -> Double? {
        guard let val = readKey(key) else { return nil }
        return decodeValue(val)
    }

    // MARK: - Fan Operations

    func getNumberOfFans() -> Int {
        guard let val = readKey("FNum") else {
            print("SMC: Could not read FNum")
            return 0
        }
        if let decoded = decodeValue(val) {
            let count = Int(decoded)
            print("SMC: Found \(count) fans")
            return count
        }
        if val.bytes.count >= 1 {
            let count = Int(val.bytes[0])
            print("SMC: Found \(count) fans (raw byte)")
            return count
        }
        return 0
    }

    func getFanCurrentSpeed(fanIndex: Int) -> Double? {
        let key = "F\(fanIndex)Ac"
        guard let val = readKey(key) else {
            print("SMC: \(key) readKey returned nil")
            return nil
        }
        let bytes = val.bytes.prefix(Int(val.dataSize)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let decoded = decodeValue(val)
        print("SMC: \(key) type=\(val.dataType) size=\(val.dataSize) bytes=[\(bytes)] → \(decoded as Any)")
        return decoded
    }

    func getFanMinSpeed(fanIndex: Int) -> Double? {
        let key = "F\(fanIndex)Mn"
        guard let val = readKey(key) else { return nil }
        return decodeValue(val)
    }

    func getFanMaxSpeed(fanIndex: Int) -> Double? {
        let key = "F\(fanIndex)Mx"
        return readFloat(key)
    }

    func getFanTargetSpeed(fanIndex: Int) -> Double? {
        let key = "F\(fanIndex)Tg"
        guard let val = readKey(key) else { return nil }
        return decodeValue(val)
    }

    func setFanMinSpeed(fanIndex: Int, speed: Double) -> Bool {
        guard let val = readKey("F\(fanIndex)Mn") else { return false }
        let bytes = encodeSpeed(speed, dataType: val.dataType)
        print("SMC: setFanMinSpeed(\(fanIndex), \(speed)) type=\(val.dataType) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        return writeKey("F\(fanIndex)Mn", bytes: bytes)
    }

    func setFanTargetSpeed(fanIndex: Int, speed: Double) -> Bool {
        guard let val = readKey("F\(fanIndex)Tg") else { return false }
        let bytes = encodeSpeed(speed, dataType: val.dataType)
        print("SMC: setFanTargetSpeed(\(fanIndex), \(speed)) type=\(val.dataType) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        return writeKey("F\(fanIndex)Tg", bytes: bytes)
    }

    private func encodeSpeed(_ speed: Double, dataType: String) -> [UInt8] {
        let dt = dataType.trimmingCharacters(in: .whitespaces)
        if dt == "flt" {
            // Native byte order float (little-endian on ARM)
            let floatVal = Float(speed)
            return withUnsafeBytes(of: floatVal) { Array($0) }
        } else {
            // fpe2 encoding
            let intSpeed = Int(speed)
            return [UInt8(intSpeed >> 6), UInt8((intSpeed << 2) ^ ((intSpeed >> 6) << 8))]
        }
    }

    func setFanMode(fanIndex: Int, mode: FanMode) -> Bool {
        // Try per-fan mode key first (Apple Silicon: F{n}Md)
        let modeKey = "F\(fanIndex)Md"
        if let _ = readKey(modeKey) {
            let modeBytes: [UInt8] = [UInt8(mode.rawValue)]
            let result = writeKey(modeKey, bytes: modeBytes)
            print("SMC: setFanMode(\(fanIndex), \(mode)) via F\(fanIndex)Md → \(result)")
            return result
        }

        // Fallback: FS! bitmask (Intel)
        let fsKey = "FS! "
        guard let val = readKey(fsKey) else {
            print("SMC: setFanMode — no F\(fanIndex)Md or FS! key found")
            return false
        }

        let currentMode = Int(decodeValue(val) ?? 0)
        var newMode: Int

        if mode == .forced {
            newMode = currentMode | (1 << fanIndex)
        } else {
            newMode = currentMode & ~(1 << fanIndex)
        }

        if val.dataSize == 2 {
            return writeKey(fsKey, bytes: [0x00, UInt8(newMode)])
        } else {
            return writeKey(fsKey, bytes: [UInt8(newMode)])
        }
    }

    func forceFanMode(manual: Bool) -> Bool {
        let numFans = getNumberOfFans()
        var success = true
        for i in 0..<numFans {
            if !setFanMode(fanIndex: i, mode: manual ? .forced : .automatic) {
                success = false
            }
        }
        return success
    }

    /// Test if SMC writes are permitted (returns true if writes work)
    func testWriteAccess() -> Bool {
        // Try to read and re-write FS! key (harmless — same value)
        if let val = readKey("FS! ") {
            let result = writeKey("FS! ", bytes: val.bytes.prefix(Int(val.dataSize)).map { $0 })
            print("SMC: Write access test (FS!): \(result ? "GRANTED" : "DENIED")")
            return result
        }
        // Try F0Md
        if let val = readKey("F0Md") {
            let result = writeKey("F0Md", bytes: val.bytes.prefix(Int(val.dataSize)).map { $0 })
            print("SMC: Write access test (F0Md): \(result ? "GRANTED" : "DENIED")")
            return result
        }
        print("SMC: Write access test: NO WRITABLE KEY FOUND")
        return false
    }

    func resetAllFansToAutomatic() {
        let numFans = getNumberOfFans()
        for i in 0..<numFans {
            _ = setFanMode(fanIndex: i, mode: .automatic)
        }
        // Also try resetting FS! directly
        let fsKey = "FS! "
        if let val = readKey(fsKey) {
            let zeros = [UInt8](repeating: 0, count: Int(val.dataSize))
            _ = writeKey(fsKey, bytes: zeros)
        }
    }

    // MARK: - Key Enumeration

    func getKeyCount() -> Int {
        guard let val = readKey("#KEY") else { return 0 }
        if val.bytes.count >= 4 {
            return Int(UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 |
                       UInt32(val.bytes[2]) << 8 | UInt32(val.bytes[3]))
        }
        return 0
    }

    func getKeyAtIndex(_ index: Int) -> String? {
        var inputData = SMCKeyData()
        inputData.data32 = UInt32(index)

        guard let result = callSMC(command: kSMCCmdGetKeyFromIndex, inputData: &inputData) else {
            return nil
        }

        return uint32ToString(result.key)
    }

    func getAllKeys() -> [String] {
        let count = getKeyCount()
        print("SMC: Total key count = \(count)")
        var keys: [String] = []
        for i in 0..<count {
            if let key = getKeyAtIndex(i) {
                keys.append(key)
            }
        }
        return keys
    }

    func discoverTemperatureKeys() -> [(key: String, value: Double, dataType: String)] {
        let allKeys = getAllKeys()
        var results: [(key: String, value: Double, dataType: String)] = []

        for key in allKeys {
            // Temperature keys typically start with T
            guard key.hasPrefix("T") else { continue }
            guard let val = readKey(key) else { continue }
            guard let decoded = decodeValue(val) else { continue }
            // Filter reasonable temperature values
            if decoded > -40 && decoded < 200 && decoded != 0 {
                results.append((key: key, value: decoded, dataType: val.dataType))
            }
        }

        print("SMC: Discovered \(results.count) temperature sensors")
        return results
    }

    func discoverFanKeys() -> [(key: String, value: Double, dataType: String)] {
        let allKeys = getAllKeys()
        var results: [(key: String, value: Double, dataType: String)] = []

        for key in allKeys {
            guard key.hasPrefix("F") else { continue }
            guard let val = readKey(key) else { continue }
            guard let decoded = decodeValue(val) else { continue }
            results.append((key: key, value: decoded, dataType: val.dataType))
        }

        print("SMC: Discovered \(results.count) fan-related keys")
        return results
    }

    func discoverVoltageKeys() -> [(key: String, value: Double, dataType: String)] {
        let allKeys = getAllKeys()
        var results: [(key: String, value: Double, dataType: String)] = []

        for key in allKeys {
            guard key.hasPrefix("V") else { continue }
            guard let val = readKey(key) else { continue }
            guard let decoded = decodeValue(val) else { continue }
            if decoded >= 0 && decoded < 100 {
                results.append((key: key, value: decoded, dataType: val.dataType))
            }
        }
        return results
    }

    func discoverCurrentKeys() -> [(key: String, value: Double, dataType: String)] {
        let allKeys = getAllKeys()
        var results: [(key: String, value: Double, dataType: String)] = []

        for key in allKeys {
            guard key.hasPrefix("I") else { continue }
            guard let val = readKey(key) else { continue }
            guard let decoded = decodeValue(val) else { continue }
            if decoded >= -50 && decoded < 100 {
                results.append((key: key, value: decoded, dataType: val.dataType))
            }
        }
        return results
    }

    func discoverPowerKeys() -> [(key: String, value: Double, dataType: String)] {
        let allKeys = getAllKeys()
        var results: [(key: String, value: Double, dataType: String)] = []

        for key in allKeys {
            guard key.hasPrefix("P") else { continue }
            guard let val = readKey(key) else { continue }
            guard let decoded = decodeValue(val) else { continue }
            if decoded >= 0 && decoded < 500 {
                results.append((key: key, value: decoded, dataType: val.dataType))
            }
        }
        return results
    }
}
