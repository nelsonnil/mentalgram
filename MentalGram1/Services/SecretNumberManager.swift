import Foundation
import Combine
import UIKit

/// Manages the secret number input system via swipe gestures on the Instagram profile photo grid.
///
/// Usage:
/// - Swipe LEFT or RIGHT on the grid → registers one digit (based on which photo row the swipe started in)
///   AND switches to the next/previous tab (Posts ↔ Reels ↔ Tagged).
/// - Swipe UP or DOWN on the grid while the buffer has at least 1 digit → validates the number.
/// - After validation the buffer resets automatically.
///
/// Digit mapping (3-column square grid, cells 1:1):
///   Row 1  photos 1–3  → digits 1, 2, 3
///   Row 2  photos 4–6  → digits 4, 5, 6
///   Row 3  photos 7–9  → digits 7, 8, 9
///   Row 4+ any photo   → digit 0
class SecretNumberManager: ObservableObject {
    static let shared = SecretNumberManager()

    /// Up to 3 registered digits (not yet validated)
    @Published var digitBuffer: [Int] = []

    private init() {}

    var hasDigits: Bool { !digitBuffer.isEmpty }
    var isFull: Bool { digitBuffer.count >= 3 }

    /// String representation of the current buffer, e.g. "36" or "142"
    var bufferDisplay: String {
        digitBuffer.map { String($0) }.joined()
    }

    // MARK: - Buffer operations

    /// Register a digit (max 3 allowed). Emits a light haptic.
    func addDigit(_ digit: Int) {
        guard digitBuffer.count < 3 else { return }
        digitBuffer.append(digit)
        print("🔢 [SECRET#] Digit \(digit) added — buffer: \(bufferDisplay)")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Validate: returns the accumulated number, resets the buffer, emits medium haptic.
    func validateAndReset() -> Int? {
        guard !digitBuffer.isEmpty else { return nil }
        let number = digitBuffer.reduce(0) { $0 * 10 + $1 }
        print("🔢 [SECRET#] VALIDATED → \(number) (buffer was: \(bufferDisplay))")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        digitBuffer = []
        return number
    }

    func reset() {
        guard !digitBuffer.isEmpty else { return }
        digitBuffer = []
        print("🔢 [SECRET#] Buffer reset")
    }

    // MARK: - Digit from touch position

    /// Map the start position of a swipe (in grid-local coordinates) to a digit 1-9 or 0.
    /// - Parameters:
    ///   - x: Horizontal position within the grid
    ///   - y: Vertical position within the grid
    ///   - gridWidth: Full width of the 3-column grid (= screen width for full-bleed grids)
    static func digit(x: CGFloat, y: CGFloat, gridWidth: CGFloat) -> Int {
        let cellW = gridWidth / 3.0
        // Grid cells are 1:1 squares (PhotosGridView / ReelsGridView use aspectRatio(1)).
        // Add 1 pt for the row spacing configured on LazyVGrid.
        let cellH = cellW + 1.0
        let col = min(2, max(0, Int(x / cellW)))
        let row = max(0, Int(y / cellH))
        if row >= 3 { return 0 }
        return row * 3 + col + 1   // 1 … 9
    }

    // MARK: - Following count display helper

    /// Build the string to display in the "following" stat, overlaying the last N characters
    /// of the original count with the accumulated buffer digits.
    ///
    /// Example: original = 347, buffer = [8, 6]  →  "386"  (last 2 replaced)
    func followingDisplayString(originalCount: Int) -> String {
        let buffer = bufferDisplay
        guard !buffer.isEmpty else { return formatCount(originalCount) }
        let original = formatCount(originalCount)
        if buffer.count >= original.count {
            return buffer
        }
        let prefix = String(original.prefix(original.count - buffer.count))
        return prefix + buffer
    }

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
