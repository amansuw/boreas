import Foundation
import Combine

class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: [LogEntry] = []
    private let maxLogs = 500
    private static var logCounter: Int = 0
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    struct LogEntry: Identifiable {
        let id: Int
        let timestamp: Date
        let message: String
        let level: Level

        enum Level: String {
            case info = "INFO"
            case warn = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
        }

        var timeString: String {
            LogManager.timeFormatter.string(from: timestamp)
        }
    }

    func log(_ message: String, level: LogEntry.Level = .info) {
        LogManager.logCounter += 1
        let entry = LogEntry(id: LogManager.logCounter, timestamp: Date(), message: message, level: level)
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
        // Also print to console
        print("[\(level.rawValue)] \(message)")
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
