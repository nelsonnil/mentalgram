import SwiftUI

// MARK: - Post Prediction Help View

struct PostPredictionHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.xl)

                    Group {
                        HelpSection(icon: "wand.and.stars", iconColor: Color(hex: "A78BFA"), title: "postpred.help.section.howitworks") {
                            howItWorks
                        }

                        divider

                        HelpSection(icon: "hand.tap.fill", iconColor: VaultTheme.Colors.secondary, title: "postpred.help.section.inputs") {
                            inputMethods
                        }

                        divider

                        HelpSection(icon: "list.number", iconColor: VaultTheme.Colors.success, title: "postpred.help.section.before") {
                            beforeShow
                        }

                        divider

                        HelpSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "postpred.help.section.during") {
                            duringShow
                        }

                        divider

                        HelpSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "postpred.help.section.tips") {
                            tipsSection
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("postpred.help.nav.title")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("postpred.help.nav.subtitle")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(VaultTheme.Colors.backgroundSecondary)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(VaultTheme.Colors.background.shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4))
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hex: "A78BFA").opacity(0.15))
                    .frame(width: 80, height: 80)
                Text("🃏")
                    .font(.system(size: 40))
            }
            Text("postpred.help.hero.title")
                .font(VaultTheme.Typography.title())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("postpred.help.hero.body")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(VaultTheme.Colors.cardBorder)
            .frame(height: 1)
            .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            PPBodyText("postpred.help.howitworks.body1")
            PPMetricRow(icon: "photo.stack.fill", color: Color(hex: "A78BFA"),
                        label: "postpred.help.metric.sets",
                        description: "postpred.help.metric.sets.desc")
            PPMetricRow(icon: "building.columns.fill", color: VaultTheme.Colors.secondary,
                        label: "postpred.help.metric.banks",
                        description: "postpred.help.metric.banks.desc")
            PPBodyText("postpred.help.howitworks.body2")

            // Animated explanation of how Banks and Sets work together
            PPBanksDemo()

            PPInfoBox(text: "postpred.help.howitworks.info")
        }
    }

    // MARK: - Input Methods

    private var inputMethods: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            PPBodyText("postpred.help.inputs.body1")

            // ── Group 1: Numeric / Custom sets ──────────────────────────
            ppInputGroupHeader(
                icon: "number.circle.fill",
                label: "postpred.help.inputs.group.numeric",
                color: Color(hex: "A78BFA")
            )

            PPGridInputDemo()

            PPShowStep(
                label: "postpred.help.input.grid.label",
                labelColor: VaultTheme.Colors.primary,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.grid.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.grid.step2", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.grid.step3", dialogue: nil)
                ]
            )

            // ── Group 2: Alphabetic sets ─────────────────────────────────
            ppInputGroupHeader(
                icon: "character.cursor.ibeam",
                label: "postpred.help.inputs.group.alpha",
                color: VaultTheme.Colors.secondary
            )

            PPShowStep(
                label: "postpred.help.input.ocr.label",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.ocr.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.ocr.step2", dialogue: nil)
                ]
            )

            PPCovertTypingDemo()

            PPShowStep(
                label: "postpred.help.input.covert.label",
                labelColor: Color(hex: "0095F6"),
                steps: [
                    PPShowStepItem(action: "postpred.help.input.covert.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.covert.step2", dialogue: nil)
                ]
            )

            PPShowStep(
                label: "postpred.help.input.api.label",
                labelColor: VaultTheme.Colors.textSecondary,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.api.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.api.step2", dialogue: nil)
                ]
            )

            // ── Group 3: Universal ───────────────────────────────────────
            ppInputGroupHeader(
                icon: "link",
                label: "postpred.help.inputs.group.universal",
                color: VaultTheme.Colors.warning
            )

            PPShowStep(
                label: "postpred.help.input.url.label",
                labelColor: VaultTheme.Colors.warning,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.url.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.url.step2", dialogue: nil)
                ]
            )
        }
    }

    @ViewBuilder
    private func ppInputGroupHeader(icon: String, label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.06))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Before the Show

    private var beforeShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            PPNumberedStep(number: 1, text: "postpred.help.before.1")
            PPNumberedStep(number: 2, text: "postpred.help.before.2")
            PPNumberedStep(number: 3, text: "postpred.help.before.3")
            PPNumberedStep(number: 4, text: "postpred.help.before.4")
            PPNumberedStep(number: 5, text: "postpred.help.before.5")
        }
    }

    // MARK: - During the Show

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            PPShowStep(
                label: "postpred.help.during.step.invite",
                labelColor: Color(hex: "A78BFA"),
                steps: [
                    PPShowStepItem(
                        action: "postpred.help.during.invite.action",
                        dialogue: "postpred.help.during.invite.dialogue"
                    )
                ]
            )

            PPShowStep(
                label: "postpred.help.during.step.input",
                labelColor: VaultTheme.Colors.secondary,
                steps: [
                    PPShowStepItem(
                        action: "postpred.help.during.input.action",
                        dialogue: "postpred.help.during.input.dialogue"
                    )
                ]
            )

            PPShowStep(
                label: "postpred.help.during.step.reveal",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    PPShowStepItem(action: "postpred.help.during.reveal.action", dialogue: nil),
                    PPShowStepItem(
                        action: "postpred.help.during.timing.action",
                        dialogue: "postpred.help.during.timing.dialogue"
                    )
                ]
            )
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            PPTipRow(icon: "timer", color: VaultTheme.Colors.warning,
                     text: "postpred.help.tip.timing")
            PPTipRow(icon: "iphone.radiowaves.left.and.right", color: VaultTheme.Colors.primary,
                     text: "postpred.help.tip.vibration")
            PPTipRow(icon: "square.grid.3x3.fill", color: VaultTheme.Colors.secondary,
                     text: "postpred.help.tip.position")
            PPTipRow(icon: "wifi", color: VaultTheme.Colors.error,
                     text: "postpred.help.tip.upload")
            PPTipRow(icon: "building.columns", color: Color(hex: "A78BFA"),
                     text: "postpred.help.tip.banks")
            ppRealVsFakeBox
        }
    }

    private var ppRealVsFakeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text(LocalizedStringKey("postpred.help.tip.fakeapp"))
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "30D158"))
                    .padding(.top, 1)
                Text(LocalizedStringKey("postpred.help.tip.openprofile"))
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(hex: "FF9F0A").opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "FF9F0A").opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Private Reusable Components (PP-prefixed to avoid conflicts)

private struct PPHelpSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let content: Content

    init(icon: String, iconColor: Color, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 18))
                Text(title)
                    .font(VaultTheme.Typography.titleSmall())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content
        }
    }
}

// Re-using HelpSection from DateForceHelpView.swift would cause ambiguity,
// so we forward to the file-private wrapper above but expose via typealias.
private typealias HelpSection = PPHelpSection

private struct PPBodyText: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }
    var body: some View {
        Text(key)
            .font(VaultTheme.Typography.body())
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PPMetricRow: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(description)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VaultTheme.Spacing.sm)
        .background(color.opacity(0.06))
        .cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

private struct PPInfoBox: View {
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(VaultTheme.Colors.info)
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.info.opacity(0.08))
        .cornerRadius(VaultTheme.CornerRadius.sm)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
            .stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1))
    }
}

private struct PPNumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(VaultTheme.Colors.primary)
                .frame(width: 22, height: 22)
                .background(VaultTheme.Colors.primary.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PPShowStepItem {
    let action: LocalizedStringKey
    let dialogue: LocalizedStringKey?
}

private struct PPShowStep: View {
    let label: LocalizedStringKey
    let labelColor: Color
    let steps: [PPShowStepItem]

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(labelColor)
                .tracking(1.5)

            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                ForEach(steps.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                            Circle()
                                .fill(labelColor.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 8)
                            Text(steps[i].action)
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let dialogue = steps[i].dialogue {
                            PPDialogueBox(text: dialogue, color: labelColor)
                        }
                    }
                }
            }
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
            .stroke(labelColor.opacity(0.2), lineWidth: 1))
    }
}

private struct PPDialogueBox: View {
    let text: LocalizedStringKey
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .cornerRadius(1)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .italic()
                .foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, VaultTheme.Spacing.md)
    }
}

private struct PPTipRow: View {
    let icon: String
    let color: Color
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 22)
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ── PPGridInputDemo ───────────────────────────────────────────────────
// Demonstrates the Grid Input mechanic: the magician browses Posts → Reels →
// Tagged as a natural cover while each swipe secretly registers the digit of
// the item touched.  After tapping Posts to confirm, the matching photo (#37)
// is unarchived and appears as a fresh new post in the grid.

private struct PPGridInputDemo: View {

    enum Phase { case swipe, confirm, reveal }
    @State private var phase: Phase = .swipe

    // Tab / section state (0=Posts, 1=Reels, 2=Tagged)
    @State private var activeTab: Int = 0

    // Digit accumulator (shown in "Nº" indicator replacing "Following")
    @State private var accumDigits: [Int] = []
    @State private var digitBounce: CGFloat = 1.0

    // Swipe animation
    @State private var activeSwipeCell: Int? = nil
    @State private var swipeTrail: CGFloat = 0
    @State private var showFinger: Bool = false
    @State private var fingerOffset: CGSize = .zero

    // Confirm (Posts button tap)
    @State private var postsBtnPulse: Bool = false
    @State private var postsBtnScale: CGFloat = 1.0

    // Reveal (new unarchived photo card)
    @State private var showRevealCard: Bool = false
    @State private var phoneGlow: Double = 0

    @State private var loopTask: Task<Void, Never>? = nil

    private let accent = Color(hex: "A78BFA")
    private let gold   = Color(hex: "F59E0B")

    // Phone geometry
    private let phoneW: CGFloat = 248
    private let phoneH: CGFloat = 492

    // Header: navBar(48) + stats(68) + bio(20) + buttons(48) + tabs(40) = 224
    private let headerH: CGFloat = 224
    private let cellW:   CGFloat = 82
    private let cellH:   CGFloat = 66

    // Swipe 1: Posts cell[0] → digit 3, tab Post→Reels
    // Swipe 2: Reels cell[6] → digit 7, tab Reels→Tagged
    private let swipe1CellIdx = 0   // digit shown = 3 via label
    private let swipe2CellIdx = 6   // digit shown = 7

    private let cellDigits   = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0]
    // Override displayed digit for the two demo cells so demo reads "37"
    private let demoDigit1 = 3
    private let demoDigit2 = 7

    // ── Cell center in ZStack coords ─────────────────────────────────────────
    private func cellCenter(_ idx: Int) -> CGSize {
        let col = CGFloat(idx % 3)
        let row = CGFloat(idx / 3)
        let x = col * (cellW + 1) + cellW / 2 - phoneW / 2
        let y = headerH + row * (cellH + 1) + cellH / 2 - phoneH / 2
        return CGSize(width: x, height: y)
    }

    // Posts tab button center (left third of tab bar; tab bar starts at y=224-40=184)
    private var postsTabCenter: CGSize {
        CGSize(width: -phoneW / 3 + phoneW / 6,          // ≈ -41
               height: (headerH - 40 / 2) - phoneH / 2)  // 184+20−246 = −42
    }

    private let ppGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(hex: "2d1b69"), Color(hex: "1a0f40")], startPoint: .topLeading, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a3a5c"), Color(hex: "0d1f3c")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a3d2e"), Color(hex: "0d261c")], startPoint: .top,        endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2010"), Color(hex: "261408")], startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "1a2a5c"), Color(hex: "0d1a3c")], startPoint: .top,        endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "0d3d2a"), Color(hex: "061f15")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "3d0d2a"), Color(hex: "260819")], startPoint: .top,        endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a3a1a"), Color(hex: "0d260d")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2a0d"), Color(hex: "261908")], startPoint: .top,        endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2d1010"), Color(hex: "1a0808")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "102d10"), Color(hex: "081a08")], startPoint: .top,        endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "10182d"), Color(hex: "080d1a")], startPoint: .topTrailing, endPoint: .bottomLeading),
    ]

    private let postIcons = ["mountain.2.fill","tree.fill","sun.horizon.fill","camera.fill",
                             "star.fill","music.note","flame.fill","heart.fill","figure.run",
                             "moon.stars.fill","leaf.fill","bolt.fill"]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ppPill("1", "Swipe",   active: phase == .swipe,   color: accent)
                ppPill("2", "Confirm", active: phase == .confirm, color: accent)
                ppPill("3", "Reveal",  active: phase == .reveal,  color: gold)
            }

            phoneMockup
                .shadow(color: (phase == .reveal ? gold : accent).opacity(phoneGlow * 0.55), radius: 28)
                .animation(.easeInOut(duration: 0.4), value: phoneGlow)

            Group {
                switch phase {
                case .swipe:
                    Text("Browsing Posts → Reels → Tagged looks natural while each swipe secretly registers a digit")
                case .confirm:
                    Text("Tap **Posts** to lock in the number and trigger the unarchive")
                case .reveal:
                    Text("Photo **#37** appears as a new post — unarchived on real Instagram at its original position")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 38)
            .animation(.easeInOut(duration: 0.3), value: phase)
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(accent.opacity(0.25), lineWidth: 1))
        .onAppear  { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Phone mockup

    private var phoneMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38).fill(Color(hex: "111111"))
                .frame(width: phoneW + 16, height: phoneH + 16)
            // Volume buttons
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525"))
                .frame(width: 3, height: 68).offset(x: -(phoneW / 2 + 9), y: -66)
            // Power button
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525"))
                .frame(width: 3, height: 44).offset(x: (phoneW / 2 + 9), y: -52)
            // Dynamic Island
            Capsule().fill(Color.black).frame(width: 96, height: 30)
                .offset(y: -(phoneH / 2 + 1))
            // Screen bg
            RoundedRectangle(cornerRadius: 28).fill(Color(hex: "060606"))
                .frame(width: phoneW, height: phoneH)
            // Screen content
            Group {
                if phase == .reveal {
                    revealScene.transition(.opacity)
                } else {
                    gridScene.transition(.opacity)
                }
            }
            .frame(width: phoneW, height: phoneH)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .animation(.easeInOut(duration: 0.38), value: phase == .reveal)
        }
    }

    // MARK: - Grid scene (swipe + confirm phases)

    private var gridScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar
                igProfileStats
                igBioLine
                igActionButtons
                igTabBar
                ZStack {
                    pagedTabContent
                    if showFinger { fingerView.offset(fingerOffset) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var igNavBar: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text("username").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 17)).foregroundColor(.white)
        }
        .padding(.horizontal, 18).frame(height: 48)
        .background(Color(hex: "060606"))
    }

    private var igProfileStats: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "E91E8C"), Color(hex: "9B59B6")],
                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                    .frame(width: 58, height: 58)
                Circle().fill(Color(hex: "1a0f40")).frame(width: 50, height: 50)
                    .overlay(Text("M").font(.system(size: 20, weight: .bold)).foregroundColor(.white))
            }
            .padding(.leading, 16)
            Spacer()
            ppStatItem("12",  "Posts")
            Spacer()
            ppStatItem("847", "Followers")
            Spacer()
            digitIndicator
            Spacer()
        }
        .frame(height: 68)
    }

    private var igBioLine: some View {
        HStack {
            Text("Magician · NYC 🎩").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.65)).padding(.leading, 18)
            Spacer()
        }
        .frame(height: 20)
    }

    private var igActionButtons: some View {
        HStack(spacing: 8) {
            Text("Follow").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30).background(accent).cornerRadius(8)
            Text("Message").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
            Image(systemName: "person.badge.plus").font(.system(size: 13)).foregroundColor(.white)
                .frame(width: 34, height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    // Tab bar: Posts / Reels / Tagged — underline slides with activeTab
    private var igTabBar: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                igTab("square.grid.3x3.fill",  idx: 0)
                igTab("play.rectangle.fill",   idx: 1)
                igTab("person.crop.square",    idx: 2)
            }
            HStack(spacing: 0) {
                Rectangle().fill(Color.white).frame(width: phoneW / 3, height: 1.5)
                    .offset(x: CGFloat(activeTab) * (phoneW / 3))
                Spacer()
            }
            .animation(.easeInOut(duration: 0.32), value: activeTab)
        }
        .frame(height: 40)
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)
    }

    private func igTab(_ icon: String, idx: Int) -> some View {
        // Posts tab (idx==0) shows pulse ring when being confirmed
        ZStack {
            if idx == 0 && postsBtnPulse {
                Circle().stroke(accent.opacity(0.5), lineWidth: 1.8)
                    .frame(width: 28, height: 28)
                    .scaleEffect(postsBtnScale)
                    .opacity(max(0, 2 - postsBtnScale))
                    .animation(.easeOut(duration: 0.55), value: postsBtnScale)
            }
            Image(systemName: icon).font(.system(size: 17))
                .foregroundColor(.white.opacity(activeTab == idx ? 1 : 0.28))
                .scaleEffect(idx == 0 && postsBtnPulse ? 1.25 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.5), value: postsBtnPulse)
        }
        .frame(maxWidth: .infinity).frame(height: 40)
        .animation(.easeInOut(duration: 0.25), value: activeTab)
    }

    // Three paged panels slide with activeTab
    private var pagedTabContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                postsPanel.frame(width: geo.size.width)
                reelsPanel.frame(width: geo.size.width)
                taggedPanel.frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(activeTab) * geo.size.width)
            .animation(.easeInOut(duration: 0.34), value: activeTab)
        }
        .clipped()
    }

    private var postsPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in postCell(i, tab: 0) }
        }
    }

    private var reelsPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in postCell(i, tab: 1) }
        }
    }

    private var taggedPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in postCell(i, tab: 2) }
        }
    }

    private func postCell(_ index: Int, tab: Int) -> some View {
        let isSwipe = activeSwipeCell == index && activeTab == tab
        // Real digit for this cell; override for demo cells so they show 3 and 7
        let digit: Int = {
            if tab == 0 && index == swipe1CellIdx { return demoDigit1 }
            if tab == 1 && index == swipe2CellIdx { return demoDigit2 }
            return cellDigits[index % cellDigits.count]
        }()

        return ZStack {
            ppGradients[index % ppGradients.count]
            // Reel icon for reels tab
            if tab == 1 {
                Image(systemName: "play.fill").font(.system(size: 16)).foregroundColor(.white.opacity(0.3))
            } else if tab == 2 {
                HStack(spacing: -8) {
                    Image(systemName: "person.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.18))
                    Image(systemName: "person.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.10))
                }
            } else {
                Image(systemName: postIcons[index % postIcons.count])
                    .font(.system(size: 16)).foregroundColor(.white.opacity(0.14))
            }
            // Corner digit badge
            VStack { Spacer()
                HStack { Spacer()
                    Text("\(digit)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.32))).padding(4)
                }
            }
            // Swipe trail
            if isSwipe {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.09))
                    VStack { Spacer()
                        HStack(spacing: 2) {
                            Capsule().fill(.white.opacity(0.75))
                                .frame(width: max(1, 28 * swipeTrail), height: 2.5)
                            Image(systemName: "arrow.left")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(swipeTrail * 0.85))
                        }
                        .padding(.leading, 5).padding(.bottom, 5)
                    }
                }
            }
        }
        .frame(height: cellH)
        .animation(.easeInOut(duration: 0.12), value: isSwipe)
    }

    // MARK: - Reveal scene (Posts grid + new unarchived photo card)

    private var revealScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar
                igProfileStats
                igBioLine
                igActionButtons
                // Tab bar locked on Posts
                ZStack(alignment: .bottom) {
                    HStack(spacing: 0) {
                        igTab("square.grid.3x3.fill",  idx: 0)
                        igTab("play.rectangle.fill",   idx: 1)
                        igTab("person.crop.square",    idx: 2)
                    }
                    Rectangle().fill(Color.white).frame(width: phoneW / 3, height: 1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 40)
                .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)

                // Posts grid — first cell is the "new" unarchived photo
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    // Slot 0: unarchived photo
                    revealCell
                    // Remaining archived slots
                    ForEach(1..<12) { i in
                        ZStack {
                            ppGradients[i % ppGradients.count]
                            Rectangle().fill(Color.black.opacity(0.38))
                            Image(systemName: postIcons[i % postIcons.count])
                                .font(.system(size: 14)).foregroundColor(.white.opacity(0.14))
                        }
                        .frame(height: cellH)
                    }
                }
                Spacer()
            }
        }
    }

    // The newly unarchived photo card — scales in when showRevealCard becomes true
    private var revealCell: some View {
        ZStack {
            // Bright gradient (not archived/dark)
            LinearGradient(
                colors: [Color(hex: "5b21b6"), Color(hex: "1a0f40")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // Centred "37" in large type
            Text("37")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            // Gold border
            if showRevealCard {
                Rectangle().stroke(gold, lineWidth: 2.5)
            }
            // "UNARCHIVED" badge bottom-left
            if showRevealCard {
                VStack { Spacer()
                    HStack {
                        Text("UNARCHIVED")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).tracking(0.4)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(gold).cornerRadius(3).padding(4)
                        Spacer()
                    }
                }
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(height: cellH)
        .scaleEffect(showRevealCard ? 1.0 : 0.5)
        .opacity(showRevealCard ? 1.0 : 0.0)
        .animation(.spring(response: 0.44, dampingFraction: 0.62), value: showRevealCard)
    }

    // MARK: - Shared helpers

    private var digitIndicator: some View {
        VStack(spacing: 2) {
            ZStack {
                if accumDigits.isEmpty {
                    Text("_ _")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                        .transition(.opacity)
                } else {
                    Text(accumDigits.map { "\($0)" }.joined())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .scaleEffect(digitBounce)
            .animation(.spring(response: 0.26, dampingFraction: 0.45), value: digitBounce)
            .animation(.spring(response: 0.3,  dampingFraction: 0.7),  value: accumDigits)

            Text("Nº")
                .font(.system(size: 10, weight: accumDigits.isEmpty ? .regular : .bold))
                .foregroundColor(accumDigits.isEmpty ? .white.opacity(0.4) : accent)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(accumDigits.isEmpty ? 0 : 0.6), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(accumDigits.isEmpty ? 0 : 0.08)))
                .animation(.easeInOut(duration: 0.25), value: accumDigits.isEmpty)
        )
    }

    private func ppStatItem(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
        }
    }

    private var fingerView: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14)).frame(width: 42, height: 42)
            Circle().fill(.white.opacity(0.88)).frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.5), radius: 5)
        }
    }

    private func ppPill(_ n: String, _ label: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(active ? color : color.opacity(0.2)).frame(width: 17, height: 17)
                Text(n).font(.system(size: 10, weight: .bold))
                    .foregroundColor(active ? .white : color)
            }
            Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(active ? color : VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(16)
        .overlay(Capsule().stroke(active ? Color.clear : VaultTheme.Colors.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    // MARK: - Animation loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                await animSwipe()
                if Task.isCancelled { break }
                await animConfirm()
                if Task.isCancelled { break }
                await animReveal()
            }
        }
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // Swipe on a cell inside a tab, then slide to the next tab — registers a digit
    @MainActor
    private func doTabSwipe(cellIdx: Int, digit: Int, nextTab: Int) async {
        let c = cellCenter(cellIdx)
        withAnimation(.none) {
            fingerOffset = CGSize(width: c.width + 22, height: c.height)
            activeSwipeCell = cellIdx; swipeTrail = 0
        }
        withAnimation(.easeIn(duration: 0.18)) { showFinger = true }
        await sleep(0.28)

        // Swipe motion + tab slides mid-swipe
        withAnimation(.easeIn(duration: 0.12)) { swipeTrail = 1 }
        withAnimation(.easeOut(duration: 0.50)) {
            fingerOffset = CGSize(width: c.width - 22, height: c.height)
        }
        await sleep(0.25)
        withAnimation(.easeInOut(duration: 0.34)) { activeTab = nextTab }
        await sleep(0.30)

        withAnimation(.easeOut(duration: 0.14)) { swipeTrail = 0; activeSwipeCell = nil }

        // Register digit with bounce in indicator
        withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) { accumDigits.append(digit) }
        digitBounce = 1.5
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { digitBounce = 1.0 }

        await sleep(0.2)
        withAnimation(.easeOut(duration: 0.14)) { showFinger = false }
        await sleep(0.18)
    }

    @MainActor
    private func animSwipe() async {
        withAnimation(.none) {
            accumDigits = []; activeTab = 0; showFinger = false; fingerOffset = .zero
            activeSwipeCell = nil; swipeTrail = 0; digitBounce = 1
            postsBtnPulse = false; postsBtnScale = 1
            showRevealCard = false; phoneGlow = 0
        }
        withAnimation(.easeInOut(duration: 0.3)) { phase = .swipe }
        await sleep(0.9)

        // Swipe 1: Posts cell[0] (digit 3) → tab slides to Reels
        await doTabSwipe(cellIdx: swipe1CellIdx, digit: demoDigit1, nextTab: 1)
        await sleep(2.2)   // pause so viewer sees "3" in the indicator clearly

        // Swipe 2: Reels cell[6] (digit 7) → tab slides to Tagged
        await doTabSwipe(cellIdx: swipe2CellIdx, digit: demoDigit2, nextTab: 2)
        await sleep(0.5)
        withAnimation(.easeOut(duration: 0.2)) { showFinger = false }
        await sleep(0.4)
    }

    @MainActor
    private func animConfirm() async {
        withAnimation(.easeInOut(duration: 0.25)) { phase = .confirm }
        await sleep(0.4)

        // Move finger from Reels swipe cell to Posts tab button
        withAnimation(.none) {
            showFinger = true
            fingerOffset = cellCenter(swipe2CellIdx)
        }
        await sleep(0.08)
        withAnimation(.easeInOut(duration: 0.5)) { fingerOffset = postsTabCenter }
        await sleep(0.58)

        // Tap Posts button — pulse ring + scale
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            postsBtnPulse = true; postsBtnScale = 1.65
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await sleep(0.2)
        withAnimation(.easeOut(duration: 0.3)) { postsBtnScale = 1.0 }
        await sleep(0.5)
        withAnimation(.easeOut(duration: 0.15)) { showFinger = false }
        await sleep(0.6)
    }

    @MainActor
    private func animReveal() async {
        withAnimation(.easeInOut(duration: 0.38)) { phase = .reveal; postsBtnPulse = false }
        await sleep(0.5)

        // New photo pops in with spring + golden glow
        withAnimation(.spring(response: 0.44, dampingFraction: 0.62)) { showRevealCard = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.3)) { phoneGlow = 1 }
        await sleep(3.2)
        withAnimation(.easeOut(duration: 0.3)) { phoneGlow = 0 }
        await sleep(0.3)
    }
}

// MARK: - ── PPCovertTypingDemo ─────────────────────────────────────────────────
// Demonstrates Covert Typing used while searching a profile in Instagram Explore.
// The Explore search bar shows the cover word; the app secretly records the real one.

private struct PPCovertTypingDemo: View {

    @State private var secretChars:  [Character] = []
    @State private var visibleChars: [Character] = []
    @State private var currentKey:   String?     = nil
    @State private var keyScale:     CGFloat     = 1.0
    @State private var revealPhase:  Bool        = false
    @State private var loopTask:     Task<Void, Never>? = nil

    private let blue = Color(hex: "0095F6")

    private let secretWord: [Character] = Array("MAGIC")
    private let coverWord:  [Character] = Array("sport")   // lowercase = search style

    var body: some View {
        VStack(spacing: 12) {
            // Context note
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(blue).font(.system(size: 11)).padding(.top, 1)
                Text("The magician **searches a profile in Explore** — typing secretly registers the spectator's word while the search bar shows an innocent cover text")
                    .font(.system(size: 11))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .background(blue.opacity(0.07))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(blue.opacity(0.18), lineWidth: 1))

            // Mini phone showing Instagram Explore + search bar
            exploreMockup

            // Animated key press
            ZStack {
                if let key = currentKey {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 40, height: 40)
                        Text(key)
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(keyScale)
                    .animation(.spring(response: 0.18, dampingFraction: 0.5), value: keyScale)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: currentKey)

            // Reveal banner
            if revealPhase {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill").foregroundColor(blue)
                    Text("Unarchiving **MAGIC**…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(blue.opacity(0.1))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(blue.opacity(0.3), lineWidth: 1))
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(VaultTheme.Spacing.lg)
        .background(Color(hex: "0a0a0a"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(blue.opacity(0.22), lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: revealPhase)
        .onAppear  { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    // Mini phone showing Instagram Explore with typing in the search bar
    private var exploreMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Color(hex: "111111"))
                .frame(width: 234, height: 148)
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: "060606"))
                .frame(width: 222, height: 136)

            VStack(spacing: 6) {
                // Nav bar
                HStack {
                    Spacer()
                    Text("Explorar")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    Spacer()
                }

                // Search bar — visible cover text typed here
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.38))
                    HStack(spacing: 0) {
                        Text(String(visibleChars))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .animation(.spring(response: 0.2), value: visibleChars.count)
                        if !visibleChars.isEmpty {
                            Rectangle().fill(.white.opacity(0.75))
                                .frame(width: 1.5, height: 11)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .frame(width: 202)

                // 2-row explore grid (profiles) below search
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                    ForEach(0..<8) { i in
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ppExploreColors[i % ppExploreColors.count])
                            Image(systemName: ppExploreIcons[i % ppExploreIcons.count])
                                .font(.system(size: 10)).foregroundColor(.white.opacity(0.22))
                        }
                        .frame(height: 36)
                    }
                }
                .frame(width: 202)

                // Secret indicator — only visible to magician (app layer)
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundColor(blue)
                    Text("App records:")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
                    Text(secretChars.isEmpty ? "—" : String(secretChars))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(blue)
                        .animation(.spring(response: 0.2), value: secretChars.count)
                }
                .frame(width: 202, alignment: .leading)
            }
            .frame(width: 214, height: 128)
        }
    }

    private let ppExploreColors: [Color] = [
        Color(hex: "2d1b69"), Color(hex: "1a3a5c"), Color(hex: "1a3d2e"), Color(hex: "3d2010"),
        Color(hex: "1a2a5c"), Color(hex: "0d3d2a"), Color(hex: "3d0d2a"), Color(hex: "1a3a1a")
    ]
    private let ppExploreIcons = ["mountain.2.fill","tree.fill","sun.horizon.fill",
                                  "camera.fill","star.fill","music.note","flame.fill","heart.fill"]

    // MARK: - Animation

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                await animTyping()
                if Task.isCancelled { break }
                await animReveal()
            }
        }
    }

    @MainActor
    private func animTyping() async {
        withAnimation(.none) {
            secretChars = []; visibleChars = []; currentKey = nil
            revealPhase = false; keyScale = 1
        }
        await sleep(0.8)

        for i in 0..<secretWord.count {
            if Task.isCancelled { return }
            let keyStr = String(secretWord[i])

            withAnimation(.spring(response: 0.18)) { currentKey = keyStr; keyScale = 0.72 }
            await sleep(0.07)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.38)) { keyScale = 1.22 }
            await sleep(0.10)
            withAnimation(.spring(response: 0.2)) { keyScale = 1.0 }

            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                secretChars.append(secretWord[i])
                visibleChars.append(coverWord[i])
            }
            UISelectionFeedbackGenerator().selectionChanged()
            await sleep(0.7)
        }

        withAnimation(.easeOut(duration: 0.22)) { currentKey = nil }
        await sleep(0.7)
    }

    @MainActor
    private func animReveal() async {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { revealPhase = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await sleep(2.5)
        withAnimation(.easeOut(duration: 0.3)) { revealPhase = false }
        await sleep(0.5)
    }
}

// MARK: - ── PPBanksDemo ────────────────────────────────────────────────────────
// Animated explanation of Sets & Banks:
//   Phase 1 — Bank 1: 26 photos (A-Z) upload one by one, counter 1→26
//   Phase 2 — Bank 1 shrinks to pill; Bank 2 uploads and shrinks
//   Phase 3 — Bank 3 uploads and shrinks
//   Phase 4 — Word "CAT" is chosen: C extracted from Bank 1,
//              A from Bank 2, T from Bank 3 → result row [C][A][T]

private struct PPBanksDemo: View {

    enum BankPhase { case upload1, upload2, upload3, select }

    @State private var phase: BankPhase = .upload1

    // Upload counters (0..26) and cell states (9 visible cells per bank)
    @State private var count1: Int = 0
    @State private var count2: Int = 0
    @State private var count3: Int = 0
    @State private var cells1: [Bool] = Array(repeating: false, count: 9)
    @State private var cells2: [Bool] = Array(repeating: false, count: 9)
    @State private var cells3: [Bool] = Array(repeating: false, count: 9)
    @State private var bank1Done: Bool = false
    @State private var bank2Done: Bool = false
    @State private var bank3Done: Bool = false

    // Select phase
    @State private var highlightBank: Int = -1
    @State private var highlightCell: Int = -1
    @State private var revealedLetters: [String] = []

    @State private var loopTask: Task<Void, Never>? = nil

    private let accent = Color(hex: "A78BFA")

    // Bank accent colors
    private let bankColors: [Color] = [
        Color(hex: "6366F1"), Color(hex: "0095F6"), Color(hex: "10B981")
    ]

    // 9 visible letter cells per bank (A-I, A-I, R-Z)
    // Target: C (bank1, idx 2), A (bank2, idx 0), T (bank3, idx 2)
    private let bankCells: [[String]] = [
        ["A","B","C","D","E","F","G","H","I"],
        ["A","B","C","D","E","F","G","H","I"],
        ["R","S","T","U","V","W","X","Y","Z"]
    ]
    private let targetCells   = [2, 0, 2]
    private let targetLetters = ["C","A","T"]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            // Phase pills
            HStack(spacing: 5) {
                bPill("1", "Upload", active: phase != .select)
                bPill("2", "Banks",  active: phase == .select && revealedLetters.isEmpty)
                bPill("3", "Reveal", active: !revealedLetters.isEmpty)
            }

            // Main content
            Group {
                switch phase {
                case .upload1:
                    uploadView(bank: 0, count: count1, cells: cells1, done: bank1Done)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .upload2:
                    uploadView(bank: 1, count: count2, cells: cells2, done: bank2Done)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .upload3:
                    uploadView(bank: 2, count: count3, cells: cells3, done: bank3Done)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                case .select:
                    selectView
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 190)
            .animation(.easeInOut(duration: 0.38), value: phase)

            // Caption
            Group {
                switch phase {
                case .upload1:
                    Text("26 photos (A–Z) upload as **Bank 1** — one image archived per letter")
                case .upload2:
                    Text("Bank 1 ✓ ready. A second full set uploads as **Bank 2**")
                case .upload3:
                    Text("Bank 2 ✓ ready. A third set uploads as **Bank 3**")
                case .select:
                    revealedLetters.isEmpty
                    ? Text("Each bank = one full A–Z set. A word uses one letter from each bank in order")
                    : Text("**C** from Bank 1 · **A** from Bank 2 · **T** from Bank 3 → photos revealed on Instagram")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 36)
            .animation(.easeInOut(duration: 0.3), value: phase)
            .animation(.easeInOut(duration: 0.3), value: revealedLetters.count)
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(accent.opacity(0.25), lineWidth: 1))
        .onAppear  { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Upload view (large, single bank)

    private func uploadView(bank: Int, count: Int, cells: [Bool], done: Bool) -> some View {
        let color = bankColors[bank]
        return VStack(spacing: 10) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(color).font(.system(size: 15))
                    .animation(.easeInOut(duration: 0.2), value: done)
                Text("BANK \(bank + 1)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Spacer()
                HStack(spacing: 3) {
                    Text("\(min(count, 26))")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(done ? color : .white)
                        .animation(.spring(response: 0.15), value: count)
                    Text("/ 26")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.38))
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13)).foregroundColor(color)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
            }

            // 3×3 letter grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(0..<9) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(cells[i] ? color.opacity(0.16) : Color.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(cells[i] ? color.opacity(0.55) : Color.white.opacity(0.07), lineWidth: 1)
                        if cells[i] {
                            Text(bankCells[bank][i])
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(color)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                    }
                    .frame(height: 44)
                    .animation(.spring(response: 0.24, dampingFraction: 0.62), value: cells[i])
                }
            }

            Text("+ 17 more letters archived invisibly")
                .font(.system(size: 9)).foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(color.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(color.opacity(done ? 0.5 : 0.18), lineWidth: 1.2))
    }

    // MARK: - Select view (3 banks side by side + result row)

    private var selectView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<3) { b in bankColumn(bank: b) }
            }

            // Word label
            HStack(spacing: 4) {
                Image(systemName: "text.cursor").font(.system(size: 11)).foregroundColor(accent)
                Text("Spectator's word: **CAT**")
                    .font(.system(size: 12)).foregroundColor(VaultTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Result row
            if !revealedLetters.isEmpty {
                HStack(spacing: 10) {
                    ForEach(revealedLetters.indices, id: \.self) { i in
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(bankColors[i].opacity(0.16))
                                .frame(width: 52, height: 58)
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(bankColors[i], lineWidth: 1.8)
                                .frame(width: 52, height: 58)
                            VStack(spacing: 2) {
                                Text(revealedLetters[i])
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(bankColors[i])
                                Text("Bank \(i+1)")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(bankColors[i].opacity(0.65))
                            }
                        }
                        .transition(.scale(scale: 0.25).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.62), value: revealedLetters.count)
            }
        }
    }

    private func bankColumn(bank: Int) -> some View {
        let color = bankColors[bank]
        return VStack(spacing: 4) {
            Text("BANK \(bank + 1)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color).tracking(0.4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(0..<9) { i in
                    let isTarget   = i == targetCells[bank]
                    let isHighlit  = highlightBank == bank && highlightCell == i
                    let isRevealed = revealedLetters.count > bank && isTarget

                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill((isHighlit || isRevealed) ? color.opacity(0.26) : Color.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: 4)
                            .stroke((isHighlit || isRevealed) ? color : Color.white.opacity(0.07),
                                    lineWidth: isHighlit ? 1.6 : 0.8)
                        Text(bankCells[bank][i])
                            .font(.system(size: 9, weight: isTarget ? .bold : .regular, design: .monospaced))
                            .foregroundColor((isHighlit || isRevealed) ? color : .white.opacity(0.32))
                    }
                    .frame(height: 26)
                    .scaleEffect(isHighlit ? 1.2 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isHighlit)
                    .animation(.easeInOut(duration: 0.2), value: isRevealed)
                }
            }

            Text("…+17")
                .font(.system(size: 7)).foregroundColor(.white.opacity(0.2))

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(color)
        }
        .padding(6)
        .background(color.opacity(0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.22), lineWidth: 0.8))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func bPill(_ n: String, _ label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(active ? accent : accent.opacity(0.2)).frame(width: 17, height: 17)
                Text(n).font(.system(size: 10, weight: .bold))
                    .foregroundColor(active ? .white : accent)
            }
            Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(active ? accent : VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(16)
        .overlay(Capsule().stroke(active ? Color.clear : VaultTheme.Colors.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // MARK: - Animation loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                await animUpload(bank: 0)
                if Task.isCancelled { break }
                await animUpload(bank: 1)
                if Task.isCancelled { break }
                await animUpload(bank: 2)
                if Task.isCancelled { break }
                await animSelect()
            }
        }
    }

    @MainActor
    private func animUpload(bank: Int) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch bank {
            case 0: phase = .upload1; count1 = 0; cells1 = Array(repeating: false, count: 9); bank1Done = false
            case 1: phase = .upload2; count2 = 0; cells2 = Array(repeating: false, count: 9); bank2Done = false
            default: phase = .upload3; count3 = 0; cells3 = Array(repeating: false, count: 9); bank3Done = false
            }
        }
        await sleep(0.5)

        for n in 1...26 {
            if Task.isCancelled { return }
            // Map counter position 1..26 → cell index 0..8 evenly
            let cellIdx = min(8, Int((Double(n - 1) / 25.0) * 8.0))
            withAnimation(.easeIn(duration: 0.05)) {
                switch bank {
                case 0:
                    count1 = n
                    if !cells1[cellIdx] { cells1[cellIdx] = true }
                case 1:
                    count2 = n
                    if !cells2[cellIdx] { cells2[cellIdx] = true }
                default:
                    count3 = n
                    if !cells3[cellIdx] { cells3[cellIdx] = true }
                }
            }
            let delay: Double = n < 8 ? 0.12 : n < 18 ? 0.08 : 0.05
            await sleep(delay)
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            switch bank {
            case 0: bank1Done = true
            case 1: bank2Done = true
            default: bank3Done = true
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await sleep(1.0)
    }

    @MainActor
    private func animSelect() async {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .select
            highlightBank = -1; highlightCell = -1; revealedLetters = []
        }
        await sleep(1.2)

        for i in 0..<3 {
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                highlightBank = i; highlightCell = targetCells[i]
            }
            UISelectionFeedbackGenerator().selectionChanged()
            await sleep(0.7)

            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                revealedLetters.append(targetLetters[i])
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            await sleep(0.9)

            withAnimation(.easeOut(duration: 0.2)) {
                highlightBank = -1; highlightCell = -1
            }
            await sleep(0.25)
        }
        await sleep(3.0)
    }
}
