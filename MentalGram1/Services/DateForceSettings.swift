import Foundation
import Combine

// MARK: - Date Force Settings
// "El Oráculo Social": forces followers/following counts on any Explore post
// to match the current date+time after subtracting audience spectators' counts.
//
// Metrics:
//   dual/auto date group → uses rawFollowerCount  (seguidores del espectador)
//   dual/auto time group → uses rawFollowingCount (seguidos del espectador)
//
// Split logic:
//   auto → exactly autoSpectatorCount/2 each group (selector: 2, 4, 6, 8)
//   dual → first count/2 spectators → date; remaining → time (dynamic, no preset)

enum DateForceMode: String, CaseIterable {
    case dual = "dual"  // Manual: magician visits spectator profiles in Explore
    case auto = "auto"  // Automatic: app fetches latest followers via API
}

enum DateForceFormat: String, CaseIterable {
    case ddmm = "DD/MM"
    case mmdd = "MM/DD"
    var displayName: String { rawValue }
}

struct DateForceSpectator: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let rawFollowerCount: Int   // seguidores — date group metric
    let rawFollowingCount: Int  // seguidos   — time group metric
    let group: DateForceGroup
}

enum DateForceGroup: String {
    case date = "date"
    case time = "time"
}

class DateForceSettings: ObservableObject {
    static let shared = DateForceSettings()

    // MARK: - Persisted

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "dateForce_enabled") }
    }

    @Published var mode: DateForceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "dateForce_mode") }
    }

    @Published var dateFormat: DateForceFormat {
        didSet { UserDefaults.standard.set(dateFormat.rawValue, forKey: "dateForce_format") }
    }

    /// Minutes added to the current time before calculating the override.
    @Published var timeOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(timeOffsetMinutes, forKey: "dateForce_timeOffset") }
    }

    /// Auto mode: total spectators to capture. Must be even (2, 4, 6, 8).
    /// Half go to date group, half to time group.
    @Published var autoSpectatorCount: Int {
        didSet { UserDefaults.standard.set(autoSpectatorCount, forKey: "dateForce_autoCount") }
    }

    // MARK: - Runtime (not persisted)

    @Published private(set) var spectators: [DateForceSpectator] = []

    /// Auto mode: which group is currently displayed in PerformanceView.
    @Published var autoDisplayGroup: DateForceGroup = .date

    /// Auto mode: true while fetching recent followers + their counts.
    @Published var isAutoLoading: Bool = false

    private var autoExpectedTotal: Int = 0

    // MARK: - Init

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "dateForce_enabled")

        // Migrate legacy modes (simple → dual, mixed → dual)
        let modeStr = UserDefaults.standard.string(forKey: "dateForce_mode") ?? DateForceMode.dual.rawValue
        if modeStr == "simple" || modeStr == "mixed" {
            self.mode = .dual
        } else {
            self.mode = DateForceMode(rawValue: modeStr) ?? .dual
        }

        let fmtStr = UserDefaults.standard.string(forKey: "dateForce_format") ?? DateForceFormat.ddmm.rawValue
        self.dateFormat = DateForceFormat(rawValue: fmtStr) ?? .ddmm

        let savedOffset = UserDefaults.standard.object(forKey: "dateForce_timeOffset") as? Int
        self.timeOffsetMinutes = savedOffset ?? 0

        // Migrate legacy autoMaxFollowers to autoSpectatorCount (must be even, max 8)
        let savedCount = UserDefaults.standard.object(forKey: "dateForce_autoCount") as? Int
                      ?? UserDefaults.standard.object(forKey: "dateForce_autoMax") as? Int
        let validCounts = [2, 4, 6, 8]
        if let c = savedCount, validCounts.contains(c) {
            self.autoSpectatorCount = c
        } else {
            self.autoSpectatorCount = 4
        }
    }

    // MARK: - Spectator Management (Dual mode — manual registration)

    func addSpectator(username: String, followingCount: Int, followerCount: Int) {
        // Group is assigned by position at registration time for display purposes.
        // sumDate / sumTime recalculate dynamically from position anyway.
        let group = nextDualGroup()
        let spectator = DateForceSpectator(
            username: username,
            rawFollowerCount: followerCount,
            rawFollowingCount: followingCount,
            group: group
        )
        spectators.append(spectator)
        print("🎯 [DATE FORCE] @\(username) followers=\(followerCount) following=\(followingCount) → \(group.rawValue) (total: \(spectators.count))")
    }

    func removeLastSpectator() {
        guard let last = spectators.last else { return }
        spectators.removeLast()
        print("🎯 [DATE FORCE] Removed: @\(last.username) (total: \(spectators.count))")
    }

    func removeSpectator(id: UUID) {
        spectators.removeAll { $0.id == id }
    }

    func resetSpectators() {
        spectators.removeAll()
        autoDisplayGroup = .date
        print("🎯 [DATE FORCE] All spectators reset")
    }

    // MARK: - Auto Mode (API-based capture)

    func beginAutoLoad(totalExpected: Int) {
        spectators.removeAll()
        autoDisplayGroup = .date
        autoExpectedTotal = totalExpected
        let half = totalExpected / 2
        print("🤖 [AUTO] Begin load — expecting \(totalExpected) (date: \(half), time: \(totalExpected - half))")
    }

    func appendAutoSpectator(username: String, followingCount: Int, followerCount: Int) {
        let index = spectators.count
        let half = autoExpectedTotal / 2
        let group: DateForceGroup = index < half ? .date : .time
        let s = DateForceSpectator(
            username: username,
            rawFollowerCount: followerCount,
            rawFollowingCount: followingCount,
            group: group
        )
        spectators.append(s)
        print("🤖 [AUTO] [\(index + 1)/\(autoExpectedTotal)] @\(username) followers=\(followerCount) following=\(followingCount) → \(group.rawValue)")
    }

    func toggleAutoDisplayGroup() {
        autoDisplayGroup = autoDisplayGroup == .date ? .time : .date
    }

    // MARK: - Group Assignment (Dual)

    /// Assigns group at registration time based on current count.
    /// The actual split for calculation is always recomputed dynamically.
    private func nextDualGroup() -> DateForceGroup {
        let dateCount = spectators.count / 2
        let currentDate = spectators.filter { $0.group == .date }.count
        return currentDate < max(1, dateCount) ? .date : .time
    }

    // MARK: - Effective group by position (for display in dual mode)

    func effectiveGroup(at index: Int) -> DateForceGroup {
        guard mode == .dual else {
            return spectators[safe: index]?.group ?? .date
        }
        let half = spectators.count / 2
        return index < half ? .date : .time
    }

    // MARK: - Date/Time Targets

    private var adjustedDate: Date {
        Date().addingTimeInterval(Double(timeOffsetMinutes) * 60)
    }

    var targetDate: Int {
        let cal = Calendar.current
        let date = adjustedDate
        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        switch dateFormat {
        case .ddmm: return day * 100 + month
        case .mmdd: return month * 100 + day
        }
    }

    var targetTime: Int {
        let cal = Calendar.current
        let date = adjustedDate
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        return hour * 100 + minute
    }

    // MARK: - Sums
    // dual: split by position — first half uses followerCount (date), rest uses followingCount (time)
    // auto: split by group property assigned during progressive load

    var sumDate: Int {
        switch mode {
        case .dual:
            let half = spectators.count / 2
            return spectators.prefix(half).reduce(0) { $0 + $1.rawFollowerCount }
        case .auto:
            return spectators.filter { $0.group == .date }.reduce(0) { $0 + $1.rawFollowerCount }
        }
    }

    var sumTime: Int {
        switch mode {
        case .dual:
            let half = spectators.count / 2
            return spectators.dropFirst(half).reduce(0) { $0 + $1.rawFollowingCount }
        case .auto:
            return spectators.filter { $0.group == .time }.reduce(0) { $0 + $1.rawFollowingCount }
        }
    }

    // MARK: - Override Values

    var overrideFollowers: Int { targetDate + sumDate }
    var overrideFollowing: Int { targetTime + sumTime }

    // MARK: - Display Helpers

    static func formatExact(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    var previewDateString: String {
        let n = targetDate
        return String(format: "%02d/%02d", n / 100, n % 100)
    }

    var previewTimeString: String {
        let t = targetTime
        return String(format: "%02d:%02d", t / 100, t % 100)
    }

    var hasSpectators: Bool { !spectators.isEmpty }

    /// Readable summary of the current split for Auto mode UI.
    var autoSplitDescription: String {
        let half = autoSpectatorCount / 2
        return "📅 \(half) for date  ·  🕐 \(half) for time"
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
