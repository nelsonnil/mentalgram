import SwiftUI

// MARK: - Force Post Help View

struct ForcePostHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    ForcePostAnimatedDemo()
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.xl)

                    Group {
                        FPHSection(
                            icon: "wand.and.stars",
                            iconColor: Color(hex: "F97316"),
                            title: "How It Works"
                        ) { howItWorks }

                        fphDivider

                        FPHSection(
                            icon: "list.number",
                            iconColor: VaultTheme.Colors.success,
                            title: "Setup"
                        ) { setupSteps }

                        fphDivider

                        FPHSection(
                            icon: "mic.fill",
                            iconColor: VaultTheme.Colors.warning,
                            title: "During the Show"
                        ) { duringShow }

                        fphDivider

                        FPHSection(
                            icon: "lightbulb.fill",
                            iconColor: Color(hex: "F472B6"),
                            title: "Tips"
                        ) { tipsSection }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // ── Top bar ──────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force Post")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Performance Guide")
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
            .background(
                VaultTheme.Colors.background
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hex: "F97316").opacity(0.15))
                    .frame(width: 80, height: 80)
                Text("🎯")
                    .font(.system(size: 40))
            }
            Text("Force the Scroll")
                .font(VaultTheme.Typography.title())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Before the show you choose a post in Settings. During the performance the spectator scrolls freely — but the app always stops on your pre-chosen image, making them believe the choice was entirely theirs.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var fphDivider: some View {
        Rectangle()
            .fill(VaultTheme.Colors.cardBorder)
            .frame(height: 1)
            .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            FPHBody("Before the show, go to Settings and pick the post you want to force from any Instagram profile. That's all the preparation needed.")
            FPHMetric(
                icon: "gearshape.fill",
                color: Color(hex: "F97316"),
                label: "Prepared in Settings",
                desc: "The selection is made before the performance — the spectator never sees this step. You simply choose the target post from any public profile."
            )
            FPHMetric(
                icon: "figure.walk",
                color: VaultTheme.Colors.primary,
                label: "Spectator scrolls freely",
                desc: "During the show the spectator scrolls through the posts at their own pace. They genuinely believe the choice is completely random."
            )
            FPHMetric(
                icon: "hand.raised.slash.fill",
                color: VaultTheme.Colors.success,
                label: "The app does the work",
                desc: "The moment the scroll starts to slow down, the app intercepts it and lands exactly on your pre-chosen image — invisible to the spectator."
            )
            FPHMetric(
                icon: "person.2.fill",
                color: VaultTheme.Colors.secondary,
                label: "Multiple profiles",
                desc: "Configure one forced post per Instagram profile. Each profile you visit during the show activates the right image automatically."
            )
            FPHInfoBox("After the scroll lands once, the interception releases completely. The spectator can keep scrolling freely — the trick fires only once and feels entirely natural.")
        }
    }

    // MARK: - Setup

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            FPHStep(n: 1, text: "**Before the show**, open Settings and enable **Force Post**.")
            FPHStep(n: 2, text: "Tap **Select Post** — or **Add Another Profile** if you've already configured one.")
            FPHStep(n: 3, text: "Search for the Instagram username of the profile you plan to use during the show.")
            FPHStep(n: 4, text: "Browse their posts and tap the one you want the spectator to land on. A local thumbnail is saved to the device.")
            FPHStep(n: 5, text: "Repeat for each additional profile. Once set up, you don't touch Settings again during the performance.")
        }
    }

    // MARK: - During the Show

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            FPHShowStep(
                label: "GO TO PERFORMANCE",
                color: Color(hex: "F97316"),
                action: "Open Performance and search for the target profile in Explore. You can hand the phone directly to the spectator at this point.",
                dialogue: "\"Take my phone. Open this person's Instagram profile — you can search anyone you like.\""
            )
            FPHShowStep(
                label: "SPECTATOR SCROLLS",
                color: VaultTheme.Colors.primary,
                action: "Tap any post to open the fullscreen viewer. Ask the spectator to scroll through the posts however they want — up, down, fast, slow. Tell them to stop whenever they feel like it.",
                dialogue: "\"Scroll through their posts totally freely. Up, down, as fast or as slow as you like. Stop wherever you want — completely at random.\""
            )
            FPHShowStep(
                label: "THE FORCE",
                color: VaultTheme.Colors.warning,
                action: "As the scroll decelerates, the app silently intercepts it and stops exactly on the post you chose in Settings. The spectator sees it as their own random choice.",
                dialogue: nil
            )
            FPHShowStep(
                label: "THE REVEAL",
                color: VaultTheme.Colors.success,
                action: "Show your prediction — a sealed envelope, a card, or simply name the post. The spectator is convinced they chose it freely.",
                dialogue: "\"Look where you stopped. I predicted that exact image before we even started — because what feels like a free choice… isn't.\""
            )
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            FPHTip(
                icon: "clock.badge.checkmark",
                color: Color(hex: "F97316"),
                text: "**Prepare in advance.** Set up your forced post in Settings well before the show. During the performance you only open Performance — nothing else."
            )
            FPHTip(
                icon: "person.badge.plus",
                color: VaultTheme.Colors.primary,
                text: "**Multiple profiles.** You can load a different forced post for each profile. Useful when you let the spectator choose which Instagram account to visit."
            )
            FPHTip(
                icon: "checkmark.shield.fill",
                color: VaultTheme.Colors.success,
                text: "**Single intercept.** The app fires once and then releases. After landing on the forced post the spectator can scroll freely — it feels completely natural."
            )
            FPHTip(
                icon: "wifi.slash",
                color: VaultTheme.Colors.error,
                text: "**Works offline.** The selected thumbnail is saved locally. The force works even without internet during the show."
            )
            FPHTip(
                icon: "lock.fill",
                color: VaultTheme.Colors.textSecondary,
                text: "**Public profiles only.** The target account must be public — or one you already follow — for its posts to appear in the picker."
            )
        }
    }
}

// MARK: - ── Animated Demo ────────────────────────────────────────────────────

private struct ForcePostAnimatedDemo: View {

    enum Scene { case settings, performance }
    @State private var scene: Scene = .settings

    // Settings scene
    @State private var selectedCell:  Int?    = nil
    @State private var showCheckmark: Bool    = false
    @State private var showSaved:     Bool    = false
    @State private var showFinger:    Bool    = false
    @State private var fingerPos:     CGSize  = CGSize(width: 83, height: 83)
    @State private var fingerScale:   CGFloat = 1.0

    // Performance scene
    @State private var scrollOffset:     CGFloat = 0
    @State private var showForcedBorder: Bool    = false
    @State private var showForcedBadge:  Bool    = false
    @State private var phoneGlow:        Double  = 0
    @State private var showSwipeFinger:  Bool    = false
    @State private var swipeFingerY:     CGFloat = 160

    @State private var loopTask: Task<Void, Never>? = nil

    // ── Phone geometry (matches ForceReel) ───────────────────────────────────
    private let phoneW: CGFloat = 248
    private let phoneH: CGFloat = 492

    // ── Post geometry ─────────────────────────────────────────────────────────
    // Each performance post card: header(34) + image(184) + actions(34) = 252px
    // VStack spacing 2 → unit = 254px per post
    private let postCardH:  CGFloat = 252
    private let postSpacing: CGFloat = 2
    private let forcedPostIdx = 6    // forced post is LAST — never seen while scrolling, only revealed at the end
    private let forcedGridIdx = 4    // cell selected in settings grid (center of 3×3)

    // ── Gradients ─────────────────────────────────────────────────────────────
    private var cellGradients: [LinearGradient] { [
        LinearGradient(colors: [Color(hex: "1a3a5c"), Color(hex: "0d1f3c")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a3d2e"), Color(hex: "0d261c")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2010"), Color(hex: "261408")], startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2d1b69"), Color(hex: "1a0f40")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3D1A1A"), Color(hex: "1a0808")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "0d3d2a"), Color(hex: "061f15")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "3d0d2a"), Color(hex: "260819")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a3a1a"), Color(hex: "0d260d")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2a0d"), Color(hex: "261908")], startPoint: .top,         endPoint: .bottomLeading),
    ] }

    private let cellIcons = ["mountain.2.fill","leaf.fill","cloud.sun.fill","figure.walk",
                              "star.fill","camera.fill","music.note","flame.fill","heart.fill"]

    // Forced (star/orange) is LAST so it is never visible during the scroll —
    // it only appears when the scroll decelerates to a stop.
    private let perfGradients: [(Color, Color)] = [
        (Color(hex: "1B2E44"), Color(hex: "0d1f3c")),  // 0
        (Color(hex: "1A3D2E"), Color(hex: "0d261c")),  // 1
        (Color(hex: "1E1A3D"), Color(hex: "1a0f40")),  // 2
        (Color(hex: "103D2A"), Color(hex: "061f15")),  // 3
        (Color(hex: "2d1b69"), Color(hex: "1a0f40")),  // 4
        (Color(hex: "1a3a1a"), Color(hex: "0d260d")),  // 5
        (Color(hex: "3D1A1A"), Color(hex: "1a0808")),  // 6 — forced (dark red / star)
    ]

    private let perfIcons = ["mountain.2.fill","leaf.fill","music.note","camera.fill",
                              "heart.fill","flame.fill","star.fill"]  // star is last

    // ── Body ─────────────────────────────────────────────────────────────────
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                scenePill(number: "1", label: "Settings", active: scene == .settings)
                scenePill(number: "2", label: "Perform",  active: scene == .performance)
            }

            phoneMockup
                .shadow(color: Color(hex: "F97316").opacity(phoneGlow * 0.6), radius: 36)
                .animation(.easeInOut(duration: 0.4), value: phoneGlow)

            Group {
                if scene == .settings {
                    Text("**Antes del show** — elige el post objetivo en Settings")
                } else {
                    Text("El espectador hace scroll libremente — la app para exactamente en tu post")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 42)
            .animation(.easeInOut(duration: 0.3), value: scene)
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "F97316").opacity(0.25), lineWidth: 1))
        .onAppear  { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Phone Mockup

    private var phoneMockup: some View {
        ZStack {
            // Outer shell
            RoundedRectangle(cornerRadius: 38).fill(Color(hex: "111111"))
                .frame(width: phoneW + 16, height: phoneH + 16)
            // Side buttons
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525")).frame(width: 3, height: 68).offset(x: -(phoneW / 2 + 9), y: -66)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525")).frame(width: 3, height: 44).offset(x:  (phoneW / 2 + 9), y: -52)
            // Dynamic Island
            Capsule().fill(Color.black).frame(width: 96, height: 30).offset(y: -(phoneH / 2 + 1))
            // Screen background
            RoundedRectangle(cornerRadius: 28).fill(Color(hex: "060606")).frame(width: phoneW, height: phoneH)
            // Scene content
            Group {
                if scene == .settings {
                    settingsScene.transition(.opacity)
                } else {
                    performanceScene.transition(.opacity)
                }
            }
            .frame(width: phoneW, height: phoneH)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .animation(.easeInOut(duration: 0.38), value: scene)
        }
    }

    // MARK: - Settings scene

    private var settingsScene: some View {
        ZStack(alignment: .top) {
            Color(hex: "060606")
            VStack(spacing: 0) {
                settingsNavBar.frame(height: 44)
                enabledRow.frame(height: 36)
                profileRow.frame(height: 46)
                gridHeader
                ZStack {
                    settingsGrid
                    if showFinger {
                        fingerCursor.offset(fingerPos)
                            .animation(.interpolatingSpring(stiffness: 130, damping: 18), value: fingerPos)
                    }
                }
                savedConfirmation.frame(height: 52)
            }
        }
    }

    private var settingsNavBar: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text("Force Post").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 18)
        .background(Color(hex: "060606"))
    }

    private var enabledRow: some View {
        HStack {
            Text("Force Post").font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
            Spacer()
            // Fake "enabled" toggle
            Capsule().fill(Color(hex: "F97316")).frame(width: 40, height: 22)
                .overlay(Circle().fill(.white).frame(width: 18).offset(x: 9))
        }
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.05))
    }

    private var profileRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: "F97316").opacity(0.85)).frame(width: 30, height: 30)
                .overlay(Text("M").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("magicians_uk").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text("target profile").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.04))
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }

    private var gridHeader: some View {
        HStack {
            Text("SELECT FORCED POST")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "F97316").opacity(0.7))
                .tracking(1.3)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
    }

    private var settingsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<9) { i in settingsCell(index: i) }
        }
    }

    private func settingsCell(index: Int) -> some View {
        let isSelected    = selectedCell == index
        let isForcedCell  = index == forcedGridIdx
        return ZStack {
            cellGradients[index]
            Image(systemName: cellIcons[index])
                .font(.system(size: isSelected && isForcedCell ? 24 : 17, weight: isForcedCell && isSelected ? .bold : .regular))
                .foregroundColor(
                    isSelected && isForcedCell ? Color(hex: "F97316")
                    : .white.opacity(isSelected ? 0.9 : 0.25)
                )
            if isSelected {
                Rectangle().fill(Color(hex: "F97316").opacity(0.18))
                RoundedRectangle(cornerRadius: 2).stroke(Color(hex: "F97316"), lineWidth: 2.5)
            }
            if isSelected && showCheckmark {
                VStack { HStack { Spacer()
                    ZStack {
                        Circle().fill(Color(hex: "F97316")).frame(width: 20, height: 20)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                    .padding(5)
                } ; Spacer() }
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
    }

    private var savedConfirmation: some View {
        ZStack {
            if showSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                        .foregroundColor(Color(hex: "F97316"))
                    Text("Saved to Settings").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.09)).cornerRadius(20)
                .overlay(Capsule().stroke(Color(hex: "F97316").opacity(0.45), lineWidth: 1))
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.65), value: showSaved)
    }

    private var fingerCursor: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14)).frame(width: 40, height: 40)
            Circle().fill(.white.opacity(0.92)).frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.5), radius: 5)
        }
        .scaleEffect(fingerScale)
        .animation(.easeInOut(duration: 0.08), value: fingerScale)
    }

    // MARK: - Performance scene

    // Content area below nav bar (phoneH - 40)
    // Content height (below nav bar) — used for finger start position
    private var contentH: CGFloat { phoneH - 40 }

    // Snap offset: forced post top at phone vertical centre (phoneH / 2).
    // VStack screen-y = 40 + scrollOffset + forcedTop  →  set equal to phoneH/2.
    private var snapOffset: CGFloat {
        let forcedTop = (postCardH + postSpacing) * CGFloat(forcedPostIdx)
        return phoneH / 2 - 40 - forcedTop   // 246 - 40 - 1524 = -1318
    }

    private var performanceScene: some View {
        // .position() is a LAYOUT transform — SwiftUI renders the view at that
        // absolute coordinate regardless of the parent's frame, so posts that are
        // below the phone screen enter smoothly from the bottom instead of
        // popping in (unlike .offset() which is visual-only and gets culled).
        ZStack(alignment: .top) {
            Color(hex: "060606")

            // Each post absolutely placed in phone coordinates.
            // centerY = navH + i*(postH+gap) + postH/2 + scrollOffset
            ForEach(0..<7, id: \.self) { i in
                perfPostCard(index: i)
                    .frame(width: phoneW, height: postCardH)
                    .position(
                        x: phoneW / 2,
                        y: 40 + CGFloat(i) * (postCardH + postSpacing) + postCardH / 2 + scrollOffset
                    )
            }

            // Swipe finger
            if showSwipeFinger {
                swipeFingerView
                    .position(x: phoneW / 2, y: 40 + swipeFingerY)
                    .animation(.easeOut(duration: 1.05), value: swipeFingerY)
            }

            // Nav bar rendered last → always on top
            perfNavBar.frame(height: 40)
        }
    }

    private var perfNavBar: some View {
        ZStack {
            Color(hex: "060606")
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("magicians_uk").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, 16)
        }
    }

    private func perfPostCard(index: Int) -> some View {
        let isForced = index == forcedPostIdx
        let (topC, botC) = perfGradients[index]

        return ZStack {
            // Full card background
            LinearGradient(colors: [topC, botC], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                // Username header
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "F97316").opacity(isForced ? 1.0 : 0.45))
                        .frame(width: 24, height: 24)
                        .overlay(Text("M").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                    Text("magicians_uk").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    if isForced { Text("·").foregroundColor(.white.opacity(0.5)).font(.system(size: 11))
                        Text("1d").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)) }
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 12).frame(height: 34)

                // Image area (square-ish)
                ZStack {
                    LinearGradient(colors: [topC.opacity(0.7), botC], startPoint: .top, endPoint: .bottom)
                    Image(systemName: perfIcons[index])
                        .font(.system(size: isForced ? 48 : 30, weight: isForced ? .bold : .regular))
                        .foregroundColor(isForced ? Color(hex: "F97316") : .white.opacity(0.25))
                }
                .frame(height: 184)

                // Actions row
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: isForced ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(isForced ? Color(hex: "F97316") : .white.opacity(0.65))
                        if isForced { Text("2.4k").font(.system(size: 11)).foregroundColor(.white.opacity(0.6)) }
                    }
                    Image(systemName: "bubble.right").font(.system(size: 16)).foregroundColor(.white.opacity(0.65))
                    Image(systemName: "paperplane").font(.system(size: 16)).foregroundColor(.white.opacity(0.65))
                    Spacer()
                    Image(systemName: "bookmark").font(.system(size: 16)).foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 12).frame(height: 34)
            }

            // Forced orange border
            if isForced && showForcedBorder {
                Rectangle().stroke(Color(hex: "F97316"), lineWidth: 3).transition(.opacity)
            }

            // FORCED badge
            if isForced && showForcedBadge {
                VStack { Spacer()
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                            Text("FORCED").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8)
                        }
                        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(hex: "F97316")).cornerRadius(20)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
        }
        .frame(width: phoneW)
    }

    private var swipeFingerView: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14)).frame(width: 44, height: 44)
            Circle().fill(.white.opacity(0.90)).frame(width: 28, height: 28).shadow(color: .black.opacity(0.5), radius: 5)
        }
    }

    // MARK: - Scene pill

    private func scenePill(number: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(active ? Color(hex: "F97316") : Color(hex: "F97316").opacity(0.2)).frame(width: 20, height: 20)
                Text(number).font(.system(size: 11, weight: .bold)).foregroundColor(active ? .white : Color(hex: "F97316"))
            }
            Text(label).font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? Color(hex: "F97316") : VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(20)
        .overlay(Capsule().stroke(active ? Color.clear : VaultTheme.Colors.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    // MARK: - Animation loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                await animSettings()
                if Task.isCancelled { break }
                await animPerformance()
            }
        }
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // ── Phase 1: Settings — finger selects forced post ────────────────────────
    @MainActor
    private func animSettings() async {
        // Reset UI state — but NOT scrollOffset yet, so the performance scene
        // fades out without the star jumping upward mid-transition.
        withAnimation(.none) {
            selectedCell = nil; showCheckmark = false; showSaved = false
            showFinger = false; fingerScale = 1.0
            fingerPos = CGSize(width: 83, height: 83)
            showForcedBorder = false; showForcedBadge = false
            phoneGlow = 0; showSwipeFinger = false
            swipeFingerY = contentH - 60
        }
        // Fade out performance → settings
        withAnimation(.easeInOut(duration: 0.38)) { scene = .settings }
        // Wait for transition to complete, THEN silently snap scroll to 0
        // (performance scene is now invisible so no jump is visible)
        await sleep(0.42)
        withAnimation(.none) { scrollOffset = 0 }
        await sleep(0.55)

        withAnimation(.easeIn(duration: 0.18)) { showFinger = true }
        await sleep(0.4)

        // Glide to center cell (forced, index 4) = (0, 0) relative to grid center
        fingerPos = .zero
        await sleep(1.0)

        // Tap press
        withAnimation(.easeIn(duration: 0.07)) { fingerScale = 0.62 }
        await sleep(0.09)
        withAnimation(.easeOut(duration: 0.14)) { fingerScale = 1.0 }
        await sleep(0.12)

        // Select cell
        withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) { selectedCell = forcedGridIdx }
        await sleep(0.38)

        // Checkmark springs in; finger fades
        withAnimation(.spring(response: 0.45, dampingFraction: 0.52)) { showCheckmark = true }
        withAnimation(.easeOut(duration: 0.22)) { showFinger = false }
        await sleep(0.55)

        // Saved confirmation
        withAnimation(.spring(response: 0.42, dampingFraction: 0.65)) { showSaved = true }
        await sleep(2.8)
    }

    // ── Phase 2: Performance — easeOut scroll; forced star slides in from below ──
    // The forced post (index 6) is beyond the normal posts, so it is NEVER visible
    // during the scroll. It only appears as the animation decelerates to a stop.
    @MainActor
    private func animPerformance() async {
        withAnimation(.none) {
            scrollOffset = 0; showForcedBorder = false; showForcedBadge = false
            phoneGlow = 0; showSwipeFinger = false
            swipeFingerY = contentH - 60   // near bottom of content area
        }
        withAnimation(.easeInOut(duration: 0.35)) { scene = .performance }
        await sleep(0.80)

        // Finger appears near bottom
        withAnimation(.easeIn(duration: 0.20)) { showSwipeFinger = true }
        await sleep(0.28)

        // easeOut: fast at start (normal posts fly by), decelerates at the end
        // where the forced star slides up from below and settles at the bottom.
        withAnimation(.easeOut(duration: 1.5)) { scrollOffset = snapOffset }
        withAnimation(.easeOut(duration: 1.05)) { swipeFingerY = 30 }

        // Finger fades as it reaches top
        await sleep(0.95)
        withAnimation(.easeOut(duration: 0.22)) { showSwipeFinger = false }

        // Wait for easeOut to complete (0.28 + 1.5 = 1.78s from animation start)
        await sleep(0.58)   // 0.28 + 0.95 + 0.58 = 1.81s ≥ 1.78 ✓

        // Orange border reveals
        withAnimation(.easeIn(duration: 0.22)) { showForcedBorder = true }
        await sleep(0.30)

        // FORCED badge + orange glow
        withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) { showForcedBadge = true }
        withAnimation(.easeIn(duration: 0.32)) { phoneGlow = 1 }
        await sleep(2.8)

        withAnimation(.easeOut(duration: 0.3)) { phoneGlow = 0 }
        await sleep(0.25)
    }
}

// MARK: - ── Reusable helpers (FPH-prefixed) ──────────────────────────────────

private struct FPHSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: Content

    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon      = icon
        self.iconColor = iconColor
        self.title     = title
        self.content   = content()
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

private struct FPHBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(VaultTheme.Typography.body())
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FPHMetric: View {
    let icon: String
    let color: Color
    let label: String
    let desc: String
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
                Text(desc)
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

private struct FPHInfoBox: View {
    let text: String
    init(_ text: String) { self.text = text }
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
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                .stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct FPHStep: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(VaultTheme.Colors.primary)
                .frame(width: 22, height: 22)
                .background(VaultTheme.Colors.primary.opacity(0.15))
                .clipShape(Circle())
            Text(LocalizedStringKey(text))
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FPHShowStep: View {
    let label: String
    let color: Color
    let action: String
    let dialogue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(1.5)

            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                    Circle()
                        .fill(color.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .padding(.top, 8)
                    Text(action)
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let dialogue {
                    HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                        Rectangle()
                            .fill(color)
                            .frame(width: 2)
                            .cornerRadius(1)
                        Text(dialogue)
                            .font(.system(size: 13))
                            .italic()
                            .foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, VaultTheme.Spacing.md)
                }
            }
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct FPHTip: View {
    let icon: String
    let color: Color
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 22)
                .padding(.top, 1)
            Text(LocalizedStringKey(text))
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
