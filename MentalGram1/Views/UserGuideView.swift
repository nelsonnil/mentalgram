import SwiftUI

// MARK: - User Guide View

struct UserGuideView: View {

    // Active sheet
    @State private var activeSheet: GuideSheet? = nil
    @State private var communityPasswordCopied = false

    // PDF export
    @StateObject private var pdfExporter = UserGuidePDFExporter()
    @State private var pdfURL: URL? = nil
    @State private var showShareSheet = false
    private let tutorialPlaylistURL = URL(string: "https://www.youtube.com/playlist?list=PLpz4HmN92GnS9twqdEhzxk28iulTv1nxe")!

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
        case transposition
        case fakeHomeScreen
        case lockscreenInput
        case amnesiaCarousel
        case faq
        case inputMethods

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
            case .transposition:   return 11
            case .fakeHomeScreen:  return 12
            case .lockscreenInput: return 13
            case .amnesiaCarousel: return 14
            case .faq:             return 15
            case .inputMethods:    return 16
            }
        }
    }

    // Colors matching HomeView
    private let colorProfile   = Color(hex: "FF9F0A")
    private let colorTricks    = Color(hex: "BF5AF2")
    private let colorStart     = Color(hex: "0A84FF")
    private let colorData      = Color(hex: "30D158")
    private let colorCommunity = Color(hex: "1877F2")

    var body: some View {
        ZStack {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    learningResourcesCard

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

                    // INPUT METHODS
                    guideSectionLabel("input.guide.section.label", icon: "hand.tap.fill", color: Color(hex: "BF5AF2"))
                    guideCardGroup {
                        guideRow(
                            icon: "hand.tap.fill",
                            iconColor: Color(hex: "BF5AF2"),
                            title: "input.guide.row.title",
                            subtitle: "input.guide.row.subtitle",
                            isFirst: true, isLast: true
                        ) { activeSheet = .inputMethods }
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
                            icon: "camera.viewfinder",
                            iconColor: colorTricks,
                            title: "Transposition",
                            subtitle: "Identify a spectator-selected public Instagram post with AI and reveal it",
                            badge: "PRO",
                            isFirst: false, isLast: false
                        ) { activeSheet = .transposition }

                        guideDivider
                        guideRow(
                            icon: "rectangle.on.rectangle.slash.fill",
                            iconColor: colorTricks,
                            title: "guide.amnesia.row.title",
                            subtitle: "guide.amnesia.row.subtitle",
                            isFirst: false, isLast: true
                        ) { activeSheet = .amnesiaCarousel }
                    }

                    // FAQ is temporarily hidden from the guide list. Keep the sheet
                    // and translations in place so it can be re-enabled quickly.
                    if false {
                        guideSectionLabel("guide.faq.section", icon: "questionmark.circle.fill", color: Color(hex: "64D2FF"))
                        guideCardGroup {
                            guideRow(
                                icon: "questionmark.circle.fill",
                                iconColor: Color(hex: "64D2FF"),
                                title: "guide.faq.row.title",
                                subtitle: "guide.faq.row.subtitle",
                                isFirst: true, isLast: true
                            ) { activeSheet = .faq }
                        }
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

                    // COMMUNITY
                    guideSectionLabel("COMMUNITY", icon: "person.3.fill", color: colorCommunity)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "1C1C1E"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(colorCommunity.opacity(0.35), lineWidth: 1)
                            )
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorCommunity)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Facebook Group")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Updates, routines, ideas & community")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "EBEBF599"))
                                }
                                Spacer()
                            }
                            Text("Join the private group to discover new updates, share your routines, get ideas and connect with other performers using the app.")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "EBEBF599"))
                                .fixedSize(horizontal: false, vertical: true)
                            // Password row — tap to copy
                            Button {
                                UIPasteboard.general.string = "vault67"
                                withAnimation(.easeInOut(duration: 0.2)) { communityPasswordCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { communityPasswordCopied = false }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(colorCommunity)
                                    Text("Password: ") + Text("vault67").bold()
                                    Spacer()
                                    Image(systemName: communityPasswordCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 14))
                                        .foregroundColor(communityPasswordCopied ? .green : Color(hex: "EBEBF599"))
                                    Text(communityPasswordCopied ? "Copied!" : "Copy")
                                        .font(.system(size: 12))
                                        .foregroundColor(communityPasswordCopied ? .green : Color(hex: "EBEBF599"))
                                }
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(hex: "2C2C2E"))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            Link(destination: URL(string: "https://www.facebook.com/share/g/1bj4vp4GoX/?mibextid=wwXIfr")!) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.system(size: 15))
                                    Text("Join the Facebook Group")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorCommunity)
                                .cornerRadius(12)
                            }
                        }
                        .padding(16)
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
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheetView(items: [url]) {
                    showShareSheet = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Learning resources

    private var learningResourcesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "FF9F0A").opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "FF9F0A"))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Learning Resources")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Use the video playlist for a fast visual overview, then continue with the in-app guide below. The app guide contains the full details, exact setup steps, safety notes, scripts and performance handling for each routine.")
                        .font(.system(size: 13))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.top, 1)
                Text("Important: after watching the video, follow the instructions inside the app. The videos explain the flow; the in-app guide is the complete reference for preparing and performing safely.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(hex: "FFCC00"))
            .cornerRadius(10)

            HStack(spacing: 10) {
                Button {
                    exportPDF()
                } label: {
                    resourceButtonContent(
                        icon: pdfExporter.isExporting ? "hourglass" : "doc.richtext.fill",
                        title: pdfExporter.isExporting ? "Preparing PDF…" : "Reference PDF",
                        subtitle: "Condensed guide",
                        color: Color(hex: "0A84FF")
                    )
                }
                .buttonStyle(.plain)
                .disabled(pdfExporter.isExporting)

                Link(destination: tutorialPlaylistURL) {
                    resourceButtonContent(
                        icon: "play.rectangle.fill",
                        title: "Video Instructions",
                        subtitle: "YouTube playlist",
                        color: Color(hex: "FF3B30")
                    )
                }
            }
        }
        .padding(16)
        .background(Color(hex: "FF9F0A").opacity(0.08))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "FF9F0A").opacity(0.28), lineWidth: 1)
        )
    }

    private func resourceButtonContent(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(color)
        .cornerRadius(12)
    }

    private func exportPDF() {
        Task {
            if let url = await pdfExporter.export() {
                pdfURL = url
                showShareSheet = true
            }
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
        case .transposition:
            TranspositionHelpView(onClose: { activeSheet = nil })
        case .fakeHomeScreen:
            FakeHomeScreenGuideView(onClose: { activeSheet = nil })
        case .lockscreenInput:
            LockscreenInputGuideView(onClose: { activeSheet = nil })
        case .amnesiaCarousel:
            AmnesiaCarouselGuideView(onClose: { activeSheet = nil })
        case .faq:
            FAQHelpView(onClose: { activeSheet = nil })
        case .inputMethods:
            InputMethodsHelpView(onClose: { activeSheet = nil })
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
