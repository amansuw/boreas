import SwiftUI

struct DebugView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var autoScroll = true
    @State private var filterText = ""

    var filteredLogs: [LogManager.LogEntry] {
        if filterText.isEmpty { return logManager.logs }
        return logManager.logs.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Log")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("\(logManager.logs.count) entries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button(action: { logManager.clear() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            // Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button(action: { filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            // Log entries
            ScrollViewReader { proxy in
                List(filteredLogs) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.timeString)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(entry.level.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(levelColor(entry.level))
                            .frame(width: 40)

                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .id(entry.id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                .onChange(of: logManager.logs.count) { _, _ in
                    if autoScroll, let last = filteredLogs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func levelColor(_ level: LogManager.LogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .warn: return .yellow
        case .error: return .red
        case .debug: return .gray
        }
    }
}
