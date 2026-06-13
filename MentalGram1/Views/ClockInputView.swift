import SwiftUI
import UIKit
import AVFoundation

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
///   No digit-count limit. Swipe pairs, then stop swiping for 3 seconds to confirm.
///
/// Card encoding (same clock-face mapping as the grid card input):
///   3 swipes total = value pair (A=↑→ 2=→↑ … 9=←← 10=←↑ J=↑← Q=↑↑ K=↑↓)
///   + single suit swipe (↑=♠ →=♥ ↓=♣ ←=♦).
///   After the third swipe, stop swiping for 3 seconds to confirm → onRevealCard("Q♣").
struct ClockInputView: View {

    /// Capture mode. Defaults to number for existing call sites.
    var mode: ClockInputMode = .number

    /// Called with the digit array when the inactivity timer confirms (number mode).
    /// e.g. [3] for "3", [3,6,9] for "369", [4,2] for "42".
    let onReveal: ([Int]) -> Void

    /// Called with the card symbol (e.g. "A♥") when confirmed (card mode).
    var onRevealCard: ((String) -> Void)? = nil

    /// Called when the user taps the black screen after the reveal to dismiss.
    let onDismiss: () -> Void

    // ── Swipe buffer (number mode) ────────────────────────────────────────
    /// First swipe of the current in-progress pair (nil = waiting for 1st swipe).
    @State private var pendingSwipe: SwipeDir? = nil
    /// Completed digits accumulated so far.
    @State private var digitBuffer: [Int] = []
    /// True once onReveal has been called (inactivity timer commits and sets this).
    @State private var revealed = false

    // ── Card buffer (card mode) ───────────────────────────────────────────
    /// Raw swipes accumulated for the card: value pair (idx 0-1) + single suit (idx 2).
    @State private var cardSwipes: [SwipeDir] = []

    // Flash feedback: briefly dims screen on invalid swipe pair
    @State private var flashError = false

    /// Debounced validation task. Restarted after every swipe; commits only after
    /// 3 seconds without another swipe.
    @State private var inactivityCommitTask: Task<Void, Never>? = nil

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
        .onTapGesture {
            // Once the value has been sent to Instagram, keep the black screen as cover
            // until the performer intentionally reveals the fake profile.
            if revealed {
                onDismiss()
            }
        }
        .onDisappear {
            inactivityCommitTask?.cancel()
            inactivityCommitTask = nil
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
        scheduleInactivityCommit()
    }

    // MARK: - Card swipe processing
    //
    // Phase 1 (swipes 1-2): value pair — 13 valid combos (A–K clock face).
    // Phase 2 (swipe 3):    single suit — ↑=♠ →=♥ ↓=♣ ←=♦ (always valid).
    // Invalid value pair resets buffer; suit swipe is always accepted.

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
            // Single suit swipe — any direction is valid
            cardSwipes.append(dir)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            print("🖤 [CLOCK-INPUT] card complete: \(decodedCardSymbol ?? "?")")
        default:
            break
        }
        scheduleInactivityCommit()
    }

    private var decodedCardSymbol: String? {
        guard cardSwipes.count == 3,
              let val = SecretNumberManager.decodeCardValue(cardSwipes[0], cardSwipes[1]) else { return nil }
        let suit = SecretNumberManager.decodeSuit(cardSwipes[2])
        return "\(val)\(suit)"
    }

    // MARK: - Commit (inactivity)

    private func scheduleInactivityCommit() {
        inactivityCommitTask?.cancel()
        inactivityCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            commitBuffer()
        }
    }

    private func commitBuffer() {
        if mode == .card {
            guard let symbol = decodedCardSymbol else {
                // Card not complete yet — keep the black screen waiting for more swipes.
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            revealed = true
            print("📳 [CLOCK-INPUT] Committed card: \(symbol)")
            fireDoubleVibration()
            onRevealCard?(symbol)
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
