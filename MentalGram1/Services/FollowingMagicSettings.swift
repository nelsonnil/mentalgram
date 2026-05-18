import Foundation
import Combine

class FollowingMagicSettings: ObservableObject {
    static let shared = FollowingMagicSettings()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "followingMagicEnabled") }
    }

    /// Duration of the countdown animation in seconds (fixed at 6).
    let countdownDuration: Int = 6

    /// Delay in seconds between the volume button press and the countdown starting (0–10).
    @Published var triggerDelay: Int {
        didSet { UserDefaults.standard.set(triggerDelay, forKey: "followingMagicTriggerDelay") }
    }

    /// Signal interference always enabled — glitch effect plays before countdown.
    let glitchEnabled: Bool = true

    /// When true, the glitch effect targets the "seguidores" (followers) stat instead of "seguidos" (following).
    @Published var targetFollowers: Bool {
        didSet { UserDefaults.standard.set(targetFollowers, forKey: "followingMagicTargetFollowers") }
    }

    /// When true, enables the "transfer illusion": deflates the searched profile then
    /// inflates own profile by the same amount when volume is pressed.
    @Published var transferEnabled: Bool {
        didSet { UserDefaults.standard.set(transferEnabled, forKey: "followingMagicTransferEnabled") }
    }

    /// The offset saved after deflating the searched profile, ready to inflate own profile.
    /// Persisted so it survives navigation back to Performance view.
    @Published var transferOffset: Int {
        didSet { UserDefaults.standard.set(transferOffset, forKey: "followingMagicTransferOffset") }
    }

    static let durationOptions = [2, 3, 4, 5]
    static let delayOptions = Array(0...10)

    /// True while the Transfer Effect inflation animation is running.
    /// Shared so PerformanceView's OCR handler can yield priority to the Transfer Effect.
    @Published var isTransferCounting: Bool = false

    /// The secret offset captured from the digit buffer when the user opens Explore.
    /// Not persisted — runtime only.
    @Published private(set) var pendingOffset: Int = 0

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "followingMagicEnabled")
        let savedDelay = UserDefaults.standard.object(forKey: "followingMagicTriggerDelay") as? Int
        self.triggerDelay = savedDelay ?? 0
        let savedTarget = UserDefaults.standard.object(forKey: "followingMagicTargetFollowers") as? Bool
        self.targetFollowers = savedTarget ?? false
        let savedTransfer = UserDefaults.standard.object(forKey: "followingMagicTransferEnabled") as? Bool
        self.transferEnabled = savedTransfer ?? false
        self.transferOffset = UserDefaults.standard.integer(forKey: "followingMagicTransferOffset")
    }

    /// Captures a digit sequence as the raw pending offset used by Counter Glitch.
    /// The raw input is kept untouched; the effective offset is computed later
    /// from the real profile count so K-mode is explicit and logged.
    @discardableResult
    func capture(digits: [Int], source: String) -> Int? {
        guard !digits.isEmpty else { return nil }
        let value = digits.reduce(0) { $0 * 10 + $1 }
        pendingOffset = min(100, max(1, value))
        let target = targetFollowers ? "followers" : "following"
        print("🎩 [MAGIC] Counter offset captured from \(source): \(pendingOffset) target:\(target)")
        LogManager.shared.info(
            "Counter offset captured source:\(source) target:\(target) offset:\(pendingOffset)",
            category: .profile
        )
        return pendingOffset
    }

    /// Captures the current digit buffer as the pending offset and resets the buffer.
    @discardableResult
    func captureFromBuffer(source: String = "grid") -> Int? {
        let buffer = SecretNumberManager.shared.digitBuffer
        let offset = capture(digits: buffer, source: source)
        if offset != nil {
            SecretNumberManager.shared.reset()
        }
        return offset
    }

    /// Converts the raw input into the effective animation offset.
    /// For large accounts, performers ask for 1-10 and input e.g. 06, which should
    /// display as 206K -> 200K. The stored input remains 6; only the effect uses 6000.
    func effectiveOffset(for realCount: Int, rawOffset: Int? = nil) -> Int {
        let input = rawOffset ?? pendingOffset
        guard input > 0 else { return 0 }
        if realCount >= 10_000 {
            return input * 1_000
        }
        return input
    }

    func offsetMode(for realCount: Int) -> String {
        realCount >= 10_000 ? "k" : "exact"
    }

    /// Clears the pending offset after the trick is revealed.
    func clear() {
        pendingOffset = 0
    }
}
