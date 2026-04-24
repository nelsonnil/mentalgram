import SwiftUI

// MARK: - Limits & Safety Help View (simplified & reassuring)

struct LimitsHelpView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                limitsTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dontWorrySection
                        ifWarningSection
                        duringShowSection
                        bestPracticesSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Top bar

    private var limitsTopBar: some View {
        ZStack {
            HStack {
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .padding(.trailing, 20)
                }
            }
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                Text("limits.help.title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - 1. Don't worry — reassuring intro

    private var dontWorrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VaultTheme.Colors.success.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.success)
                }
                Text("limits.help.calm.title")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }

            Text("limits.help.calm.body")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            infoBox(
                icon: "checkmark.seal.fill",
                iconColor: VaultTheme.Colors.success,
                text: "limits.help.calm.infobox",
                bgColor: VaultTheme.Colors.success
            )
        }
    }

    // MARK: - 2. If you see a warning — clear steps

    private var ifWarningSection: some View {
        limSection(icon: "exclamationmark.bubble.fill",
                   iconColor: Color(hex: "FF9F0A"),
                   title: "limits.help.warning.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("limits.help.warning.intro")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                stepRow(number: "1", text: "limits.help.warning.step1")
                stepRow(number: "2", text: "limits.help.warning.step2")
                stepRow(number: "3", text: "limits.help.warning.step3")
                stepRow(number: "4", text: "limits.help.warning.step4")

                infoBox(
                    icon: "heart.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "limits.help.warning.reassure",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    // MARK: - 3. During a show

    private var duringShowSection: some View {
        limSection(icon: "theatermasks.fill",
                   iconColor: Color(hex: "A78BFA"),
                   title: "limits.help.show.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("limits.help.show.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "wifi.slash",
                    iconColor: Color(hex: "A78BFA"),
                    text: "limits.help.show.infobox",
                    bgColor: Color(hex: "A78BFA")
                )
            }
        }
    }

    // MARK: - 4. Best practices

    private var bestPracticesSection: some View {
        limSection(icon: "sparkles",
                   iconColor: VaultTheme.Colors.primary,
                   title: "limits.help.best.title") {
            VStack(alignment: .leading, spacing: 10) {
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item1")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item2")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item3")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item4")
            }
        }
    }

    // MARK: - Shared helpers

    private func limSection<Content: View>(
        icon: String, iconColor: Color, title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content()
        }
    }

    private func limBullet(icon: String, iconColor: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoBox(icon: String, iconColor: Color, text: LocalizedStringKey, bgColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(bgColor.opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bgColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func stepRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF9F0A").opacity(0.15))
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "FF9F0A"))
            }
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}
