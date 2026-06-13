import SwiftUI
import UIKit

// MARK: - Card Numpad Input

/// Black fullscreen card selector used by Performance.
/// It starts as a blank black screen; the first tap reveals an elegant value/suit pad.
struct CardNumpadInputView: View {
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var padVisible = false
    @State private var selectedValue: CardValue?
    @State private var selectedSuit: CardSuit?
    @State private var didCommit = false

    private let firstRowValues: [CardValue] = [
        .init(label: "A", value: 1),
        .init(label: "2", value: 2),
        .init(label: "3", value: 3),
        .init(label: "4", value: 4),
        .init(label: "5", value: 5)
    ]

    private let secondRowValues: [CardValue] = [
        .init(label: "6", value: 6),
        .init(label: "7", value: 7),
        .init(label: "8", value: 8),
        .init(label: "9", value: 9),
        .init(label: "10", value: 10)
    ]

    private let faceValues: [CardValue] = [
        .init(label: "J", value: 11),
        .init(label: "Q", value: 12),
        .init(label: "K", value: 13)
    ]

    private let suits: [CardSuit] = [
        .init(symbol: "♠", index: 1, color: Color.white.opacity(0.90)),
        .init(symbol: "♥", index: 2, color: Color(hex: "FF375F")),
        .init(symbol: "♣", index: 3, color: Color.white.opacity(0.72)),
        .init(symbol: "♦", index: 4, color: Color(hex: "FF453A"))
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if padVisible {
                VStack(spacing: 16) {
                    header
                    valueRow(firstRowValues, minHeight: 56)
                    valueRow(secondRowValues, minHeight: 56)
                    faceValueRow
                    suitGrid
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !padVisible else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                padVisible = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(selectedSymbol ?? "Select Card")
                .font(.system(size: selectedSymbol == nil ? 24 : 34, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedSymbol)
            Text("Tap value, then suit")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func valueRow(_ values: [CardValue], minHeight: CGFloat) -> some View {
        HStack(spacing: 10) {
            ForEach(values) { value in
                cardButton(
                    title: value.label,
                    isSelected: selectedValue == value,
                    foreground: .white,
                    minHeight: minHeight
                ) {
                    selectedValue = value
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    tryCommit()
                }
            }
        }
    }

    private var faceValueRow: some View {
        HStack(spacing: 10) {
            ForEach(faceValues) { value in
                cardButton(
                    title: value.label,
                    isSelected: selectedValue == value,
                    foreground: .white,
                    minHeight: 54
                ) {
                    selectedValue = value
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    tryCommit()
                }
            }
        }
    }

    private var suitGrid: some View {
        HStack(spacing: 12) {
            ForEach(suits) { suit in
                cardButton(
                    title: suit.symbol,
                    isSelected: selectedSuit == suit,
                    foreground: suit.color,
                    minHeight: 64
                ) {
                    selectedSuit = suit
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    tryCommit()
                }
            }
        }
    }

    private func cardButton(
        title: String,
        isSelected: Bool,
        foreground: Color,
        minHeight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: title == "10" ? 24 : 28, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .black : foreground)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.85 : 0.18), lineWidth: 1)
                )
                .shadow(color: isSelected ? Color.white.opacity(0.18) : .clear, radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(didCommit)
    }

    private var selectedSymbol: String? {
        guard let selectedValue else { return nil }
        if let selectedSuit {
            return "\(selectedValue.label)\(selectedSuit.symbol)"
        }
        return selectedValue.label
    }

    private func tryCommit() {
        guard !didCommit, let value = selectedValue, let suit = selectedSuit else { return }
        didCommit = true
        let symbol = "\(value.label)\(suit.symbol)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSelect(symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }
}

private struct CardValue: Identifiable, Hashable {
    let label: String
    let value: Int
    var id: Int { value }
}

private struct CardSuit: Identifiable, Equatable {
    let symbol: String
    let index: Int
    let color: Color
    var id: Int { index }

    static func == (lhs: CardSuit, rhs: CardSuit) -> Bool {
        lhs.index == rhs.index
    }
}
