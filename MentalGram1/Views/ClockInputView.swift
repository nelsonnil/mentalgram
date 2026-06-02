import SwiftUI
import UIKit

// MARK: - Digit Encoding
//
// SwipeDir and the digit-pair decoding are defined once in SecretNumberManager
// and shared here, so the encoding stays consistent across the grid input and
// this fullscreen clock input:
//   0 = ↑↑   1 = ↑→   2 = →↑   3 = →→   4 = →↓
//   5 = ↓→   6 = ↓↓   7 = ↓←   8 = ←↓   9 = ←←

// MARK: - Clock Input Mode

/// Whether the black clock screen captures a number (digit pairs) or a playing card
/// (value pair + suit pair). The mode is chosen by the active interface kind in
/// PerformanceView (Number Clock vs Card Clock).
enum ClockInputMode { case number, card }

// MARK: - ClockInputView

/// A completely black fullscreen overlay used to enter a number OR a playing card
/// through hidden swipe gestures. The screen simulates the device being off.
///
/// Number encoding (same as Digit Grid):
///   Each digit (0-9) = 2 consecutive swipes.
///   0=↑↑  1=↑→  2=→↑  3=→→  4=→↓  5=↓→  6=↓↓  7=↓←  8=←↓  9=←←
///   No digit-count limit. Swipe pairs, then long-press to confirm → onReveal([digits]).
///
/// Card encoding (same clock-face mapping as the grid card input):
///   4 swipes total = value pair (K=↑↑, A=↑→, 2=→↑, … J=←↑, Q=↑←) + suit pair
///   (↑↑=♠, →→=♥, ↓↓=♣, ←←=♦). Long-press confirms → onRevealCard("A♥").
///
/// After confirming, long-press again to dismiss.
struct ClockInputView: View {

    /// Capture mode. Defaults to number for existing call sites.
    var mode: ClockInputMode = .number

    /// Called with the digit array when the user long-presses to confirm (number mode).
    /// e.g. [3] for "3", [3,6,9] for "369", [4,2] for "42".
    let onReveal: ([Int]) -> Void

    /// Called with the card symbol (e.g. "A♥") when confirmed (card mode).
    var onRevealCard: ((String) -> Void)? = nil

    /// Called when the user long-presses after the reveal to dismiss.
    let onDismiss: () -> Void

    // ── Swipe buffer (number mode) ────────────────────────────────────────
    /// First swipe of the current in-progress pair (nil = waiting for 1st swipe).
    @State private var pendingSwipe: SwipeDir? = nil
    /// Completed digits accumulated so far.
    @State private var digitBuffer: [Int] = []
    /// True once onReveal has been called (long-press commits and sets this).
    @State private var revealed = false

    // ── Card buffer (card mode) ───────────────────────────────────────────
    /// Raw swipes accumulated for the card: value pair (idx 0-1) + suit pair (idx 2-3).
    @State private var cardSwipes: [SwipeDir] = []

    // Flash feedback: briefly dims screen on invalid swipe pair
    @State private var flashError = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)
                .opacity(flashError ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: flashError)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Swipe detection — each completed pair adds one digit
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    handleSwipe(swipeDirection(from: value))
                }
        )
        // Long press:
        //   • Before reveal  → commit whatever digits are buffered (≥1 digit required)
        //   • After reveal   → dismiss the overlay
        .onLongPressGesture(minimumDuration: 1.0) {
            if revealed {
                onDismiss()
            } else {
                commitBuffer()
            }
        }
    }

    // MARK: - Gesture direction

    private func swipeDirection(from value: DragGesture.Value) -> SwipeDir {
        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dy) >= abs(dx) {
            return dy < 0 ? .up : .down
        } else {
            return dx < 0 ? .left : .right
        }
    }

    // MARK: - Swipe processing

    private func handleSwipe(_ dir: SwipeDir) {
        // Ignore swipes once the value has already been committed
        guard !revealed else { return }

        if mode == .card {
            handleCardSwipe(dir)
            return
        }

        if let first = pendingSwipe {
            // Second swipe of a pair — try to decode
            pendingSwipe = nil
            if let digit = SecretNumberManager.decodeDigit(first, dir) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                digitBuffer.append(digit)
                print("🖤 [CLOCK-INPUT] pair \(first)\(dir) → digit \(digit)  buffer: \(digitBuffer.map(String.init).joined())")
            } else {
                // Invalid pair — error flash; treat second swipe as start of a new pair
                triggerErrorFlash()
                pendingSwipe = dir
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                print("🖤 [CLOCK-INPUT] invalid pair \(first)\(dir) — restarting with \(dir)")
            }
        } else {
            // First swipe of a new pair
            pendingSwipe = dir
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            print("🖤 [CLOCK-INPUT] first swipe \(dir) — waiting for second")
        }
    }

    // MARK: - Card swipe processing
    //
    // Phase 1 (swipes 1-2): value pair — one of the 12 valid card-value pairs.
    // Phase 2 (swipes 3-4): suit pair  — same direction twice.
    // Invalid pairs roll back and the offending swipe starts a new attempt.

    private func handleCardSwipe(_ dir: SwipeDir) {
        let idx = cardSwipes.count
        switch idx {
        case 0:
            cardSwipes.append(dir)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case 1:
            if SecretNumberManager.decodeCardValue(cardSwipes[0], dir) != nil {
                cardSwipes.append(dir)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                triggerErrorFlash()
                cardSwipes = [dir]
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case 2:
            cardSwipes.append(dir)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case 3:
            if dir == cardSwipes[2] {
                cardSwipes.append(dir)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                print("🖤 [CLOCK-INPUT] card complete: \(decodedCardSymbol ?? "?")")
            } else {
                triggerErrorFlash()
                cardSwipes = Array(cardSwipes.prefix(2)) + [dir]
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        default:
            break
        }
    }

    private var decodedCardSymbol: String? {
        guard cardSwipes.count == 4,
              let val  = SecretNumberManager.decodeCardValue(cardSwipes[0], cardSwipes[1]),
              let suit = SecretNumberManager.decodeSuit(cardSwipes[2], cardSwipes[3]) else { return nil }
        return "\(val)\(suit)"
    }

    // MARK: - Commit (long-press)

    private func commitBuffer() {
        if mode == .card {
            guard let symbol = decodedCardSymbol else {
                // Card not complete yet — gentle warning haptic
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            revealed = true
            print("📳 [CLOCK-INPUT] Committed card: \(symbol)")
            fireDoubleVibration()
            onRevealCard?(symbol)
            // Auto-dismiss after a brief pause so the user feels the confirmation
            // haptics before the black screen disappears — no second long press needed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onDismiss()
            }
            return
        }

        guard !digitBuffer.isEmpty else {
            // Nothing to commit yet — gentle warning haptic
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        // Discard any in-progress partial pair
        pendingSwipe = nil
        revealed = true
        let number = digitBuffer.reduce(0) { $0 * 10 + $1 }
        print("📳 [CLOCK-INPUT] Committed: \(number) — digits: \(digitBuffer)")
        fireDoubleVibration()
        onReveal(digitBuffer)
        // Auto-dismiss after a brief pause so the confirmation haptics complete
        // before the fake Instagram profile is revealed — no second long press needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onDismiss()
        }
    }

    // MARK: - Error flash

    private func triggerErrorFlash() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(.easeInOut(duration: 0.15)) { flashError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.15)) { flashError = false }
        }
    }

    // MARK: - Haptics

    private func fireDoubleVibration() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
