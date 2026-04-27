import SwiftUI

// MARK: - User Guide View

struct UserGuideView: View {

    // Active sheet
    @State private var activeSheet: GuideSheet? = nil

    private enum GuideSheet: Identifiable {
        case introduction
        case limits
        case performance
        case profilePicture
        case note
        case biography
        case forcePost
        case forceReel
        case postPrediction
        case counterGlitch
        case dateForce
        case fakeHomeScreen
        case lockscreenInput
        case amnesiaCarousel

        var id: Int {
            switch self {
            case .introduction:    return 0
            case .limits:          return 1
            case .performance:     return 2
            case .profilePicture:  return 3
            case .note:            return 4
            case .biography:       return 5
            case .forcePost:       return 6
            case .forceReel:       return 7
            case .postPrediction:  return 8
            case .counterGlitch:   return 9
            case .dateForce:       return 10
            case .fakeHomeScreen:  return 11
            case .lockscreenInput: return 12
            case .amnesiaCarousel: return 13
            }
        }
    }

    // Colors matching HomeView
    private let colorProfile = Color(hex: "FF9F0A")
    private let colorTricks  = Color(hex: "BF5AF2")
    private let colorStart   = Color(hex: "0A84FF")
    private let colorData    = Color(hex: "30D158")

    var body: some View {
        ZStack {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // GETTING STARTED
                    guideSectionLabel("GETTING STARTED", icon: "star.fill", color: colorStart)
                    guideCardGroup {
                        guideRow(
                            icon: "wand.and.stars",
                            iconColor: Color(hex: "A78BFA"),
                            title: "What is Vault?",
                            subtitle: "Introduction, features and the three pillars of Vault",
                            isFirst: true, isLast: false
                        ) { activeSheet = .introduction }

                        guideDivider
                        guideRow(
                            icon: "iphone",
                            iconColor: colorStart,
                            title: "Performance",
                            subtitle: "How the Instagram emulator works — navigation, profiles and Explore",
                            isFirst: false, isLast: false
                        ) { activeSheet = .performance }

                        guideDivider
                        guideRow(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: Color(hex: "FF9F0A"),
                            title: "Limits & Safety",
                            subtitle: "API limits, cooldowns, bot detection and how to recover",
                            isFirst: false, isLast: true
                        ) { activeSheet = .limits }
                    }

                    // INSTAGRAM PROFILE
                    guideSectionLabel("INSTAGRAM PROFILE", icon: "camera.fill", color: colorProfile)
                    guideCardGroup {
                        guideRow(
                            icon: "person.crop.circle.fill",
                            iconColor: colorProfile,
                            title: "Profile Picture",
                            subtitle: "Change your Instagram profile photo as a prediction",
                            isFirst: true, isLast: false
                        ) { activeSheet = .profilePicture }

                        guideDivider
                        guideRow(
                            icon: "bubble.left.fill",
                            iconColor: colorProfile,
                            title: "Note",
                            subtitle: "Post an Instagram note that matches what the spectator thought",
                            isFirst: false, isLast: false
                        ) { activeSheet = .note }

                        guideDivider
                        guideRow(
                            icon: "text.alignleft",
                            iconColor: colorProfile,
                            title: "Biography",
                            subtitle: "Update your bio in real time to reveal a prediction",
                            isFirst: false, isLast: true
                        ) { activeSheet = .biography }
                    }

                    // TRICKS
                    guideSectionLabel("TRICKS", icon: "wand.and.stars", color: colorTricks)
                    guideCardGroup {
                        guideRow(
                            icon: "hand.point.up.left.fill",
                            iconColor: colorTricks,
                            title: "Force Post",
                            subtitle: "Force a scroll to stop on a specific post",
                            isFirst: true, isLast: false
                        ) { activeSheet = .forcePost }

                        guideDivider
                        guideRow(
                            icon: "square.grid.2x2",
                            iconColor: colorTricks,
                            title: "Force Reel",
                            subtitle: "Force a specific reel to appear in Explore",
                            isFirst: false, isLast: false
                        ) { activeSheet = .forceReel }

                        guideDivider
                        guideRow(
                            icon: "number.circle.fill",
                            iconColor: colorTricks,
                            title: "Post Prediction",
                            subtitle: "Unarchive photos from the active set to reveal a prediction",
                            badge: "⭐ Sets",
                            isFirst: false, isLast: false
                        ) { activeSheet = .postPrediction }

                        guideDivider
                        guideRow(
                            icon: "person.2.fill",
                            iconColor: colorTricks,
                            title: "Counter Glitch Effect",
                            subtitle: "Inflate a follower or following count with a countdown",
                            isFirst: false, isLast: false
                        ) { activeSheet = .counterGlitch }

                        guideDivider
                        guideRow(
                            icon: "calendar",
                            iconColor: colorTricks,
                            title: "Date Force",
                            subtitle: "Force followers/following to reveal today's date",
                            isFirst: false, isLast: false
                        ) { activeSheet = .dateForce }

                        guideDivider
                        guideRow(
                            icon: "rectangle.on.rectangle.slash.fill",
                            iconColor: colorTricks,
                            title: "guide.amnesia.row.title",
                            subtitle: "guide.amnesia.row.subtitle",
                            isFirst: false, isLast: true
                        ) { activeSheet = .amnesiaCarousel }
                    }

                    // CAMOUFLAGE
                    guideSectionLabel("guide.section.camouflage", icon: "theatermasks.fill", color: colorData)
                    guideCardGroup {
                        guideRow(
                            icon: "iphone.homebutton",
                            iconColor: colorData,
                            title: "guide.fakehome.title",
                            subtitle: "guide.fakehome.subtitle",
                            isFirst: true, isLast: false
                        ) { activeSheet = .fakeHomeScreen }

                        guideDivider
                        guideRow(
                            icon: "lock.fill",
                            iconColor: colorData,
                            title: "guide.lockscreen.title",
                            subtitle: "guide.lockscreen.subtitle",
                            isFirst: false, isLast: true
                        ) { activeSheet = .lockscreenInput }
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("User Guide")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Sheet content router

    @ViewBuilder
    private func sheetContent(for sheet: GuideSheet) -> some View {
        switch sheet {
        case .introduction:
            IntroductionHelpView(onClose: { activeSheet = nil })
        case .performance:
            PerformanceHelpView(onClose: { activeSheet = nil })
        case .limits:
            LimitsHelpView(onClose: { activeSheet = nil })
        case .profilePicture:
            ProfilePictureHelpView(onClose: { activeSheet = nil })
        case .note:
            NoteHelpView(onClose: { activeSheet = nil })
        case .biography:
            BiographyHelpView(onClose: { activeSheet = nil })
        case .forcePost:
            ForcePostHelpView(onClose: { activeSheet = nil })
        case .forceReel:
            ForceReelHelpView(onClose: { activeSheet = nil })
        case .postPrediction:
            PostPredictionHelpView(onClose: { activeSheet = nil })
        case .counterGlitch:
            CounterGlitchHelpView(onClose: { activeSheet = nil })
        case .dateForce:
            DateForceHelpView(onClose: { activeSheet = nil })
        case .fakeHomeScreen:
            FakeHomeScreenGuideView(onClose: { activeSheet = nil })
        case .lockscreenInput:
            LockscreenInputGuideView(onClose: { activeSheet = nil })
        case .amnesiaCarousel:
            AmnesiaCarouselGuideView(onClose: { activeSheet = nil })
        }
    }

    // MARK: - Section label

    private func guideSectionLabel(_ title: LocalizedStringKey, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .tracking(0.8)
        }
        .padding(.leading, 4)
        .padding(.top, 4)
    }

    // MARK: - Card group container

    private func guideCardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Guide row

    private func guideRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        badge: String? = nil,
        badgeColor: Color = .yellow,
        isFirst: Bool,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(badgeColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Divider

    private var guideDivider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.leading, 68)
    }
}
