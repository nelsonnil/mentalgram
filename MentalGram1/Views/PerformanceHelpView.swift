import SwiftUI

// MARK: - Performance Help View

struct PerformanceHelpView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                perfTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        overviewSection
                        plusButtonSection
                        profileSection
                        bottomBarSection
                        exploreSection
                        realDataSection
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

    private var perfTopBar: some View {
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
                Text("Performance")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Overview

    private var overviewSection: some View {
        perfSection(icon: "iphone", iconColor: VaultTheme.Colors.primary, title: "perf.help.overview.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("perf.help.overview.body1")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                perfInfoBox(
                    icon: "wifi",
                    iconColor: VaultTheme.Colors.primary,
                    text: "perf.help.overview.infobox",
                    bgColor: VaultTheme.Colors.primary
                )

                Text("perf.help.overview.body2")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The + Button → Settings

    private var plusButtonSection: some View {
        perfSection(icon: "plus.circle.fill", iconColor: VaultTheme.Colors.success, title: "perf.help.plus.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("perf.help.plus.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Visual mock of the + button location
                plusButtonMock

                perfInfoBox(
                    icon: "gearshape.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "perf.help.plus.infobox",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    private var plusButtonMock: some View {
        // Header bar mock — + is top-left, username in center, menu icons on right
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // + button — highlighted
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VaultTheme.Colors.success.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus.app")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.success)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VaultTheme.Colors.success.opacity(0.5), lineWidth: 1.5)
                )

                Spacer()

                // Username centre
                HStack(spacing: 4) {
                    Text("username")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.black.opacity(0.4))
                }

                Spacer()

                // Right icons
                HStack(spacing: 14) {
                    Image(systemName: "at")
                        .font(.system(size: 18))
                        .foregroundColor(.black.opacity(0.35))
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18))
                        .foregroundColor(.black.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)

            // Label below the header
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(VaultTheme.Colors.success)
                Text("perf.help.plus.mock.sublabel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(VaultTheme.Colors.success)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(VaultTheme.Colors.success.opacity(0.06))
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VaultTheme.Colors.success.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Profile area (followers, tabs)

    private var profileSection: some View {
        perfSection(icon: "person.crop.circle.fill", iconColor: Color(hex: "FF9F0A"), title: "perf.help.profile.title") {
            VStack(alignment: .leading, spacing: 12) {
                // Followers row
                perfFeatureRow(
                    icon: "arrow.up.forward.app.fill",
                    iconColor: Color(hex: "E1306C"),
                    title: "perf.help.profile.pic.title",
                    desc: "perf.help.profile.pic.desc"
                )

                perfFeatureRow(
                    icon: "person.2.fill",
                    iconColor: Color(hex: "BF5AF2"),
                    title: "perf.help.profile.followers.title",
                    desc: "perf.help.profile.followers.desc"
                )

                perfFeatureRow(
                    icon: "square.grid.3x3.fill",
                    iconColor: Color(hex: "FF9F0A"),
                    title: "perf.help.profile.tabs.title",
                    desc: "perf.help.profile.tabs.desc"
                )

                perfFeatureRow(
                    icon: "arrow.clockwise",
                    iconColor: VaultTheme.Colors.primary,
                    title: "perf.help.profile.refresh.title",
                    desc: "perf.help.profile.refresh.desc"
                )

                // Profile tabs mock
                profileTabsMock
            }
        }
    }

    private var profileTabsMock: some View {
        HStack(spacing: 0) {
            ForEach([
                ("square.grid.3x3", "perf.help.mock.posts"),
                ("play.rectangle", "perf.help.mock.reels"),
                ("person.crop.square", "perf.help.mock.tagged")
            ], id: \.0) { icon, label in
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(icon == "square.grid.3x3" ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.textSecondary)
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(icon == "square.grid.3x3" ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    Rectangle()
                        .fill(icon == "square.grid.3x3" ? VaultTheme.Colors.textPrimary : Color.clear)
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
        }
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Bottom navigation bar

    private var bottomBarSection: some View {
        perfSection(icon: "rectangle.bottomthird.inset.filled", iconColor: Color(hex: "E63946"), title: "perf.help.bottombar.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("perf.help.bottombar.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                bottomBarMock

                perfInfoBox(
                    icon: "magnifyingglass",
                    iconColor: Color(hex: "E63946"),
                    text: "perf.help.bottombar.infobox",
                    bgColor: Color(hex: "E63946")
                )
            }
        }
    }

    private var bottomBarMock: some View {
        HStack(spacing: 0) {
            ForEach([
                ("house", "perf.help.mock.home", false),
                ("play.rectangle", "perf.help.mock.reels", false),
                ("paperplane", "perf.help.mock.send", false),
                ("magnifyingglass", "perf.help.mock.search", true),
                ("person.crop.circle", "perf.help.mock.profile", false)
            ], id: \.0) { icon, label, isActive in
                VStack(spacing: 4) {
                    ZStack {
                        if isActive {
                            Circle()
                                .fill(Color(hex: "E63946").opacity(0.15))
                                .frame(width: 32, height: 32)
                        }
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isActive ? Color(hex: "E63946") : VaultTheme.Colors.textSecondary.opacity(0.35))
                    }
                    Text(label)
                        .font(.system(size: 8, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? Color(hex: "E63946") : VaultTheme.Colors.textSecondary.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .overlay(
                    isActive ? AnyView(
                        Text("perf.help.mock.active")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(hex: "E63946"))
                            .clipShape(Capsule())
                            .offset(y: -22)
                    ) : AnyView(EmptyView())
                )
            }
        }
        .padding(.vertical, 10)
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Explore

    private var exploreSection: some View {
        perfSection(icon: "magnifyingglass", iconColor: Color(hex: "6366F1"), title: "perf.help.explore.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("perf.help.explore.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                perfFeatureRow(
                    icon: "play.rectangle.fill",
                    iconColor: Color(hex: "6366F1"),
                    title: "perf.help.explore.reels.title",
                    desc: "perf.help.explore.reels.desc"
                )

                perfFeatureRow(
                    icon: "person.crop.circle.badge.magnifyingglass",
                    iconColor: VaultTheme.Colors.primary,
                    title: "perf.help.explore.search.title",
                    desc: "perf.help.explore.search.desc"
                )

                perfInfoBox(
                    icon: "lightbulb.fill",
                    iconColor: Color(hex: "6366F1"),
                    text: "perf.help.explore.infobox",
                    bgColor: Color(hex: "6366F1")
                )
            }
        }
    }

    // MARK: - Real data

    private var realDataSection: some View {
        perfSection(icon: "link.circle.fill", iconColor: VaultTheme.Colors.success, title: "perf.help.realdata.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("perf.help.realdata.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    dataRow(icon: "photo.stack.fill",    color: VaultTheme.Colors.success,  text: "perf.help.realdata.item1")
                    dataRow(icon: "person.2.fill",        color: Color(hex: "BF5AF2"),       text: "perf.help.realdata.item2")
                    dataRow(icon: "play.rectangle.fill",  color: VaultTheme.Colors.primary,   text: "perf.help.realdata.item3")
                    dataRow(icon: "text.alignleft",       color: Color(hex: "FF9F0A"),       text: "perf.help.realdata.item4")
                }
                .padding(12)
                .background(VaultTheme.Colors.cardBackground)
                .cornerRadius(10)
            }
        }
    }

    private func dataRow(icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared helpers

    private func perfSection<Content: View>(
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

    private func perfInfoBox(icon: String, iconColor: Color, text: LocalizedStringKey, bgColor: Color) -> some View {
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

    private func perfFeatureRow(icon: String, iconColor: Color, title: LocalizedStringKey, desc: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
