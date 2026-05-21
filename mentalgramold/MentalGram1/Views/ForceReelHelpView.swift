import SwiftUI

// MARK: - Force Reel Help View

struct ForceReelHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader.padding(.bottom, VaultTheme.Spacing.lg)
                    ForceReelAnimatedDemo()
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.xl)
                    Group {
                        FRHSection(icon: "wand.and.stars",  iconColor: Color(hex: "6366F1"),      title: "How It Works") { howItWorks }
                        frhDivider
                        FRHSection(icon: "gearshape.fill",  iconColor: VaultTheme.Colors.success, title: "Setup") { setupSteps }
                        frhDivider
                        FRHSection(icon: "mic.fill",        iconColor: VaultTheme.Colors.warning,  title: "During the Show") { duringShow }
                        frhDivider
                        FRHSection(icon: "lightbulb.fill",  iconColor: Color(hex: "F472B6"),       title: "Tips") { tipsSection }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force Reel").font(VaultTheme.Typography.titleSmall()).foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Performance Guide").font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(VaultTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32).background(VaultTheme.Colors.backgroundSecondary).clipShape(Circle())
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg).padding(.vertical, VaultTheme.Spacing.md)
            .background(VaultTheme.Colors.background.shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4))
        }
    }

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle().fill(Color(hex: "6366F1").opacity(0.15)).frame(width: 80, height: 80)
                Text("🎬").font(.system(size: 40))
            }
            Text("Force the Reel").font(VaultTheme.Typography.title()).foregroundColor(VaultTheme.Colors.textPrimary)
            Text("In Settings you pick a reel and assign it a position number. The spectator names any number — the magician browses between Posts, Reels and Tagged sections, secretly registering each digit. The forced reel appears at exactly that position in Explore.")
                .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, VaultTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity).padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var frhDivider: some View {
        Rectangle().fill(VaultTheme.Colors.cardBorder).frame(height: 1).padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            FRHBody("You choose a reel in Settings before the show. During the performance the spectator names any number — the magician browses between Posts, Reels and Tagged sections, secretly registering each digit as they swipe.")
            FRHMetric(icon: "play.rectangle.fill", color: Color(hex: "6366F1"), label: "One reel, one number",
                      desc: "The reel and its forced position are set in Settings beforehand. The spectator names a number freely — it always matches.")
            FRHMetric(icon: "square.grid.3x3.fill", color: VaultTheme.Colors.primary, label: "Sections are a secret keypad",
                      desc: "Swiping between Posts, Reels and Tagged looks like normal browsing. Each swipe secretly registers the digit of the item touched.")
            FRHMetric(icon: "hand.draw.fill", color: VaultTheme.Colors.success, label: "Magician dials it in",
                      desc: "The magician swipes between sections — one swipe per digit. The 'Following' counter confirms each one silently.")
            FRHMetric(icon: "play.circle.fill", color: VaultTheme.Colors.warning, label: "Reel appears in Explore",
                      desc: "Navigate to Explore. The app counts to that position in the grid — the forced reel is already waiting there.")
            FRHInfoBox("The 'Following' counter shows the accumulated digit in real time — only the magician knows what it means.")
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            FRHStep(n: 1, text: "**Before the show**, open Settings and enable **Force Reel**.")
            FRHStep(n: 2, text: "Tap **Select Reel**, search for any account and pick the reel you want to force.")
            FRHStep(n: 3, text: "Note the position number assigned — this is the number the spectator must 'freely' name.")
            FRHStep(n: 4, text: "Once configured, close Settings. You don't touch it again during the performance.")
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            FRHShowStep(label: "OPEN A PROFILE", color: Color(hex: "6366F1"),
                        action: "In Performance, navigate to any Instagram profile and open their post grid.",
                        dialogue: "\"Open any profile — a friend, a celebrity, anyone. Look at their posts.\"")
            FRHShowStep(label: "SPECTATOR NAMES A NUMBER", color: VaultTheme.Colors.primary,
                        action: "Ask the spectator to call out any number freely. While their attention is on the screen, you swipe between sections — Posts, Reels, Tagged — to register each digit.",
                        dialogue: "\"Think of any number — say it out loud. Completely your choice.\"")
            FRHShowStep(label: "MAGICIAN DIALS IN SECRET", color: VaultTheme.Colors.warning,
                        action: "Each swipe between sections looks like normal browsing. What the spectator doesn't know is that each swipe secretly registers the digit of the item touched.",
                        dialogue: nil)
            FRHShowStep(label: "OPEN EXPLORE", color: VaultTheme.Colors.success,
                        action: "Navigate to Explore. The grid counts to the spectator's number and highlights exactly the reel you placed there in Settings.",
                        dialogue: "\"Count to position #13 in Explore. That reel — right where your number landed — is what I prepared for you.\"")
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            FRHTip(icon: "clock.badge.checkmark", color: Color(hex: "6366F1"),
                   text: "**Prepare beforehand.** Select the reel and memorise its position — Settings are not touched during performance.")
            FRHTip(icon: "hand.draw.fill", color: VaultTheme.Colors.primary,
                   text: "**Swipe naturally.** Browsing between Posts, Reels and Tagged looks completely normal — no one suspects a digit is being registered.")
            FRHTip(icon: "number.circle.fill", color: VaultTheme.Colors.success,
                   text: "**More digits = more impressive.** A 3-digit number like 134 feels completely impossible to predict.")
            FRHTip(icon: "checkmark.shield.fill", color: VaultTheme.Colors.warning,
                   text: "**Confirm before Explore.** Always tap the post icon to lock in the number before navigating.")
        }
    }
}

// MARK: - ── Animated Demo ─────────────────────────────────────────────────────

private struct ForceReelAnimatedDemo: View {

    enum Phase { case map, swipe, explore }
    @State private var phase: Phase = .map

    // Phase 1
    @State private var mapScanIdx: Int = -1

    // Phase 2 — section-swipe digit input
    @State private var activeTab:       Int     = 0
    @State private var accumDigits:     [Int]   = []
    @State private var activeSwipeCell: Int?    = nil
    @State private var swipeTrail:      CGFloat = 0
    @State private var showFinger:      Bool    = false
    @State private var fingerOffset:    CGSize  = .zero
    @State private var confirmFlash:    Bool    = false
    @State private var followingBounce: CGFloat = 1.0
    @State private var followingPulse:  Bool    = false

    // Phase 3 — explore grid counter
    @State private var exploreCounter:   Int    = 0
    @State private var showForcedBorder: Bool   = false
    @State private var showReelBadge:    Bool   = false
    @State private var phoneGlow:        Double = 0

    @State private var loopTask: Task<Void, Never>? = nil

    private let cellDigits   = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0]
    private let forcedNumber = 13

    // ── Phone dimensions ─────────────────────────────────────────────────────
    // Outer: 264×508   Screen: 248×492
    private let phoneW: CGFloat = 248
    private let phoneH: CGFloat = 492

    // ── Grid geometry ─────────────────────────────────────────────────────────
    // Header: navBar(48)+stats(68)+bio(20)+buttons(48)+tabs(40) = 224px
    // Grid: 492-224 = 268px   cellW=82  cellH=66
    private let cellW:  CGFloat = 82
    private let cellH:  CGFloat = 66

    private var gridCX: CGFloat { phoneW / 2 }
    private var gridCY: CGFloat { 268 / 2 }

    private func cellCenter(_ idx: Int) -> CGSize {
        let col = idx % 3;  let row = idx / 3
        return CGSize(
            width:  CGFloat(col) * (cellW + 1) + cellW / 2 - gridCX,
            height: CGFloat(row) * (cellH + 1) + cellH / 2 - gridCY
        )
    }

    // ── Explore grid ─────────────────────────────────────────────────────────
    // searchBar: 52px → content: 440px   5 rows × 87px = 435px
    private let exploreRowH: CGFloat = 87
    private let exploreTotalRows = 15

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                phasePill(n: "1", label: "Grid",    active: phase == .map)
                phasePill(n: "2", label: "Dial",    active: phase == .swipe)
                phasePill(n: "3", label: "Explore", active: phase == .explore)
            }

            phoneMockup
                .shadow(color: Color(hex: "6366F1").opacity(phoneGlow * 0.6), radius: 36)
                .animation(.easeInOut(duration: 0.4), value: phoneGlow)

            Group {
                switch phase {
                case .map:
                    Text("Each post maps to a secret digit — the magician memorises the layout")
                case .swipe:
                    Text("Swiping between sections registers each digit — watch **Following** count update")
                case .explore:
                    Text("The grid counts #1, #2… all the way to #\(forcedNumber) — the forced reel was there all along")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 42)
            .animation(.easeInOut(duration: 0.3), value: phase)
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg).stroke(Color(hex: "6366F1").opacity(0.25), lineWidth: 1))
        .onAppear  { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Phone mockup

    private var phoneMockup: some View {
        ZStack {
            // Outer shell
            RoundedRectangle(cornerRadius: 38).fill(Color(hex: "111111"))
                .frame(width: phoneW + 16, height: phoneH + 16)
            // Side buttons
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525")).frame(width: 3, height: 68).offset(x: -(phoneW / 2 + 9), y: -66)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525")).frame(width: 3, height: 44).offset(x: (phoneW / 2 + 9), y: -52)
            // Dynamic Island
            Capsule().fill(Color.black).frame(width: 96, height: 30).offset(y: -(phoneH / 2 + 1))
            // Screen background
            RoundedRectangle(cornerRadius: 28).fill(Color(hex: "060606")).frame(width: phoneW, height: phoneH)
            // Screen content
            Group {
                if phase == .explore {
                    exploreScene.transition(.opacity)
                } else {
                    gridScene.transition(.opacity)
                }
            }
            .frame(width: phoneW, height: phoneH)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .animation(.easeInOut(duration: 0.38), value: phase)
        }
    }

    // MARK: - Grid scene

    private var gridScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar
                igProfileStats
                igBioLine
                igActionButtons
                igTabBar
                // Paged panels + finger overlay
                ZStack {
                    pagedTabContent
                    if showFinger { fingerView.offset(fingerOffset) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // ── Nav bar ───────────────────────────────────────────────────────────────
    private var igNavBar: some View {
        ZStack {
            Color(hex: "060606")
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("username").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17)).foregroundColor(.white)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 48)
    }

    // ── Profile stats ─────────────────────────────────────────────────────────
    private var igProfileStats: some View {
        HStack(spacing: 0) {
            // Story-ring avatar
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
            statItem("12",  "Posts")
            Spacer()
            statItem("847", "Followers")
            Spacer()
            followingCol
            Spacer()
        }
        .frame(height: 68)
    }

    private func statItem(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
        }
    }

    // "Following" — becomes live digit counter in Phase 2
    private var followingCol: some View {
        VStack(spacing: 2) {
            ZStack {
                if accumDigits.isEmpty {
                    Text("68").font(.system(size: 15, weight: .bold)).foregroundColor(.white).transition(.opacity)
                } else {
                    Text(accumDigits.map { "\($0)" }.joined())
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "6366F1"))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .scaleEffect(followingBounce)
            .animation(.spring(response: 0.26, dampingFraction: 0.45), value: followingBounce)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: accumDigits)

            Text("Following")
                .font(.system(size: 10, weight: accumDigits.isEmpty ? .regular : .bold))
                .foregroundColor(accumDigits.isEmpty ? .white.opacity(0.55) : Color(hex: "6366F1"))
                .animation(.easeInOut(duration: 0.2), value: accumDigits.isEmpty)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "6366F1").opacity(accumDigits.isEmpty ? 0 : 0.6), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "6366F1").opacity(accumDigits.isEmpty ? 0 : 0.08)))
                .animation(.easeInOut(duration: 0.25), value: accumDigits.isEmpty)
        )
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
                .frame(maxWidth: .infinity).frame(height: 30).background(Color(hex: "6366F1")).cornerRadius(8)
            Text("Message").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
            Image(systemName: "person.badge.plus").font(.system(size: 13)).foregroundColor(.white)
                .frame(width: 34, height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    // ── Dynamic tab bar ───────────────────────────────────────────────────────
    private var igTabBar: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                igTab("square.grid.3x3.fill", idx: 0)
                igTab("play.rectangle.fill",  idx: 1)
                igTab("person.crop.square",   idx: 2)
            }
            // Sliding underline indicator
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
        Image(systemName: icon).font(.system(size: 17))
            .foregroundColor(.white.opacity(activeTab == idx ? 1 : 0.28))
            .frame(maxWidth: .infinity).frame(height: 40)
            .animation(.easeInOut(duration: 0.25), value: activeTab)
    }

    // ── Paged tab content — uses GeometryReader to avoid overflow ─────────────
    private var pagedTabContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                postsGrid.frame(width: geo.size.width)
                reelsGrid.frame(width: geo.size.width)
                taggedGrid.frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(activeTab) * geo.size.width)
            .animation(.easeInOut(duration: 0.34), value: activeTab)
        }
        .clipped()
    }

    // ── Posts grid ────────────────────────────────────────────────────────────
    private var postsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in postCell(index: i) }
        }
    }

    private func postCell(index: Int) -> some View {
        let digit    = cellDigits[index]
        let isZero   = index >= 9
        let isMapLit = (index < 9 && mapScanIdx == index) || (isZero && mapScanIdx == 9)
        let isSwipe  = activeSwipeCell == index && activeTab == 0

        return ZStack {
            postGradients[index]
            Image(systemName: postIcons[index]).font(.system(size: 19)).foregroundColor(.white.opacity(0.11))
            if [1, 4, 8].contains(index) { reelsBadge }

            if isZero { Rectangle().fill(Color(hex: "F97316").opacity(isMapLit ? 0.30 : 0.07)).animation(.easeInOut(duration: 0.18), value: isMapLit) }
            if isMapLit && !isZero { Rectangle().fill(.white.opacity(0.20)).transition(.opacity) }

            if isSwipe { swipeFeedback }

            // Phase 1: large centred badge
            if phase == .map {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isMapLit ? (isZero ? Color(hex: "F97316") : Color(hex: "6366F1")) : Color.black.opacity(0.55))
                        .frame(width: 32, height: 32)
                    Text("\(digit)").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.white)
                }
                .scaleEffect(isMapLit ? 1.18 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isMapLit)
            } else {
                cornerDigit(digit)
            }
            if isZero && mapScanIdx == 9 { Rectangle().stroke(Color(hex: "F97316"), lineWidth: 2).transition(.opacity) }
        }
        .frame(height: cellH)
        .animation(.easeInOut(duration: 0.14), value: isMapLit)
        .animation(.easeInOut(duration: 0.12), value: isSwipe)
    }

    // ── Reels grid ────────────────────────────────────────────────────────────
    private var reelsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in reelCell(index: i) }
        }
    }

    private func reelCell(index: Int) -> some View {
        let digit  = cellDigits[index]
        let isSwipe = activeSwipeCell == index && activeTab == 1
        let counts = ["1.2M","845k","2.3M","321k","1.5M","892k","567k","1.1M","445k","2.1M","738k","1.9M"]

        return ZStack {
            reelGradients[index % reelGradients.count]
            Image(systemName: "play.fill").font(.system(size: 17)).foregroundColor(.white.opacity(0.38))
            VStack { Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 7)).foregroundColor(.white.opacity(0.7))
                    Text(counts[index]).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
            if isSwipe { swipeFeedback }
            cornerDigit(digit)
        }
        .frame(height: cellH)
        .animation(.easeInOut(duration: 0.12), value: isSwipe)
    }

    // ── Tagged grid ───────────────────────────────────────────────────────────
    private var taggedGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in taggedCell(index: i) }
        }
    }

    private func taggedCell(index: Int) -> some View {
        let digit  = cellDigits[index]
        let isSwipe = activeSwipeCell == index && activeTab == 2

        return ZStack {
            tagGradients[index % tagGradients.count]
            HStack(spacing: -10) {
                Image(systemName: "person.fill").font(.system(size: 15)).foregroundColor(.white.opacity(0.18))
                Image(systemName: "person.fill").font(.system(size: 15)).foregroundColor(.white.opacity(0.12))
                Image(systemName: "person.fill").font(.system(size: 15)).foregroundColor(.white.opacity(0.07))
            }
            VStack { HStack { Spacer()
                Image(systemName: "person.crop.square").font(.system(size: 9)).foregroundColor(.white.opacity(0.5)).padding(6)
            } ; Spacer() }
            if isSwipe { swipeFeedback }
            cornerDigit(digit)
        }
        .frame(height: cellH)
        .animation(.easeInOut(duration: 0.12), value: isSwipe)
    }

    // ── Shared cell helpers ───────────────────────────────────────────────────
    private var reelsBadge: some View {
        VStack { HStack { Spacer()
            Image(systemName: "play.fill").font(.system(size: 8)).foregroundColor(.white.opacity(0.8)).padding(6)
        } ; Spacer() }
    }

    private var swipeFeedback: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.09))
            VStack { Spacer()
                HStack(spacing: 3) {
                    Capsule().fill(.white.opacity(0.75)).frame(width: max(1, 30 * swipeTrail), height: 3)
                    Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(swipeTrail * 0.85))
                }
                .padding(.leading, 7).padding(.bottom, 7)
            }
        }
    }

    private func cornerDigit(_ digit: Int) -> some View {
        VStack { Spacer()
            HStack { Spacer()
                Text("\(digit)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.32))).padding(5)
            }
        }
    }

    private var fingerView: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14)).frame(width: 42, height: 42)
            Circle().fill(.white.opacity(0.88)).frame(width: 28, height: 28).shadow(color: .black.opacity(0.5), radius: 5)
        }
    }

    // MARK: - Explore scene — grid with animated counter

    private var exploreScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igExploreBar.frame(height: 52)
                ZStack(alignment: .topTrailing) {
                    exploreGrid
                    if exploreCounter > 0 { counterBadge.padding(10) }
                }
                .frame(maxHeight: .infinity).clipped()
            }
        }
    }

    private var igExploreBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                Text("Search").font(.system(size: 13)).foregroundColor(.white.opacity(0.28))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9).background(Color.white.opacity(0.09)).cornerRadius(12)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(Color(hex: "060606"))
    }

    // 5 rows × 3 cols = 15 cells
    private var exploreGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(1...exploreTotalRows, id: \.self) { pos in
                exploreCell(position: pos)
            }
        }
    }

    private func exploreCell(position: Int) -> some View {
        let isForced    = position == forcedNumber
        let isCurrent   = exploreCounter == position
        let isHighlighted = showForcedBorder && isForced

        return ZStack {
            // Background gradient
            if isForced {
                LinearGradient(colors: [Color(hex: "1a0f40"), Color(hex: "0d0820")], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                postGradients[(position - 1) % postGradients.count]
                    .opacity(exploreCounter > position ? 0.55 : 1.0)
            }

            // Flash when counter lands on this cell
            if isCurrent {
                Rectangle().fill(.white.opacity(0.18)).transition(.opacity)
            }

            // Position number
            Text("#\(position)")
                .font(.system(size: isCurrent ? 20 : (isHighlighted ? 18 : 14), weight: .bold, design: .monospaced))
                .foregroundColor(
                    isHighlighted ? Color(hex: "6366F1")
                    : isCurrent   ? .white
                    : .white.opacity(0.28)
                )
                .animation(.spring(response: 0.2), value: isCurrent)

            // Play reel icon (forced)
            if isForced {
                VStack { HStack { Spacer()
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundColor(isHighlighted ? Color(hex: "6366F1") : .white.opacity(0.3)).padding(6)
                } ; Spacer() }
            }

            // Indigo border
            if isHighlighted {
                Rectangle().stroke(Color(hex: "6366F1"), lineWidth: 3).transition(.opacity)
            }

            // FORCED label
            if isForced && showReelBadge {
                VStack { Spacer()
                    HStack { Spacer()
                        Text("FORCED").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(0.5)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Color(hex: "6366F1")).cornerRadius(8).padding(5)
                    }
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(height: exploreRowH)
        .animation(.easeInOut(duration: 0.14), value: isCurrent)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }

    // Floating counter badge (top-right of grid)
    private var counterBadge: some View {
        HStack(spacing: 3) {
            Text("#").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: "6366F1").opacity(0.75))
            Text("\(exploreCounter)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "6366F1"))
                .frame(minWidth: 28, alignment: .leading)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: exploreCounter)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "060606").opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "6366F1").opacity(0.55), lineWidth: 1.5))
        )
    }

    // MARK: - Phase pill

    private func phasePill(n: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(active ? Color(hex: "6366F1") : Color(hex: "6366F1").opacity(0.2)).frame(width: 20, height: 20)
                Text(n).font(.system(size: 11, weight: .bold)).foregroundColor(active ? .white : Color(hex: "6366F1"))
            }
            Text(label).font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? Color(hex: "6366F1") : VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(20)
        .overlay(Capsule().stroke(active ? Color.clear : VaultTheme.Colors.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    // MARK: - Gradient sets

    private var postGradients: [LinearGradient] { [
        LinearGradient(colors: [Color(hex: "1a3a5c"), Color(hex: "0d1f3c")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a3d2e"), Color(hex: "0d261c")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2010"), Color(hex: "261408")], startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2d1b69"), Color(hex: "1a0f40")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a2a5c"), Color(hex: "0d1a3c")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "0d3d2a"), Color(hex: "061f15")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "3d0d2a"), Color(hex: "260819")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a3a1a"), Color(hex: "0d260d")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "3d2a0d"), Color(hex: "261908")], startPoint: .top,         endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2d1010"), Color(hex: "1a0808")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "102d10"), Color(hex: "081a08")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "10182d"), Color(hex: "080d1a")], startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2a1020"), Color(hex: "140810")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "102a20"), Color(hex: "081408")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "202a10"), Color(hex: "101408")], startPoint: .topTrailing, endPoint: .bottomLeading),
    ] }

    private var reelGradients: [LinearGradient] { [
        LinearGradient(colors: [Color(hex: "0d1f3c"), Color(hex: "1a0f40")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "0d261c"), Color(hex: "0d1040")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "261408"), Color(hex: "0d0820")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a0f3c"), Color(hex: "0d1f3c")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "0d1a40"), Color(hex: "1a0f28")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "061f15"), Color(hex: "0d1040")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "260819"), Color(hex: "0d0f28")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "0d260d"), Color(hex: "0d1f3c")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "261908"), Color(hex: "1a0f28")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a0808"), Color(hex: "0d0820")], startPoint: .top,         endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "081a08"), Color(hex: "0d1040")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "080d1a"), Color(hex: "1a0f28")], startPoint: .topLeading,  endPoint: .bottom),
    ] }

    private var tagGradients: [LinearGradient] { [
        LinearGradient(colors: [Color(hex: "2e1a1a"), Color(hex: "1a0f0f")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2e1a"), Color(hex: "0f1a0f")], startPoint: .top,        endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "2e2a1a"), Color(hex: "1a180f")], startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "1a1a2e"), Color(hex: "0f0f1a")], startPoint: .topLeading,  endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "2a1a2e"), Color(hex: "180f1a")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2e2a"), Color(hex: "0f1a18")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2e1a2a"), Color(hex: "1a0f18")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a2e1a"), Color(hex: "0f1a0f")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2e2e1a"), Color(hex: "1a1a0f")], startPoint: .topLeading,  endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2a1a1a"), Color(hex: "180f0f")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2a1a"), Color(hex: "0f180f")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a1a2a"), Color(hex: "0f0f18")], startPoint: .topLeading,  endPoint: .bottomTrailing),
    ] }

    private let postIcons = ["building.2.fill","tree.fill","sun.horizon.fill","figure.run",
                             "star.fill","camera.fill","music.note","flame.fill","heart.fill",
                             "moon.stars.fill","leaf.fill","bolt.fill"]

    // MARK: - Animation loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                await animPhase1()
                if Task.isCancelled { break }
                await animPhase2()
                if Task.isCancelled { break }
                await animPhase3()
            }
        }
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // ── Phase 1: Grid Map ────────────────────────────────────────────────────
    @MainActor
    private func animPhase1() async {
        withAnimation(.none) {
            mapScanIdx = -1; activeTab = 0; showFinger = false; accumDigits = []
            activeSwipeCell = nil; confirmFlash = false; followingBounce = 1.0; followingPulse = false
            exploreCounter = 0; showForcedBorder = false; showReelBadge = false; phoneGlow = 0
        }
        withAnimation(.easeInOut(duration: 0.3)) { phase = .map }
        await sleep(0.9)

        for i in 0..<9 {
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.13)) { mapScanIdx = i }
            await sleep(0.27)
        }
        withAnimation(.easeOut(duration: 0.15)) { mapScanIdx = -1 }
        await sleep(0.15)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) { mapScanIdx = 9 }
        await sleep(1.9)
        withAnimation(.easeOut(duration: 0.3)) { mapScanIdx = -1 }
        await sleep(0.35)
    }

    // ── Phase 2: Swipe sections → digit "1" then "3" in Following ────────────
    @MainActor
    private func animPhase2() async {
        withAnimation(.none) {
            activeTab = 0; accumDigits = []; activeSwipeCell = nil; swipeTrail = 0
            showFinger = false; fingerOffset = .zero; confirmFlash = false; mapScanIdx = -1; followingBounce = 1.0
        }
        withAnimation(.easeInOut(duration: 0.3)) { phase = .swipe }
        await sleep(0.85)

        // Swipe 1 → Posts→Reels, digit 1
        await doSwipe(cellIdx: 0, digit: 1, nextTab: 1)
        // Long pause — let viewer see Following="1" clearly
        await sleep(2.2)

        // Swipe 2 → Reels→Tagged, digit 3
        await doSwipe(cellIdx: 2, digit: 3, nextTab: 2)
        await sleep(0.5)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { confirmFlash = true }
        withAnimation(.easeOut(duration: 0.25)) { showFinger = false }
        await sleep(2.5)
    }

    @MainActor
    private func doSwipe(cellIdx: Int, digit: Int, nextTab: Int) async {
        let c = cellCenter(cellIdx)
        withAnimation(.none) {
            fingerOffset = CGSize(width: c.width + 22, height: c.height)
            activeSwipeCell = cellIdx; swipeTrail = 0
        }
        // Finger appears
        withAnimation(.easeIn(duration: 0.18)) { showFinger = true }
        await sleep(0.28)

        // Swipe motion — slower for visibility
        withAnimation(.easeIn(duration: 0.12)) { swipeTrail = 1 }
        withAnimation(.easeOut(duration: 0.50)) {
            fingerOffset = CGSize(width: c.width - 22, height: c.height)
        }
        // Tab slides midway through the swipe
        await sleep(0.25)
        withAnimation(.easeInOut(duration: 0.34)) { activeTab = nextTab }
        await sleep(0.30)   // finish the swipe motion

        // Clean up
        withAnimation(.easeOut(duration: 0.14)) { swipeTrail = 0; activeSwipeCell = nil }

        // Register digit with dramatic bounce in Following
        withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) { accumDigits.append(digit) }
        // Big bounce — 1.5x scale
        followingBounce = 1.5
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { followingBounce = 1.0 }

        await sleep(0.20)
        withAnimation(.easeOut(duration: 0.14)) { showFinger = false }
        await sleep(0.18)
    }

    // ── Phase 3: Explore grid counter from #1 → #13 ──────────────────────────
    @MainActor
    private func animPhase3() async {
        withAnimation(.none) { exploreCounter = 0; showForcedBorder = false; showReelBadge = false; phoneGlow = 0 }
        withAnimation(.easeInOut(duration: 0.4)) { phase = .explore }
        await sleep(0.8)

        // Delays per step: fast at start, slowing into #13 (easeOut feel)
        let delays: [Double] = [
            0.11, 0.11, 0.12, 0.13, 0.14, 0.15, 0.17, 0.19,  // 1-8  fast
            0.23, 0.30, 0.40,                                   // 9-11 medium
            0.55, 0.85                                          // 12-13 slow
        ]

        for i in 1...forcedNumber {
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) { exploreCounter = i }
            let delay = i <= delays.count ? delays[i - 1] : 0.15
            await sleep(delay)
        }

        await sleep(0.4)

        // Reveal forced cell
        withAnimation(.easeIn(duration: 0.25)) { showForcedBorder = true }
        await sleep(0.35)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { showReelBadge = true }
        withAnimation(.easeIn(duration: 0.35)) { phoneGlow = 1 }
        await sleep(3.0)
        withAnimation(.easeOut(duration: 0.3)) { phoneGlow = 0 }
        await sleep(0.3)
    }
}

// MARK: - ── Reusable helpers (FRH-prefixed) ──────────────────────────────────

private struct FRHSection<Content: View>: View {
    let icon: String; let iconColor: Color; let title: String; let content: Content
    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.iconColor = iconColor; self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 18))
                Text(title).font(VaultTheme.Typography.titleSmall()).foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content
        }
    }
}

private struct FRHBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FRHMetric: View {
    let icon: String; let color: Color; let label: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Text(desc).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VaultTheme.Spacing.sm).background(color.opacity(0.06)).cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

private struct FRHInfoBox: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill").foregroundColor(VaultTheme.Colors.info).font(.system(size: 14)).padding(.top, 1)
            Text(text).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VaultTheme.Spacing.md).background(VaultTheme.Colors.info.opacity(0.08)).cornerRadius(VaultTheme.CornerRadius.sm)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm).stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1))
    }
}

private struct FRHStep: View {
    let n: Int; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(VaultTheme.Colors.primary)
                .frame(width: 22, height: 22).background(VaultTheme.Colors.primary.opacity(0.15)).clipShape(Circle())
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FRHShowStep: View {
    let label: String; let color: Color; let action: String; let dialogue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(color).tracking(1.5)
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                    Circle().fill(color.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 8)
                    Text(action).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let d = dialogue {
                    HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                        Rectangle().fill(color).frame(width: 2).cornerRadius(1)
                        Text(d).font(.system(size: 13)).italic().foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, VaultTheme.Spacing.md)
                }
            }
        }
        .padding(VaultTheme.Spacing.md).background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

private struct FRHTip: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 16)).frame(width: 22).padding(.top, 1)
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
