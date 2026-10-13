import Foundation
import SwiftUI
import Combine

// MARK: - App Log Entry

struct AppLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    var message: String
    /// Set when identical consecutive messages were collapsed into this entry.
    var repeatCount: Int?
    var lastSeen: Date?
    var baseMessage: String?
    
    init(level: LogLevel, category: LogCategory, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    var fullTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    var icon: String {
        switch level {
        case .error: return "🔴"
        case .warning: return "⚠️"
        case .success: return "✅"
        case .info: return "ℹ️"
        case .debug: return "🔍"
        case .network: return "🌐"
        case .upload: return "📤"
        case .bot: return "🚨"
        }
    }
    
    var color: Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return .blue
        case .debug: return .gray
        case .network: return .blue
        case .upload: return .purple
        case .bot: return .red
        }
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case error = "ERROR"
    case warning = "WARNING"
    case success = "SUCCESS"
    case info = "INFO"
    case debug = "DEBUG"
    case network = "NETWORK"
    case upload = "UPLOAD"
    case bot = "BOT"
}

enum LogCategory: String, Codable, CaseIterable {
    case general = "General"
    case upload = "Upload"
    case network = "Network"
    case api = "API"
    case cache = "Cache"
    case profile = "Profile"
    case bot = "Bot Detection"
    case device = "Device"
    case auth = "Auth"
}

// MARK: - Log Manager

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [AppLogEntry] = []
    
    private let maxLogs = 2000
    private let logRetentionDays = 7
    /// Identical consecutive messages within this window collapse into one entry.
    private let repeatCollapseWindow: TimeInterval = 600
    private var pendingSave: DispatchWorkItem?

    /// File-system path — no UserDefaults size limit
    private var logsFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("vault_logs.json")
    }

    private init() {
        // Remove the old oversized UserDefaults key to free space immediately
        UserDefaults.standard.removeObject(forKey: "app_logs")

        loadLogs()
        cleanOldLogs()

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let bundle = Bundle.main.bundleIdentifier ?? "?"
        log("App started — v\(version) (\(build)) \(bundle) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
            level: .info, category: .general)
        // Open the cold-start window so the SafetyGate blocks automatic API
        // calls during the first seconds after launch (if configured).
        InstagramSafetyGate.shared.markAppLaunch()

        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.pendingSave?.cancel()
            self?.saveLogs()
        }
    }
    
    // MARK: - Logging
    
    func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
        let entry = AppLogEntry(level: level, category: category, message: message)
        let urgent = level == .error || level == .warning || level == .bot
        
        DispatchQueue.main.async {
            if var last = self.logs.last,
               last.level == level, last.category == category,
               (last.baseMessage ?? last.message) == message,
               entry.timestamp.timeIntervalSince(last.lastSeen ?? last.timestamp) < self.repeatCollapseWindow {
                let count = (last.repeatCount ?? 1) + 1
                last.baseMessage = message
                last.repeatCount = count
                last.lastSeen = entry.timestamp
                last.message = "\(message) (×\(count), last \(entry.timeString))"
                self.logs[self.logs.count - 1] = last
            } else {
                self.logs.append(entry)
            }
            
            // Trim if too many
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
            
            self.scheduleSave(immediately: urgent)
        }
        
        // Also print to console for Xcode debugging
        print("\(entry.icon) [\(level.rawValue)] [\(category.rawValue)] \(message)")
    }

    /// Encoding 2000 entries on every line is wasteful; routine lines are batched,
    /// problems are written at once so they survive a crash right after.
    private func scheduleSave(immediately: Bool) {
        pendingSave?.cancel()
        guard !immediately else {
            pendingSave = nil
            saveLogs()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.saveLogs() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    
    // Convenience methods
    func error(_ message: String, category: LogCategory = .general) {
        log(message, level: .error, category: category)
    }
    
    func warning(_ message: String, category: LogCategory = .general) {
        log(message, level: .warning, category: category)
    }
    
    func success(_ message: String, category: LogCategory = .general) {
        log(message, level: .success, category: category)
    }
    
    func info(_ message: String, category: LogCategory = .general) {
        log(message, level: .info, category: category)
    }
    
    func debug(_ message: String, category: LogCategory = .general) {
        log(message, level: .debug, category: category)
    }
    
    func network(_ message: String) {
        log(message, level: .network, category: .network)
    }
    
    func upload(_ message: String) {
        log(message, level: .upload, category: .upload)
    }
    
    func bot(_ message: String) {
        log(message, level: .bot, category: .bot)
    }
    
    // MARK: - Persistence (file-system, no UserDefaults size limit)

    private func saveLogs() {
        guard let encoded = try? JSONEncoder().encode(logs) else { return }
        let url = logsFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: url, options: .atomic)
    }

    private func loadLogs() {
        guard let data = try? Data(contentsOf: logsFileURL),
              let decoded = try? JSONDecoder().decode([AppLogEntry].self, from: data) else {
            return
        }
        logs = decoded
    }
    
    private func cleanOldLogs() {
        let cutoffDate = Date().addingTimeInterval(-Double(logRetentionDays * 24 * 3600))
        logs.removeAll { $0.timestamp < cutoffDate }
        saveLogs()
    }
    
    // MARK: - Export
    
    func exportLogsAsText() -> String {
        let header = "=== Vault App Logs ===\nExported: \(Date())\nTotal Logs: \(logs.count)\n\n"
        
        let logLines = logs.map { entry in
            "[\(entry.fullTimeString)] [\(entry.level.rawValue)] [\(entry.category.rawValue)]\n\(entry.message)\n"
        }.joined(separator: "\n")
        
        return header + logLines
    }
    
    func clearAllLogs() {
        logs.removeAll()
        saveLogs()
        log("Logs cleared by user", level: .info, category: .general)
    }
    
    // MARK: - Filtering
    
    func filteredLogs(level: LogLevel? = nil, category: LogCategory? = nil, searchText: String = "") -> [AppLogEntry] {
        var filtered = logs
        
        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }
        
        if let category = category {
            filtered = filtered.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.message.lowercased().contains(searchText.lowercased())
            }
        }
        
        return filtered
    }
}
