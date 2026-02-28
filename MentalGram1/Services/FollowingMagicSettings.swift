import Foundation
import Combine

class FollowingMagicSettings: ObservableObject {
    static let shared = FollowingMagicSettings()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "followingMagicEnabled") }
    }

    /// Duration of the countdown animation in seconds (2, 3, 4, or 5).
    @Published var countdownDuration: Int {
        didSet { UserDefaults.standard.set(countdownDuration, forKey: "followingMagicDuration") }
    }

    /// Delay in seconds between the volume button press and the countdown starting (0–10).
    @Published var triggerDelay: Int {
        didSet { UserDefaults.standard.set(triggerDelay, forKey: "followingMagicTriggerDelay") }
    }

    /// Show full-screen glitch/interference effect before the countdown starts.
    @Published var glitchEnabled: Bool {
        didSet { UserDefaults.standard.set(glitchEnabled, forKey: "followingMagicGlitch") }
    }

    static let durationOptions = [2, 3, 4, 5]
    static let delayOptions = Array(0...10)

    /// The secret offset captured from the digit buffer when the user opens Explore.
    /// Not persisted — runtime only.
    @Published private(set) var pendingOffset: Int = 0

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "followingMagicEnabled")
        let savedDuration = UserDefaults.standard.integer(forKey: "followingMagicDuration")
        self.countdownDuration = savedDuration > 0 ? savedDuration : 3
        let savedDelay = UserDefaults.standard.object(forKey: "followingMagicTriggerDelay") as? Int
        self.triggerDelay = savedDelay ?? 0
        let savedGlitch = UserDefaults.standard.object(forKey: "followingMagicGlitch") as? Bool
        self.glitchEnabled = savedGlitch ?? true
    }

    /// Captures the current digit buffer as the pending offset and resets the buffer.
    func captureFromBuffer() {
        let buffer = SecretNumberManager.shared.digitBuffer
        guard !buffer.isEmpty else { return }
        let value = buffer.reduce(0) { $0 * 10 + $1 }
        // Clamp to valid magic range 1–100
        pendingOffset = min(100, max(1, value))
        print("🎩 [MAGIC] Following offset captured: \(pendingOffset)")
        SecretNumberManager.shared.reset()
    }

    /// Clears the pending offset after the trick is revealed.
    func clear() {
        pendingOffset = 0
    }
}
