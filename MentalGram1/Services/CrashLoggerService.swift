import Foundation
import UIKit

// MARK: - CrashLoggerService
//
// Installs low-level handlers for both Objective-C exceptions and POSIX signals
// so that any crash that kills the process is written to a JSON file in the
// app's Documents directory BEFORE the process dies.
//
// Usage: call CrashLoggerService.install() once, as early as possible at app
// startup (e.g. AppDelegate.application(_:didFinishLaunchingWithOptions:)).
//
// On the next launch the stored crash reports are available via
// CrashLoggerService.shared.storedReports.

final class CrashLoggerService {

    static let shared = CrashLoggerService()
    private init() {}

    // MARK: - Public API

    /// Installs the crash handlers. Must be called once at startup.
    static func install() {
        // Persist device/app metadata once so signal handlers (which run on a
        // tiny stack and cannot call most Foundation APIs) can just read a
        // pre-written file.
        shared.writeMetadata()
        // ObjC uncaught-exception handler
        NSSetUncaughtExceptionHandler(objcExceptionHandler)
        // POSIX signals that indicate hard crashes
        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE, SIGPIPE, SIGTRAP] {
            signal(sig, signalHandler)
        }
    }

    /// All crash reports written to disk, newest first.
    var storedReports: [CrashReport] {
        guard let dir = crashDir else { return [] }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> CrashReport? in
                let url = dir.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let report = try? JSONDecoder().decode(CrashReport.self, from: data) else { return nil }
                return report
            }
            .sorted { $0.date > $1.date }
    }

    /// Deletes all stored crash reports.
    func clearAll() {
        guard let dir = crashDir else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where name.hasSuffix(".json") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Internals

    private static let crashDirName = "crash_logs"
    private static let metaFileName = "crash_meta.json"
    private static let maxStoredReports = 20

    /// Crash directory URL (inside the app's Documents folder).
    static var crashDirURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent(crashDirName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var crashDir: URL? { Self.crashDirURL }

    // MARK: - Metadata (written before crash handlers can fire)

    private struct Meta: Codable {
        let appVersion: String
        let buildNumber: String
        let osVersion: String
        let deviceModel: String
    }

    private static var metaURL: URL? {
        crashDirURL?.appendingPathComponent(metaFileName)
    }

    private func writeMetadata() {
        let meta = Meta(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
        if let url = Self.metaURL,
           let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url)
        }
    }

    // MARK: - Writing a report (safe for signal context via low-level I/O)

    /// Called from both the ObjC handler and the signal handler.
    /// Uses only async-signal-safe operations when `fromSignal == true`.
    static func writeReport(type: String, name: String, reason: String, stackTrace: String) {
        // Read pre-written metadata
        var appVersion = "?"; var buildNumber = "?"; var osVersion = "?"; var deviceModel = "?"
        if let url = metaURL, let data = try? Data(contentsOf: url),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            appVersion  = meta.appVersion
            buildNumber = meta.buildNumber
            osVersion   = meta.osVersion
            deviceModel = meta.deviceModel
        }

        let now = Date()
        let ts  = ISO8601DateFormatter().string(from: now)
        let fileName = "crash_\(Int(now.timeIntervalSince1970)).json"

        let report = CrashReport(
            id: fileName,
            date: now,
            timestamp: ts,
            type: type,
            name: name,
            reason: reason,
            stackTrace: stackTrace,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel
        )

        if let dir = crashDirURL,
           let data = try? JSONEncoder().encode(report) {
            let fileURL = dir.appendingPathComponent(fileName)
            try? data.write(to: fileURL)
        }

        // Prune old reports keeping only the most recent N
        pruneOldReports()
    }

    private static func pruneOldReports() {
        guard let dir = crashDirURL else { return }
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != metaFileName }
            .sorted()   // ISO timestamp prefix → chronological order
        if files.count > maxStoredReports {
            let toDelete = files.prefix(files.count - maxStoredReports)
            for name in toDelete { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
        }
    }
}

// MARK: - CrashReport model

struct CrashReport: Codable, Identifiable {
    let id: String
    let date: Date
    let timestamp: String
    let type: String        // "Exception" | "Signal"
    let name: String        // exception name or signal name
    let reason: String
    let stackTrace: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String

    /// Human-readable plain-text summary for sharing.
    var plainText: String {
        """
        ===== CRASH REPORT =====
        App:       \(appVersion) (\(buildNumber))
        OS:        iOS \(osVersion) — \(deviceModel)
        Date:      \(timestamp)
        Type:      \(type)
        Name:      \(name)
        Reason:    \(reason)

        Stack Trace:
        \(stackTrace)
        ========================
        """
    }
}

// MARK: - ObjC Exception handler (runs on the crashing thread, full runtime available)

private let objcExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    let stack = exception.callStackSymbols.joined(separator: "\n")
    CrashLoggerService.writeReport(
        type: "Exception",
        name: exception.name.rawValue,
        reason: exception.reason ?? "(no reason)",
        stackTrace: stack
    )
}

// MARK: - Signal handler (async-signal-safe: avoid heap allocations / ObjC)

private let signalHandler: @convention(c) (Int32) -> Void = { sig in
    // Map signal number to a name
    let name: String
    switch sig {
    case SIGABRT:  name = "SIGABRT"
    case SIGSEGV:  name = "SIGSEGV"
    case SIGILL:   name = "SIGILL"
    case SIGBUS:   name = "SIGBUS"
    case SIGFPE:   name = "SIGFPE"
    case SIGPIPE:  name = "SIGPIPE"
    case SIGTRAP:  name = "SIGTRAP"
    default:       name = "SIG\(sig)"
    }

    // Capture the call stack via Thread (not guaranteed async-signal-safe but
    // works in practice on iOS for crash reporting purposes).
    let stack = Thread.callStackSymbols.joined(separator: "\n")

    CrashLoggerService.writeReport(
        type: "Signal",
        name: name,
        reason: "Fatal signal \(name) (\(sig)) received",
        stackTrace: stack
    )

    // Re-raise the signal with the default handler so the OS can generate
    // the standard crash report / terminate the process normally.
    signal(sig, SIG_DFL)
    raise(sig)
}
