import SwiftUI

// MARK: - Input Methods Help View

struct InputMethodsHelpView: View {
    let onClose: () -> Void

    private let accent = Color(hex: "BF5AF2")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    VStack(alignment: .leading, spacing: 0) {

                        imSection(icon: "questionmark.circle.fill", iconColor: accent,
                                  title: String(localized: "input.guide.intro.title")) {
                            imBody(String(localized: "input.guide.intro.body"))
                        }

                        sectionDivider

                        imSection(icon: "rectangle.3.group.fill", iconColor: accent,
                                  title: String(localized: "input.guide.compat.title")) {
                            compatTable
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "keyboard",
                            title: String(localized: "input.guide.covertyping.title"),
                            compatLabel: String(localized: "input.guide.covertyping.compat"),
                            color: Color(hex: "0095F6")
                        ) {
                            imBody(String(localized: "input.guide.covertyping.body"))
                            IMCoverTypingDemo()
                            instructionBox(
                                icon: "space",
                                color: Color(hex: "0095F6"),
                                text: String(localized: "input.guide.covertyping.activate")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "camera.fill",
                            title: String(localized: "input.guide.ocr.title"),
                            compatLabel: String(localized: "input.guide.ocr.compat"),
                            color: VaultTheme.Colors.success
                        ) {
                            imBody(String(localized: "input.guide.ocr.body"))
                            instructionBox(
                                icon: "speaker.wave.2.fill",
                                color: VaultTheme.Colors.success,
                                text: String(localized: "input.guide.ocr.activate")
                            )
                            instructionBox(
                                icon: "lightbulb.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.ocr.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "square.grid.3x2.fill",
                            title: String(localized: "input.guide.digitgrid.title"),
                            compatLabel: String(localized: "input.guide.digitgrid.compat"),
                            color: VaultTheme.Colors.primary
                        ) {
                            imBody(String(localized: "input.guide.digitgrid.body"))
                            IMGridInputDemo()
                            IMConfirmationMatrix()
                            instructionBox(
                                icon: "eye.slash.fill",
                                color: VaultTheme.Colors.primary,
                                text: String(localized: "input.guide.digitgrid.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "moon.fill",
                            title: String(localized: "input.guide.clock.title"),
                            compatLabel: String(localized: "input.guide.clock.compat"),
                            color: Color(hex: "94A3B8")
                        ) {
                            imBody(String(localized: "input.guide.clock.body"))
                            IMDigitPairEncodingTable()
                            IMSwipeExamples(
                                examples: [
                                    ("5", "↓→", "Single digit 5"),
                                    ("37", "→→ + ↓←", "3 then 7"),
                                    ("369", "→→ + ↓↓ + ←←", "3, 6, then 9")
                                ],
                                color: Color(hex: "94A3B8")
                            )
                            IMHapticLegend(color: Color(hex: "94A3B8"))
                            instructionBox(
                                icon: "hand.tap.fill",
                                color: Color(hex: "94A3B8"),
                                text: String(localized: "input.guide.clock.activate")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "suit.spade.fill",
                            title: String(localized: "input.guide.cardclock.title"),
                            compatLabel: String(localized: "input.guide.cardclock.compat"),
                            color: Color(hex: "16A34A")
                        ) {
                            imBody(String(localized: "input.guide.cardclock.body"))
                            IMCardClockEncoding()
                            IMSwipeExamples(
                                examples: [
                                    ("J\u{2660}", "↑←  ↑", "Jack of Spades"),
                                    ("3\u{2665}", "→→  →", "3 of Hearts"),
                                    ("A\u{2666}", "↑→  ←", "Ace of Diamonds")
                                ],
                                color: Color(hex: "16A34A")
                            )
                            IMHapticLegend(color: Color(hex: "16A34A"))
                            instructionBox(
                                icon: "hand.tap.fill",
                                color: Color(hex: "16A34A"),
                                text: String(localized: "input.guide.cardclock.activate")
                            )
                            instructionBox(
                                icon: "lightbulb.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.cardclock.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "rectangle.grid.3x2.fill",
                            title: String(localized: "input.guide.numpadcard.title"),
                            compatLabel: String(localized: "input.guide.numpadcard.compat"),
                            color: Color(hex: "16A34A")
                        ) {
                            imBody(String(localized: "input.guide.numpadcard.body"))
                            IMCardNumpadDemo()
                            instructionBox(
                                icon: "hand.tap.fill",
                                color: Color(hex: "16A34A"),
                                text: String(localized: "input.guide.numpadcard.activate")
                            )
                            instructionBox(
                                icon: "lightbulb.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.numpadcard.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "lock.fill",
                            title: String(localized: "input.guide.lockscreen.title"),
                            compatLabel: String(localized: "input.guide.lockscreen.compat"),
                            color: Color(hex: "6366F1")
                        ) {
                            imBody(String(localized: "input.guide.lockscreen.body"))
                            IMLockscreenMiniDemo(mode: .number)
                            instructionBox(
                                icon: "hand.tap.fill",
                                color: Color(hex: "6366F1"),
                                text: String(localized: "input.guide.lockscreen.activate")
                            )
                            instructionBox(
                                icon: "photo.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.lockscreen.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "suit.club.fill",
                            title: String(localized: "input.guide.lockscreencard.title"),
                            compatLabel: String(localized: "input.guide.lockscreencard.compat"),
                            color: Color(hex: "16A34A")
                        ) {
                            imBody(String(localized: "input.guide.lockscreencard.body"))
                            IMLockscreenMiniDemo(mode: .card)
                            IMCardLockscreenCodeTable()
                            instructionBox(
                                icon: "tablecells.fill",
                                color: Color(hex: "16A34A"),
                                text: String(localized: "input.guide.lockscreencard.activate")
                            )
                            instructionBox(
                                icon: "lightbulb.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.lockscreencard.tip")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "network",
                            title: String(localized: "input.guide.api.title"),
                            compatLabel: String(localized: "input.guide.api.compat"),
                            color: Color(hex: "FFD60A")
                        ) {
                            imBody(String(localized: "input.guide.api.body"))
                            instructionBox(
                                icon: "arrow.triangle.2.circlepath",
                                color: Color(hex: "FFD60A"),
                                text: String(localized: "input.guide.api.activate")
                            )
                        }

                        sectionDivider

                        richMethodSection(
                            icon: "link",
                            title: String(localized: "input.guide.urlscheme.title"),
                            compatLabel: String(localized: "input.guide.urlscheme.compat"),
                            color: Color(hex: "FB923C")
                        ) {
                            imBody(String(localized: "input.guide.urlscheme.body"))
                            IMURLExamples()
                            instructionBox(
                                icon: "bolt.fill",
                                color: Color(hex: "FB923C"),
                                text: String(localized: "input.guide.urlscheme.activate")
                            )
                            instructionBox(
                                icon: "lightbulb.fill",
                                color: Color(hex: "FF9F0A"),
                                text: String(localized: "input.guide.urlscheme.tip")
                            )
                        }

                        sectionDivider

                        imSection(icon: "play.circle.fill", iconColor: Color(hex: "FF6B35"),
                                  title: String(localized: "input.guide.force.title")) {
                            VStack(alignment: .leading, spacing: 12) {
                                imBody(String(localized: "input.guide.force.body"))

                                forceCard(
                                    icon: "hand.point.up.left.fill",
                                    color: Color(hex: "BF5AF2"),
                                    title: String(localized: "input.guide.force.post.title"),
                                    body: String(localized: "input.guide.force.post.body")
                                )

                                forceCard(
                                    icon: "square.grid.2x2",
                                    color: Color(hex: "BF5AF2"),
                                    title: String(localized: "input.guide.force.reel.title"),
                                    body: String(localized: "input.guide.force.reel.body")
                                )
                            }
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // Top bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.top, VaultTheme.Spacing.lg)
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(accent.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.top, 8)

            Text(String(localized: "input.guide.title"))
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, VaultTheme.Spacing.lg)

            Text(String(localized: "input.guide.subtitle"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .padding(.horizontal, VaultTheme.Spacing.lg)
        }
    }

    // MARK: - Compatibility table

    private var compatTable: some View {
        VStack(spacing: 0) {
            compatRow(
                setLabel: "Words",
                methods: String(localized: "input.guide.compat.word.methods"),
                isLast: false
            )
            Divider().background(Color.white.opacity(0.06))
            compatRow(
                setLabel: "Numbers",
                methods: String(localized: "input.guide.compat.number.methods"),
                isLast: false
            )
            Divider().background(Color.white.opacity(0.06))
            compatRow(
                setLabel: "Cards",
                methods: String(localized: "input.guide.compat.card.methods"),
                isLast: true
            )
        }
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func compatRow(setLabel: String, methods: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(setLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 76, alignment: .leading)
            Text(methods)
                .font(.system(size: 12))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Method section

    private func richMethodSection<C: View>(
        icon: String,
        title: String,
        compatLabel: String,
        color: Color,
        @ViewBuilder content: () -> C
    ) -> some View {
        imSection(icon: icon, iconColor: color, title: title) {
            VStack(alignment: .leading, spacing: 12) {
                Text(compatLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(6)

                content()
            }
        }
    }

    private func instructionBox(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(color.opacity(0.07))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Force card

    private func forceCard(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Helpers (same pattern as LockscreenInputGuideView)

    private func imSection<C: View>(
        icon: String, iconColor: Color, title: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            content()
        }
        .padding(.vertical, 16)
    }

    private func imBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sectionDivider: some View {
        Divider().background(Color.white.opacity(0.08))
    }
}

// MARK: - Shared Input Guide Components

private struct IMDigitPairEncodingTable: View {
    private let accent = VaultTheme.Colors.primary
    private let rows: [[(String, String)]] = [
        [("0", "↑↑"), ("1", "↑→"), ("2", "→↑"), ("3", "→→"), ("4", "→↓")],
        [("5", "↓→"), ("6", "↓↓"), ("7", "↓←"), ("8", "←↓"), ("9", "←←")]
    ]

    var body: some View {
        IMMiniTable(title: String(localized: "postpred.help.input.clockinput.encoding.title"), color: accent) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(rows[row], id: \.0) { digit, pair in
                        IMEncodingPill(label: digit, value: pair, color: accent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct IMCardClockEncoding: View {
    private let accent = Color(hex: "16A34A")
    private let valueRows: [[(String, String)]] = [
        [("A", "↑→"), ("2", "→↑"), ("3", "→→"), ("4", "→↓"), ("5", "↓→"), ("6", "↓↓"), ("7", "↓←")],
        [("8", "←↓"), ("9", "←←"), ("10", "←↑"), ("J", "↑←"), ("Q", "↑↑"), ("K", "↑↓")]
    ]
    private let suits: [(String, String)] = [("♠", "↑"), ("♥", "→"), ("♣", "↓"), ("♦", "←")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IMMiniTable(title: String(localized: "postpred.help.input.cardclock.guide.values"), color: accent) {
                ForEach(valueRows.indices, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(valueRows[row], id: \.0) { face, pair in
                            IMEncodingPill(label: face, value: pair, color: accent)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            IMMiniTable(title: String(localized: "postpred.help.input.cardclock.guide.suits"), color: accent) {
                HStack(spacing: 8) {
                    ForEach(suits, id: \.0) { suit, pair in
                        IMEncodingPill(label: suit, value: pair, color: accent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct IMMiniTable<C: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(0.5)
            content()
        }
        .padding(10)
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.16), lineWidth: 1))
    }
}

private struct IMEncodingPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.2), lineWidth: 0.8))
    }
}

private struct IMSwipeExamples: View {
    let examples: [(label: String, swipes: String, note: String)]
    let color: Color

    var body: some View {
        IMMiniTable(title: String(localized: "postpred.help.input.clockinput.examples.title"), color: color) {
            ForEach(examples, id: \.label) { example in
                HStack(alignment: .top, spacing: 10) {
                    Text(example.label)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .frame(width: 34, alignment: .center)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.14))
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.swipes)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        Text(example.note)
                            .font(.system(size: 11))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct IMHapticLegend: View {
    let color: Color

    var body: some View {
        IMMiniTable(title: String(localized: "postpred.help.input.clockinput.haptic.title"), color: color) {
            IMHapticRow(icon: "hand.point.right.fill", color: Color(hex: "60A5FA"),
                        text: String(localized: "postpred.help.input.clockinput.haptic.light"))
            IMHapticRow(icon: "circle.hexagongrid.fill", color: Color(hex: "A78BFA"),
                        text: String(localized: "postpred.help.input.clockinput.haptic.medium"))
            IMHapticRow(icon: "iphone.radiowaves.left.and.right", color: Color(hex: "34D399"),
                        text: String(localized: "postpred.help.input.clockinput.haptic.success"))
            IMHapticRow(icon: "xmark.circle.fill", color: VaultTheme.Colors.error,
                        text: String(localized: "postpred.help.input.clockinput.haptic.error"))
        }
    }
}

private struct IMHapticRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IMConfirmationMatrix: View {
    private let rows: [(String, String, String)] = [
        ("Post Prediction", "Tap the hidden cell positions to build the number, then confirm with the Posts icon or a long press.", "photo.on.rectangle"),
        ("Force Reel", "Use the grid map to enter the position, then open Search/Explore to lock the pending reel position.", "play.rectangle.fill"),
        ("Counter Glitch", "Use the same grid map to enter the offset; followers/following or Explore captures it for the counter.", "number.circle.fill")
    ]

    var body: some View {
        IMMiniTable(title: "CONFIRMATION BY FEATURE", color: Color(hex: "FF9F0A")) {
            ForEach(rows, id: \.0) { title, detail, icon in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "FF9F0A"))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct IMGridInputDemo: View {
    @State private var activeTab = 0
    @State private var activeCell = 0
    @State private var enteredDigits: [Int] = []
    @State private var task: Task<Void, Never>?

    private let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0]
    private let tabs: [(String, String)] = [
        ("square.grid.3x3.fill", "Posts"),
        ("play.rectangle.fill", "Reels"),
        ("person.crop.square", "Tagged")
    ]

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            Image(systemName: tabs[index].0)
                                .font(.system(size: 14, weight: .semibold))
                            Text(tabs[index].1)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(activeTab == index ? .white : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color.black)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    ForEach(digits.indices, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(cellColor(index).opacity(index == activeCell ? 0.95 : 0.42))
                                .frame(height: 54)
                            Image(systemName: activeTab == 1 ? "play.fill" : activeTab == 2 ? "person.fill" : "photo.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.18))
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("\(digits[index])")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(index >= 9 ? Color(hex: "F97316") : Color(hex: "6366F1")))
                                        .padding(5)
                                }
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(index == activeCell ? Color.white.opacity(0.75) : .clear, lineWidth: 2)
                        )
                        .scaleEffect(index == activeCell ? 1.03 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: activeCell)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1))

            HStack {
                Text("Following")
                    .font(.system(size: 11))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                Text(enteredDigits.isEmpty ? "1,268" : enteredDigits.map(String.init).joined())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(VaultTheme.Colors.primary)
                Spacer()
                Text(enteredDigits.isEmpty ? "Map 1-9 + 0 row" : "Hidden value building")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(enteredDigits.isEmpty ? Color(hex: "FF9F0A") : VaultTheme.Colors.success)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaultTheme.Colors.primary.opacity(0.18), lineWidth: 1))
        .onAppear { startLoop() }
        .onDisappear { task?.cancel() }
    }

    private func cellColor(_ index: Int) -> Color {
        let colors = [Color(hex: "3B82F6"), Color(hex: "8B5CF6"), Color(hex: "F97316"), Color(hex: "16A34A")]
        return colors[(index + activeTab) % colors.count]
    }

    private func startLoop() {
        task?.cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                enteredDigits = []
                activeTab = 0
                activeCell = 0
                try? await Task.sleep(nanoseconds: 700_000_000)
                activeCell = 2
                enteredDigits = [3]
                try? await Task.sleep(nanoseconds: 900_000_000)
                activeTab = 1
                activeCell = 9
                enteredDigits = [3, 0]
                try? await Task.sleep(nanoseconds: 900_000_000)
                activeTab = 2
                activeCell = 6
                enteredDigits = [3, 0, 7]
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
        }
    }
}

private struct IMCardNumpadDemo: View {
    private let color = Color(hex: "16A34A")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IMNumpadPhonePreview(phase: .black)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                IMNumpadPhonePreview(phase: .pad)
            }
            Text("Real flow: black screen → tap anywhere → value + suit pad → automatic close")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22), lineWidth: 1))
    }

    private enum Phase { case black, pad }

    private struct IMNumpadPhonePreview: View {
        let phase: Phase
        private let firstRow = ["A", "2", "3", "4", "5"]
        private let secondRow = ["6", "7", "8", "9", "10"]
        private let faceRow = ["J", "Q", "K"]
        private let suits = ["♠", "♥", "♣", "♦"]

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black)
                    .frame(height: 216)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))

                if phase == .black {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 34, height: 34)
                        Text("tap")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.30))
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("A♠")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        valueRow(firstRow, selected: "A")
                        valueRow(secondRow, selected: nil)
                        valueRow(faceRow, selected: nil)
                        HStack(spacing: 5) {
                            ForEach(suits, id: \.self) { suit in
                                Text(suit)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(suit == "♠" ? .black : ((suit == "♥" || suit == "♦") ? Color(hex: "FF453A") : .white.opacity(0.82)))
                                    .frame(height: 28)
                                    .frame(maxWidth: .infinity)
                                    .background(suit == "♠" ? Color.white : Color.white.opacity(0.10))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }

        private func valueRow(_ values: [String], selected: String?) -> some View {
            HStack(spacing: 5) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: value == "10" ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(value == selected ? .black : .white)
                        .frame(height: values.count == 3 ? 24 : 25)
                        .frame(maxWidth: .infinity)
                        .background(value == selected ? Color.white : Color.white.opacity(0.10))
                        .cornerRadius(8)
                }
            }
        }
    }
}

private struct IMCardLockscreenCodeTable: View {
    private let color = Color(hex: "16A34A")
    private let values: [(String, String)] = [
        ("A", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"), ("6", "6"), ("7", "7"),
        ("8", "8"), ("9", "9"), ("10", "10"), ("J", "11"), ("Q", "12"), ("K", "13")
    ]
    private let suits: [(String, String)] = [("♠", "1"), ("♥", "2"), ("♣", "3"), ("♦", "4")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CARD LOCKSCREEN CODE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(0.5)
            Text("Code format: value + suit. Use 0 before A-9 if you want a 3-digit code. Examples: A♠ = 11 or 011 · 10♥ = 102 · J♣ = 113 · K♦ = 134.")
                .font(.system(size: 11))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Values")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 5) {
                        ForEach(values, id: \.0) { face, code in
                            IMEncodingPill(label: face, value: code, color: color)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suits")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                    ForEach(suits, id: \.0) { suit, code in
                        IMEncodingPill(label: suit, value: code, color: color)
                    }
                }
                .frame(width: 64)
            }
        }
        .padding(10)
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.16), lineWidth: 1))
    }
}

private struct IMCoverTypingDemo: View {
    @State private var secretChars: [Character] = []
    @State private var visibleChars: [Character] = []
    @State private var revealPhase = false
    @State private var task: Task<Void, Never>?

    private let secretWord: [Character] = Array("MAGIC")
    private let coverWord: [Character] = Array("sport")
    private let blue = Color(hex: "0095F6")

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                Text(String(visibleChars))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                if !visibleChars.isEmpty {
                    Rectangle().fill(.white.opacity(0.75)).frame(width: 1.5, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10))
            .cornerRadius(10)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundColor(blue)
                Text("App records:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Text(secretChars.isEmpty ? "-" : String(secretChars))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(blue)
                Spacer()
            }

            if revealPhase {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(blue)
                    Text("Space confirms the hidden word")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(blue.opacity(0.1))
                .cornerRadius(10)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(14)
        .background(Color(hex: "0A0A0A"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(blue.opacity(0.22), lineWidth: 1))
        .onAppear { startLoop() }
        .onDisappear { task?.cancel() }
    }

    private func startLoop() {
        task?.cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                secretChars = []; visibleChars = []; revealPhase = false
                try? await Task.sleep(nanoseconds: 500_000_000)
                for index in 0..<secretWord.count {
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                        secretChars.append(secretWord[index])
                        visibleChars.append(coverWord[index])
                    }
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { revealPhase = true }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
        }
    }
}

private struct IMLockscreenMiniDemo: View {
    enum Mode { case number, card }
    let mode: Mode

    private var accent: Color { mode == .number ? Color(hex: "6366F1") : Color(hex: "16A34A") }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index < 4 ? Color.white : Color.clear)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .frame(width: 10, height: 10)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { digit in
                    Text("\(digit)")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
            }
            .frame(maxWidth: 180)

            Text(mode == .number ? "PIN -> number" : "PIN -> card lookup")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.24), lineWidth: 1))
    }
}

private struct IMURLExamples: View {
    private let examples = [
        "vault://reveal?word=MAGIC",
        "vault://reveal?slot=15",
        "vault://reveal?card=J\u{2660}",
        "vault://bio?text=Now"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(examples, id: \.self) { example in
                Text(example)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "FB923C"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
            }
        }
    }
}
