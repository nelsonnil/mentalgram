import Foundation
import SwiftUI

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    
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
    
    @Published var logs: [LogEntry] = []
    
    private let maxLogs = 1000
    private let logRetentionDays = 7
    private let logsKey = "app_logs"
    
    private init() {
        loadLogs()
        cleanOldLogs()
        
        // Log app start
        log("App started", level: .info, category: .general)
    }
    
    // MARK: - Logging
    
    func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
        let entry = LogEntry(level: level, category: category, message: message)
        
        DispatchQueue.main.async {
            self.logs.append(entry)
            
            // Trim if too many
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
            
            self.saveLogs()
        }
        
        // Also print to console for Xcode debugging
        print("\(entry.icon) [\(level.rawValue)] [\(category.rawValue)] \(message)")
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
    
    // MARK: - Persistence
    
    private func saveLogs() {
        guard let encoded = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(encoded, forKey: logsKey)
    }
    
    private func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: logsKey),
              let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else {
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
    
    func filteredLogs(level: LogLevel? = nil, category: LogCategory? = nil, searchText: String = "") -> [LogEntry] {
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
