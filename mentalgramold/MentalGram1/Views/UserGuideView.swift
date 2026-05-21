import SwiftUI

// MARK: - User Guide View

struct UserGuideView: View {

    // Active sheet
    @State private var activeSheet: GuideSheet? = nil

    private enum GuideSheet: Identifiable {
        case introduction
        case limits
        case profilePicture
        case note
        case biography
        case forcePost
        case forceReel
        case postPrediction
        case counterGlitch
        case dateForce

        var id: Int {
            switch self {
            case .introduction:   return 0
            case .limits:         return 1
            case .profilePicture: return 2
            case .note:           return 3
            case .biography:      return 4
            case .forcePost:      return 5
            case .forceReel:      return 6
            case .postPrediction: return 7
            case .counterGlitch:  return 8
            case .dateForce:      return 9
            }
        }
    }

    // Colors matching HomeView
    private let colorProfile = Color(hex: "FF9F0A")
    private let colorTricks  = Color(hex: "BF5AF2")
    private let colorStart   = Color(hex: "0A84FF")

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
                            icon: "square.grid.2x2",
                            iconColor: colorTricks,
                            title: "Force Post",
                            subtitle: "Force a scroll to stop on a specific post",
                            isFirst: true, isLast: false
                        ) { activeSheet = .forcePost }

                        guideDivider
                        guideRow(
                            icon: "hand.point.up.left.fill",
                            iconColor: colorTricks,
                            title: "Force Reel",
                            subtitle: "Place up to 3 reels in Explore to control the choice",
                            isFirst: false, isLast: false
                        ) { activeSheet = .forceReel }

                        guideDivider
                        guideRow(
                            icon: "number.circle.fill",
                            iconColor: colorTricks,
                            title: "Post Prediction",
                            subtitle: "Unarchive photos from the active set to reveal a prediction",
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
                            isFirst: false, isLast: true
                        ) { activeSheet = .dateForce }
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
        }
    }

    // MARK: - Section label

    private func guideSectionLabel(_ title: String, icon: String, color: Color) -> some View {
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
        title: String,
        subtitle: String,
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
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
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
