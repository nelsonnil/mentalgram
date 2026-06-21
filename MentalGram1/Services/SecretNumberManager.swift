import Foundation
import Combine
import UIKit

// MARK: - Swipe Direction

/// Four cardinal swipe directions used for digit pair encoding.
enum SwipeDir: Equatable, CustomStringConvertible {
    case up, down, left, right
    var description: String {
        switch self { case .up: return "↑"; case .down: return "↓"; case .left: return "←"; case .right: return "→" }
    }
}

/// Manages the secret number input system via directional swipe gestures on the Instagram grid.
///
/// ## Encoding
/// Each digit 0–9 is encoded as **two consecutive swipes**:
///
///   0 = ↑↑   1 = ↑→   2 = →↑   3 = →→   4 = →↓
///   5 = ↓→   6 = ↓↓   7 = ↓←   8 = ←↓   9 = ←←
///
/// After completing each pair the digit is appended to the buffer.
/// A **long press** on the grid commits the buffer and triggers the reveal.
/// There is no upper limit on the number of digits that can be accumulated.
///
/// ## Feedback
/// - First swipe of a pair  → light haptic
/// - Valid pair decoded      → medium haptic + digit stored
/// - Invalid pair            → warning haptic, second swipe becomes new first
/// - Long-press / commit     → heavy haptic
class SecretNumberManager: ObservableObject {
    static let shared = SecretNumberManager()

    /// Completed digits waiting to be committed.
    @Published var digitBuffer: [Int] = []

    /// First swipe of the current pair (nil = waiting for first swipe).
    @Published var pendingDir: SwipeDir? = nil

    private init() {}

    var hasDigits: Bool  { !digitBuffer.isEmpty }
    var hasPending: Bool { pendingDir != nil }

    /// String of accumulated digits, e.g. "506" or "42".
    var bufferDisplay: String {
        digitBuffer.map { String($0) }.joined()
    }

    // MARK: - Swipe pair decoding

    /// Decode two consecutive swipe directions into a digit 0–9, or nil for invalid pairs.
    static func decodeDigit(_ a: SwipeDir, _ b: SwipeDir) -> Int? {
        switch (a, b) {
        case (.up,    .up):    return 0
        case (.up,    .right): return 1
        case (.right, .up):    return 2
        case (.right, .right): return 3
        case (.right, .down):  return 4
        case (.down,  .right): return 5
        case (.down,  .down):  return 6
        case (.down,  .left):  return 7
        case (.left,  .down):  return 8
        case (.left,  .left):  return 9
        default:               return nil
        }
    }

    // MARK: - Card Clock Input

    /// Raw swipe buffer for the card clock system (max 3: 2 for value + 1 for suit).
    @Published var cardSwipeBuffer: [SwipeDir] = []

    var hasCardInput:    Bool { !cardSwipeBuffer.isEmpty }
    var cardInputFull:   Bool { cardSwipeBuffer.count == 3 }

    /// Decode a value swipe-pair into a card face string (A,2–9,10,J,Q,K), or nil if invalid.
    ///
    ///  Clock face mapping:
    ///   A=↑→  2=→↑  3=→→  4=→↓  5=↓→  6=↓↓  7=↓←  8=←↓  9=←←
    ///   10=←↑  J=↑←  Q=↑↑  K=↑↓
    static func decodeCardValue(_ a: SwipeDir, _ b: SwipeDir) -> String? {
        switch (a, b) {
        case (.up,    .right): return "A"
        case (.right, .up):    return "2"
        case (.right, .right): return "3"
        case (.right, .down):  return "4"
        case (.down,  .right): return "5"
        case (.down,  .down):  return "6"
        case (.down,  .left):  return "7"
        case (.left,  .down):  return "8"
        case (.left,  .left):  return "9"
        case (.left,  .up):    return "10"
        case (.up,    .left):  return "J"
        case (.up,    .up):    return "Q"
        case (.up,    .down):  return "K"
        default:               return nil
        }
    }

    /// Decode a single suit swipe into a suit symbol.
    ///   ↑=♠  →=♥  ↓=♣  ←=♦
    static func decodeSuit(_ dir: SwipeDir) -> String {
        switch dir {
        case .up:    return "♠"
        case .right: return "♥"
        case .down:  return "♣"
        case .left:  return "♦"
        }
    }

    /// Full card symbol if all 3 swipes are present and valid, e.g. "J♠".
    var decodedCard: String? {
        guard cardSwipeBuffer.count == 3,
              let val = Self.decodeCardValue(cardSwipeBuffer[0], cardSwipeBuffer[1]) else { return nil }
        let suit = Self.decodeSuit(cardSwipeBuffer[2])
        return "\(val)\(suit)"
    }

    /// Text to overlay on the following counter while the user enters a card.
    ///  0 swipes → nil
    ///  1 swipe  → "·"    (waiting for 2nd value swipe)
    ///  2 swipes → "Q·"   (value decoded, waiting for single suit swipe)
    ///  3 swipes → "Q♣"   (complete card)
    var cardDisplayString: String? {
        switch cardSwipeBuffer.count {
        case 0: return nil
        case 1: return "·"
        case 2:
            let val = Self.decodeCardValue(cardSwipeBuffer[0], cardSwipeBuffer[1]) ?? "?"
            return "\(val)·"
        case 3:
            return decodedCard ?? "?"
        default: return nil
        }
    }

    /// Record one directional swipe into the card clock buffer.
    ///
    /// Phase 1 (swipes 1-2): value pair — 13 valid combinations (A–K clock face).
    /// Phase 2 (swipe 3):    single suit swipe — ↑=♠ →=♥ ↓=♣ ←=♦ (always valid).
    ///
    /// On an invalid value pair the buffer resets and the invalid swipe starts a new attempt.
    func addCardSwipe(_ dir: SwipeDir) {
        let idx = cardSwipeBuffer.count

        switch idx {
        case 0:
            // First value swipe — accept any direction
            cardSwipeBuffer.append(dir)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            print("🃏 [CARD] Value swipe 1: \(dir)")

        case 1:
            // Second value swipe — decode the pair
            if Self.decodeCardValue(cardSwipeBuffer[0], dir) != nil {
                cardSwipeBuffer.append(dir)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                print("🃏 [CARD] Value: \(cardDisplayString ?? "?")")
            } else {
                // Invalid value pair → restart with this swipe as new first
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                cardSwipeBuffer = [dir]
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                print("🃏 [CARD] Invalid value pair — restarting with \(dir)")
            }

        case 2:
            // Single suit swipe — any direction is valid (↑=♠ →=♥ ↓=♣ ←=♦)
            cardSwipeBuffer.append(dir)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            print("🃏 [CARD] Card complete: \(decodedCard ?? "?")")

        default:
            // Buffer full — ignore until committed
            break
        }
    }

    // MARK: - Input

    /// Record one swipe. Each valid pair (2 swipes) commits a digit to the buffer.
    func addSwipe(_ dir: SwipeDir) {
        if let first = pendingDir {
            if let digit = Self.decodeDigit(first, dir) {
                // Valid pair → digit decoded
                pendingDir = nil
                digitBuffer.append(digit)
                print("🔢 [SECRET#] \(first)\(dir) → \(digit)  buffer: \(bufferDisplay)")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                // Invalid pair — start fresh; the second swipe becomes the new first
                print("🔢 [SECRET#] Invalid pair \(first)\(dir) — restarting")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDir = dir
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            // First swipe of a new pair
            pendingDir = dir
            print("🔢 [SECRET#] First: \(dir) — waiting for second")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        updateFollowingOverrides()
    }

    /// Direct digit injection (used by LockscreenInputView and other non-swipe sources).
    func addDigit(_ digit: Int) {
        digitBuffer.append(digit)
        print("🔢 [SECRET#] Digit \(digit) added — buffer: \(bufferDisplay)")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Validate: returns the number represented by the buffer, then resets.
    @discardableResult
    func validateAndReset() -> Int? {
        guard !digitBuffer.isEmpty else { return nil }
        let number = digitBuffer.reduce(0) { $0 * 10 + $1 }
        print("🔢 [SECRET#] VALIDATED → \(number)  (was: \(bufferDisplay))")
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        digitBuffer = []
        pendingDir  = nil
        return number
    }

    func reset() {
        guard !digitBuffer.isEmpty || pendingDir != nil || !cardSwipeBuffer.isEmpty else { return }
        digitBuffer     = []
        pendingDir      = nil
        cardSwipeBuffer = []
        print("🔢 [SECRET#] Buffer reset")
    }

    // MARK: - Following count display helper

    /// Overlay the last N characters of the original "following" count string with the
    /// current buffer digits, so the spectator sees a gradually replacing number.
    func followingDisplayString(originalCount: Int) -> String {
        let buffer = bufferDisplay
        guard !buffer.isEmpty else { return formatCount(originalCount) }
        let original = formatCount(originalCount)
        if buffer.count >= original.count { return buffer }
        let prefix = String(original.prefix(original.count - buffer.count))
        return prefix + buffer
    }

    // MARK: - Notification helpers

    /// Called after every `addSwipe` so observers can refresh count overlays.
    private func updateFollowingOverrides() {
        // Actual UI update is performed by PerformanceView / UserProfileView
        // via `.onChange(of: secretManager.digitBuffer)` or direct call.
        // This is a no-op hook left for future centralisation.
    }

    // MARK: - Legacy position-based digit helper (kept for backward compatibility)

    /// Map swipe-start position inside the 3-column photo grid to a digit.
    /// Row 1 → 1–3, Row 2 → 4–6, Row 3 → 7–9, Row 4+ → 0.
    static func digit(
        x: CGFloat,
        y: CGFloat,
        gridWidth: CGFloat,
        cellAspectRatio: CGFloat = 1.0,
        spacing: CGFloat = 1.0
    ) -> Int {
        let cellW = gridWidth / 3.0
        let cellH = (cellW / max(cellAspectRatio, 0.1)) + spacing
        let col = min(2, max(0, Int(x / cellW)))
        let row = max(0, Int(y / cellH))
        if row >= 3 { return 0 }
        return row * 3 + col + 1
    }

    // MARK: - Formatting

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1f M", Double(n) / 1_000_000)
                .replacingOccurrences(of: ".", with: ",")
        } else if n >= 1_000 {
            return String(format: "%.1f K", Double(n) / 1_000)
                .replacingOccurrences(of: ".", with: ",")
        }
        return String(n)
    }
}
