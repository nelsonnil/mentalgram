import SwiftUI
import Combine
import UIKit

// MARK: - Main Home View

struct HomeView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject private var urlAction = URLActionManager.shared
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @State private var selectedTab = 1 // Start on Sets tab
    @State private var showingCreateSet = false
    @State private var showingExplore = false
    @State private var showingChallengeAlert = false
    @AppStorage("launchDirectlyToPerformance") private var launchDirectlyToPerformance = false
    /// Set to true once the user has read (and acknowledged) the Limits & Safety guide.
    /// Existing users with a cached profile are auto-unlocked on first launch after this update.
    @AppStorage("limitsGuideRead") private var limitsGuideRead: Bool = false
    @State private var showLimitsGate = false

    // Pre-performance visible photos check
    @State private var showVisiblePhotosAlert = false
    @State private var visiblePhotosToArchive: [SetPhoto] = []
    @State private var isArchivingBeforePerformance = false
    @State private var archiveProgress: (done: Int, total: Int) = (0, 0)
    @State private var showArchiveProgressSheet = false
    @State private var performanceGate: PerformanceGate?
    @State private var showPerformanceRelogin = false
    @State private var showInitialProfileLoad = false
    @State private var showBudgetWarning = false
    @State private var budgetWarningUsed: Int = 0
    @State private var budgetWarningRemaining: Int = 55
    @State private var budgetWarningRenewal: Date? = nil
    @State private var showListInputConflictAlert = false
    
    /// Custom binding that intercepts tab switches to Performance (0)
    /// and shows the pre-check alert if there are visible photos.
    private var tabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 0 && instagram.isLoggedIn {
                    requestPerformanceEntry()
                    return
                }
                // Leaving Performance → check budget and warn if low
                if selectedTab == 0 && newValue != 0 && instagram.isLoggedIn {
                    let rl = instagram.checkRateLimit()
                    if rl.remaining < 15 {
                        budgetWarningUsed      = rl.actionsUsed
                        budgetWarningRemaining = rl.remaining
                        budgetWarningRenewal   = instagram.budgetRenewalTime()
                        showBudgetWarning      = true
                    }
                }
                selectedTab = newValue
                CrashLoggerService.shared.recordScreen(tabName(for: newValue))
                updateTabBarAppearance(forTab: newValue)
            }
        )
    }

    private func tabName(for index: Int) -> String {
        switch index {
        case 0: return "Performance"
        case 1: return "Sets"
        case 2: return "Settings"
        case 3: return "Guide"
        default: return "Tab \(index)"
        }
    }
    
    var body: some View {
        TabView(selection: tabBinding) {
            // Performance Tab — fake Instagram replica.
            // Follows the device appearance (light/dark) like the real Instagram app:
            // the adaptive UIColor.* values inside paint white in light mode and black
            // in dark mode automatically. No scheme is forced here.
            Group {
                if instagram.isLoggedIn {
                    PerformanceView(selectedTab: $selectedTab, showingExplore: $showingExplore)
                } else {
                    // Blank dark view when not logged in
                    VaultTheme.Colors.background
                        .ignoresSafeArea()
                }
            }
            .tabItem {
                Label("Performance", systemImage: "chart.bar.fill")
            }
            .tag(0)
            
            // Sets Tab - dark theme
            NavigationView {
                SetsListView()
            }
            .tabItem {
                Label("Sets", systemImage: "square.grid.2x2.fill")
            }
            .tag(1)
            
            // Settings Tab - dark theme
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)

            // Guide Tab — only active when logged in
            Group {
                if instagram.isLoggedIn {
                    NavigationView {
                        UserGuideView()
                    }
                } else {
                    VaultTheme.Colors.background
                        .ignoresSafeArea()
                }
            }
            // Guide is built entirely for a dark theme (fixed dark colors). Pin the
            // scheme locally via environment so it stays dark without leaking to the
            // Performance tab (which must follow the device appearance).
            .environment(\.colorScheme, .dark)
            .tabItem {
                Label("Guide", systemImage: "book.fill")
            }
            .tag(3)
        }
        // No global color-scheme forcing: Performance follows the device appearance
        // (like the real Instagram), while the dark-themed tabs (Sets, Settings) force
        // .dark locally inside their own views.
        .accentColor(selectedTab == 0 ? .primary : VaultTheme.Colors.primary)
        .onChange(of: selectedTab) { newTab in
            updateTabBarAppearance(forTab: newTab)
            // Leaving Performance → wipe the secret digit buffer so the
            // following-count indicator is clean on the next entry.
            if newTab != 0 {
                SecretNumberManager.shared.reset()
            }
        }
        // URL scheme: bypass the check and go directly to Performance
        .onChange(of: urlAction.pendingMode) { mode in
            guard !mode.isEmpty else { return }
            print("📲 [URL] Switching to Performance tab for action: \(mode)")
            requestPerformanceEntry()
        }
        .onAppear {
            CrashLoggerService.shared.recordScreen(tabName(for: selectedTab))
            // Auto-unlock the Limits gate for users who already have a cached profile
            // (i.e. experienced users who had the app before this feature was added).
            if !limitsGuideRead && instagram.isLoggedIn
                && ProfileCacheService.shared.loadProfile() != nil {
                limitsGuideRead = true
            }

            if launchDirectlyToPerformance && instagram.isLoggedIn {
                if !limitsGuideRead {
                    showLimitsGate = true
                } else {
                    requestPerformanceEntry()
                }
            }
            updateTabBarAppearance(forTab: selectedTab)
            // Clean up any stuck upload state (e.g. deleted active set from infinite-loop bug)
            UploadManager.shared.clearStuckState()
        }
        .fullScreenCover(isPresented: $showLimitsGate) {
            LimitsHelpView(
                showContinueButton: true,
                onContinue: {
                    limitsGuideRead = true
                    showLimitsGate = false
                    // After acknowledging, proceed to Performance (checking visible photos first)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        let visible = visiblePhotosInActiveSets()
                        if !visible.isEmpty {
                            visiblePhotosToArchive = visible
                            showVisiblePhotosAlert = true
                        } else {
                            enterPerformanceDirectly()
                        }
                    }
                }
            )
        }
        .alert("Visible Photos Detected", isPresented: $showVisiblePhotosAlert) {
            Button("Continue Anyway") {
                enterPerformanceDirectly()
            }
            // Disable "Verify & Archive" while post-reveal protection is active —
            // the photos were just revealed for a trick and archiving them now
            // would fire during the SafetyGate's hold window, which gets ignored
            // by archivePhoto() and would silently leave photos public.
            if InstagramSafetyGate.shared.postRevealSecondsRemaining == 0 {
                Button("Verify & Archive") {
                    showArchiveProgressSheet = true
                    Task { await archiveVisiblePhotosAndEnter() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let sets = activeSetNames()
            let protectedSecs = InstagramSafetyGate.shared.postRevealSecondsRemaining
            if protectedSecs > 0 {
                let m = protectedSecs / 60
                let s = protectedSecs % 60
                let countdown = m > 0 ? "\(m)m \(s)s" : "\(s)s"
                Text("\(visiblePhotosToArchive.count) photo(s) from your active sets are still visible — they were just revealed.\n\nPost-reveal protection active: \(countdown) remaining before archiving is safe.\n\nYou can continue to Performance now and archive later from Sets.")
            } else {
                Text("\(visiblePhotosToArchive.count) photo(s) from your active sets are still visible on Instagram.\n\nActive sets: \(sets)\n\nArchive them before performing?")
            }
        }
        .alert("Input conflict", isPresented: $showListInputConflictAlert) {
            Button("Go to Settings") {
                selectedTab = 2
                updateTabBarAppearance(forTab: 2)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(listInputConflictMessage)
        }
        .sheet(isPresented: $showArchiveProgressSheet) {
            archiveProgressView
        }
        .sheet(item: $performanceGate) { gate in
            PerformanceGateSheet(
                gate: gate,
                onOpenInstagram: openInstagram,
                onRelogin: {
                    performanceGate = nil
                    showPerformanceRelogin = true
                },
                onContinue: {
                    performanceGate = nil
                    requestPerformanceEntry()
                },
                onCancel: {
                    performanceGate = nil
                }
            )
        }
        .sheet(isPresented: $showPerformanceRelogin) {
            ReloginSheet(isPresented: $showPerformanceRelogin)
        }
        .sheet(isPresented: $showBudgetWarning) {
            BudgetWarningSheet(
                used: budgetWarningUsed,
                remaining: budgetWarningRemaining,
                renewalTime: budgetWarningRenewal,
                onDismiss: { showBudgetWarning = false }
            )
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showInitialProfileLoad) {
            InitialProfileLoadView {
                showInitialProfileLoad = false
                // Re-run the check so visible-photos gate etc. can still fire
                requestPerformanceEntry()
            }
        }
        .fullScreenCover(isPresented: $showingExplore, onDismiss: {
            // Restart volume monitoring if FollowingMagic needs it for Transfer phase 2
            // (UserProfileView stopped monitoring on dismiss; PerformanceView.onAppear won't fire)
            let fm = FollowingMagicSettings.shared
            print("🎩 [TRANSFER] HomeView Explore onDismiss — isEnabled:\(fm.isEnabled) transferOffset:\(fm.transferOffset) pendingOffset:\(fm.pendingOffset)")
            if fm.isEnabled && (fm.transferOffset > 0 || fm.pendingOffset > 0) {
                VolumeButtonMonitor.shared.prepareVolume()
                VolumeButtonMonitor.shared.startMonitoring()
            }
        }) {
            ExploreView(selectedTab: $selectedTab, showingExplore: $showingExplore)
        }
    }

    // MARK: - Pre-Performance Check

    private func visiblePhotosInActiveSets() -> [SetPhoto] {
        var result: [SetPhoto] = []
        let activeIds = [activeSetSettings.activeWordSetId,
                         activeSetSettings.activeNumberSetId,
                         activeSetSettings.activeCustomSetId,
                         activeSetSettings.activeCardSetId,
                         activeSetSettings.activeListSetId].compactMap { $0 }
        print("🔍 [PRE-PERF] Checking \(activeIds.count) active set(s) for visible photos")
        for setId in activeIds {
            guard let photoSet = dataManager.sets.first(where: { $0.id == setId }) else {
                print("⚠️ [PRE-PERF] Active set \(setId) not found in dataManager")
                continue
            }
            let visible = photoSet.photos.filter {
                $0.mediaId != nil && !$0.isArchived
            }
            let byStatus = Dictionary(grouping: photoSet.photos.filter { $0.mediaId != nil }, by: { $0.uploadStatus.rawValue })
            print("🔍 [PRE-PERF] Set '\(photoSet.name)': \(visible.count) visible photo(s) of \(photoSet.photos.count) total — by status: \(byStatus.mapValues { $0.count })")
            result.append(contentsOf: visible)
        }
        print("🔍 [PRE-PERF] Total visible photos found: \(result.count)")
        return result
    }

    private func activeSetNames() -> String {
        let activeIds = [activeSetSettings.activeWordSetId,
                         activeSetSettings.activeNumberSetId,
                         activeSetSettings.activeCustomSetId,
                         activeSetSettings.activeCardSetId,
                         activeSetSettings.activeListSetId].compactMap { $0 }
        let names = activeIds.compactMap { id in
            dataManager.sets.first(where: { $0.id == id })?.name
        }
        return names.joined(separator: ", ")
    }

    private var listInputConflictLocations: [String] {
        guard activeSetSettings.activeListSetId != nil else { return [] }
        return integrations.bioNoteInterfaceLocations(matching: [
            .numberClock, .cardClock, .cardNumpad, .numberLockscreen, .cardLockscreen
        ])
    }

    private var listInputConflictMessage: String {
        let locations = listInputConflictLocations
        let list = locations.isEmpty ? "" : "\n\nActive conflicts:\n" + locations.joined(separator: "\n")
        return "List Input cannot be used at the same time as fullscreen card, Clock, or Lockscreen inputs in Biography or Notes.\n\nDisable one of those inputs before entering Performance.\(list)"
    }

    private func requestPerformanceEntry() {
        guard instagram.isLoggedIn else {
            enterPerformanceDirectly()
            return
        }

        guard !instagram.isSessionExpired else {
            performanceGate = .sessionExpired
            return
        }

        // Gate: require Limits & Safety to be read before first Performance entry
        guard limitsGuideRead else {
            showLimitsGate = true
            return
        }

        if !listInputConflictLocations.isEmpty {
            showListInputConflictAlert = true
            return
        }

        // Performance loads its own profile from cache + one getProfileInfo() refresh
        // when entering (same pattern as Explore → UserProfileView). No background
        // full-loader is started here.

        let decision = InstagramSafetyGate.shared.peekPerformanceEntry()
        if !decision.allowRemoteCalls {
            let isPostArchiveCooldown = decision.reason == "post-archive cooldown"
            if isPostArchiveCooldown {
                performanceGate = .safetyPause(
                    seconds: max(1, decision.waitSeconds),
                    reason: decision.reason
                )
                return
            }
        }

        let visible = visiblePhotosInActiveSets()
        if !visible.isEmpty {
            visiblePhotosToArchive = visible
            showVisiblePhotosAlert = true
            return
        }

        enterPerformanceDirectly()
    }

    private func enterPerformanceDirectly() {
        selectedTab = 0
        updateTabBarAppearance(forTab: 0)
    }

    private func openInstagram() {
        guard let appURL = URL(string: "instagram://app") else { return }
        UIApplication.shared.open(appURL) { success in
            if !success, let webURL = URL(string: "https://www.instagram.com/") {
                UIApplication.shared.open(webURL)
            }
        }
    }

    @MainActor
    private func archiveVisiblePhotosAndEnter() async {
        let photos = visiblePhotosToArchive
        archiveProgress = (0, photos.count)
        isArchivingBeforePerformance = true

        for (i, photo) in photos.enumerated() {
            guard let mediaId = photo.mediaId else { continue }

            // Skip photos still under post-reveal protection — archiving them now
            // would be inside the SafetyGate hold window and would risk a bot signal.
            if InstagramSafetyGate.shared.isMediaPostRevealProtected(mediaId: mediaId) {
                print("⏭️ [PRE-PERF] Skipping \(mediaId) — post-reveal protected")
                archiveProgress = (i + 1, photos.count)
                continue
            }

            do {
                let archived = try await InstagramService.shared.archivePhoto(mediaId: mediaId, skipPreCheck: false)
                if archived {
                    dataManager.updatePhoto(photoId: photo.id, isArchived: true, uploadStatus: .completed)
                    // Remove from ProfileCache so PerformanceView grid is already clean on entry
                    ProfileCacheService.shared.removeMediaItem(byMediaId: mediaId)
                }
            } catch {
                print("⚠️ [PRE-PERF] Failed to archive \(mediaId): \(error.localizedDescription)")
            }
            archiveProgress = (i + 1, photos.count)
        }

        isArchivingBeforePerformance = false
        showArchiveProgressSheet = false
        visiblePhotosToArchive = []
        selectedTab = 0
        updateTabBarAppearance(forTab: 0)
    }

    private var archiveProgressView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: archiveProgress.total > 0
                          ? CGFloat(archiveProgress.done) / CGFloat(archiveProgress.total) : 0)
                    .stroke(Color(hex: "7C3AED"), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: archiveProgress.done)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            VStack(spacing: 6) {
                Text("Archiving photos…")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(archiveProgress.done) / \(archiveProgress.total)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            Text("Please wait. Do not close the app.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "111111").ignoresSafeArea())
        .interactiveDismissDisabled(isArchivingBeforePerformance)
    }
    
    /// Update tab bar appearance based on which tab is active
    /// Performance tab = Instagram-style (light), Sets/Settings = Vault dark theme
    private func updateTabBarAppearance(forTab tab: Int) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        if tab == 0 {
            // Performance: Instagram-style white tab bar
            appearance.backgroundColor = .white
            appearance.stackedLayoutAppearance.selected.iconColor = .black
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.black
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = .gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.gray
            ]
        } else {
            // Sets/Settings: Vault dark theme
            appearance.backgroundColor = UIColor(VaultTheme.Colors.backgroundSecondary)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(VaultTheme.Colors.primary)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(VaultTheme.Colors.primary)
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(VaultTheme.Colors.textSecondary)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(VaultTheme.Colors.textSecondary)
            ]
        }
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Performance Entry Gate

private enum PerformanceGate: Identifiable {
    case sessionExpired
    case safetyPause(seconds: Int, reason: String)

    var id: String {
        switch self {
        case .sessionExpired:
            return "sessionExpired"
        case .safetyPause(_, let reason):
            return "safetyPause-\(reason)"
        }
    }
}

private struct PerformanceGateSheet: View {
    let gate: PerformanceGate
    let onOpenInstagram: () -> Void
    let onRelogin: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remainingSeconds: Int = 0

    private var isSessionExpired: Bool {
        if case .sessionExpired = gate { return true }
        return false
    }

    private var title: String {
        if isSessionExpired {
            return String(localized: "performance.gate.session.title")
        }
        return String(
            format: String(localized: "performance.gate.wait.title"),
            formattedRemaining
        )
    }

    private var message: String {
        switch gate {
        case .sessionExpired:
            return String(localized: "performance.gate.session.message")
        case .safetyPause(_, let reason) where reason == "post-archive cooldown":
            return String(localized: "performance.gate.post_archive.message")
        case .safetyPause:
            return String(localized: "performance.gate.safety.message")
        }
    }

    private var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            Image(systemName: isSessionExpired ? "key.slash.fill" : "clock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(isSessionExpired ? .orange : .blue)
                .padding(.top, 6)

            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            if isSessionExpired {
                VStack(spacing: 10) {
                    Button(action: onOpenInstagram) {
                        Label(String(localized: "session.panel.open_instagram"), systemImage: "camera.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black)
                            .cornerRadius(12)
                    }

                    Button(action: onRelogin) {
                        Label(String(localized: "session.panel.relogin_after_instagram"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(String(format: String(localized: "performance.gate.auto_enter"), formattedRemaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button(String(localized: "common.cancel")) {
                dismiss()
                onCancel()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .presentationDetents([.height(isSessionExpired ? 430 : 330)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            if case .safetyPause(let seconds, _) = gate {
                remainingSeconds = seconds
                Task { @MainActor in
                    while remainingSeconds > 0 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        remainingSeconds = max(0, remainingSeconds - 1)
                    }
                    dismiss()
                    onContinue()
                }
            }
        }
    }
}

// MARK: - Sets List View

struct SetsListView: View {
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    @ObservedObject private var amnesia = AmnesiaCarouselSettings.shared
    @State private var showingCreateSet = false
    @State private var newlyCreatedSet: PhotoSet? = nil
    @State private var navigateToNewSet = false
    @State private var detailSet: PhotoSet? = nil
    @State private var navigateToDetail = false
    // Rename state
    @State private var setToRename: PhotoSet? = nil
    @State private var renameText = ""
    @State private var showRenameAlert = false
    // Delete confirmation state
    @State private var setToDelete: PhotoSet? = nil
    @State private var showDeleteAlert = false
    
    var body: some View {
        ZStack {
            // Dark background
            VaultTheme.Colors.background
                .ignoresSafeArea()

            // Hidden NavigationLink for programmatic navigation to newly created set
            if let newSet = newlyCreatedSet {
                NavigationLink(
                    destination: SetDetailView(set: newSet),
                    isActive: $navigateToNewSet
                ) { EmptyView() }
                .hidden()
            }
            if let detailSet {
                NavigationLink(
                    destination: SetDetailView(set: detailSet),
                    isActive: $navigateToDetail
                ) { EmptyView() }
                .hidden()
            }

            VStack(spacing: 0) {
                // ── Fixed status console (does not scroll) ───────────────────
                if instagram.isLoggedIn {
                    VStack(spacing: 0) {
                        APIBudgetWidget()
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        InstagramSyncCard()
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                            .padding(.bottom, 10)
                        CooldownWarningBanner()
                        PostRevealArchiveBanner()

                        // Visible 1pt bottom separator — clean hard edge
                        Color.white.opacity(0.18).frame(height: 1)
                    }
                    // Elevated panel color: noticeably lighter than the #0A0A0A content below
                    .background(
                        Color(hex: "222222")
                            .ignoresSafeArea(edges: .top)
                    )
                    // Downward drop shadow: creates the "floating panel" depth effect
                    .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 5)
                }

                // ── Scrollable content ───────────────────────────────────────
                ScrollView {
                    LazyVStack(spacing: VaultTheme.Spacing.md) {
                        // Header — "My Sets" with inline "+" button
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "7C3AED"), Color(hex: "FF9500")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("My Sets")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Text("Post Prediction · Old Date")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                }
                                Spacer()
                                // "+" button moved here from the navigation bar toolbar
                                Button(action: { showingCreateSet = true }) {
                                    ZStack {
                                        Circle()
                                            .fill(VaultTheme.Colors.gradientPrimary)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            Text("Each set groups photo banks used to unarchive posts during your performance.")
                                .font(.system(size: 12))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.top, VaultTheme.Spacing.md)
                        .padding(.bottom, VaultTheme.Spacing.sm)

                        if hasPendingPrePerformanceActions {
                            pendingArchiveBanner
                                .padding(.horizontal, VaultTheme.Spacing.lg)
                        }

                        postPredictionToggleCard
                            .padding(.horizontal, VaultTheme.Spacing.lg)

                        if dataManager.sets.isEmpty {
                            EmptyStateView(
                                icon: "square.stack.3d.up.slash.fill",
                                title: "No Sets Yet",
                                message: "Create your first photo set to get started with magic performances",
                                actionTitle: "Create Set",
                                action: { showingCreateSet = true }
                            )
                            .padding(.top, 40)
                        } else {
                            ForEach(dataManager.sets) { set in
                                SetRowView(
                                    set: set,
                                    isLoggedIn: instagram.isLoggedIn,
                                    onRename: {
                                        setToRename = set
                                        renameText = set.name
                                        showRenameAlert = true
                                    },
                                    onDelete: {
                                        setToDelete = set
                                        showDeleteAlert = true
                                    },
                                    onOpenDetail: {
                                        detailSet = set
                                        navigateToDetail = true
                                    }
                                )
                                .padding(.horizontal, VaultTheme.Spacing.lg)
                            }
                            .padding(.bottom, VaultTheme.Spacing.lg)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingCreateSet) {
            CreateSetView(isPresented: $showingCreateSet) { createdSet in
                newlyCreatedSet = createdSet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToNewSet = true
                }
            }
        }
        .alert("Rename Set", isPresented: $showRenameAlert) {
            TextField("Set name", text: $renameText)
            Button("Rename") {
                if let s = setToRename {
                    dataManager.renameSet(id: s.id, newName: renameText)
                }
                setToRename = nil
            }
            Button("Cancel", role: .cancel) { setToRename = nil }
        } message: {
            Text("Enter a new name for \"\(setToRename?.name ?? "")\"")
        }
        .alert("Delete Set", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let s = setToDelete {
                    withAnimation { dataManager.deleteSet(id: s.id) }
                }
                setToDelete = nil
            }
            Button("Cancel", role: .cancel) { setToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(setToDelete?.name ?? "")\"? This cannot be undone.")
        }
        // Use environment (not preferredColorScheme) so the dark theme stays local to
        // this tab and does NOT leak to the Performance tab, which must follow the device.
        .environment(\.colorScheme, .dark)
    }

    private var visibleSetPhotosCount: Int {
        dataManager.sets.reduce(0) { partial, set in
            partial + set.photos.filter { $0.mediaId != nil && !$0.isArchived }.count
        }
    }

    private var setsWithVisiblePhotosCount: Int {
        dataManager.sets.filter { set in
            set.photos.contains { $0.mediaId != nil && !$0.isArchived }
        }.count
    }

    private var hasAmnesiaPendingReset: Bool {
        amnesia.isEnabled && amnesia.isReady && amnesia.isRevealed
    }

    private var hasPendingPrePerformanceActions: Bool {
        visibleSetPhotosCount > 0 || hasAmnesiaPendingReset
    }

    private var activeSetName: String? {
        guard let activeId = activeSetSettings.activeSetId else { return nil }
        return dataManager.sets.first(where: { $0.id == activeId })?.name
    }

    private var postPredictionToggleCard: some View {
        let isEnabled = activeSetSettings.isPostPredictionEnabled
        return VaultCard(glowColor: isEnabled ? Color(hex: "7C3AED").opacity(0.25) : Color.orange.opacity(0.20)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill((isEnabled ? Color(hex: "7C3AED") : Color.orange).opacity(0.16))
                            .frame(width: 34, height: 34)
                        Image(systemName: isEnabled ? "wand.and.stars" : "power")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isEnabled ? Color(hex: "A78BFA") : .orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post Prediction")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Text(isEnabled ? "Enabled for Performance" : "Disabled in Performance")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isEnabled ? Color.green.opacity(0.9) : Color.orange.opacity(0.95))
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { activeSetSettings.isPostPredictionEnabled },
                        set: { activeSetSettings.setPostPredictionEnabled($0, availableSets: dataManager.sets) }
                    ))
                    .labelsHidden()
                    .tint(Color(hex: "7C3AED"))
                }

                Text(postPredictionToggleDescription)
                    .font(.system(size: 12, weight: isEnabled ? .medium : .semibold))
                    .foregroundColor(isEnabled ? VaultTheme.Colors.textSecondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var postPredictionToggleDescription: String {
        if !activeSetSettings.isPostPredictionEnabled {
            return "Post Prediction is off. No set will unarchive or reveal photos when you enter Performance."
        }
        if let activeSetName {
            return "Active set: \(activeSetName). Turn this off when you want Performance without Post Prediction."
        }
        return "Post Prediction is on, but no set is active. Select a set below to enable reveals."
    }

    @ViewBuilder
    private var pendingArchiveBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Pre-Performance Check Required")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
            }
            Text("Detected \(visibleSetPhotosCount) visible photo(s) across \(setsWithVisiblePhotosCount) set(s). Archive them before performance. \(hasAmnesiaPendingReset ? "Amnesia Carousel is revealed — reset it." : "")")
                .font(.system(size: 12))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
    
    private func deleteSets(at offsets: IndexSet) {
        for index in offsets {
            let set = dataManager.sets[index]
            dataManager.deleteSet(id: set.id)
        }
    }
}

// MARK: - Set Row View

struct SetRowView: View {
    let set: PhotoSet
    let isLoggedIn: Bool
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    
    // Per-type accent colors
    private var typeAccent: Color {
        switch set.type {
        case .word:   return Color(hex: "7C3AED")  // purple
        case .number: return Color(hex: "FF9500")  // orange
        case .custom: return Color(hex: "F97316")  // orange
        case .card:   return Color(hex: "16A34A")  // green
        case .list:   return Color(hex: "64D2FF")  // cyan
        }
    }
    
    private var typeGradient: [Color] {
        switch set.type {
        case .word:   return [Color(hex: "7C3AED"), Color(hex: "6D28D9")]
        case .number: return [Color(hex: "FF9500"), Color(hex: "C2670A")]
        case .custom: return [Color(hex: "F97316"), Color(hex: "EA580C")]
        case .card:   return [Color(hex: "16A34A"), Color(hex: "15803D")]
        case .list:   return [Color(hex: "64D2FF"), Color(hex: "0A84FF")]
        }
    }

    private var typeIcon: String {
        switch set.type {
        case .word:   return "textformat.abc"
        case .number: return "123.rectangle.fill"
        case .custom: return "square.grid.2x2.fill"
        case .card:   return "suit.spade.fill"
        case .list:   return "list.bullet.rectangle.portrait.fill"
        }
    }

    private var statusBadgeStyle: StatusBadge.BadgeStyle {
        switch set.status {
        case .ready:     return .info
        case .uploading: return .warning
        case .paused:    return .pending
        case .completed: return .success
        case .error:     return .error
        }
    }

    var body: some View {
        let isActive = activeSetSettings.isActive(set.id, type: set.type)

        ZStack(alignment: .leading) {
            // Active left accent bar
            if isActive {
                RoundedRectangle(cornerRadius: 3)
                    .fill(typeAccent)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 10)
            }

        VaultCard {
                VStack(spacing: 0) {
            HStack(spacing: VaultTheme.Spacing.md) {
                        // Type icon
                        IconBadge(icon: typeIcon, colors: typeGradient, size: 52)

                        VStack(alignment: .leading, spacing: 5) {
                            // Name row
                            HStack(alignment: .center, spacing: 6) {
                        Text(set.name)
                            .font(VaultTheme.Typography.title())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                                if isActive {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(typeAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(typeAccent.opacity(0.15))
                                        .cornerRadius(4)
                                }
                        
                        Spacer()
                        
                        if isLoggedIn {
                                    StatusBadge(text: set.status.label, style: statusBadgeStyle)
                                }

                                // ··· menu
                                Menu {
                                    Button { onRename?() } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { onDelete?() } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                        .frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            // Stats row
                            HStack(spacing: 8) {
                                Label(set.type.title, systemImage: "tag.fill")
                                Text("·").foregroundColor(VaultTheme.Colors.textTertiary)
                                Label("\(set.banks.isEmpty ? 1 : set.banks.count) banks",
                                      systemImage: "square.stack.3d.up.fill")
                                Text("·").foregroundColor(VaultTheme.Colors.textTertiary)
                                Label("\(set.totalPhotos) photos",
                                      systemImage: "photo.stack.fill")
                        }
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                            // Completed date
                            if isLoggedIn && set.status == .completed,
                               let completedDate = set.completedAt {
                                Label(completedDate.formatted(date: .abbreviated, time: .omitted),
                                      systemImage: "calendar")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                                    .padding(.top, 1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpenDetail?()
                    }

                    // Upload progress bar
                    if isLoggedIn && (set.status == .uploading || set.status == .paused) {
                        VStack(spacing: 4) {
                            ProgressBar(
                                progress: set.totalPhotos > 0
                                    ? Double(set.uploadedPhotos) / Double(set.totalPhotos) : 0,
                                height: 5,
                                gradient: set.status == .paused 
                                    ? LinearGradient(colors: [VaultTheme.Colors.textSecondary],
                                                     startPoint: .leading, endPoint: .trailing)
                                    : VaultTheme.Colors.gradientWarning
                            )
                            HStack {
                                Text("\(set.uploadedPhotos) / \(set.totalPhotos)")
                                Spacer()
                                let pct = set.totalPhotos > 0
                                    ? Int((Double(set.uploadedPhotos) / Double(set.totalPhotos)) * 100) : 0
                                Text("\(pct)%").fontWeight(.bold)
                                    .foregroundColor(set.status == .paused
                                        ? VaultTheme.Colors.textSecondary : VaultTheme.Colors.warning)
                            }
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        .padding(.top, 10)
                    }

                    // Active toggle strip — always visible at the bottom of the card
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.top, 10)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isActive {
                                activeSetSettings.setActive(nil, for: set.type)
                            } else {
                                activeSetSettings.setActive(set.id, for: set.type)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isActive ? typeAccent : VaultTheme.Colors.textTertiary)
                            Text(isActive ? "Active set" : "Set as active")
                                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? typeAccent : VaultTheme.Colors.textSecondary)
                            Spacer()
                            if isActive {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(typeAccent.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // ── Per-set input method picker ───────────────
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.top, 4)

                    SetInputPicker(set: set)
                        .id(set.id)

                    // ── URL Scheme (only for types that support it) ─
                    if set.type.revealURLTemplate != nil {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.top, 4)
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            Text("URL Scheme")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .textCase(.uppercase)
                        }
                        SetURLSchemeRow(set: set)
                    }

                    // ── Edit set detail ─
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.top, 4)

                    Button {
                        onOpenDetail?()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Upload to Instagram")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text(set.type == .list ? "Add media to list items, then upload/archive the set." : "Add media to slots, then upload/archive the set.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [typeAccent.opacity(0.78), typeAccent.opacity(0.52)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .cornerRadius(11)
                        .shadow(color: typeAccent.opacity(0.22), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, isActive ? 8 : 0)
        }
        .glowEffect(color: isActive ? typeAccent.opacity(0.35) : .clear, radius: 6)
        .glowEffect(color: isLoggedIn && set.status == .uploading ? VaultTheme.Colors.warning : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Set URL Scheme Row

/// Displays the vault:// reveal URL for a specific set with a one-tap copy button.
struct SetURLSchemeRow: View {
    let set: PhotoSet
    @State private var copied = false

    private var urlScheme: String {
        let safeName = set.name
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? set.name
        guard let mode = set.type.revealURLTemplate else { return "" }
        switch set.type {
        case .word:           return "vault://reveal?\(mode)=<word>&set=\(safeName)"
        case .number, .custom, .list: return "vault://reveal?\(mode)=<value>&set=\(safeName)"
        case .card:           return "vault://reveal?\(mode)=<card>&set=\(safeName)"
        }
    }

    var body: some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(VaultTheme.Colors.textTertiary)
            Text(urlScheme)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                UIPasteboard.general.string = urlScheme
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(copied ? .green : VaultTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var dataManager = DataManager.shared
    
    var body: some View {
        List {
            ForEach(dataManager.logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.action)
                            .font(.headline)
                        Spacer()
                        Text(log.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(log.details)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Activity")
        .listStyle(.insetGrouped)
    }
}

// MARK: - Instagram Sync Card

/// Compact card placed right below the API Budget widget.
/// Shows the last time the profile was synced from Instagram and provides a
/// one-tap Refresh button for when the user has made changes on real Instagram
/// (new post, bio edit, new highlight, etc.).
struct InstagramSyncCard: View {
    @ObservedObject private var instagram = InstagramService.shared

    // Last refresh timestamp — shared with PerformanceView via AppStorage.
    @AppStorage("perf_lastRefreshTimestamp") private var lastRefreshTimestamp: Double = 0

    @State private var isRefreshing = false
    @State private var showCopied  = false

    private var lastSyncText: String {
        guard lastRefreshTimestamp > 0 else {
            return String(localized: "sync.never_synced")
        }
        let date = Date(timeIntervalSince1970: lastRefreshTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.primary)
                Text(String(localized: "sync.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                Spacer()
                // Last sync badge
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                    Text(lastSyncText)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                }
            }

            // ── Info line ─────────────────────────────────────────────────
            Text(String(localized: "sync.info"))
                .font(.system(size: 12))
                .foregroundColor(VaultTheme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // ── Refresh button ────────────────────────────────────────────
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                NotificationCenter.default.post(name: .performanceManualRefresh, object: nil)
                // Re-enable after 3 s — the actual callback lives in PerformanceView
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    isRefreshing = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(isRefreshing
                         ? String(localized: "sync.refreshing")
                         : String(localized: "sync.refresh_button"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isRefreshing
                    ? Color.white.opacity(0.08)
                    : VaultTheme.Colors.primary.opacity(0.18)
                )
                .foregroundColor(isRefreshing ? VaultTheme.Colors.textTertiary : VaultTheme.Colors.primary)
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: isRefreshing)
            }
            .disabled(isRefreshing || !instagram.isLoggedIn)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaultTheme.Colors.primary.opacity(0.18), lineWidth: 1))
        // Re-read the timestamp when the app comes to foreground or after a refresh
        .onChange(of: lastRefreshTimestamp) { _ in
            if isRefreshing { isRefreshing = false }
        }
    }
}

// MARK: - API Budget Widget

/// Compact card showing actions used this hour, a colour-coded progress bar,
/// and the exact time the budget will be fully renewed.
/// Designed for the Settings tab — updates on every `.onAppear`.
struct APIBudgetWidget: View {
    @ObservedObject private var instagram = InstagramService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var used: Int = 0
    @State private var remaining: Int = 55
    @State private var renewalTime: Date? = nil

    private let max = 55

    // Colour zones: green → yellow → red
    private var barColor: Color {
        switch used {
        case 0..<36:  return Color(red: 0.22, green: 0.78, blue: 0.45)  // green
        case 36..<48: return .orange
        default:      return .red
        }
    }

    private var fraction: Double { min(1, Double(used) / Double(max)) }

    private var statusLabel: String {
        if remaining == 0 {
            return String(localized: "budget.status.full_used")
        }
        if let t = renewalTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return String(format: String(localized: "budget.renewal_at"), formatter.string(from: t))
        }
        return String(localized: "budget.status.full")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(barColor)
                    .font(.system(size: 15, weight: .semibold))
                Text(String(localized: "budget.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                Spacer()
                Text(String(format: String(localized: "budget.used_of"), used, max))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(barColor)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction, height: 6)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 6)

            HStack {
                Image(systemName: renewalTime == nil ? "checkmark.circle.fill" : "clock")
                    .font(.caption2)
                    .foregroundColor(renewalTime == nil ? .green : VaultTheme.Colors.textSecondary)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundColor(renewalTime == nil ? Color.green.opacity(0.9) : VaultTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(barColor.opacity(0.25), lineWidth: 1))
        .onAppear { refresh() }
        // Refresh whenever a new action is tracked
        .onChange(of: instagram.actionsThisHour) { _ in refresh() }
        // Refresh when the app returns to the foreground — the rolling 1-hour window
        // may have expired actions that are not tracked via actionsThisHour changes.
        .onChange(of: scenePhase) { phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        let rl = instagram.checkRateLimit()
        used      = rl.actionsUsed
        remaining = rl.remaining
        renewalTime = instagram.budgetRenewalTime()
    }
}

// MARK: - Cooldown Warning Banner

/// Banner rojo que muestra los cooldowns anti-bot activos (foto, nota, bio,
/// y el cooldown de 90s de interface capture de bio/notas) con un countdown
/// en tiempo real. Se oculta automáticamente cuando expiran todos.
struct CooldownWarningBanner: View {
    @ObservedObject private var instagram = InstagramService.shared
    @Environment(\.scenePhase) private var scenePhase

    // Estado local para los tiempos restantes
    @State private var picSeconds: Int          = 0
    @State private var noteSeconds: Int         = 0
    @State private var bioSeconds: Int          = 0
    @State private var captureNoteSeconds: Int  = 0
    @State private var captureBioSeconds: Int   = 0
    @State private var perfPauseSeconds: Int    = 0
    @State private var pullRefreshSeconds: Int  = 0
    @State private var timer: Timer?            = nil
    @State private var blinkTimer: Timer?       = nil
    @State private var blink: Bool              = false
    @State private var refreshTick: Int         = 0

    // Interface-capture cooldown duration kept in sync with PerformanceView
    private let captureCooldown: TimeInterval = 90

    private var activeCooldowns: [(icon: String, label: String, seconds: Int)] {
        var list: [(String, String, Int)] = []
        if perfPauseSeconds   > 0 { list.append(("bolt.slash.fill",                "cooldown.performance",     perfPauseSeconds))   }
        if picSeconds         > 0 { list.append(("camera.fill",                    "cooldown.photo",           picSeconds))         }
        if noteSeconds        > 0 { list.append(("bubble.left.fill",               "cooldown.note",            noteSeconds))        }
        if bioSeconds         > 0 { list.append(("person.text.rectangle.fill",     "cooldown.bio",             bioSeconds))         }
        if captureNoteSeconds > 0 { list.append(("hand.draw.fill",                 "cooldown.capture.note",    captureNoteSeconds)) }
        if captureBioSeconds  > 0 { list.append(("hand.draw.fill",                 "cooldown.capture.bio",     captureBioSeconds))  }
        if pullRefreshSeconds > 0 { list.append(("arrow.clockwise.circle.fill",    "cooldown.refresh",         pullRefreshSeconds)) }
        return list
    }

    private var shouldBlink: Bool {
        hasActive
    }

    private var hasActive: Bool { !activeCooldowns.isEmpty }

    var body: some View {
        // The outer wrapper is always rendered so the timer fires even before
        // the first cooldown appears (e.g. right after returning from Performance).
        ZStack {
            if hasActive {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasActive)
            }
        }
        .onAppear {
            refresh()
            startTimer()
            startBlink()
        }
        .onDisappear { stopTimer() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refresh() }
        }
        .onChange(of: shouldBlink) { active in
            if active { startBlink() }
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(blink ? .red : Color.red.opacity(0.35))
                    .scaleEffect(blink ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 0.5), value: blink)
                    .padding(.top, 1)
                cooldownList
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bannerBackground)
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var cooldownList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "cooldown.title"))
                .font(.system(size: 13, weight: .black))
                .foregroundColor(blink ? .red : Color.red.opacity(0.45))
                .scaleEffect(blink ? 1.03 : 1.0, anchor: .leading)
                .animation(.easeInOut(duration: 0.5), value: blink)
            ForEach(activeCooldowns, id: \.label) { item in
                CooldownRow(
                    item: item,
                    formatSeconds: formatSeconds,
                    // Strong blinking on every visible row so cooldowns are hard to miss.
                    highlight: blink
                )
            }
        }
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(shouldBlink
                  ? Color.red.opacity(blink ? 0.18 : 0.08)
                  : Color.red.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(shouldBlink ? (blink ? 0.9 : 0.3) : 0.4), lineWidth: blink ? 1.5 : 1))
            .animation(.easeInOut(duration: 0.5), value: blink)
    }

    private func formatSeconds(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        if m > 0 { return String(format: "%d:%02d", m, sec) }
        return "\(sec)s"
    }

    private func captureRemainingSeconds(for target: String) -> Int {
        let key = "last_interface_capture_sent_\(target)"
        let lastSent = UserDefaults.standard.double(forKey: key)
        guard lastSent > 0 else { return 0 }
        let remaining = captureCooldown - (Date().timeIntervalSince1970 - lastSent)
        return remaining > 0 ? Int(remaining) : 0
    }

    private func refresh() {
        let pic  = instagram.isProfilePicOnCooldown()
        let note = instagram.isNoteOnCooldown()
        let bio  = instagram.isBiographyOnCooldown()
        picSeconds  = pic.onCooldown  ? pic.remainingSeconds  : 0
        noteSeconds = note.onCooldown ? note.remainingSeconds : 0
        bioSeconds  = bio.onCooldown  ? bio.remainingSeconds  : 0
        captureNoteSeconds = captureRemainingSeconds(for: "note")
        captureBioSeconds  = captureRemainingSeconds(for: "bio")
        perfPauseSeconds   = InstagramSafetyGate.shared.performancePauseSecondsRemaining
        let pullDecision = InstagramSafetyGate.shared.decision(for: .pullRefresh)
        pullRefreshSeconds = pullDecision.allowed ? 0 : max(0, pullDecision.waitSeconds)
    }

    private func startBlink() {
        guard blinkTimer == nil else { return }   // already running
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
            if shouldBlink {
                blink.toggle()
            } else {
                blink = false
                t.invalidate()
                blinkTimer = nil
            }
        }
    }

    private func startTimer() {
        stopTimer()
        refreshTick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if picSeconds          > 0 { picSeconds          -= 1 }
            if noteSeconds         > 0 { noteSeconds         -= 1 }
            if bioSeconds          > 0 { bioSeconds          -= 1 }
            if captureNoteSeconds  > 0 { captureNoteSeconds  -= 1 }
            if captureBioSeconds   > 0 { captureBioSeconds   -= 1 }
            if perfPauseSeconds    > 0 { perfPauseSeconds    -= 1 }
            if pullRefreshSeconds  > 0 { pullRefreshSeconds  -= 1 }

            // Resync every 3 s so new cooldowns from Performance are detected
            // within seconds of the user navigating back to this view.
            refreshTick += 1
            if refreshTick >= 3 {
                refreshTick = 0
                refresh()
                if shouldBlink { startBlink() }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
}

// MARK: - Post-Reveal Re-Archive Banner

/// Rojo parpadeante que aparece en Settings tras un reveal de Post Prediction
/// mientras haya fotos sin archivar. Muestra el countdown del hold anti-bot
/// y ofrece un botón "Archivar ahora" que respeta todos los cooldowns de SafetyGate.
struct PostRevealArchiveBanner: View {
    @ObservedObject private var instagram = InstagramService.shared
    @ObservedObject private var dataManager = DataManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isArchiving      = false
    @State private var doneSoFar        = 0
    @State private var totalToArchive   = 0
    @State private var archiveError: String? = nil
    @State private var postRevealLeft: Int  = 0
    @State private var timer: Timer?        = nil
    @State private var blinkTimer: Timer?   = nil
    @State private var blink: Bool          = false
    @State private var refreshTick: Int     = 0

    // Photos that were unarchived by PP reveal and still need to be re-archived
    private var revealedPhotos: [(setId: UUID, photo: SetPhoto)] {
        dataManager.sets.flatMap { set in
            set.photos
                .filter { !$0.isArchived && $0.mediaId != nil && $0.uploadStatus == .completed }
                .map { (set.id, $0) }
        }
    }

    private var count: Int { revealedPhotos.count }
    private var hasPhotos: Bool { count > 0 }

    var body: some View {
        ZStack {
            if hasPhotos {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasPhotos)
            }
        }
        .onAppear {
            refreshCounters()
            startTimer()
        }
        .onDisappear { stopTimer() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshCounters() }
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(blink ? .red : Color.red.opacity(0.35))
                .scaleEffect(blink ? 1.18 : 1.0)
                .animation(.easeInOut(duration: 0.5), value: blink)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(isArchiving
                     ? "Archivando \(doneSoFar)/\(totalToArchive)…"
                     : "\(count) foto\(count == 1 ? "" : "s") visible\(count == 1 ? "" : "s") tras el reveal")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(blink ? .red : Color.red.opacity(0.45))
                    .scaleEffect(blink ? 1.03 : 1.0, anchor: .leading)
                    .animation(.easeInOut(duration: 0.5), value: blink)

                if let err = archiveError {
                    Text("Error: \(err)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if postRevealLeft > 0 {
                    Text("Archivable en \(formatSeconds(postRevealLeft)) — espera el hold anti-bot")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(blink ? .red : Color.red.opacity(0.8))
                        .animation(.easeInOut(duration: 0.5), value: blink)
                } else if !isArchiving {
                    Text("Post Prediction dejó fotos visibles en Instagram. Archívalas para el próximo truco.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !isArchiving {
                    Button(action: {
                        archiveError = nil
                        Task { await runArchive() }
                    }) {
                        Label("Archivar ahora", systemImage: "archivebox.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(archiveButtonEnabled ? Color.red : Color.red.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!archiveButtonEnabled)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(blink ? 0.18 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red.opacity(blink ? 0.9 : 0.3), lineWidth: blink ? 1.5 : 1))
                .animation(.easeInOut(duration: 0.5), value: blink)
        )
        .padding(.horizontal, VaultTheme.Spacing.lg)
        .padding(.bottom, 8)
    }

    private var archiveButtonEnabled: Bool {
        !isArchiving
        && postRevealLeft == 0
        && !instagram.isLocked
        && !instagram.isSessionChallenged
        && !instagram.isSessionExpired
    }

    // MARK: - Archive action

    private func runArchive() async {
        let photos = revealedPhotos
        guard !photos.isEmpty else { return }

        await MainActor.run {
            isArchiving      = true
            doneSoFar        = 0
            totalToArchive   = photos.count
            archiveError     = nil
        }

        for (_, photo) in photos {
            guard let mediaId = photo.mediaId else { continue }

            // Re-check post-reveal hold before each photo — the hold may still be
            // active for individual IDs even after the global countdown clears.
            let mediaSafety = InstagramSafetyGate.shared.canArchive(mediaId: mediaId)
            guard mediaSafety.allowed else {
                await MainActor.run {
                    archiveError = "Hold activo: \(mediaSafety.reason) — espera \(mediaSafety.waitSeconds)s"
                    isArchiving  = false
                }
                return
            }

            do {
                // skipPreCheck = true: skip the GET state-check (we know from local
                // model that the photo is unarchived).  archivePhoto internally
                // applies the 3–6.5 s anti-bot delay before the POST.
                let success = try await instagram.archivePhoto(mediaId: mediaId, skipPreCheck: true)
                if success {
                    await MainActor.run {
                        dataManager.updatePhoto(photoId: photo.id, isArchived: true)
                        doneSoFar += 1
                    }
                }
            } catch {
                await MainActor.run {
                    archiveError = error.localizedDescription
                    isArchiving  = false
                }
                return
            }
        }

        await MainActor.run { isArchiving = false }
    }

    // MARK: - Timer

    private func refreshCounters() {
        postRevealLeft = InstagramSafetyGate.shared.postRevealSecondsRemaining
    }

    private func startTimer() {
        stopTimer()
        refreshTick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if postRevealLeft > 0 { postRevealLeft -= 1 }
            refreshTick += 1
            if refreshTick >= 3 {
                refreshTick = 0
                refreshCounters()
            }
            if blink || postRevealLeft > 0 { startBlink() }
        }
    }

    private func stopTimer() {
        timer?.invalidate();        timer       = nil
        blinkTimer?.invalidate();   blinkTimer  = nil
    }

    private func startBlink() {
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
            if hasPhotos {
                blink.toggle()
            } else {
                blink = false; t.invalidate(); blinkTimer = nil
            }
        }
    }

    private func formatSeconds(_ s: Int) -> String {
        let m = s / 60; let sec = s % 60
        return m > 0 ? String(format: "%d:%02d", m, sec) : "\(sec)s"
    }
}

/// Una fila dentro del CooldownWarningBanner.
/// `highlight` activa el parpadeo en filas de interface capture cooldown.
private struct CooldownRow: View {
    let item: (icon: String, label: String, seconds: Int)
    let formatSeconds: (Int) -> String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(highlight ? .red : Color.red.opacity(0.8))
                .animation(.easeInOut(duration: 0.5), value: highlight)
            Text(LocalizedStringKey(item.label))
                .font(.system(size: 11, weight: highlight ? .bold : .medium))
                .foregroundColor(highlight ? .red : Color.red.opacity(0.85))
                .animation(.easeInOut(duration: 0.5), value: highlight)
            Spacer()
            Text(formatSeconds(item.seconds))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(.red)
                .scaleEffect(highlight ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.5), value: highlight)
        }
    }
}

// MARK: - Duplicate Note Warning Banner

/// Shown at the top of Settings after a Performance note send is blocked because
/// the detected text matches the last note exactly. This is intentionally not a
/// timer: the fix for the user is to change at least one word.
private struct DuplicateNoteWarningBanner: View {
    @AppStorage("note_duplicate_warning_text") private var duplicateText: String = ""
    @State private var blink = false
    @State private var timer: Timer? = nil

    var body: some View {
        if !duplicateText.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(blink ? .red : Color.red.opacity(0.35))
                    .scaleEffect(blink ? 1.18 : 1.0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate note blocked")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(blink ? .red : Color.red.opacity(0.45))
                    Text("OCR recognized \"\(duplicateText)\" again. Change at least one word before sending another Note.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(blink ? .red : Color.red.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    duplicateText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(blink ? 0.18 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(blink ? 0.9 : 0.3), lineWidth: blink ? 1.5 : 1)
                    )
            )
            .animation(.easeInOut(duration: 0.5), value: blink)
            .onAppear { startBlink() }
            .onDisappear { stopBlink() }
        }
    }

    private func startBlink() {
        stopBlink()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            blink.toggle()
        }
    }

    private func stopBlink() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Exit-Performance Budget Sheet

/// Non-blocking sheet shown when the user leaves Performance with < 15 actions remaining.
/// Gives them the key info to decide whether to come back soon or wait for renewal.
struct BudgetWarningSheet: View {
    let used: Int
    let remaining: Int
    let renewalTime: Date?
    let onDismiss: () -> Void

    private let max = 55

    private var fraction: Double { min(1, Double(used) / Double(max)) }

    private var barColor: Color {
        remaining < 7 ? .red : .orange
    }

    private var renewalString: String {
        guard let t = renewalTime else { return "" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: t)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(barColor)
                Text(String(localized: "budget.warning.title"))
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }

            // Budget card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(format: String(localized: "budget.used_of"), used, max))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundColor(barColor)
                    Spacer()
                    Text(String(format: String(localized: "budget.remaining"), remaining))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 5).fill(barColor)
                            .frame(width: geo.size.width * fraction, height: 8)
                    }
                }
                .frame(height: 8)

                if let _ = renewalTime {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.caption)
                        Text(String(format: String(localized: "budget.warning.renewal"), renewalString))
                            .font(.footnote)
                    }
                    .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(barColor.opacity(0.3), lineWidth: 1))
            .padding(.horizontal, 4)

            Text(String(localized: "budget.warning.advice"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button(action: onDismiss) {
                Text(String(localized: "action.understood"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Color(hex: "#1C1C1E").ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var instagram      = InstagramService.shared
    @ObservedObject var backup         = CloudBackupService.shared
    @ObservedObject private var uploadManager = UploadManager.shared
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var amnesia = AmnesiaCarouselSettings.shared
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @ObservedObject private var ppTestMode = PostPredictionTestMode.shared
    @State private var settingsProfilePic: UIImage? = nil
    @State private var showingLogoutAlert = false
    @State private var showingFollowerData = false
    @State private var latestFollower: InstagramFollower?
    @State private var followerFullInfo: [String: Any]?
    @State private var isLoadingFollower = false
    
    // Profile Picture Change
    @State private var showingImagePicker = false
    @State private var selectedImageData: Data?
    @State private var isUploadingProfilePic = false
    @State private var uploadMessage: String?
    @State private var showingUploadAlert = false
    @AppStorage("autoProfilePicOnPerformance") private var autoProfilePicOnPerformance = false
    
    // Instagram Notes
    @State private var noteText: String = ""
    @State private var isSendingNote = false
    @State private var noteMessage: String?
    @State private var showingNoteAlert = false

    // Clipboard auto-mode: "" = off, "note" = send as note, "bio" = update biography
    // Only one can be active at a time.
    @AppStorage("clipboardAutoMode") private var clipboardAutoMode: String = ""

    // Top-level auto-input mode per target (off/clipboard/api/ocr)
    @AppStorage("noteTopInputMode") private var noteTopInputMode: String = "off"
    @AppStorage("bioTopInputMode")  private var bioTopInputMode:  String = "off"
    @AppStorage("note_feature_enabled") private var noteFeatureEnabled: Bool = true
    @AppStorage("bio_feature_enabled")  private var bioFeatureEnabled:  Bool = true

    // Text templates — user writes "My prediction is {word}" and the app
    // replaces {word} with the detected/fetched word at send time.
    @AppStorage("note_template") private var noteTemplate: String = ""
    @AppStorage("bio_template")   private var bioTemplate1: String = ""
    @AppStorage("bio_template_2") private var bioTemplate2: String = ""
    @AppStorage("bio_template_3") private var bioTemplate3: String = ""
    @AppStorage("bio_template_4") private var bioTemplate4: String = ""
    @AppStorage("bio_active_slot") private var bioActiveSlot: Int = 0
    @AppStorage("bio_acrostic_enabled") private var bioAcrosticEnabled: Bool = false

    private var activeBioBinding: Binding<String> {
        switch bioActiveSlot {
        case 1:  return $bioTemplate2
        case 2:  return $bioTemplate3
        case 3:  return $bioTemplate4
        default: return $bioTemplate1
        }
    }
    private var bioTemplate: String {
        get { activeBioBinding.wrappedValue }
        nonmutating set { activeBioBinding.wrappedValue = newValue }
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    // OCR configuration (shared between note and bio)
    @AppStorage("ocr_language") private var ocrLanguage: String = "es-ES"
    @AppStorage("ocr_camera")   private var ocrCamera:   Int    = 0  // 0=back, 1=front

    // Biography
    @State private var bioText: String = ""
    @State private var isSendingBio = false
    @State private var bioMessage: String?
    @State private var showingBioAlert = false
    @FocusState private var bioFieldFocused:  Bool
    @FocusState private var noteFieldFocused: Bool
    
    // Hidden Login (easter egg)
    @State private var showingLogin = false
    @State private var developerMode = false
    @State private var communityPasswordCopied = false
    
    // Other Settings — Fake Home Screen & launch behavior
    @AppStorage("launchDirectlyToPerformance") private var launchDirectlyToPerformance = false
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @State private var showingHomeScreenPicker = false

    // Collapsible cards — Instagram Profile section
    @State private var profilePicExpanded = false
    @State private var noteExpanded = false
    @State private var bioExpanded = false
    @State private var showProfilePicHelp = false
    @State private var showNoteHelp = false
    @State private var showBioHelp = false
    // TEST: Archive access
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "0F0F0F").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Fixed status console (does not scroll) ───────────────────
                if instagram.isLoggedIn {
                    VStack(spacing: 0) {
                        APIBudgetWidget()
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        InstagramSyncCard()
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                            .padding(.bottom, 10)
                        CooldownWarningBanner()
                        PostRevealArchiveBanner()

                        // Visible 1pt bottom separator
                        Color.white.opacity(0.18).frame(height: 1)
                    }
                    .background(
                        Color(hex: "222222")
                            .ignoresSafeArea(edges: .top)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 5)
                }

                // ── Scrollable content ────────────────────────────────────────
                mainScrollView
            }
        }
        .navigationBarHidden(true)
        // Use environment (not preferredColorScheme) so the dark theme stays local to
        // this tab and does NOT leak to the Performance tab, which must follow the device.
        .environment(\.colorScheme, .dark)
        .alert("Logout", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) { instagram.logout() }
        } message: { Text("Are you sure you want to logout?") }
        .alert(uploadMessage ?? "Upload Complete", isPresented: $showingUploadAlert) {
            Button("OK") { uploadMessage = nil }
        } message: { Text(uploadMessage ?? "") }
        .alert(noteMessage ?? "", isPresented: $showingNoteAlert) {
            Button("OK") { noteMessage = nil }
        } message: { Text(noteMessage ?? "") }
        .alert(bioMessage ?? "", isPresented: $showingBioAlert) {
            Button("OK") { bioMessage = nil }
        } message: { Text(bioMessage ?? "") }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImageData: $selectedImageData)
        }
        .sheet(isPresented: $showingHomeScreenPicker) {
            HomeScreenImagePicker { image in
                illusionService.save(image)
            }
        }
        .sheet(isPresented: $showingFollowerData) {
            FollowerDataSheet(follower: latestFollower, fullInfo: followerFullInfo)
        }
        .sheet(isPresented: $showingLogin) {
            InstagramWebLoginView(isPresented: $showingLogin)
        }
    }

    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !instagram.isLoggedIn {
                    notLoggedInSection
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.vertical, VaultTheme.Spacing.lg)
                } else {
                    // "Settings" inline header — replaces the navigation bar title
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [VaultTheme.Colors.primaryDark, VaultTheme.Colors.secondary],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text("Settings")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    .padding(.top, VaultTheme.Spacing.md)
                    .padding(.bottom, VaultTheme.Spacing.sm)

                    loggedInSections
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.lg)
                }
            }
        }
    }

    @ViewBuilder private var loggedInSections: some View {
        if hasPendingPrePerformanceActions {
            prePerformanceWarningSection
        }
        DuplicateNoteWarningBanner()
            .padding(.bottom, 4)
        accountSection
        performanceModeSection
        instagramProfileSection
        tricksSection
        integrationsSection
        otherSection
        communitySection
        dataSection
    }

    private var visibleSetPhotosCount: Int {
        dataManager.sets.reduce(0) { partial, set in
            partial + set.photos.filter { $0.mediaId != nil && !$0.isArchived }.count
        }
    }

    private var setsWithVisiblePhotosCount: Int {
        dataManager.sets.filter { set in
            set.photos.contains { $0.mediaId != nil && !$0.isArchived }
        }.count
    }

    private var hasAmnesiaPendingReset: Bool {
        amnesia.isEnabled && amnesia.isReady && amnesia.isRevealed
    }

    private var hasPendingPrePerformanceActions: Bool {
        visibleSetPhotosCount > 0 || hasAmnesiaPendingReset
    }

    @ViewBuilder
    private var prePerformanceWarningSection: some View {
        settingsSectionLabel("PRE-PERFORMANCE CHECK", icon: "exclamationmark.triangle.fill", color: .orange)
        modernCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Archive pending items before performance")
                        .font(VaultTheme.Typography.bodyBold())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                }
                Text("Detected \(visibleSetPhotosCount) visible photo(s) in \(setsWithVisiblePhotosCount) set(s). Re-verify and archive in Sets before opening Performance.")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if hasAmnesiaPendingReset {
                    Text("Amnesia Carousel is revealed. Open Amnesia Carousel and press Reset before the next show.")
                                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Not Logged In

    @ViewBuilder private var notLoggedInSection: some View {
        settingsSectionLabel("ACCOUNT", icon: "person.circle", color: Self.colorAccount)
        modernCard {
            VStack(spacing: VaultTheme.Spacing.md) {
                Text("Version \(appVersionDisplay)")
                                        .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .onTapGesture {
                        withAnimation { developerMode = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .onLongPressGesture(minimumDuration: 2.0) {
                        withAnimation { developerMode = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                if developerMode {
                    OutlineButton(title: "Connect Account", icon: "link.badge.plus",
                                  action: { showingLogin = true })
                }
            }
        }
    }

    // MARK: - Section: Account

    @ViewBuilder private var accountSection: some View {
        settingsSectionLabel("ACCOUNT", icon: "person.circle.fill", color: Self.colorAccount)
        accentedSection(color: Self.colorAccount) {
            modernCard {
                VStack(spacing: 0) {
                    // Avatar row
                    HStack(spacing: VaultTheme.Spacing.md) {
                        Group {
                            if let pic = settingsProfilePic ?? profileCache.pendingProfilePic {
                                Image(uiImage: pic)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle().fill(Self.colorAccount.opacity(0.2)).frame(width: 48, height: 48)
                                    Text(String(instagram.session.username.prefix(1)).uppercased())
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Self.colorAccount)
                                }
                            }
                        }
                        .task { await loadSettingsProfilePic() }
                        VStack(alignment: .leading, spacing: 2) {
                            let fullName = profileCache.cachedProfile?.fullName ?? ""
                            if !fullName.isEmpty {
                                Text(fullName)
                                    .font(VaultTheme.Typography.bodyBold())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("@\(instagram.session.username)")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                    } else {
                                Text("@\(instagram.session.username)")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                            Text("Instagram account connected")
                                            .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                    }
                    modernDivider()
                    NavigationLink(destination: LogsView()) {
                        modernRow(icon: "doc.text.fill", iconColor: Self.colorAccount,
                                  title: "View App Logs",
                                  trailing: Text("\(LogManager.shared.logs.count)").font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary))
                    }
                    .buttonStyle(.plain)
                    modernDivider()
                    NavigationLink(destination: CrashLogsView()) {
                        modernRow(icon: "ladybug.fill", iconColor: .red,
                                  title: "Crash Logs",
                                  trailing: crashBadge)
                    }
                    .buttonStyle(.plain)
                    modernDivider()
                    Button(action: { showingLogoutAlert = true }) {
                        modernRow(icon: "rectangle.portrait.and.arrow.right", iconColor: VaultTheme.Colors.error,
                                  title: "Logout",
                                  trailing: EmptyView())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Spacer().frame(height: 28)
    }

    /// Badge shown next to "Crash Logs" row: red pill with count when crashes exist, empty otherwise.
    @ViewBuilder private var crashBadge: some View {
        let count = CrashLoggerService.shared.storedReports.count
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
        } else {
            EmptyView()
        }
    }

    private func loadSettingsProfilePic() async {
        guard let url = profileCache.cachedProfile?.profilePicURL, !url.isEmpty else { return }
        if let cached = ProfileCacheService.shared.loadImage(forURL: url) {
            await MainActor.run { settingsProfilePic = cached }
            return
        }
        guard let imageUrl = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: imageUrl),
              let image = UIImage(data: data) else { return }
        ProfileCacheService.shared.saveImage(image, forURL: url)
        await MainActor.run { settingsProfilePic = image }
    }

    // MARK: - Section: Instagram Profile

    @ViewBuilder private var performanceModeSection: some View {
        settingsSectionLabel("performance.mode.title", icon: "testtube.2", color: Color.green)
        accentedSection(color: Color.green) {
            modernCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: ppTestMode.isEnabled ? "checkmark.shield.fill" : "play.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ppTestMode.isEnabled ? Color.green : VaultTheme.Colors.textTertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ppTestMode.isEnabled ? String(localized: "performance.mode.test") : String(localized: "performance.mode.normal"))
                                .font(VaultTheme.Typography.bodyBold())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text(String(localized: "performance.mode.subtitle"))
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $ppTestMode.isEnabled)
                            .labelsHidden()
                            .tint(Color.green)
                    }

                    Text(String(localized: "performance.mode.test.note"))
                        .font(.system(size: 13))
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var instagramProfileSection: some View {
        settingsSectionLabel("INSTAGRAM PROFILE", icon: "camera.fill", color: Self.colorProfile)
        accentedSection(color: Self.colorProfile) {
            profilePictureCard
            noteCard
            biographyCard
        }
        .sheet(isPresented: $showProfilePicHelp) {
            ProfilePictureHelpView(onClose: { showProfilePicHelp = false })
        }
        .sheet(isPresented: $showNoteHelp) {
            NoteHelpView(onClose: { showNoteHelp = false })
        }
        .sheet(isPresented: $showBioHelp) {
            BiographyHelpView(onClose: { showBioHelp = false })
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Tricks

    @ViewBuilder private var tricksSection: some View {
        settingsSectionLabel("TRICKS", icon: "wand.and.stars", color: Self.colorTricks)
        accentedSection(color: Self.colorTricks) {
            ForceReelSettingsCard()
            ForcePostSettingsCard()
            ForceNumberRevealSettingsCard()
            FollowingMagicSettingsCard()
            DateForceSettingsCard()
            AmnesiaCarouselSettingsCard()
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Integrations

    @ViewBuilder private var integrationsSection: some View {
        settingsSectionLabel("INTEGRATIONS", icon: "bolt.horizontal.fill", color: Self.colorIntegration)
        accentedSection(color: Self.colorIntegration) {
            modernCard {
                VStack(spacing: 0) {
                    NavigationLink(destination: IntegrationsSettingsView()) {
                        modernRow(icon: "bolt.horizontal.fill", iconColor: Self.colorIntegration,
                                  title: "Magic API",
                                  trailing: Text("Inject & Custom APIs")
                                    .font(VaultTheme.Typography.caption())
                                      .foregroundColor(VaultTheme.Colors.textSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Community

    @ViewBuilder private var communitySection: some View {
        settingsSectionLabel("COMMUNITY", icon: "person.3.fill", color: Self.colorCommunity)
        accentedSection(color: Self.colorCommunity) {
            modernCard {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Self.colorCommunity)
                                .frame(width: 36, height: 36)
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Facebook Group")
                                .font(VaultTheme.Typography.body().weight(.semibold))
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text("Updates, new tricks, routines & community")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    Text("Join the private group to discover new updates, share routines, get ideas and connect with other performers using the app.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
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
                                .foregroundColor(Self.colorCommunity)
                            Text("Password: ")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                            + Text("vault67")
                                .font(VaultTheme.Typography.caption().weight(.bold))
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: communityPasswordCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(communityPasswordCopied ? .green : VaultTheme.Colors.textSecondary)
                            Text(communityPasswordCopied ? "Copied!" : "Copy")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(communityPasswordCopied ? .green : VaultTheme.Colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#2C2C2E"))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    Link(destination: URL(string: "https://www.facebook.com/share/g/1bj4vp4GoX/?mibextid=wwXIfr")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 16))
                            Text("Join the Facebook Group")
                                .font(VaultTheme.Typography.body().weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Self.colorCommunity)
                        .cornerRadius(12)
                    }
                }
            }
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Other

    @ViewBuilder private var otherSection: some View {
        settingsSectionLabel("OTHER", icon: "gearshape.2.fill", color: Self.colorData)
        accentedSection(color: Self.colorData) {
            modernToggleRow(
                icon: "bolt.fill",
                iconColor: Self.colorData,
                title: "settings.launch_direct.title",
                detail: "settings.launch_direct.detail",
                isOn: $launchDirectlyToPerformance
            )
            modernDivider()
            FakeHomeScreenCard(showingPicker: $showingHomeScreenPicker)
            LockscreenInputSettingsCard()
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Data

    @ViewBuilder private var dataSection: some View {
        settingsSectionLabel("DATA & INFO", icon: "externaldrive.fill", color: Self.colorData)
        accentedSection(color: Self.colorData) {
            BackupCard(backup: backup)
            modernCard {
                VStack(spacing: 0) {
                            HStack {
                        Text("Version")
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Spacer()
                        Text(appVersionDisplay)
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            .onLongPressGesture(minimumDuration: 2.0) {
                                withAnimation { developerMode = true }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                    }
                    #if DEBUG
                    if developerMode {
                        modernDivider()
                        Button {
                            let uid = InstagramService.shared.session.userId
                            guard !uid.isEmpty else { return }
                            // 1. Borrar el flag de precarga
                            UserDefaults.standard.removeObject(forKey: "perf_fully_preloaded_\(uid)")
                            // 2. Borrar el perfil cacheado en disco (JSON)
                            ProfileCacheService.shared.clearProfile()
                            // 3. Borrar todas las imágenes cacheadas
                            ProfileCacheService.shared.clearAllImages()
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Reset first-time preload (DEBUG)")
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                        }
                        .padding(.top, 8)
                    }
                    #endif
                }
            }
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Profile Picture Card

    private var profilePictureCard: some View {
        AnyView(collapsibleCard(icon: "person.crop.circle.fill", iconColor: Self.colorProfile,
                        title: "Profile Picture", subtitle: "Change your Instagram profile photo",
                        isExpanded: $profilePicExpanded,
                        helpAction: { showProfilePicHelp = true }) {
            modernToggleRow(icon: "wand.and.stars", iconColor: Self.colorProfile,
                            title: "Auto on Performance open",
                            detail: "Uploads the latest gallery photo each time Performance opens",
                            isOn: $autoProfilePicOnPerformance)
            modernDivider()
            if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                HStack { Spacer()
                    VStack(spacing: 6) {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 80, height: 80).clipShape(Circle())
                            .overlay(Circle().stroke(VaultTheme.Colors.primary, lineWidth: 2))
                        Text("Ready to upload").font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                Spacer()
                }
            }
            if selectedImageData != nil {
                modernActionButton(title: isUploadingProfilePic ? "Uploading…" : "Upload Profile Picture",
                                   icon: "arrow.up.circle.fill",
                                   loading: isUploadingProfilePic,
                                   enabled: canUpload()) { uploadProfilePicture() }
            }
            if let msg = getCooldownMessage() { modernStatusRow(msg, color: VaultTheme.Colors.warning, icon: "clock.fill") }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            profilePicURLSchemesContent
        })
    }

    // MARK: - Note Card

    private var noteCard: some View {
        AnyView(collapsibleCard(icon: "bubble.left.fill", iconColor: Self.colorProfile,
                        title: "Note", subtitle: "Visible above your profile picture for 24h",
                        isExpanded: $noteExpanded,
                        helpAction: { showNoteHelp = true }) {
            modernToggleRow(
                icon: "power",
                iconColor: Self.colorProfile,
                title: "Enable Notes",
                detail: "When off, Notes will not send manually or from Performance inputs.",
                isOn: $noteFeatureEnabled
            )
            if !noteFeatureEnabled {
                modernStatusRow("Notes disabled", color: VaultTheme.Colors.warning, icon: "pause.circle.fill")
            }
            modernDivider()
            // ── Text field (= template) ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                TextField("Write a note… or use {text1}", text: $noteTemplate)
                    .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(VaultTheme.Spacing.md)
                    .background(Color(hex: "#2C2C2E")).cornerRadius(VaultTheme.CornerRadius.sm)
                    .disabled(isSendingNote || !noteFeatureEnabled)
                    .focused($noteFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { noteFieldFocused = false }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            if noteFieldFocused {
                                Spacer()
                                Button("Done") { noteFieldFocused = false }
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .onChange(of: noteTemplate) { if $0.count > 60 { noteTemplate = String($0.prefix(60)) } }

                // ── Insert buttons + char counter ─────────────────────────────
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["{text1}", "{text2}", "{text3}", "{text4}", "{text5}"], id: \.self) { token in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        insertTokenAtCursor(token, fallback: &noteTemplate)
                                    }
                                } label: {
                                    Text(token)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(noteTemplate.contains(token) ? Self.colorProfile : Color(hex: "#3A3A3C"))
                                        .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                                .disabled(!noteFeatureEnabled)
                                .opacity(noteFeatureEnabled ? 1.0 : 0.45)
                            }
                        }
                    }
                    Text("\(noteTemplate.count)/60")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(noteTemplate.count > 50 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
                        .padding(.leading, 8)
                }

                // ── Per-placeholder source pickers (dynamic) ──────────────────
                InlineSourcePickerView(target: "note", template: noteTemplate, accentColor: Self.colorProfile)
            }
            .disabled(!noteFeatureEnabled)
            .opacity(noteFeatureEnabled ? 1.0 : 0.45)

            modernActionButton(title: isSendingNote ? "Sending…" : "Send Note",
                               icon: "paperplane.fill", loading: isSendingNote,
                               enabled: noteFeatureEnabled && !noteTemplate.isEmpty && !isSendingNote && !instagram.isLocked && getNoteCooldownSeconds() == 0,
                               action: sendNote)
            if let msg = getDuplicateNoteWarningMessage() {
                modernStatusRow(msg, color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill")
            }
            if let msg = getNoteCooldownMessage() { modernStatusRow(msg, color: VaultTheme.Colors.warning, icon: "clock.fill") }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            urlSchemeRow(icon: "link", title: "URL Scheme",
                         detail: "Open this URL to send a note when Performance opens",
                         url: urlSchemeExample(mode: "note", template: noteTemplate))
        })
    }

    // MARK: - Biography Card

    private var biographyCard: some View {
        AnyView(collapsibleCard(icon: "text.alignleft", iconColor: Self.colorProfile,
                        title: "Biography", subtitle: "Appears on your Instagram profile page",
                        isExpanded: $bioExpanded,
                        helpAction: { showBioHelp = true }) {
            let currentBio = ProfileCacheService.shared.cachedProfile?.biography ?? ""
            modernToggleRow(
                icon: "power",
                iconColor: Self.colorProfile,
                title: "Enable Biography",
                detail: "When off, Biography will not update manually or from Performance inputs.",
                isOn: $bioFeatureEnabled
            )
            if !bioFeatureEnabled {
                modernStatusRow("Biography disabled", color: VaultTheme.Colors.warning, icon: "pause.circle.fill")
            }
            modernDivider()
            VStack(alignment: .leading, spacing: 6) {

                // ── T1 / T2 / T3 / T4 template slot selector ──────────────────
                HStack(spacing: 6) {
                    ForEach(0..<4) { idx in
                        let label = ["T1","T2","T3","T4"][idx]
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { bioActiveSlot = idx }
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(bioActiveSlot == idx ? .white : VaultTheme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(bioActiveSlot == idx ? Self.colorProfile : Color(hex: "#2C2C2E"))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!bioFeatureEnabled)
                        .opacity(bioFeatureEnabled ? 1.0 : 0.45)
                    }
                }

                // ── Text editor OR acrostic-mode banner ───────────────────────
                if bioAcrosticEnabled {
                    // When acrostic is ON the template is irrelevant — show an
                    // informational banner instead of the editable field.
                    HStack(spacing: 10) {
                        Image(systemName: "text.badge.star")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "F472B6"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Acrostic Mode active"))
                                .font(VaultTheme.Typography.captionBold())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text(String(localized: "The word received from the source below will be converted automatically into an acrostic poem."))
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(VaultTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "F472B6").opacity(0.10))
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                            .stroke(Color(hex: "F472B6").opacity(0.35), lineWidth: 1)
                    )
                } else {
                    ZStack(alignment: .topLeading) {
                        if activeBioBinding.wrappedValue.isEmpty {
                            Text(currentBio.isEmpty ? String(localized: "Write your biography…") : currentBio)
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.5))
                                .padding(.horizontal, VaultTheme.Spacing.md).padding(.vertical, VaultTheme.Spacing.md)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: activeBioBinding)
                            .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(.horizontal, VaultTheme.Spacing.sm).padding(.vertical, 4)
                            .scrollContentBackground(.hidden).background(Color.clear)
                            .focused($bioFieldFocused).disabled(isSendingBio || !bioFeatureEnabled)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    if bioFieldFocused {
                                        Spacer()
                                        Button("Done") { bioFieldFocused = false }
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .onChange(of: activeBioBinding.wrappedValue) { if $0.count > 150 { activeBioBinding.wrappedValue = String($0.prefix(150)) } }
                    }
                    .background(Color(hex: "#2C2C2E")).cornerRadius(VaultTheme.CornerRadius.sm)

                    // ── Insert buttons + char counter ──────────────────────────
                    HStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["{text1}", "{text2}", "{text3}", "{text4}", "{text5}"], id: \.self) { token in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            insertTokenAtCursor(token, fallback: &activeBioBinding.wrappedValue)
                                        }
                                    } label: {
                                        Text(token)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(bioTemplate.contains(token) ? Self.colorProfile : Color(hex: "#3A3A3C"))
                                            .cornerRadius(7)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!bioFeatureEnabled)
                                    .opacity(bioFeatureEnabled ? 1.0 : 0.45)
                                }
                            }
                        }
                        Text("\(bioTemplate.count)/150")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(bioTemplate.count > 130 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
                            .padding(.leading, 8)
                    }
                }

                // ── Per-placeholder input pickers ─────────────────────────────
                // In acrostic mode always show {text1} picker so the source
                // (API / OCR) can be configured.
                InlineSourcePickerView(
                    target: "bio",
                    template: bioAcrosticEnabled ? "{text1}" : bioTemplate,
                    accentColor: Self.colorProfile
                )

                // ── Acrostic mode toggle ───────────────────────────────────────
                acrosticToggleRow
            }
            .disabled(!bioFeatureEnabled)
            .opacity(bioFeatureEnabled ? 1.0 : 0.45)

            modernActionButton(title: isSendingBio ? "Updating…" : "Update Biography",
                               icon: "checkmark.circle.fill", loading: isSendingBio,
                               enabled: bioFeatureEnabled && (!bioTemplate.isEmpty || bioAcrosticEnabled) && !isSendingBio && !instagram.isLocked) {
                bioFieldFocused = false; sendBiography()
            }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            urlSchemeRow(icon: "link", title: "URL Scheme",
                         detail: "Open this URL to update biography when Performance opens",
                         url: urlSchemeExample(mode: "bio", template: bioTemplate))
        })
    }


    // MARK: - Acrostic Toggle Row

    private var acrosticToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.badge.star")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(bioAcrosticEnabled ? Self.colorProfile : VaultTheme.Colors.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Acrostic Mode"))
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textPrimary)

                // Live example in device language with first-letter highlight
                acrosticExampleLine
                    .font(.system(size: 11))
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $bioAcrosticEnabled)
                .toggleStyle(SwitchToggleStyle(tint: Self.colorProfile))
                .labelsHidden()
        }
        .padding(.horizontal, VaultTheme.Spacing.md)
        .padding(.vertical, VaultTheme.Spacing.sm)
        .background(Color(hex: bioAcrosticEnabled ? "#1C1C1E" : "#2C2C2E"))
        .cornerRadius(VaultTheme.CornerRadius.sm)
        .animation(.easeInOut(duration: 0.2), value: bioAcrosticEnabled)
    }

    // Builds "STAR → Stone · Tree · Arrow · River" with first letter of each word in orange
    private var acrosticExampleLine: Text {
        let exampleWord = acrosticExampleWord
        let pairs = AcrosticEngine.preview(word: exampleWord)

        var line = Text(exampleWord + " → ")
            .foregroundColor(VaultTheme.Colors.textSecondary)

        for (idx, pair) in pairs.enumerated() {
            let first  = String(pair.word.prefix(1))
            let rest   = String(pair.word.dropFirst())
            line = line
                + Text(first).foregroundColor(.orange).bold()
                + Text(rest).foregroundColor(VaultTheme.Colors.textSecondary)
            if idx < pairs.count - 1 {
                line = line + Text(" · ").foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.4))
            }
        }
        return line
    }

    // Picks a 4-letter example word that makes sense in the current language
    private var acrosticExampleWord: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "es": return "VASO"
        case "fr": return "REVE"
        case "de": return "LICHT"
        case "it": return "MARE"
        case "pt": return "ALMA"
        case "nl": return "LICHT"
        case "pl": return "NURT"
        case "ru": return "ДУША"
        case "ja": return "HANA"
        case "ko": return "MOND"
        case "hi": return "JAL"
        case "th": return "FAH"
        case "vi": return "SONG"
        default:   return "STAR"
        }
    }

    // MARK: - Section accent colors (internal so CollapsibleCard structs can reference them)
    static let colorAccount     = Color(hex: "#0A84FF")
    static let colorProfile     = Color(hex: "#FF9F0A")
    static let colorTricks      = Color(hex: "#BF5AF2")
    static let colorIntegration = Color(hex: "#FFD60A")
    static let colorData        = Color(hex: "#30D158")
    static let colorCommunity   = Color(hex: "#1877F2")

    // MARK: - Modern UI Helpers

    @ViewBuilder
    private func settingsSectionLabel(_ title: LocalizedStringKey, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .tracking(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wraps section cards with a left-side colored accent line
    @ViewBuilder
    private func accentedSection<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(color)
                .frame(width: 3)
            VStack(spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func modernCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            content()
        }
        .padding(VaultTheme.Spacing.md)
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }

    /// Card con cabecera pulsable que expande/colapsa el contenido
    @ViewBuilder
    private func collapsibleCard<Content: View>(
        icon: String, iconColor: Color, title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        isExpanded: Binding<Bool>,
        helpAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible, tap to toggle
            HStack(spacing: VaultTheme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(VaultTheme.Colors.textPrimary)
                    if let sub = subtitle {
                        Text(sub).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                }
                Spacer()
                if let helpAction = helpAction {
                    Button(action: helpAction) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded.wrappedValue)
            }
            .padding(VaultTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.wrappedValue.toggle()
                }
            }

            // Expandable content
            if isExpanded.wrappedValue {
                Divider().background(Color(hex: "#2C2C2E"))
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                    content()
                }
                                        .padding(VaultTheme.Spacing.md)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }

    @ViewBuilder
    private func modernCardHeader(icon: String, iconColor: Color, title: LocalizedStringKey) -> some View {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
            }
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(VaultTheme.Colors.textPrimary)
        }
    }

    private func modernDivider() -> some View {
        Divider().background(Color(hex: "#2C2C2E"))
    }

    @ViewBuilder
    private func modernToggleRow(icon: String, iconColor: Color, title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                Text(detail).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    @ViewBuilder
    private func modernRow<T: View>(icon: String, iconColor: Color, title: LocalizedStringKey, trailing: T) -> some View {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor)
            }
            Text(title).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
            Spacer()
            trailing
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(VaultTheme.Colors.textTertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modernActionButton(title: LocalizedStringKey, icon: String, loading: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                if loading {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: icon)
                }
                Text(title).font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(enabled ? VaultTheme.Colors.primary : VaultTheme.Colors.textDisabled)
            .cornerRadius(VaultTheme.CornerRadius.md)
        }
        .disabled(!enabled || loading)
    }

    @ViewBuilder
    private func modernStatusRow(_ message: String, color: Color, icon: String) -> some View {
                            HStack(spacing: VaultTheme.Spacing.sm) {
            Image(systemName: icon).foregroundColor(color)
            Text(message).font(VaultTheme.Typography.caption()).foregroundColor(color)
        }
    }

    // MARK: - Auto Input Picker (Off / Clipboard / API / OCR)

    @ViewBuilder
    private func autoInputPicker(
        clipboardKey: String,
        topMode: Binding<String>,
        apiSource: Binding<ApiSource>
    ) -> some View {
        let currentMode = AutoInputMode(rawValue: topMode.wrappedValue) ?? .off

                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Auto Input")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("API: polls every 2 s while Performance is active. OCR: camera recognises the word when you press the volume-up button. Sources are configured above via {text1}, {text2}, {text3}, {text4}, {text5}.")
                                                    .font(VaultTheme.Typography.caption())
                                                    .foregroundColor(VaultTheme.Colors.textSecondary)

            // ── Pill row ────────────────────────────────────────────
            HStack(spacing: 8) {
                ForEach(AutoInputMode.allCases.filter { $0 != .clipboard }, id: \.rawValue) { mode in
                    let isSelected = currentMode == mode

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            topMode.wrappedValue = mode.rawValue
                            if clipboardAutoMode == clipboardKey { clipboardAutoMode = "" }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Self.colorProfile : Color(hex: "#2C2C2E"))
                        .cornerRadius(8)
                    }
                    .contentShape(Rectangle())
                }
            }

            // ── OCR sub-panel (visible only when OCR mode is active) ─
            if currentMode == .ocr {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color(hex: "#3A3A3C"))

                    // Language picker
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 13))
                            .foregroundColor(Self.colorProfile)
                            .frame(width: 20)
                        Text("Language")
                            .font(VaultTheme.Typography.body())
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                                Button {
                                    ocrLanguage = lang.code
                                } label: {
                                    HStack {
                                        Text(lang.display)
                                        if ocrLanguage == lang.code {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(OCRConfiguration.displayName(for: ocrLanguage))
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(Self.colorProfile)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Self.colorProfile)
                            }
                        }
                    }

                    Divider().background(Color(hex: "#3A3A3C"))

                    // Camera picker
                                HStack {
                        Image(systemName: ocrCamera == 0 ? "camera.fill" : "camera.rotate.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Self.colorProfile)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Camera")
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text(ocrCamera == 0 ? "Rear camera" as LocalizedStringKey : "Front camera")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                                    Spacer()
                        HStack(spacing: 6) {
                            ForEach([(0, "Rear"), (1, "Front")], id: \.0) { val, label in
                                let sel = ocrCamera == val
                                Button { ocrCamera = val } label: {
                                    Text(LocalizedStringKey(label))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(sel ? .white : VaultTheme.Colors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(sel ? Self.colorProfile : Color(hex: "#2C2C2E"))
                                        .cornerRadius(6)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    // Info note
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        Text("Camera activates silently in background when Performance opens. Vibrates once on recognition.")
                                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .padding(8)
                    .background(Color(hex: "#2C2C2E"))
                    .cornerRadius(8)
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

        }
    }

    // NOTE: Extracted to a standalone View struct to avoid SwiftUI type-complexity
    // stack overflow that occurs when deeply-nested @ViewBuilder closures accumulate
    // too many generic TupleView layers inside a single body computation.
    // See: InlineSourcePickerView below SettingsView.

    private func apiSourceRow(target: String, source: Binding<ApiSource>, onSelect: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Magic API source")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Polls every 2 s while Performance is active. Detects the spectator's selection as soon as they submit it.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(ApiSource.allCases.filter { !$0.isInterfaceInput || $0 == .ocr }, id: \.rawValue) { apiSource in
                    Button {
                        source.wrappedValue = apiSource
                        if apiSource != .none { onSelect() }
                    } label: {
                        Text(apiSource == .none ? "Off" : apiSource.displayName.replacingOccurrences(of: "Custom API ", with: "API "))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(source.wrappedValue == apiSource ? .white : VaultTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(source.wrappedValue == apiSource ? VaultTheme.Colors.primary : Color(hex: "#2C2C2E"))
                            .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    private func fetchLatestFollower() {
        // ANTI-BOT: Defer this manual fetch when any heavy operation is in
        // flight (upload, sync/archive, reveal). Surfacing it as part of a
        // burst is exactly what got us a 401 last time. The user sees a brief
        // alert instead of failing silently.
        if instagram.isHeavyOperationActive {
            uploadMessage = "An upload or sync is in progress. Try again in a moment."
            showingUploadAlert = true
            LogManager.shared.warning("Fetch latest follower deferred — heavy op active", category: .general)
            return
        }
        isLoadingFollower = true
        
        Task {
            do {
                let follower = try await instagram.getLatestFollower()
                
                var fullInfo: [String: Any]?
                if let follower = follower {
                    fullInfo = try await instagram.getUserFullInfo(userId: follower.userId)
                }
                
                await MainActor.run {
                    latestFollower = follower
                    followerFullInfo = fullInfo
                    showingFollowerData = true
                    isLoadingFollower = false
                }
            } catch {
                print("❌ Error fetching follower: \(error)")
                await MainActor.run {
                    isLoadingFollower = false
                }
            }
        }
    }
    
    // MARK: - URL Scheme Helper Views

    @ViewBuilder
    private var profilePicURLSchemesContent: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(VaultTheme.Colors.primary)
                Text("URL Schemes")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            Text("Use these URLs in iOS Shortcuts to update your profile picture automatically when Performance opens.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            urlSchemeRow(
                icon:   "photo.on.rectangle",
                title:  "Last gallery photo",
                detail: "Uploads the most recent photo from your camera roll",
                url:    URLActionManager.profilePicLastURL
            )
            Divider()
            profilePicBase64Row
        }
    }

    @ViewBuilder
    private var profilePicBase64Row: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(VaultTheme.Colors.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base64 from external app")
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Another app sends the image as base64. Vault handles resize and compression automatically.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = "vault://profilepic?data=<base64>"
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Copy")
                    }
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            Text("vault://profilepic?data=<base64>")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .padding(.horizontal, VaultTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(VaultTheme.Colors.backgroundSecondary)
                .cornerRadius(VaultTheme.CornerRadius.sm)
        }
    }

    @ViewBuilder
    private func urlSchemeRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey, url: String) -> some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(VaultTheme.Colors.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text(detail)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Copy")
                    }
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            Text(url)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .lineLimit(2)
                .padding(.horizontal, VaultTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(VaultTheme.Colors.backgroundSecondary)
                .cornerRadius(VaultTheme.CornerRadius.sm)
        }
    }
    
    // MARK: - Profile Picture Upload Helpers
    
    private func canUpload() -> Bool {
        // Check all anti-bot conditions
        guard selectedImageData != nil else { return false }
        guard !uploadManager.isActive && !uploadManager.isSyncArchiveActive else { return false }
        guard !instagram.isLocked else { return false }
        guard !instagram.isNetworkStabilizing else { return false }
        
        let (onCooldown, _) = instagram.isProfilePicOnCooldown()
        guard !onCooldown else { return false }
        
        return true
    }
    
    private func getCooldownMessage() -> String? {
        let (onCooldown, remaining) = instagram.isProfilePicOnCooldown()
        if onCooldown {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return "Wait \(minutes)m \(seconds)s before next upload"
        }
        return nil
    }
    
    // MARK: - Instagram Notes Helpers
    
    private func getNoteCooldownSeconds() -> Int {
        let cooldown = instagram.isNoteOnCooldown()
        return cooldown.onCooldown ? cooldown.remainingSeconds : 0
    }
    
    private func getNoteCooldownMessage() -> String? {
        let remaining = getNoteCooldownSeconds()
        if remaining > 0 {
            return "Wait \(remaining)s before next note"
        }
        return nil
    }

    private func getDuplicateNoteWarningMessage() -> String? {
        guard UserDefaults.standard.string(forKey: "note_duplicate_warning_text") != nil else {
            return nil
        }
        return "Duplicate note blocked. Change at least one word before sending again."
    }
    
    private func sendNote() {
        guard noteFeatureEnabled else {
            noteMessage = "Notes are disabled. Enable Notes before sending."
            showingNoteAlert = true
            return
        }
        guard !noteTemplate.isEmpty else { return }
        guard !uploadManager.isActive && !uploadManager.isSyncArchiveActive else {
            noteMessage = uploadWriteBlockedMessage
            showingNoteAlert = true
            return
        }

        isSendingNote = true
        let rawTemplate = noteTemplate

        Task {
            do {
                // Resolve {text1}/{text2}/{text3}/{text4}/{text5} from configured sources before sending
                var resolved = rawTemplate
                let hasTokens = resolved.contains("{text1}") || resolved.contains("{text2}") || resolved.contains("{text3}") || resolved.contains("{text4}") || resolved.contains("{text5}") || resolved.contains("{word}")
                if hasTokens {
                    let values = await IntegrationsSettings.shared.fetchTemplatePlaceholders(for: "note")
                    if !values.isEmpty {
                        if let v1 = values["text1"] {
                            resolved = resolved.replacingOccurrences(of: "{word}", with: v1)
                                               .replacingOccurrences(of: "{text1}", with: v1)
                        }
                        if let v2 = values["text2"] { resolved = resolved.replacingOccurrences(of: "{text2}", with: v2) }
                        if let v3 = values["text3"] { resolved = resolved.replacingOccurrences(of: "{text3}", with: v3) }
                        if let v4 = values["text4"] { resolved = resolved.replacingOccurrences(of: "{text4}", with: v4) }
                        if let v5 = values["text5"] { resolved = resolved.replacingOccurrences(of: "{text5}", with: v5) }
                    }
                }
                let textToSend = String(resolved.prefix(60))
                let success = try await instagram.createNote(text: textToSend, userInitiated: true)

                await MainActor.run {
                    isSendingNote = false
                    if success {
                        UserDefaults.standard.set(Date(), forKey: "last_note_sent_date")
                        noteMessage = "✅ Note sent!\n\nYour note \"\(textToSend)\" is now visible above your profile picture in DMs for 24 hours."
                        showingNoteAlert = true
                        // Don't clear noteTemplate — it's a reusable template
                    }
                }
            } catch {
                await MainActor.run {
                    isSendingNote = false
                    noteMessage = "❌ Failed to send note\n\n\(error.localizedDescription)"
                    showingNoteAlert = true
                }
            }
        }
    }
    
    // MARK: - Biography

    /// Builds a vault:// URL example based on which {textN} tokens are present in the template.
    private func urlSchemeExample(mode: String, template: String) -> String {
        let usesText1 = template.contains("{text1}") || template.contains("{word}")
        let usesText2 = template.contains("{text2}")
        let usesText3 = template.contains("{text3}")
        let usesText4 = template.contains("{text4}")
        let usesText5 = template.contains("{text5}")
        var params: [String] = []
        if usesText1 || (!usesText2 && !usesText3 && !usesText4 && !usesText5) { params.append("text1=<value>") }
        if usesText2 { params.append("text2=<value>") }
        if usesText3 { params.append("text3=<value>") }
        if usesText4 { params.append("text4=<value>") }
        if usesText5 { params.append("text5=<value>") }
        return "vault://\(mode)?\(params.joined(separator: "&"))"
    }

    private func sendBiography() {
        guard bioFeatureEnabled else {
            bioMessage = "Biography is disabled. Enable Biography before updating."
            showingBioAlert = true
            return
        }
        guard !bioTemplate.isEmpty else { return }
        guard !uploadManager.isActive && !uploadManager.isSyncArchiveActive else {
            bioMessage = uploadWriteBlockedMessage
            showingBioAlert = true
            return
        }
        isSendingBio = true
        let rawTemplate = bioTemplate

        Task {
            do {
                // Resolve {text1}/{text2}/{text3}/{text4}/{text5} from configured sources before sending
                var resolved = rawTemplate
                let hasTokens = resolved.contains("{text1}") || resolved.contains("{text2}") || resolved.contains("{text3}") || resolved.contains("{text4}") || resolved.contains("{text5}") || resolved.contains("{word}")
                if hasTokens {
                    let values = await IntegrationsSettings.shared.fetchTemplatePlaceholders(for: "bio")
                    if !values.isEmpty {
                        if let v1 = values["text1"] {
                            resolved = resolved.replacingOccurrences(of: "{word}", with: v1)
                                               .replacingOccurrences(of: "{text1}", with: v1)
                        }
                        if let v2 = values["text2"] { resolved = resolved.replacingOccurrences(of: "{text2}", with: v2) }
                        if let v3 = values["text3"] { resolved = resolved.replacingOccurrences(of: "{text3}", with: v3) }
                        if let v4 = values["text4"] { resolved = resolved.replacingOccurrences(of: "{text4}", with: v4) }
                        if let v5 = values["text5"] { resolved = resolved.replacingOccurrences(of: "{text5}", with: v5) }
                    }
                    // Expand \n escapes
                    resolved = resolved.replacingOccurrences(of: "\\n", with: "\n")
                }

                // ── Acrostic transformation ────────────────────────────────────
                // When acrostic mode is on and the resolved text is a single word
                // (letters only, no spaces), convert it to an acrostic poem.
                if bioAcrosticEnabled {
                    let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isWord = !trimmed.isEmpty && trimmed.rangeOfCharacter(from: .whitespaces) == nil
                    if isWord, let poem = AcrosticEngine.build(word: trimmed) {
                        resolved = poem
                    }
                }

                let textToSend = String(resolved.prefix(150))
                let success = try await instagram.changeBiography(text: textToSend, userInitiated: true)
                await MainActor.run {
                    isSendingBio = false
                    if success {
                        bioMessage = "✅ Biography updated!\n\nYour Instagram profile now shows:\n\"\(textToSend)\""
                        showingBioAlert = true
                        // Don't clear bioTemplate — it's a reusable template
                    }
                }
            } catch {
                await MainActor.run {
                    isSendingBio = false
                    bioMessage = "❌ Failed to update biography\n\n\(error.localizedDescription)"
                    showingBioAlert = true
                }
            }
        }
    }

    private var uploadWriteBlockedMessage: String {
        "Temporarily disabled while a set is uploading.\n\nFinish, pause, or cancel the active upload before sending Notes, Biography, or Profile Picture changes."
    }
    
    // MARK: - Profile Picture Upload
    
    private func uploadProfilePicture() {
        guard let imageData = selectedImageData else { return }
        guard !uploadManager.isActive && !uploadManager.isSyncArchiveActive else {
            uploadMessage = uploadWriteBlockedMessage
            showingUploadAlert = true
            return
        }
        
        isUploadingProfilePic = true
        
        Task {
            do {
                print("🖼️ [UI] Starting profile picture upload...")
                
                // Upload with all anti-bot protections
                let success = try await instagram.changeProfilePicture(imageData: imageData, userInitiated: true)
                
                await MainActor.run {
                    isUploadingProfilePic = false
                    
                    if success {
                        // Show new profile pic instantly in the fake Instagram view —
                        // no need to wait for Instagram's CDN URL from the next refresh.
                        if let image = UIImage(data: imageData) {
                            ProfileCacheService.shared.pendingProfilePic = image
                            print("⚡️ [UI] Profile pic override set — will appear instantly in Performance view")
                        }
                        uploadMessage = "✅ Profile picture updated successfully!\n\nYour Instagram profile picture has been changed. Wait 5 minutes before changing again."
                        showingUploadAlert = true
                        selectedImageData = nil // Clear selection
                    } else {
                        uploadMessage = "❌ Upload failed. Please try again later."
                        showingUploadAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isUploadingProfilePic = false
                    
                    let errorMessage = error.localizedDescription
                    if errorMessage.contains("already your profile picture") {
                        uploadMessage = "⚠️ This is already your profile picture.\n\nPlease select a different image."
                    } else if errorMessage.contains("Lockdown") {
                        uploadMessage = "🚨 Lockdown active\n\nInstagram detected unusual activity. Wait for lockdown to clear before uploading."
                    } else if errorMessage.contains("cooldown") || errorMessage.contains("Wait") {
                        uploadMessage = "⏱️ Please wait\n\n\(errorMessage)"
                    } else {
                        uploadMessage = "❌ Upload failed\n\n\(errorMessage)"
                    }
                    showingUploadAlert = true
                }
            }
        }
    }
    
}

// MARK: - Inline Source Picker
// Shows per-placeholder source pickers (Inject / API1 / API2 / API3 / OCR)
// only for the tokens that are actually present in the template text.

private struct InlineSourcePickerView: View {
    let target: String
    let template: String
    let accentColor: Color
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @AppStorage("ocr_language") private var ocrLanguage: String = "es-ES"
    @AppStorage("ocr_camera")   private var ocrCamera:   Int    = 0
    @State private var blockedSource: ApiSource? = nil
    @State private var blockedToken: String = "{text1}"
    @State private var showBlockedInputAlert = false

    private let allTokens = ["{text1}", "{text2}", "{text3}", "{text4}", "{text5}"]

    private var visibleTokens: [String] {
        var t = allTokens.filter { template.contains($0) }
        if template.contains("{word}") && !t.contains("{text1}") { t.insert("{text1}", at: 0) }
        return t
    }

    private var hasOCRSlot: Bool {
        integrations.ocrSlot(for: target) != nil
    }

    private func sourceBinding(for token: String) -> Binding<ApiSource> {
        switch token {
        case "{text2}": return target == "note" ? $integrations.noteText2Source : $integrations.bioText2Source
        case "{text3}": return target == "note" ? $integrations.noteText3Source : $integrations.bioText3Source
        case "{text4}": return target == "note" ? $integrations.noteText4Source : $integrations.bioText4Source
        case "{text5}": return target == "note" ? $integrations.noteText5Source : $integrations.bioText5Source
        default:        return target == "note" ? $integrations.noteText1Source : $integrations.bioText1Source
        }
    }

    private func blockedInputMessage(source: ApiSource, token: String) -> String {
        let locations = integrations.conflictLocations(excludingTarget: target, excludingToken: token)
        let list = locations.isEmpty ? "another active input" : locations.joined(separator: "\n")
        return "\(source.displayName) cannot be used together with the currently active physical input:\n\n\(list)\n\nUse this input and deactivate the conflicting selection?"
    }

    /// SF Symbol for interface-family sources (camera / lockscreen / clock). nil for API/none.
    static func sourceIcon(_ src: ApiSource) -> String? {
        switch src {
        case .ocr:              return "camera.viewfinder"
        case .numberLockscreen: return "lock.fill"
        case .cardLockscreen:   return "lock.rectangle.stack.fill"
        case .numberClock:      return "hand.draw.fill"
        case .cardClock:        return "clock.fill"
        case .cardNumpad:       return "rectangle.grid.3x2.fill"
        default:                return nil
        }
    }

    @ViewBuilder
    private func inputHintBanner(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .cornerRadius(8)
    }

    var body: some View {
        if !visibleTokens.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider().background(Color(hex: "#3A3A3C"))
                Text("INPUTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                // ── Per-token source dropdowns ────────────────────────────────
                ForEach(visibleTokens, id: \.self) { token in
                    let label = (token == "{text1}" && template.contains("{word}") && !template.contains("{text1}"))
                        ? "{word}" : token
                    let binding = sourceBinding(for: token)
                    let currentSrc = binding.wrappedValue

                    HStack(spacing: 10) {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accentColor)
                            .frame(width: 62, alignment: .leading)

                        Menu {
                            Button {
                                withAnimation { binding.wrappedValue = .none }
                            } label: {
                                HStack {
                                    Text("None")
                                    if currentSrc == .none { Image(systemName: "checkmark") }
                                }
                            }
                            Divider()
                            ForEach(ApiSource.allCases.filter { $0 != .none }, id: \.rawValue) { src in
                                let isConflict = !integrations.canSelectSource(src, target: target, token: token)
                                Button {
                                    if isConflict {
                                        blockedSource = src
                                        blockedToken = token
                                        showBlockedInputAlert = true
                                    } else {
                                        withAnimation { binding.wrappedValue = src }
                                    }
                                } label: {
                                    HStack {
                                        if let icon = Self.sourceIcon(src) {
                                            Label(src.displayName, systemImage: icon)
                                        } else {
                                            Text(src.displayName)
                                        }
                                        if currentSrc == src { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if let icon = Self.sourceIcon(currentSrc) {
                                    Image(systemName: icon)
                                        .font(.system(size: 13))
                                }
                                Text(currentSrc == .none ? "No source" : currentSrc.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(currentSrc == .none ? VaultTheme.Colors.textSecondary : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(currentSrc == .none ? Color(hex: "#2C2C2E") : accentColor.opacity(0.85))
                            .cornerRadius(8)
                        }
                    }
                }

                // ── Context banners for interface-based inputs ───────────────
                let usedKinds = integrations.interfaceKindsInUse()

                // OCR: remind user how to trigger
                if usedKinds.contains(.ocr) {
                    inputHintBanner(icon: "camera.viewfinder", color: Color(hex: "A78BFA"),
                                    text: "OCR is active. Press the Volume Up button in Performance to start the camera. The recognised text will be sent automatically.")
                }

                // Card Clock / Card Lockscreen: explain the capture and the localized output
                if usedKinds.contains(.cardClock) {
                    inputHintBanner(icon: "clock.fill", color: Color(hex: "FF9F0A"),
                                    text: "Card Clock shows a black screen in Performance. 2 swipes for value (A=↑→ … 9=←← 10=←↑ J=↑← Q=↑↑ K=↑↓) + 1 swipe for suit (↑=♠ →=♥ ↓=♣ ←=♦). Stop swiping for 3 seconds to confirm; the black screen stays until you tap anywhere. The card name (e.g. \"3 of hearts\") fills this placeholder, and an active card set unarchives that card automatically.")
                }
                if usedKinds.contains(.cardNumpad) {
                    inputHintBanner(icon: "rectangle.grid.3x2.fill", color: Color(hex: "16A34A"),
                                    text: "Numpad Card starts as a black screen in Performance. Tap anywhere to reveal the card pad, choose a value and a suit, then the pad disappears. The localized card name fills this placeholder, and an active card set unarchives that card automatically.")
                }
                if usedKinds.contains(.cardLockscreen) {
                    inputHintBanner(icon: "lock.rectangle.stack.fill", color: Color(hex: "FF9F0A"),
                                    text: "Card Lockscreen shows the fake lock screen in Performance. Enter the card code (0 + value + suit). The card name fills this placeholder, and an active card set unarchives that card automatically.")
                }

                // ── OCR settings (visible only when any slot uses OCR) ───────
                if hasOCRSlot {
                    Divider().background(Color(hex: "#3A3A3C"))
                    Text("OCR SETTINGS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                    HStack(spacing: 10) {
                        // Language picker
                        Menu {
                            ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                                Button {
                                    ocrLanguage = lang.code
                                } label: {
                                    HStack {
                                        Text(lang.display)
                                        if ocrLanguage == lang.code { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe").font(.system(size: 11))
                                Text(OCRConfiguration.displayName(for: ocrLanguage))
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(7)
                        }
                        // Camera toggle
                        HStack(spacing: 4) {
                            ForEach([(0, "Rear"), (1, "Front")], id: \.0) { val, label in
                                Button {
                                    ocrCamera = val
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: val == 0 ? "camera.fill" : "camera.rotate.fill")
                                            .font(.system(size: 10))
                                        Text(label)
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(ocrCamera == val ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(ocrCamera == val ? accentColor : Color(hex: "#2C2C2E"))
                                    .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        Text("Press volume UP to recognise. Camera runs silently in background.")
                            .font(.system(size: 11))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
            .alert("Input conflict", isPresented: $showBlockedInputAlert) {
                Button("Cancel", role: .cancel) { blockedSource = nil }
                Button("Use this input") {
                    if let source = blockedSource {
                        integrations.resolveConflictAndSet(source: source, target: target, token: blockedToken)
                    }
                    blockedSource = nil
                }
            } message: {
                if let source = blockedSource {
                    Text(blockedInputMessage(source: source, token: blockedToken))
                } else {
                    Text("This input conflicts with another physical input.")
                }
            }
        }
    }
}

// MARK: - Follower Data Sheet

struct FollowerDataSheet: View {
    let follower: InstagramFollower?
    let fullInfo: [String: Any]?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                if let follower = follower {
                    VStack(spacing: 24) {
                        // Profile Picture
                        if let picURL = follower.profilePicURL,
                           let url = URL(string: picURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: 3))
                        }
                        
                        // User Info
                        VStack(spacing: 12) {
                            Text("@\(follower.username)")
                                .font(.title2.bold())
                            
                            if !follower.fullName.isEmpty {
                                Text(follower.fullName)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Stats (si tenemos fullInfo)
                        if let info = fullInfo {
                            let posts = InstagramService.robustInt(info["media_count"])
                            let followers = InstagramService.robustInt(info["follower_count"])
                            let following = InstagramService.robustInt(info["following_count"])
                            HStack(spacing: 20) {
                                    StatBadge(label: "Posts", value: "\(posts)")
                                    StatBadge(label: "Followers", value: formatCount(followers))
                                    StatBadge(label: "Following", value: formatCount(following))
                            }
                            .padding(.horizontal)
                        }
                        
                        // Bio (si existe)
                        if let info = fullInfo,
                           let bio = info["biography"] as? String,
                           !bio.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Bio")
                                    .font(.headline)
                                
                                Text(bio)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        
                        // Data Cards
                        VStack(alignment: .leading, spacing: 16) {
                            DataRow(label: "User ID", value: follower.userId)
                            DataRow(label: "Username", value: "@\(follower.username)")
                            DataRow(label: "Full Name", value: follower.fullName.isEmpty ? "N/A" : follower.fullName)
                            
                            // Datos adicionales de fullInfo
                            if let info = fullInfo {
                                if let isVerified = info["is_verified"] as? Bool {
                                    DataRow(label: "Verified", value: isVerified ? "✓ Yes" : "✗ No")
                                }
                                if let isPrivate = info["is_private"] as? Bool {
                                    DataRow(label: "Private Account", value: isPrivate ? "✓ Yes" : "✗ No")
                                }
                                if let externalURL = info["external_url"] as? String, !externalURL.isEmpty {
                                    DataRow(label: "Website", value: externalURL)
                                }
                            }
                            
                            if let picURL = follower.profilePicURL {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Profile Picture URL")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Text(picURL)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .textSelection(.enabled)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Preview Comment
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comment Preview")
                                .font(.headline)
                            
                            Text("\(follower.fullName.isEmpty ? follower.username : follower.fullName), this was written for you")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(10)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No follower data")
                            .font(.headline)
                        
                        Text("Unable to fetch latest follower")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Latest Follower")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.purple)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 12)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Reusable Collapsible Card Shell

struct CollapsibleCard<Content: View, Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var badge: String? = nil          // Optional inline badge next to the title
    var badgeColor: Color = .yellow   // Badge accent color
    @Binding var isExpanded: Bool
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(icon: String, iconColor: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey,
         badge: String? = nil, badgeColor: Color = .yellow,
         isExpanded: Binding<Bool>,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeColor = badgeColor
        self._isExpanded = isExpanded
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
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
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                trailing()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
            }
            .padding(VaultTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider().background(Color(hex: "#2C2C2E"))
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                    content()
                }
                .padding(VaultTheme.Spacing.md)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }
}

// MARK: - Force Reel Settings Card

// MARK: - Force Post Settings Card

struct ForcePostSettingsCard: View {
    @ObservedObject private var settings = ForcePostSettings.shared
    @State private var showingPicker = false
    @State private var showingHelp   = false
    @State private var editingUserId: String? = nil   // nil = new entry
    @State private var isExpanded = false

    var body: some View {
        Group {
        CollapsibleCard(icon: "hand.point.up.left.fill", iconColor: SettingsView.colorTricks,
                        title: "Force Post",
                        subtitle: "Force a scroll to stop on a specific post",
                        isExpanded: $isExpanded,
                        trailing: {
                            Button(action: { showingHelp = true }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                        }) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
                }

            Text("Pre-select a post from any profile. When visiting that profile in Performance, the scroll always stops on the forced image. Add multiple profiles to force different posts per profile.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                // List of existing entries
                ForEach(settings.entries) { entry in
                    entryRow(entry: entry)
                    if entry.id != settings.entries.last?.id {
                        Divider().padding(.vertical, 4)
                    }
                }

                // Add button
                Button(action: {
                    editingUserId = nil
                    showingPicker = true
                }) {
                    Label(settings.entries.isEmpty ? "Select Post" : "Add Another Profile",
                          systemImage: settings.entries.isEmpty ? "photo.on.rectangle.angled" : "plus.circle.fill")
                        .font(VaultTheme.Typography.body())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VaultTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        }
        .sheet(isPresented: $showingPicker) {
            ForcePostPickerView(editingUserId: editingUserId)
        }
        .sheet(isPresented: $showingHelp) {
            ForcePostHelpView(onClose: { showingHelp = false })
        }
    }

    @ViewBuilder
    private func entryRow(entry: ForcedPostEntry) -> some View {
                        HStack(spacing: VaultTheme.Spacing.md) {
            // Thumbnail
            if let img = settings.thumbnail(forUserId: entry.userId) {
                                    Image(uiImage: img)
                                        .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 54, height: 54)
                                        .clipped()
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 54, height: 54)
                    .overlay(ProgressView().scaleEffect(0.6))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("@\(entry.username)")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text("ID: \(String(entry.mediaId.prefix(14)))…")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }

                            Spacer()

            VStack(spacing: 6) {
                Button(action: {
                    editingUserId = entry.userId
                    showingPicker = true
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                            }
                            .buttonStyle(.bordered)

                Button(role: .destructive, action: { settings.clearEntry(userId: entry.userId) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
        }
    }
}

struct ForceReelSettingsCard: View {
    @ObservedObject private var settings = ForceReelSettings.shared
    @State private var showingPicker = false
    @State private var showingHelp   = false
    @State private var editingSlotIndex: Int = 0
    @State private var isExpanded = false

    var body: some View {
        CollapsibleCard(icon: "square.grid.2x2", iconColor: SettingsView.colorTricks,
                        title: "force_reel.title",
                        subtitle: "force_reel.subtitle",
                        isExpanded: $isExpanded,
                        trailing: {
                            Button(action: { showingHelp = true }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                        }) {
            HStack {
                Text("settings.enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
            }

            Text("force_reel.description")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            if settings.isEnabled {
                Divider()

                if let slot = settings.slots.first(where: \.hasReel) {
                    slotPreview(slot: slot)
                    } else {
                    Button(action: {
                        editingSlotIndex = 0
                        showingPicker = true
                    }) {
                        Label(String(localized: "force_reel.select_reel"),
                              systemImage: "play.rectangle.on.rectangle.fill")
                                .font(VaultTheme.Typography.body())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, VaultTheme.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ForceReelPickerView(slotIndex: editingSlotIndex)
        }
        .sheet(isPresented: $showingHelp) {
            ForceReelHelpView(onClose: { showingHelp = false })
        }
    }

    @ViewBuilder
    private func slotPreview(slot: ForceReelSlot) -> some View {
        HStack(spacing: VaultTheme.Spacing.md) {
            ZStack(alignment: .bottomLeading) {
                if let img = settings.thumbnailImages[slot.id] {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(4/5, contentMode: .fill)
                        .frame(width: 54, height: 68)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 54, height: 68)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .padding(3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(slot.sourceUsername)")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                if settings.downloadingVideo[slot.id] == true {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("force_reel.downloading")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else if settings.videoReady[slot.id] != true {
                    // Download never completed — CDN URL may have expired.
                    // Warn the magician to re-select the reel before the show.
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text(String(localized: "force_reel.video_missing"))
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Button(action: {
                    editingSlotIndex = slot.id
                    showingPicker = true
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: { settings.clearSlot(slot.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

// MARK: - Force Number Reveal Settings Card

struct ForceNumberRevealSettingsCard: View {
    @State private var showingHelp = false

    var body: some View {
        VaultCard {
            VStack(spacing: VaultTheme.Spacing.md) {

                // ── Header ───────────────────────────────────────────
                HStack(spacing: VaultTheme.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SettingsView.colorTricks)
                            .frame(width: 32, height: 32)
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post Prediction")
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Text("Unarchive photos from the active set to reveal a prediction")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    Spacer()
                    Button { showingHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // ── Go to Sets hint ───────────────────────────────────
                HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SettingsView.colorTricks)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "postpred.goto_sets.title"))
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Text(String(localized: "postpred.goto_sets.body"))
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            PostPredictionHelpView(onClose: { showingHelp = false })
        }
    }
}

// MARK: - Post Prediction Sub-Views
// Extracted as standalone View structs to keep ForceNumberRevealSettingsCard's
// body type-graph shallow and prevent SwiftUI TupleView stack overflows.

// MARK: - PostPredictionInputModeView (Off / API / OCR — unified, mutually exclusive)

private struct PostPredictionInputModeView: View {
    @ObservedObject var settings: ForceNumberRevealSettings
    @Binding var ppTopInputMode: String
    @Binding var apiSource: ApiSource
    @Binding var ocrCamera: Int
    @Binding var ocrLanguage: String
    let activeWordSet: PhotoSet?
    let activeNumberSet: PhotoSet?

    private var currentMode: AutoInputMode {
        AutoInputMode(rawValue: ppTopInputMode) ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Auto Input")
                .font(VaultTheme.Typography.bodyBold())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Choose one input method. Open Performance first, then ask the spectator to make their selection.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            // ── Off / API / OCR / Swipe pills ────────────────────────
            HStack(spacing: 8) {
                ForEach([AutoInputMode.off, AutoInputMode.api, AutoInputMode.ocr, AutoInputMode.clockInput], id: \.rawValue) { mode in
                    let isSelected = currentMode == mode
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            ppTopInputMode = mode.rawValue
                            settings.ocrEnabled = (mode == .ocr)
                            if mode != .api { apiSource = .none }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                        .cornerRadius(8)
                    }
                    .contentShape(Rectangle())
                }
            }

            // ── API source sub-picker ─────────────────────────────────
            if currentMode == .api {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().background(Color(hex: "#3A3A3C"))
                    Text("API Source")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                    Text("Polls every 2 s while Performance is active. Reveals automatically when a new word arrives.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(ApiSource.allCases.filter { $0 != .none && !$0.isInterfaceInput }, id: \.rawValue) { src in
                            let isActive = apiSource == src
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    apiSource = isActive ? .none : src
                                }
                            } label: {
                                Text(src.displayName.replacingOccurrences(of: "Custom API ", with: "API "))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isActive ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isActive ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                                    .cornerRadius(6)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal:   .opacity.combined(with: .move(edge: .top))
                ))
            }

            // ── OCR sub-panel ─────────────────────────────────────────
            if currentMode == .ocr {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color(hex: "#3A3A3C"))
                    Text("Camera starts silently when Performance opens. Recognized text auto-reveals: letters → word set, digits → number set.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)

                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "text.cursor")
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Word set: \(activeWordSet?.name ?? "None selected")")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(activeWordSet != nil ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.warning)
                            Text("Number set: \(activeNumberSet?.name ?? "None selected")")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(activeNumberSet != nil ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.warning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Camera")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .textCase(.uppercase)
                        HStack(spacing: 6) {
                            ForEach([0, 1], id: \.self) { val in
                                let sel = ocrCamera == val
                                Button { ocrCamera = val } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: val == 0 ? "camera.fill" : "camera.rotate.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(val == 0 ? "Rear" as LocalizedStringKey : "Front")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(sel ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(sel ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                                    .cornerRadius(8)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Language")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .textCase(.uppercase)
                        Menu {
                            ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                                Button { ocrLanguage = lang.code } label: {
                                    if ocrLanguage == lang.code {
                                        Label(lang.display, systemImage: "checkmark")
                                    } else {
                                        Text(lang.display)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "globe").font(.system(size: 12))
                                Text(OCRConfiguration.displayName(for: ocrLanguage))
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                            }
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal:   .opacity.combined(with: .move(edge: .top))
                ))
            }

            // ── Clock Input sub-panel ─────────────────────────────────
            if currentMode == .clockInput {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(Color(hex: "#3A3A3C"))
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 14))
                            .foregroundColor(SettingsView.colorTricks)
                        Text("Black Screen Swipe Input")
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                    }
                    Text("When Performance opens, the screen goes completely black — simulating the phone is off. Enter a 2-digit number (01–99) or 100 using directional swipes. Each digit needs 2 swipes:")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: 3) {
                        let table: [(String, String)] = [
                            ("0", "↑↑"), ("1", "↑→"), ("2", "→↑"), ("3", "→→"), ("4", "→↓"),
                            ("5", "↓→"), ("6", "↓↓"), ("7", "↓←"), ("8", "←↓"), ("9", "←←")
                        ]
                        let rows = stride(from: 0, to: table.count, by: 5).map {
                            Array(table[$0..<min($0 + 5, table.count)])
                        }
                        ForEach(rows.indices, id: \.self) { ri in
                            HStack(spacing: 4) {
                                ForEach(rows[ri].indices, id: \.self) { ci in
                                    let pair = rows[ri][ci]
                                    Text("\(pair.0):\(pair.1)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color(hex: "#2C2C2E"))
                                        .cornerRadius(5)
                                }
                            }
                        }
                    }

                    Text("Example: to reveal #5, swipe ↓→ for digit 0, then ↓→ for digit 5 (\"05\" = 4 swipes total). For 100: ↑→ (1) + ↑↑ (0) + ↑↑ (0) = 6 swipes.\n\nAfter a successful reveal, long-press (1 s) to dismiss and see the updated fake Instagram.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal:   .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
    }
}

private struct PostPredictionActiveSetView: View {
    let activeNumberSet: PhotoSet?
    let activeWordSet: PhotoSet?

    var body: some View {
        VStack(spacing: VaultTheme.Spacing.sm) {
                    if let set = activeNumberSet {
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(VaultTheme.Colors.success)
                            VStack(alignment: .leading, spacing: 2) {
                        Text("Active number set: \(set.name)")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("\(set.banks.count) banks · \(set.totalPhotos) photos")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                    } else {
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(VaultTheme.Colors.warning)
                            Text("No active number set selected. Go to your sets and mark one as active.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
            if let set = activeWordSet {
                    HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(VaultTheme.Colors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active word set: \(set.name)")
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Text("\(set.banks.count) banks · \(set.totalPhotos) photos")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                        Spacer()
                }
            }
        }
    }
}

/// Shows only the name of the single globally-active set (new architecture).
private struct PostPredictionCoverTypingView: View {
    @ObservedObject var secretSettings: SecretInputSettings
    let coverTypingPreview: String

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            HStack {
                Text("Cover Typing")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $secretSettings.isEnabled).labelsHidden()
            }
            Text("Masks what you type in Explore so spectators see a different word. Pressing SPACE triggers the word reveal.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)

            if secretSettings.isEnabled {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                    Text("Mask Mode")
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    ForEach(MaskInputMode.allCases, id: \.self) { mode in
                        let selected = secretSettings.mode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { secretSettings.mode = mode }
                        } label: {
                            HStack(spacing: VaultTheme.Spacing.md) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected ? VaultTheme.Colors.primary : VaultTheme.Colors.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Text(mode.rawValue)
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if secretSettings.mode == .customUsername {
                        TextField("Custom username", text: $secretSettings.customUsername)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(VaultTheme.Spacing.md)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    HStack(spacing: 4) {
                        Text("Preview:")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                        Text("\"car\" → \"\(coverTypingPreview)\"")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.primary)
                    }
                                        }
                                    }
                                }
                            }
                        }


private struct PostPredictionURLSchemeView: View {
    private let templateURL = "vault://reveal?word=<your word>"

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "link")
                    .foregroundColor(VaultTheme.Colors.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL Scheme")
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Open this URL to trigger a reveal directly when Performance opens")
                        .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                                Spacer()
                Button {
                    UIPasteboard.general.string = templateURL
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Copy")
                                }
                                .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            Text(templateURL)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .lineLimit(2)
                .padding(.horizontal, VaultTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(VaultTheme.Colors.backgroundSecondary)
                .cornerRadius(VaultTheme.CornerRadius.sm)
        }
    }
}

// MARK: - Counter Glitch Effect Settings Card

struct FollowingMagicSettingsCard: View {
    @ObservedObject private var settings = FollowingMagicSettings.shared
    @State private var isExpanded = false
    @State private var showingHelp = false

    var body: some View {
        Group {
        CollapsibleCard(icon: "person.2.fill", iconColor: SettingsView.colorTricks,
                        title: "Counter Glitch Effect",
                        subtitle: "Inflate a follower or following count with a countdown",
                        isExpanded: $isExpanded,
                        trailing: {
                            Button { showingHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
                }
            Text("Swipe the grid to secretly build a number (1–100), then open Explore. When you visit an audience member's profile the selected counter appears inflated by that exact number. Press a volume button to start the countdown back to the real number.\n\nDuring the glitch, Vault shows the full counter value so small changes remain visible even on profiles above 1K.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    // ── Target stat ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Target counter")
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        HStack(spacing: 8) {
                            ForEach([(false, "Following", "person.2"), (true, "Followers", "person.2.fill")], id: \.0) { isFollowers, label, icon in
                                let selected = settings.targetFollowers == isFollowers
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settings.targetFollowers = isFollowers
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(LocalizedStringKey(label))
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(selected ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                                    .cornerRadius(8)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    Divider()

                    // ── Transfer illusion ─────────────────────────────────
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .foregroundColor(SettingsView.colorTricks)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer effect")
                                .font(VaultTheme.Typography.bodyBold())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text("Deflates the searched profile, then inflates yours when you press the volume button.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.transferEnabled)
                            .labelsHidden()
                    }

                    Divider()

                    // ── Trigger delay ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        HStack {
                            Text("Delay before countdown")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            Spacer()
                            Text(settings.triggerDelay == 0 ? "Instant" : "\(settings.triggerDelay)s")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.primary)
                                .monospacedDigit()
                        }
                        Text("Time between pressing the volume button and the numbers starting to decrease.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        Slider(
                            value: Binding(
                                get: { Double(settings.triggerDelay) },
                                set: { settings.triggerDelay = Int($0.rounded()) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                        .tint(VaultTheme.Colors.primary)
                        HStack {
                            Text("0s").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
                            Spacer()
                            Text("10s").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    }

                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            CounterGlitchHelpView(onClose: { showingHelp = false })
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - Date Force Settings Card (El Oráculo Social)

struct DateForceSettingsCard: View {
    @ObservedObject private var settings = DateForceSettings.shared
    @State private var showingHelp = false
    @State private var isExpanded = false

    var body: some View {
        Group {
        CollapsibleCard(
            icon: "calendar.badge.clock",
            iconColor: SettingsView.colorTricks,
            title: "Date Force",
            subtitle: "Force followers/following to reveal today's date",
            isExpanded: $isExpanded,
            trailing: {
                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                    }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        ) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
            }
            Text("Open any spectator's profile in Explore — it registers automatically when you close it. Open any Explore post to reveal today's date and time.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    // Date format + time offset
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Date format")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            HStack(spacing: 8) {
                                ForEach(DateForceFormat.allCases, id: \.rawValue) { fmt in
                                    let isSelected = settings.dateFormat == fmt
                                    Button(action: { settings.dateFormat = fmt }) {
                                        Text(fmt.displayName)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Add minutes to time")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text(settings.timeOffsetMinutes == 0 ? "Off" : "+\(settings.timeOffsetMinutes) min")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                                    .animation(.easeInOut(duration: 0.15), value: settings.timeOffsetMinutes)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(settings.timeOffsetMinutes) },
                                    set: { settings.timeOffsetMinutes = Int($0.rounded()) }
                                ),
                                in: 0...5,
                                step: 1
                            )
                            .tint(settings.timeOffsetMinutes == 0 ? VaultTheme.Colors.textTertiary : VaultTheme.Colors.primary)
                            HStack {
                                Text("Off")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("+5 min")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                            }
                        }
                    }

                    Divider()

                    // Mode info (auto only — dual temporarily disabled)
                    Text("App captures new followers automatically during Performance. Open 'Followed by' to manage spectators.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    #if false
                    // MARK: - Mode selector (dual mode temporarily disabled)
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Mode")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        HStack(spacing: 8) {
                            ForEach(DateForceMode.allCases, id: \.rawValue) { mode in
                                let isSelected = settings.mode == mode
                                Button(action: { settings.mode = mode }) {
                                    Text(mode == .dual ? "Dual" : "Auto")
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        Text(settings.mode == .dual
                             ? "Visit each spectator manually in Explore. First half → 📅 date (their followers). Second half → 🕐 time (their following)."
                             : "App captures your latest followers automatically. Tap 'Followed by' in Performance to start.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Spectator count selector (now handled in Performance via baseline snapshot)
                    if settings.mode == .auto {
                        Divider()
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Spectators to capture")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("\(settings.autoSpectatorCount)")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            HStack(spacing: 8) {
                                ForEach([2, 4, 6, 8], id: \.self) { n in
                                    let isSelected = settings.autoSpectatorCount == n
                                    Button(action: { settings.autoSpectatorCount = n }) {
                                        Text("\(n)")
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            let half = settings.autoSpectatorCount / 2
                            HStack(spacing: 12) {
                                Label("\(half) for date (followers)", systemImage: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.blue.opacity(0.8))
                                Label("\(half) for time (following)", systemImage: "clock")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.orange.opacity(0.8))
                            }
                        }
                    }

                    // Dual info row
                    if settings.mode == .dual {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic split")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                            Text("Register an even number of spectators. The app splits them in half automatically: first half → 📅 date (their followers), second half → 🕐 time (their following).")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
                    #endif

                    Divider()

                    // Live preview
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Live preview")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)

                        HStack(spacing: 0) {
                            VStack(spacing: 3) {
                                Text("Target")
                                    .font(.system(size: 10))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Text("\(settings.previewDateString) \(settings.previewTimeString)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            .frame(maxWidth: .infinity)

                            Divider().frame(height: 32)

                            VStack(spacing: 3) {
                                Text("Followers (📅)")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.blue.opacity(0.7))
                                Text(DateForceSettings.formatExact(settings.overrideFollowers))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)

                            Divider().frame(height: 32)

                            VStack(spacing: 3) {
                                Text("Following (🕐)")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.orange.opacity(0.7))
                                Text(DateForceSettings.formatExact(settings.overrideFollowing))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                        .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 10)
                        .background(VaultTheme.Colors.backgroundSecondary)
                        .cornerRadius(8)
                    }

                    // Registered spectators list
                    if !settings.spectators.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Spectators (\(settings.spectators.count))")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Button(action: { settings.resetSpectators() }) {
                                    Text("Reset")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(VaultTheme.Colors.error)
                                }
                            }

                            ForEach(Array(settings.spectators.enumerated()), id: \.element.id) { index, spec in
                                let group = settings.effectiveGroup(at: index)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(group == .date ? Color.blue.opacity(0.25) : Color.orange.opacity(0.25))
                                        .frame(width: 8, height: 8)
                                    Text("@\(spec.username)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Spacer()
                                    if group == .date {
                                        Text("\(spec.rawFollowerCount) followers")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(Color.blue.opacity(0.8))
                                    } else {
                                        Text("\(spec.rawFollowingCount) following")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(Color.orange.opacity(0.8))
                                    }
                                    Text(group == .date ? "📅" : "🕐")
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            DateForceHelpView(onClose: { showingHelp = false })
        }
    }
}

// MARK: - Backup Card

private struct BackupCard: View {
    @ObservedObject var backup: CloudBackupService
    @ObservedObject private var drive = iCloudDriveSync.shared
    @State private var showRestoreConfirm = false
    @State private var showRestoredAlert = false
    @State private var isRestoring = false

    private var lastBackupText: String {
        guard let date = backup.lastBackupDate else {
            return String(localized: "backup.never")
        }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return String(localized: "backup.just_now") }
        if diff < 3600 {
            let m = Int(diff / 60)
            return String(format: String(localized: "backup.min_ago"), m)
        }
        if diff < 86400 {
            let h = Int(diff / 3600)
            return String(format: String(localized: "backup.h_ago"), h)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                    Text("iCloud Backup")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    if !backup.iCloudAvailable {
                        Text("Not available")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }
                }

                HStack {
                    Text("Last backup")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Text(lastBackupText)
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }

                HStack {
                    Text("Status")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        let hasError = backup.lastKVError != nil || drive.lastError != nil
                        Circle()
                            .fill(hasError ? Color.orange : (backup.iCloudAvailable ? Color.green : Color.gray))
                            .frame(width: 7, height: 7)
                        Text(hasError ? "Warning" : (backup.iCloudAvailable ? "Active" : "Inactive"))
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                }

                // Sets backup status row
                if backup.backedUpSetsBytes > 0 || backup.hasCloudBackup {
                    HStack {
                        Text("Sets in backup")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text(backup.backedUpSetsBytes > 0 ? "\(backup.backedUpSetsBytes / 1024) KB" : "OK")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
                }

                // Photos in iCloud Drive status row
                HStack {
                    Text("Photos in iCloud Drive")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    HStack(spacing: 4) {
                        if let driveErr = drive.lastError {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text(driveErr.isICloudFull ? "iCloud full" : "Unavailable")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(drive.cloudFileCount > 0 ? "\(drive.cloudFileCount) photos" : "Synced")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
                }

                // Error / warning banner
                if let kvErr = backup.lastKVError {
                    warningBanner(icon: "exclamationmark.triangle.fill", message: kvErr, color: .orange)
                }
                if let driveErr = drive.lastError {
                    warningBanner(
                        icon: driveErr.isICloudFull ? "icloud.slash.fill" : "exclamationmark.icloud.fill",
                        message: driveErr.errorDescription ?? driveErr.localizedDescription,
                        color: driveErr.isICloudFull ? .red : .orange
                    )
                }

                Button(action: { performManualBackup() }) {
                    HStack {
                        if backup.isSyncing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.clockwise.icloud")
                        }
                        Text(backup.isSyncing ? "Saving…" : "Back up now")
                            .font(VaultTheme.Typography.body().weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(backup.iCloudAvailable ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!backup.iCloudAvailable || backup.isSyncing)

                Button(action: { showRestoreConfirm = true }) {
                    HStack {
                        if isRestoring {
                            ProgressView()
                                .tint(.blue)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                        Text(isRestoring ? "Restoring…" : "Restore from backup")
                            .font(VaultTheme.Typography.body().weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(backup.hasCloudBackup ? .blue : .gray)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(!backup.hasCloudBackup || isRestoring || backup.isSyncing)

                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "gear.badge.checkmark",
                            text: String(localized: "backup.info.auto"))
                    infoRow(icon: "slider.horizontal.3",
                            text: String(localized: "backup.info.what"))
                    infoRow(icon: "photo.on.rectangle",
                            text: String(localized: "backup.info.photos"))
                    infoRow(icon: "icloud.slash",
                            text: String(localized: "backup.info.excluded"))
                }

                HStack(spacing: 8) {
                    Button(action: {
                        let report = backup.backupDiagnostics()
                        print(report)
                        LogManager.shared.info(report, category: .general)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "stethoscope")
                            Text("KV Diag")
                                .font(VaultTheme.Typography.caption().weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.gray.opacity(0.08))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }

                    Button(action: {
                        // Use DispatchQueue (not Task.detached) to avoid Swift concurrency
                        // issues with the blocking url(forUbiquityContainerIdentifier:) call
                        DispatchQueue.global(qos: .userInitiated).async {
                            iCloudDriveSync.shared.runDiagnostics()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.questionmark")
                            Text("Drive Diag")
                                .font(VaultTheme.Typography.caption().weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.gray.opacity(0.08))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
            }
        }
        .alert("Restore from iCloud?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("This will overwrite your current settings and sets with the iCloud backup. This action cannot be undone.")
        }
        .alert("Restore complete", isPresented: $showRestoredAlert) {
            Button("OK") { }
        } message: {
            Text("Your settings and sets have been restored from iCloud.")
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue.opacity(0.7))
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

    private func warningBanner(icon: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)
                .padding(.top, 1)
            Text(message)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func performManualBackup() {
        backup.syncToCloud()
        drive.syncAllPhotosToCloud { uploaded, skipped, error in
            if let error = error {
                LogManager.shared.warning("Manual iCloud Drive backup issue: \(error.localizedDescription)", category: .general)
            } else {
                print("☁️ [DRIVE] Manual backup: \(uploaded) uploaded, \(skipped) already synced")
            }
        }
    }

    private func performRestore() {
        isRestoring = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = backup.restoreFromCloud()
            DispatchQueue.main.async {
                if success {
                    DataManager.shared.reloadAfterRestore()
                    iCloudDriveSync.shared.downloadAllPhotosFromCloud { count in
                        print("☁️ [BACKUP] Manual restore: \(count) photo files downloaded")
                    }
                }
                isRestoring = false
                showRestoredAlert = success
            }
        }
    }
}

// MARK: - Fake Home Screen Card

struct FakeHomeScreenCard: View {
    @Binding var showingPicker: Bool
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @AppStorage("performanceCoverMode") private var performanceCoverModeRaw = PerformanceCoverMode.off.rawValue
    @AppStorage("fakeHomeScreenEnabled") private var legacyFakeHomeScreenEnabled = false
    @State private var isExpanded = false
    @State private var showingHelp = false

    private static let accent = SettingsView.colorData

    private var selectedMode: PerformanceCoverMode {
        get {
            if UserDefaults.standard.object(forKey: "performanceCoverMode") == nil && legacyFakeHomeScreenEnabled {
                return .homeScreen
            }
            return PerformanceCoverMode(rawValue: performanceCoverModeRaw) ?? .off
        }
        nonmutating set {
            performanceCoverModeRaw = newValue.rawValue
            legacyFakeHomeScreenEnabled = newValue == .homeScreen
        }
    }

    var body: some View {
        CollapsibleCard(
            icon: "iphone",
            iconColor: Self.accent,
            title: "Performance Cover",
            subtitle: "Choose what appears before Performance is revealed",
            isExpanded: $isExpanded,
            trailing: {
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        ) {
            infoRow
            modernDivider()
            modeSelector
            if selectedMode == .homeScreen {
                modernDivider()
                imagePickerRow
            } else if selectedMode == .screenOff {
                modernDivider()
                screenOffInfoRow
            }
        }
        .sheet(isPresented: $showingHelp) {
            FakeHomeScreenHelpSheet()
        }
    }

    @ViewBuilder private var infoRow: some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Self.accent)
                    .frame(width: 28, height: 28)
                Image(systemName: "iphone.homebutton")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedMode.title)
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text(selectedMode.subtitle)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    @ViewBuilder private var modeSelector: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Cover mode")
                .font(VaultTheme.Typography.bodyBold())
                .foregroundColor(VaultTheme.Colors.textPrimary)

            ForEach(PerformanceCoverMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: VaultTheme.Spacing.md) {
                        Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedMode == mode ? Self.accent : VaultTheme.Colors.textSecondary)
                        Image(systemName: mode.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text(mode.subtitle)
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(VaultTheme.Spacing.sm)
                    .background(selectedMode == mode ? Self.accent.opacity(0.10) : Color.clear)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var screenOffInfoRow: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 52, height: 92)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#3A3A3C"), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("Fake Screen Off")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text("Shows a black screen when Performance opens. Tap anywhere to reveal the profile, using the same flow as Fake Home Screen.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var imagePickerRow: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            thumbnailView
            VStack(alignment: .leading, spacing: 6) {
                Text(illusionService.hasImage ? "Screenshot loaded" : "No screenshot")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text("Upload a screenshot of your iPhone home screen showing the Instagram icon.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var thumbnailView: some View {
        if let img = illusionService.screenshot {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#3A3A3C"), lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#2C2C2E"))
                .frame(width: 52, height: 92)
                .overlay(Image(systemName: "iphone")
                    .font(.system(size: 22))
                    .foregroundColor(VaultTheme.Colors.textTertiary))
        }
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { showingPicker = true } label: {
                Label(illusionService.hasImage ? "Replace" : "Select screenshot",
                      systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Self.accent)
                    .cornerRadius(7)
            }
            if illusionService.hasImage {
                Button { illusionService.delete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.error)
                        .padding(6)
                        .background(VaultTheme.Colors.error.opacity(0.12))
                        .cornerRadius(7)
                }
            }
        }
    }

    @ViewBuilder private func modernDivider() -> some View {
        Divider().background(Color(hex: "#3A3A3C"))
    }
}

// MARK: - Fake Home Screen Help Sheet

private struct FakeHomeScreenHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    helpSection(
                        icon: "iphone.homebutton",
                        iconColor: SettingsView.colorData,
                        title: "What is Performance Cover?",
                        body: "When you open Performance, the app can first show a cover screen before revealing your profile. Choose Fake Home Screen for a real screenshot, or Fake Screen Off for a black screen that looks like the phone is off."
                    )

                    helpSection(
                        icon: "hand.tap.fill",
                        iconColor: SettingsView.colorData,
                        title: "How to use it",
                        body: "1. Select a cover mode.\n\n2. For Fake Home Screen, upload a screenshot with the Instagram icon visible.\n\n3. For Fake Screen Off, no image is needed.\n\n4. Next time you open Performance, tap anywhere on the cover to reveal your profile."
                    )

                    helpSection(
                        icon: "eye.slash.fill",
                        iconColor: SettingsView.colorData,
                        title: "Why use it?",
                        body: "It creates the illusion that you are simply opening the real Instagram app. Anyone looking at your screen only sees the normal home screen before your profile appears, making the experience look completely natural."
                    )
                }
                .padding(20)
            }
            .navigationTitle("Performance Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func helpSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(body)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Lockscreen Input Settings Card

struct LockscreenInputSettingsCard: View {
    @ObservedObject private var settings = LockscreenInputSettings.shared
    @State private var isExpanded = false
    @State private var showingPicker = false
    @State private var showingHelp = false

    var body: some View {
        CollapsibleCard(icon: "lock.fill", iconColor: SettingsView.colorData,
                        title: "guide.lockscreen.title",
                        subtitle: "guide.lockscreen.subtitle",
                        isExpanded: $isExpanded,
                        trailing: {
                            Button { showingHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }) {
            Label(String(localized: "lockscreen.perset_note"), systemImage: "info.circle")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                Text("guide.lockscreen.help.wallpaper.title", comment: "Wallpaper section header")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)

                if let img = settings.wallpaperImage {
                    HStack(spacing: 12) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                showingPicker = true
                            } label: {
                                Label(String(localized: "action.change"), systemImage: "photo.on.rectangle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(SettingsView.colorTricks)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button {
                                settings.clearWallpaper()
                                settings.isEnabled = false
                            } label: {
                                Label(String(localized: "action.remove"), systemImage: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(VaultTheme.Colors.error)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 16))
                            Text("settings.lockscreen.choose_wallpaper", comment: "Choose wallpaper button")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SettingsView.colorTricks)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    if settings.isEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(VaultTheme.Colors.warning)
                                .font(.system(size: 12))
                            Text("settings.lockscreen.warning_no_wallpaper", comment: "Warning when no wallpaper set")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.warning)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            HomeScreenImagePicker { image in
                settings.saveWallpaper(image)
            }
        }
        .sheet(isPresented: $showingHelp) {
            LockscreenInputHelpSheet()
        }
    }
}

// MARK: - Lockscreen Input Help Sheet

private struct LockscreenInputHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    helpSection(
                        icon: "lock.fill",
                        iconColor: SettingsView.colorData,
                        title: String(localized: "guide.lockscreen.help.what.title"),
                        body: String(localized: "guide.lockscreen.help.what.body")
                    )

                    helpSection(
                        icon: "hand.point.up.left.fill",
                        iconColor: SettingsView.colorData,
                        title: String(localized: "guide.lockscreen.help.how.title"),
                        body: String(localized: "guide.lockscreen.help.how.body")
                    )

                    helpSection(
                        icon: "photo.fill",
                        iconColor: SettingsView.colorData,
                        title: String(localized: "guide.lockscreen.help.wallpaper.title"),
                        body: String(localized: "guide.lockscreen.help.wallpaper.body")
                    )

                    helpSection(
                        icon: "eye.slash.fill",
                        iconColor: SettingsView.colorData,
                        title: String(localized: "guide.lockscreen.help.why.title"),
                        body: String(localized: "guide.lockscreen.help.why.body")
                    )

                    helpSection(
                        icon: "square.grid.2x2.fill",
                        iconColor: SettingsView.colorData,
                        title: String(localized: "guide.lockscreen.help.tricks.title"),
                        body: String(localized: "guide.lockscreen.help.tricks.body")
                    )
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "guide.lockscreen.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "action.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func helpSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(body)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Amnesia Carousel Settings Card

struct AmnesiaCarouselSettingsCard: View {
    @ObservedObject private var settings = AmnesiaCarouselSettings.shared
    @ObservedObject private var instagram = InstagramService.shared
    @State private var isExpanded         = false
    @State private var showingHelp        = false
    @State private var showingImagePicker = false
    @State private var pickingSlot        = 0
    @State private var uploadError: String?
    @State private var showingError       = false
    @State private var showingResetAlert  = false

    private let accent = SettingsView.colorTricks

    var body: some View {
        CollapsibleCard(
            icon: "rectangle.on.rectangle.slash",
            iconColor: accent,
            title: LocalizedStringKey("guide.amnesia.row.title"),
            subtitle: LocalizedStringKey("guide.amnesia.row.subtitle"),
            isExpanded: $isExpanded,
            trailing: {
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        ) {
            // Toggle
            HStack {
                Text(String(localized: "amnesia.toggle"))
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .tint(accent)
            }

            if settings.isEnabled {
                modernDivider()
                imageSlots
                modernDivider()
                statusRow
                modernDivider()
                actionButtons
            }
        }
        .sheet(isPresented: $showingHelp) {
            AmnesiaCarouselHelpSheet()
        }
        .sheet(isPresented: $showingImagePicker) {
            HomeScreenImagePicker { image in
                settings.setImage(image, for: pickingSlot)
            }
        }
        .alert(String(localized: "amnesia.state.error"), isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(uploadError ?? "")
        }
        .alert(String(localized: "amnesia.reset_title"), isPresented: $showingResetAlert) {
            Button(String(localized: "amnesia.reset_confirm"), role: .destructive) { triggerReset() }
            Button(String(localized: "amnesia.reset_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "amnesia.reset_msg"))
        }
    }

    // MARK: - Image slots

    private var imageSlots: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "amnesia.images_title"))
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Button {
                    loadESPTemplate()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .semibold))
                        Text(String(localized: "amnesia.esp_template"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(settings.isReady)
            }

            // Slots 1-4 in a 2×2 grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    amnesiaSlot(index: i, isHidden: false)
                }
            }

            // Slot 5 (the hidden image) — visually distinct
            VStack(alignment: .leading, spacing: 4) {
                amnesiaSlot(index: 4, isHidden: true)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(String(localized: "amnesia.slot5_hint"))
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(.orange.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder
    private func amnesiaSlot(index: Int, isHidden: Bool) -> some View {
        Button {
            pickingSlot = index
            showingImagePicker = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHidden ? Color.orange : Color(hex: "#3A3A3C"),
                        style: StrokeStyle(lineWidth: isHidden ? 2 : 1.5,
                                           dash: isHidden ? [6, 3] : [])
                    )
                    .background(Color(hex: "#1C1C1E").cornerRadius(8))

                if let img = settings.images[index] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 80)
                        .clipped()
                        .cornerRadius(7)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: isHidden ? "eye.slash" : "photo.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(isHidden ? .orange.opacity(0.7) : VaultTheme.Colors.textSecondary)
                        Text(isHidden ? String(localized: "amnesia.slot_hidden") : String(format: String(localized: "amnesia.slot_n"), index + 1))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isHidden ? .orange.opacity(0.7) : VaultTheme.Colors.textSecondary)
                    }
                }
            }
            .frame(height: 80)
        }
        .disabled(settings.uploadState.isUploading || settings.isReady)
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(settings.uploadState.label)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            if settings.isReady {
                Spacer()
                Text(settings.isRevealed ? "REVELADO" : "INICIAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(settings.isRevealed ? .orange : .green)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((settings.isRevealed ? Color.orange : Color.green).opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }

    private var statusColor: Color {
        switch settings.uploadState {
        case .idle:        return .gray
        case .uploading:   return .yellow
        case .ready:       return .green
        case .swapping:    return .orange
        case .error:       return .red
        }
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
                if !settings.isReady {
                modernActionButton(
                    title: settings.uploadState.isUploading ? settings.uploadState.label : String(localized: "amnesia.btn_upload"),
                    icon: "arrow.up.circle.fill",
                    loading: settings.uploadState.isUploading,
                    enabled: settings.allImagesFilled && !settings.uploadState.isUploading && !instagram.isLocked
                ) { startUpload() }
            } else {
                if settings.isRevealed {
                    modernActionButton(
                        title: settings.uploadState == .swapping ? String(localized: "amnesia.state.swapping") : String(localized: "amnesia.btn_reset"),
                        icon: "arrow.counterclockwise.circle.fill",
                        loading: settings.uploadState == .swapping,
                        enabled: settings.uploadState != .swapping
                    ) { showingResetAlert = true }
                }

                // Clear all button (secondary)
                Button {
                    settings.clearAll()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                        Text(String(localized: "amnesia.btn_clear"))
                            .font(VaultTheme.Typography.caption())
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(settings.uploadState == .swapping)
            }
        }
    }

    // MARK: - Actions

    private func startUpload() {
        let filled = settings.images.compactMap { $0 }
        guard filled.count == 5 else { return }
        settings.uploadState = .uploading(step: 0, total: 12)

        Task {
            do {
                try await InstagramService.shared.uploadAmnesiaCarousels(
                    images: filled.map { $0 }
                ) { step, total in
                    Task { @MainActor in
                        settings.uploadState = .uploading(step: step, total: total)
                    }
                }
            } catch {
                await MainActor.run {
                    settings.uploadState = .error(error.localizedDescription)
                    uploadError = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func triggerReset() {
        settings.uploadState = .swapping
        Task {
            do {
                try await InstagramService.shared.swapAmnesiaCarousels(settings: settings)
                await MainActor.run { settings.uploadState = .ready }
            } catch {
                await MainActor.run {
                    settings.uploadState = .ready
                    uploadError = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func loadESPTemplate() {
        let names = ["esp_card_1", "esp_card_2", "esp_card_3", "esp_card_4", "esp_card_5"]
        for (i, name) in names.enumerated() {
            if let img = UIImage(named: name) {
                settings.setImage(img, for: i)
            }
        }
    }

    private func modernDivider() -> some View {
        Divider().background(Color(hex: "#3A3A3C"))
    }

    @ViewBuilder
    private func modernActionButton(title: String, icon: String, loading: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                if loading {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: icon)
                }
                Text(title).font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(enabled ? VaultTheme.Colors.primary : VaultTheme.Colors.textDisabled)
            .cornerRadius(VaultTheme.CornerRadius.md)
        }
        .disabled(!enabled || loading)
    }
}

// MARK: - Amnesia Carousel Help Sheet

private struct AmnesiaCarouselHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Animated preview
                    AmnesiaAnimationView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    Divider()

                    helpSection(
                        icon: "questionmark.circle.fill",
                        title: String(localized: "guide.amnesia.what.title"),
                        body: String(localized: "guide.amnesia.what.body")
                    )

                    helpSection(
                        icon: "rectangle.on.rectangle.slash.fill",
                        title: String(localized: "guide.amnesia.trigger.title"),
                        body: String(localized: "guide.amnesia.trigger.body")
                    )

                    helpSection(
                        icon: "star.fill",
                        title: String(localized: "guide.amnesia.hidden.title"),
                        body: String(localized: "guide.amnesia.hidden.body")
                    )

                    helpSection(
                        icon: "mic.fill",
                        title: String(localized: "guide.amnesia.script.title"),
                        body: scriptText
                    )

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Color(hex: "#1C1C1E").ignoresSafeArea())
            .navigationTitle(String(localized: "guide.amnesia.row.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "action.close")) { dismiss() }
                        .foregroundColor(SettingsView.colorTricks)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func helpSection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(SettingsView.colorTricks)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(body)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scriptText: String {
        [
            "\(String(localized: "guide.amnesia.script.opening.phase"))\n\(String(localized: "guide.amnesia.script.opening.text"))",
            "\(String(localized: "guide.amnesia.script.close.phase"))\n\(String(localized: "guide.amnesia.script.close.text"))",
            "\(String(localized: "guide.amnesia.script.optionA.phase"))\n\(String(localized: "guide.amnesia.script.optionA.text"))",
            "\(String(localized: "guide.amnesia.script.optionB.phase"))\n\(String(localized: "guide.amnesia.script.optionB.text"))",
            "\(String(localized: "guide.amnesia.script.climax.phase"))\n\(String(localized: "guide.amnesia.script.climax.text"))"
        ].joined(separator: "\n\n──────────────────────────────\n\n")
    }
}

// MARK: - Amnesia Animation View

struct AmnesiaAnimationView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    // Zener card symbols drawn in SwiftUI
    private var symbols: [(String, AnyView)] {
        [
            (String(localized: "amnesia.anim.card_circle"),   AnyView(ZenerCircle())),
            (String(localized: "amnesia.anim.card_cross"),    AnyView(ZenerCross())),
            (String(localized: "amnesia.anim.card_square"),   AnyView(ZenerSquare())),
            (String(localized: "amnesia.anim.card_waves"),    AnyView(ZenerWaves())),
            (String(localized: "amnesia.anim.card_star"),     AnyView(ZenerStar()))
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Phase label
            Text(phaseTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)
                .animation(.easeInOut(duration: 0.4), value: phase)

            // Cards row
            HStack(spacing: 10) {
                ForEach(0..<visibleCount, id: \.self) { i in
                    ZenerCardView(content: symbols[i].1,
                                  label: symbols[i].0,
                                  isRevealed: i == 4,
                                  showGlow: phase >= 2 && i == 4)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: visibleCount)

            // Subtitle
            Text(phaseSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.4), value: phase)
                .frame(minHeight: 36)

            // Dots indicator
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == phase ? SettingsView.colorTricks : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#2C2C2E").cornerRadius(12))
        .onReceive(timer) { _ in
            withAnimation { phase = (phase + 1) % 4 }
        }
    }

    private var visibleCount: Int {
        switch phase {
        case 0, 1: return 4
        case 2, 3: return 5
        default:   return 4
        }
    }

    private var phaseTitle: String {
        switch phase {
        case 0: return String(localized: "amnesia.anim.phase0_title")
        case 1: return String(localized: "amnesia.anim.phase1_title")
        case 2: return String(localized: "amnesia.anim.phase2_title")
        case 3: return String(localized: "amnesia.anim.phase3_title")
        default: return ""
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case 0: return String(localized: "amnesia.anim.phase0_sub")
        case 1: return String(localized: "amnesia.anim.phase1_sub")
        case 2: return String(localized: "amnesia.anim.phase2_sub")
        case 3: return String(localized: "amnesia.anim.phase3_sub")
        default: return ""
        }
    }
}

// MARK: - Zener Card View

private struct ZenerCardView: View {
    let content: AnyView
    let label: String
    let isRevealed: Bool
    let showGlow: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#1C1C1E"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                showGlow ? Color.orange : (isRevealed ? Color.orange.opacity(0.5) : Color(hex: "#3A3A3C")),
                                lineWidth: showGlow ? 2 : 1
                            )
                    )
                    .shadow(color: showGlow ? .orange.opacity(0.6) : .clear, radius: 8)
                content
                    .frame(width: 28, height: 28)
            }
            .frame(width: 44, height: 44)

            Text(isRevealed ? "★" : "")
                .font(.system(size: 8))
                .foregroundColor(.orange)
                .frame(height: 10)
        }
    }
}

// MARK: - Zener Symbols (SwiftUI shapes)

private struct ZenerCircle: View {
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
            .padding(4)
    }
}

private struct ZenerCross: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2.5, height: 22)
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 22, height: 2.5)
        }
    }
}

private struct ZenerSquare: View {
    var body: some View {
        Rectangle()
            .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
            .padding(4)
    }
}

private struct ZenerWaves: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var path = Path()
            let waves = 3
            let ampY = h * 0.18
            let segW = w / CGFloat(waves)
            path.move(to: CGPoint(x: 0, y: h / 2))
            for i in 0..<waves {
                let x0 = CGFloat(i) * segW
                path.addCurve(
                    to:        CGPoint(x: x0 + segW,     y: h / 2),
                    control1:  CGPoint(x: x0 + segW * 0.3, y: h / 2 - ampY),
                    control2:  CGPoint(x: x0 + segW * 0.7, y: h / 2 + ampY)
                )
            }
            ctx.stroke(path, with: .color(.white.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .padding(4)
    }
}

private struct ZenerStar: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let R: CGFloat = min(cx, cy) - 2
            let r: CGFloat = R * 0.4
            let points = 5
            var path = Path()
            for i in 0..<(points * 2) {
                let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let radius: CGFloat = i.isMultiple(of: 2) ? R : r
                let pt = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(.orange.opacity(0.9)))
            ctx.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5))
        }
    }
}

// MARK: - Initial Profile Load (first-time blocking loader)

/// Shown the very first time the magician taps Performance and there is no local
/// cache yet. Loads up to 100 posts with human-paced delays so the full profile is
/// ready before entering the replica. Cannot be dismissed by the user.
private struct InitialProfileLoadView: View {
    let onComplete: () -> Void

    @ObservedObject private var instagram = InstagramService.shared

    private enum InitialLoadTimeout: Error {
        case timedOut
    }

    enum Phase {
        case validating, loadingProfile, paginating(Int)
        case loadingReels, loadingTagged
        case failed(String)
    }
    @State private var phase: Phase = .validating
    @State private var photosLoaded: Int = 0
    @State private var reelsLoaded: Int = 0
    @State private var taggedLoaded: Int = 0

    private let maxPhotos = 100
    /// Page limit: safety cap (100 posts / ~18 per page ≈ 6 pages)
    private let maxPages = 8

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.white)
                    .animation(.easeInOut(duration: 0.4), value: iconName)

                VStack(spacing: 10) {
                    Text(String(localized: "initial_load.title"))
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(phaseDescription)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: phaseDescription)
                }

                // Progress bar — visual confirmation that the load is actually progressing
                if case .failed = phase {
                    EmptyView()
                } else {
                    VStack(spacing: 8) {
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(maxWidth: 220)
                            .animation(.easeInOut, value: progressFraction)

                        if !secondaryStatus.isEmpty {
                            Text(secondaryStatus)
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.white.opacity(0.7))
                                .animation(.easeInOut, value: secondaryStatus)
                        }
                    }
                }

                // Reassurance block: estimated time + one-time promise.
                // Pinned right below the progress so the user reads it without scrolling
                // and stops worrying that the app is stuck.
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.55))
                        Text(String(localized: "initial_load.estimated_time"))
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundColor(Color.green.opacity(0.85))
                        Text(String(localized: "initial_load.one_time_promise"))
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Text(String(localized: "initial_load.footer"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task { await runLoad() }
    }

    /// Fraction in 0…1 for the linear progress bar.
    /// Total estimated items: 100 posts + 20 reels + 20 tagged = 140.
    private var progressFraction: Double {
        let total = 140.0
        let done = Double(photosLoaded) + Double(reelsLoaded) + Double(taggedLoaded)
        return max(0.02, min(1.0, done / total))
    }

    /// Secondary status shown below the progress bar.
    private var secondaryStatus: String {
        var parts: [String] = []
        if photosLoaded > 0 {
            parts.append(photosLoaded == 1
                ? String(format: String(localized: "initial_load.photos_count_one"), photosLoaded)
                : String(format: String(localized: "initial_load.photos_count"), photosLoaded))
        }
        if reelsLoaded > 0 {
            parts.append(String(format: String(localized: "initial_load.reels_count"), reelsLoaded))
        }
        if taggedLoaded > 0 {
            parts.append(String(format: String(localized: "initial_load.tagged_count"), taggedLoaded))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var iconName: String {
        switch phase {
        case .validating:      return "lock.shield"
        case .loadingProfile:  return "person.crop.circle"
        case .paginating:      return "arrow.down.circle"
        case .loadingReels:    return "play.circle"
        case .loadingTagged:   return "tag.circle"
        case .failed:          return "exclamationmark.triangle"
        }
    }

    private var phaseDescription: String {
        switch phase {
        case .validating:        return String(localized: "initial_load.phase.validating")
        case .loadingProfile:    return String(localized: "initial_load.phase.loading_profile")
        case .paginating(let n): return String(format: String(localized: "initial_load.phase.paginating"), n)
        case .loadingReels:      return String(localized: "initial_load.phase.loading_reels")
        case .loadingTagged:     return String(localized: "initial_load.phase.loading_tagged")
        case .failed(let msg):   return msg
        }
    }

    @MainActor
    private func runLoad() async {
        // 1 ── Validate session
        phase = .validating
        let status = await instagram.validateSession()
        if status == .expired {
            // Can't load without a valid session; bounce back gracefully
            phase = .failed(String(localized: "initial_load.error.session"))
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            onComplete()
            return
        }

        // 2 ── Load first page (includes profile info + first ~18 posts)
        phase = .loadingProfile
        guard var profile = try? await instagram.getProfileInfo() else {
            phase = .failed(String(localized: "initial_load.error.load_failed"))
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            onComplete()
            return
        }
        photosLoaded = profile.cachedMediaURLs.count
        ProfileCacheService.shared.saveProfile(profile)

        // 3 ── Paginate with safety-gate-friendly delays until 100 posts or no more pages
        var cursor     = profile.cachedNextMaxId
        var allURLs    = profile.cachedMediaURLs
        var allItems   = profile.cachedMediaItems
        var page       = 1

        while let currentCursor = cursor,
              allURLs.count < maxPhotos,
              page <= maxPages {

            phase = .paginating(page)

            if instagram.shouldUseCacheOnlyForOptionalCalls {
                print("🛡️ [INITIAL LOAD] Pagination stopped near rate budget")
                break
            }

            // Human-paced delay between requests (5–8 s)
            let delayNs = UInt64.random(in: 5_000_000_000...8_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)

            guard let (newItems, newCursor) = try? await instagram.getUserMediaItems(
                userId: nil, amount: 21, maxId: currentCursor
            ) else { break }  // network / API error → stop, use what we have

            let existingIds = Set(allItems.map(\.mediaId))
            let fresh = newItems.filter { !existingIds.contains($0.mediaId) }
            let freshURLs = fresh.map { $0.imageURL }

            allItems += fresh
            allURLs  += freshURLs

            // Guard against duplicate/looping cursor
            let nextCursor = (newCursor != currentCursor) ? newCursor : nil
            cursor = nextCursor

            // Cap at limit
            allURLs  = Array(allURLs.prefix(maxPhotos))
            allItems = Array(allItems.prefix(maxPhotos))

            photosLoaded = allURLs.count
            page += 1

            // Persist incrementally so a mid-load app kill still saves partial data
            var updated = profile
            updated.cachedMediaURLs  = allURLs
            updated.cachedMediaItems = allItems
            updated.cachedNextMaxId  = cursor    // next-page cursor for PerformanceView
            updated.cachedAt         = Date()
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)

            if cursor == nil || allURLs.count >= maxPhotos { break }
        }

        // 4 ── Load reels (up to 2 pages, handled internally by getUserReels)
        guard !instagram.shouldUseCacheOnlyForOptionalCalls else {
            print("🛡️ [INITIAL LOAD] Optional reels/tagged skipped near rate budget")
            try? await Task.sleep(nanoseconds: 900_000_000)
            onComplete()
            return
        }
        phase = .loadingReels
        try? await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...7_000_000_000))
        if let reelItems = try? await withTimeout(seconds: 35, operation: {
            try await instagram.getUserReels(userId: nil, amount: 50)
        }) {
            reelsLoaded = reelItems.count
            var updated = profile
            updated.cachedReelURLs  = reelItems.map { $0.imageURL }
            updated.cachedReelItems = reelItems
            updated.cachedAt        = Date()
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            // Mark as paginated so fetchReelsIfNeeded never re-fetches the old 10-item cache
            UserDefaults.standard.set(true, forKey: "reels_paginated_\(profile.userId)")
        }

        // 5 ── Load tagged (up to 2 pages, handled internally by getUserTagged)
        phase = .loadingTagged
        try? await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...7_000_000_000))
        if let taggedItems = try? await withTimeout(seconds: 35, operation: {
            try await instagram.getUserTagged(userId: nil, amount: 50)
        }) {
            taggedLoaded = taggedItems.count
            var updated = profile
            updated.cachedTaggedURLs = taggedItems.map { $0.imageURL }
            updated.cachedAt         = Date()
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            UserDefaults.standard.set(true, forKey: "tagged_paginated_\(profile.userId)")
        }

        // Brief completion moment so the user sees the final count
        try? await Task.sleep(nanoseconds: 900_000_000)
        onComplete()
    }

    /// Secondary profile tabs should never block Performance entry forever.
    /// If Instagram stalls on reels/tagged, keep the partial cache and continue.
    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw InitialLoadTimeout.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Home Screen Image Picker

import PhotosUI

struct HomeScreenImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { self?.onPick(image) }
            }
        }
    }
}
