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

    @Environment(\.scenePhase) private var scenePhase

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
    /// Basic input debounce. Prevents accidental swipe storms from creating a
    /// cascade of haptics, animations and commit tasks on the black screen.
    @State private var lastSwipeAt: Date = .distantPast
    @State private var lastErrorFeedbackAt: Date = .distantPast
    @State private var lastHapticAt: Date = .distantPast

    /// Debounced validation task. Restarted after every swipe; commits only after
    /// 3 seconds without another swipe.
    @State private var inactivityCommitTask: Task<Void, Never>? = nil
    @State private var flashResetTask: Task<Void, Never>? = nil
    @State private var secondVibrationTask: Task<Void, Never>? = nil

    private let minSwipeInterval: TimeInterval = 0.24
    private let minErrorFeedbackInterval: TimeInterval = 0.75
    private let minHapticInterval: TimeInterval = 0.12

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)
                .opacity(flashError ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: flashError)
        }
        .background(Color.black.ignoresSafeArea(.all))
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        // Swipe detection — each completed pair adds one digit
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    handleSwipe(swipeDirection(from: value))
                }
        )
        .onAppear {
            CrashLoggerService.shared.recordScreen(mode == .card ? "ClockInput: Card Clock" : "ClockInput: Number Clock")
            CrashLoggerService.shared.recordAction(mode == .card ? "ClockInput card opened" : "ClockInput number opened")
            lastSwipeAt = Date()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                lastSwipeAt = Date()
                CrashLoggerService.shared.recordScreen(mode == .card ? "ClockInput: Card Clock" : "ClockInput: Number Clock")
                CrashLoggerService.shared.recordAction(mode == .card ? "ClockInput card active" : "ClockInput number active")
            case .inactive, .background:
                suspendInputForLifecycle()
            @unknown default:
                break
            }
        }
        .onTapGesture {
            // Once the value has been sent to Instagram, keep the black screen as cover
            // until the performer intentionally reveals the fake profile.
            if revealed {
                onDismiss()
            }
        }
        .onDisappear {
            cancelPendingFeedbackAndCommit()
            CrashLoggerService.shared.recordAction(mode == .card ? "ClockInput card closed" : "ClockInput number closed")
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
        guard isAppActiveForInput else { return }
        guard acceptSwipeNow() else { return }

        if mode == .card {
            handleCardSwipe(dir)
            return
        }

        if let first = pendingSwipe {
            // Second swipe of a pair — try to decode
            pendingSwipe = nil
            if let digit = SecretNumberManager.decodeDigit(first, dir) {
                impact(.medium)
                digitBuffer.append(digit)
                print("🖤 [CLOCK-INPUT] pair \(first)\(dir) → digit \(digit)  buffer: \(digitBuffer.map(String.init).joined())")
            } else {
                // Invalid pair — error flash; treat second swipe as start of a new pair
                triggerErrorFlash()
                pendingSwipe = dir
                impact(.light)
                print("🖤 [CLOCK-INPUT] invalid pair \(first)\(dir) — restarting with \(dir)")
            }
        } else {
            // First swipe of a new pair
            pendingSwipe = dir
            impact(.light)
            print("🖤 [CLOCK-INPUT] first swipe \(dir) — waiting for second")
        }
        scheduleInactivityCommit()
    }

    private func acceptSwipeNow() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSwipeAt) >= minSwipeInterval else { return false }
        lastSwipeAt = now
        return true
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
            impact(.light)
            scheduleInactivityCommit()
        case 1:
            if SecretNumberManager.decodeCardValue(cardSwipes[0], dir) != nil {
                cardSwipes.append(dir)
                impact(.medium)
                scheduleInactivityCommit()
            } else {
                triggerErrorFlash()
                cardSwipes = [dir]
                impact(.light)
                scheduleInactivityCommit()
            }
        case 2:
            // Single suit swipe — any direction is valid
            cardSwipes.append(dir)
            impact(.heavy)
            // Schedule confirmation once. Further swipes are ignored so a nervous
            // performer cannot keep pushing the commit timer back forever.
            scheduleInactivityCommit()
            print("🖤 [CLOCK-INPUT] card complete: \(decodedCardSymbol ?? "?")")
        default:
            // Card already has value+suit. Ignore extra swipes completely:
            // no haptic, no animation, no timer reset.
            break
        }
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
            guard isAppActiveForInput else { return }
            commitBuffer()
        }
    }

    private func commitBuffer() {
        if mode == .card {
            guard let symbol = decodedCardSymbol else {
                // Card not complete yet — keep the black screen waiting for more swipes.
                notify(.warning)
                return
            }
            revealed = true
            print("📳 [CLOCK-INPUT] Committed card: \(symbol)")
            CrashLoggerService.shared.recordAction("ClockInput card committed \(symbol)")
            fireDoubleVibration()
            onRevealCard?(symbol)
            return
        }

        guard !digitBuffer.isEmpty else {
            // Nothing to commit yet — gentle warning haptic
            notify(.warning)
            return
        }
        // Discard any in-progress partial pair
        pendingSwipe = nil
        revealed = true
        let number = digitBuffer.reduce(0) { $0 * 10 + $1 }
        print("📳 [CLOCK-INPUT] Committed: \(number) — digits: \(digitBuffer)")
        CrashLoggerService.shared.recordAction("ClockInput number committed \(number)")
        fireDoubleVibration()
        onReveal(digitBuffer)
    }

    // MARK: - Error flash

    private func triggerErrorFlash() {
        guard isAppActiveForInput else { return }
        let now = Date()
        guard now.timeIntervalSince(lastErrorFeedbackAt) >= minErrorFeedbackInterval else { return }
        lastErrorFeedbackAt = now
        notify(.error)
        withAnimation(.easeInOut(duration: 0.15)) { flashError = true }
        flashResetTask?.cancel()
        flashResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard isAppActiveForInput else { return }
            withAnimation(.easeInOut(duration: 0.15)) { flashError = false }
        }
    }

    // MARK: - Haptics

    private func fireDoubleVibration() {
        guard isAppActiveForInput else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        secondVibrationTask?.cancel()
        secondVibrationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard isAppActiveForInput else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard shouldFireHapticNow() else { return }
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard shouldFireHapticNow() else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(type)
    }

    private var isAppActiveForInput: Bool {
        scenePhase == .active && UIApplication.shared.applicationState == .active
    }

    private func shouldFireHapticNow() -> Bool {
        guard isAppActiveForInput else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastHapticAt) >= minHapticInterval else { return false }
        lastHapticAt = now
        return true
    }

    private func suspendInputForLifecycle() {
        cancelPendingFeedbackAndCommit()
        lastSwipeAt = Date()
        if !revealed {
            pendingSwipe = nil
            digitBuffer.removeAll()
            cardSwipes.removeAll()
        }
        flashError = false
        CrashLoggerService.shared.recordAction(mode == .card ? "ClockInput card suspended" : "ClockInput number suspended")
    }

    private func cancelPendingFeedbackAndCommit() {
        inactivityCommitTask?.cancel()
        inactivityCommitTask = nil
        flashResetTask?.cancel()
        flashResetTask = nil
        secondVibrationTask?.cancel()
        secondVibrationTask = nil
    }
}
