import SwiftUI
import Combine

struct LockscreenInputView: View {
    let onDismiss: () -> Void

    @State private var allDigits: [Int] = []
    @State private var secretDigits: [Int] = []
    @State private var isValidated = false
    @State private var pressedDigit: Int? = nil

    private let buttonSize: CGFloat = 80

    private let numpadLayout: [[NumpadKey]] = [
        [.digit(1, ""), .digit(2, "ABC"), .digit(3, "DEF")],
        [.digit(4, "GHI"), .digit(5, "JKL"), .digit(6, "MNO")],
        [.digit(7, "PQRS"), .digit(8, "TUV"), .digit(9, "WXYZ")],
        [.empty, .digit(0, ""), .empty]
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                wallpaperBackground(size: geo.size)

                // Tap-outside-numpad receptor (validates the secret number)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { validateIfNeeded() }

                // Title + numpad — genuinely centered between Dynamic Island and home bar
                VStack(spacing: 0) {
                    Spacer()
                    passcodeSection
                    Spacer().frame(height: 40)
                    numpadSection
                    Spacer()
                }

                // Emergency / Cancel — pinned to bottom independently, like real iOS
                VStack(spacing: 0) {
                    Spacer()
                    bottomRow
                        .padding(.bottom, geo.safeAreaInsets.bottom + 36)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private func wallpaperBackground(size: CGSize) -> some View {
        ZStack {
            if let img = LockscreenInputSettings.shared.wallpaperImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            Color.black.opacity(0.12).ignoresSafeArea()
        }
    }

    // MARK: - Passcode dots

    private var passcodeSection: some View {
        VStack(spacing: 18) {
            Text("Enter Passcode")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < allDigits.count ? Color.white : Color.clear)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 1.5)
                        )
                        .frame(width: 14, height: 14)
                }
            }
        }
    }

    // MARK: - Numpad

    private var numpadSection: some View {
        VStack(spacing: 16) {
            ForEach(0..<numpadLayout.count, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(0..<numpadLayout[row].count, id: \.self) { col in
                        let key = numpadLayout[row][col]
                        switch key {
                        case .digit(let num, let letters):
                            numpadButton(digit: num, letters: letters)
                        case .empty:
                            Color.clear.frame(width: buttonSize, height: buttonSize)
                        }
                    }
                }
            }
        }
    }

    private func numpadButton(digit: Int, letters: String) -> some View {
        let isPressed = pressedDigit == digit

        return ZStack {
            // Liquid-glass circle — matches iOS 26 native lock screen style
            Circle()
                .fill(Color.white.opacity(isPressed ? 0.38 : 0.20))
                .overlay(
                    // Subtle top-left specular highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.30 : 0.14),
                                    Color.clear
                                ],
                                center: .init(x: 0.35, y: 0.28),
                                startRadius: 0,
                                endRadius: buttonSize * 0.52
                            )
                        )
                )
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .frame(width: buttonSize, height: buttonSize)

            VStack(spacing: 2) {
                Text("\(digit)")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(.white)

                if !letters.isEmpty {
                    Text(letters)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .scaleEffect(isPressed ? 1.08 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            if pressing {
                pressedDigit = digit
            } else {
                handleDigitTap(digit)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if pressedDigit == digit { pressedDigit = nil }
                }
            }
        }, perform: {})
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack {
            Text("Emergency")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 36)
        }
    }

    // MARK: - Logic

    private func handleDigitTap(_ digit: Int) {
        guard allDigits.count < 4 else { return }

        allDigits.append(digit)

        if !isValidated {
            secretDigits.append(digit)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if allDigits.count == 4 {
            commitAndDismiss()
        }
    }

    private func validateIfNeeded() {
        guard !isValidated, !secretDigits.isEmpty else { return }
        isValidated = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func commitAndDismiss() {
        let manager = SecretNumberManager.shared
        manager.reset()
        for d in secretDigits {
            manager.addDigit(d)
        }
        print("🔒 [LOCKSCREEN] Secret number committed: \(secretDigits) (value: \(secretDigits.reduce(0) { $0 * 10 + $1 }))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    // MARK: - Key model

    private enum NumpadKey {
        case digit(Int, String)
        case empty
    }
}
