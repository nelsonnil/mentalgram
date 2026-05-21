import SwiftUI
import Photos
import AVFoundation
import AudioToolbox

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject private var dateForce = DateForceSettings.shared
    @ObservedObject private var fullLoader = ProfileFullLoaderService.shared
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @AppStorage("autoProfilePicOnPerformance") private var autoProfilePicOnPerformance = false
    @AppStorage("clipboardAutoMode") private var clipboardAutoMode: String = ""
    // Last clipboard text sent — avoids re-sending the same text on repeated opens.
    @AppStorage("clipboardAutoLastSent") private var clipboardAutoLastSent: String = ""
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @ObservedObject private var urlAction = URLActionManager.shared

    // OCR
    @AppStorage("noteTopInputMode") private var noteTopInputMode: String = "off"
    @AppStorage("bioTopInputMode")  private var bioTopInputMode:  String = "off"
    @AppStorage("ppTopInputMode")   private var ppTopInputMode:   String = "off"
    // Text templates — user-defined wrappers with {word} token
    @AppStorage("note_template") private var noteTemplate: String = ""
    @AppStorage("bio_template")  private var bioTemplate:  String = ""
    // Optimistic note state — @AppStorage triggers instant re-render on write
    @AppStorage("last_note_text")           private var lastNoteText: String = ""
    @AppStorage("last_note_sent_timestamp") private var lastNoteSentTimestamp: Double = 0
    @ObservedObject private var forceRevealSettings = ForceNumberRevealSettings.shared
    @ObservedObject private var followingMagic = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor  = VolumeButtonMonitor.shared
    @ObservedObject private var amnesiaSettings = AmnesiaCarouselSettings.shared
    @StateObject private var ocrCoordinator = OCRCoordinator()
    /// Set by OCR result handler; observed by InstagramProfileView to trigger post-prediction reveal.
    @State private var pendingOCRWord: String? = nil
    /// Set by URL scheme handler; observed by InstagramProfileView to trigger custom-set slot reveal.
    @State private var pendingSlotReveal: Int? = nil
    /// Set by URL scheme handler; observed by InstagramProfileView to trigger playing-card reveal.
    @State private var pendingCardReveal: String? = nil
    /// Set by the fake lockscreen; observed by InstagramProfileView to route number/custom/card reveals.
    @State private var pendingLockscreenDigits: [Int]? = nil
    /// True once OCR has recognised and routed a word in this session.
    /// Prevents a second OCR trigger in the same Performance session (one reveal per trick).
    @State private var ocrUsedInSession: Bool = false
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var showingLockdownSheet = false   // For long-press lockdown details
    @State private var showDigitGridAlert = false
    @State private var performanceRemoteCallsAllowed = true
    @State private var performanceEntryRecorded = false
    /// Seconds remaining in the safety-gate pause. Non-zero only when blocked with no cache.
    @State private var safetyGateCountdown: Int = 0
    /// Shown the very first time Performance loads (no cache yet). Stored so it never appears again.
    @AppStorage("perf.hasSeenFirstTimeBanner") private var hasSeenFirstTimeBanner: Bool = false
    @State private var showFirstTimeBanner: Bool = false
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    
    // MARK: - Infinite Scroll State
    @State private var allMediaURLs: [String] = []
    @State private var mediaItemsByURL: [String: InstagramMediaItem] = [:]
    @State private var revealDates: [String: Date] = [:]
    @State private var nextMaxId: String? = nil
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    /// True while a DispatchQueue retry has already been scheduled.
    /// Prevents the thundering-herd problem where 12 onAppear callbacks each
    /// schedule their own retry when the SafetyGate is in cooldown.
    @State private var paginationRetryScheduled = false
    private let maxPhotosOwnProfile = 100
    // Lazy-tab loading: track whether each secondary tab has been loaded at least once.
    @State private var reelsLoadedOnce  = false
    @State private var taggedLoadedOnce = false

    // MARK: - Fake Home Screen illusion
    @AppStorage("fakeHomeScreenEnabled") private var fakeHomeScreenEnabled = false
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @State private var showingHomeScreenIllusion = false

    // MARK: - Fake Lockscreen input
    @State private var showingLockscreen = false
    /// Prevents re-presenting the lockscreen when onAppear re-fires after the
    /// fullScreenCover is dismissed (which happens on every iOS version).
    @State private var lockscreenWasShown = false

    // MARK: - Spectator profile overlay
    @State private var selectedSpectator: InstagramFollower? = nil
    @State private var spectatorProfile: InstagramProfile?  = nil
    @State private var isLoadingSpectator: Bool             = false

    // MARK: - Upload conflict alert (reveal blocked while upload is active)
    @State private var showUploadConflictAlert = false
    @State private var spectatorLoadError: String? = nil

    // MARK: - Anti-bot: auto-pause upload while Performance is visible
    // True when PerformanceView itself requested the pause (not the user, not an error).
    // Used in onDisappear to signal SetDetailView to auto-resume.
    @State private var didAutoPauseUpload = false
    @ObservedObject private var uploadManager = UploadManager.shared

    // MARK: - Anti-bot: probe dedup
    // Prevents multiple session probes from firing simultaneously when the user
    // rapidly minimizes/foregrounds the app during a lockdown.
    @State private var probeInFlight = false

    // MARK: - Refresh throttle (prevent rapid consecutive API calls)
    /// Persisted across app restarts so throttle survives close/reopen cycles.
    /// Aligned with `InstagramSafetyGate.entryRefresh` (90s) so this is a
    /// belt-and-braces fallback for the case where the safety gate's
    /// in-memory state was wiped by a crash but the user reopens Performance
    /// immediately. Previous value of 600s blocked every entry refresh for
    /// 10 minutes, which meant "I just uploaded a photo on Instagram → open
    /// Performance → photo never appears because the cache is served and the
    /// refresh is throttled out".
    @AppStorage("perf_lastRefreshTimestamp") private var lastRefreshTimestamp: Double = 0
    private let minRefreshInterval: TimeInterval = 90
    @State private var isPullRefreshInFlight = false
    @State private var isSilentGridRefreshing = false
    private let fullRefreshAfterGridRefreshGap: TimeInterval = 90

    // MARK: - API Polling (continuous watch mode)
    /// Background task that polls the Inject/Custom API every 4–6 s while the view is visible.
    /// When the spectator's selection arrives, updates bio/note and vibrates — no need to re-open the app.
    @State private var apiPollingTask: Task<Void, Never>? = nil
    /// Last change token received from the API for each target ("bio" / "note" / "pp").
    /// First poll only seeds this baseline; later polls trigger only when the token changes.
    @State private var lastApiPollTokens: [String: String] = [:]

    // MARK: - Auto-refresh on Performance entry
    /// Persisted timestamp of the last full profile refresh. Used to decide whether
    /// to auto-refresh silently when the user opens Performance view.
    @AppStorage("perf_lastAutoRefreshTimestamp") private var lastAutoRefreshTimestamp: Double = 0
    private let autoRefreshInterval: TimeInterval = 5 * 60   // 5 minutes

    // MARK: - Inter-reveal cooldown (anti-bot)
    /// Persisted timestamp set after every successful reveal (unarchive+comment).
    /// Prevents back-to-back reveal operations that look automated to Instagram.
    @AppStorage("perf_lastRevealCompletedTimestamp") private var lastRevealCompletedTimestamp: Double = 0
    private let interRevealCooldown: TimeInterval = 90   // seconds

    // MARK: - Post Prediction visual ring
    /// Orange ring appears on the profile avatar after a successful PP reveal.
    /// Persists when the user exits Performance so they see it as confirmation.
    /// Reset to false every time the user opens a new Performance session.
    @AppStorage("postPredRevealRingActive") private var postPredRevealRingActive: Bool = false

    // MARK: - Sub-views (split to help Swift type-checker)

    private var performanceRoot: some View {
        ZStack(alignment: .bottom) {
            // Full-screen white base (status bar + home indicator area)
            Color.white.ignoresSafeArea()
            // profileContent fills the entire screen — the scroll view's internal
            // bottom spacer (94 pt) ensures the last grid row scrolls above the pill.
            // No external bottom padding here so the grid extends all the way down
            // and the glass pill floats over real content, not an empty white gap.
            profileContent
            bottomBar
        }
    }

    @ViewBuilder private var profileContent: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let profile = profile {
                instagramProfileView(profile: profile)
            } else {
                InstagramProfileSkeleton(onPlusPress: { selectedTab = 1 })
            }
            if instagram.isLocked { performanceLockdownOverlay }
            // Show countdown when safety gate has blocked all remote calls and there's
            // no cached profile to display — otherwise the user sees a blank/frozen screen.
            if !performanceRemoteCallsAllowed && profile == nil && safetyGateCountdown > 0 {
                safetyGateWaitingOverlay
            }
            if showFirstTimeBanner { firstTimeBannerOverlay }
        }
    }

    private var firstTimeBannerOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.white)
                Text(String(localized: "perf.first_time_banner"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.82))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.bottom, 90)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var safetyGateWaitingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)
            Text(safetyGateCountdown > 0
                 ? String(format: String(localized: "perf.safety_gate.wait"), safetyGateCountdown)
                 : String(localized: "perf.safety_gate.retrying"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.92))
    }

    @MainActor private func triggerFirstTimeBannerIfNeeded() {
        guard !hasSeenFirstTimeBanner, profile == nil else { return }
        hasSeenFirstTimeBanner = true
        withAnimation(.easeIn(duration: 0.3)) { showFirstTimeBanner = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showFirstTimeBanner = false }
        }
    }

    @ViewBuilder private var spectatorOverlay: some View {
        if isLoadingSpectator {
            Color.white.ignoresSafeArea()
                .overlay(
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.2)
                        Text("Loading profile…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                )
                .zIndex(899)
        }
        if showingHomeScreenIllusion, let screenshot = illusionService.screenshot {
            Image(uiImage: screenshot)
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width,
                       height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.12)) { showingHomeScreenIllusion = false }
                }
                .zIndex(999)
        }
    }

    private var bottomBar: some View {
            InstagramBottomBar(
                profileImageURL: profile?.profilePicURL,
                cachedImage: profile?.profilePicURL != nil ? cachedImages[profile!.profilePicURL] : nil,
                isHome: !showingExplore, isSearch: showingExplore,
                onHomePress: {},
                onSearchPress: {
                    // Capture buffer ONCE before any consumer resets it.
                    // FollowingMagic's captureFromBuffer() calls reset() internally,
                    // which would empty the buffer before ForceReel can read it.
                    let capturedDigits = SecretNumberManager.shared.digitBuffer
                    let capturedNumber = capturedDigits.reduce(0) { $0 * 10 + $1 }

                    if FollowingMagicSettings.shared.isEnabled && !capturedDigits.isEmpty {
                        FollowingMagicSettings.shared.captureFromBuffer(source: "grid")
                    }
                    if ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel && capturedNumber > 0 {
                        ForceReelSettings.shared.pendingPosition = capturedNumber
                        print("🎭 [FORCE] Position captured: \(capturedNumber)")
                        // Buffer may already be reset by FollowingMagic above; only reset if still populated.
                        if SecretNumberManager.shared.hasDigits {
                            SecretNumberManager.shared.reset()
                        }
                    }
                    showingExplore = true
                },
                onReelsPress: {},
                onMessagesPress: {},
                onProfilePress: {},
                showRevealRing: postPredRevealRingActive
        )
    }

    private func instagramProfileView(profile: InstagramProfile) -> some View {
        InstagramProfileView(
            profile: profile,
            cachedImages: $cachedImages,
            onRefresh: loadProfileSync,
            onAsyncRefresh: handlePerformancePullToRefresh,
            onPlusPress: { selectedTab = 1 },
            mediaURLs: allMediaURLs,
            onMediaAppear: loadMoreIfNeeded,
            onAutoFollowedByTap: { handleAutoFollowedByTap() },
            onAddLocalImages: { photos in
                batchInsertRevealURLs(photos)
                print("⚡️ [PERF] \(photos.count) photo(s) pre-inserted instantly as contiguous block — API unarchive in progress")
            },
            onRevealComplete: { revealedPhotos in
                let revealedIds = revealedPhotos.compactMap { item -> String? in
                    guard item.pseudoURL.hasPrefix("reveal://") else { return nil }
                    return String(item.pseudoURL.dropFirst("reveal://".count))
                }
                InstagramSafetyGate.shared.markPostReveal(mediaIds: revealedIds)
                for item in revealedPhotos {
                    if let image = item.image { cachedImages[item.pseudoURL] = image }
                    insertRevealURL(item.pseudoURL)
                }
                if !revealedPhotos.isEmpty {
                    print("⚡️ [PERF] \(revealedPhotos.count) photo(s) inserted from local storage")
                    LogManager.shared.info("Grid updated from local images: \(revealedPhotos.count) photo(s)", category: .general)
                }
                // Mark reveal completion timestamp for inter-reveal anti-bot cooldown.
                // The next reveal (new trick) will be blocked for `interRevealCooldown` seconds.
                lastRevealCompletedTimestamp = Date().timeIntervalSince1970
                lastAutoRefreshTimestamp = Date().timeIntervalSince1970 // suppress auto-refresh too
                // Double full-power vibration (notification-level) — magician confirms photos live on Instagram
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s gap
                    await MainActor.run {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    }
                }
                Task { await refreshMediaGridSilently() }
            },
            onAmnesiaSwapComplete: {
                // InstagramProfileView completed a swap — refresh the grid after a
                // short delay so the new carousel images appear without manual pull-to-refresh.
                Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 s CDN processing
                    await refreshMediaGridSilently()
                    print("🎭 [AMNESIA] Grid auto-refreshed after swap (InstagramProfileView path)")
                }
            },
            mediaItemsByURL: mediaItemsByURL,
            isLoading: isLoading,
            onUploadConflict: { showUploadConflictAlert = true },
            onFollowerTap: { follower in
                withAnimation(.easeInOut(duration: 0.25)) { selectedSpectator = follower }
            },
            onFollowersListDismiss: {
                guard dateForce.isEnabled,
                      !dateForce.selectedFollowerIds.isEmpty,
                      !dateForce.isAutoLoading else { return }
                // Resetea espectadores anteriores para que la nueva selección sea limpia
                if dateForce.hasSpectators { dateForce.resetSpectators() }
                loadAutoFollowers()
            },
            pendingOCRWord: $pendingOCRWord,
            pendingSlotReveal: $pendingSlotReveal,
            pendingCardReveal: $pendingCardReveal,
            pendingLockscreenDigits: $pendingLockscreenDigits,
            onTabSelected: { tab in handleTabSelected(tab) }
        )
    }

    /// Called by InstagramProfileView whenever the Posts/Reels/Tagged tab changes.
    /// Loads reels or tagged content on first tap, without blocking the UI.
    private func handleTabSelected(_ tab: Int) {
        guard let profile else { return }
        switch tab {
        case 1:
            // Allow re-fetch even if reelsLoadedOnce=true when no images are actually
            // visible — this handles the case where iOS purged the Caches/ directory
            // (thumbnails lost) and the CDN URLs expired so re-download also failed.
            let hasReelImages = profile.cachedReelURLs.contains { cachedImages[$0] != nil }
            guard !reelsLoadedOnce || !hasReelImages else { return }
            reelsLoadedOnce = true
            Task { await fetchReelsIfNeeded(for: profile, forceIfNoImages: !hasReelImages) }
        case 2:
            let hasTaggedImages = profile.cachedTaggedURLs.contains { cachedImages[$0] != nil }
            guard !taggedLoadedOnce || !hasTaggedImages else { return }
            taggedLoadedOnce = true
            Task { await fetchTaggedIfNeeded(for: profile, forceIfNoImages: !hasTaggedImages) }
        default:
            break
        }
    }

    /// Schedules a background preload of reels and tagged so they are cached
    /// before the user swipes to those tabs. Safe to call multiple times —
    /// `fetchReelsIfNeeded` and `fetchTaggedIfNeeded` skip when already cached.
    /// Delay is intentionally staggered to avoid competing with the posts
    /// download burst that just finished.
    private func scheduleBackgroundReelsTaggedPreload(for cached: InstagramProfile) {
        // Already both loaded → nothing to do
        let reelsPaginationKey = "reels_paginated_\(cached.userId)"
        let alreadyPaginatedReels = UserDefaults.standard.bool(forKey: reelsPaginationKey)
        let reelsReady = !cached.cachedReelURLs.isEmpty
            && !cached.cachedReelItems.isEmpty
            && !(cached.cachedReelItems.count == 10 && !alreadyPaginatedReels)

        let taggedPaginationKey = "tagged_paginated_\(cached.userId)"
        let alreadyPaginatedTagged = UserDefaults.standard.bool(forKey: taggedPaginationKey)
        let taggedReady = !cached.cachedTaggedURLs.isEmpty
            && !(cached.cachedTaggedURLs.count == 18 && !alreadyPaginatedTagged)

        guard !reelsReady || !taggedReady else {
            print("🎬 [BG] Reels + tagged already cached — skipping preload")
            return
        }
        print("🎬 [BG] Scheduling background preload — reelsReady:\(reelsReady) taggedReady:\(taggedReady)")

        Task { @MainActor in
            // Delay to let the posts download burst settle first (anti-bot)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !instagram.isLocked,
                  !instagram.isSessionChallenged,
                  !instagram.isUploadingProfilePic,
                  instagram.isLoggedIn else {
                print("🚫 [BG] Reels/tagged preload deferred — locked/challenged/uploading")
                return
            }
            guard let current = profile else { return }
            // Use the flag so we don't double-fetch if user swiped to the tab
            // during the 5s sleep and handleTabSelected already started a fetch.
            if !reelsReady && !reelsLoadedOnce {
                print("🎬 [BG] Auto-preloading reels in background…")
                reelsLoadedOnce = true
                await fetchReelsIfNeeded(for: current)
            }
            // Extra pause between reels and tagged (anti-bot)
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_500_000_000...2_500_000_000))
            guard !instagram.isLocked, !instagram.isSessionChallenged else { return }
            guard let current2 = profile else { return }
            if !taggedReady && !taggedLoadedOnce {
                print("🏷️ [BG] Auto-preloading tagged in background…")
                taggedLoadedOnce = true
                await fetchTaggedIfNeeded(for: current2)
            }
        }
    }

    /// Fetches reels for the own profile tab. Safe to call on-demand.
    /// - Parameter forceIfNoImages: when true, re-fetches even if URLs are already
    ///   cached — used when iOS purged the image cache and CDN URLs have expired,
    ///   so a fresh URL set is needed before thumbnails can be re-downloaded.
    @MainActor
    private func fetchReelsIfNeeded(for cached: InstagramProfile, forceIfNoImages: Bool = false) async {
        guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionChallenged else { return }
        guard !instagram.isUploadingProfilePic else { return }
        guard !instagram.shouldUseCacheOnlyForOptionalCalls else {
            let rate = instagram.checkRateLimit()
            print("🛡️ [REELS] Lazy load skipped near rate budget (\(rate.actionsUsed)/55)")
            reelsLoadedOnce = false
            return
        }
        // Re-fetch when:
        //  a) No cache at all (first load)
        //  b) URLs exist but items list is missing (old cache before cachedReelItems was added)
        //  c) Exactly 10 items cached — that was the hard server cap before pagination was added.
        //  d) forceIfNoImages=true: URLs cached but no images visible (e.g. iOS purged Caches/
        //     and CDN URLs expired — fresh URLs are needed so downloads can succeed).
        let reelsPaginationKey = "reels_paginated_\(cached.userId)"
        let alreadyPaginated = UserDefaults.standard.bool(forKey: reelsPaginationKey)
        let looksLikeOldSinglePage = cached.cachedReelItems.count == 10 && !alreadyPaginated
        let needsFetch = cached.cachedReelURLs.isEmpty
                      || cached.cachedReelItems.isEmpty
                      || looksLikeOldSinglePage
                      || forceIfNoImages
        guard needsFetch else {
            print("🎬 [REELS] Already cached (\(cached.cachedReelURLs.count) URLs, \(cached.cachedReelItems.count) items) — skipping fetch")
            return
        }
        if forceIfNoImages {
            print("🎬 [REELS] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🎬 [REELS] Lazy-loading reels for first tab visit…")
        do {
            // Random human-like delay before the new API call.
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserReels(userId: cached.userId, amount: 50)
            let reelURLs = items.map { $0.imageURL }
            var updated = cached
            updated.cachedReelURLs = reelURLs
            updated.cachedReelItems = items
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            // Mark paginated fetch done so we never re-fetch just because count==10
            UserDefaults.standard.set(true, forKey: "reels_paginated_\(cached.userId)")
            // Download thumbnails
            for url in reelURLs where cachedImages[url] == nil {
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            LogManager.shared.info("Reels lazy-loaded: \(reelURLs.count) items", category: .general)
        } catch {
            reelsLoadedOnce = false // allow retry on next tab visit
            print("⚠️ [REELS] Lazy load failed (non-critical): \(error)")
        }
    }

    /// Fetches tagged posts for the own profile tab. Safe to call on-demand.
    /// - Parameter forceIfNoImages: when true, re-fetches even if URLs are already
    ///   cached — used when iOS purged the image cache and CDN URLs have expired.
    @MainActor
    private func fetchTaggedIfNeeded(for cached: InstagramProfile, forceIfNoImages: Bool = false) async {
        guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionChallenged else { return }
        guard !instagram.isUploadingProfilePic else { return }
        guard !instagram.shouldUseCacheOnlyForOptionalCalls else {
            let rate = instagram.checkRateLimit()
            print("🛡️ [TAGGED] Lazy load skipped near rate budget (\(rate.actionsUsed)/55)")
            taggedLoadedOnce = false
            return
        }
        let taggedPaginationKey = "tagged_paginated_\(cached.userId)"
        let taggedAlreadyPaginated = UserDefaults.standard.bool(forKey: taggedPaginationKey)
        let taggedLooksOld = cached.cachedTaggedURLs.count == 18 && !taggedAlreadyPaginated
        guard cached.cachedTaggedURLs.isEmpty || taggedLooksOld || forceIfNoImages else {
            print("🏷️ [TAGGED] Already cached (\(cached.cachedTaggedURLs.count)) — skipping fetch")
            return
        }
        if forceIfNoImages {
            print("🏷️ [TAGGED] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🏷️ [TAGGED] Lazy-loading tagged for first tab visit…")
        do {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserTagged(userId: cached.userId, amount: 50)
            let taggedURLs = items.map { $0.imageURL }
            var updated = cached
            updated.cachedTaggedURLs = taggedURLs
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            UserDefaults.standard.set(true, forKey: "tagged_paginated_\(cached.userId)")
            for url in taggedURLs where cachedImages[url] == nil {
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            LogManager.shared.info("Tagged lazy-loaded: \(taggedURLs.count) items", category: .general)
        } catch {
            taggedLoadedOnce = false
            print("⚠️ [TAGGED] Lazy load failed (non-critical): \(error)")
        }
    }

    // MARK: - OCR modifiers (split out to reduce body complexity for the Swift type-checker)

    private var ocrModifiers: some View {
        ZStack {
            performanceRoot
            spectatorOverlay
        }
            .onChange(of: volumeMonitor.upCount) { _ in
                guard spectatorProfile == nil else {
                    print("📷 [OCR] Blocked — spectator profile is visible")
                    return
                }
                guard !showingExplore else {
                    print("📷 [OCR] Blocked — Explore is open")
                    return
                }
                guard !followingMagic.transferEnabled || followingMagic.transferOffset == 0 else {
                    print("📷 [OCR] Blocked — Transfer offset saved, volume UP reserved for inflation")
                    return
                }
                guard !ocrUsedInSession else {
                    print("📷 [OCR] Blocked — already used once in this Performance session")
                    return
                }
                let noteOcr     = noteTopInputMode == "ocr"
                let bioOcr      = bioTopInputMode  == "ocr"
                let postPredOcr = ppTopInputMode == "ocr"
                guard noteOcr || bioOcr || postPredOcr else { return }
                if ocrCoordinator.isRunning {
                    ocrCoordinator.stop()
                    print("📷 [OCR] Stopped by volume UP (toggle off)")
                } else {
                    let config = OCRConfiguration.fromUserDefaults()
                    ocrCoordinator.start(config: config)
                    print("📷 [OCR] Started by volume UP — note=\(noteOcr) bio=\(bioOcr) postPrediction=\(postPredOcr)")
                }
            }
            .onChange(of: ocrCoordinator.recognizedText) { text in
                guard let text = text, !text.isEmpty else { return }
                print("📷 [OCR] Recognized: \"\(text)\"")

                // INTER-REVEAL COOLDOWN (anti-bot): block reveal if the previous one
                // finished less than `interRevealCooldown` seconds ago. This prevents
                // back-to-back unarchive+comment POST pairs that Instagram flags.
                let timeSinceLastReveal = Date().timeIntervalSince1970 - lastRevealCompletedTimestamp
                if timeSinceLastReveal < interRevealCooldown {
                    let remaining = Int(interRevealCooldown - timeSinceLastReveal)
                    print("🚫 [OCR] Reveal blocked — inter-reveal cooldown active (\(remaining)s remaining)")
                    LogManager.shared.warning("Reveal blocked: cooldown \(remaining)s remaining (anti-bot)", category: .api)
                    return
                }

                // Lock OCR for the rest of this Performance session — one reveal per trick.
                ocrUsedInSession = true
                // Execute all active OCR targets sequentially (bio → note → post prediction)
                // to avoid concurrent API calls that could trigger bot detection.
                Task {
                    let hasBio  = bioTopInputMode  == "ocr"
                    let hasNote = noteTopInputMode == "ocr"
                    let hasPost = ppTopInputMode == "ocr"

                    if hasBio {
                        print("📷 [OCR] Step 1/3 — applying to biography")
                        await applyOCRResult(text: text, target: "bio")
                    }
                    if hasNote {
                        if hasBio {
                            // Brief gap between consecutive API write operations
                            print("📷 [OCR] Waiting 3s before note (anti-bot gap)")
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                        }
                        print("📷 [OCR] Step \(hasBio ? "2" : "1")/\([hasBio, hasNote, hasPost].filter { $0 }.count) — applying to note")
                        await applyOCRResult(text: text, target: "note")
                    }
                    if hasPost {
                        let priorSteps = (hasBio ? 1 : 0) + (hasNote ? 1 : 0)
                        if priorSteps > 0 {
                            print("📷 [OCR] Waiting 3s before post prediction (anti-bot gap)")
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                        }
                        print("📷 [OCR] Step \(priorSteps + 1)/\([hasBio, hasNote, hasPost].filter { $0 }.count) — applying to post prediction")
                        await applyOCRToPostPrediction(text: text)
                    }
                }
            }
    }

    var body: some View {
        ZStack {
            ocrModifiers
            // NOTE: The background full-profile pre-loader has been retired. Performance
            // now loads its profile the same way UserProfileView (from Explore) does:
            // cache first, then one getProfileInfo() call if needed. The 90-second
            // "Getting ready" overlay (FullLoadOverlayView) is no longer rendered.
        }
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
            .preferredColorScheme(.light)
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
            .alert("Error", isPresented: Binding(
                get: { spectatorLoadError != nil },
                set: { if !$0 { spectatorLoadError = nil } }
            )) {
                Button("OK") { spectatorLoadError = nil }
            } message: {
                Text(spectatorLoadError ?? "")
            }
            .alert("Digit Grid Disabled", isPresented: $showDigitGridAlert) {
                Button("Enable") { ForceNumberRevealSettings.shared.gridSwipeEnabled = true }
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text("You have an active number set but Digit Grid input is off. Enable it to unarchive photos by swiping the grid.")
            }
            // Spectator profile: bound to selectedSpectator to avoid the nil→item race
            // condition that caused stale profiles when tapping a second follower.
            .fullScreenCover(item: $selectedSpectator) { follower in
                SpectatorProfileCover(follower: follower, onClose: {
                    selectedSpectator = nil
                })
                .preferredColorScheme(.light)
            }
            .fullScreenCover(isPresented: $showingLockscreen) {
                LockscreenInputView { digits in
                    showingLockscreen = false
                    if !digits.isEmpty {
                        pendingLockscreenDigits = digits
                    }
                    // If fake home screen is also enabled, show it next
                    if fakeHomeScreenEnabled && illusionService.hasImage {
                        showingHomeScreenIllusion = true
                    }
                }
            }
        // selectedSpectator drives fullScreenCover directly — no extra onChange needed.
        // When Explore closes, reset digit buffer (InstagramProfileView's onChange clears followingOverride)
        .onChange(of: showingExplore) { isOpen in
            if !isOpen {
                SecretNumberManager.shared.reset()
            }
        }
        // Instantly show a newly uploaded profile picture without waiting for a CDN URL.
        // HomeView sets this override right after a successful upload; we mirror it into
        // cachedImages under the current profilePicURL key so the header and bottom bar
        // update immediately. The override is cleared on the next full profile refresh.
        .onChange(of: profileCache.pendingProfilePic) { newPic in
            if let pic = newPic {
                // New local pic available — show immediately regardless of CDN state
                guard let url = profile?.profilePicURL, !url.isEmpty else { return }
                cachedImages[url] = pic
                print("⚡️ [PERF] Profile pic updated instantly from local image (no CDN GET needed)")
                LogManager.shared.info("Profile pic shown instantly from local storage", category: .general)
            } else {
                // pendingProfilePic cleared → Instagram CDN confirmed the new picture.
                // Same double full-system vibration as Note and Biography confirmations.
                fireDoubleConfirmationVibration()
                print("📳 [PERF] Double vibration: profile pic confirmed live on Instagram CDN")
                LogManager.shared.info("Profile pic confirmed live on Instagram (double vibration fired)", category: .general)
            }
        }
        // Instantly reflect a biography update in the fake Instagram profile view.
        // changeBiography() saves to ProfileCacheService on success; we pick it up here.
        .onChange(of: profileCache.cachedProfile?.biography) { newBio in
            guard let newBio, !isLoading else { return }
            guard let current = profile, current.biography != newBio else { return }
            profile = InstagramProfile(
                userId: current.userId, username: current.username,
                fullName: current.fullName, biography: newBio,
                externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                isVerified: current.isVerified, isPrivate: current.isPrivate,
                followerCount: current.followerCount, followingCount: current.followingCount,
                mediaCount: current.mediaCount, followedBy: current.followedBy,
                isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                cachedHighlights: current.cachedHighlights,
                cachedMediaItems: current.cachedMediaItems,
                cachedReelItems: current.cachedReelItems,
                cachedNextMaxId: current.cachedNextMaxId
            )
            print("⚡️ [PERF] Biography updated instantly in fake profile (no GET needed)")
            LogManager.shared.info("Biography updated instantly in profile view", category: .general)
        }
        // React to local profile cache changes (archive/unarchive, etc.)
        // without making any extra API call.
        .onChange(of: profileCache.cachedProfile?.cachedMediaURLs) { newURLs in
            guard let newURLs else { return }
            // Only sync if the change came from somewhere else (not from our own full reload)
            guard !isLoading else {
                print("🔄 [PERF] onChange cachedMediaURLs fired but isLoading=true — skipped")
                return
            }
            let currentSet = Set(allMediaURLs)
            let newSet = Set(newURLs)
            guard currentSet != newSet else {
                print("🔄 [PERF] onChange cachedMediaURLs fired — no diff (both \(newURLs.count) items), skipped")
                return
            }
            let removed = currentSet.subtracting(newSet).count
            let added   = newSet.subtracting(currentSet).count
            print("🔄 [PERF] onChange cachedMediaURLs: \(allMediaURLs.count)→\(newURLs.count) (-\(removed) +\(added))")
            if profile == nil, let cached = profileCache.cachedProfile {
                profile = cached
            }
            allMediaURLs = newURLs
            // Keep mediaItemsByURL in sync with the new URL set:
            //   1) Bring in metadata for any newly-arrived URLs from the cached profile.
            //   2) Drop entries whose URLs no longer appear in the grid (avoids leaking
            //      stale CDN URLs that rotated, which left orphan items in the dict).
            //   3) Always preserve reveal:// metadata since those are local-only entries
            //      injected by performance actions, not present in the profile cache.
            if let cachedItems = profileCache.cachedProfile?.cachedMediaItems {
                for item in cachedItems where newSet.contains(item.imageURL) {
                    mediaItemsByURL[item.imageURL] = item
                }
            }
            let urlsToKeep = newSet
            mediaItemsByURL = mediaItemsByURL.filter { key, _ in
                urlsToKeep.contains(key) || key.hasPrefix("reveal://")
            }
            revealDates = revealDates.filter { key, _ in urlsToKeep.contains(key) }
            // Download thumbnails for any new URLs not yet cached
            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty { downloadImagesForURLs(missing) }
            print("🔄 [PERF] Grid updated locally — \(newURLs.count) items (no API call)")
        }
        .onAppear {
            // Reset Post Prediction visual ring — new session starts clean.
            // The ring from the previous trick is cleared so the magician can see
            // a fresh confirmation for the current trick.
            postPredRevealRingActive = false

            // Screen always on — managed globally by MentalGram1App
            // Show fake lockscreen for secret digit entry (one-shot per session).
            // Guard required: onAppear re-fires when fullScreenCover is dismissed,
            // which would instantly re-present the lockscreen in an infinite loop.
            if !lockscreenWasShown && LockscreenInputSettings.shared.isReady {
                lockscreenWasShown = true
                showingLockscreen = true
                print("🔒 [LOCKSCREEN] Showing fake lockscreen for secret input")
            }
            // Show fake home screen if enabled and image is available
            else if fakeHomeScreenEnabled && illusionService.hasImage && !showingLockscreen {
                showingHomeScreenIllusion = true
                print("🏠 [ILLUSION] Fake home screen active — tap to reveal profile")
            }

            // Anti-bot: if a set upload is actively running, pause it while we're here.
            // Parallel API calls (upload POSTs + profile GETs / auto-pic POSTs) from the
            // same session are a strong bot signal.
            // isPausedByPerformance is set immediately so ExploreView search doesn't
            // get blocked during the brief race between requestPause and the loop
            // actually transitioning to .paused.
            if uploadManager.isUploading {
                uploadManager.isPausedByPerformance = true
                uploadManager.preserveWaitOnAutoPause = true
                uploadManager.requestPause = true
                didAutoPauseUpload = true
                print("⏸️ [PERF] Upload paused — entering Performance view (anti-bot)")
                LogManager.shared.warning("Upload auto-paused: Performance view opened", category: .general)
            } else if uploadManager.isActive {
                // Already paused (e.g. user paused manually before entering Performance).
                // Still mark context so Explore search is unrestricted.
                uploadManager.isPausedByPerformance = true
            }

            // Activate volume button detection for FollowingMagic and/or OCR.
            // prepareVolume() warms up the audio session and slider (must run first).
            // startMonitoring() registers the KVO observer that increments upCount/downCount.
            let needsVolume = FollowingMagicSettings.shared.isEnabled
                || noteTopInputMode == "ocr"
                || bioTopInputMode  == "ocr"
                || ppTopInputMode == "ocr"
            if needsVolume {
                VolumeButtonMonitor.shared.prepareVolume()
                VolumeButtonMonitor.shared.startMonitoring()
            }

            // API polling can trigger network calls; keep Performance cache-only
            // while an upload is active/auto-paused to avoid POST+GET overlap.
            if uploadManager.isActive || didAutoPauseUpload {
                print("🛡️ [PERF] API polling skipped — upload active/paused")
                LogManager.shared.warning("Performance API polling skipped: upload active", category: .general)
            } else {
                // API polling: watch Inject/Custom API in background.
                // Vibrates + updates bio/note the moment the spectator's selection arrives.
                startApiPollingIfNeeded()
            }

            let entryDecision: InstagramSafetyGate.PerformanceEntryDecision
            if performanceEntryRecorded {
                entryDecision = InstagramSafetyGate.PerformanceEntryDecision(
                    allowRemoteCalls: performanceRemoteCallsAllowed,
                    waitSeconds: 0,
                    reason: performanceRemoteCallsAllowed ? "" : "existing cache-only safety entry"
                )
            } else {
                entryDecision = InstagramSafetyGate.shared.recordPerformanceEntry()
                performanceRemoteCallsAllowed = entryDecision.allowRemoteCalls
                performanceEntryRecorded = true
            }

            // PRE-FLIGHT: Validate session before any API call.
            // If the session is expired/challenged, isSessionExpired is set to true
            // by validateSession() → SessionGuardView overlay takes over automatically.
            // Network errors are treated as non-blocking (profile loads from cache).
            Task { @MainActor in
                guard !uploadManager.isActive, !didAutoPauseUpload else {
                    print("🛡️ [PERF] Entry remote calls skipped — upload active/paused")
                    LogManager.shared.warning("CACHE ONLY — Performance entry skipped remote calls: upload active", category: .general)
                    checkAndLoadProfile(allowRemote: false)
                    return
                }
                guard entryDecision.allowRemoteCalls else {
                    print("🛡️ [PERF] Cache-only entry — \(entryDecision.reason) (\(entryDecision.waitSeconds)s)")
                    LogManager.shared.warning("CACHE ONLY — Performance entry blocked remote calls: \(entryDecision.reason)", category: .general)
                    checkAndLoadProfile(allowRemote: false)
                    triggerFirstTimeBannerIfNeeded()
                    // If there's no cached profile either, show a countdown + auto-retry
                    // so the user doesn't see a frozen blank screen.
                    if profile == nil && entryDecision.waitSeconds > 0 {
                        safetyGateCountdown = entryDecision.waitSeconds
                        Task { @MainActor in
                            while safetyGateCountdown > 0 {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                safetyGateCountdown = max(0, safetyGateCountdown - 1)
                            }
                            // Auto-retry once the pause expires
                            guard profile == nil else { return }
                            performanceEntryRecorded = false
                            performanceRemoteCallsAllowed = true
                            // Re-validate session and attempt remote load now that the
                            // safety gate has released. Without this the user would stay
                            // on the skeleton forever until they manually leave and re-enter.
                            let status = await instagram.validateSession()
                            guard status == .valid || status == .networkError else {
                                LogManager.shared.warning("Post-countdown remote retry aborted — session \(status)", category: .general)
                                return
                            }
                            checkAndLoadProfile(allowRemote: true)
                        }
                    }
                    return
                }

                let sessionStatus = await instagram.validateSession()
                guard sessionStatus == .valid || sessionStatus == .networkError else {
                    print("🚫 [PERF] Session invalid (\(sessionStatus)) — aborting onAppear actions")
                    return
                }
                checkAndLoadProfile(allowRemote: true)
                triggerFirstTimeBannerIfNeeded()

                // Cold-start guard: during the first ~45s of the app session we do NOT
                // chain a silent grid refresh after validateSession. The 3-endpoint
                // warmup (current_user + feed/user + friendships/followers) is exactly
                // what Instagram fingerprints as automated. The cached grid is shown
                // immediately, and a delayed refresh fires once the window expires.
                if InstagramSafetyGate.shared.isInColdStartWindow {
                    let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
                    print("⏳ [COLD-START] Skipping entry silent refresh — \(remaining)s remaining")
                    LogManager.shared.info("[COLD-START] Entry silent refresh deferred — \(remaining)s", category: .general)
                    // Schedule a single refresh just after the window closes, with a
                    // small extra jitter to avoid landing exactly at t=45s.
                    let delayNs = UInt64(remaining + Int.random(in: 5...10)) * 1_000_000_000
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: delayNs)
                        // Re-check all guards at fire-time, not just at schedule-time.
                        // Critical: if a network timeout or challenge occurred while we
                        // were sleeping (e.g. the /accounts/current_user/ probe timed
                        // out at t+30s), skip the refresh — it would fire into a broken
                        // session and trigger challenge_required on /feed/user/.
                        guard !instagram.isLocked,
                              !instagram.isSessionChallenged,
                              !instagram.isSessionExpired,
                              !instagram.hasRecentApiError,
                              !uploadManager.isActive else {
                            print("⏭️ [COLD-START] Deferred refresh cancelled — session or error state changed while sleeping")
                            LogManager.shared.info("[COLD-START] Deferred refresh cancelled: session/error guard failed at fire-time", category: .general)
                            return
                        }
                        // Also skip if the performance safety gate blocked the most
                        // recent entry into cache-only mode — the grid content was
                        // already served from cache, a network call would just add
                        // risk on top of a potentially rate-limited session.
                        guard performanceRemoteCallsAllowed else {
                            print("⏭️ [COLD-START] Deferred refresh cancelled — performance entry still in cache-only mode")
                            LogManager.shared.info("[COLD-START] Deferred refresh cancelled: performance entry cache-only", category: .general)
                            return
                        }
                        lastAutoRefreshTimestamp = Date().timeIntervalSince1970
                        await refreshMediaGridSilently()
                    }
                    return
                }

                // AUTO-REFRESH: silently update the grid if the profile data is stale
                // (older than 5 minutes) so new posts uploaded in real Instagram appear
                // immediately without the user needing to pull-to-refresh.
                // Skipped if: session challenged, upload active, or a reveal just finished
                // (the reveal's own silent-refresh already covers freshness).
                let timeSinceAutoRefresh = Date().timeIntervalSince1970 - lastAutoRefreshTimestamp
                let timeSinceReveal = Date().timeIntervalSince1970 - lastRevealCompletedTimestamp
                let autoRefreshNeeded = timeSinceAutoRefresh > autoRefreshInterval
                let recentReveal = timeSinceReveal < (interRevealCooldown + 30) // reveal refresh still fresh
                if autoRefreshNeeded && !recentReveal
                    && !instagram.isSessionChallenged
                    && !instagram.isLocked
                    && !uploadManager.isActive {
                    print("🔄 [AUTO-REFRESH] Stale data (\(Int(timeSinceAutoRefresh))s old) — refreshing grid silently")
                    lastAutoRefreshTimestamp = Date().timeIntervalSince1970
                    await refreshMediaGridSilently()
                } else {
                    let reason = !autoRefreshNeeded ? "data fresh (\(Int(timeSinceAutoRefresh))s)"
                               : recentReveal ? "recent reveal (\(Int(timeSinceReveal))s ago)"
                               : instagram.isSessionChallenged ? "session challenged"
                               : instagram.isLocked ? "locked"
                               : "upload active"
                    print("🔄 [AUTO-REFRESH] Skipped — \(reason)")
                }
            }

            // Serialize all auto-actions in a single sequential Task.
            // Running them in parallel creates concurrent API calls from the
            // same session → strong bot signal (especially POST+GET combos).
            Task { @MainActor in
                guard !uploadManager.isActive || didAutoPauseUpload else {
                    print("🛡️ [PERF] Auto-actions skipped — upload active/paused")
                    LogManager.shared.warning("SAFETY BLOCK — Performance auto-actions skipped: upload active", category: .general)
                    return
                }
                // Abort auto-actions if session is expired (validateSession above already
                // set isSessionExpired = true and the overlay is showing).
                guard performanceRemoteCallsAllowed else {
                    print("🛡️ [PERF] Auto-actions skipped — cache-only safety entry")
                    LogManager.shared.warning("SAFETY BLOCK — Performance auto-actions skipped in cache-only mode", category: .general)
                    return
                }
                guard !instagram.isSessionExpired else {
                    print("🚫 [PERF] Auto-actions skipped — session expired")
                    return
                }
                // 1. Auto profile pic (POST) — wait for loadProfile to finish first
                if autoProfilePicOnPerformance {
                    // Cold-start guard: defer the POST until the window closes so it
                    // doesn't stack on top of the entry GETs (POST+GET combos are a
                    // strong bot signal).
                    if InstagramSafetyGate.shared.isInColdStartWindow {
                        let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
                        print("⏳ [COLD-START] Auto profile pic deferred — \(remaining)s remaining")
                        LogManager.shared.info("[COLD-START] Auto profile pic deferred — \(remaining)s", category: .general)
                        try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 4...8)) * 1_000_000_000)
                    } else {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                    guard !instagram.isLocked, !instagram.isSessionChallenged else {
                        print("📷 [AUTO PIC] Skipped in serial queue — locked or challenged")
                        return
                    }
                    await autoUploadLatestGalleryPhoto()
                }

                // 2. URL scheme action OR clipboard (API mode is handled only by polling).
                // The polling baseline prevents old Inject/API values from firing on app launch.
                if let action = urlAction.consume() {
                    if action.mode.hasPrefix("profilepic") {
                        await applyURLProfilePicAction(mode: action.mode, data: action.text)
                    } else {
                        await applyURLAction(mode: action.mode, text: action.text)
                    }
                } else if clipboardAutoMode != "" {
                    await applyClipboardAutoMode()
                }
            }
            ocrUsedInSession = false

            // Show a nudge if Post Prediction is enabled with an active number set
            // but Digit Grid input is off — and this is NOT a URL scheme reveal
            // (URL reveals supply the word directly so no grid is needed).
            let hasNumberSet = ActiveSetSettings.shared.activeNumberSetId != nil
            let isURLReveal  = urlAction.pendingMode == "reveal"
                            || urlAction.pendingMode == "reveal_slot"
                            || urlAction.pendingMode == "reveal_card"
            if forceRevealSettings.isEnabled,
               !forceRevealSettings.gridSwipeEnabled,
               hasNumberSet,
               !isURLReveal {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showDigitGridAlert = true
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            // Pause / resume full-profile pre-loader with app lifecycle.
            switch phase {
            case .background, .inactive:
                if fullLoader.isBlockingPerformance { fullLoader.pause() }
            case .active:
                if fullLoader.isBlockingPerformance { fullLoader.startOrResume() }
            @unknown default: break
            }

            // Auto-recovery: when the app returns from background while locked,
            // probe the Instagram session. If the user dismissed the challenge in
            // the real Instagram app, the probe succeeds → unlock immediately.
            // If the session is truly expired → trigger the re-login sheet.
            guard phase == .active, instagram.isLocked else { return }
            // ANTI-BOT: Deduplicate probes. Rapid minimize/foreground cycles
            // would otherwise queue multiple probe Tasks running concurrently.
            guard !probeInFlight else {
                print("ℹ️ [RECOVERY] Probe already in flight — skipping duplicate")
                return
            }
            probeInFlight = true
            Task { @MainActor in
                defer { probeInFlight = false }
                // Brief wait so the app fully re-enters foreground
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard instagram.isLocked else { return } // already cleared by timer
                print("🔍 [RECOVERY] App foregrounded during lockdown — probing session...")
                LogManager.shared.info("Session probe triggered on foreground (lockdown active)", category: .general)
                let ok = await instagram.probeSession()
                if ok {
                    instagram.unlock()
                    instagram.isSessionChallenged = false
                    print("✅ [RECOVERY] Session valid — lockdown cleared automatically")
                    LogManager.shared.info("Lockdown auto-cleared: session probe passed after foreground", category: .general)
                } else {
                    // Session still challenged or expired — escalate to re-login if lockUntil passed
                    if let until = instagram.lockUntil, Date() > until {
                        print("🔴 [RECOVERY] Session probe failed after lockdown expired — escalating to re-login")
                        LogManager.shared.warning("Session probe failed post-lockdown — session may be expired", category: .general)
                        instagram.isSessionExpired = true
                    } else {
                        print("ℹ️ [RECOVERY] Session probe failed — lockdown still active, waiting for timer")
                    }
                }
            }
        }
        // URL scheme arriving while PerformanceView is already visible (tab 0 already selected).
        // onAppear won't fire in that case, so we consume the action here directly.
        .onChange(of: urlAction.pendingMode) { mode in
            guard !mode.isEmpty else { return }
            Task { @MainActor in
                guard let action = urlAction.consume() else { return }
                guard !instagram.isSessionExpired else { return }
                print("📲 [URL] Consuming in-view action: \(action.mode)")
                if action.mode.hasPrefix("profilepic") {
                    await applyURLProfilePicAction(mode: action.mode, data: action.text)
                } else {
                    await applyURLAction(mode: action.mode, text: action.text)
                }
            }
        }
        // ── Progressive: "Followed by ..." row ───────────────────────────────
        // Arrives right after the first call of the own-profile chain. Painting
        // it immediately makes the avatar row look "alive" while posts load.
        .onReceive(NotificationCenter.default.publisher(for: .ownProfileFollowedByReady)) { note in
            guard let followers = note.userInfo?["followedBy"] as? [InstagramFollower],
                  !followers.isEmpty else { return }
            guard var current = profile else { return }
            // Mutate via re-init because the struct's `followedBy` is `let`.
            let updated = InstagramProfile(
                userId: current.userId, username: current.username, fullName: current.fullName,
                biography: current.biography, externalUrl: current.externalUrl,
                profilePicURL: current.profilePicURL, isVerified: current.isVerified,
                isPrivate: current.isPrivate, followerCount: current.followerCount,
                followingCount: current.followingCount, mediaCount: current.mediaCount,
                followedBy: followers,
                isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                cachedHighlights: current.cachedHighlights,
                cachedMediaItems: current.cachedMediaItems,
                cachedReelItems: current.cachedReelItems,
                cachedNextMaxId: current.cachedNextMaxId
            )
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            print("⚡ [PERF] Progressive: followedBy row painted (\(followers.count))")

            // Download follower thumbnails eagerly so the row doesn't ghost.
            Task { @MainActor in
                for follower in followers {
                    guard let urlStr = follower.profilePicURL, !urlStr.isEmpty,
                          cachedImages[urlStr] == nil else { continue }
                    if let img = await downloadImage(from: urlStr) {
                        cachedImages[urlStr] = img
                        ProfileCacheService.shared.saveImage(img, forURL: urlStr)
                    }
                }
            }
            _ = current  // silence unused-write warning
        }
        // ── Progressive: posts grid ──────────────────────────────────────────
        // Posts grid arrives mid-chain, ~3-4s after entering Performance. Drop
        // them straight into the UI so the user sees thumbnails immediately
        // (same behaviour as a real Instagram profile that pops in row-by-row).
        .onReceive(NotificationCenter.default.publisher(for: .ownProfileMediaReady)) { note in
            guard let mediaItems = note.userInfo?["mediaItems"] as? [InstagramMediaItem],
                  !mediaItems.isEmpty else { return }
            let nextCursor = note.userInfo?["nextMaxId"] as? String
            guard var current = profile else { return }
            let mediaURLs = mediaItems.map { $0.imageURL }

            let updated = InstagramProfile(
                userId: current.userId, username: current.username, fullName: current.fullName,
                biography: current.biography, externalUrl: current.externalUrl,
                profilePicURL: current.profilePicURL, isVerified: current.isVerified,
                isPrivate: current.isPrivate, followerCount: current.followerCount,
                followingCount: current.followingCount,
                mediaCount: current.mediaCount > 0 ? current.mediaCount : mediaURLs.count,
                followedBy: current.followedBy,
                isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                cachedAt: current.cachedAt,
                cachedMediaURLs: mediaURLs,
                cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                cachedHighlights: current.cachedHighlights,
                cachedMediaItems: mediaItems,
                cachedReelItems: current.cachedReelItems,
                cachedNextMaxId: nextCursor ?? current.cachedNextMaxId
            )
            profile = updated
            allMediaURLs = mediaURLs
            if nextMaxId == nil { nextMaxId = nextCursor }
            hasMorePages = true
            // Seed mediaItemsByURL for the post viewer (likes/comments/date).
            for item in mediaItems { mediaItemsByURL[item.imageURL] = item }
            ProfileCacheService.shared.saveProfile(updated)
            print("⚡ [PERF] Progressive: posts grid painted (\(mediaURLs.count) items)")
            LogManager.shared.info("Performance painted progressive grid — \(mediaURLs.count) posts before chain finished", category: .general)
            loadCachedImages()
            _ = current
        }
        // ── Progressive header render ─────────────────────────────────────────
        // `InstagramService.getProfileInfo` posts this for own profile as soon as
        // the header is ready (after fast-path / web_profile_info), BEFORE the
        // heavy 5-call chain (followers + media + reels + tagged + highlights ≈ 10s).
        // Paint username, profile pic and counters immediately so the user is not
        // staring at the skeleton while the anti-bot sleeps run.
        .onReceive(NotificationCenter.default.publisher(for: .ownProfileHeaderReady)) { note in
            guard let snapshot = note.userInfo?["snapshot"] as? InstagramProfile else { return }
            // Only adopt the snapshot when our current profile is missing the
            // header that the snapshot brings — otherwise we'd flicker counts.
            let needsHeader = (profile == nil)
                || (profile?.username.isEmpty ?? true)
                || (profile?.profilePicURL.isEmpty ?? true)
                || ((profile?.followerCount ?? 0) == 0 && snapshot.followerCount > 0)
                || ((profile?.followingCount ?? 0) == 0 && snapshot.followingCount > 0)
                || ((profile?.mediaCount ?? 0) == 0 && snapshot.mediaCount > 0)

            if needsHeader {
                // Preserve any media that is already in `profile` so the user
                // doesn't lose the grid he is looking at right now.
                var merged = snapshot
                if let current = profile {
                    if merged.cachedMediaURLs.isEmpty { merged.cachedMediaURLs = current.cachedMediaURLs }
                    if merged.cachedMediaItems.isEmpty { merged.cachedMediaItems = current.cachedMediaItems }
                    if merged.cachedReelURLs.isEmpty { merged.cachedReelURLs = current.cachedReelURLs }
                    if merged.cachedReelItems.isEmpty { merged.cachedReelItems = current.cachedReelItems }
                    if merged.cachedTaggedURLs.isEmpty { merged.cachedTaggedURLs = current.cachedTaggedURLs }
                    if merged.cachedHighlights.isEmpty { merged.cachedHighlights = current.cachedHighlights }
                    if merged.cachedNextMaxId == nil { merged.cachedNextMaxId = current.cachedNextMaxId }
                }
                profile = merged
                allMediaURLs = merged.cachedMediaURLs
                print("⚡ [PERF] Header snapshot adopted — @\(merged.username) followers:\(merged.followerCount) (grid kept: \(merged.cachedMediaURLs.count))")
                LogManager.shared.info("Performance painted progressive header — heavy chain still running in background", category: .general)
                loadCachedImages()
            } else {
                print("⚡ [PERF] Header snapshot ignored — current profile already has fresher header")
            }
        }
        // ── ExploreView secret-input word reveal completed ───────────────────
        // ExploreView posts this when a latest-follower / search-bar reveal finishes.
        // We insert the photos into the fake grid (smooth, no full reload), show the
        // profile ring, fire double strong vibration, and schedule a silent CDN refresh.
        .onReceive(NotificationCenter.default.publisher(for: .exploreWordRevealComplete)) { note in
            guard let mediaIds = note.userInfo?["mediaIds"] as? [String], !mediaIds.isEmpty else { return }

            // Build (pseudoURL, localImage) pairs from DataManager local storage
            let allSetPhotos = DataManager.shared.sets.flatMap { $0.photos }
            let photoItems: [(pseudoURL: String, image: UIImage?)] = mediaIds.compactMap { mediaId in
                guard allSetPhotos.contains(where: { $0.mediaId == mediaId }) else { return nil }
                let photo = allSetPhotos.first(where: { $0.mediaId == mediaId })
                let image = photo?.imageData.flatMap { UIImage(data: $0) }
                return (pseudoURL: "reveal://\(mediaId)", image: image)
            }

            // Insert photos as a contiguous block — same path as OCR/API reveals
            if !photoItems.isEmpty {
                batchInsertRevealURLs(photoItems)
                print("⚡️ [PERF] Explore reveal: \(photoItems.count) photo(s) inserted into grid from ExploreView")
            }

            // Profile ring
            postPredRevealRingActive = true

            // Double full-power vibration (same pattern as OCR/API reveal)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
            }

            // Silent CDN refresh after a delay so real Instagram CDN URLs replace placeholders
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 s — let Instagram process
                await refreshMediaGridSilently()
                print("🔄 [PERF] Silent CDN refresh after Explore word reveal")
            }
        }
        .onDisappear {
            // Reset one-shot flags so they fire again on the next entry into Performance
            lockscreenWasShown = false
            performanceEntryRecorded = false

            // Stop volume monitoring and OCR when leaving Performance
            print("🎩 [TRANSFER] PerformanceView.onDisappear — stopping monitoring (transferOffset:\(FollowingMagicSettings.shared.transferOffset))")
            VolumeButtonMonitor.shared.stopMonitoring()
            ocrCoordinator.stop()
            stopApiPolling()

            // Clear the performance-context pause flag regardless of how we got here.
            uploadManager.isPausedByPerformance = false

            // Anti-bot: if we auto-paused an upload on appear, signal SetDetailView to resume it.
            // Only resume if the upload is still in .paused state (user didn't cancel/error).
            if didAutoPauseUpload && uploadManager.isPaused {
                uploadManager.autoResumePending = true
                print("▶️ [PERF] Leaving Performance — signalling upload to auto-resume")
                LogManager.shared.info("Upload auto-resume pending: leaving Performance view", category: .general)
            }
            didAutoPauseUpload = false
        }
    }
    
    // MARK: - URL Scheme Profile Pic Action

    /// Handles vault://profilepic in its three variants.
    private func applyURLProfilePicAction(mode: String, data: String) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [URL PIC] Not logged in or lockdown active — skipping")
            return
        }

        print("📲 [URL PIC] Handling mode=\(mode)")
        LogManager.shared.info("URL scheme profile pic action: \(mode)", category: .general)

        var imageData: Data?

        switch mode {
        case "profilepic_last":
            // Reuse existing logic but force upload (ignore asset-ID duplicate check)
            let authorized = await requestPhotosPermissionIfNeeded()
            guard authorized else {
                print("📷 [URL PIC] No Photos permission")
                return
            }
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: .image, options: fetchOptions).firstObject else {
                print("📷 [URL PIC] Gallery empty")
                return
            }
            imageData = await loadImageData(from: asset)

        case "profilepic_clipboard":
            guard let clipImage = UIPasteboard.general.image else {
                print("📋 [URL PIC] No image in clipboard")
                return
            }
            imageData = resizeAndCompress(clipImage, maxDimension: 512, quality: 0.75)

        case "profilepic_base64":
            guard !data.isEmpty,
                  let decoded = Data(base64Encoded: data, options: .ignoreUnknownCharacters),
                  let img = UIImage(data: decoded) else {
                print("❌ [URL PIC] Invalid base64 image data")
                return
            }
            // Vault handles resize + compress — the sender doesn't need to do anything
            imageData = resizeAndCompress(img, maxDimension: 512, quality: 0.75)
            print("📲 [URL PIC] Base64 decoded: \(decoded.count / 1024) KB → \((imageData?.count ?? 0) / 1024) KB after resize")

        default:
            print("⚠️ [URL PIC] Unknown mode: \(mode)")
            return
        }

        guard let finalData = imageData else {
            print("❌ [URL PIC] Could not prepare image data")
            return
        }

        do {
            let success = try await instagram.changeProfilePicture(imageData: finalData)
            if success, let uiImage = UIImage(data: finalData) {
                let picURL = profile?.profilePicURL ?? "urlpic_pending"
                await MainActor.run {
                    cachedImages[picURL] = uiImage
                    ProfileCacheService.shared.pendingProfilePic = uiImage
                }
                print("✅ [URL PIC] Profile picture updated via URL scheme (\(mode))")
                LogManager.shared.success("Profile pic updated via URL scheme (\(mode))", category: .general)
            }
        } catch {
            print("⚠️ [URL PIC] Upload failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme profile pic failed: \(error.localizedDescription)", category: .general)
        }
    }

    /// Resizes a UIImage to fit within maxDimension×maxDimension and compresses to JPEG.
    private func resizeAndCompress(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Template Helper

    /// Normalises any supported line-break representation into a real `\n` character.
    ///
    /// Supported inputs (in order of precedence):
    ///   `{newline}`  — named token (easiest to type in URL fields)
    ///   `{br}`       — short alias
    ///   `<br>` / `<br/>` / `<br />` — HTML tags (some automation tools emit these)
    ///   `%0A` / `%0a` — raw un-decoded percent sequence (defensive fallback)
    ///   `\r\n`       — Windows CRLF (from tools that send %0D%0A)
    ///   `\r`         — standalone carriage return
    ///   `\n` (literal backslash-n) — the in-app template escape
    private func expandEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "{newline}", with: "\n")
            .replacingOccurrences(of: "{br}",      with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>",  with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br>",   with: "\n", options: .caseInsensitive)
            // Defensive: raw %0A in case URLComponents did not percent-decode the value
            .replacingOccurrences(of: "%0A", with: "\n", options: .caseInsensitive)
            // Normalise Windows-style CRLF and standalone CR before the \n pass
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            // Literal backslash-n (the in-app template escape, must be last)
            .replacingOccurrences(of: "\\n",  with: "\n")
    }

    /// Replaces `{word}` in `template` with the detected/fetched word, then expands
    /// `\n` / `{newline}` escapes into real line-breaks so multi-line bios/notes work.
    /// Returns `word` (with escapes expanded) when the template is empty or has no token.
    private func applyTemplate(_ word: String, template: String) -> String {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || !t.contains("{word}") {
            return expandEscapes(word)
        }
        return expandEscapes(t.replacingOccurrences(of: "{word}", with: word))
    }

    // MARK: - URL Scheme Action

    private func applyURLAction(mode: String, text: String) async {
        guard !instagram.isLocked else {
            print("🚫 [URL] Lockdown active — skipping URL action")
            return
        }
        print("📲 [URL] Executing action=\(mode), text=\"\(text.prefix(40))\"")
        LogManager.shared.info("URL scheme action: \(mode) — \"\(text.prefix(40))\"", category: .general)

        // ── Word reveal via vault://reveal?word= ─────────────────────────────
        if mode == "reveal" {
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return }
            print("📲 [URL] Reveal word: \"\(word)\"")
            LogManager.shared.info("URL reveal → word: \"\(word)\"", category: .general)
            // Mark as URL-triggered so the OCR handler skips the ocrEnabled guard
            await MainActor.run {
                ForceNumberRevealSettings.shared.urlRevealActive = true
                pendingOCRWord = word
            }
            return
        }

        // ── Custom Set reveal via vault://reveal?slot= ────────────────────────
        if mode == "reveal_slot" {
            guard let slot = Int(text), (1...100).contains(slot) else {
                print("⚠️ [URL] Invalid slot value: \"\(text)\"")
                return
            }
            guard let activeId = ActiveSetSettings.shared.activeCustomSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .custom }) else {
                print("🚫 [URL] Custom slot reveal: no active custom set")
                LogManager.shared.warning("URL custom reveal: no active custom set", category: .general)
                return
            }
            if UploadManager.shared.isActive && !didAutoPauseUpload {
                print("⚠️ [URL] Custom slot reveal blocked: upload is active and not paused by Performance")
                return
            }
            print("📲 [URL] Custom slot reveal: slot=\(slot) from '\(activeSet.name)'")
            LogManager.shared.info("URL reveal → custom slot \(slot) from '\(activeSet.name)'", category: .general)
            await MainActor.run { pendingSlotReveal = slot }
            return
        }

        // ── Playing Card reveal via vault://reveal?card= ──────────────────────
        if mode == "reveal_card" {
            let symbol = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symbol.isEmpty else { return }
            guard let activeId = ActiveSetSettings.shared.activeCardSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) else {
                print("🚫 [URL] Card reveal: no active card set")
                LogManager.shared.warning("URL card reveal: no active card set", category: .general)
                return
            }
            guard SetType.cardSlotLabels.contains(symbol) else {
                print("⚠️ [URL] Card reveal: '\(symbol)' is not a valid card symbol")
                return
            }
            if UploadManager.shared.isActive && !didAutoPauseUpload {
                print("⚠️ [URL] Card reveal blocked: upload is active and not paused by Performance")
                return
            }
            print("📲 [URL] Card reveal: \(symbol) from '\(activeSet.name)'")
            LogManager.shared.info("URL reveal → card \(symbol) from '\(activeSet.name)'", category: .general)
            await MainActor.run { pendingCardReveal = symbol }
            return
        }

        do {
            // Expand \n / {newline} escapes so line breaks work from URL schemes too
            let expanded = expandEscapes(text)
            if mode == "note" {
                let final = truncateAtWordBoundary(expanded, limit: 60)
                if final.count < expanded.count {
                    print("✂️ [URL] Note truncated: \(expanded.count)→\(final.count) chars")
                }
                // Optimistic: show note bubble immediately
                await MainActor.run { lastNoteText = final }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [URL] Note sent via URL scheme")
                    LogManager.shared.success("Note sent via URL scheme (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            } else if mode == "bio" {
                let final = truncateAtWordBoundary(expanded, limit: 150)
                if final.count < expanded.count {
                    print("✂️ [URL] Bio truncated: \(expanded.count)→\(final.count) chars")
                }
                // Optimistic: show bio immediately
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights,
                            cachedMediaItems: current.cachedMediaItems,
                            cachedReelItems: current.cachedReelItems,
                            cachedNextMaxId: current.cachedNextMaxId
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    print("✅ [URL] Biography updated via URL scheme")
                    LogManager.shared.success("Biography updated via URL scheme (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [URL] Action failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme action failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Clipboard Auto-Mode

    private func applyClipboardAutoMode() async {
        guard clipboardAutoMode == "note" || clipboardAutoMode == "bio" else { return }
        guard !instagram.isLocked else {
            print("🚫 [CLIPBOARD] Lockdown active — skipping clipboard auto-mode")
            return
        }
        // Cold-start guard: clipboard often contains stale text from before the
        // app was opened. Defer until the window closes so a stale note/bio
        // POST doesn't fire right on top of the entry GETs.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] Clipboard auto-mode deferred — \(remaining)s remaining")
            LogManager.shared.info("[COLD-START] Clipboard auto-mode deferred — \(remaining)s", category: .general)
            try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 3...6)) * 1_000_000_000)
            guard !instagram.isLocked, !instagram.isSessionChallenged else { return }
        }

        // Read clipboard text
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            print("📋 [CLIPBOARD] Clipboard is empty — nothing to send")
            return
        }

        // Avoid re-sending the same text on repeated Performance opens
        guard text != clipboardAutoLastSent else {
            print("📋 [CLIPBOARD] Same text as last send — skipping (\"\(text.prefix(30))…\")")
            return
        }

        print("📋 [CLIPBOARD] Auto-mode=\(clipboardAutoMode), text=\"\(text.prefix(40))\"")
        LogManager.shared.info("Clipboard auto-mode triggered (\(clipboardAutoMode)): \"\(text.prefix(40))\"", category: .general)

        do {
            if clipboardAutoMode == "note" {
                let composed = applyTemplate(text, template: noteTemplate)
                let final = truncateAtWordBoundary(composed, limit: 60)
                if final.count < composed.count {
                    print("✂️ [CLIPBOARD] Note truncated at word boundary: \(composed.count)→\(final.count) chars")
                }
                // Optimistic: show note bubble immediately
                await MainActor.run { lastNoteText = final }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    clipboardAutoLastSent = text  // track original clipboard text to avoid re-sends
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [CLIPBOARD] Note sent from clipboard")
                    LogManager.shared.success("Auto-note sent from clipboard (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            } else {
                let composed = applyTemplate(text, template: bioTemplate)
                let final = truncateAtWordBoundary(composed, limit: 150)
                if final.count < composed.count {
                    print("✂️ [CLIPBOARD] Biography truncated at word boundary: \(composed.count)→\(final.count) chars")
                }
                // Optimistic: show bio immediately
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights,
                            cachedMediaItems: current.cachedMediaItems,
                            cachedReelItems: current.cachedReelItems,
                            cachedNextMaxId: current.cachedNextMaxId
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    clipboardAutoLastSent = text  // track original clipboard text to avoid re-sends
                    print("✅ [CLIPBOARD] Biography updated from clipboard")
                    LogManager.shared.success("Auto-bio updated from clipboard (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [CLIPBOARD] Auto-mode error: \(error.localizedDescription)")
            LogManager.shared.warning("Clipboard auto-mode failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Magic API Auto-Mode

    /// Fetches a value from the configured API source and applies it as note or biography.
    private func applyApiAutoMode(target: String, preloadedValue: String? = nil) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [API AUTO] Lockdown active or not logged in — skipping")
            return
        }
        // Cold-start guard: if a fresh value arrives during the first 45s the
        // POST (createNote / changeBiography) would stack on top of the entry
        // GETs and trigger challenge_required. Wait until the window closes.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] API auto-mode (\(target)) deferred — \(remaining)s remaining")
            LogManager.shared.info("[COLD-START] API auto-mode (\(target)) deferred — \(remaining)s", category: .general)
            try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 3...6)) * 1_000_000_000)
            guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionChallenged else { return }
        }

        let source = target == "note" ? integrations.noteApiSource : integrations.bioApiSource
        guard source != .none else { return }

        let text: String
        if let preloaded = preloadedValue, !preloaded.isEmpty {
            text = preloaded
            print("⚡ [API AUTO] Using preloaded value for target=\(target): \"\(text.prefix(40))\"")
        } else {
            print("⚡ [API AUTO] Fetching from \(source.displayName) for target=\(target)…")
            guard let fetched = await integrations.fetchValue(for: source), !fetched.isEmpty else {
                print("⚠️ [API AUTO] No value received from \(source.displayName)")
                LogManager.shared.warning("Magic API returned no value (\(source.displayName))", category: .general)
                return
            }
            text = fetched
        }

        // Skip if same value was already sent within 2 hours — avoids Instagram duplicate spam rejection
        let ud = UserDefaults.standard
        let lastKey   = target == "note" ? "last_note_auto_input"      : "last_biography_text"
        let dateKey   = target == "note" ? "last_note_auto_sent_date"  : "last_biography_sent_date"
        let trimmed   = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
            let sentDate   = ud.object(forKey: dateKey) as? Date ?? .distantPast
            let hoursSince = Date().timeIntervalSince(sentDate) / 3600
            if hoursSince < 2 {
                print("⏭️ [API AUTO] Dedup: same text sent \(String(format: "%.0f", hoursSince * 60))m ago — skipping (\"\(text.prefix(30))\")")
                return
            }
            print("⏭️ [API AUTO] Dedup expired (\(String(format: "%.1f", hoursSince))h) — allowing re-send")
            ud.removeObject(forKey: lastKey)
        }

        print("⚡ [API AUTO] Got value: \"\(text.prefix(40))\" — applying to \(target)")
        LogManager.shared.info("Magic API (\(source.displayName)) → \(target): \"\(text.prefix(40))\"", category: .general)

        // Apply text template ({word} → fetched word)
        let tpl = target == "note" ? noteTemplate : bioTemplate
        let composed = applyTemplate(text, template: tpl)
        if tpl.contains("{word}") {
            print("⚡ [API AUTO] Template applied (\(target)): \"\(composed.prefix(60))\"")
        }

        do {
            if target == "note" {
                let final = truncateAtWordBoundary(composed, limit: 60)
                // Optimistic: show note bubble immediately, before API confirms
                await MainActor.run { lastNoteText = final }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    print("✅ [API AUTO] Note sent: \"\(final)\"")
                    ud.set(trimmed, forKey: lastKey)          // raw text for dedup
                    ud.set(Date(), forKey: dateKey)           // timestamp so dedup expires in 2h
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    fireDoubleConfirmationVibration()
                }
            } else {
                let final = truncateAtWordBoundary(composed, limit: 150)
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights,
                            cachedMediaItems: current.cachedMediaItems,
                            cachedReelItems: current.cachedReelItems,
                            cachedNextMaxId: current.cachedNextMaxId
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    print("✅ [API AUTO] Biography updated: \"\(final)\"")
                    ud.set(trimmed, forKey: lastKey)          // raw text for dedup
                    ud.set(Date(), forKey: dateKey)           // timestamp so dedup expires in 2h
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [API AUTO] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("Magic API auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
            // If Instagram says "already sent", mark as sent so we stop retrying it
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already sent") || msg.contains("duplicate") {
                ud.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: lastKey)
                print("⏭️ [API AUTO] Marked as already sent to prevent future retries")
            }
        }
    }

    // MARK: - API Polling

    /// Starts polling the Inject/Custom API every ~2 s while PerformanceView is visible.
    /// Triggers bio/note update + vibration, and Post Prediction word reveal, the moment
    /// a new value arrives from the spectator.
    private func startApiPollingIfNeeded() {
        let bioActive  = integrations.bioApiSource  != .none && bioTopInputMode  == "api"
        let noteActive = integrations.noteApiSource != .none && noteTopInputMode == "api"
        let ppActive   = integrations.ppApiSource   != .none && ppTopInputMode   == "api"
        guard bioActive || noteActive || ppActive else { return }
        guard apiPollingTask == nil else { return }

        print("🔔 [API POLL] Starting — bio=\(bioActive) note=\(noteActive) pp=\(ppActive) interval=2s")
        apiPollingTask = Task { @MainActor in
            await seedApiPollingBaselines(bioActive: bioActive, noteActive: noteActive, ppActive: ppActive)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionExpired else { continue }

                // ── bio / note ────────────────────────────────────────────────
                for target in ["bio", "note"] {
                    let source = target == "note" ? integrations.noteApiSource : integrations.bioApiSource
                    let mode   = target == "note" ? noteTopInputMode : bioTopInputMode
                    guard source != .none, mode == "api" else { continue }

                    guard let payload = await integrations.fetchPayload(for: source) else { continue }
                    let newValue = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !newValue.isEmpty else { continue }

                    let tokenKey = "\(target):\(source.rawValue)"
                    if lastApiPollTokens[tokenKey] == nil {
                        lastApiPollTokens[tokenKey] = payload.changeToken
                        print("🔔 [API POLL] Baseline for \(target) seeded — waiting for fresh change")
                        LogManager.shared.info("API poll baseline seeded for \(target); waiting for fresh input", category: .general)
                        continue
                    }
                    guard payload.changeToken != lastApiPollTokens[tokenKey] else { continue }

                    lastApiPollTokens[tokenKey] = payload.changeToken
                    print("🔔 [API POLL] New value for \(target): \"\(newValue.prefix(40))\"")
                    LogManager.shared.info("API poll detected new \(target): \"\(newValue.prefix(40))\"", category: .general)
                    await applyApiAutoMode(target: target, preloadedValue: newValue)
                }

                // ── Post Prediction word reveal ───────────────────────────────
                guard integrations.ppApiSource != .none, ppTopInputMode == "api" else { continue }
                guard let ppPayload = await integrations.fetchPayload(for: integrations.ppApiSource) else { continue }
                let ppValue = ppPayload.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ppValue.isEmpty else { continue }

                let ppTokenKey = "pp:\(integrations.ppApiSource.rawValue)"
                if lastApiPollTokens[ppTokenKey] == nil {
                    lastApiPollTokens[ppTokenKey] = ppPayload.changeToken
                    print("🔔 [API POLL] Baseline for pp seeded — waiting for fresh change")
                    LogManager.shared.info("API poll baseline seeded for pp; waiting for fresh input", category: .general)
                    continue
                }
                guard ppPayload.changeToken != lastApiPollTokens[ppTokenKey] else { continue }

                lastApiPollTokens[ppTokenKey] = ppPayload.changeToken
                let word = ppValue.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🔔 [API POLL] New PP word: \"\(word.prefix(40))\"")
                LogManager.shared.info("API poll detected new PP word: \"\(word.prefix(40))\"", category: .general)
                // Route through the same path as URL scheme reveals
                ForceNumberRevealSettings.shared.urlRevealActive = true
                pendingOCRWord = word
            }
        }
    }

    private func seedApiPollingBaselines(bioActive: Bool, noteActive: Bool, ppActive: Bool) async {
        let targets: [(key: String, source: ApiSource)] = [
            noteActive ? ("note", integrations.noteApiSource) : nil,
            bioActive ? ("bio", integrations.bioApiSource) : nil,
            ppActive ? ("pp", integrations.ppApiSource) : nil
        ].compactMap { $0 }

        for target in targets where target.source != .none {
            guard let payload = await integrations.fetchPayload(for: target.source) else { continue }
            let value = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let tokenKey = "\(target.key):\(target.source.rawValue)"
            lastApiPollTokens[tokenKey] = payload.changeToken
            print("🔔 [API POLL] Baseline for \(target.key) seeded immediately — waiting for fresh change")
            LogManager.shared.info("API poll baseline seeded for \(target.key); waiting for fresh input", category: .general)
        }
    }

    private func stopApiPolling() {
        guard apiPollingTask != nil else { return }
        apiPollingTask?.cancel()
        apiPollingTask = nil
        lastApiPollTokens = [:]
        print("🔔 [API POLL] Stopped")
    }

    // MARK: - OCR → Post Prediction

    /// Routes the OCR result to InstagramProfileView via pendingOCRWord binding.
    private func applyOCRToPostPrediction(text: String) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        await MainActor.run { pendingOCRWord = cleaned }
    }

    private func applyOCRResult(text: String, target: String) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [OCR] Not logged in or lockdown active — skipping")
            return
        }

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_auto_input"      : "last_biography_text"
        let dateKey = target == "note" ? "last_note_auto_sent_date"  : "last_biography_sent_date"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Dedup on the raw detected word — expires after 2 hours
        if let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
            let sentDate   = ud.object(forKey: dateKey) as? Date ?? .distantPast
            let hoursSince = Date().timeIntervalSince(sentDate) / 3600
            if hoursSince < 2 {
                print("⏭️ [OCR] Dedup: same word sent \(String(format: "%.0f", hoursSince * 60))m ago — skipping (\"\(trimmed.prefix(30))\")")
                return
            }
            print("⏭️ [OCR] Dedup expired (\(String(format: "%.1f", hoursSince))h) — allowing re-send")
            ud.removeObject(forKey: lastKey)
        }

        // Apply text template ({word} → detected word)
        let tpl = target == "note" ? noteTemplate : bioTemplate
        let composed = applyTemplate(trimmed, template: tpl)
        if tpl.contains("{word}") {
            print("📷 [OCR] Template applied (\(target)): \"\(composed.prefix(60))\"")
        }

        print("📷 [OCR] Applying to \(target): \"\(trimmed.prefix(40))\"")
        LogManager.shared.info("OCR → \(target): \"\(composed.prefix(40))\"", category: .general)

        do {
            if target == "note" {
                let final = truncateAtWordBoundary(composed, limit: 60)
                // Optimistic: show note bubble immediately, before API confirms
                await MainActor.run { lastNoteText = final }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // raw word for dedup
                    ud.set(Date(), forKey: dateKey)   // timestamp so dedup expires in 2h
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [OCR] Note sent: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            } else {
                let final = truncateAtWordBoundary(composed, limit: 150)
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights,
                            cachedMediaItems: current.cachedMediaItems,
                            cachedReelItems: current.cachedReelItems,
                            cachedNextMaxId: current.cachedNextMaxId
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // raw word for dedup
                    ud.set(Date(), forKey: dateKey)   // timestamp so dedup expires in 2h
                    print("✅ [OCR] Biography updated: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [OCR] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("OCR auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
        }
    }

    /// Two full-power vibrations with a 2-second gap — mirrors the post-unarchive confirmation.
    // MARK: - Amnesia Carousel

    /// Called when the magician closes the PostScrollView after viewing the short carousel.
    /// Runs the archive-A / unarchive-B swap in the background with anti-bot delays.
    private func triggerAmnesiaSwap() {
        guard amnesiaSettings.isEnabled,
              amnesiaSettings.isReady,
              !amnesiaSettings.isRevealed,
              amnesiaSettings.uploadState != .swapping,
              !instagram.isLocked
        else {
            print("🎭 [AMNESIA] Swap skipped — not ready or already revealed")
            return
        }
        print("🎭 [AMNESIA] Triggering reveal swap…")
        amnesiaSettings.uploadState = .swapping

        Task {
            do {
                try await instagram.swapAmnesiaCarousels(settings: amnesiaSettings)
                await MainActor.run {
                    amnesiaSettings.uploadState = .ready
                    fireDoubleConfirmationVibration()
                }
                // Wait for Instagram's CDN to process the swap before fetching the
                // updated grid — without this delay the old images are still served.
                try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 s
                await refreshMediaGridSilently()
                print("🎭 [AMNESIA] Grid refreshed after swap")
            } catch {
                await MainActor.run {
                    amnesiaSettings.uploadState = .ready
                    print("⚠️ [AMNESIA] Swap error: \(error.localizedDescription)")
                    LogManager.shared.warning("Amnesia swap failed: \(error.localizedDescription)", category: .api)
                }
            }
        }
    }

    private func fireDoubleConfirmationVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    /// Truncates `text` to `limit` characters, cutting at the last whitespace
    /// within the limit so no word is split. Returns the original string unchanged
    /// if it is already within the limit.
    private func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let truncated = String(text.prefix(limit))
        // Find the last whitespace to avoid splitting a word
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[truncated.startIndex..<lastSpace])
        }
        // No space found — the whole text is one long word; hard-truncate
        return truncated
    }
    
    private func checkAndLoadProfile(allowRemote: Bool) {
        // ALWAYS try to load from cache first (anti-bot: no automatic requests)
        if var cached = ProfileCacheService.shared.loadProfile() {
            // Guard against a race condition where the background reel/tagged preload
            // hasn't saved to disk yet but is already in self.profile memory. If we
            // blindly overwrite self.profile with the on-disk version (which still has
            // empty reels/tagged), the reels/tagged grid would flash empty even though
            // the user was already seeing them. Preserve whichever source has data.
            if let current = profile {
                if cached.cachedReelURLs.isEmpty && !current.cachedReelURLs.isEmpty {
                    cached.cachedReelURLs = current.cachedReelURLs
                    cached.cachedReelItems = current.cachedReelItems
                    print("📦 [CACHE] Preserved in-memory reels (\(current.cachedReelURLs.count)) — disk cache not yet updated")
                }
                if cached.cachedTaggedURLs.isEmpty && !current.cachedTaggedURLs.isEmpty {
                    cached.cachedTaggedURLs = current.cachedTaggedURLs
                    print("📦 [CACHE] Preserved in-memory tagged (\(current.cachedTaggedURLs.count)) — disk cache not yet updated")
                }
            }
            print("📦 [CACHE] Loading profile from cache — \(cached.cachedMediaURLs.count) posts, \(cached.cachedMediaItems.count) items")

            self.profile = cached
            self.allMediaURLs = cached.cachedMediaURLs
            // Keep infinite scroll available, but SafetyGate paces remote pages.
            self.hasMorePages = cached.cachedMediaURLs.count < maxPhotosOwnProfile
            // Pagination is gated by the global cold-start window — no extra
            // local timer needed. Real user scrolls past the 90% threshold are
            // what unblock the next page.

            // Build mediaItemsByURL in O(n) using a dictionary keyed by imageURL.
            // Previous code used first(where:) inside a loop → O(n²) with 100+ posts.
            //
            // Drop entries whose URLs are no longer in the grid before merging the new
            // ones. Without this, stale CDN URLs from previous loads accumulate and can
            // ghost-link to mismatched metadata. We preserve reveal:// keys because they
            // are local-only placeholders inserted by performance actions and don't
            // belong to the profile cache.
            let activeURLs = Set(cached.cachedMediaURLs)
            mediaItemsByURL = mediaItemsByURL.filter { key, _ in
                activeURLs.contains(key) || key.hasPrefix("reveal://")
            }
            for item in cached.cachedMediaItems { mediaItemsByURL[item.imageURL] = item }

            loadCachedImages()

            // Background preload reels + tagged from cache hit so they are
            // ready immediately when the user swipes (or are already showing
            // if cached from a previous session).
            scheduleBackgroundReelsTaggedPreload(for: cached)

            // ALWAYS attempt a single entry refresh — that is how the user
            // sees a photo they just uploaded on the real Instagram app, or
            // a follower count change, etc. The triple throttle
            //   • `InstagramSafetyGate.entryRefresh`   (90s, in-memory)
            //   • `lastRefreshTimestamp` + minRefreshInterval (90s, persisted)
            //   • `isLoading` / `isPullRefreshInFlight` guards (in `loadProfile`)
            // means rapid in-and-out navigation is automatically ignored.
            // Only skip when soft-blocked / challenged / over budget.
            let headerMissing = cached.username.isEmpty || cached.profilePicURL.isEmpty
            let zeroStats     = cached.followerCount == 0 && cached.followingCount == 0 && cached.mediaCount == 0
            if allowRemote
                && !instagram.shouldUseCacheOnlyForOptionalCalls
                && !instagram.isSessionChallenged {
                if headerMissing || zeroStats {
                    print("📦 [CACHE] Cached profile missing header/stats — refresh on entry")
                } else {
                    print("📦 [CACHE] Cached profile loaded — firing entry refresh (gated to 90s minimum)")
                }
                loadProfileSync(source: "entry")
            } else {
                print("📦 [CACHE] Entry refresh skipped — allowRemote:\(allowRemote) cacheOnly:\(instagram.shouldUseCacheOnlyForOptionalCalls) challenged:\(instagram.isSessionChallenged)")
            }
        } else {
            // First-ever entry for this account (or post-logout). Mirror Explore →
            // UserProfileView: show skeleton (rendered when profile == nil) and fire
            // ONE getProfileInfo() call that returns header + first ~18 posts.
            print("📦 [CACHE] No cached profile — single getProfileInfo() call (Explore pattern)")
            LogManager.shared.info("Performance entry: cache miss, single profile fetch", category: .general)
            if allowRemote
                && !instagram.shouldUseCacheOnlyForOptionalCalls
                && !instagram.isSessionChallenged {
                loadProfileSync(source: "entry")
            }
        }
    }
    
    /// Fetches reels, tagged and highlights in background, updates the cached profile
    @MainActor
    private func fetchAndUpdateReelsTagged(for cached: InstagramProfile) async {
        guard instagram.isLoggedIn else { return }
        
        // Anti-bot: delay 5s so this doesn't compete with Explore background refresh at startup
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // Re-check after delay: bail if locked, uploading profile pic, or session challenged
        guard !instagram.isLocked else {
            print("🚫 [CACHE] Supplementary fetch skipped — lockdown active after startup delay")
            return
        }
        guard !instagram.isUploadingProfilePic else {
            print("🚫 [CACHE] Supplementary fetch skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("Supplementary fetch skipped: profile pic upload active", category: .general)
            return
        }
        guard !instagram.isSessionChallenged else {
            print("🚫 [CACHE] Supplementary fetch skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Supplementary fetch skipped: session recently challenged", category: .general)
            return
        }

        do {
            // Sequential instead of parallel — avoids 3 simultaneous API calls
            let reels      = try await instagram.getUserReels(userId: cached.userId, amount: 50)
            guard !instagram.isLocked else { return }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))

            let tagged     = try await instagram.getUserTagged(userId: cached.userId, amount: 50)
            guard !instagram.isLocked else { return }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))

            let highlights = (try? await instagram.getUserHighlights(userId: cached.userId)) ?? cached.cachedHighlights

            let reelURLs     = reels.map { $0.imageURL }
            let taggedURLs   = tagged.map { $0.imageURL }

            print("📦 [CACHE] Background fetch: \(reelURLs.count) reels, \(taggedURLs.count) tagged, \(highlights.count) highlights")

            // Build updated profile preserving all existing data
            let updated = InstagramProfile(
                userId: cached.userId, username: cached.username, fullName: cached.fullName,
                biography: cached.biography, externalUrl: cached.externalUrl,
                profilePicURL: cached.profilePicURL, isVerified: cached.isVerified,
                isPrivate: cached.isPrivate, followerCount: cached.followerCount,
                followingCount: cached.followingCount, mediaCount: cached.mediaCount,
                followedBy: cached.followedBy, isFollowing: cached.isFollowing,
                isFollowRequested: cached.isFollowRequested, cachedAt: cached.cachedAt,
                cachedMediaURLs: cached.cachedMediaURLs,
                cachedReelURLs: reelURLs,
                cachedTaggedURLs: taggedURLs,
                cachedHighlights: highlights,
                cachedReelItems: reels,
                cachedNextMaxId: cached.cachedNextMaxId
            )

            self.profile = updated
            ProfileCacheService.shared.saveProfile(updated)

            // Download thumbnails for reels + tagged + highlight covers
            let allNew = reelURLs + taggedURLs + highlights.map { $0.coverImageURL }
            for url in allNew {
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            print("✅ [CACHE] Background supplementary fetch complete")
        } catch {
            print("⚠️ [CACHE] Background supplementary fetch failed (non-critical): \(error)")
        }
    }
    
    @MainActor
    private func loadProfile() async {
        await loadProfile(source: "manual")
    }

    @MainActor
    private func handlePerformancePullToRefresh() async {
        // Full refresh is allowed, but it is serialized and silent when blocked.
        // A pull during an existing spinner/silent refresh must not start another API chain.
        guard !isPullRefreshInFlight, !isLoading, !isSilentGridRefreshing else {
            print("🚫 [PERF] Pull refresh skipped — refresh already in progress")
            try? await Task.sleep(nanoseconds: 350_000_000)
            return
        }
        isPullRefreshInFlight = true
        defer { isPullRefreshInFlight = false }

        checkAndLoadProfile(allowRemote: false)

        guard performanceRemoteCallsAllowed,
              !uploadManager.isActive,
              !instagram.isLocked,
              !instagram.isSessionChallenged,
              !instagram.isUploadingProfilePic else {
            print("🛡️ [PERF] Pull refresh handled as cache-only")
            try? await Task.sleep(nanoseconds: 450_000_000)
            return
        }

        let now = Date().timeIntervalSince1970
        let timeSinceGridRefresh = now - lastAutoRefreshTimestamp
        guard lastAutoRefreshTimestamp == 0 || timeSinceGridRefresh >= fullRefreshAfterGridRefreshGap else {
            print("🛡️ [PERF] Pull refresh cache-only — grid refreshed \(Int(timeSinceGridRefresh))s ago")
            LogManager.shared.warning("SAFETY BLOCK — full refresh skipped after recent grid refresh", category: .general)
            try? await Task.sleep(nanoseconds: 450_000_000)
            return
        }

        let timeSinceLastRefresh = now - lastRefreshTimestamp
        guard lastRefreshTimestamp == 0 || timeSinceLastRefresh >= minRefreshInterval else {
            print("🚫 [PERF] Pull refresh cache-only — \(Int(timeSinceLastRefresh))s since last refresh")
            try? await Task.sleep(nanoseconds: 450_000_000)
            return
        }

        await loadProfile(source: "manual")
    }

    @MainActor
    private func loadProfile(source: String) async {
        guard instagram.isLoggedIn else { return }

        if instagram.shouldUseCacheOnlyForOptionalCalls {
            let rate = instagram.checkRateLimit()
            print("🛡️ [PERF] loadProfile skipped — near hourly budget (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("CACHE ONLY — loadProfile skipped near rate budget (\(rate.actionsUsed)/55)", category: .general)
            return
        }

        let safetyAction: InstagramSafetyGate.Action = source == "entry" ? .entryRefresh : .pullRefresh
        let safetyDecision = InstagramSafetyGate.shared.decision(for: safetyAction)
        guard safetyDecision.allowed else {
            print("🛡️ [PERF] loadProfile blocked — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — loadProfile \(source): \(safetyDecision.reason)", category: .general)
            if source == "manual" {
                // Pull-to-refresh is audience-facing. Safety blocks must be silent,
                // otherwise they look like network/bot errors on the fake Instagram.
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            return
        }
        InstagramSafetyGate.shared.record(safetyAction)

        // Prevent concurrent loads (double swipe-to-refresh)
        guard !isLoading else {
            print("🚫 [PERF] loadProfile skipped — already loading")
            LogManager.shared.warning("loadProfile skipped: already loading", category: .general)
            return
        }

        // Throttle: block refreshes faster than minRefreshInterval (persisted across restarts)
        let now = Date().timeIntervalSince1970
        let timeSinceLastRefresh = now - lastRefreshTimestamp
        if lastRefreshTimestamp > 0 && timeSinceLastRefresh < minRefreshInterval {
            let waited = Int(timeSinceLastRefresh)
            print("🚫 [PERF] loadProfile throttled — \(waited)s since last refresh (min \(Int(minRefreshInterval))s)")
            LogManager.shared.warning("loadProfile throttled: \(waited)s since last refresh", category: .general)
            return
        }

        // Anti-bot: skip if profile-pic POST is running, OR if the session is in a challenged
        // state (challenge_required detected recently). Making more calls while challenged
        // escalates bot signals and can cause action_blocked lockdowns.
        if instagram.isUploadingProfilePic {
            print("🚫 [PERF] loadProfile skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("loadProfile skipped: profile pic upload active", category: .general)
            return
        }
        // Stamp both timestamps so neither the throttle nor the auto-refresh fires again soon
        lastRefreshTimestamp = now
        lastAutoRefreshTimestamp = now

        print("🔄 [PERF] loadProfile starting — full profile refresh")
        LogManager.shared.info("Profile refresh started", category: .general)

        isLoading = true

        do {
            // ANTI-BOT: Wait if network changed recently
            try await instagram.waitForNetworkStability()
            
                let fetchedProfile = try await instagram.getProfileInfo()
                
                    if let fetchedProfile = fetchedProfile {
                // Keep the user-scoped image cache during refresh so existing thumbnails
                // remain visible while fresh metadata is saved over the old profile.json.
                mediaItemsByURL.removeAll()
                revealDates.removeAll()
                // Keep cachedImages so existing thumbnails stay visible during transition
                
                        self.profile = fetchedProfile
                self.allMediaURLs = fetchedProfile.cachedMediaURLs
                // Seed the pagination cursor so the first scroll-triggered call
                // fetches page 2 directly instead of re-loading page 1.
                if self.nextMaxId == nil {
                    self.nextMaxId = fetchedProfile.cachedNextMaxId
                }
                self.hasMorePages = true
                // Populate post viewer data (likes/comments already in items, 0 extra API calls)
                for item in fetchedProfile.cachedMediaItems {
                    mediaItemsByURL[item.imageURL] = item
                }
                // If the full refresh already brought reels/tagged, mark them as loaded
                // so the lazy-tab loader doesn't make redundant API calls.
                // For reels we also require the full items (with videoURL); without
                // them the grid would show static thumbnails instead of video.
                if !fetchedProfile.cachedReelURLs.isEmpty && !fetchedProfile.cachedReelItems.isEmpty {
                    reelsLoadedOnce = true
                }
                if !fetchedProfile.cachedTaggedURLs.isEmpty { taggedLoadedOnce = true }
                        ProfileCacheService.shared.saveProfile(fetchedProfile)
                // Migrate the locally-captured pending pic to the new CDN URL key
                // BEFORE clearing it. Instagram may return a different CDN URL on
                // each profile refresh, so without this the new URL would momentarily
                // have no image → brief flash/spinner between pendingProfilePic=nil
                // and the async download completing.
                if let pendingPic = ProfileCacheService.shared.pendingProfilePic,
                   !fetchedProfile.profilePicURL.isEmpty {
                    cachedImages[fetchedProfile.profilePicURL] = pendingPic
                    ProfileCacheService.shared.saveImage(pendingPic, forURL: fetchedProfile.profilePicURL)
                    print("⚡️ [PERF] Pending profile pic migrated to new CDN URL — no flash on transition")
                }
                // New CDN URL is now in fetchedProfile.profilePicURL → pending override no longer needed.
                ProfileCacheService.shared.pendingProfilePic = nil
                        downloadAndCacheImages(profile: fetchedProfile)
                // Background preload reels + tagged so they are ready before
                // the user swipes to those tabs. Uses the same fetchReelsIfNeeded /
                // fetchTaggedIfNeeded that tab-swipe uses, so the logic is
                // identical: skip if already cached, respect anti-bot budget.
                // Delay 5s to avoid competing with the posts download burst.
                scheduleBackgroundReelsTaggedPreload(for: fetchedProfile)
                    } else {
                        print("⚠️ [PERF] getProfileInfo returned nil — profile data unavailable")
                        LogManager.shared.error("loadProfile: getProfileInfo returned nil for userId \(instagram.session.userId)", category: .general)
                    }
                    isLoading = false
            } catch let error as InstagramError {
                print("⚠️ Instagram error detected: \(error)")
                    isLoading = false
            switch error {
            case .challengeRequired:
                // Transient GET challenge — the session will recover on its own.
                // Do NOT show the connection error alert; it would confuse the user
                // since no actual bot detection appears in the Instagram app.
                print("⚠️ [PERF] loadProfile: transient challenge_required — suppressing connection error alert")
                LogManager.shared.warning("loadProfile: transient challenge_required — alert suppressed", category: .general)
            default:
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ Error loading profile: \(error)")
                    isLoading = false
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
    
    // Sync wrapper for non-async call sites (onRefresh button, header "@" button)
    private func loadProfileSync() {
        loadProfileSync(source: "manual")
    }

    private func loadProfileSync(source: String) {
        Task { await loadProfile(source: source) }
    }
    
    private func loadCachedImages() {
        guard let profile = profile else { return }

        // ── 1. Serve everything that is already on disk (synchronous, free) ──────
        if let pending = ProfileCacheService.shared.pendingProfilePic {
            cachedImages[profile.profilePicURL] = pending
        } else if let image = ProfileCacheService.shared.loadImage(forURL: profile.profilePicURL) {
            cachedImages[profile.profilePicURL] = image
        }

        let highlightCoverURLs = profile.cachedHighlights.map { $0.coverImageURL }
        let followerPicURLs    = profile.followedBy.compactMap { $0.profilePicURL }
        let allURLs = [profile.profilePicURL]
            + profile.cachedMediaURLs
            + followerPicURLs
            + profile.cachedReelURLs
            + profile.cachedTaggedURLs
            + highlightCoverURLs

        var missingURLs: [String] = []
        var hitCount = 0
        for url in allURLs where cachedImages[url] == nil {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                hitCount += 1
            } else {
                missingURLs.append(url)
            }
        }
        print("📦 [CACHE] disk-hit \(hitCount), to-download \(missingURLs.count) — total \(cachedImages.count)")

        guard !missingURLs.isEmpty else { return }

        // ── 2. Download missing images in parallel ─────────────────────────────
        // Thumbnails are <50 KB each so we can run many concurrent requests
        // safely. Going from 4 → 10 drops a 66-image first-paint from ~17s to
        // ~7s on a typical network — directly addresses the "blank for 60s"
        // perception when iOS has purged the image cache.
        Task {
            let concurrencyLimit = 10
            await withTaskGroup(of: (String, UIImage?).self) { group in
                var inFlight = 0
                var pending = missingURLs.makeIterator()

                // Seed the first batch
                while inFlight < concurrencyLimit, let url = pending.next() {
                    let u = url
                    group.addTask { (u, await self.downloadImage(from: u)) }
                    inFlight += 1
                }

                for await (url, image) in group {
                    inFlight -= 1
                    if let img = image {
                        let u = url
                        let i = img
                        await MainActor.run {
                            // Prefer the local pending override for the profile pic
                            if u == profile.profilePicURL,
                               ProfileCacheService.shared.pendingProfilePic != nil { return }
                            self.cachedImages[u] = i
                            ProfileCacheService.shared.saveImage(i, forURL: u)
                        }
                    }
                    // Enqueue next URL as a slot frees up
                    if let url = pending.next() {
                        let u = url
                        group.addTask { (u, await self.downloadImage(from: u)) }
                        inFlight += 1
                    }
                }
            }
            print("✅ [CACHE] Parallel download finished — total \(await MainActor.run { self.cachedImages.count })")
        }
    }
    
    private func downloadAndCacheImages(profile: InstagramProfile) {
        Task {
            // Download profile pic
            print("🖼️ [CACHE] Downloading profile pic: \(String(profile.profilePicURL.prefix(80)))...")
            if let image = await downloadImage(from: profile.profilePicURL) {
                await MainActor.run {
                    cachedImages[profile.profilePicURL] = image
                    ProfileCacheService.shared.saveImage(image, forURL: profile.profilePicURL)
                    print("✅ [CACHE] Profile pic downloaded and cached")
                }
            } else {
                print("❌ [CACHE] Failed to download profile pic")
            }
            
            // Download media thumbnails
            print("🖼️ [CACHE] Downloading \(profile.cachedMediaURLs.count) media thumbnails...")
            for (index, url) in profile.cachedMediaURLs.enumerated() {
                if let image = await downloadImage(from: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                        ProfileCacheService.shared.saveImage(image, forURL: url)
                    }
                    print("✅ [CACHE] Media \(index + 1)/\(profile.cachedMediaURLs.count) downloaded")
                } else {
                    print("❌ [CACHE] Failed to download media \(index + 1)")
                }
            }
            
            // Download followed by profile pics
            print("🖼️ [CACHE] Downloading \(profile.followedBy.count) follower profile pics...")
            for (index, follower) in profile.followedBy.enumerated() {
                if let picURL = follower.profilePicURL {
                    if let image = await downloadImage(from: picURL) {
                        await MainActor.run {
                            cachedImages[picURL] = image
                            ProfileCacheService.shared.saveImage(image, forURL: picURL)
                        }
                    }
                }
            }
            
            // Download reel thumbnails
            if !profile.cachedReelURLs.isEmpty {
                print("🎬 [CACHE] Downloading \(profile.cachedReelURLs.count) reel thumbnails...")
                for url in profile.cachedReelURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }
            
            // Download tagged thumbnails
            if !profile.cachedTaggedURLs.isEmpty {
                print("🏷️ [CACHE] Downloading \(profile.cachedTaggedURLs.count) tagged thumbnails...")
                for url in profile.cachedTaggedURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }

            // Download highlight cover images
            if !profile.cachedHighlights.isEmpty {
                print("🌟 [CACHE] Downloading \(profile.cachedHighlights.count) highlight covers...")
                for highlight in profile.cachedHighlights {
                    let url = highlight.coverImageURL
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }
            
            print("✅ [CACHE] All images download process completed")
        }
    }
    
    // MARK: - Infinite Scroll
    
    private func loadMoreMedia() {
        guard !isLoadingMore, hasMorePages, allMediaURLs.count < maxPhotosOwnProfile else {
            print("📜 [PROFILE] Cannot load more - loading: \(isLoadingMore), hasMore: \(hasMorePages), count: \(allMediaURLs.count)")
            return
        }
        guard performanceRemoteCallsAllowed else {
            print("🛡️ [PROFILE] Pagination skipped — Performance cache-only mode")
            LogManager.shared.warning("SAFETY BLOCK — Performance pagination skipped in cache-only mode", category: .general)
            return
        }
        guard !uploadManager.isActive else {
            print("🛡️ [PROFILE] Pagination skipped — upload active/paused")
            LogManager.shared.warning("SAFETY BLOCK — Performance pagination skipped: upload active", category: .general)
            return
        }
        // ANTI-BOT: Also block pagination while Sync & Archive is running.
        // S&A calls ProfileCacheService.removeMediaItem() for each archive, which
        // changes cachedMediaURLs → onChange fires → grid cells render → loadMoreIfNeeded
        // triggers a GET /feed/user/ while we're still inside the archive loop.
        // That exact POST → POST → GET sequence triggered the May 16 challenge_required.
        guard !uploadManager.isSyncArchiveActive else {
            print("🛡️ [PROFILE] Pagination skipped — Sync & Archive active")
            LogManager.shared.warning("SAFETY BLOCK — Performance pagination skipped: S&A active", category: .general)
            return
        }
        let safetyDecision = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
        guard safetyDecision.allowed else {
            print("🛡️ [PROFILE] Pagination skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — Performance pagination: \(safetyDecision.reason)", category: .general)
            return
        }
        InstagramSafetyGate.shared.record(.ownProfilePagination)
        
        isLoadingMore = true
        let paginationCursorInfo = nextMaxId != nil ? "cursor=\(nextMaxId!.prefix(12))…" : "cursor=nil(p1)"
        print("📜 [PROFILE] Loading more media (count:\(allMediaURLs.count) \(paginationCursorInfo))...")
        LogManager.shared.debug("Own pagination start — count:\(allMediaURLs.count) \(paginationCursorInfo)", category: .profile)

        let existingURLsBeforeRequest = Set(allMediaURLs)
        let existingMediaIdsBeforeRequest = Set(mediaItemsByURL.values.map { $0.mediaId })
        
        Task {
            do {
                // Fetch next batch
                let requestedMaxId = nextMaxId
                var (mediaItems, newMaxId) = try await instagram.getUserMediaItems(userId: profile?.userId, amount: 21, maxId: requestedMaxId)

                // If the first pagination call rediscovers the already-cached first
                // page, use the returned cursor for the real next page. CDN URLs rotate,
                // so compare by mediaId first.
                // CRITICAL: this internal 2nd call must respect the SafetyGate and use
                // a human-like delay, otherwise we'd emit 2 GETs to /feed/user/ within
                // ~1s — Instagram bot fingerprint.
                if requestedMaxId == nil, let discoveredMaxId = newMaxId {
                    let hasFreshItem = mediaItems.contains { item in
                        if !item.mediaId.isEmpty, existingMediaIdsBeforeRequest.contains(item.mediaId) { return false }
                        return !existingURLsBeforeRequest.contains(item.imageURL)
                    }
                    if !hasFreshItem {
                        let nextPageDecision = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
                        if nextPageDecision.allowed {
                            print("📜 [PROFILE] First pagination returned cached first page — fetching next cursor after pause")
                            // Human-like 1.5–2.5s pause before the internal second call.
                            // Shorter than the old 3.5–4.5s since cachedNextMaxId now
                            // prevents this path for most users; the delay only fires for
                            // accounts with fewer posts than the initial fetch batch.
                            let pauseNs = UInt64.random(in: 1_500_000_000...2_500_000_000)
                            try? await Task.sleep(nanoseconds: pauseNs)
                            InstagramSafetyGate.shared.record(.ownProfilePagination)
                            let nextPage = try await instagram.getUserMediaItems(userId: profile?.userId, amount: 21, maxId: discoveredMaxId)
                            mediaItems = nextPage.0
                            newMaxId = nextPage.1
                        } else {
                            print("🛡️ [PROFILE] Skipping internal nextPage — SafetyGate (\(nextPageDecision.reason), wait \(nextPageDecision.waitSeconds)s)")
                            LogManager.shared.warning("SAFETY BLOCK — internal nextPage skipped: \(nextPageDecision.reason)", category: .general)
                        }
                    }
                }
                
                await MainActor.run {
                    // Deduplicate by stable mediaId first. CDN URLs rotate and can make
                    // the same post look new if compared by URL only.
                    let existingURLs = Set(allMediaURLs)
                    let existingMediaIds = Set(mediaItemsByURL.values.map { $0.mediaId })
                    var seenIncomingIds = Set<String>()
                    let freshItems = mediaItems.filter { item in
                        let key = item.mediaId.isEmpty ? item.imageURL : item.mediaId
                        guard seenIncomingIds.insert(key).inserted else { return false }
                        if !item.mediaId.isEmpty, existingMediaIds.contains(item.mediaId) { return false }
                        return !existingURLs.contains(item.imageURL)
                    }

                    // Store items for post viewer (likes/comments already included)
                    for item in freshItems { mediaItemsByURL[item.imageURL] = item }

                    // Respect limit
                    let remainingSlots = maxPhotosOwnProfile - allMediaURLs.count
                    let urlsToAppend = Array(freshItems.prefix(remainingSlots).map { $0.imageURL })

                    // Filter to multiples of 3 to avoid UI gaps
                    let totalAfterAdd = allMediaURLs.count + urlsToAppend.count
                    let remainder = totalAfterAdd % 3
                    let urlsToDisplay = remainder == 0 ? urlsToAppend : Array(urlsToAppend.dropLast(remainder))

                    allMediaURLs.append(contentsOf: urlsToDisplay)
                    nextMaxId = newMaxId
                    hasMorePages = (newMaxId != nil) && (newMaxId != requestedMaxId) && (allMediaURLs.count < maxPhotosOwnProfile)
                    isLoadingMore = false

                    if var updatedProfile = profile {
                        updatedProfile.cachedMediaURLs = allMediaURLs
                        updatedProfile.cachedMediaItems = allMediaURLs.compactMap { mediaItemsByURL[$0] }
                        // Persist the latest cursor so the next app session starts from
                        // page N+1 instead of re-fetching the already-cached first page.
                        updatedProfile.cachedNextMaxId = newMaxId
                        updatedProfile.cachedAt = Date()
                        profile = updatedProfile
                        ProfileCacheService.shared.saveProfile(updatedProfile)
                    }

                    print("📜 [PROFILE] Loaded \(urlsToDisplay.count) new (skipped \(mediaItems.count - freshItems.count) dupes), total: \(allMediaURLs.count), hasMore: \(hasMorePages)")

                    // Download images for new URLs
                    downloadImagesForURLs(urlsToDisplay)
                }
            } catch {
                print("❌ [PROFILE] Error loading more: \(error)")
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }
    
    private func loadMoreIfNeeded(currentURL: String) {
        // Cold-start guard: pagination triggered by SwiftUI mounting cells
        // during the first 45s would add a 3rd /feed/user/ call right after
        // the entry burst. The user can still scroll — when they cross the
        // 90% threshold after the window closes, pagination resumes.
        if InstagramSafetyGate.shared.isInColdStartWindow { return }

        // Skip while another page load or silent refresh is already running.
        guard !isLoadingMore, !isSilentGridRefreshing else { return }

        guard let index = allMediaURLs.firstIndex(of: currentURL) else { return }
        // 55% threshold: fires earlier so the next page arrives before the user
        // reaches the last cell. With 12 initial posts this fires at post 7.
        let threshold = max(1, Int(Double(allMediaURLs.count) * 0.55))

        if index >= threshold {
            print("📜 [PROFILE] User reached 55% (\(index)/\(allMediaURLs.count)) — loading more…")
            // If pagination is still in the SafetyGate cooldown (e.g. 6s after
            // silent refresh), schedule a SINGLE automatic retry so the user
            // never sees a blank grid — no manual action needed.
            // paginationRetryScheduled prevents the thundering-herd problem where
            // 12 onAppear callbacks each schedule their own retry.
            if performanceRemoteCallsAllowed {
                let decision = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
                if decision.allowed {
                    loadMoreMedia()
                } else if !paginationRetryScheduled {
                    paginationRetryScheduled = true
                    let wait = max(1, decision.waitSeconds)
                    print("⏳ [PROFILE] Pagination gated (\(decision.reason), \(wait)s) — will retry")
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(wait) + 0.3) {
                        paginationRetryScheduled = false
                        guard !isLoadingMore, hasMorePages else { return }
                        loadMoreMedia()
                    }
                }
            } else {
                loadMoreMedia()  // cache-only guard handled inside loadMoreMedia itself
            }
        }
    }
    
    private func downloadImagesForURLs(_ urls: [String]) {
        Task {
            for url in urls {
                if cachedImages[url] == nil, let image = await downloadImage(from: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                        ProfileCacheService.shared.saveImage(image, forURL: url)
                    }
                }
            }
        }
    }
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else {
            print("⚠️ [DOWNLOAD] Empty URL string")
            LogManager.shared.warning("Image download skipped: empty URL", category: .cache)
            return nil
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ [DOWNLOAD] Invalid URL: \(urlString)")
            LogManager.shared.warning("Image download invalid URL: \(String(urlString.prefix(80)))", category: .cache)
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 [DOWNLOAD] HTTP \(httpResponse.statusCode) for: \(String(urlString.prefix(60)))...")
                
                if httpResponse.statusCode != 200 {
                    print("❌ [DOWNLOAD] Non-200 status code")
                    LogManager.shared.warning("Image download HTTP \(httpResponse.statusCode): \(String(urlString.prefix(80)))", category: .cache)
                    return nil
                }
            }
            
            guard let image = UIImage(data: data) else {
                print("❌ [DOWNLOAD] Failed to create UIImage from data")
                LogManager.shared.warning("Image download decode failed: \(String(urlString.prefix(80))) bytes:\(data.count)", category: .cache)
                return nil
            }
            
            return image
        } catch {
            print("❌ [DOWNLOAD] Error: \(error.localizedDescription)")
            LogManager.shared.warning("Image download error: \(error.localizedDescription) url:\(String(urlString.prefix(80)))", category: .cache)
            return nil
        }
    }
    
    // MARK: - Performance Lockdown Overlay (Hide errors from spectators)
    
    private var performanceLockdownOverlay: some View {
        ZStack {
            // Full-screen semi-transparent backdrop
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Generic "No Internet" icon (hide technical details)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
                
                VStack(spacing: 8) {
                    Text("ig.no_internet")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("ig.check_connection")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Hidden "Info" button for magician (long-press to reveal)
                Text("⚠️")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.3))
                    .onLongPressGesture(minimumDuration: 2.0) {
                        showMagicianDebugInfo()
                    }
            }
            .padding(40)
        }
        .alert("Upload in progress", isPresented: $showUploadConflictAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A photo upload is currently running. Wait for it to finish before revealing numbers — both actions share the same hourly Instagram limit and triggering both together can cause bot detection.")
        }
        .sheet(isPresented: $showingLockdownSheet) {
            LockdownDetailsSheet()
        }
    }
    
    private func showMagicianDebugInfo() {
        print("🔓 [MAGICIAN] Lockdown details requested")
        LogManager.shared.info("Magician opened lockdown details during performance lockdown", category: .general)
        showingLockdownSheet = true
    }

    // MARK: - Silent Media Grid Refresh (after Force Number Reveal unarchive)

    /// Inserts a batch of reveal:// pseudo-URLs as a **contiguous block** at a single anchor position.
    ///
    /// Problem solved: if each letter is placed individually by its own `uploadDate`, letters uploaded
    /// over several minutes (due to anti-bot delays) can land in positions that interleave with real posts
    /// whose dates fall within that window — breaking the word order in the grid.
    ///
    /// Solution: all letters share one insertion index (derived from the newest date in the batch).
    /// Since `jobs` is in reversed-word order [A, L, O, H], inserting each at the same index
    /// pushes the previous ones right: A→[A], L→[L,A], O→[O,L,A], H→[H,O,L,A] ✓
    @MainActor
    private func batchInsertRevealURLs(_ photos: [(pseudoURL: String, image: UIImage?)]) {
        guard !photos.isEmpty else { return }

        // Cache images
        for item in photos { if let img = item.image { cachedImages[item.pseudoURL] = img } }

        // Single photo: delegate to the date-aware individual inserter
        if photos.count == 1 { insertRevealURL(photos[0].pseudoURL); return }

        // Collect upload dates for all photos in the batch
        let allSetPhotos = DataManager.shared.sets.flatMap { $0.photos }
        for item in photos {
            let mediaId = String(item.pseudoURL.dropFirst("reveal://".count))
            if let d = revealUploadDate(for: mediaId) ?? allSetPhotos.first(where: { $0.mediaId == mediaId })?.uploadDate {
                revealDates[item.pseudoURL] = d
            }
        }

        // Anchor = newest date in the batch (position the whole group here)
        guard let anchorDate = photos.compactMap({ revealDates[$0.pseudoURL] }).max() else {
            // No dates at all — fallback: insert all at position 0 (same as individual fallback)
            for item in photos {
                guard !allMediaURLs.contains(item.pseudoURL) else { continue }
                allMediaURLs.insert(item.pseudoURL, at: 0)
            }
            print("⚡️ [REVEAL BATCH] No dates — \(photos.count) photos at pos 0 (fallback)")
            return
        }

        // Pinned-post prefix detection (same logic as insertRevealURL)
        var maxDate: Date = .distantPast
        var maxDateIndex = 0
        for (i, url) in allMediaURLs.enumerated() {
            let d: Date? = url.hasPrefix("reveal://") ? revealDates[url] : mediaItemsByURL[url]?.takenAt
            if let d = d, d > maxDate { maxDate = d; maxDateIndex = i }
        }
        let pinnedEnd = maxDate == .distantPast ? 0 : maxDateIndex

        // Find one insertion index for the entire group
        var insertAt = allMediaURLs.count  // default: append at end
        for i in pinnedEnd..<allMediaURLs.count {
            let url = allMediaURLs[i]
            let d: Date? = url.hasPrefix("reveal://") ? revealDates[url] : mediaItemsByURL[url]?.takenAt
            guard let d = d else { continue }
            if d <= anchorDate { insertAt = i; break }
        }

        // Insert every photo at the SAME index — each new insertion shifts the previous to the right,
        // so the jobs order [A,L,O,H] produces the grid order [H,O,L,A] (correct word direction).
        var inserted = 0
        for item in photos {
            guard !allMediaURLs.contains(item.pseudoURL) else { continue }
            allMediaURLs.insert(item.pseudoURL, at: insertAt)
            inserted += 1
        }
        print("⚡️ [REVEAL BATCH] \(inserted)/\(photos.count) photos inserted at pos \(insertAt) (pinnedEnd=\(pinnedEnd), anchor=\(anchorDate))")
    }

    /// Inserts a reveal:// pseudo-URL at the correct chronological position (newest-first).
    ///
    /// Strategy:
    ///  1. Find the photo's `uploadDate` from DataManager (set at upload time, very close to Instagram's
    ///     `taken_at` since Instagram uses its own server timestamp upon receiving the photo).
    ///  2. Store that date in `revealDates` so sibling reveal:// items can be compared against it.
    ///  3. Scan `allMediaURLs` newest-first; insert just before the first item that is OLDER.
    ///     - CDN items:    compare via `mediaItemsByURL[url]?.takenAt`
    ///     - reveal:// items: compare via `revealDates[url]`
    ///  4. Fallback: insert at position 0 if no date is available (safe default, old behavior).
    ///
    /// Example — word "julia", grid has two new real posts (Mar 28) and old posts (Jan 10):
    ///   Each magic photo has uploadDate in Feb 2026 → they land AFTER the Mar 28 posts, BEFORE Jan 10.
    ///   Final: [new1(Mar28), new2(Mar28), J, U, L, I, A, old(Jan10)] ✓
    @MainActor
    private func insertRevealURL(_ pseudoURL: String) {
        guard !allMediaURLs.contains(pseudoURL) else { return }

        let mediaId = String(pseudoURL.dropFirst("reveal://".count))

        // Look up the upload date from DataManager — equals the taken_at sent to Instagram
        // (or the actual upload time for older sets uploaded before the grid-anchor feature).
        let uploadDate = revealUploadDate(for: mediaId)

        guard let revealDate = uploadDate else {
            allMediaURLs.insert(pseudoURL, at: 0)
            print("⚡️ [REVEAL] No uploadDate for \(mediaId) — inserted at position 0 (fallback)")
            return
        }

        revealDates[pseudoURL] = revealDate

        // ── Detect pinned-post prefix ─────────────────────────────────────────
        // Instagram places pinned posts at the top of the grid regardless of their
        // taken_at. They can appear in ANY order (not necessarily descending).
        //
        // Strategy: find the index of the GLOBALLY NEWEST item in the grid.
        // That item is always the first non-pinned post (the most recent regular post).
        // Everything before it may be pinned (or simply an older pinned post that
        // happens to precede it). This is more robust than "first jump" detection,
        // which fails when pinned posts are not in monotonically decreasing order.
        //
        // Example: [pinned 2023-06] [pinned 2025-01] [pinned 2023-06] [today 2026] [2d ago] …
        //           maxDate index = 3 ─────────────────────────────────^
        //           pinnedEnd = 3 → scan starts after the 3 pinned posts ✓
        var maxDate: Date = .distantPast
        var maxDateIndex = 0
        for (i, url) in allMediaURLs.enumerated() {
            let d: Date?
            if url.hasPrefix("reveal://") {
                d = revealDates[url]
            } else {
                d = mediaItemsByURL[url]?.takenAt
            }
            if let itemDate = d, itemDate > maxDate {
                maxDate = itemDate
                maxDateIndex = i
            }
        }
        let pinnedEnd = maxDateIndex
        print("⚡️ [REVEAL] Pinned prefix: \(pinnedEnd) item(s) (maxDate=\(maxDate) at pos \(maxDateIndex)) — scanning from pos \(pinnedEnd)")
        // ──────────────────────────────────────────────────────────────────────

        // Scan only the non-pinned portion for the chronological insertion point.
        // Using `<=` (not `<`) so that sibling reveal photos with the SAME uploadDate
        // each insert BEFORE the previous one → final order is correct word direction.
        // (Without `<=`, all same-date photos would append sequentially → reversed word.)
        for i in pinnedEnd..<allMediaURLs.count {
            let url = allMediaURLs[i]
            let itemDate: Date?
            if url.hasPrefix("reveal://") {
                itemDate = revealDates[url]
            } else {
                itemDate = mediaItemsByURL[url]?.takenAt
            }
            guard let d = itemDate else { continue }
            if d <= revealDate {
                allMediaURLs.insert(pseudoURL, at: i)
                print("⚡️ [REVEAL] \(mediaId) (taken_at≈\(revealDate)) → inserted at pos \(i) (pinnedEnd=\(pinnedEnd))")
                return
            }
        }

        // Older than everything in the non-pinned section → append at the end.
        allMediaURLs.append(pseudoURL)
        print("⚡️ [REVEAL] \(mediaId) (taken_at≈\(revealDate)) → appended at end")
    }

    /// Returns the date used to place a reveal:// item in the fake grid.
    /// Older builds could accidentally overwrite `uploadDate` at reveal time when
    /// `updatePhoto` received the same mediaId again. If that happened, the card
    /// looked "new" and jumped to position 0. We repair that outlier from siblings
    /// in the same completed set so existing decks recover automatically.
    @MainActor
    private func revealUploadDate(for mediaId: String) -> Date? {
        for set in DataManager.shared.sets {
            guard let photo = set.photos.first(where: { $0.mediaId == mediaId }) else { continue }
            guard let rawDate = photo.uploadDate else { return nil }

            guard let completedAt = set.completedAt,
                  rawDate > completedAt.addingTimeInterval(300) else {
                return rawDate
            }

            let validSiblingDates = set.photos.compactMap { sibling -> Date? in
                guard sibling.mediaId != mediaId, let date = sibling.uploadDate else { return nil }
                return date <= completedAt.addingTimeInterval(300) ? date : nil
            }.sorted()

            guard !validSiblingDates.isEmpty else { return rawDate }

            let repairedDate = validSiblingDates[validSiblingDates.count / 2]
            DataManager.shared.updatePhoto(photoId: photo.id, uploadDate: repairedDate)
            print("🛠️ [REVEAL] Repaired uploadDate for \(mediaId): \(rawDate) → \(repairedDate)")
            return repairedDate
        }

        return nil
    }

    /// Does NOT touch profile stats, bio, follower count, etc. — zero visible disruption.
    @MainActor
    private func refreshMediaGridSilently() async {
        guard !isLoading, !isPullRefreshInFlight, !isSilentGridRefreshing else {
            print("⚠️ [PERF] Silent refresh skipped — another refresh is active")
            return
        }
        // Cold-start guard: never run an automatic silent refresh during the
        // first ~45s of the app session — this is the API burst Instagram
        // fingerprints as bot behaviour.
        guard InstagramSafetyGate.shared.allowAutoCall("silent grid refresh") else {
            return
        }
        isSilentGridRefreshing = true
        defer { isSilentGridRefreshing = false }

        guard !instagram.isLocked, let userId = profile?.userId else {
            print("⚠️ [PERF] Silent refresh skipped — locked or no profile")
            return
        }
        // Anti-bot: skip silent GET if a profile-pic POST is still running, or if the
        // session is in a challenged state — avoid cascading bot signals.
        guard !instagram.isUploadingProfilePic else {
            print("⚠️ [PERF] Silent refresh skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("Silent refresh skipped: profile pic upload active", category: .general)
            return
        }
        guard !instagram.isSessionChallenged else {
            print("⚠️ [PERF] Silent refresh skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Silent refresh skipped: session recently challenged", category: .general)
            return
        }
        let safetyDecision = InstagramSafetyGate.shared.decision(for: .silentGridRefresh)
        guard safetyDecision.allowed else {
            print("🛡️ [PERF] Silent refresh skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — silent grid refresh: \(safetyDecision.reason)", category: .general)
            return
        }
        InstagramSafetyGate.shared.record(.silentGridRefresh)

        // ANTI-BOT: Staged loading. If another API request was made in the last
        // 2 seconds (e.g. validateSession on Performance entry, post-reveal API,
        // or a cold-start window that just closed and drained queued tasks all
        // at once), wait a jittered 1.2–2.5s so we don't stack endpoint-after-
        // endpoint. This is invisible to the magician: the grid already shows
        // local images, this GET just upgrades pseudo-URLs to CDN URLs.
        if instagram.hasRecentApiBurst(threshold: 1, seconds: 2) {
            let waitNs = UInt64.random(in: 1_200_000_000...2_500_000_000)
            print("⏳ [PERF] Silent refresh: staging delay \(Double(waitNs)/1_000_000_000)s to avoid burst")
            try? await Task.sleep(nanoseconds: waitNs)
        }

        // No delay needed: the grid already shows local images via pseudo-URLs.
        // This GET only replaces pseudo-URLs with real CDN URLs in the background.
        print("🔄 [PERF] Silent refresh: fetching updated media grid (no delay — local images shown already)…")
        LogManager.shared.info("Silent media refresh triggered after reveal", category: .general)

        do {
            let (items, refreshedMaxId) = try await instagram.getUserMediaItems(userId: userId, amount: 21, maxId: nil)
            let newURLs = items.map { $0.imageURL }
            guard !newURLs.isEmpty else {
                print("⚠️ [PERF] Silent refresh: empty response from Instagram")
                return
            }

            // Pre-download all new images BEFORE swapping allMediaURLs.
            // This prevents blank cells: cells keep showing local reveal:// images
            // until the real CDN images are fully cached and ready.
            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty {
                print("🔄 [PERF] Silent refresh: pre-downloading \(missing.count) CDN image(s) before swap…")
                await withTaskGroup(of: Void.self) { group in
                    for url in missing {
                        group.addTask {
                            if let image = await self.downloadImage(from: url) {
                                await MainActor.run {
                                    self.cachedImages[url] = image
                                    ProfileCacheService.shared.saveImage(image, forURL: url)
                                }
                            }
                        }
                    }
                }
                print("🔄 [PERF] Silent refresh: all CDN images cached — swapping grid now")
            }

            // Atomic swap: reveal:// placeholders replaced with real CDN URLs.
            // All images are already in cache so no blank frames appear.
            let revealURLsBefore = allMediaURLs.filter { $0.hasPrefix("reveal://") }
            let cleanedExisting  = allMediaURLs.filter { !$0.hasPrefix("reveal://") }

            // Build existingTail by mediaId — NOT by URL string.
            // CDN URLs rotate per session, so the same post has different URL strings
            // between fetches. Comparing URL strings causes every previously-seen
            // post to land in existingTail, creating duplicates in the grid.
            let newMediaIds = Set(items.map { $0.mediaId })
            let existingTail = cleanedExisting.filter { url -> Bool in
                // Only keep URLs whose mediaId is known AND not covered by the new fetch.
                // Stale/orphan URLs (no matching item) are always discarded.
                guard let item = mediaItemsByURL[url] else { return false }
                return !newMediaIds.contains(item.mediaId)
            }
            var merged = newURLs + existingTail

            // ── Preserve unconfirmed reveal:// placeholders ───────────────────────
            // When a photo was uploaded with an old taken_at (grid anchor), it lives
            // BELOW the first 21 posts Instagram returns. The silent refresh won't
            // include its real CDN URL, so without this step the reveal:// placeholder
            // would simply be dropped and the photo would disappear from the fake grid.
            // Solution: any reveal:// whose mediaId is NOT yet in the CDN results is
            // re-inserted at the chronologically correct position so it stays visible
            // until a later refresh (or full reload) brings the real CDN URL.
            for revealURL in revealURLsBefore {
                let mediaId = String(revealURL.dropFirst("reveal://".count))
                // Already confirmed: real CDN URL for this mediaId is in merged → skip
                if newMediaIds.contains(mediaId) { continue }
                // Already present (shouldn't happen): skip
                if merged.contains(revealURL) { continue }

                // Determine the date to use for positioning
                let revealDate: Date? = revealDates[revealURL] ?? {
                    DataManager.shared.sets
                        .flatMap { $0.photos }
                        .first(where: { $0.mediaId == mediaId })
                        .flatMap { $0.uploadDate }
                }()

                guard let anchorDate = revealDate else {
                    // No date info — prepend as fallback
                    merged.insert(revealURL, at: 0)
                    print("⚡️ [REVEAL PRESERVE] \(mediaId) — no date, re-inserted at 0")
                    continue
                }

                // Find the correct insertion point: first item strictly older than anchorDate
                var inserted = false
                for (i, url) in merged.enumerated() {
                    let d: Date?
                    if url.hasPrefix("reveal://") {
                        d = revealDates[url] ?? {
                            let mid = String(url.dropFirst("reveal://".count))
                            return DataManager.shared.sets.flatMap { $0.photos }.first(where: { $0.mediaId == mid })?.uploadDate
                        }()
                    } else {
                        d = mediaItemsByURL[url]?.takenAt
                    }
                    guard let itemDate = d else { continue }
                    if itemDate < anchorDate {
                        merged.insert(revealURL, at: i)
                        print("⚡️ [REVEAL PRESERVE] \(mediaId) — not yet in CDN, re-inserted at pos \(i) (anchor=\(anchorDate))")
                        inserted = true
                        break
                    }
                }
                if !inserted {
                    merged.append(revealURL)
                    print("⚡️ [REVEAL PRESERVE] \(mediaId) — not yet in CDN, appended at end")
                }
            }
            // ─────────────────────────────────────────────────────────────────────
            
            // ── Diagnostic logs ──────────────────────────────────────────────
            print("🔄 [SWAP] allMediaURLs BEFORE (\(allMediaURLs.count) total, \(revealURLsBefore.count) reveal://):")
            for (i, url) in allMediaURLs.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                print("  [\(i)] \(url.hasPrefix("reveal://") ? url : "cdn…\(url.suffix(40))") id=\(itemId)")
            }
            print("🔄 [SWAP] Instagram returned \(newURLs.count) URLs (newest→oldest):")
            for (i, url) in newURLs.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                let date   = items.first(where: { $0.imageURL == url })?.takenAt.map { "\($0)" } ?? "noDate"
                print("  [\(i)] id=\(itemId) date=\(date)")
            }
            print("🔄 [SWAP] existingTail (\(existingTail.count) old paged URLs not in new fetch)")
            print("🔄 [SWAP] merged AFTER (\(merged.count) total):")
            for (i, url) in merged.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                print("  [\(i)] \(url.hasPrefix("reveal://") ? url : "cdn…\(url.suffix(40))") id=\(itemId)")
            }
            // ─────────────────────────────────────────────────────────────────

            allMediaURLs = merged
            nextMaxId = refreshedMaxId
            hasMorePages = refreshedMaxId != nil && merged.count < maxPhotosOwnProfile
            // No local pagination suppression needed — `isLoadingMore` and the
            // SafetyGate cross-action pause already prevent another /feed/user/
            // call from firing right after a silent refresh.

            // Clear cached reveal dates only for placeholders that WERE replaced by real CDN URLs.
            // Preserved reveal:// URLs (still in merged) keep their cached date for future refreshes.
            let stillPresentRevealURLs = Set(merged.filter { $0.hasPrefix("reveal://") })
            revealDates = revealDates.filter { stillPresentRevealURLs.contains($0.key) }

            // Keep mediaItemsByURL in sync so removeMediaItem(byMediaId:) can resolve fresh URLs.
            for item in items { mediaItemsByURL[item.imageURL] = item }

            // Persist both URLs and items — this keeps cachedMediaItems fresh so that
            // removeMediaItem(byMediaId:) can find the correct CDN URL to remove.
            ProfileCacheService.shared.updateMediaURLsAndItems(merged, items: items)

            let newCount = newURLs.filter { !cleanedExisting.contains($0) }.count
            print("🔄 [PERF] Silent refresh done — \(merged.count) total, \(newCount) newly visible")
            LogManager.shared.info("Silent refresh done: \(merged.count) items, \(newCount) new", category: .general)
        } catch {
            print("⚠️ [PERF] Silent media refresh failed: \(error.localizedDescription)")
            LogManager.shared.warning("Silent refresh failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Auto Profile Picture

    private static let lastUploadedAssetKey = "autoPic_lastUploadedAssetId"
    private static let lastUploadedHashKey  = "autoPic_lastUploadedHash"

    /// Silently uploads the most recent gallery photo as profile picture.
    /// Safe to call on every onAppear — does nothing if same photo as last upload.
    @MainActor
    private func autoUploadLatestGalleryPhoto() async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("📷 [AUTO PIC] Skipped — not logged in or locked")
            return
        }

        // ── Ensure permission ──
        let authorized = await requestPhotosPermissionIfNeeded()
        guard authorized else {
            print("📷 [AUTO PIC] No Photos permission — skipping")
            return
        }

        // ── Fast check: compare asset identifier before loading any image data ──
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = result.firstObject else {
            print("📷 [AUTO PIC] Gallery is empty — skipping")
            return
        }

        let assetId      = asset.localIdentifier
        let lastId       = UserDefaults.standard.string(forKey: Self.lastUploadedAssetKey)
        let lastHash     = UserDefaults.standard.string(forKey: Self.lastUploadedHashKey)
        let instagramHash = UserDefaults.standard.string(forKey: "last_profile_pic_hash")

        // Same asset AND instagram already has this hash → absolutely nothing to do
        if assetId == lastId, let lh = lastHash, lh == instagramHash {
            print("📷 [AUTO PIC] Same photo already on Instagram — skipping (0 API calls)")
            return
        }

        print("📷 [AUTO PIC] New photo detected (assetId changed or hash mismatch) — loading image…")

        // ── Load image only when necessary ──
        guard let imageData = await loadImageData(from: asset) else {
            print("📷 [AUTO PIC] Failed to load image data from asset")
            return
        }

        // Pre-check hash to avoid waitForNetworkStability() for duplicates
        let hash = instagram.hashImageData(imageData)
        if hash == instagramHash {
            UserDefaults.standard.set(assetId, forKey: Self.lastUploadedAssetKey)
            UserDefaults.standard.set(hash,    forKey: Self.lastUploadedHashKey)
            print("📷 [AUTO PIC] Hash matches Instagram — recording asset and skipping upload")
            return
        }

        // Anti-bot: block if any sensitive operation is already in progress.
        // Two concurrent POST operations from the same session is a strong bot signal.
        guard !instagram.isRevealOperationActive else {
            print("📷 [AUTO PIC] Skipped — OCR reveal is active (anti-bot)")
            LogManager.shared.warning("Auto profile pic skipped: OCR reveal active", category: .general)
            return
        }
        // If the session was recently challenged (challenge_required returned for any call),
        // skip the profile-pic POST — it is the most likely cause of escalating to action_blocked.
        guard !instagram.isSessionChallenged else {
            print("📷 [AUTO PIC] Skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Auto profile pic skipped: session recently challenged", category: .general)
            return
        }
        guard !isLoading else {
            print("📷 [AUTO PIC] Skipped — profile refresh is in progress (anti-bot)")
            LogManager.shared.warning("Auto profile pic skipped: profile refresh active", category: .general)
            return
        }

        print("📷 [AUTO PIC] Uploading new profile picture (\(imageData.count / 1024) KB)…")
        // NOTE: isUploadingProfilePic flag is now managed inside changeProfilePicture() itself,
        // so all callers (auto-pic, HomeView manual upload) are covered automatically.

        do {
            let success = try await instagram.changeProfilePicture(imageData: imageData)
            if success, let uiImage = UIImage(data: imageData) {
                UserDefaults.standard.set(assetId, forKey: Self.lastUploadedAssetKey)
                UserDefaults.standard.set(hash,    forKey: Self.lastUploadedHashKey)

                // Show new image in the fake profile immediately — under the current CDN key.
                // pendingProfilePic keeps the image alive so loadProfile() can migrate it to
                // the new CDN URL later; clearing pendingProfilePic triggers the double vibration
                // that confirms the picture is live on Instagram (same as Post Prediction).
                let picURL = profile?.profilePicURL ?? "autoPic_pending"
                cachedImages[picURL] = uiImage
                ProfileCacheService.shared.saveImage(uiImage, forURL: picURL)
                ProfileCacheService.shared.pendingProfilePic = uiImage

                print("📷 [AUTO PIC] ✅ Profile picture updated — showing instantly, vibration pending CDN confirm")
                // If the silent refresh was skipped during upload (anti-bot guard),
                // nextMaxId may still be nil. Schedule a deferred silent refresh
                // so the first pagination doesn't waste a request re-fetching page 1.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if self.nextMaxId == nil {
                        print("📷 [AUTO PIC] Silent refresh deferred — triggering to capture nextMaxId")
                        Task { await self.refreshMediaGridSilently() }
                    }
                }
            }
        } catch {
            print("📷 [AUTO PIC] Upload skipped: \(error.localizedDescription)")
        }

        // Reset exponential backoff so a failed background upload cannot delay
        // user-facing requests (e.g. Explore feed) that run shortly after.
        await instagram.resetBackoff()
    }

    /// Requests Photos read access if not yet determined. Returns true if granted.
    private func requestPhotosPermissionIfNeeded() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    /// Loads full-quality JPEG data from a PHAsset.
    private func loadImageData(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let reqOptions = PHImageRequestOptions()
            reqOptions.deliveryMode = .highQualityFormat
            reqOptions.isNetworkAccessAllowed = true
            reqOptions.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: reqOptions) { data, _, _, _ in
                if let data, let image = UIImage(data: data) {
                    continuation.resume(returning: image.jpegData(compressionQuality: 0.9))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Date Force Auto Mode

    private func handleAutoFollowedByTap() {
        guard dateForce.isEnabled && dateForce.mode == .auto else { return }
        guard !dateForce.isAutoLoading else { return }

        if dateForce.hasSpectators {
            dateForce.toggleAutoDisplayGroup()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            loadAutoFollowers()
        }
    }

    @MainActor
    private func loadAutoFollowers() {
        guard !dateForce.isAutoLoading else { return }
        // ANTI-BOT: Don't fire a multi-profile fetch on top of an active upload,
        // sync/archive, or reveal. The auto-load typically hits 5-10 profiles
        // back-to-back, which during heavy operations becomes a textbook burst.
        // We defer by simply returning — the magician can tap again later.
        if instagram.isHeavyOperationActive {
            print("🛡️ [AUTO] Date Force load skipped — heavy operation active")
            LogManager.shared.warning("Date Force auto-load deferred — heavy op active", category: .general)
            return
        }
        dateForce.isAutoLoading = true

        Task {
            do {
                let manualIds = dateForce.selectedFollowerIds

                if !manualIds.isEmpty {
                    // ── Manual selection: use pre-loaded cache when available ──
                    let half = manualIds.count / 2
                    print("🤖 [AUTO] Loading \(manualIds.count) selected spectators — rank 1-\(half) → 📅 date, rank \(half+1)-\(manualIds.count) → 🕐 time")

                    await MainActor.run {
                        dateForce.beginAutoLoad(totalExpected: manualIds.count)
                    }

                    var needsAPIDelay = false
                    for userId in manualIds {
                        if let cached = dateForce.preloadedProfiles[userId] {
                            // Already pre-loaded while user was in the followers list — instant, no API call
                            await MainActor.run {
                                dateForce.appendAutoSpectator(
                                    username: cached.username,
                                    userId: cached.userId,
                                    profilePicURL: cached.profilePicURL,
                                    followingCount: cached.followingCount,
                                    followerCount: cached.followerCount
                                )
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            print("⚡️ [AUTO] \(cached.username) from cache — no API call")
                        } else {
                            // Not in cache yet — fetch from API with rate-limit delay
                            if needsAPIDelay {
                                try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_400_000_000))
                            }
                            needsAPIDelay = true
                            if let p = try? await instagram.getProfileInfo(userId: userId) {
                                await MainActor.run {
                                    dateForce.appendAutoSpectator(
                                        username: p.username,
                                        userId: p.userId,
                                        profilePicURL: p.profilePicURL,
                                        followingCount: p.followingCount,
                                        followerCount: p.followerCount
                                    )
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else {
                                print("⚠️ [AUTO] Could not fetch profile for userId \(userId)")
                            }
                        }
                    }
                } else {
                    // ── Auto mode: take the N most recent followers ──
                    let count = dateForce.autoSpectatorCount
                    print("🤖 [AUTO] Fetching \(count) most recent followers...")
                    let followers = try await instagram.getRecentFollowers(count: count)

                    let half = followers.count / 2
                    print("🤖 [AUTO] \(followers.count) spectators — rank 1-\(half) → 📅 date, rank \(half+1)-\(followers.count) → 🕐 time")

                    await MainActor.run {
                        dateForce.beginAutoLoad(totalExpected: followers.count)
                    }

                    for (i, follower) in followers.enumerated() {
                        if i > 0 {
                            try? await Task.sleep(nanoseconds: UInt64.random(in: 700_000_000...1_500_000_000))
                        }
                        if let p = try? await instagram.getProfileInfo(
                            userId: follower.userId,
                            usernameHint: follower.username,
                            fullNameHint: follower.fullName,
                            profilePicURLHint: follower.profilePicURL
                        ) {
                            await MainActor.run {
                                dateForce.appendAutoSpectator(
                                    username: follower.username,
                                    userId: follower.userId,
                                    profilePicURL: follower.profilePicURL,
                                    followingCount: p.followingCount,
                                    followerCount: p.followerCount
                                )
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } else {
                            print("⚠️ [AUTO] Could not fetch profile for @\(follower.username)")
                        }
                    }
                }

                await MainActor.run {
                    dateForce.isAutoLoading = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    print("🤖 [AUTO] Done — \(dateForce.spectators.count) spectators loaded")
                }
            } catch {
                print("❌ [AUTO] Error: \(error)")
                await MainActor.run { dateForce.isAutoLoading = false }
            }
        }
    }

}

// MARK: - Instagram Profile View

struct InstagramProfileView: View {
    let profile: InstagramProfile
    @Binding var cachedImages: [String: UIImage]
    let onRefresh: () -> Void          // sync — used by header button
    let onAsyncRefresh: () async -> Void  // async — used by pull-to-refresh
    let onPlusPress: () -> Void
    @State private var selectedTab = 0

    // Infinite scroll support
    var mediaURLs: [String]? = nil // If provided, use instead of profile.cachedMediaURLs
    var onMediaAppear: ((String) -> Void)? = nil // Called when a media cell appears

    // Date Force Auto mode
    @ObservedObject private var dateForce = DateForceSettings.shared
    var onAutoFollowedByTap: (() -> Void)? = nil

    // Amnesia Carousel
    @ObservedObject private var amnesiaSettings = AmnesiaCarouselSettings.shared

    // Optimistic note state — @AppStorage triggers instant re-render on write
    @AppStorage("last_note_text")           private var lastNoteText: String = ""
    @AppStorage("last_note_sent_timestamp") private var lastNoteSentTimestamp: Double = 0

    // Inter-reveal cooldown — shared via AppStorage with PerformanceView (anti-bot)
    @AppStorage("perf_lastRevealCompletedTimestamp") private var lastRevealCompletedTimestamp: Double = 0
    private let interRevealCooldown: TimeInterval = 90

    // Post Prediction visual feedback ring — set true when a PP reveal unarchives ≥1 photo.
    // Read by InstagramBottomBar (orange ring on profile avatar).
    // Reset to false when PerformanceView appears (new trick session).
    @AppStorage("postPredRevealRingActive") private var postPredRevealRingActive: Bool = false

    // Post Prediction input mode — shared key with PerformanceView so both structs
    // read the same UserDefaults value without needing a binding.
    // "off" | "api" | "ocr"
    @AppStorage("ppTopInputMode") private var ppTopInputMode: String = "off"

    // Error alert for when reveal fails (e.g. set not uploaded)
    @State private var revealErrorTitle: String = ""
    @State private var revealErrorMessage: String = ""
    @State private var showRevealError: Bool = false

    // Called after a successful Force Number Reveal with local images already loaded.
    // Each element: pseudo-URL key + optional UIImage from local storage.
    // PerformanceView inserts them into the grid immediately (no GET needed).
    /// Inserts local images into the grid immediately — does NOT trigger CDN refresh.
    /// Use before API unarchive calls so images appear before Instagram processes them.
    var onAddLocalImages: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil
    /// Called after all API unarchives complete — inserts any remaining images AND triggers CDN refresh.
    var onRevealComplete: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil
    /// Called after a successful Amnesia Carousel swap so PerformanceView can
    /// silently refresh the grid and show the new carousel images automatically.
    var onAmnesiaSwapComplete: (() -> Void)? = nil

    // Media items dictionary for post viewer (keyed by imageURL)
    var mediaItemsByURL: [String: InstagramMediaItem] = [:]

    // Passed from PerformanceView so the pull-to-refresh guard can check them.
    var isLoading: Bool = false
    // Called when reveal is blocked because an upload is active.
    var onUploadConflict: (() -> Void)? = nil
    // Called when user taps a follower — PerformanceView handles the overlay.
    var onFollowerTap: ((InstagramFollower) -> Void)? = nil

    // Called when the followers list sheet is dismissed — lets PerformanceView auto-load spectators.
    var onFollowersListDismiss: (() -> Void)? = nil

    /// Set by PerformanceView when OCR recognizes text for Post Prediction.
    /// InstagramProfileView consumes it, routes to word or digit reveal, then clears it.
    @Binding var pendingOCRWord: String?
    /// Set by PerformanceView URL-scheme handler; triggers a custom-set slot reveal.
    @Binding var pendingSlotReveal: Int?
    /// Set by PerformanceView URL-scheme handler; triggers a playing-card reveal.
    @Binding var pendingCardReveal: String?
    /// Set by PerformanceView after the fake lockscreen commits hidden digits.
    @Binding var pendingLockscreenDigits: [Int]?
    /// Called whenever the Posts/Reels/Tagged tab changes so PerformanceView can
    /// trigger lazy loading of secondary tabs on first visit.
    var onTabSelected: ((Int) -> Void)? = nil

    // Single fullScreenCover for posts/reels/tagged — avoids SwiftUI bugs when
    // multiple .fullScreenCover modifiers are stacked on the same view.
    enum ViewerSheet: Identifiable {
        case posts(index: Int)
        case reels(index: Int)
        case tagged(index: Int)
        var id: String {
            switch self { case .posts(let i): return "posts-\(i)"
                          case .reels(let i): return "reels-\(i)"
                          case .tagged(let i): return "tagged-\(i)" }
        }
    }
    @State private var activeViewer: ViewerSheet? = nil
    /// Captures the last-opened posts index so the Amnesia onDismiss handler
    /// can read it after activeViewer has already been cleared to nil.
    @State private var lastPostViewerIndex: Int = 0
    /// Set to true just before presenting a .posts viewer so onDismiss can
    /// distinguish a posts-dismiss from a reels/tagged-dismiss.
    @State private var lastDismissedViewerWasPosts = false

    // Convenience computed properties kept so downstream code compiles unchanged
    private var showingPostViewer: Bool { if case .posts = activeViewer { return true }; return false }
    private var selectedPostIndex: Int { if case .posts(let i) = activeViewer { return i }; return 0 }
    private var selectedReelIndex: Int { if case .reels(let i) = activeViewer { return i }; return 0 }
    private var selectedTaggedIndex: Int { if case .tagged(let i) = activeViewer { return i }; return 0 }

    // Followers list
    @State private var showFollowersList = false
    @State private var showFollowingList = false

    // Secret number input
    @ObservedObject private var secretManager      = SecretNumberManager.shared
    @ObservedObject private var instagram          = InstagramService.shared
    @ObservedObject private var followingMagic     = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor      = VolumeButtonMonitor.shared
    @State private var followingOverride: String?   = nil
    @State private var followerOverride: String?    = nil
    // Transfer effect: inflate own profile after deflating a searched one
    @State private var transferCountdownTimer: Timer? = nil
    @State private var showTransferGlitch = false
    // isTransferCounting lives in FollowingMagicSettings.shared so PerformanceView
    // can read it and block OCR while the animation runs.

    // OCR peek: temporarily shows the recognized text in the Posts stat for 3 seconds
    @State private var postsOCRNumberOverride: String? = nil   // for numeric results
    @State private var postsOCRLabelOverride:  String? = nil   // for word results

    // Effective override for follower/following stats.
    // Transfer phase 2 must stay visually neutral until the magician presses volume.
    // The timer-driven @State below is the only thing allowed to alter the own profile.
    private var effectiveFollowerOverride: String? {
        if let o = followerOverride { return o }
        return nil
    }
    private var effectiveFollowingOverride: String? {
        if let o = followingOverride { return o }
        return nil
    }

    private func logVisibleCountState(reason: String) {
        LogManager.shared.info(
            "Visible counts (\(reason)) @\(profile.username) real followers:\(profile.followerCount) following:\(profile.followingCount) followerOverride:\(followerOverride ?? "nil") followingOverride:\(followingOverride ?? "nil") transferOffset:\(followingMagic.transferOffset) transferCounting:\(followingMagic.isTransferCounting)",
            category: .profile
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                InstagramHeaderView(
                    username: profile.username,
                    isVerified: profile.isVerified,
                    onRefresh: onRefresh,
                    onPlusPress: onPlusPress
                )
                profileInfoSection
                    .padding(.top, 12)
                tabBarSection
                Divider()
                tabContentSection
                // Bottom spacer so the last row of the grid can always be scrolled
                // fully above the floating pill (~54 pt pill height + 8 pt bottom gap + 32 pt margin).
                Color.clear.frame(height: 94)
            }
        }
        .onAppear {
            applyPendingTransferDeflation()
            logVisibleCountState(reason: "profile appear")
        }
        .onChange(of: followingMagic.transferOffset) { _ in
            applyPendingTransferDeflation()
        }
        .onChange(of: followerOverride) { _ in
            logVisibleCountState(reason: "follower override changed")
        }
        .onChange(of: followingOverride) { _ in
            logVisibleCountState(reason: "following override changed")
        }
        // Pull-to-refresh: runs load in an unstructured Task so SwiftUI
            // cancellation doesn't abort the URLSession requests inside loadProfile.
            // The spinner stays visible until the task finishes.
            .refreshable {
                await Task { await onAsyncRefresh() }.value
            }
            .background(Color.white)
        // Race-condition fix for URL-scheme reveals:
        // When vault://reveal?word=X arrives while PerformanceView is loading,
        // pendingOCRWord may be set BEFORE InstagramProfileView enters the hierarchy.
        // SwiftUI's onChange only fires on CHANGES (not on initial value), so the
        // reveal would be silently skipped.  onAppear catches that missed value.
        .onAppear {
            if let word = pendingOCRWord, !word.isEmpty {
                // Re-use the same logic as onChange by briefly clearing and re-setting
                // the value so the onChange fires reliably regardless of timing.
                pendingOCRWord = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    pendingOCRWord = word
                }
            }
        }
        // Keep following count display in sync with digit buffer
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
        // Transfer effect: volume UP on own profile inflates count by saved offset
        .onChange(of: volumeMonitor.upCount) { _ in
            let te  = followingMagic.transferEnabled
            let to  = followingMagic.transferOffset
            let tc  = followingMagic.isTransferCounting
            let stg = showTransferGlitch
            print("🎩 [INFLATE] upCount changed — transferEnabled:\(te) transferOffset:\(to) isTransferCounting:\(tc) showTransferGlitch:\(stg)")
            guard te, to > 0, !tc, !stg else {
                print("🎩 [INFLATE] Guard FAILED — transferEnabled:\(te) offset:\(to) counting:\(tc) glitch:\(stg)")
                return
            }
            let delay = followingMagic.triggerDelay
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    guard followingMagic.transferOffset > 0,
                          !followingMagic.isTransferCounting,
                          !showTransferGlitch else { return }
                    GlitchSoundPlayer.shared.play(style: .electricBuzz)
                    showTransferGlitch = true
                }
            } else {
                GlitchSoundPlayer.shared.play(style: .electricBuzz)
                showTransferGlitch = true
            }
        }
        .overlay {
            if showTransferGlitch {
                GlitchOverlayView {
                    showTransferGlitch = false
                    startTransferInflation()
                }
            }
        }
        .onChange(of: pendingOCRWord) { word in
            guard let word = word, !word.isEmpty else { return }
            pendingOCRWord = nil  // consume immediately
            let fromURL = ForceNumberRevealSettings.shared.urlRevealActive
            ForceNumberRevealSettings.shared.urlRevealActive = false  // reset immediately
            // URL reveals bypass the ocrEnabled guard — they only need the master switch
            guard ppTopInputMode == "ocr" || fromURL else { return }
            guard !UploadManager.shared.isActive else {
                print("⚠️ [OCR-PP] Reveal blocked: upload is active")
                return
            }
            // INTER-REVEAL COOLDOWN (anti-bot)
            let timeSinceLastReveal = Date().timeIntervalSince1970 - lastRevealCompletedTimestamp
            if timeSinceLastReveal < interRevealCooldown {
                let remaining = Int(interRevealCooldown - timeSinceLastReveal)
                print("🚫 [OCR-PP] Reveal blocked — inter-reveal cooldown active (\(remaining)s remaining)")
                LogManager.shared.warning("PP reveal blocked: cooldown \(remaining)s remaining (anti-bot)", category: .api)
                return
            }
            // Anti-bot: if a profile pic upload is running, delay reveal until it finishes.
            // Two simultaneous POST operations from the same session is a bot signal.
            guard !InstagramService.shared.isUploadingProfilePic else {
                print("⚠️ [OCR-PP] Reveal blocked: profile pic upload in progress (anti-bot)")
                LogManager.shared.warning("OCR reveal blocked: profile pic upload active", category: .general)
                // Retry once after a short delay to avoid losing the reveal
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3s
                    guard !InstagramService.shared.isUploadingProfilePic else {
                        print("⚠️ [OCR-PP] Reveal still blocked after 3s wait — aborting")
                        return
                    }
                    // Re-trigger reveal after pic upload finishes
                    await MainActor.run { pendingOCRWord = word }
                }
                return
            }
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cleaned.allSatisfy({ $0.isNumber }) {
                let digits = cleaned.compactMap { Int(String($0)) }
                guard !digits.isEmpty,
                      let activeId = ActiveSetSettings.shared.activeNumberSetId,
                      let set = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) else {
                    print("⚠️ [OCR-PP] No active number set for '\(cleaned)'")
                    return
                }
                print("📷 [OCR-PP] Numeric '\(cleaned)' → revealByDigits \(digits)")
                LogManager.shared.info("OCR Post Prediction (numeric): \(cleaned)", category: .general)
                // Peek: show recognized number in Posts stat for 3 s
                showOCRPeek(number: cleaned)
                Task { await revealByDigits(digits, fromSet: set) }
            } else {
                guard let set = {
                    let dm = DataManager.shared
                    // Prefer pinned active set (even if not uploaded — revealByLetters will diagnose)
                    if let id = ActiveSetSettings.shared.activeWordSetId,
                       let s = dm.sets.first(where: { $0.id == id && $0.type == .word }) { return s }
                    // Fallback: any word set that has uploadd+archived photos ready to reveal
                    return dm.sets.first { $0.type == .word && !$0.banks.isEmpty &&
                        $0.photos.contains(where: { $0.mediaId != nil && $0.isArchived }) }
                }() else {
                    print("⚠️ [OCR-PP] No active word set for '\(cleaned)'")
                    return
                }
                print("📷 [OCR-PP] Word '\(cleaned)' → revealByLetters")
                LogManager.shared.info("OCR Post Prediction (word): \(cleaned)", category: .general)
                // Peek: show recognized word as Posts label for 3 s
                showOCRPeek(label: cleaned)
                Task { await revealByLetters(cleaned, fromSet: set) }
            }
        }
        // ── URL-scheme: Custom Set slot reveal ──────────────────────────────────
        .onChange(of: pendingSlotReveal) { slot in
            guard let slot = slot else { return }
            pendingSlotReveal = nil
            guard let activeId = ActiveSetSettings.shared.activeCustomSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .custom }) else {
                print("⚠️ [URL] pendingSlotReveal: no active custom set")
                return
            }
            showOCRPeek(label: "#\(slot)")
            Task { await revealByCustomSlot(slot, fromSet: activeSet) }
        }
        // ── URL-scheme: Playing Card reveal ─────────────────────────────────────
        .onChange(of: pendingCardReveal) { symbol in
            guard let symbol = symbol, !symbol.isEmpty else { return }
            pendingCardReveal = nil
            guard SetType.cardSlotLabels.contains(symbol) else {
                print("⚠️ [URL] pendingCardReveal: '\(symbol)' is not a valid card symbol")
                return
            }
            guard let activeId = ActiveSetSettings.shared.activeCardSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) else {
                print("⚠️ [URL] pendingCardReveal: no active card set")
                return
            }
            showOCRPeek(label: symbol)
            Task { await revealByCardSlot(symbol: symbol, fromSet: activeSet) }
        }
        // ── Fake lockscreen: Number / Custom / Playing Card reveal ──────────────
        .onChange(of: pendingLockscreenDigits) { digits in
            guard let digits = digits, !digits.isEmpty else { return }
            pendingLockscreenDigits = nil
            routeDigitsFromLockscreen(digits)
        }
        // ── Notify PerformanceView when the tab changes (for lazy loading) ──────
        .onChange(of: selectedTab) { tab in
            onTabSelected?(tab)
        }
        .alert(revealErrorTitle, isPresented: $showRevealError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(revealErrorMessage)
        }
    }

    // MARK: - Lockscreen Reveal Routing

    private func routeDigitsFromLockscreen(_ digits: [Int]) {
        let input = digits.map(String.init).joined()
        print("🔒 [LOCKSCREEN] Routing committed digits: \(input)")
        LogManager.shared.info("Lockscreen input committed: \(input)", category: .general)

        secretManager.reset()
        followingOverride = nil
        followerOverride = nil

        guard !UploadManager.shared.isActive else {
            print("⚠️ [LOCKSCREEN] Reveal blocked: upload is active")
            LogManager.shared.warning("Lockscreen reveal blocked: upload in progress", category: .general)
            onUploadConflict?()
            return
        }

        // Cards are checked first because inputs like 061 are intentionally a card code
        // (0 + value + suit), while number/custom reveals remain available as fallback.
        if let activeId = ActiveSetSettings.shared.activeCardSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }),
           let (value, suit) = decodeCardInput(digits) {
            let symbol = cardSymbol(value: value, suit: suit)
            showOCRPeek(label: symbol)
            Task { await revealByCardSlot(symbol: symbol, fromSet: activeSet) }
            return
        }

        let slot = digits.reduce(0) { $0 * 10 + $1 }
        if slot >= 1,
           let activeId = ActiveSetSettings.shared.activeCustomSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .custom }) {
            showOCRPeek(label: "#\(slot)")
            Task { await revealByCustomSlot(slot, fromSet: activeSet) }
            return
        }

        if let activeId = ActiveSetSettings.shared.activeNumberSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) {
            showOCRPeek(number: input)
            Task { await revealByDigits(digits, fromSet: activeSet) }
            return
        }

        print("⚠️ [LOCKSCREEN] No active number/custom/card set for input \(input)")
        LogManager.shared.warning("Lockscreen input \(input) ignored: no active reveal set", category: .general)
    }

    // MARK: - OCR Peek

    /// Briefly shows the OCR-recognized value in the Posts stat for 3 seconds, then reverts.
    /// - number: passes the text as the count override (e.g. "425")
    /// - label:  passes the text as the label override (e.g. "coche")
    /// Shows the recognized text in the "seguidos" stat immediately.
    /// The override stays until clearOCRPeek() is called (when all unarchives finish).
    private func showOCRPeek(number: String? = nil, label: String? = nil) {
        withAnimation(.easeInOut(duration: 0.25)) {
            postsOCRNumberOverride = number
            postsOCRLabelOverride  = label
        }
    }

    /// Clears the "seguidos" override with a fade animation.
    private func clearOCRPeek() {
        withAnimation(.easeInOut(duration: 0.35)) {
            postsOCRNumberOverride = nil
            postsOCRLabelOverride  = nil
        }
    }

    // MARK: - Body sub-sections

    @ViewBuilder private var profileInfoSection: some View {
        VStack(spacing: seAdapt(12, 16)) {
                    HStack(alignment: .center, spacing: 0) {

                        // ── Profile picture ──────────────────────────────────────────
                        // The note bubble is an overlay so it NEVER affects the HStack layout.
                        // Placed with a negative y-offset it floats above the profile circle
                        // without pushing the name/stats column to the right.
                        let noteIsActive = !lastNoteText.isEmpty
                            && lastNoteSentTimestamp > 0
                            && Date().timeIntervalSince1970 - lastNoteSentTimestamp < 86400

                        ZStack(alignment: .bottomTrailing) {
                        let picSize: CGFloat = seAdapt(77, 86)
                            // Inner centered ZStack: ring + white gap + photo are all
                            // centred relative to each other so the ring wraps evenly.
                            ZStack {
                                // Outer gradient ring — visible only after a PP reveal succeeds
                                if postPredRevealRingActive {
                                    Circle()
                                        .stroke(
                                            AngularGradient(
                                                colors: [
                                                    Color(red: 0.99, green: 0.78, blue: 0.12),
                                                    Color(red: 0.99, green: 0.42, blue: 0.13),
                                                    Color(red: 0.90, green: 0.14, blue: 0.49),
                                                    Color(red: 0.52, green: 0.17, blue: 0.83),
                                                    Color(red: 0.99, green: 0.78, blue: 0.12)
                                                ],
                                                center: .center
                                            ),
                                            lineWidth: 3
                                        )
                                        .frame(width: picSize + 8, height: picSize + 8)
                                    // White gap between gradient ring and photo
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: picSize + 4, height: picSize + 4)
                                }
                                if let image = cachedImages[profile.profilePicURL] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: picSize, height: picSize)
                                        .clipShape(Circle())
                                        .onAppear { print("✅ [UI] Profile pic image displayed") }
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: picSize, height: picSize)
                                        .overlay(ProgressView().scaleEffect(0.8))
                                        .onAppear {
                                            print("⚠️ [UI] Profile pic not in cache")
                                            print("⚠️ [UI] Looking for URL: \(String(profile.profilePicURL.prefix(80)))")
                                            print("⚠️ [UI] Available cached URLs: \(cachedImages.keys.map { String($0.prefix(40)) }.joined(separator: ", "))")
                                        }
                                }
                            }
                            // Blue ➕ button stays anchored to the bottom-right of the outer ZStack
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                    }
                    .onTapGesture {
                        let username = profile.username
                        if let appURL = URL(string: "instagram://user?username=\(username)"),
                           UIApplication.shared.canOpenURL(appURL) {
                            UIApplication.shared.open(appURL)
                        } else if let webURL = URL(string: "https://www.instagram.com/\(username)/") {
                            UIApplication.shared.open(webURL)
                        }
                    }
                        // Note bubble floats ABOVE the profile circle — overlay keeps it
                        // outside the layout flow so nothing shifts to the right.
                        .overlay(alignment: .top) {
                            if noteIsActive {
                                NotesBubbleView(text: lastNoteText)
                                    .fixedSize()
                                    // Negative offset: lifts the bubble above the profile circle.
                                    // Dot intentionally overlaps the top of the profile picture.
                                    .offset(y: -26)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.leading, UIScreen.main.bounds.width * 0.04)
                        
                        Spacer(minLength: 8)
                        
                // Columna derecha: nombre encima de los stats
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.fullName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)

                        HStack(spacing: 0) {
                        StatView(number: profile.mediaCount, label: String(localized: "ig.stat.posts"))
                            .frame(maxWidth: .infinity)

                        Button {
                            if FollowingMagicSettings.shared.isEnabled && SecretNumberManager.shared.hasDigits {
                                FollowingMagicSettings.shared.captureFromBuffer(source: "followers-list")
                            }
                            showFollowersList = true
                        } label: {
                            StatView(number: profile.followerCount, label: String(localized: "ig.stat.followers"),
                                     overrideText: effectiveFollowerOverride)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button {
                            if FollowingMagicSettings.shared.isEnabled && SecretNumberManager.shared.hasDigits {
                                FollowingMagicSettings.shared.captureFromBuffer(source: "following-list")
                            }
                            showFollowingList = true
                        } label: {
                            StatView(number: profile.followingCount, label: String(localized: "ig.stat.following"),
                                     overrideText: postsOCRNumberOverride ?? effectiveFollowingOverride,
                                     overrideLabel: postsOCRLabelOverride)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                        }
                        .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if !profile.biography.isEmpty {
                            Text(profile.biography)
                                .font(.system(size: 14))
                        .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let url = profile.externalUrl {
                    Text(url)
                                .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.0, green: 0.36, blue: 0.73))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
                    if !profile.followedBy.isEmpty {
                FollowedByView(
                    followers: profile.followedBy,
                    cachedImages: cachedImages,
                    onFollowerTap: onFollowerTap
                )
                            .responsiveHorizontalPadding()
                    }
                    
            let btnH: CGFloat = seAdapt(28, 32)
                    HStack(spacing: 8) {
                        Button(action: {}) {
                    Text("ig.edit_profile")
                        .font(.system(size: seAdapt(13, 14), weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: btnH)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .foregroundColor(.black).cornerRadius(8)
                }
                        Button(action: {}) {
                    Text("ig.share_profile")
                        .font(.system(size: seAdapt(13, 14), weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: btnH)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .foregroundColor(.black).cornerRadius(8)
                }
                        Button(action: {}) {
                    IGIcon(asset: "instagram_follow", fallback: "person.badge.plus", size: seAdapt(14, 16))
                        .frame(width: btnH, height: btnH)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                                .cornerRadius(8)
                        }
                    }
                    .responsiveHorizontalPadding()
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                    let storySize: CGFloat = seAdapt(56, 64)
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .frame(width: storySize, height: storySize)
                            .overlay(Image(systemName: "plus").foregroundColor(.black))
                        Text("ig.new")
                            .font(.system(size: seAdapt(10, 12)))
                            .foregroundColor(.black)
                    }
                    if profile.cachedHighlights.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(spacing: 4) {
                                Circle().fill(Color.gray.opacity(0.2)).frame(width: storySize, height: storySize)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: seAdapt(36, 44), height: 10)
                            }
                        }
                    } else {
                        ForEach(profile.cachedHighlights) { highlight in
                            StoryHighlightCell(highlight: highlight,
                                               image: cachedImages[highlight.coverImageURL])
                                }
                            }
                        }
                        .responsiveHorizontalPadding()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.vertical, 12)
    }
                
    @ViewBuilder private var tabBarSection: some View {
                HStack(spacing: 0) {
            TabButton(icon: "square.grid.3x3", activeAsset: "instagram_grid_active", inactiveAsset: "instagram_grid_inactive", isSelected: selectedTab == 0) {
                if ForceNumberRevealSettings.shared.isEnabled,
                   ForceNumberRevealSettings.shared.gridSwipeEnabled,
                   secretManager.hasDigits,
                   let activeId = ActiveSetSettings.shared.activeNumberSetId,
                   let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) {
                    let digits = secretManager.digitBuffer
                    let digitLabel = digits.map(String.init).joined()
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil

                    // Block reveal if an upload is active — they share the same hourly rate limit
                    if UploadManager.shared.isActive {
                        print("⚠️ [FORCE#] Reveal blocked: upload is active (shared rate limit)")
                        LogManager.shared.warning("Force reveal blocked: upload in progress — try after upload completes", category: .general)
                        onUploadConflict?()
                    } else {
                        // Show recognized number in "seguidos" immediately while unarchiving
                        showOCRPeek(number: digitLabel)
                        Task { await revealByDigits(digits, fromSet: activeSet) }
                    }

                } else if ForceNumberRevealSettings.shared.isEnabled,
                          ForceNumberRevealSettings.shared.gridSwipeEnabled,
                          secretManager.hasDigits,
                          let activeId = ActiveSetSettings.shared.activeCustomSetId,
                          let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .custom }) {
                    // Custom set: all digits form the slot number (1–100)
                    // e.g. [7] → 7, [1,5] → 15, [1,0,0] → 100
                    let slot = secretManager.digitBuffer.reduce(0) { $0 * 10 + $1 }
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil

                    if UploadManager.shared.isActive {
                        print("⚠️ [CUSTOM] Reveal blocked: upload is active")
                        LogManager.shared.warning("Custom reveal blocked: upload in progress", category: .general)
                        onUploadConflict?()
                    } else if slot >= 1 {
                        showOCRPeek(label: "#\(slot)")
                        Task { await revealByCustomSlot(slot, fromSet: activeSet) }
                    }

                } else if ForceNumberRevealSettings.shared.isEnabled,
                          ForceNumberRevealSettings.shared.gridSwipeEnabled,
                          secretManager.hasDigits,
                          let activeId = ActiveSetSettings.shared.activeCardSetId,
                          let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) {
                    // Card set: decode 2 or 3 digits → card symbol (e.g. "J♠", "10♥")
                    let digits = secretManager.digitBuffer
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil

                    if UploadManager.shared.isActive {
                        print("⚠️ [CARD] Reveal blocked: upload is active")
                        LogManager.shared.warning("Card reveal blocked: upload in progress", category: .general)
                        onUploadConflict?()
                    } else if let (value, suit) = decodeCardInput(digits) {
                        let symbol = cardSymbol(value: value, suit: suit)
                        showOCRPeek(label: symbol)
                        Task { await revealByCardSlot(symbol: symbol, fromSet: activeSet) }
                    } else {
                        print("⚠️ [CARD] Invalid digit sequence: \(digits) — need [value, suit] or [tens, units, suit]")
                        LogManager.shared.warning("Card reveal: invalid input \(digits.map(String.init).joined())", category: .general)
                    }

                } else {
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil
                }
                        selectedTab = 0
                    }
            TabButton(icon: "play.rectangle", activeAsset: "instagram_reels_active", inactiveAsset: "instagram_reels_inactive", isSelected: selectedTab == 1) {
                        selectedTab = 1
                secretManager.reset()
                followingOverride = nil; followerOverride = nil
                    }
            TabButton(icon: "person.crop.square", activeAsset: "instagram_tagged_active", inactiveAsset: "instagram_tagged_inactive", isSelected: selectedTab == 2) {
                        selectedTab = 2
                secretManager.reset()
                followingOverride = nil; followerOverride = nil
                    }
                }
                .frame(height: 44)
    }

    @ViewBuilder private var tabContentSection: some View {
        Group {
            switch selectedTab {
            case 0:
                let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
                PhotosGridView(
                    mediaURLs: urlsToShow,
                    cachedImages: cachedImages,
                    onMediaAppear: onMediaAppear,
                    onTapIndex: { index in
                        lastPostViewerIndex = index
                        lastDismissedViewerWasPosts = true
                        activeViewer = .posts(index: index)
                    }
                )
            case 1:
                ReelsGridView(
                    reelURLs: profile.cachedReelURLs,
                    cachedImages: cachedImages,
                    reelItems: profile.cachedReelItems,
                    onTapIndex: { index in
                        activeViewer = .reels(index: index)
                    }
                )
            case 2:
                if profile.cachedTaggedURLs.isEmpty {
                    TaggedEmptyStateView()
                } else {
                    PhotosGridView(
                        mediaURLs: profile.cachedTaggedURLs,
                        cachedImages: cachedImages,
                        onTapIndex: { index in
                            activeViewer = .tagged(index: index)
                        }
                    )
                }
            default:
                EmptyView()
            }
        }
        .coordinateSpace(name: "secretGrid")
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .named("secretGrid"))
                .onEnded { value in handleGridSwipe(value) }
        )
        .fullScreenCover(item: $activeViewer, onDismiss: {
            // Amnesia Carousel trigger fires only when a POSTS viewer is dismissed.
            // activeViewer is already nil here so we use lastPostViewerIndex.
            guard lastDismissedViewerWasPosts else { return }
            lastDismissedViewerWasPosts = false
            let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
            if amnesiaSettings.isEnabled,
               amnesiaSettings.isReady,
               !amnesiaSettings.isRevealed,
               let shortId = amnesiaSettings.shortCarouselMediaId,
               lastPostViewerIndex < urlsToShow.count
            {
                let viewedURL  = urlsToShow[lastPostViewerIndex]
                let viewedItem = mediaItemsByURL[viewedURL]
                if viewedItem?.mediaId == shortId || viewedURL.contains(shortId) {
                    triggerAmnesiaSwap()
                }
            }
        }) { sheet in
            switch sheet {
            case .posts(let index):
                let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
                PostScrollView(
                    mediaURLs: urlsToShow,
                    mediaItemsByURL: mediaItemsByURL,
                    cachedImages: cachedImages,
                    initialIndex: index,
                    username: profile.username,
                    profileImage: cachedImages[profile.profilePicURL],
                    userId: profile.userId
                )
            case .reels(let index):
                let reelMap = Dictionary(uniqueKeysWithValues: profile.cachedReelItems.map { ($0.imageURL, $0) })
                PostScrollView(
                    mediaURLs: profile.cachedReelURLs,
                    mediaItemsByURL: reelMap,
                    cachedImages: cachedImages,
                    initialIndex: index,
                    username: profile.username,
                    profileImage: cachedImages[profile.profilePicURL],
                    userId: profile.userId
                )
            case .tagged(let index):
                PostScrollView(
                    mediaURLs: profile.cachedTaggedURLs,
                    mediaItemsByURL: mediaItemsByURL,
                    cachedImages: cachedImages,
                    initialIndex: index,
                    username: profile.username,
                    profileImage: cachedImages[profile.profilePicURL],
                    userId: profile.userId
                )
            }
        }
        .fullScreenCover(isPresented: $showFollowersList, onDismiss: {
            onFollowersListDismiss?()
        }) {
            FollowersListView(
                username: profile.username,
                followerCount: profile.followerCount,
                followingCount: profile.followingCount,
                onClose: { showFollowersList = false },
                mode: .followers
            )
            .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showFollowingList, onDismiss: {
            onFollowersListDismiss?()
        }) {
            FollowersListView(
                username: profile.username,
                followerCount: profile.followerCount,
                followingCount: profile.followingCount,
                onClose: { showFollowingList = false },
                mode: .following
            )
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Secret number gesture handling

    private func handleGridSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let absDx = abs(dx)
        let absDy = abs(dy)

        // Require a clearly horizontal gesture: horizontal travel must be
        // at least 2.5× the vertical drift AND at least 60 pt in total.
        // This prevents accidental tab switches during vertical scrolling where
        // the finger drifts slightly sideways (e.g. dx=35/dy=25 no longer qualifies).
        let isHorizontal = absDx > absDy * 2.5 && absDx > 60
        let isVertical   = absDy > absDx && absDy > 40

        guard isHorizontal else { return }

        // Register digit from the row where the swipe started
        let gridWidth = UIScreen.main.bounds.width
        let digit = SecretNumberManager.digit(
            x: value.startLocation.x,
            y: value.startLocation.y,
            gridWidth: gridWidth
        )
        secretManager.addDigit(digit)
        updateFollowingOverride()

        // Every accepted secret swipe must also change tabs. At the edges,
        // bounce inward so a right swipe on Posts still moves to Reels instead
        // of registering a digit while the screen appears unchanged.
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = tabAfterSecretSwipe(dx: dx)
        }
    }

    private func tabAfterSecretSwipe(dx: CGFloat) -> Int {
        if dx < 0 {
            return selectedTab < 2 ? selectedTab + 1 : 1
        }
        return selectedTab > 0 ? selectedTab - 1 : 1
    }

    private func updateFollowingOverride() {
        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
            followerOverride  = nil
        } else if followingMagic.targetFollowers {
            followingOverride = nil
            followerOverride  = secretManager.followingDisplayString(originalCount: profile.followerCount)
                    } else {
            followerOverride  = nil
            followingOverride = secretManager.followingDisplayString(originalCount: profile.followingCount)
        }
    }

    private func applyPendingTransferDeflation() {
        guard followingMagic.transferEnabled,
              followingMagic.transferOffset > 0,
              !followingMagic.isTransferCounting else { return }

        let offset = followingMagic.transferOffset
        let useFollowers = followingMagic.targetFollowers
        let realCount = useFollowers ? profile.followerCount : profile.followingCount
        let offsetMode = followingMagic.offsetMode(for: realCount)
        let startCount = max(0, realCount - offset)
        let text = formatMagicCount(startCount)

        if useFollowers {
            followerOverride = text
            followingOverride = nil
        } else {
            followingOverride = text
            followerOverride = nil
        }

        LogManager.shared.info(
            "Counter own-inflate prepared @\(profile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) effectiveOffset:\(offset) mode:\(offsetMode) start:\(startCount) end:\(realCount)",
            category: .profile
        )
    }

    /// Inflates own following/followers from realCount - transferOffset up to the real count.
    /// This makes phase 2 end on the verifiable real Instagram value.
    private func startTransferInflation() {
        let offset     = followingMagic.transferOffset
        let useFollowers = followingMagic.targetFollowers
        let realCount  = useFollowers
            ? profile.followerCount
            : profile.followingCount
        let offsetMode = followingMagic.offsetMode(for: realCount)
        let startCount = max(0, realCount - offset)
        // Step size scales with the animation range so it always finishes in countdownDuration.
        // K-mode minimum is 100 (= 0.1 K per visual update).
        let range = max(1, realCount - startCount)
        let minStep = realCount >= 10_000 ? 100 : 1
        let stepSize = max(minStep, range / 200)
        let visibleSteps = max(1, range / stepSize)
        let totalMs    = followingMagic.countdownDuration * 1000
        let intervalMs = max(16, totalMs / max(1, visibleSteps))

        followingMagic.isTransferCounting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        var current = startCount
        LogManager.shared.info(
            "Counter own-inflate started @\(profile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) effectiveOffset:\(offset) mode:\(offsetMode) start:\(startCount) end:\(realCount)",
            category: .profile
        )

        transferCountdownTimer = Timer.scheduledTimer(
            withTimeInterval: Double(intervalMs) / 1000.0,
            repeats: true
        ) { timer in
            current += stepSize
            let displayCurrent = min(current, realCount)
            let text = self.formatMagicCount(displayCurrent)
            if useFollowers {
                self.followerOverride  = text
                self.followingOverride = nil
            } else {
                self.followingOverride = text
                self.followerOverride  = nil
            }
            if displayCurrent >= realCount {
                timer.invalidate()
                self.transferCountdownTimer = nil
                self.followerOverride  = nil
                self.followingOverride = nil
                self.followingMagic.isTransferCounting = false
                self.followingMagic.transferOffset = 0
                VolumeButtonMonitor.shared.stopMonitoring()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                LogManager.shared.info(
                    "Counter own-inflate completed @\(self.profile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) effectiveOffset:\(offset) mode:\(offsetMode)",
                    category: .profile
                )
                print("🎩 [TRANSFER] Inflation complete — back to real: \(self.formatMagicCount(realCount))")
            }
        }
    }

    /// Formats a count for magic counter display, matching StatView for 4-digit values.
    private func formatMagicCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000
            return value == value.rounded() ? String(format: "%.0fM", value) : String(format: "%.1fM", value)
        } else if count >= 10_000 {
            let value = Double(count) / 1_000
            return value == value.rounded() ? String(format: "%.0fK", value) : String(format: "%.1fK", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - Force Number Reveal

    /// Unarchives the photo matching each digit in the corresponding bank, sequentially.
    /// Digit at position i (0-based) → bank i+1 → find photo with symbol == String(digit).
    private func revealByDigits(_ digits: [Int], fromSet set: PhotoSet) async {
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        // Signal operation start — blocks pull-to-refresh while running
        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        // BACKGROUND PROTECTION: request extra execution time from iOS so the
        // full reveal completes even if the user minimises the app mid-reveal.
        // iOS grants ~30s for a background task; reveals take ~5-25s for most
        // sets (anti-bot delays + API calls), so this is sufficient.
        let bgTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "RevealDigits") { }
        }
        defer {
            Task { await MainActor.run { UIApplication.shared.endBackgroundTask(bgTask) } }
        }

        // Secondary guard: block if upload became active between button tap and Task execution
        if UploadManager.shared.isActive {
            print("⚠️ [FORCE#] Reveal aborted inside task: upload became active (shared rate limit)")
            LogManager.shared.warning("Force reveal aborted: upload became active after tap", category: .general)
            return
        }

        // Digits are read right-to-left: last digit → bank 1, second-to-last → bank 2, etc.
        // e.g. 568 → bank1=8, bank2=6, bank3=5
        let reversedDigits = digits.reversed()

        print("🔢 [FORCE#] ═══════════════════════════════════════")
        print("🔢 [FORCE#] Revealing digits: \(digits.map { String($0) }.joined()) (reversed: \(reversedDigits.map { String($0) }.joined())) from set '\(set.name)'")
        LogManager.shared.info("Force number reveal: \(digits.map { String($0) }.joined()) from set '\(set.name)'", category: .general)

        var successCount  = 0
        var skipCount     = 0
        var failCount     = 0
        var revealedIds: [String] = []           // only IDs actually unarchived via API in this session
        var revealedPhotos: [(pseudoURL: String, image: UIImage?)] = [] // for instant grid update

        // Cancel any previous pending re-archive before starting a new reveal
        ForceNumberRevealSettings.shared.cancelPendingReArchive()

        for (i, digit) in reversedDigits.enumerated() {
            // Stop if lockdown activates mid-reveal
            guard !instagram.isLocked else {
                print("🚨 [FORCE#] Lockdown active — stopping reveal")
                break
            }

            guard i < sortedBanks.count else {
                print("⚠️ [FORCE#] No bank at position \(i + 1) — skipping digit \(digit)")
                failCount += 1
                continue
            }

            let bank         = sortedBanks[i]
            let symbol       = String(digit)
            let photosInBank = set.photos.filter { $0.bankId == bank.id }

            // Already unarchived locally → skip API call.
            // IMPORTANT: do NOT add to revealedIds — we didn't unarchive it in this session,
            // so scheduling a re-archive would risk archiving something already archived on
            // Instagram (state-desync) which triggers bot detection.
            if let alreadyVisible = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }),
               let visibleMediaId = alreadyVisible.mediaId {
                print("ℹ️ [FORCE#] Digit \(digit) bank \(i + 1): already unarchived locally — skipping API call, inserting in fake grid")
                let localImage: UIImage? = alreadyVisible.imageData.flatMap { UIImage(data: $0) }
                revealedPhotos.append((pseudoURL: "reveal://\(visibleMediaId)", image: localImage))
                skipCount += 1
                continue
            }

            // Find archived photo → need API call
            guard let photo = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
                  let mediaId = photo.mediaId else {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1): no archived photo found with symbol '\(symbol)'")
                failCount += 1
                continue
            }

            // Anti-bot: random human-like delay before each unarchive
            let delay = UInt64.random(in: 800_000_000...2_200_000_000)
            try? await Task.sleep(nanoseconds: delay)

            do {
                // skipPreCheck: photo.isArchived == true already verified at line 2729
                let unarchived = try await instagram.unarchivePhoto(mediaId: mediaId, skipPreCheck: true)
                if unarchived {
                    dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                            isArchived: false, uploadStatus: .completed, errorMessage: nil,
                                            uploadDate: photo.uploadDate)
                    print("✅ [FORCE#] Digit \(digit) bank \(i + 1): unarchived (ID: \(mediaId))")
                    LogManager.shared.success("Force reveal digit \(digit) bank \(i + 1) (ID: \(mediaId))", category: .general)
                    revealedIds.append(mediaId)
                    successCount += 1

                    // Load local image so PerformanceView can insert it instantly (no GET needed)
                    let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
                    revealedPhotos.append((pseudoURL: "reveal://\(mediaId)", image: localImage))
                    print("🖼️ [FORCE#] Local image \(localImage != nil ? "loaded" : "not found") for \(mediaId)")
                } else {
                    print("⚠️ [FORCE#] Digit \(digit) bank \(i + 1): unarchive returned false")
                    failCount += 1
                }
            } catch {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1) error: \(error)")
                LogManager.shared.error("Force reveal error digit \(digit) bank \(i + 1): \(error.localizedDescription)", category: .general)
                failCount += 1
                let msg = error.localizedDescription.lowercased()
                if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                    UploadManager.shared.sendSessionExpiredNotification()
                }
            }
        }

        print("🔢 [FORCE#] Done — \(successCount) ok, \(skipCount) skipped, \(failCount) failed")

        // Schedule auto re-archive if enabled and we have IDs to re-archive
        if !revealedIds.isEmpty {
            ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: revealedIds)
        }

        // If at least one photo was actually unarchived via API, pass local images
        // to PerformanceView for an immediate grid update — no GET call needed.
        if successCount > 0 {
            onRevealComplete?(revealedPhotos)
        }

        // All unarchives done — clear the "seguidos" override
        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - Custom Set Reveal

    /// Unarchives the single photo at the given slot number in the active custom set.
    /// Slot number maps directly to the photo's `symbol` (e.g. slot 3 → symbol "3").
    /// Uses the same anti-bot delays, rate-limit guards, and re-archive scheduling as
    /// the number reveal, but without the multi-bank logic (custom has one bank).
    private func revealByCustomSlot(_ slot: Int, fromSet set: PhotoSet) async {
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared
        let symbol = String(slot)

        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        let bgTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "RevealCustom") { }
        }
        defer {
            Task { await MainActor.run { UIApplication.shared.endBackgroundTask(bgTask) } }
        }

        if UploadManager.shared.isActive {
            print("⚠️ [CUSTOM] Reveal aborted: upload became active")
            return
        }

        print("🖼️ [CUSTOM] ═══════════════════════════════════════")
        print("🖼️ [CUSTOM] Revealing slot \(slot) from set '\(set.name)'")
        LogManager.shared.info("Custom set reveal: slot \(slot) from '\(set.name)'", category: .general)

        ForceNumberRevealSettings.shared.cancelPendingReArchive()

        // Already unarchived locally → nothing to do
        if set.photos.contains(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
            print("ℹ️ [CUSTOM] Slot \(slot): already unarchived locally — inserting in fake grid")
            if let visiblePhoto = set.photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }),
               let visibleMediaId = visiblePhoto.mediaId {
                let localImage: UIImage? = visiblePhoto.imageData.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    onRevealComplete?([(pseudoURL: "reveal://\(visibleMediaId)", image: localImage)])
                }
            }
            await MainActor.run { clearOCRPeek() }
            return
        }

        guard let photo = set.photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
              let mediaId = photo.mediaId else {
            print("❌ [CUSTOM] Slot \(slot): no archived photo with symbol '\(symbol)'")
            LogManager.shared.warning("Custom reveal: slot \(slot) not found or not uploaded in '\(set.name)'", category: .general)
            await MainActor.run {
                revealErrorTitle = String(localized: "reveal.error.title")
                revealErrorMessage = String(format: String(localized: "ig.set_not_uploaded_body"), set.name)
                showRevealError = true
                clearOCRPeek()
            }
            return
        }

        // Anti-bot: human-like delay
        let delay = UInt64.random(in: 800_000_000...2_200_000_000)
        try? await Task.sleep(nanoseconds: delay)

        do {
            let unarchived = try await instagram.unarchivePhoto(mediaId: mediaId, skipPreCheck: true)
            if unarchived {
                dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                        isArchived: false, uploadStatus: .completed, errorMessage: nil,
                                        uploadDate: photo.uploadDate)
                print("✅ [CUSTOM] Slot \(slot) unarchived (ID: \(mediaId))")
                LogManager.shared.success("Custom reveal slot \(slot) ok (ID: \(mediaId))", category: .general)

                // Schedule auto re-archive
                ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: [mediaId])

                // Instant grid update with local image
                let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    onRevealComplete?([(pseudoURL: "reveal://\(mediaId)", image: localImage)])
                }
            } else {
                print("⚠️ [CUSTOM] Slot \(slot): unarchive returned false")
            }
        } catch {
            print("❌ [CUSTOM] Slot \(slot) error: \(error)")
            LogManager.shared.error("Custom reveal slot \(slot) error: \(error.localizedDescription)", category: .general)
            let msg = error.localizedDescription.lowercased()
            if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                UploadManager.shared.sendSessionExpiredNotification()
            }
        }

        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - Playing Card Reveal

    /// Decode a 2- or 3-digit buffer into a card value (1–13) and suit (1–4).
    ///
    /// - 2 digits [v, s]      → value = v  (1=A … 9=9),   suit = s
    /// - 3 digits [0, v, s]   → value = v  (leading-zero alias, e.g. 061 = 6♠)
    /// - 3 digits [t, u, s]   → value = t×10+u (10, 11=J, 12=Q, 13=K), suit = s
    ///
    /// Returns `nil` for invalid input (wrong digit count, out-of-range value/suit).
    private func decodeCardInput(_ digits: [Int]) -> (value: Int, suit: Int)? {
        switch digits.count {
        case 2:
            let value = digits[0], suit = digits[1]
            guard (1...9).contains(value), (1...4).contains(suit) else { return nil }
            return (value, suit)
        case 3:
            let value = digits[0] == 0 ? digits[1] : digits[0] * 10 + digits[1]
            let suit = digits[2]
            let validValue = digits[0] == 0 ? (1...9).contains(value) : (10...13).contains(value)
            guard validValue, (1...4).contains(suit) else { return nil }
            return (value, suit)
        default:
            return nil
        }
    }

    /// Convert a numeric value (1–13) and suit index (1=♠, 2=♥, 3=♣, 4=♦) to
    /// the card symbol string used as the photo's `symbol` in the deck set.
    private func cardSymbol(value: Int, suit: Int) -> String {
        let v: String
        switch value {
        case 1:  v = "A"
        case 11: v = "J"
        case 12: v = "Q"
        case 13: v = "K"
        default: v = String(value)
        }
        let suits = ["♠", "♥", "♣", "♦"]
        let s = (1...4).contains(suit) ? suits[suit - 1] : "?"
        return "\(v)\(s)"
    }

    /// Unarchives the photo matching `symbol` in the active card set.
    /// Identical flow to `revealByCustomSlot` — anti-bot delays, rate-limit guards,
    /// re-archive scheduling, and instant grid update.
    private func revealByCardSlot(symbol: String, fromSet set: PhotoSet) async {
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        let bgTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "RevealCard") { }
        }
        defer {
            Task { await MainActor.run { UIApplication.shared.endBackgroundTask(bgTask) } }
        }

        if UploadManager.shared.isActive {
            print("⚠️ [CARD] Reveal aborted: upload became active")
            return
        }

        print("🃏 [CARD] ═══════════════════════════════════════")
        print("🃏 [CARD] Revealing \(symbol) from set '\(set.name)'")
        LogManager.shared.info("Card set reveal: \(symbol) from '\(set.name)'", category: .general)

        ForceNumberRevealSettings.shared.cancelPendingReArchive()

        if set.photos.contains(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
            print("ℹ️ [CARD] \(symbol): already unarchived locally — inserting in fake grid")
            if let visiblePhoto = set.photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }),
               let visibleMediaId = visiblePhoto.mediaId {
                let localImage: UIImage? = visiblePhoto.imageData.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    onRevealComplete?([(pseudoURL: "reveal://\(visibleMediaId)", image: localImage)])
                }
            }
            await MainActor.run { clearOCRPeek() }
            return
        }

        guard let photo = set.photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
              let mediaId = photo.mediaId else {
            print("❌ [CARD] \(symbol): no archived photo found — slot not uploaded?")
            LogManager.shared.warning("Card reveal: \(symbol) not found or not uploaded in '\(set.name)'", category: .general)
            await MainActor.run {
                revealErrorTitle = String(localized: "reveal.error.title")
                revealErrorMessage = String(format: String(localized: "ig.set_not_uploaded_body"), set.name)
                showRevealError = true
                clearOCRPeek()
            }
            return
        }

        let delay = UInt64.random(in: 800_000_000...2_200_000_000)
        try? await Task.sleep(nanoseconds: delay)

        do {
            let unarchived = try await instagram.unarchivePhoto(mediaId: mediaId, skipPreCheck: true)
            if unarchived {
                dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                        isArchived: false, uploadStatus: .completed, errorMessage: nil,
                                        uploadDate: photo.uploadDate)
                print("✅ [CARD] \(symbol) unarchived (ID: \(mediaId))")
                LogManager.shared.success("Card reveal \(symbol) ok (ID: \(mediaId))", category: .general)

                ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: [mediaId])

                let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    onRevealComplete?([(pseudoURL: "reveal://\(mediaId)", image: localImage)])
                }
            } else {
                print("⚠️ [CARD] \(symbol): unarchive returned false")
            }
        } catch {
            print("❌ [CARD] \(symbol) error: \(error)")
            LogManager.shared.error("Card reveal \(symbol) error: \(error.localizedDescription)", category: .general)
            let msg = error.localizedDescription.lowercased()
            if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                UploadManager.shared.sendSessionExpiredNotification()
            }
        }

        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - OCR Post Prediction: reveal by letters (word set)

    /// Reveals a word by unarchiving one photo per letter from the active word set.
    /// Letters are reversed so the spectator reads top→bottom = left→right word order.
    /// e.g. "hola" → reversed ["a","l","o","h"] → a→bank1, l→bank2, o→bank3, h→bank4
    ///
    /// Flow:
    ///  Phase 1 — Preparation (sync): find all photos, insert local images instantly into grid.
    ///  Phase 2 — API (async): unarchive each photo on Instagram sequentially.
    ///  Phase 3 — Finish: trigger CDN refresh once, clear override.
    private func revealByLetters(_ word: String, fromSet set: PhotoSet) async {
        let dm          = DataManager.shared
        let instagram   = InstagramService.shared
        let letters     = word.lowercased().reversed().map { String($0) }
        let alphabet    = set.selectedAlphabet ?? .latin
        let sortedBanks = set.banks.sorted { $0.position < $1.position }

        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        // BACKGROUND PROTECTION: ensure all API calls complete even if the
        // user minimises mid-reveal (e.g. a 10-letter word can take 20-30s).
        let bgTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "RevealLetters") { }
        }
        defer {
            Task { await MainActor.run { UIApplication.shared.endBackgroundTask(bgTask) } }
        }

        print("📷 [OCR-PP] ═══ Revealing '\(word)' (\(letters.count) letters) from '\(set.name)'")
        print("📷 [OCR-PP] Banks: \(sortedBanks.map { "pos\($0.position)=\($0.name)" })")

        // ── PHASE 1: Collect photos & insert local images instantly ──────────────
        struct LetterJob {
            let letter: String
            let photo: SetPhoto
            let mediaId: String
            let pseudoURL: String
            let localImage: UIImage?
            let requiresUnarchive: Bool
        }

        var jobs: [LetterJob] = []

        for (idx, letter) in letters.enumerated() {
            let bankPosition = idx + 1
            guard let bank = sortedBanks.first(where: { $0.position == bankPosition })
                          ?? (idx < sortedBanks.count ? sortedBanks[idx] : nil) else {
                print("❌ [OCR-PP] No bank at position \(bankPosition) for letter '\(letter)'"); break
            }
            guard let charIndex = alphabet.indexFor(String(letter)) else {
                print("❌ [OCR-PP] '\(letter)' not found in alphabet"); continue
            }
            let symbol = alphabet.characters[charIndex]
            let photos = set.photos.filter { $0.bankId == bank.id }

            print("📷 [OCR-PP] [\(idx+1)/\(letters.count)] '\(letter)' → '\(symbol)' bank '\(bank.name)' pos\(bank.position)")

            // Already unarchived locally — skip
            if let alreadyVisible = photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }),
               let visibleMediaId = alreadyVisible.mediaId {
                print("ℹ️ [OCR-PP] '\(letter)' already unarchived — keep visible in fake grid (no API call)")
                let localImage = alreadyVisible.imageData.flatMap { UIImage(data: $0) }
                jobs.append(LetterJob(letter: letter, photo: alreadyVisible, mediaId: visibleMediaId,
                                      pseudoURL: "reveal://\(visibleMediaId)", localImage: localImage,
                                      requiresUnarchive: false))
                continue
            }
            guard let photo = photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
                  let mediaId = photo.mediaId else {
                print("❌ [OCR-PP] No archived photo for '\(symbol)' in '\(bank.name)'")
                print("❌ [OCR-PP] Bank photos: \(photos.prefix(5).map { "sym=\($0.symbol) arch=\($0.isArchived)" })")
                continue
            }
            let localImage = photo.imageData.flatMap { UIImage(data: $0) }
            jobs.append(LetterJob(letter: letter, photo: photo, mediaId: mediaId,
                                  pseudoURL: "reveal://\(mediaId)", localImage: localImage,
                                  requiresUnarchive: true))
        }

        // ── Diagnose failure when no jobs were found ──────────────────────────────
        if jobs.isEmpty {
            let allPhotos = set.photos
            let anyUploaded = allPhotos.contains { $0.mediaId != nil }
            if !anyUploaded {
                // Set exists but has never been uploaded — give a clear error to the magician
                print("❌ [OCR-PP] Set '\(set.name)' has no uploaded photos (mediaId=nil for all)")
                LogManager.shared.warning("Reveal blocked: set '\(set.name)' has no uploaded photos", category: .general)
                await MainActor.run {
                    revealErrorTitle = String(localized: "ig.set_not_uploaded_title")
                    revealErrorMessage = String(format: String(localized: "ig.set_not_uploaded_body"), set.name)
                    showRevealError = true
                    clearOCRPeek()
                }
            } else {
                print("⚠️ [OCR-PP] '\(word)' — no matching archived photos found in '\(set.name)' (0 jobs)")
            }
            return
        }

        // Insert ALL local images into grid immediately (before any API call)
        if !jobs.isEmpty {
            let instantPhotos = jobs.map { (pseudoURL: $0.pseudoURL, image: $0.localImage) }
            await MainActor.run { onAddLocalImages?(instantPhotos) }
            print("⚡️ [OCR-PP] \(instantPhotos.count) local image(s) pre-inserted into grid")
        }

        // ── PHASE 2: API unarchive calls ──────────────────────────────────────────
        var revealedIds: [String] = []

        for (jobIdx, job) in jobs.enumerated() {
            guard !instagram.isLocked else { break }

            if !job.requiresUnarchive {
                print("ℹ️ [OCR-PP] '\(job.letter)' already visible on Instagram — skipped API call")
                continue
            }

            do {
                let result = try await instagram.reveal(mediaId: job.mediaId)
                if result.success {
                    await MainActor.run {
                        dm.updatePhoto(photoId: job.photo.id, isArchived: false, commentId: result.commentId)
                    }
                    revealedIds.append(job.mediaId)
                    print("✅ [OCR-PP] '\(job.letter)' unarchived on Instagram (ID: \(job.mediaId))")
                    LogManager.shared.success("OCR revealed '\(job.letter)' (mediaId: \(job.mediaId))", category: .general)
                } else {
                    print("❌ [OCR-PP] reveal returned false for '\(job.letter)'")
                }
            } catch {
                print("❌ [OCR-PP] Error '\(job.letter)': \(error.localizedDescription)")
                LogManager.shared.error("OCR reveal error '\(job.letter)': \(error.localizedDescription)", category: .general)
            }

            // Anti-bot delay between letters (skip after last one)
            if jobIdx < jobs.count - 1 {
                let delay = UInt64.random(in: 800_000_000...2_200_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        // ── PHASE 3: Finish ───────────────────────────────────────────────────────
        ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: revealedIds)
        print("📷 [OCR-PP] ═══ Done — \(revealedIds.count)/\(jobs.count) unarchived on Instagram")

        // Persist which set was last revealed so SetDetailView can warn if the
        // magician tries to re-archive too soon (cycling reveal→archive rapidly
        // is the main cause of Instagram bot detection).
        if !revealedIds.isEmpty {
            UserDefaults.standard.set(set.id.uuidString, forKey: "perf_lastRevealedSetId")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "perf_lastRevealedSetTimestamp")
            InstagramSafetyGate.shared.markPostReveal(mediaIds: revealedIds)
            // Activate orange ring on the profile avatar — persists until next Performance session
            await MainActor.run { postPredRevealRingActive = true }
        }

        // Trigger ONE CDN refresh now that all photos are unarchived on Instagram
        await MainActor.run { onRevealComplete?([]) }

        // Clear the "seguidos" override
        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - Amnesia Carousel swap

    private func triggerAmnesiaSwap() {
        guard amnesiaSettings.isEnabled,
              amnesiaSettings.isReady,
              !amnesiaSettings.isRevealed,
              amnesiaSettings.uploadState != .swapping,
              !instagram.isLocked else { return }

        amnesiaSettings.uploadState = .swapping
        Task {
            do {
                try await instagram.swapAmnesiaCarousels(settings: amnesiaSettings)
                await MainActor.run {
                    amnesiaSettings.uploadState = .ready

                    // ── Visual feedback: orange ring on profile avatars ────────────
                    // Reuses the Post Prediction ring flag so both header and bottom-bar
                    // avatars light up. Cleared when PerformanceView re-enters (new trick).
                    postPredRevealRingActive = true

                    // ── Haptic feedback: triple full-power vibration ──────────────
                    // Mirrors Post Prediction API reveal confirmation so the magician
                    // can feel the swap in their pocket without looking at the screen.
                    fireAmnesiaVibration()

                    // Signal PerformanceView to refresh the grid after CDN delay.
                    onAmnesiaSwapComplete?()
                }
            } catch {
                await MainActor.run { amnesiaSettings.uploadState = .ready }
                LogManager.shared.log("Amnesia swap error: \(error.localizedDescription)", level: .error, category: .general)
            }
        }
    }

    /// Triple full-power vibration with 1.5 s gaps — identical pattern to Post Prediction API reveal.
    private func fireAmnesiaVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        }
    }

}

// MARK: - Reels Grid View (4:5 aspect with play icon overlay — thumbnails only)

struct ReelsGridView: View {
    let reelURLs: [String]
    let cachedImages: [String: UIImage]
    /// Full reel items kept so we know the videoURL when the viewer opens.
    /// Grid cells themselves never play video — Instagram shows only thumbnails
    /// on the profile grid, and playing 12+ AVPlayers at once saturates iOS
    /// AVFoundation resources (causes black detail views and degraded
    /// performance everywhere else).
    var reelItems: [InstagramMediaItem] = []
    /// 12 cells = 4 rows, so digit 0 (row 4+) is reachable
    var minCells: Int = 12
    /// Called when the magician taps a reel thumbnail. Returns the tapped index.
    var onTapIndex: ((Int) -> Void)? = nil

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        let placeholderCount = max(0, minCells - reelURLs.count)
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(Array(reelURLs.enumerated()), id: \.element) { index, url in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        ZStack(alignment: .bottomLeading) {
                            if let image = cachedImages[url] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                            IGIcon(asset: "instagram_play", fallback: "play.fill", size: 12, color: .white)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    )
                    .clipped()
                    .onTapGesture { onTapIndex?(index) }
            }
            // Placeholder cells
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            ZStack(alignment: .bottomLeading) {
                                Rectangle().fill(Color.gray.opacity(0.15))
                                IGIcon(asset: "instagram_play", fallback: "play.fill", size: 12, color: .white.opacity(0.4))
                                    .padding(6)
                            }
                        )
                        .clipped()
                }
            }
        }
    }
}

// MARK: - Instagram Header

struct InstagramHeaderView: View {
    let username: String
    let isVerified: Bool
    let onRefresh: () -> Void
    let onPlusPress: () -> Void
    @State private var didLogLayout = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Keep side controls fixed so long usernames on compact devices
            // cannot visually push/crop + and menu icons into screen corners.
            Button(action: onPlusPress) {
                IGIcon(asset: "Instagram_plus", fallback: "plus.app", size: 22)
                    .frame(width: 30, height: 30, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .frame(width: 34, alignment: .leading)

            HStack(spacing: 4) {
                if isVerified {
                    IGIcon(asset: "instagram_verified", fallback: "checkmark.seal.fill", size: 16, color: .blue)
                }
                Text(username)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                IGIcon(asset: "instagram_chevron_down", fallback: "chevron.down", size: 12)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(0)

            HStack(spacing: 16) {
                Button(action: {}) {
                    IGIcon(asset: "instagram_threads", fallback: "at", size: 20)
                }
                Button(action: {}) {
                    IGIcon(asset: "Instagram_menu", fallback: "line.3.horizontal", size: 22)
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .responsiveHorizontalPadding()
        .frame(height: 44)
        .background(Color.white)
        .onAppear {
            guard !didLogLayout else { return }
            didLogLayout = true

            let screen = UIScreen.main.bounds
            let safeTop = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .safeAreaInsets.top ?? 0

            let message = "Header layout: screen=\(Int(screen.width))x\(Int(screen.height)) scale=\(UIScreen.main.scale), safeTop=\(Int(safeTop)), isSmall=\(UIScreen.isSmall), username='\(username)', left=34, right=72, iconPlus=22, iconMenu=22"
            print("📐 [LAYOUT] \(message)")
            LogManager.shared.info(message, category: .general)
        }
    }
}

// MARK: - Stat View

struct StatView: View {
    let number: Int
    let label: String
    var overrideText: String? = nil
    var overrideLabel: String? = nil
    
    var body: some View {
        // alignment: .leading → número y label alineados al mismo borde izquierdo.
        // El primer dígito y la primera letra quedan exactamente en la misma columna.
        VStack(alignment: .leading, spacing: 1) {
            Text(overrideText ?? formatCount(number))
                .font(.system(size: seAdapt(15, 17), weight: .semibold))
                .foregroundColor(.black)
                .monospacedDigit()
            Text(overrideLabel ?? label)
                .font(.system(size: seAdapt(12, 14)))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 10_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }
}

// MARK: - Followed By View

// MARK: - Story Highlight Cell

struct StoryHighlightCell: View {
    let highlight: InstagramHighlight
    let image: UIImage?

    private let outerSize: CGFloat = seAdapt(60, 68)
    private let innerSize: CGFloat = seAdapt(54, 62)
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.99, green: 0.42, blue: 0.05),
                                     Color(red: 0.85, green: 0.08, blue: 0.40),
                                     Color(red: 0.57, green: 0.12, blue: 0.76)],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: outerSize, height: outerSize)

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: innerSize, height: innerSize)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: innerSize, height: innerSize)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }

            Text(highlight.title)
                .font(.system(size: seAdapt(10, 11)))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: outerSize)
        }
    }
}

// MARK: - Auto Followed By View (Date Force Auto Mode)
// Shows up to 3 DateForce spectators with real profile images.
// Self-contained: tapping opens UserProfileView inline (no callback chain).
struct AutoFollowedByView: View {
    @ObservedObject var dateForce: DateForceSettings
    // kept for backward compat but no longer used for profile opening
    var onTap: (() -> Void)? = nil

    @State private var loadingUserId: String? = nil
    @State private var openedProfile: InstagramProfile? = nil
    @State private var showingProfile = false

    private var isLoading: Bool { dateForce.isAutoLoading }
    private var visible: [DateForceSpectator] {
        Array(dateForce.spectators.suffix(3).reversed().prefix(3))
    }

    var body: some View {
        ZStack {
        HStack(spacing: 4) {
                circlesArea
                textArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if loadingUserId != nil {
                ProgressView().scaleEffect(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }

            if showingProfile, let profile = openedProfile {
                UserProfileView(profile: profile, onClose: {
                    withAnimation(.easeInOut(duration: 0.22)) { showingProfile = false }
                })
                // Force SwiftUI to discard @State and re-init when the profile changes;
                // without this, switching from profile A to B can leave A's grid/state.
                .id(profile.userId)
                .transition(.move(edge: .trailing))
                .zIndex(10)
                .ignoresSafeArea()
            }
        }
    }

    private func openProfile(userId: String, username: String) {
        guard loadingUserId == nil else { return }
        loadingUserId = userId
        Task {
            if let p = try? await InstagramService.shared.getProfileInfo(
                userId: userId,
                usernameHint: username
            ) {
                await MainActor.run {
                    loadingUserId = nil
                    openedProfile = p
                    withAnimation(.easeInOut(duration: 0.22)) { showingProfile = true }
                }
            } else {
                await MainActor.run { loadingUserId = nil }
            }
        }
    }

    @ViewBuilder private var circlesArea: some View {
        if isLoading && visible.isEmpty {
            ProgressView().scaleEffect(0.65).frame(width: 20, height: 20)
        } else {
            HStack(spacing: -8) {
                ForEach(visible) { s in
                    spectatorCircle(for: s)
                        .onTapGesture { openProfile(userId: s.userId, username: s.username) }
                }
            }
        }
    }

    @ViewBuilder private func spectatorCircle(for s: DateForceSpectator) -> some View {
        Group {
            if let picURL = s.profilePicURL, let url = URL(string: picURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Circle().fill(Color.gray.opacity(0.3))
                    }
                }
            } else {
                Circle().fill(Color.gray.opacity(0.3))
            }
        }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    @ViewBuilder private var textArea: some View {
        if isLoading && visible.isEmpty {
            Text("Capturing followers…")
                .font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.isEmpty {
            Text("ig.followed_by")
                .font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count >= 3 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[1].userId, username: visible[1].username) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[2].userId, username: visible[2].username) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[1].userId, username: visible[1].username) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Followed By View

struct FollowedByView: View {
    let followers: [InstagramFollower]
    let cachedImages: [String: UIImage]
    var onFollowerTap: ((InstagramFollower) -> Void)? = nil

    private var visibleFollowers: [InstagramFollower] { Array(followers.prefix(3)) }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: -8) {
                ForEach(visibleFollowers, id: \.username) { follower in
                    avatarCircle(for: follower)
                        .onTapGesture { onFollowerTap?(follower) }
                }
            }
            namesArea
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var namesArea: some View {
        if visibleFollowers.count >= 3 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[1]) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[2]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visibleFollowers.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[1]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visibleFollowers.count == 1 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[0]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func avatarCircle(for follower: InstagramFollower) -> some View {
        Group {
            if let picURL = follower.profilePicURL, let image = cachedImages[picURL] {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let picURL = follower.profilePicURL, let url = URL(string: picURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Circle().fill(Color.gray.opacity(0.3))
                    }
                }
            } else {
                Circle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let icon: String
    let activeAsset: String?
    let inactiveAsset: String?
    let isSelected: Bool
    let action: () -> Void

    init(icon: String, activeAsset: String? = nil, inactiveAsset: String? = nil,
         isSelected: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.activeAsset = activeAsset
        self.inactiveAsset = inactiveAsset
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                let assetName = isSelected ? activeAsset : inactiveAsset
                if let asset = assetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
            Image(systemName: icon)
                .font(.system(size: 24))
                }
            }
            .foregroundColor(isSelected ? .black : Color(white: 0.56))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(
                    Rectangle()
                    .fill(isSelected ? Color.black : Color.clear)
                        .frame(height: 1),
                    alignment: .bottom
                )
        }
    }
}

// MARK: - Photos Grid

struct PhotosGridView: View {
    let mediaURLs: [String]
    let cachedImages: [String: UIImage]
    var onMediaAppear: ((String) -> Void)? = nil
    var onTapIndex: ((Int) -> Void)? = nil
    /// Always render at least this many cells so swipe digit-detection works
    /// even on tabs with few or no photos. 12 = 4 rows (row 4 maps to digit 0).
    var minCells: Int = 12
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        let placeholderCount = max(0, minCells - mediaURLs.count)
        LazyVGrid(columns: columns, spacing: 1) {
            // Identify cells by URL (element) instead of position (offset). Otherwise
            // reveal:// insertions and refreshes cause SwiftUI to reuse cells by index
            // and show the wrong thumbnail in a slot.
            ForEach(Array(mediaURLs.enumerated()), id: \.element) { index, url in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Group {
                if let image = cachedImages[url] {
                    Image(uiImage: image)
                        .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                        }
                    )
                        .clipped()
                    .onAppear { onMediaAppear?(url) }
                    .onTapGesture { onTapIndex?(index) }
            }
            // Placeholder cells
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(Rectangle().fill(Color.gray.opacity(0.15)))
                        .clipped()
                }
            }
        }
    }
}

// MARK: - Tagged Empty State

struct TaggedEmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 112)

            ZStack {
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: 82, height: 82)

                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.black)
            }

            Text("Photos and videos of you")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)

            Text("When people tag you in photos and videos, they'll appear here.")
                .font(.system(size: 15))
                .foregroundColor(Color(white: 0.48))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 42)

            Spacer(minLength: 160)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}

// MARK: - Post Scroll Viewer (Instagram "Posts" style)

struct PostScrollView: View {
    let mediaURLs: [String]
    let mediaItemsByURL: [String: InstagramMediaItem]
    let cachedImages: [String: UIImage]
    let initialIndex: Int
    let username: String
    let profileImage: UIImage?
    let userId: String
    var forcePostURL: String? = nil
    var forcePostMediaId: String? = nil
    var forcedThumbnail: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedItems: [String: InstagramMediaItem] = [:]
    @State private var hasForceActivated: Bool = false

    private var forcedPostIndex: Int? {
        mediaURLs.firstIndex(where: isForcedPostURL)
    }

    private var isForceActive: Bool {
        forcedPostIndex != nil
    }

    private func isForcedPostURL(_ url: String) -> Bool {
        if let mediaId = forcePostMediaId, !mediaId.isEmpty {
            if mediaItemsByURL[url]?.mediaId == mediaId { return true }
            if url.contains(mediaId) { return true }
        }
        if let forcePostURL, url == forcePostURL { return true }
        return false
    }

    private func postID(_ index: Int) -> String { "post_\(index)" }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        // LazyVStack so video cells (AVPlayer-backed) only mount when
                        // they are about to appear on screen. The Force Post interceptor
                        // already has a fallback (forcedIndex × avg row height) for the
                        // case where the forced card hasn't been materialised yet.
                        LazyVStack(spacing: 0) {
                            ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                                PostCardView(
                                    url: url,
                                    item: resolvedItems[url],
                                    cachedImages: cachedImages,
                                    username: username,
                                    profileImage: profileImage
                                )
                                .id(postID(index))
                                .accessibilityIdentifier(isForcedPostURL(url) ? "forced_post_card" : "")
                                Divider().background(Color(white: 0.9))
                            }
                        }
                    }

                    if isForceActive, let forcedPostIndex {
                        ScrollViewInterceptor(
                            forcedIndex: forcedPostIndex,
                            totalPostCount: mediaURLs.count,
                            hasActivated: $hasForceActivated,
                            isActive: isForceActive,
                            forcedThumbnail: forcedThumbnail
                        )
                        .frame(width: 0, height: 0)
                    }
                }
                .onAppear {
                    resolvedItems = mediaItemsByURL
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(postID(initialIndex), anchor: .top)
                    }
                    let missingCount = mediaURLs.filter { mediaItemsByURL[$0] == nil }.count
                    if missingCount > 0 {
                        Task { await fetchMissingItems() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.black)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("ig.tab_posts")
                            .font(.system(size: 15, weight: .semibold))
                        Text(username)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(Color.white)
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func fetchMissingItems() async {
        guard !InstagramService.shared.isLocked else {
            print("🚫 [POSTS] Item fetch skipped — lockdown active")
            return
        }
        do {
            let (items, _) = try await InstagramService.shared.getUserMediaItems(
                userId: userId, amount: 18, maxId: nil
            )
            for item in items { resolvedItems[item.imageURL] = item }
        } catch {
            print("⚠️ [POSTS] Background item fetch failed: \(error)")
        }
    }
}

// MARK: - Individual Post Card

private struct PostCardView: View {
    let url: String
    let item: InstagramMediaItem?
    let cachedImages: [String: UIImage]
    let username: String
    let profileImage: UIImage?
    @State private var carouselIndex = 0

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private func formatted(_ n: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: avatar + username + "..." menu
            HStack(spacing: 10) {
                if let pic = profileImage {
                    Image(uiImage: pic)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                Text(username)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                IGIcon(asset: "instagram_more_horizontal", fallback: "ellipsis", size: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            mediaView

            if carouselURLs.count > 1 {
                HStack(spacing: 4) {
                    ForEach(carouselURLs.indices, id: \.self) { index in
                        Circle()
                            .fill(index == carouselIndex ? Color.blue : Color.gray.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }

            // Action bar with counts (like real Instagram)
            HStack(spacing: 4) {
                actionIcon("instagram_like", fallback: "heart", count: item?.likeCount)
                actionIcon("instagram_comment", fallback: "bubble.left", count: item?.commentCount)
                    .padding(.leading, 8)
                actionIcon("instagram_share", fallback: "paperplane", count: nil)
                    .padding(.leading, 8)
                Spacer()
                IGIcon(asset: "instagram_save", fallback: "bookmark", size: 22)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Caption: username bold + text inline (like real Instagram)
            if let caption = item?.caption, !caption.isEmpty {
                captionView(caption)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Date
            if let date = item?.takenAt {
                Text(date, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 12)
            }
        }
    }

    private var carouselURLs: [String] {
        guard let item = item, item.mediaType == .carousel, item.carouselImageURLs.count > 1 else {
            return []
        }
        return item.carouselImageURLs
    }

    @ViewBuilder
    private var mediaView: some View {
        let urls = carouselURLs
        if urls.count > 1 {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay(
                    TabView(selection: $carouselIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, imageURL in
                            postImage(for: imageURL)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                )
                .clipped()
        } else if let item = item,
                  item.mediaType == .video,
                  let videoURL = item.videoURL,
                  !videoURL.isEmpty {
            // Inline video playback for feed-style posts/reels. The poster is
            // the cached thumbnail so we never see a black flash while AVPlayer
            // loads its first frame. Plays with sound like the real Instagram
            // feed; LazyVStack ensures the player is destroyed once the cell
            // scrolls off screen.
            Color.clear
                .aspectRatio(4.0/5.0, contentMode: .fit)
                .overlay(
                    GridVideoPlayer(
                        videoURL: videoURL,
                        muted: false,
                        posterImage: cachedImages[url]
                    )
                )
                .clipped()
                .frame(maxWidth: .infinity)
        } else if let image = cachedImages[url] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(ProgressView().tint(.gray))
        }
    }

    @ViewBuilder
    private func postImage(for imageURL: String) -> some View {
        if let image = cachedImages[imageURL] ?? (imageURL == url ? cachedImages[url] : nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let remoteURL = URL(string: imageURL) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .overlay(ProgressView().tint(.gray))
                }
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay(ProgressView().tint(.gray))
        }
    }

    @ViewBuilder
    private func actionIcon(_ assetName: String, fallback: String = "square", count: Int?) -> some View {
        HStack(spacing: 4) {
            IGIcon(asset: assetName, fallback: fallback, size: 24)
            if let c = count, c > 0 {
                Text(formatted(c))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
    }

    @ViewBuilder
    private func captionView(_ caption: String) -> some View {
        // Username bold + caption inline using attributed text — flows naturally like Instagram
        let attributed = attributedCaption(caption)
        Text(attributed)
            .font(.system(size: 13))
            .lineLimit(3)
            .foregroundColor(.black)
    }

    private func attributedCaption(_ caption: String) -> AttributedString {
        var user = AttributedString(username + " ")
        user.font = .system(size: 13, weight: .semibold)
        var text = AttributedString(caption)
        text.font = .system(size: 13)
        return user + text
    }
}

// MARK: - Nav Button Style

/// Minimal press feedback only — no permanent background on any icon.
/// Active-tab indicator is handled separately inside InstagramBottomBar.
private struct IGNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.84 : 1.0)
            .animation(.easeInOut(duration: 0.11), value: configuration.isPressed)
    }
}

// MARK: - Glass Pill View Extension

private extension View {
    /// Applies the pill background.
    /// iOS 26+: native .glassEffect(.clear) — real liquid glass, light bending,
    ///          specular highlights, maximum transparency over photo content.
    /// iOS 16–25: ultraThinMaterial + white tint fallback.
    @ViewBuilder
    func igGlassPill() -> some View {
        if #available(iOS 26.0, *) {
            // Tint at 0.82 neutralises dark grid photos so the pill looks
            // the same light grey as it does over Explore's white background.
            self.glassEffect(.regular.tint(.white.opacity(0.82)), in: .capsule)
        } else {
            self.background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.62)))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.90), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
            )
        }
    }
}

// MARK: - Instagram Bottom Bar

struct InstagramBottomBar: View {
    let profileImageURL: String?
    let cachedImage: UIImage?
    let isHome: Bool
    let isSearch: Bool
    let onHomePress: () -> Void
    let onSearchPress: () -> Void
    let onReelsPress: () -> Void
    let onMessagesPress: () -> Void
    let onProfilePress: () -> Void
    /// When true, replaces the default black border with an orange gradient ring —
    /// visual confirmation that Post Prediction revealed a photo on Instagram.
    var showRevealRing: Bool = false

    /// Reactive budget observer — drives the red-dot visibility on the paper plane.
    /// Shared singleton so the dot updates in real time in both Performance and Explore.
    @ObservedObject private var instagram = InstagramService.shared

    /// Instagram-style orange gradient used for the "story ring" effect.
    private var storyRingGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.99, green: 0.78, blue: 0.12), // warm yellow
                Color(red: 0.99, green: 0.42, blue: 0.13), // vivid orange
                Color(red: 0.90, green: 0.14, blue: 0.49), // hot pink
                Color(red: 0.52, green: 0.17, blue: 0.83), // violet
                Color(red: 0.99, green: 0.78, blue: 0.12)  // wrap back
            ],
            center: .center
        )
    }

    var body: some View {
        // Content area height is fixed at 46 pt; pill adds 10 pt padding each side
        // → total pill height ≈ 66 pt → capsule cornerRadius ≈ 33 pt.
        // The indicator uses cornerRadius 28 (= 33 − 5) for concentric curvature,
        // and expands to fill almost the full pill height (4 pt margin top/bottom).
        HStack(spacing: 0) {
            Button(action: onHomePress) {
                navItem(asset: "instagram_home", fallback: "house", isActive: isHome)
            }
            .buttonStyle(IGNavButtonStyle())

            Button(action: onReelsPress) {
                navItem(asset: "instagram_reels_tab", fallback: "play.rectangle", isActive: false)
            }
            .buttonStyle(IGNavButtonStyle())

            Button(action: onMessagesPress) {
                navItem(
                    asset: "instagram_share",
                    fallback: "paperplane",
                    isActive: false,
                    showRedDot: instagram.checkRateLimit().remaining < 8
                )
            }
            .buttonStyle(IGNavButtonStyle())

            Button(action: onSearchPress) {
                navItem(asset: "instagram_search", fallback: "magnifyingglass", isActive: isSearch)
            }
            .buttonStyle(IGNavButtonStyle())

            Button(action: onProfilePress) {
                profileAvatarView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(IGNavButtonStyle())
        }
        .frame(height: 46)          // fixed content height → pill height = 66 pt
        .padding(.vertical, 10)
        .igGlassPill()
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
    }

    /// Icon centred in an equal-width slot. The indicator background expands to
    /// fill the full slot height (maxHeight: .infinity), leaving only 4 pt margin
    /// top/bottom — it nearly touches the pill capsule edge, matching native iOS.
    /// cornerRadius 28 is concentric with the pill's capsule (~33 pt radius).
    @ViewBuilder
    private func navItem(
        asset: String,
        fallback: String,
        isActive: Bool,
        showRedDot: Bool = false
    ) -> some View {
        ZStack {
            // Dot is anchored relative to the 24 pt icon, not the full slot
            IGIcon(asset: asset, fallback: fallback, size: 24)
                .overlay(alignment: .bottomTrailing) {
                    if showRedDot {
                        Circle()
                            // Explicit sRGB red so it stays vivid even over dark glass
                            .fill(Color(red: 1.0, green: 0.18, blue: 0.18))
                            .frame(width: 8, height: 8)
                            // White ring separates the dot from any dark background
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.11 : 0))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        )
    }

    @ViewBuilder
    private var profileAvatarView: some View {
        if let image = cachedImage {
            ZStack {
                // Gradient ring (visible only when a PP reveal succeeded)
                if showRevealRing {
                    Circle()
                        .stroke(storyRingGradient, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                }
                // White gap between ring and photo (Instagram-style)
                Circle()
                    .fill(Color.white)
                    .frame(width: showRevealRing ? 29 : 28, height: showRevealRing ? 29 : 28)
                // Profile picture
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(showRevealRing ? Color.clear : Color.black, lineWidth: 1.5)
                    )
            }
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 26))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Notes Bubble Tail Shape

/// Smooth tongue that narrows from the bubble junction down to a soft tip,
/// matching Instagram's Notes tail silhouette.
private struct NotesTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // Right side → rounded tip
        p.addCurve(to:       CGPoint(x: w * 0.50, y: h),
                   control1: CGPoint(x: w * 1.00, y: h * 0.28),
                   control2: CGPoint(x: w * 0.72, y: h))
        // Tip → left side (mirror)
        p.addCurve(to:       CGPoint(x: 0, y: 0),
                   control1: CGPoint(x: w * 0.28, y: h),
                   control2: CGPoint(x: 0, y: h * 0.28))
        p.closeSubpath()
        return p
    }
}

// MARK: - Notes Bubble View

struct NotesBubbleView: View {
    let text: String

    // Tail & dot geometry
    private let tailW: CGFloat = 10
    private let tailH: CGFloat = 7
    private let tailX: CGFloat = 14   // distance from bubble left edge
    private let dotD:  CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Capsule bubble — width hugs the text, no fixed frame ──────
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minWidth: 42, maxWidth: 110)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 1)
                )
                .zIndex(1)

            // ── Tiny curved tail, overlaps bubble bottom by 2 pt ─────────
            // No stroke — pure white fill seamlessly joins the capsule.
            NotesTailShape()
                .fill(Color.white)
                .frame(width: tailW, height: tailH)
                .padding(.leading, tailX)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: -2)
                .zIndex(0)

            // ── Small separate dot — mirrors Instagram's speech-bubble ────
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                .frame(width: dotD, height: dotD)
                .padding(.leading, tailX + tailW * 0.5 - dotD * 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
        }
    }
}

// MARK: - Spectator Profile Cover

/// Loads a follower's full profile then presents it as a UserProfileView.
/// Owned by fullScreenCover(item: $selectedSpectator) so each new follower
/// gets a fresh presentation context with no stale-item race condition.
struct SpectatorProfileCover: View {
    let follower: InstagramFollower
    let onClose: () -> Void

    @State private var profile: InstagramProfile? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let profile {
                UserProfileView(profile: profile, onClose: onClose)
                    .id(profile.userId)
            } else if isLoading {
                Color.white.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text("Loading profile…")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    )
            } else {
                Color.white.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(errorMessage ?? "Could not load profile")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button("Close", action: onClose)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    )
            }
        }
        .task {
            print("👤 [SPECTATOR] Loading profile for @\(follower.username)")
            do {
                if let p = try await InstagramService.shared.getProfileInfo(
                    userId: follower.userId,
                    usernameHint: follower.username,
                    fullNameHint: follower.fullName,
                    profilePicURLHint: follower.profilePicURL
                ) {
                    await MainActor.run {
                        profile = p
                        isLoading = false
                    }
                    print("✅ [SPECTATOR] Profile loaded: @\(p.username)")
                } else {
                    await MainActor.run {
                        errorMessage = "Could not load profile for @\(follower.username)"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                print("❌ [SPECTATOR] Error: \(error)")
            }
        }
    }
}

// MARK: - Full Load Progress Overlay

/// Full-screen overlay shown in PerformanceView while ProfileFullLoaderService
/// is pre-caching the profile. Disappears automatically once loading completes.
struct FullLoadOverlayView: View {
    @ObservedObject var loader: ProfileFullLoaderService
    /// After this many seconds the user can skip the wait.
    private let skipAfterSeconds: Int = 120
    @State private var elapsed: Int = 0
    @State private var timerRef: Timer? = nil

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Instagram logo mark
                if UIImage(named: "instagram_logo_icon") != nil {
                    Image("instagram_logo_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .padding(.bottom, 28)
                }

                // Phase spinner or countdown ring
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 2.5)
                        .frame(width: 72, height: 72)

                    if loader.phase == .warmingUp && loader.warmupSecondsRemaining > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(loader.warmupSecondsRemaining) / 90.0)
                            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: loader.warmupSecondsRemaining)

                        Text("\(loader.warmupSecondsRemaining)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(1.4)
                    }
                }
                .padding(.bottom, 28)

                Text(loader.progressDescription)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut, value: loader.phase)

                if loader.phase == .grid && loader.gridItemsLoaded > 0 {
                    Text("\(loader.gridItemsLoaded) posts")
                        .font(.system(size: 13))
                        .foregroundColor(Color.black.opacity(0.45))
                        .padding(.top, 6)
                        .transition(.opacity)
                }

                Spacer()
                Spacer()

                if elapsed >= skipAfterSeconds {
                    Button {
                        loader.skipToCompleted()
                    } label: {
                        Text(NSLocalizedString("fullload.skip", comment: "Skip and use anyway"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.45))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .padding(.bottom, 48)
                } else {
                    // Placeholder keeps layout stable while skip button isn't shown
                    Color.clear
                        .frame(height: 40)
                        .padding(.bottom, 48)
                }
            }
        }
        .onAppear { startElapsedTimer() }
        .onDisappear { timerRef?.invalidate(); timerRef = nil }
    }

    private func startElapsedTimer() {
        elapsed = 0
        timerRef?.invalidate()
        timerRef = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
        }
    }
}

