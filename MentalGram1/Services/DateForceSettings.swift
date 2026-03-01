import Foundation
import Combine

// MARK: - Date Force Settings
// "El Oráculo Social": forces followers/following counts on any Explore post
// to match the current date+time after subtracting audience spectators' following counts.

enum DateForceMode: String, CaseIterable {
    case simple = "simple"  // All spectators → date group; time comes directly
    case dual   = "dual"    // First N → date group, rest → time group
}

enum DateForceFormat: String, CaseIterable {
    case ddmm = "DD/MM"
    case mmdd = "MM/DD"

    var displayName: String { rawValue }
}

struct DateForceSpectator: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let rawFollowingCount: Int
    let effectiveValue: Int
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

    /// How many spectators go to the date group (in dual mode).
    /// Spectators beyond this count go to the time group.
    @Published var dateGroupSize: Int {
        didSet { UserDefaults.standard.set(dateGroupSize, forKey: "dateForce_dateGroupSize") }
    }

    /// Minutes added to the current time before calculating the override.
    /// Compensates for the time spent building drama before the reveal.
    /// 0 = use exact current time.
    @Published var timeOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(timeOffsetMinutes, forKey: "dateForce_timeOffset") }
    }

    // MARK: - Runtime (not persisted)

    @Published private(set) var spectators: [DateForceSpectator] = []

    // MARK: - Init

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "dateForce_enabled")

        let modeStr = UserDefaults.standard.string(forKey: "dateForce_mode") ?? DateForceMode.dual.rawValue
        self.mode = DateForceMode(rawValue: modeStr) ?? .dual

        let fmtStr = UserDefaults.standard.string(forKey: "dateForce_format") ?? DateForceFormat.ddmm.rawValue
        self.dateFormat = DateForceFormat(rawValue: fmtStr) ?? .ddmm

        let saved = UserDefaults.standard.integer(forKey: "dateForce_dateGroupSize")
        self.dateGroupSize = saved > 0 ? saved : 2

        let savedOffset = UserDefaults.standard.object(forKey: "dateForce_timeOffset") as? Int
        self.timeOffsetMinutes = savedOffset ?? 0
    }

    // MARK: - Spectator Management

    func addSpectator(username: String, followingCount: Int) {
        let group = nextGroup()
        let effective = Self.effectiveValue(from: followingCount)
        let spectator = DateForceSpectator(
            username: username,
            rawFollowingCount: followingCount,
            effectiveValue: effective,
            group: group
        )
        spectators.append(spectator)
        print("🎯 [DATE FORCE] Spectator added: @\(username) following=\(followingCount) effective=\(effective) group=\(group.rawValue) (total: \(spectators.count))")
    }

    func removeLastSpectator() {
        guard let last = spectators.last else { return }
        spectators.removeLast()
        print("🎯 [DATE FORCE] Removed last spectator: @\(last.username) (total: \(spectators.count))")
    }

    func removeSpectator(id: UUID) {
        spectators.removeAll { $0.id == id }
    }

    func resetSpectators() {
        spectators.removeAll()
        print("🎯 [DATE FORCE] All spectators reset")
    }

    // MARK: - Group Assignment

    private func nextGroup() -> DateForceGroup {
        switch mode {
        case .simple:
            return .date
        case .dual:
            let dateCount = spectators.filter { $0.group == .date }.count
            return dateCount < dateGroupSize ? .date : .time
        }
    }

    // MARK: - Effective Value Extraction

    /// Converts a following count to the digits the magician will read aloud.
    /// < 1000: exact number (347 → 347)
    /// ≥ 1000: last 3 digits (1,247 → 247, 15,432 → 432)
    static func effectiveValue(from count: Int) -> Int {
        guard count >= 1000 else { return count }
        return count % 1000
    }

    // MARK: - Date/Time Targets (computed from current clock + optional offset)

    /// Current time adjusted by timeOffsetMinutes
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

    var sumDate: Int {
        spectators.filter { $0.group == .date }.reduce(0) { $0 + $1.effectiveValue }
    }

    var sumTime: Int {
        spectators.filter { $0.group == .time }.reduce(0) { $0 + $1.effectiveValue }
    }

    // MARK: - Override Values for Explore Post

    /// The followers count to display on the Explore post detail.
    /// Formula: targetDate + sumDate → spectator sees this, subtracts sumDate, gets the date.
    var overrideFollowers: Int {
        targetDate + sumDate
    }

    /// The following count to display on the Explore post detail.
    /// In dual mode: targetTime + sumTime
    /// In simple mode: targetTime directly (no audience math for time)
    var overrideFollowing: Int {
        switch mode {
        case .simple: return targetTime
        case .dual:   return targetTime + sumTime
        }
    }

    // MARK: - Display Helpers

    /// Format the override number for display (always exact, never K).
    /// Uses English locale so separator is always "," (matches Instagram).
    static func formatExact(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// Preview strings for the magician in Settings
    var previewDateString: String {
        let n = targetDate
        let first = n / 100
        let second = n % 100
        return String(format: "%02d/%02d", first, second)
    }

    var previewTimeString: String {
        let h = targetTime / 100
        let m = targetTime % 100
        return String(format: "%02d:%02d", h, m)
    }

    var hasSpectators: Bool { !spectators.isEmpty }
}
