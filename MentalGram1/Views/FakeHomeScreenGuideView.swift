import SwiftUI

struct FakeHomeScreenGuideView: View {
    let onClose: () -> Void
    private let accent = Color(hex: "30D158")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    VStack(alignment: .leading, spacing: 0) {
                        guideSection(icon: "iphone.homebutton", iconColor: accent,
                                     title: String(localized: "guide.fakehome.help.what.title")) {
                            guideBody(String(localized: "guide.fakehome.help.what.body"))
                        }
                        sectionDivider
                        guideSection(icon: "hand.tap.fill", iconColor: accent,
                                     title: String(localized: "guide.fakehome.help.how.title")) {
                            guideBody(String(localized: "guide.fakehome.help.how.body"))
                        }
                        sectionDivider
                        guideSection(icon: "eye.slash.fill", iconColor: accent,
                                     title: String(localized: "guide.fakehome.help.why.title")) {
                            guideBody(String(localized: "guide.fakehome.help.why.body"))
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
                Image(systemName: "iphone.homebutton")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.top, 8)

            Text(String(localized: "guide.fakehome.title"))
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, VaultTheme.Spacing.lg)

            Text(String(localized: "guide.fakehome.subtitle"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .padding(.horizontal, VaultTheme.Spacing.lg)
        }
    }

    // MARK: - Helpers

    private func guideSection<C: View>(icon: String, iconColor: Color, title: String,
                                       @ViewBuilder content: () -> C) -> some View {
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

    private func guideBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sectionDivider: some View {
        Divider().background(Color.white.opacity(0.08))
    }
}
