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
            PPInfoBox(text: "postpred.help.howitworks.info")
        }
    }

    // MARK: - Input Methods

    private var inputMethods: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            PPBodyText("postpred.help.inputs.body1")

            PPShowStep(
                label: "postpred.help.input.grid.label",
                labelColor: VaultTheme.Colors.primary,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.grid.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.grid.step2", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.grid.step3", dialogue: nil)
                ]
            )

            PPShowStep(
                label: "postpred.help.input.ocr.label",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    PPShowStepItem(action: "postpred.help.input.ocr.step1", dialogue: nil),
                    PPShowStepItem(action: "postpred.help.input.ocr.step2", dialogue: nil)
                ]
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
        }
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
