import SwiftUI
import CoreMotion
import UIKit

// MARK: - Notes amber / gold colour (matches iOS Notes cursor + checkmark)

private let notesYellow      = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
private let notesYellowColor = Color(notesYellow)

// MARK: - UITextView wrapper

private struct NotesTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate                 = context.coordinator
        tv.backgroundColor          = .clear
        tv.tintColor                = notesYellow   // amber cursor
        tv.textContainerInset       = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        tv.font                     = UIFont.systemFont(ofSize: 20, weight: .regular)
        tv.textColor                = .label
        tv.autocorrectionType       = .default
        tv.autocapitalizationType   = .sentences
        tv.spellCheckingType        = .default
        tv.isScrollEnabled          = true
        tv.showsVerticalScrollIndicator = false
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.isEditable = isEditable
        // Auto-focus once on first render
        if !context.coordinator.didBecomeFirstResponder && isEditable {
            context.coordinator.didBecomeFirstResponder = true
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var didBecomeFirstResponder = false
        weak var textView: UITextView?
        init(text: Binding<String>) { _text = text }
        func textViewDidChange(_ tv: UITextView) { text = tv.text }
    }
}

// MARK: - FakeNotesInputView

/// Two-phase full-screen iOS Notes replica.
///
/// Phase 1 — Typing:  spectator writes freely; back button locked; face-down (or ✓)
///                    captures the text silently and moves to Phase 2.
/// Phase 2 — Ready:   keyboard gone; tap anywhere → onCapture fires and view dismisses.
struct FakeNotesInputView: View {
    let onCapture: ([String]) -> Void
    let onCancel:  () -> Void        // kept for completeness; only fires in Phase 2

    // Phase tracking
    @State private var confirmed      = false
    @State private var capturedLines: [String] = []

    // Text
    @State private var text: String = ""

    // Face-down detection
    @State private var faceDownSeconds: Double  = 0
    @State private var confirmProgress: Double  = 0

    private let motionManager              = CMMotionManager()
    private let faceDownThreshold: Double  = 1.0
    private let accelerometerInterval: TimeInterval = 0.1

    var body: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                notesNavBar
                NotesTextView(text: $text, isEditable: !confirmed)
            }

            // ── Face-down progress ring (Phase 1 only) ───────────────────────
            if confirmProgress > 0 && !confirmed {
                faceDownRing
            }

            // ── Phase 2 overlay: tap anywhere to continue ────────────────────
            if confirmed {
                tapToContinueOverlay
            }
        }
        .onAppear   { startMotionDetection() }
        .onDisappear { stopMotionDetection() }
    }

    // MARK: - Navigation bar

    private var notesNavBar: some View {
        HStack(spacing: 10) {

            // Back chevron — LOCKED in Phase 1, active in Phase 2
            Button(action: handleBack) {
                circleIcon("chevron.left", size: 19, weight: .semibold,
                           opacity: confirmed ? 1.0 : 0.30)
            }
            .disabled(!confirmed)

            Spacer()

            // Undo (decorative)
            Button(action: {}) {
                circleIcon("arrow.uturn.backward", size: 19, weight: .regular)
            }
            .disabled(true)

            // Share + Ellipsis pill (decorative)
            HStack(spacing: 0) {
                Button(action: {}) { pillIcon("square.and.arrow.up", size: 19) }
                Color(UIColor.separator).frame(width: 0.5, height: 24)
                Button(action: {}) { pillIcon("ellipsis", size: 19) }
            }
            .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
            .disabled(true)

            // Yellow checkmark — manual confirm (Phase 1 only; hidden in Phase 2)
            Button(action: triggerCapture) {
                ZStack {
                    Circle()
                        .fill(notesYellowColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 44, height: 44)
            .opacity(confirmed ? 0 : 1)
            .disabled(confirmed)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Phase 2 tap-to-continue overlay

    private var tapToContinueOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { commitCapture() }
    }

    // MARK: - Icon helpers

    @ViewBuilder
    private func circleIcon(_ name: String, size: CGFloat,
                             weight: Font.Weight, opacity: Double = 1.0) -> some View {
        ZStack {
            Circle()
                .fill(Color(UIColor.secondarySystemBackground))
                .frame(width: 38, height: 38)
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
                .foregroundColor(.primary)
        }
        .frame(width: 46, height: 46)
        .opacity(opacity)
    }

    @ViewBuilder
    private func pillIcon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .regular))
            .foregroundColor(.primary)
            .frame(width: 46, height: 38)
    }

    // MARK: - Face-down ring

    private var faceDownRing: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .stroke(notesYellowColor.opacity(0.25), lineWidth: 5)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: confirmProgress)
                    .stroke(notesYellowColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: accelerometerInterval), value: confirmProgress)
                Image(systemName: "iphone.gen3.slash")
                    .font(.system(size: 20))
                    .foregroundColor(notesYellowColor)
            }
            .padding(.bottom, 52)
        }
    }

    // MARK: - Motion detection

    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = accelerometerInterval
        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let data = data, !confirmed else { return }
            if data.acceleration.z > 0.85 {
                faceDownSeconds += accelerometerInterval
                confirmProgress  = min(faceDownSeconds / faceDownThreshold, 1.0)
                if faceDownSeconds >= faceDownThreshold { triggerCapture() }
            } else {
                faceDownSeconds = 0
                confirmProgress = 0
            }
        }
    }

    private func stopMotionDetection() {
        motionManager.stopAccelerometerUpdates()
    }

    // MARK: - Capture logic

    /// Phase 1 → Phase 2: capture text silently, dismiss keyboard, wait for tap.
    private func triggerCapture() {
        guard !confirmed else { return }
        confirmed = true
        stopMotionDetection()
        // Haptic: double vibration signals the magician the word is saved
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        capturedLines = text
            .components(separatedBy: .newlines)
            .map    { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Phase 2 → dismiss: magician taps anywhere, view fires onCapture and closes.
    private func commitCapture() {
        onCapture(capturedLines)
    }

    private func handleBack() {
        // Only reachable in Phase 2 (disabled in Phase 1)
        commitCapture()
    }
}
