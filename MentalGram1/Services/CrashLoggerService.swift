import Foundation
import UIKit
import Darwin

// MARK: - CrashLoggerService
//
// Installs low-level handlers for both Objective-C exceptions and POSIX signals
// so that any crash that kills the process is written to a JSON file in the
// app's Documents directory BEFORE the process dies.
//
// Also detects silent Jetsam/OOM kills via a "running" marker file written at
// startup and removed on clean exit.  If the marker is present at next launch
// the previous session was killed by the OS (likely OOM / watchdog) and a
// synthetic crash report is logged automatically.
//
// Usage:
//   1. Call CrashLoggerService.install() as early as possible at startup.
//   2. Call CrashLoggerService.checkAndLogPreviousSessionCrash() right after.
//   3. Call CrashLoggerService.markCleanExit() from applicationWillTerminate.

final class CrashLoggerService {

    static let shared = CrashLoggerService()
    private init() {}

    // MARK: - Public API

    /// Installs crash handlers and writes the "app is running" Jetsam marker.
    /// Must be called once, as early as possible at startup.
    static func install() {
        // Pre-compute crash-dir path as a C string so the signal handler can
        // use it without any Foundation allocation.
        if let dir = crashDirURL {
            var buf = [CChar](repeating: 0, count: 1024)
            dir.path.withCString { src in
                strlcpy(&buf, src, buf.count)
            }
            crashDirCString = buf
        }
        // Persist metadata once for the signal handler to read later.
        shared.writeMetadata()
        // OOM / Jetsam marker: written here, removed on clean exit.
        shared.writeRunningMarker()
        // ObjC uncaught-exception handler (full Foundation available).
        NSSetUncaughtExceptionHandler(objcExceptionHandler)
        // POSIX signal handlers (must be async-signal-safe).
        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE, SIGPIPE, SIGTRAP] {
            signal(sig, posixSignalHandler)
        }
    }

    /// Call immediately after install() to detect and log a previous-session
    /// Jetsam / OOM kill.  Must be called BEFORE writing a new running marker.
    static func checkAndLogPreviousSessionCrash() {
        guard let url = shared.runningMarkerURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        // The marker was not removed → previous run was killed abnormally.
        writeReport(
            type: "Jetsam/OOM",
            name: "Abnormal Termination",
            reason: "The app was killed by the OS without invoking any crash handler " +
                    "(most likely an out-of-memory kill or watchdog timeout).",
            stackTrace: "(Not available — process was killed by SIGKILL)"
        )
        // Marker will be overwritten by the new install() call.
    }

    /// Call from applicationWillTerminate so the next launch does not
    /// misinterpret a user-initiated kill as a Jetsam crash.
    static func markCleanExit() {
        shared.removeRunningMarker()
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
                      let report = try? JSONDecoder().decode(CrashReport.self, from: data)
                else { return nil }
                return report
            }
            .sorted { $0.date > $1.date }
    }

    /// Deletes all stored crash reports.
    func clearAll() {
        guard let dir = crashDir else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where name.hasSuffix(".json") || name.hasSuffix(".txt") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Internals

    private static let crashDirName    = "crash_logs"
    private static let metaFileName    = "crash_meta.json"
    private static let markerFileName  = "app_running.marker"
    private static let maxStoredReports = 20

    // Pre-computed crash-dir path as a C string buffer (populated at install() time).
    // Safe to read from a signal handler — no heap allocation required.
    static var crashDirCString: [CChar]? = nil

    static var crashDirURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = docs.appendingPathComponent(crashDirName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var crashDir: URL? { Self.crashDirURL }

    // MARK: - Jetsam / OOM marker

    private var runningMarkerURL: URL? {
        Self.crashDirURL?.appendingPathComponent(Self.markerFileName)
    }

    private func writeRunningMarker() {
        guard let url = runningMarkerURL else { return }
        try? "running".data(using: .utf8)?.write(to: url)
    }

    private func removeRunningMarker() {
        guard let url = runningMarkerURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Metadata (written before crash handlers fire)

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
            appVersion:  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            osVersion:   UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
        if let url = Self.metaURL, let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url)
        }
    }

    // MARK: - Writing a JSON report (Foundation-safe: ObjC handler + Jetsam detector)

    static func writeReport(type: String, name: String, reason: String, stackTrace: String) {
        var appVersion = "?"; var buildNumber = "?"; var osVersion = "?"; var deviceModel = "?"
        if let url = metaURL,
           let data = try? Data(contentsOf: url),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            appVersion  = meta.appVersion
            buildNumber = meta.buildNumber
            osVersion   = meta.osVersion
            deviceModel = meta.deviceModel
        }

        let now      = Date()
        let ts       = ISO8601DateFormatter().string(from: now)
        let fileName = "crash_\(Int(now.timeIntervalSince1970)).json"

        let report = CrashReport(
            id: fileName, date: now, timestamp: ts,
            type: type, name: name, reason: reason, stackTrace: stackTrace,
            appVersion: appVersion, buildNumber: buildNumber,
            osVersion: osVersion, deviceModel: deviceModel
        )

        if let dir = crashDirURL, let data = try? JSONEncoder().encode(report) {
            try? data.write(to: dir.appendingPathComponent(fileName))
        }
        pruneOldReports()
    }

    // MARK: - Writing a signal-safe text report (signal handler only)
    //
    // Uses only POSIX / Darwin calls that are async-signal-safe:
    //   open(), write(), close(), time(), strlcpy(), strlcat(),
    //   backtrace(), backtrace_symbols_fd()
    // No snprintf (variadic — unavailable in Swift), no Foundation, no ObjC.

    static func writeSignalReport(sigNum: Int32) {
        guard var dirBuf = crashDirCString else { return }

        // Build filename: <dir>/crash_<unix-timestamp>.txt
        // All operations use stack-allocated buffers — no malloc.
        var path = [CChar](repeating: 0, count: 1100)
        strlcpy(&path, &dirBuf, path.count)
        strlcat(&path, "/crash_", path.count)

        // Convert time_t to decimal digits without snprintf/Foundation.
        var tsDigits = [CChar](repeating: 0, count: 24)
        var v = Int(time(nil))
        if v <= 0 {
            tsDigits[0] = 48  // '0'
        } else {
            var tmp = [CChar](repeating: 0, count: 22)
            var i = 0
            while v > 0 {
                tmp[i] = CChar(48 + Int32(v % 10))
                v /= 10
                i += 1
            }
            // tmp holds digits in reverse order — flip them into tsDigits.
            for j in 0..<i { tsDigits[j] = tmp[i - 1 - j] }
        }
        strlcat(&path, &tsDigits, path.count)
        strlcat(&path, ".txt", path.count)

        let fd = open(&path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Helper: write a StaticString literal (async-signal-safe).
        func emit(_ s: StaticString) {
            s.withUTF8Buffer { buf in _ = Darwin.write(fd, buf.baseAddress!, buf.count) }
        }

        emit("===== CRASH REPORT (Signal) =====\nSignal: ")
        switch sigNum {
        case SIGABRT: emit("SIGABRT")
        case SIGSEGV: emit("SIGSEGV")
        case SIGILL:  emit("SIGILL")
        case SIGBUS:  emit("SIGBUS")
        case SIGFPE:  emit("SIGFPE")
        case SIGPIPE: emit("SIGPIPE")
        case SIGTRAP: emit("SIGTRAP")
        default:      emit("SIGUNKNOWN")
        }
        emit("\n\nStack Trace:\n")

        // backtrace + backtrace_symbols_fd are async-signal-safe on Darwin.
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let count  = backtrace(&frames, 64)
        backtrace_symbols_fd(&frames, count, fd)
        emit("\n=================================\n")
    }

    private static func pruneOldReports() {
        guard let dir = crashDirURL else { return }
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { ($0.hasSuffix(".json") || $0.hasSuffix(".txt")) && $0 != metaFileName && $0 != markerFileName }
            .sorted()
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
    let type: String        // "Exception" | "Signal" | "Jetsam/OOM"
    let name: String
    let reason: String
    let stackTrace: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String

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

// MARK: - ObjC Exception handler
// Runs on the crashing thread — full Foundation / ObjC runtime available.

private let objcExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    let stack = exception.callStackSymbols.joined(separator: "\n")
    CrashLoggerService.writeReport(
        type: "Exception",
        name: exception.name.rawValue,
        reason: exception.reason ?? "(no reason)",
        stackTrace: stack
    )
}

// MARK: - POSIX Signal handler
// MUST be async-signal-safe: no ObjC, no Foundation, no heap allocation.

private let posixSignalHandler: @convention(c) (Int32) -> Void = { sig in
    // writeSignalReport uses only async-signal-safe POSIX/Darwin calls.
    CrashLoggerService.writeSignalReport(sigNum: sig)
    // Re-raise with default handler so the OS generates its own crash report.
    signal(sig, SIG_DFL)
    raise(sig)
}
