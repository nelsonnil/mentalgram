import Foundation
import UIKit
import Darwin
import os.log

// MARK: - CrashLoggerService
//
// Installs low-level handlers for both Objective-C exceptions and POSIX signals
// so that any crash that kills the process is written to disk BEFORE the process dies.
//
// Signal crashes are written as `.txt` (async-signal-safe). On the next launch they
// are converted to full `.json` CrashReports so Settings → Crash Logs always shows
// stack + device + diagnostics (not just "iPhone").
//
// Also detects silent Jetsam/OOM kills via a "running" marker file.
//
// Usage:
//   1. Call CrashLoggerService.checkAndLogPreviousSessionCrash() first.
//   2. Call CrashLoggerService.install() as early as possible.
//   3. Call CrashLoggerService.importPendingSignalReports() after install.
//   4. Call CrashLoggerService.markCleanExit() from applicationWillTerminate.

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
        // Persist metadata once for handlers / next-launch import to read.
        shared.writeMetadata()
        shared.writePlainMetadataForSignalHandler()
        shared.installMemoryWarningObserver()
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
            stackTrace: "(Not available — process was killed by SIGKILL)",
            includeRecentLogs: true
        )
        // Marker will be overwritten by the new install() call.
    }

    /// Converts raw `.txt` signal dumps from a previous crash into full `.json`
    /// reports (with app version, real device id, diagnostics, recent logs).
    /// Call once after `install()` on every launch.
    static func importPendingSignalReports() {
        guard let dir = crashDirURL else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where name.hasSuffix(".txt") && name.hasPrefix("crash_") {
            let url = dir.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else { continue }
            if let report = parseSignalTextReport(fileName: name, contents: raw) {
                if let data = try? JSONEncoder().encode(report) {
                    let jsonName = name.replacingOccurrences(of: ".txt", with: ".json")
                    try? data.write(to: dir.appendingPathComponent(jsonName), options: .atomic)
                }
            }
            try? fm.removeItem(at: url)
        }
        pruneOldReports()
    }

    /// Call from applicationWillTerminate so the next launch does not
    /// misinterpret a user-initiated kill as a Jetsam crash.
    static func markCleanExit() {
        shared.removeRunningMarker()
    }

    /// All crash reports written to disk, newest first.
    /// Includes `.json` reports and any leftover `.txt` signal dumps not yet imported.
    var storedReports: [CrashReport] {
        guard let dir = crashDir else { return [] }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var reports: [CrashReport] = []
        for name in files {
            let url = dir.appendingPathComponent(name)
            if name.hasSuffix(".json"), name.hasPrefix("crash_") {
                guard let data = try? Data(contentsOf: url),
                      let report = try? JSONDecoder().decode(CrashReport.self, from: data)
                else { continue }
                reports.append(report)
            } else if name.hasSuffix(".txt"), name.hasPrefix("crash_") {
                guard let raw = try? String(contentsOf: url, encoding: .utf8),
                      let report = Self.parseSignalTextReport(fileName: name, contents: raw)
                else { continue }
                reports.append(report)
            }
        }
        return reports.sorted { $0.date > $1.date }
    }

    /// Deletes all stored crash reports.
    func clearAll() {
        guard let dir = crashDir else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where name.hasSuffix(".json") || name.hasSuffix(".txt") {
            // Keep metadata helpers
            if name == Self.metaFileName || name == Self.plainMetaFileName || name == Self.markerFileName {
                continue
            }
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    func recordScreen(_ name: String) {
        updateDiagnostics(screen: name, action: nil)
    }

    func recordAction(_ action: String) {
        updateDiagnostics(screen: nil, action: action)
    }

    func recordLifecycle(_ phase: String) {
        updateDiagnostics(screen: nil, action: "lifecycle: \(phase)")
    }

    /// Human-readable export of every stored report (for testers to AirDrop / email).
    func exportAllAsText() -> String {
        let reports = storedReports
        guard !reports.isEmpty else {
            return "=== Vault Crash Logs ===\nNo crashes recorded.\n"
        }
        let header = "=== Vault Crash Logs ===\nExported: \(Date())\nCount: \(reports.count)\n\n"
        return header + reports.map(\.plainText).joined(separator: "\n\n")
    }

    // MARK: - Internals

    private static let crashDirName     = "crash_logs"
    private static let metaFileName     = "crash_meta.json"
    private static let plainMetaFileName = "crash_meta.txt"
    private static let markerFileName   = "app_running.marker"
    private static let maxStoredReports = 20
    private static let diagnosticsKey   = "crash_diagnostics_v1"

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

    // MARK: - Device identity

    /// Hardware machine id, e.g. `iPhone15,2` — never the useless generic "iPhone".
    static func hardwareMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    /// Marketing-ish label + machine id for crash reports.
    static func richDeviceModel() -> String {
        let machine = hardwareMachineIdentifier()
        let marketing = marketingName(for: machine)
        let generic = UIDevice.current.model // "iPhone" / "iPad"
        if let marketing {
            return "\(marketing) (\(machine))"
        }
        return "\(generic) (\(machine))"
    }

    private static func marketingName(for machine: String) -> String? {
        // Keep a short practical map — unknown ids still show the machine string.
        let map: [String: String] = [
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone 17 Air",
            "iPad13,18": "iPad", "iPad14,10": "iPad Air",
            "arm64": "Simulator"
        ]
        return map[machine]
    }

    private static func currentMemorySummary() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return "memory: unavailable" }
        let usedMB = Double(info.resident_size) / 1_048_576.0
        let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0
        return String(format: "memory: %.0f MB used / %.0f MB device", usedMB, totalMB)
    }

    // MARK: - Jetsam / OOM marker

    private var runningMarkerURL: URL? {
        Self.crashDirURL?.appendingPathComponent(Self.markerFileName)
    }

    private func writeRunningMarker() {
        guard let url = runningMarkerURL else { return }
        let payload = [
            "running",
            "ts=\(ISO8601DateFormatter().string(from: Date()))",
            "device=\(Self.richDeviceModel())",
            Self.currentMemorySummary()
        ].joined(separator: "\n")
        try? payload.data(using: .utf8)?.write(to: url)
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
        let deviceIdentifier: String
    }

    private static var metaURL: URL? {
        crashDirURL?.appendingPathComponent(metaFileName)
    }

    private static var plainMetaURL: URL? {
        crashDirURL?.appendingPathComponent(plainMetaFileName)
    }

    private func writeMetadata() {
        let machine = Self.hardwareMachineIdentifier()
        let meta = Meta(
            appVersion:  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            osVersion:   UIDevice.current.systemVersion,
            deviceModel: Self.richDeviceModel(),
            deviceIdentifier: machine
        )
        if let url = Self.metaURL, let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Plain ASCII meta file the signal handler can `open`/`read`/`write` safely.
    private func writePlainMetadataForSignalHandler() {
        guard let url = Self.plainMetaURL else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let text = """
        App: \(appVersion) (\(build))
        OS: iOS \(UIDevice.current.systemVersion)
        Device: \(Self.richDeviceModel())
        Machine: \(Self.hardwareMachineIdentifier())
        \(Self.currentMemorySummary())

        """
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private struct Diagnostics: Codable {
        var lastScreen: String?
        var lastAction: String?
        var lifecycle: String?
        var memoryWarningCount: Int
        var lastMemoryWarningAt: String?
        var updatedAt: String
        var recentActions: [String]

        var plainText: String {
            var lines: [String] = []
            lines.append("Last screen: \(lastScreen ?? "unknown")")
            lines.append("Last action: \(lastAction ?? "unknown")")
            lines.append("Lifecycle: \(lifecycle ?? "unknown")")
            lines.append("Memory warnings: \(memoryWarningCount)")
            lines.append("Last memory warning: \(lastMemoryWarningAt ?? "none")")
            lines.append("Diagnostics updated: \(updatedAt)")
            if !recentActions.isEmpty {
                lines.append("Recent actions:")
                lines.append(contentsOf: recentActions.suffix(12).map { "  - \($0)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func readDiagnostics() -> Diagnostics? {
        guard let data = UserDefaults.standard.data(forKey: diagnosticsKey) else { return nil }
        return try? JSONDecoder().decode(Diagnostics.self, from: data)
    }

    private static func recentAppLogSnippet(limit: Int = 25) -> String {
        // Best-effort — LogManager may not be ready during very early crashes.
        let entries = LogManager.shared.logs.suffix(limit)
        guard !entries.isEmpty else { return "Recent app logs: (none)" }
        var lines = ["Recent app logs (last \(entries.count)):"]
        for entry in entries {
            let msg = entry.message.replacingOccurrences(of: "\n", with: " ")
            let clipped = msg.count > 180 ? String(msg.prefix(180)) + "…" : msg
            lines.append("  [\(entry.fullTimeString)] [\(entry.level.rawValue)] \(clipped)")
        }
        return lines.joined(separator: "\n")
    }

    private func updateDiagnostics(screen: String?, action: String?) {
        var diagnostics = Self.readDiagnostics() ?? Diagnostics(
            lastScreen: nil,
            lastAction: nil,
            lifecycle: nil,
            memoryWarningCount: 0,
            lastMemoryWarningAt: nil,
            updatedAt: "",
            recentActions: []
        )
        let now = ISO8601DateFormatter().string(from: Date())
        if let screen { diagnostics.lastScreen = screen }
        if let action {
            diagnostics.lastAction = action
            diagnostics.recentActions.append("\(now) \(action)")
            if diagnostics.recentActions.count > 20 {
                diagnostics.recentActions.removeFirst(diagnostics.recentActions.count - 20)
            }
            if action.hasPrefix("lifecycle: ") {
                diagnostics.lifecycle = String(action.dropFirst("lifecycle: ".count))
            }
        }
        diagnostics.updatedAt = now
        if let data = try? JSONEncoder().encode(diagnostics) {
            UserDefaults.standard.set(data, forKey: Self.diagnosticsKey)
        }
    }

    private func installMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            var diagnostics = Self.readDiagnostics() ?? Diagnostics(
                lastScreen: nil,
                lastAction: nil,
                lifecycle: nil,
                memoryWarningCount: 0,
                lastMemoryWarningAt: nil,
                updatedAt: "",
                recentActions: []
            )
            let now = ISO8601DateFormatter().string(from: Date())
            diagnostics.memoryWarningCount += 1
            diagnostics.lastMemoryWarningAt = now
            diagnostics.lastAction = "memory warning"
            diagnostics.updatedAt = now
            diagnostics.recentActions.append("\(now) memory warning")
            if diagnostics.recentActions.count > 20 {
                diagnostics.recentActions.removeFirst(diagnostics.recentActions.count - 20)
            }
            if let data = try? JSONEncoder().encode(diagnostics) {
                UserDefaults.standard.set(data, forKey: Self.diagnosticsKey)
            }
            // Refresh plain meta so a subsequent Jetsam/signal dump has fresh memory info.
            CrashLoggerService.shared.writePlainMetadataForSignalHandler()
        }
    }

    // MARK: - Writing a JSON report (Foundation-safe: ObjC handler + Jetsam detector)

    static func writeReport(
        type: String,
        name: String,
        reason: String,
        stackTrace: String,
        includeRecentLogs: Bool = false
    ) {
        var appVersion = "?"; var buildNumber = "?"; var osVersion = "?"; var deviceModel = "?"
        var deviceIdentifier = Self.hardwareMachineIdentifier()
        if let url = metaURL,
           let data = try? Data(contentsOf: url),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            appVersion  = meta.appVersion
            buildNumber = meta.buildNumber
            osVersion   = meta.osVersion
            deviceModel = meta.deviceModel
            deviceIdentifier = meta.deviceIdentifier
        } else {
            deviceModel = richDeviceModel()
            osVersion = UIDevice.current.systemVersion
            appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        }

        let now      = Date()
        let ts       = ISO8601DateFormatter().string(from: now)
        let fileName = "crash_\(Int(now.timeIntervalSince1970)).json"

        var diagnosticsBlock = readDiagnostics()?.plainText ?? "Not available"
        diagnosticsBlock += "\n" + currentMemorySummary()
        // Never touch LogManager from a live crash handler (locks / ObjC runtime risk).
        // Safe on next-launch Jetsam/import paths.
        if includeRecentLogs {
            diagnosticsBlock += "\n" + recentAppLogSnippet()
        }

        let report = CrashReport(
            id: fileName, date: now, timestamp: ts,
            type: type, name: name, reason: reason, stackTrace: stackTrace,
            appVersion: appVersion, buildNumber: buildNumber,
            osVersion: osVersion, deviceModel: deviceModel,
            deviceIdentifier: deviceIdentifier,
            diagnostics: diagnosticsBlock
        )

        if let dir = crashDirURL, let data = try? JSONEncoder().encode(report) {
            try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        }
        pruneOldReports()
        os_log(.fault, "Vault crash recorded: %{public}@ — %{public}@", type, name)
    }

    // MARK: - Parse signal .txt → CrashReport

    static func parseSignalTextReport(fileName: String, contents: String) -> CrashReport? {
        let signalName = contents
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("Signal:") })
            .map { $0.replacingOccurrences(of: "Signal:", with: "").trimmingCharacters(in: .whitespaces) }
            ?? "SIGUNKNOWN"

        // Stack starts after "Stack Trace:" line.
        let stack: String
        if let range = contents.range(of: "Stack Trace:\n") {
            stack = String(contents[range.upperBound...])
                .replacingOccurrences(of: "\n=================================\n", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            stack = contents
        }

        // Prefer live meta; fall back to values embedded in the .txt header.
        var appVersion = "?"; var buildNumber = "?"; var osVersion = "?"; var deviceModel = "?"
        var deviceIdentifier = hardwareMachineIdentifier()
        if let url = metaURL,
           let data = try? Data(contentsOf: url),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            appVersion = meta.appVersion
            buildNumber = meta.buildNumber
            osVersion = meta.osVersion
            deviceModel = meta.deviceModel
            deviceIdentifier = meta.deviceIdentifier
        } else {
            // Parse "App: 1.0 (123)" etc. from the txt header written by the signal handler.
            for line in contents.split(separator: "\n").prefix(12) {
                let s = String(line)
                if s.hasPrefix("App: ") {
                    let rest = String(s.dropFirst(5))
                    if let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")") {
                        appVersion = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
                        buildNumber = String(rest[rest.index(after: open)..<close])
                    } else {
                        appVersion = rest
                    }
                } else if s.hasPrefix("OS: ") {
                    osVersion = s.replacingOccurrences(of: "OS: iOS ", with: "")
                        .replacingOccurrences(of: "OS: ", with: "")
                } else if s.hasPrefix("Device: ") {
                    deviceModel = String(s.dropFirst(8))
                } else if s.hasPrefix("Machine: ") {
                    deviceIdentifier = String(s.dropFirst(9))
                }
            }
            if deviceModel == "?" { deviceModel = richDeviceModel() }
        }

        // Timestamp from filename crash_<unix>.txt when possible.
        var date = Date()
        let stamp = fileName
            .replacingOccurrences(of: "crash_", with: "")
            .replacingOccurrences(of: ".txt", with: "")
        if let epoch = TimeInterval(stamp) {
            date = Date(timeIntervalSince1970: epoch)
        }

        var diagnosticsBlock = readDiagnostics()?.plainText ?? "Not available"
        diagnosticsBlock += "\n" + recentAppLogSnippet()

        return CrashReport(
            id: fileName.replacingOccurrences(of: ".txt", with: ".json"),
            date: date,
            timestamp: ISO8601DateFormatter().string(from: date),
            type: "Signal",
            name: signalName,
            reason: "Process terminated by \(signalName) (Swift fatalError / native crash / abort).",
            stackTrace: stack.isEmpty ? "(empty stack)" : stack,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
            deviceIdentifier: deviceIdentifier,
            diagnostics: diagnosticsBlock
        )
    }

    // MARK: - Writing a signal-safe text report (signal handler only)
    //
    // Uses only POSIX / Darwin calls that are async-signal-safe:
    //   open(), write(), close(), read(), time(), strlcpy(), strlcat(),
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

        emit("===== CRASH REPORT (Signal) =====\n")

        // Copy pre-written plain meta (App/OS/Device) — open/read/write are signal-safe.
        var metaPath = [CChar](repeating: 0, count: 1100)
        strlcpy(&metaPath, &dirBuf, metaPath.count)
        strlcat(&metaPath, "/crash_meta.txt", metaPath.count)
        let metaFd = open(&metaPath, O_RDONLY)
        if metaFd >= 0 {
            var buf = [UInt8](repeating: 0, count: 512)
            while true {
                let n = Darwin.read(metaFd, &buf, buf.count)
                if n <= 0 { break }
                _ = Darwin.write(fd, buf, n)
            }
            close(metaFd)
        }

        emit("Signal: ")
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
            .filter {
                ($0.hasSuffix(".json") || $0.hasSuffix(".txt"))
                && $0.hasPrefix("crash_")
            }
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
    /// Hardware id e.g. iPhone15,2 — optional for older on-disk reports.
    let deviceIdentifier: String?
    let diagnostics: String?

    init(
        id: String, date: Date, timestamp: String,
        type: String, name: String, reason: String, stackTrace: String,
        appVersion: String, buildNumber: String,
        osVersion: String, deviceModel: String,
        deviceIdentifier: String? = nil,
        diagnostics: String?
    ) {
        self.id = id
        self.date = date
        self.timestamp = timestamp
        self.type = type
        self.name = name
        self.reason = reason
        self.stackTrace = stackTrace
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.deviceIdentifier = deviceIdentifier
        self.diagnostics = diagnostics
    }

    var plainText: String {
        """
        ===== CRASH REPORT =====
        App:       \(appVersion) (\(buildNumber))
        OS:        iOS \(osVersion)
        Device:    \(deviceModel)
        Machine:   \(deviceIdentifier ?? "?")
        Date:      \(timestamp)
        Type:      \(type)
        Name:      \(name)
        Reason:    \(reason)

        Stack Trace:
        \(stackTrace)

        Diagnostics:
        \(diagnostics ?? "Not available")
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
        stackTrace: stack,
        includeRecentLogs: false
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
