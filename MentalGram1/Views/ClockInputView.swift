import SwiftUI
import UIKit

// MARK: - Digit Encoding
//
// SwipeDir and the digit-pair decoding are defined once in SecretNumberManager
// and shared here, so the encoding stays consistent across the grid input and
// this fullscreen clock input:
//   0 = ↑↑   1 = ↑→   2 = →↑   3 = →→   4 = →↓
//   5 = ↓→   6 = ↓↓   7 = ↓←   8 = ←↓   9 = ←←

// MARK: - ClockInputView

/// A completely black fullscreen overlay used to enter a number (1-100)
/// through hidden swipe gestures. The screen simulates the device being off.
/// Each digit (0-9) requires exactly 2 swipes. Numbers 1-99 use 2 digits
/// (4 swipes). 100 uses 3 digits (6 swipes, entered as 1→0→0).
/// A long press (1 s) dismisses the overlay after a successful reveal.
struct ClockInputView: View {

    /// Called with the digit array once a valid number is entered.
    /// The array contains individual digits left-to-right, e.g. [0,5] for 5 or [1,0,0] for 100.
    let onReveal: ([Int]) -> Void

    /// Called when the user long-presses to dismiss.
    let onDismiss: () -> Void

    // ── Swipe buffer ──────────────────────────────────────────────────────
    @State private var currentPair:  [SwipeDir] = []   // building the current digit (0-2 swipes)
    @State private var digitBuffer:  [Int]      = []   // completed digits so far
    @State private var revealed     = false            // true once a valid number validated

    // Disambiguation timer: after "10" (2 digits), wait before validating
    @State private var waitingFor100Task: Task<Void, Never>? = nil

    // Flash feedback: briefly dims screen on invalid input
    @State private var flashError = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)
                // Error flash: momentary dim-then-return on bad swipe
                .opacity(flashError ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: flashError)

            // Invisible tap target that fills the whole screen for long press
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Swipe detection
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dir = swipeDirection(from: value)
                    handleSwipe(dir)
                }
        )
        // Long press to dismiss (only allowed after reveal completes)
        .onLongPressGesture(minimumDuration: 1.0) {
            if revealed {
                onDismiss()
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
        // Light haptic on every individual swipe
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        currentPair.append(dir)

        guard currentPair.count == 2 else { return }

        // Decode the completed pair into a digit
        let a = currentPair[0], b = currentPair[1]
        currentPair = []

        guard let digit = SecretNumberManager.decodeDigit(a, b) else {
            // Invalid pair: error haptic + flash, reset everything
            triggerErrorReset()
            return
        }

        // Medium haptic: digit complete
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        digitBuffer.append(digit)

        evaluateBuffer()
    }

    // MARK: - Buffer evaluation

    private func evaluateBuffer() {
        let count = digitBuffer.count
        let number = digitBuffer.reduce(0) { $0 * 10 + $1 }

        switch count {
        case 1:
            // Only 1 digit so far — need at least 2 for a two-digit number
            break

        case 2:
            // Possible two-digit numbers: 01…09 (= 1-9) or 10…99
            // Special case: "10" could become "100" — wait 1.5 s before committing
            if number == 0 {
                // "00" is not a valid number — reset
                triggerErrorReset()
            } else if number == 10 {
                // Could be 10 or start of 100 — set a disambiguation timer
                waitingFor100Task?.cancel()
                waitingFor100Task = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // No 3rd digit arrived — commit as 10
                        commitReveal(digits: digitBuffer, number: number)
                    }
                }
            } else if number >= 1 && number <= 99 {
                // Immediate validation for all other two-digit numbers
                waitingFor100Task?.cancel()
                commitReveal(digits: digitBuffer, number: number)
            } else {
                triggerErrorReset()
            }

        case 3:
            // Cancel any pending disambiguation timer — we're handling it now
            waitingFor100Task?.cancel()
            waitingFor100Task = nil

            if number == 100 {
                commitReveal(digits: digitBuffer, number: number)
            } else {
                // Invalid 3-digit number
                triggerErrorReset()
            }

        default:
            // Too many digits without validation — full reset
            triggerErrorReset()
        }
    }

    // MARK: - Commit

    private func commitReveal(digits: [Int], number: Int) {
        revealed = true
        // Strong double vibration — same as all other reveal paths
        fireDoubleVibration()
        print("📳 [CLOCK-INPUT] Number entered: \(number) — digits: \(digits)")
        onReveal(digits)
    }

    // MARK: - Error / Reset

    private func triggerErrorReset() {
        currentPair = []
        digitBuffer = []
        waitingFor100Task?.cancel()
        waitingFor100Task = nil

        // Error haptic
        UINotificationFeedbackGenerator().notificationOccurred(.error)

        // Brief visual flash
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
