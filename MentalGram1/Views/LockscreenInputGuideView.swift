import SwiftUI

struct LockscreenInputGuideView: View {
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
                        guideSection(icon: "lock.fill", iconColor: accent,
                                     title: String(localized: "guide.lockscreen.help.what.title")) {
                            guideBody(String(localized: "guide.lockscreen.help.what.body"))
                        }
                        sectionDivider
                        guideSection(icon: "hand.point.up.left.fill", iconColor: accent,
                                     title: String(localized: "guide.lockscreen.help.how.title")) {
                            guideBody(String(localized: "guide.lockscreen.help.how.body"))
                        }
                        sectionDivider
                        guideSection(icon: "photo.fill", iconColor: accent,
                                     title: String(localized: "guide.lockscreen.help.wallpaper.title")) {
                            guideBody(String(localized: "guide.lockscreen.help.wallpaper.body"))
                        }
                        sectionDivider
                        guideSection(icon: "eye.slash.fill", iconColor: accent,
                                     title: String(localized: "guide.lockscreen.help.why.title")) {
                            guideBody(String(localized: "guide.lockscreen.help.why.body"))
                        }
                        sectionDivider
                        guideSection(icon: "square.grid.2x2.fill", iconColor: accent,
                                     title: String(localized: "guide.lockscreen.help.tricks.title")) {
                            guideBody(String(localized: "guide.lockscreen.help.tricks.body"))
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
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.top, 8)

            Text(String(localized: "guide.lockscreen.title"))
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, VaultTheme.Spacing.lg)

            Text(String(localized: "guide.lockscreen.subtitle"))
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
