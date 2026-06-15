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
    @AppStorage("note_feature_enabled") private var noteFeatureEnabled: Bool = true
    @AppStorage("bio_feature_enabled")  private var bioFeatureEnabled:  Bool = true
    // Text templates — user-defined wrappers with {word} token
    @AppStorage("note_template")   private var noteTemplate:  String = ""
    @AppStorage("bio_template")    private var bioTemplate1:  String = ""
    @AppStorage("bio_template_2")  private var bioTemplate2:  String = ""
    @AppStorage("bio_template_3")  private var bioTemplate3:  String = ""
    @AppStorage("bio_template_4")  private var bioTemplate4:  String = ""
    @AppStorage("bio_active_slot")      private var bioActiveSlot: Int = 0
    @AppStorage("bio_acrostic_enabled") private var bioAcrosticEnabled: Bool = false

    private var bioTemplate: String {
        switch bioActiveSlot {
        case 1:  return bioTemplate2
        case 2:  return bioTemplate3
        case 3:  return bioTemplate4
        default: return bioTemplate1
        }
    }
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
    /// Set by List Set private selector; observed by InstagramProfileView to reveal that slot.
    @State private var pendingListReveal: Int? = nil
    /// Set by URL scheme handler; observed by InstagramProfileView to trigger playing-card reveal.
    @State private var pendingCardReveal: String? = nil
    /// Set by the fake lockscreen; observed by InstagramProfileView to route number/custom/card reveals.
    @State private var pendingLockscreenDigits: [Int]? = nil
    /// True once OCR has recognised and routed a word in this session.
    /// Prevents a second OCR trigger in the same Performance session (one reveal per trick).
    @State private var ocrUsedInSession: Bool = false
    /// Optimistic bio text currently being sent via OCR / interface capture.
    /// While set, the onChange(of: profileCache.cachedProfile?.biography) handler will NOT
    /// revert the fake profile bio — prevents a concurrent loadProfile (fetching the old bio
    /// from Instagram before our POST completes) from overwriting the newly-shown word.
    @State private var pendingBioText: String? = nil
    /// Short-lived local override for bio changes initiated inside Vault (URL scheme,
    /// clipboard, OCR, API, interface inputs). Instagram profile refreshes can briefly
    /// return the previous biography right after a successful POST; preserve the local
    /// value so the fake profile does not visually revert.
    @State private var localBioOverride: (text: String, timestamp: Date)? = nil
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var cdnForbiddenTimestamps: [Date] = []
    @State private var cdnRefreshScheduled = false
    /// Prevents multiple concurrent loadCachedImages runs from stacking up
    /// and flooding the network with parallel URLSession tasks.
    @State private var isLoadingImages = false
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
    /// Prevents a double vibration when loadProfile() later clears pendingProfilePic
    /// after the auto-pic flow already vibrated on POST success.
    @State private var profilePicVibratedAlready = false
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    /// True while a DispatchQueue retry has already been scheduled.
    /// Prevents the thundering-herd problem where 12 onAppear callbacks each
    /// schedule their own retry when the SafetyGate is in cooldown.
    @State private var paginationRetryScheduled = false
    private let maxPhotosOwnProfile = 100
    // Lazy-tab loading: track whether each secondary tab has been loaded at least once.
    @State private var reelsLoadedOnce      = false
    @State private var taggedLoadedOnce     = false
    // Highlights: once we know the result (empty or not) we hide the placeholder row.
    @State private var highlightsLoadedOnce = false

    // MARK: - Fake Home Screen illusion
    @AppStorage("fakeHomeScreenEnabled") private var fakeHomeScreenEnabled = false
    @AppStorage("performanceCoverMode") private var performanceCoverModeRaw = PerformanceCoverMode.off.rawValue
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @State private var showingHomeScreenIllusion = false
    @State private var showingScreenOffCover = false
    @State private var performanceCoverWasShown = false

    private var effectivePerformanceCoverMode: PerformanceCoverMode {
        if UserDefaults.standard.object(forKey: "performanceCoverMode") == nil && fakeHomeScreenEnabled {
            return .homeScreen
        }
        return PerformanceCoverMode(rawValue: performanceCoverModeRaw) ?? .off
    }

    private var shouldShowPerformanceCover: Bool {
        switch effectivePerformanceCoverMode {
        case .off:
            return false
        case .homeScreen:
            return illusionService.hasImage
        case .screenOff:
            return true
        }
    }

    private func presentPerformanceCoverIfNeeded() {
        guard shouldShowPerformanceCover, !performanceCoverWasShown else { return }
        performanceCoverWasShown = true
        switch effectivePerformanceCoverMode {
        case .homeScreen:
            showingHomeScreenIllusion = true
        case .screenOff:
            showingScreenOffCover = true
        case .off:
            break
        }
    }

    // MARK: - Fake Lockscreen input
    @State private var showingLockscreen = false
    /// Prevents re-presenting the lockscreen when onAppear re-fires after the
    /// fullScreenCover is dismissed (which happens on every iOS version).
    @State private var lockscreenWasShown = false

    // MARK: - Clock Input input
    @State private var showingClockInput = false
    /// Prevents re-presenting the black screen when onAppear re-fires after dismiss.
    @State private var clockInputWasShown = false

    // MARK: - Card Numpad input
    @State private var showingCardNumpad = false
    /// Prevents re-presenting the card selector when onAppear re-fires after dismiss.
    @State private var cardNumpadWasShown = false

    // MARK: - List Set input
    @State private var showingListInput = false
    @State private var listInputWasShown = false

    private var activeListSet: PhotoSet? {
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeListSetId else { return nil }
        return DataManager.shared.sets.first { $0.id == activeId && $0.type == .list }
    }

    private func resetFullscreenInputPresentationFlags() {
        lockscreenWasShown = false
        clockInputWasShown = false
        cardNumpadWasShown = false
        listInputWasShown = false
        showingLockscreen = false
        showingClockInput = false
        showingCardNumpad = false
        showingListInput = false
    }

    private func resetPerformanceCoverPresentationFlags() {
        performanceCoverWasShown = false
        showingHomeScreenIllusion = false
        showingScreenOffCover = false
    }

    /// True when the black swipe-clock screen should appear on Performance open.
    /// Covers: PP clockInput mode, active number/custom set using Clock Input, OR
    /// any set/bio/note source configured for Number Clock or Card Clock. Card Clock is
    /// now unified to this black screen too (4 swipes → value+suit), so a single capture
    /// can reveal the active card set AND fill any bio/note placeholder at once.
    private var isClockInputActive: Bool {
        if ppTopInputMode == "clockInput" { return true }
        let kinds = integrations.interfaceKindsInUse()
        if kinds.contains(.numberClock) || kinds.contains(.cardClock) { return true }
        guard let activeId = ActiveSetSettings.shared.activeSetId,
              let activeType = ActiveSetSettings.shared.activeSetType,
              activeType == .number || activeType == .custom else { return false }
        return DataManager.shared.sets.first { $0.id == activeId }?.resolvedInputMethod == .clockInput
    }

    /// True when the black clock screen should capture a CARD (value+suit) rather than a
    /// number. Decided by the single active interface kind (only one can be active at a time).
    private var isClockCardMode: Bool {
        integrations.interfaceKindsInUse().contains(.cardClock)
    }

    /// True when Performance should start on the black tap-to-show card numpad.
    /// Covers an active Playing Cards set using Numpad Card, or Notes/Bio placeholders
    /// configured to receive a localized card name from that interface.
    private var isCardNumpadActive: Bool {
        integrations.interfaceKindsInUse().contains(.cardNumpad)
    }

    /// True when the fake lockscreen should appear on Performance open.
    /// Covers: global LockscreenInputSettings (active set path) OR any bio/note
    /// placeholder configured for Number/Card Lockscreen (wallpaper is optional for the
    /// bio/note path — the view renders on a dark background if none is set).
    private var isLockscreenActive: Bool {
        if LockscreenInputSettings.shared.isReady { return true }
        let kinds = integrations.interfaceKindsInUse()
        return kinds.contains(.numberLockscreen) || kinds.contains(.cardLockscreen)
    }

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
    private let minRefreshInterval: TimeInterval = 60
    @State private var isPullRefreshInFlight = false
    @State private var isSilentGridRefreshing = false
    private let fullRefreshAfterGridRefreshGap: TimeInterval = 90
    /// Controls whether pull-to-refresh is active. Set to false after each refresh
    /// and restored once both local (60 s) and SafetyGate (120 s) cooldowns expire,
    /// so the pull gesture bounces without showing the spinner when blocked.
    @State private var isRefreshEnabled: Bool = true

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
            Color(UIColor.igPageBackground).ignoresSafeArea()
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
            Color(UIColor.igPageBackground).ignoresSafeArea()
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
            Color(UIColor.igPageBackground).ignoresSafeArea()
                .overlay(
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.2)
                        Text("ig.loading_profile")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                )
                .zIndex(899)
        }
    }

    @ViewBuilder private var performanceCoverOverlay: some View {
        if showingHomeScreenIllusion,
           effectivePerformanceCoverMode == .homeScreen,
           let screenshot = illusionService.screenshot {
            Image(uiImage: screenshot)
                .resizable()
                .scaledToFill()
            .frame(width: UIScreen.main.bounds.width,
                   height: UIScreen.main.bounds.height)
            .background(Color.black.ignoresSafeArea(.all))
            .clipped()
            .ignoresSafeArea(.all)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeIn(duration: 0.12)) { showingHomeScreenIllusion = false }
            }
            .zIndex(10_000)
        }
    }

    private var bottomBar: some View {
            InstagramBottomBar(
                profileImageURL: profile?.profilePicURL,
                cachedImage: profile?.profilePicURL != nil ? cachedImages[profile!.profilePicURL] : nil,
                isHome: !showingExplore, isSearch: showingExplore,
                onHomePress: {},
                onSearchPress: {
                    let capturedDigits = SecretNumberManager.shared.digitBuffer
                    if captureGridSideEffects(digits: capturedDigits, source: "search") {
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

    @discardableResult
    private func captureGridSideEffects(digits: [Int], source: String) -> Bool {
        guard !digits.isEmpty else { return false }

        let capturedNumber = digits.reduce(0) { $0 * 10 + $1 }
        var didCapture = false

        if FollowingMagicSettings.shared.isEnabled {
            FollowingMagicSettings.shared.capture(digits: digits, source: source)
            didCapture = true
        }

        if ForceReelSettings.shared.isEnabled,
           ForceReelSettings.shared.hasReel,
           capturedNumber > 0 {
            ForceReelSettings.shared.pendingPosition = capturedNumber
            print("🎭 [FORCE] Position captured from \(source): \(capturedNumber)")
            didCapture = true
        }

        return didCapture
    }

    private func instagramProfileView(profile: InstagramProfile) -> some View {
        InstagramProfileView(
            profile: profile,
            cachedImages: $cachedImages,
            onRefresh: loadProfileSync,
            onAsyncRefresh: handlePerformancePullToRefresh,
            isRefreshEnabled: isRefreshEnabled,
            onPlusPress: { selectedTab = 1 },
            highlightsLoadedOnce: $highlightsLoadedOnce,
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
                batchInsertRevealURLs(revealedPhotos)

                // For video slots: seed mediaItemsByURL with a pseudo InstagramMediaItem so that
                // the PostCardView can show the video player immediately (using the CDN videoURL
                // stored in SetPhoto), without waiting for the silent refresh to complete.
                var hasVideoReveal = false
                for mediaId in revealedIds {
                    let allPhotos = DataManager.shared.sets.flatMap { $0.photos }
                    guard let setPhoto = allPhotos.first(where: { $0.mediaId == mediaId }),
                          setPhoto.isVideo,
                          let videoURL = setPhoto.videoURL else { continue }
                    hasVideoReveal = true
                    let pseudoURL = "reveal://\(mediaId)"
                    let pseudoItem = InstagramMediaItem(
                        id: mediaId, mediaId: mediaId,
                        imageURL: pseudoURL, videoURL: videoURL,
                        caption: nil,
                        takenAt: setPhoto.uploadDate,
                        likeCount: nil, commentCount: nil,
                        mediaType: .video,
                        videoAspectRatio: setPhoto.videoAspectRatio
                    )
                    mediaItemsByURL[pseudoURL] = pseudoItem
                    print("🎬 [VIDEO REVEAL] Seeded mediaItemsByURL for reveal://\(mediaId) ratio=\(setPhoto.videoAspectRatio?.description ?? "nil")")
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
                // Videos need extended retries: Instagram takes longer to make them available
                // in the profile grid after unarchiving. Retry at 5s, 25s and 55s.
                // Photos only need the standard single refresh at ~5s.
                if hasVideoReveal {
                    print("🎬 [VIDEO REVEAL] Scheduling extended grid refresh retries (video takes longer to process)")
                    for delaySeconds: UInt64 in [5, 25, 55] {
                        Task {
                            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                            await refreshMediaGridSilently()
                        }
                    }
                } else {
                    Task { await refreshMediaGridSilently() }
                }
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
            pendingListReveal: $pendingListReveal,
            pendingCardReveal: $pendingCardReveal,
            pendingLockscreenDigits: $pendingLockscreenDigits,
            onTabSelected: { tab in handleTabSelected(tab) },
            onInterfaceCapture: { value, kinds in
                Task { await applyInterfaceCapture(value: value, kinds: kinds) }
            }
        )
    }

    /// Called by InstagramProfileView whenever the Posts/Reels/Tagged tab changes.
    /// Loads reels or tagged content on first tap, without blocking the UI.
    private let secondaryTabVisibleMinimum = 12

    private func handleTabSelected(_ tab: Int) {
        guard let profile else { return }
        switch tab {
        case 1:
            // Allow re-fetch even if reelsLoadedOnce=true when no images are actually
            // visible — this handles the case where iOS purged the Caches/ directory
            // (thumbnails lost) and the CDN URLs expired so re-download also failed.
            let hasReelImages = profile.cachedReelURLs.contains { cachedImages[$0] != nil }
            let needsVisibleMinimum = profile.cachedReelURLs.count < secondaryTabVisibleMinimum
            guard !reelsLoadedOnce || !hasReelImages || needsVisibleMinimum else { return }
            reelsLoadedOnce = true
            Task {
                await fetchReelsIfNeeded(
                    for: profile,
                    forceIfNoImages: !hasReelImages,
                    ensureVisibleMinimum: needsVisibleMinimum
                )
            }
        case 2:
            let hasTaggedImages = profile.cachedTaggedURLs.contains { cachedImages[$0] != nil }
            let needsVisibleMinimum = profile.cachedTaggedURLs.count < secondaryTabVisibleMinimum
            guard !taggedLoadedOnce || !hasTaggedImages || needsVisibleMinimum else { return }
            taggedLoadedOnce = true
            Task {
                await fetchTaggedIfNeeded(
                    for: profile,
                    forceIfNoImages: !hasTaggedImages,
                    ensureVisibleMinimum: needsVisibleMinimum
                )
            }
        default:
            break
        }
    }

    /// Schedules a background preload of reels, tagged, and highlights so they are cached
    /// before the user swipes to those tabs. Safe to call multiple times —
    /// each fetch helper skips when already cached.
    /// Delay is intentionally staggered to avoid competing with the posts
    /// download burst that just finished.
    private func scheduleBackgroundReelsTaggedPreload(for cached: InstagramProfile) {
        // Already loaded → nothing to do
        let reelsPaginationKey = "reels_paginated_\(cached.userId)"
        let alreadyPaginatedReels = UserDefaults.standard.bool(forKey: reelsPaginationKey)
        let reelsReady = !cached.cachedReelURLs.isEmpty
            && !cached.cachedReelItems.isEmpty
            && !(cached.cachedReelItems.count == 10 && !alreadyPaginatedReels)

        let taggedPaginationKey = "tagged_paginated_\(cached.userId)"
        let alreadyPaginatedTagged = UserDefaults.standard.bool(forKey: taggedPaginationKey)
        let taggedReady = !cached.cachedTaggedURLs.isEmpty
            && !(cached.cachedTaggedURLs.count == 18 && !alreadyPaginatedTagged)

        let highlightsReady = cached.cachedHighlights.isEmpty
            ? highlightsCheckIsFresh(for: cached.userId)
            : cachedHighlightCoversAreReady(cached.cachedHighlights)

        guard !reelsReady || !taggedReady || !highlightsReady else {
            print("🎬 [BG] Reels + tagged + highlights already cached — skipping preload")
            return
        }
        print("🎬 [BG] Scheduling background preload — reelsReady:\(reelsReady) taggedReady:\(taggedReady) highlightsReady:\(highlightsReady)")

        Task { @MainActor in
            // Delay to let the posts download burst settle first (anti-bot)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !instagram.isLocked,
                  !instagram.isSessionChallenged,
                  !instagram.isUploadingProfilePic,
                  instagram.isLoggedIn else {
                print("🚫 [BG] Reels/tagged/highlights preload deferred — locked/challenged/uploading")
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
            // Fetch highlights if not yet cached (lazy, like reels/tagged).
            guard let current3 = profile else { return }
            let highlightCoversReady = !current3.cachedHighlights.isEmpty
                && cachedHighlightCoversAreReady(current3.cachedHighlights)
            if !current3.cachedHighlights.isEmpty && !highlightCoversReady {
                print("🌟 [BG] Highlight covers missing — refreshing metadata…")
                await fetchHighlightsIfNeeded(for: current3)
            } else if current3.cachedHighlights.isEmpty && !highlightsCheckIsFresh(for: current3.userId) {
                print("🌟 [BG] Highlights not cached — auto-fetching…")
                await fetchHighlightsIfNeeded(for: current3)
            } else if current3.cachedHighlights.isEmpty {
                print("🌟 [BG] Highlights checked recently — skipping empty refresh")
                highlightsLoadedOnce = true
            } else {
                print("🌟 [BG] Highlights already cached (\(current3.cachedHighlights.count)) — skipping fetch")
                highlightsLoadedOnce = true
            }
        }
    }

    private func highlightsCheckIsFresh(for userId: String) -> Bool {
        let key = "highlights_checked_at_\(userId)"
        let last = UserDefaults.standard.double(forKey: key)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < 12 * 60 * 60
    }

    private func markHighlightsChecked(for userId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "highlights_checked_at_\(userId)")
    }

    @MainActor
    private func cachedHighlightCoversAreReady(_ highlights: [InstagramHighlight]) -> Bool {
        guard !highlights.isEmpty else { return false }
        var allReady = true
        for highlight in highlights {
            let url = highlight.coverImageURL
            guard !url.isEmpty else {
                allReady = false
                continue
            }
            if cachedImages[url] != nil { continue }
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
            } else {
                allReady = false
            }
        }
        return allReady
    }

    /// Fetches reels for the own profile tab. Safe to call on-demand.
    /// - Parameter forceIfNoImages: when true, re-fetches even if URLs are already
    ///   cached — used when iOS purged the image cache and CDN URLs have expired,
    ///   so a fresh URL set is needed before thumbnails can be re-downloaded.
    @MainActor
    private func fetchReelsIfNeeded(
        for cached: InstagramProfile,
        forceIfNoImages: Bool = false,
        ensureVisibleMinimum: Bool = false
    ) async {
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
        //  d) ensureVisibleMinimum=true: user opened Reels and the grid has fewer
        //     than 12 items, so allow one extra page only now.
        //  e) forceIfNoImages=true: URLs cached but no images visible (e.g. iOS purged Caches/
        //     and CDN URLs expired — fresh URLs are needed so downloads can succeed).
        let reelsPaginationKey = "reels_paginated_\(cached.userId)"
        let alreadyPaginated = UserDefaults.standard.bool(forKey: reelsPaginationKey)
        let looksLikeOldSinglePage = cached.cachedReelItems.count == 10 && !alreadyPaginated
        let needsVisibleMinimum = ensureVisibleMinimum && cached.cachedReelURLs.count < secondaryTabVisibleMinimum
        let needsFetch = cached.cachedReelURLs.isEmpty
                      || cached.cachedReelItems.isEmpty
                      || looksLikeOldSinglePage
                      || needsVisibleMinimum
                      || forceIfNoImages
        guard needsFetch else {
            print("🎬 [REELS] Already cached (\(cached.cachedReelURLs.count) URLs, \(cached.cachedReelItems.count) items) — skipping fetch")
            return
        }
        if forceIfNoImages {
            print("🎬 [REELS] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🎬 [REELS] Lazy-loading reels progressively (page by page)…")
        do {
            // Random human-like delay before the first API call.
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))

            let reelsPaginationKey = "reels_paginated_\(cached.userId)"
            let maxPages = ensureVisibleMinimum ? 2 : 1
            var allItems: [InstagramMediaItem] = []
            var nextCursor: String? = nil
            var page = 0

            repeat {
                let (pageItems, nextId) = try await instagram.getUserReelsPage(
                    userId: cached.userId,
                    amount: 50,
                    maxId: nextCursor
                )
                guard !pageItems.isEmpty else { break }

                allItems += pageItems

                // ── Show this page in the grid immediately ──────────────────────
                var updated = profile ?? cached
                updated.cachedReelURLs  = allItems.map { $0.imageURL }
                updated.cachedReelItems = allItems
                profile = updated

                // Download thumbnails for this page only — they fill in one by one
                // while the next page (if any) is being fetched.
                let pageURLs = pageItems.map { $0.imageURL }
                for url in pageURLs where cachedImages[url] == nil {
                    if let img = await downloadImage(from: url) {
                        cachedImages[url] = img
                        ProfileCacheService.shared.saveImage(img, forURL: url)
                    }
                }

                nextCursor = nextId
                page += 1

                // Anti-bot: small pause between pages
                if nextCursor != nil && page < maxPages {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 600_000_000...1_200_000_000))
                }
            } while nextCursor != nil && page < maxPages

            // Persist final state
            var final = profile ?? cached
            final.cachedReelURLs  = allItems.map { $0.imageURL }
            final.cachedReelItems = allItems
            profile = final
            ProfileCacheService.shared.saveProfile(final)
            UserDefaults.standard.set(true, forKey: reelsPaginationKey)
            LogManager.shared.info("Reels lazy-loaded: \(allItems.count) items (\(page) page(s))", category: .general)
        } catch {
            reelsLoadedOnce = false // allow retry on next tab visit
            print("⚠️ [REELS] Lazy load failed (non-critical): \(error)")
        }
    }

    /// Fetches tagged posts for the own profile tab. Safe to call on-demand.
    /// - Parameter forceIfNoImages: when true, re-fetches even if URLs are already
    ///   cached — used when iOS purged the image cache and CDN URLs have expired.
    @MainActor
    private func fetchTaggedIfNeeded(
        for cached: InstagramProfile,
        forceIfNoImages: Bool = false,
        ensureVisibleMinimum: Bool = false
    ) async {
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
        let needsVisibleMinimum = ensureVisibleMinimum && cached.cachedTaggedURLs.count < secondaryTabVisibleMinimum
        guard cached.cachedTaggedURLs.isEmpty || taggedLooksOld || needsVisibleMinimum || forceIfNoImages else {
            print("🏷️ [TAGGED] Already cached (\(cached.cachedTaggedURLs.count)) — skipping fetch")
            return
        }
        if forceIfNoImages {
            print("🏷️ [TAGGED] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🏷️ [TAGGED] Lazy-loading tagged for first tab visit…")
        do {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserTagged(
                userId: cached.userId,
                amount: 50,
                maxPages: ensureVisibleMinimum ? 2 : 1,
                minimumItems: ensureVisibleMinimum ? secondaryTabVisibleMinimum : 0
            )
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

    /// Fetches story highlights for the own profile. Safe to call on-demand.
    @MainActor
    private func fetchHighlightsIfNeeded(for cached: InstagramProfile) async {
        guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionChallenged else {
            highlightsLoadedOnce = true
            return
        }
        guard !instagram.isUploadingProfilePic else {
            highlightsLoadedOnce = true
            return
        }
        guard !instagram.shouldUseCacheOnlyForOptionalCalls else {
            let rate = instagram.checkRateLimit()
            print("🛡️ [HIGHLIGHTS] Lazy load skipped near rate budget (\(rate.actionsUsed)/55)")
            highlightsLoadedOnce = true
            return
        }
        if !cached.cachedHighlights.isEmpty && cachedHighlightCoversAreReady(cached.cachedHighlights) {
            print("🌟 [HIGHLIGHTS] Already cached (\(cached.cachedHighlights.count)) with cover images — skipping fetch")
            highlightsLoadedOnce = true
            return
        }
        print("🌟 [HIGHLIGHTS] Lazy-loading highlights…")
        do {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserHighlights(userId: cached.userId)
            if items.isEmpty {
                print("🌟 [HIGHLIGHTS] Fetch returned 0 items — preserving existing cache and retrying later")
                LogManager.shared.warning("Highlights fetch returned 0 items; preserving cache and leaving retry available", category: .general)
                highlightsLoadedOnce = true
                return
            } else {
                markHighlightsChecked(for: cached.userId)
            }
            var updated = cached
            updated.cachedHighlights = items
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            // Download cover images
            for highlight in items {
                let url = highlight.coverImageURL
                if cachedImages[url] == nil, let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            print("🌟 [HIGHLIGHTS] Loaded \(items.count) highlights")
            LogManager.shared.info("Highlights lazy-loaded: \(items.count) items", category: .general)
        } catch {
            print("⚠️ [HIGHLIGHTS] Lazy load failed (non-critical): \(error)")
        }
        highlightsLoadedOnce = true
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
                // OCR is active when any slot has .ocr as its source, OR legacy OCR mode is set
                let noteOcr     = noteFeatureEnabled && (integrations.ocrSlot(for: "note") != nil || noteTopInputMode == "ocr")
                let bioOcr      = bioFeatureEnabled && (integrations.ocrSlot(for: "bio")  != nil || bioTopInputMode  == "ocr")
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
                    // Active when legacy OCR mode is set OR any slot has .ocr as its source
                    let hasBio  = bioFeatureEnabled && (bioTopInputMode  == "ocr" || integrations.ocrSlot(for: "bio")  != nil)
                    let hasNote = noteFeatureEnabled && (noteTopInputMode == "ocr" || integrations.ocrSlot(for: "note") != nil)
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
            if showingListInput, let set = activeListSet {
                ListSetInputView(
                    set: set,
                    onSettingsPress: {
                        showingListInput = false
                        selectedTab = 1
                    },
                    onSelect: { symbol in
                        showingListInput = false
                        if let slot = Int(symbol) {
                            pendingListReveal = slot
                        }
                        presentPerformanceCoverIfNeeded()
                    }
                )
                .zIndex(1200)
            }
            performanceCoverOverlay
            // NOTE: The background full-profile pre-loader has been retired. Performance
            // now loads its profile the same way UserProfileView (from Explore) does:
            // cache first, then one getProfileInfo() call if needed. The 90-second
            // "Getting ready" overlay (FullLoadOverlayView) is no longer rendered.
        }
            .background(Color(UIColor.igPageBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
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
            }
            .fullScreenCover(isPresented: $showingScreenOffCover) {
                ScreenOffCoverView {
                    showingScreenOffCover = false
                }
            }
            .fullScreenCover(isPresented: $showingLockscreen) {
                LockscreenInputView { digits in
                    showingLockscreen = false
                    if !digits.isEmpty {
                        pendingLockscreenDigits = digits
                    }
                    // If a performance cover is also enabled, show it next.
                    presentPerformanceCoverIfNeeded()
                }
            }
            .fullScreenCover(isPresented: $showingClockInput) {
                ClockInputView(
                    mode: isClockCardMode ? .card : .number,
                    onReveal: { digits in
                        pendingLockscreenDigits = digits
                    },
                    onRevealCard: { symbol in
                        pendingCardReveal = symbol
                    },
                    onDismiss: {
                        showingClockInput = false
                    }
                )
            }
            .fullScreenCover(isPresented: $showingCardNumpad) {
                CardNumpadInputView(
                    onSelect: { symbol in
                        pendingCardReveal = symbol
                    },
                    onDismiss: {
                        showingCardNumpad = false
                    }
                )
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
                // pendingProfilePic cleared (loadProfile migrated the pic to the new CDN URL).
                // Vibrate only if the auto-pic flow didn't already vibrate on POST success.
                if profilePicVibratedAlready {
                    profilePicVibratedAlready = false
                    print("📳 [PERF] Profile pic CDN migration complete — vibration already fired, skipping duplicate")
                } else {
                    fireDoubleConfirmationVibration()
                    print("📳 [PERF] Double vibration: profile pic confirmed live on Instagram CDN")
                    LogManager.shared.info("Profile pic confirmed live on Instagram (double vibration fired)", category: .general)
                }
            }
        }
        // Instantly reflect a biography update in the fake Instagram profile view.
        // changeBiography() saves to ProfileCacheService on success; we pick it up here.
        .onChange(of: profileCache.cachedProfile?.biography) { newBio in
            guard let newBio else { return }
            if isLoading && pendingBioText == nil && activeLocalBioOverride == nil {
                return
            }
            // If a bio POST is in-flight (OCR / interface capture), block any revert that
            // arrives from a concurrent loadProfile fetching the old bio from Instagram.
            // Once the POST completes (success or fail) pendingBioText is cleared and
            // the next cache change (which will carry the correct value) is accepted.
            if let pending = pendingBioText, newBio != pending {
                print("⚡️ [PERF] onChange bio: ignored revert to '\(newBio.prefix(30))' — pending POST for '\(pending.prefix(30))'")
                return
            }
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
            // Sync pull-to-refresh availability with any persisted SafetyGate cooldown
            // so the first pull after re-entering PerformanceView doesn't flash a spinner.
            let entryPullDecision = InstagramSafetyGate.shared.decision(for: .pullRefresh)
            if !entryPullDecision.allowed && entryPullDecision.waitSeconds > 0 {
                isRefreshEnabled = false
                let waitSec = entryPullDecision.waitSeconds
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(1, waitSec)) * 1_000_000_000)
                    isRefreshEnabled = true
                }
            } else {
                isRefreshEnabled = true
            }

            // Reset Post Prediction visual ring — new session starts clean.
            // The ring from the previous trick is cleared so the magician can see
            // a fresh confirmation for the current trick.
            postPredRevealRingActive = false

            // Screen always on — managed globally by MentalGram1App
            // Show fake lockscreen for secret digit entry (one-shot per session).
            // Guard required: onAppear re-fires when fullScreenCover is dismissed,
            // which would instantly re-present the lockscreen in an infinite loop.
            let lockscreenActive = isLockscreenActive
            let clockActive      = isClockInputActive
            let cardNumpadActive = isCardNumpadActive
            let listActive       = activeListSet != nil
            let interfaceKinds   = integrations.interfaceKindsInUse()
            print("🎩 [PERF] onAppear — listActive=\(listActive) lockscreenActive=\(lockscreenActive) cardNumpadActive=\(cardNumpadActive) clockActive=\(clockActive) interfaceKinds=\(interfaceKinds) listInputWasShown=\(listInputWasShown) lockscreenWasShown=\(lockscreenWasShown) cardNumpadWasShown=\(cardNumpadWasShown) clockInputWasShown=\(clockInputWasShown)")

            if !listInputWasShown && listActive {
                listInputWasShown = true
                showingListInput = true
                print("📋 [LIST-SET] Showing private list selector")
            }
            else if !lockscreenWasShown && lockscreenActive {
                lockscreenWasShown = true
                showingLockscreen = true
                print("🔒 [LOCKSCREEN] Showing fake lockscreen for secret input")
            }
            else if !cardNumpadWasShown && !lockscreenWasShown && cardNumpadActive {
                cardNumpadWasShown = true
                showingCardNumpad = true
                print("🃏 [CARD-NUMPAD] Showing black card selector")
            }
            // Show clock input black screen if mode is active (and lockscreen isn't)
            else if !clockInputWasShown && !lockscreenWasShown && !cardNumpadWasShown && clockActive {
                clockInputWasShown = true
                showingClockInput = true
                print("🖤 [CLOCK-INPUT] Showing black screen for swipe digit input")
            }
            // Show performance cover if enabled. Fake Home Screen uses the uploaded
            // screenshot; Fake Screen Off uses the same tap-to-reveal flow with black.
            else if shouldShowPerformanceCover && !performanceCoverWasShown && !showingLockscreen && !showingClockInput && !showingCardNumpad && !showingListInput {
                presentPerformanceCoverIfNeeded()
                print("🏠 [ILLUSION] \(effectivePerformanceCoverMode.title) active — tap to reveal profile")
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
            // Also activate volume monitoring when any bio/note {textN} placeholder
            // uses OCR as its source (even if the legacy top-level mode is "off").
            let hasPlaceholderOCR = integrations.interfaceKindsInUse().contains(.ocr)
            let needsVolume = FollowingMagicSettings.shared.isEnabled
                || (noteFeatureEnabled && noteTopInputMode == "ocr")
                || (bioFeatureEnabled && bioTopInputMode  == "ocr")
                || ppTopInputMode == "ocr"
                || hasPlaceholderOCR
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
                // 1. Auto profile pic. The local fake UI update happens immediately inside
                // autoUploadLatestGalleryPhoto(); only the real Instagram POST is delayed
                // by cold-start / profile-refresh safety gates.
                if autoProfilePicOnPerformance {
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
                        await applyURLAction(mode: action.mode, text: action.text, values: action.values)
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
                    await applyURLAction(mode: action.mode, text: action.text, values: action.values)
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
            guard let current = profile else { return }
            let mediaURLs = mediaItems.map { $0.imageURL }

            // ── Bridge CDN URL rotation by mediaId ─────────────────────────────
            // Instagram rotates CDN tokens per-session. Build a reverse-lookup
            // from mediaId → cached image using the current mediaItemsByURL so we
            // can copy already-downloaded images to the new URL keys. This avoids
            // the flash of gray cells when the first-page arrives with rotated URLs.
            let oldItemsByMediaId: [String: InstagramMediaItem] = mediaItemsByURL.values.reduce(into: [:]) {
                $0[$1.mediaId] = $1
            }
            for newItem in mediaItems {
                guard cachedImages[newItem.imageURL] == nil,
                      let oldItem = oldItemsByMediaId[newItem.mediaId],
                      let bridgedImage = cachedImages[oldItem.imageURL] else { continue }
                cachedImages[newItem.imageURL] = bridgedImage
            }

            // ── Preserve pagination tail ────────────────────────────────────────
            // The progressive notification only carries page-1 (~12 items).
            // If the current grid has more items (user had scrolled), keep the
            // tail so the grid doesn't visibly collapse from e.g. 36→12.
            let newMediaIds = Set(mediaItems.map { $0.mediaId })
            let existingTail = allMediaURLs.filter { url -> Bool in
                guard let item = mediaItemsByURL[url] else { return false }
                return !newMediaIds.contains(item.mediaId)
            }
            let finalURLs = mediaURLs + existingTail

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
            allMediaURLs = finalURLs
            if nextMaxId == nil { nextMaxId = nextCursor }
            hasMorePages = true
            // Seed mediaItemsByURL for the post viewer (likes/comments/date).
            for item in mediaItems { mediaItemsByURL[item.imageURL] = item }
            ProfileCacheService.shared.saveProfile(updated)
            let tailCount = existingTail.count
            print("⚡ [PERF] Progressive: posts grid painted (\(mediaURLs.count) fresh + \(tailCount) tail preserved)")
            LogManager.shared.info("Performance painted progressive grid — \(mediaURLs.count) posts before chain finished", category: .general)
            loadCachedImages()
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
            guard selectedTab != 0 else {
                print("🎩 [PERF] Transient onDisappear while still in Performance — keeping cover/OCR/API active")
                return
            }
            // Reset one-shot flags so they fire again on the next entry into Performance
            resetFullscreenInputPresentationFlags()
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
        .onChange(of: selectedTab) { tab in
            guard tab != 0 else { return }
            // TabView can keep PerformanceView alive, so onDisappear is not always
            // enough. Reset the one-shot fullscreen input flags when the user leaves
            // Performance so Card Numpad / Lockscreen / Clock / List show again next time.
            resetFullscreenInputPresentationFlags()
            resetPerformanceCoverPresentationFlags()
            performanceEntryRecorded = false
            print("🎩 [TRANSFER] Performance tab changed — stopping monitoring (transferOffset:\(FollowingMagicSettings.shared.transferOffset))")
            VolumeButtonMonitor.shared.stopMonitoring()
            ocrCoordinator.stop()
            stopApiPolling()
            uploadManager.isPausedByPerformance = false
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
                fireDoubleConfirmationVibration()
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

    /// Replaces `{text1}`, `{text2}`, `{text3}`, `{text4}`, `{text5}` (and the legacy alias `{word}` = `{text1}`)
    /// in `template` with the provided value map, then expands `\n` escapes.
    /// Returns `values["text1"] ?? ""` (with escapes expanded) when template is empty.
    private func applyTemplate(_ values: [String: String], template: String) -> String {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return expandEscapes(values["text1"] ?? "")
        }
        var result = t
        // {word} is a legacy alias for {text1}
        if let v1 = values["text1"] {
            result = result
                .replacingOccurrences(of: "{word}", with: v1)
                .replacingOccurrences(of: "{text1}", with: v1)
        }
        if let v2 = values["text2"] { result = result.replacingOccurrences(of: "{text2}", with: v2) }
        if let v3 = values["text3"] { result = result.replacingOccurrences(of: "{text3}", with: v3) }
        if let v4 = values["text4"] { result = result.replacingOccurrences(of: "{text4}", with: v4) }
        if let v5 = values["text5"] { result = result.replacingOccurrences(of: "{text5}", with: v5) }
        return expandEscapes(result)
    }

    /// Legacy single-word overload — maps `word` to `{text1}`.
    private func applyTemplate(_ word: String, template: String) -> String {
        applyTemplate(["text1": word], template: template)
    }

    // MARK: - URL Scheme Action

    private func applyURLAction(mode: String, text: String, values: [String: String] = [:]) async {
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

        // ── Custom/List Set reveal via vault://reveal?slot= ───────────────────
        if mode == "reveal_slot" {
            guard let slot = Int(text), (1...100).contains(slot) else {
                print("⚠️ [URL] Invalid slot value: \"\(text)\"")
                return
            }
            let activeSettings = ActiveSetSettings.shared
            guard let activeId = activeSettings.activeCustomSetId ?? activeSettings.activeListSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && ($0.type == .custom || $0.type == .list) }) else {
                print("🚫 [URL] Slot reveal: no active custom/list set")
                LogManager.shared.warning("URL slot reveal: no active custom/list set", category: .general)
                return
            }
            if UploadManager.shared.isActive && !didAutoPauseUpload {
                print("⚠️ [URL] Custom slot reveal blocked: upload is active and not paused by Performance")
                return
            }
            print("📲 [URL] Slot reveal: slot=\(slot) from '\(activeSet.name)'")
            LogManager.shared.info("URL reveal → slot \(slot) from '\(activeSet.name)'", category: .general)
            await MainActor.run {
                if activeSet.type == .list {
                    pendingListReveal = slot
                } else {
                    pendingSlotReveal = slot
                }
            }
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

        if (mode == "note" && !noteFeatureEnabled) || (mode == "bio" && !bioFeatureEnabled) {
            print("⏭️ [URL] \(mode) disabled — skipping")
            LogManager.shared.info("URL scheme \(mode) skipped because feature is disabled", category: .general)
            return
        }

        do {
            // Build effective value dict: use URL-scheme values when provided, else fall back to `text`
            let effectiveValues: [String: String] = values.isEmpty ? ["text1": text] : values

            // Apply text template ({text1}/{text2}/{text3}/{text4}/{text5}/{word} → URL-scheme values)
            let tpl = mode == "note" ? noteTemplate : bioTemplate
            let composed = tpl.isEmpty ? expandEscapes(text) : applyTemplate(effectiveValues, template: tpl)

            if mode == "note" {
                let final = truncateAtWordBoundary(composed, limit: 60)
                if final.count < composed.count {
                    print("✂️ [URL] Note truncated: \(composed.count)→\(final.count) chars")
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
                let final = truncateAtWordBoundary(composed, limit: 150)
                if final.count < composed.count {
                    print("✂️ [URL] Bio truncated: \(composed.count)→\(final.count) chars")
                }
                // Optimistic: show bio immediately.
                // Pin pendingBioText so a concurrent loadProfile fetching the old bio
                // from Instagram while the POST is in-flight cannot revert the UI.
                await MainActor.run { pinLocalBiography(final) }
                do {
                    let ok = try await instagram.changeBiography(text: final)
                    if ok {
                        print("✅ [URL] Biography updated via URL scheme")
                        LogManager.shared.success("Biography updated via URL scheme (\(final.count) chars)", category: .general)
                        fireDoubleConfirmationVibration()
                    }
                } catch {
                    print("⚠️ [URL] Bio change failed: \(error.localizedDescription)")
                    LogManager.shared.warning("URL scheme bio failed: \(error.localizedDescription)", category: .general)
                }
                await MainActor.run { pendingBioText = nil }
            }
        } catch {
            print("⚠️ [URL] Action failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme action failed: \(error.localizedDescription)", category: .general)
        }
    }

    private var activeLocalBioOverride: String? {
        guard let override = localBioOverride else { return nil }
        guard Date().timeIntervalSince(override.timestamp) < 5 * 60 else { return nil }
        return override.text
    }

    @MainActor
    private func pinLocalBiography(_ text: String) {
        pendingBioText = text
        localBioOverride = (text, Date())
        applyBiographyToVisibleProfile(text)
    }

    @MainActor
    private func applyBiographyToVisibleProfile(_ text: String) {
        guard let current = profile else { return }
        profile = profileByReplacingBiography(current, biography: text)
    }

    private func profileByReplacingBiography(_ current: InstagramProfile, biography: String) -> InstagramProfile {
        InstagramProfile(
            userId: current.userId, username: current.username,
            fullName: current.fullName, biography: biography,
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

    // MARK: - Clipboard Auto-Mode

    private func applyClipboardAutoMode() async {
        guard clipboardAutoMode == "note" || clipboardAutoMode == "bio" else { return }
        guard targetFeatureEnabled(clipboardAutoMode) else {
            print("⏭️ [CLIPBOARD] \(clipboardAutoMode) disabled — skipping")
            return
        }
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
                let inputForBio = bioAcrosticEnabled ? text : composed
                let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
                let final = truncateAtWordBoundary(acrosticComposed, limit: 150)
                if final.count < acrosticComposed.count {
                    print("✂️ [CLIPBOARD] Biography truncated at word boundary: \(acrosticComposed.count)→\(final.count) chars")
                }
                // Optimistic: show bio immediately
                await MainActor.run { pinLocalBiography(final) }
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

    private func targetFeatureEnabled(_ target: String) -> Bool {
        target == "note" ? noteFeatureEnabled : bioFeatureEnabled
    }

    /// Fetches a value from the configured API source and applies it as note or biography.
    private func applyApiAutoMode(target: String, preloadedValue: String? = nil) async {
        guard targetFeatureEnabled(target) else {
            print("⏭️ [API AUTO] \(target) disabled — skipping")
            return
        }
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

        // Determine primary source (text1) — falls back to legacy single source
        let primarySource = target == "note"
            ? (integrations.noteText1Source != .none ? integrations.noteText1Source : integrations.noteApiSource)
            : (integrations.bioText1Source  != .none ? integrations.bioText1Source  : integrations.bioApiSource)
        guard primarySource != .none || integrations.hasTemplateSources(for: target) else { return }

        // ── Fetch primary (text1) value ──
        let primaryText: String
        if let preloaded = preloadedValue, !preloaded.isEmpty {
            primaryText = preloaded
            print("⚡ [API AUTO] Using preloaded value for target=\(target): \"\(primaryText.prefix(40))\"")
        } else if primarySource != .none {
            print("⚡ [API AUTO] Fetching from \(primarySource.displayName) for target=\(target)…")
            guard let fetched = await integrations.fetchValue(for: primarySource), !fetched.isEmpty else {
                print("⚠️ [API AUTO] No value received from \(primarySource.displayName)")
                LogManager.shared.warning("Magic API returned no value (\(primarySource.displayName))", category: .general)
                return
            }
            primaryText = fetched
        } else {
            primaryText = ""
        }

        // Skip if same primary value was already sent within 2 hours — avoids Instagram duplicate spam rejection
        let ud = UserDefaults.standard
        let lastKey   = target == "note" ? "last_note_auto_input"      : "last_biography_text"
        let dateKey   = target == "note" ? "last_note_auto_sent_date"  : "last_biography_sent_date"
        let trimmed   = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
            let sentDate   = ud.object(forKey: dateKey) as? Date ?? .distantPast
            let hoursSince = Date().timeIntervalSince(sentDate) / 3600
            if hoursSince < 2 {
                print("⏭️ [API AUTO] Dedup: same text sent \(String(format: "%.0f", hoursSince * 60))m ago — skipping (\"\(primaryText.prefix(30))\")")
                return
            }
            print("⏭️ [API AUTO] Dedup expired (\(String(format: "%.1f", hoursSince))h) — allowing re-send")
            ud.removeObject(forKey: lastKey)
        }

        // ── Fetch text2 / text3 / text4 / text5 in parallel (if configured) ──
        var values: [String: String] = [:]
        if !primaryText.isEmpty { values["text1"] = primaryText }

        let src2 = target == "note" ? integrations.noteText2Source : integrations.bioText2Source
        let src3 = target == "note" ? integrations.noteText3Source : integrations.bioText3Source
        let src4 = target == "note" ? integrations.noteText4Source : integrations.bioText4Source
        let src5 = target == "note" ? integrations.noteText5Source : integrations.bioText5Source
        if src2 != .none || src3 != .none || src4 != .none || src5 != .none {
            async let v2 = src2 != .none ? integrations.fetchValue(for: src2) : nil
            async let v3 = src3 != .none ? integrations.fetchValue(for: src3) : nil
            async let v4 = src4 != .none ? integrations.fetchValue(for: src4) : nil
            async let v5 = src5 != .none ? integrations.fetchValue(for: src5) : nil
            let (r2, r3, r4, r5) = await (v2, v3, v4, v5)
            if let r2 { values["text2"] = r2 }
            if let r3 { values["text3"] = r3 }
            if let r4 { values["text4"] = r4 }
            if let r5 { values["text5"] = r5 }
        }

        let text = primaryText.isEmpty ? (values["text2"] ?? values["text3"] ?? values["text4"] ?? values["text5"] ?? "") : primaryText
        print("⚡ [API AUTO] Values for \(target): \(values.map { "\($0.key)=\($0.value.prefix(20))" }.joined(separator: ", "))")
        LogManager.shared.info("Magic API → \(target): \(values.map { "\($0.key)=\($0.value.prefix(20))" }.joined(separator: ", "))", category: .general)

        // Apply text template ({text1}/{text2}/{text3}/{word} → fetched values)
        let tpl = target == "note" ? noteTemplate : bioTemplate
        let composed = applyTemplate(values, template: tpl)
        if !tpl.isEmpty {
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
                // When acrostic mode is ON, bypass the template and feed the raw
                // fetched word directly to the acrostic engine — the template
                // would produce a sentence with spaces that the engine would reject.
                let inputForBio = bioAcrosticEnabled ? text : composed
                let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
                let final = truncateAtWordBoundary(acrosticComposed, limit: 150)
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run { pinLocalBiography(final) }
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
        // Bio/Note active if any polled placeholder source is configured — no mode gate needed,
        // the source selection itself determines whether polling should run.
        // .ocr sources are event-driven and excluded via isPolled.
        let bioActive  = integrations.bioText1Source.isPolled  || integrations.bioText2Source.isPolled  || integrations.bioText3Source.isPolled  || integrations.bioText4Source.isPolled  || integrations.bioText5Source.isPolled  || integrations.bioApiSource.isPolled
        let noteActive = integrations.noteText1Source.isPolled || integrations.noteText2Source.isPolled || integrations.noteText3Source.isPolled || integrations.noteText4Source.isPolled || integrations.noteText5Source.isPolled || integrations.noteApiSource.isPolled
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
                    // Use first polled text1 source as the primary poll trigger
                    let text1src  = target == "note" ? integrations.noteText1Source  : integrations.bioText1Source
                    let legacySrc = target == "note" ? integrations.noteApiSource    : integrations.bioApiSource
                    let source    = text1src.isPolled ? text1src : (legacySrc.isPolled ? legacySrc : .none)
                    let hasPolledSrc = source.isPolled
                        || (target == "note" ? integrations.noteText2Source.isPolled || integrations.noteText3Source.isPolled || integrations.noteText4Source.isPolled || integrations.noteText5Source.isPolled
                                             : integrations.bioText2Source.isPolled  || integrations.bioText3Source.isPolled  || integrations.bioText4Source.isPolled  || integrations.bioText5Source.isPolled)
                    guard hasPolledSrc else { continue }

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
            noteActive ? ("note", integrations.noteText1Source != .none ? integrations.noteText1Source : integrations.noteApiSource) : nil,
            bioActive  ? ("bio",  integrations.bioText1Source  != .none ? integrations.bioText1Source  : integrations.bioApiSource)  : nil,
            ppActive   ? ("pp",   integrations.ppApiSource) : nil
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

    // Applies Acrostic Mode if enabled and the text is a single word.
    // Returns the acrostic poem, or the original text if conditions are not met.
    private func applyAcrosticIfNeeded(_ text: String) -> String {
        guard bioAcrosticEnabled else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespaces) == nil else { return text }
        guard let poem = AcrosticEngine.build(word: trimmed) else { return text }
        print("🔤 [ACROSTIC] '\(trimmed)' → poem (\(poem.count) chars)")
        return poem
    }

    private func applyOCRResult(text: String, target: String) async {
        guard targetFeatureEnabled(target) else {
            print("⏭️ [OCR] \(target) disabled — skipping")
            return
        }
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

        // Determine which slot the OCR word goes into (the one configured as .ocr, default text1)
        let ocrSlot = integrations.ocrSlot(for: target) ?? 1
        let slotKey = "text\(ocrSlot)"
        let ocrValues: [String: String] = [slotKey: trimmed]

        // Apply text template: OCR fills the configured slot; other slots are resolved from their APIs
        let tpl = target == "note" ? noteTemplate : bioTemplate
        // Fetch any non-OCR API sources in parallel
        var resolvedValues = await integrations.fetchTemplatePlaceholders(for: target, ocrValues: ocrValues)
        // OCR value always wins for its assigned slot
        resolvedValues[slotKey] = trimmed
        let composed = tpl.isEmpty ? trimmed : applyTemplate(resolvedValues, template: tpl)
        print("📷 [OCR] Template applied (\(target), slot=\(slotKey)): \"\(composed.prefix(60))\"")


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
                // When acrostic mode is ON, bypass the template and feed the raw
                // OCR word directly to the acrostic engine.
                let inputForBio = bioAcrosticEnabled ? trimmed : composed
                let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
                let final = truncateAtWordBoundary(acrosticComposed, limit: 150)

                // ── Optimistic UI update (fake profile shows result instantly) ────────
                // Pin pendingBioText so that a concurrent loadProfile (fetching the old
                // bio from Instagram while our POST is in-flight) cannot revert the fake
                // profile via onChange(of: profileCache.cachedProfile?.biography).
                await MainActor.run { pinLocalBiography(final) }

                // ── Direct POST — mirrors mentalgram5's proven pattern ─────────────
                // No cold-start delay or jitter here. The real root cause of the previous
                // HTTP 400 "new login from device" was changeBiography sending email=""
                // (empty string) when edit-profile fields weren't cached, which Instagram
                // interprets as "clear my email from an unknown device".
                // That is fixed by prefetchEditFieldsIfNeeded() (fires 20s after session
                // validation) and by the body builder in changeBiography that now omits
                // empty identity fields instead of sending empty strings.
                // Adding extra delays here introduces guard-fail-after-sleep bugs where
                // UploadManager or isLocked state can change during the sleep window and
                // silently abort the POST while leaving the fake profile reverted.
                let ok = try await instagram.changeBiography(text: final)
                await MainActor.run { pendingBioText = nil }
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // raw word for dedup
                    ud.set(Date(), forKey: dateKey)   // timestamp so dedup expires in 2h
                    print("✅ [OCR] Biography updated: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            await MainActor.run { pendingBioText = nil }
            print("⚠️ [OCR] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("OCR auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Interface capture → bio/note injection

    /// Routes a value captured by a secret input interface (Lockscreen / Number Clock /
    /// Card Clock) into any bio & note {textN} slots whose source matches one of `kinds`,
    /// then sends the composed note / biography. This lets a single capture both reveal a
    /// set AND fill the prediction text. Mirrors applyOCRResult's anti-bot dedup.
    private func applyInterfaceCapture(value: String, kinds: Set<InterfaceKind>) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await applyInterfaceCaptureToTarget(value: trimmed, kinds: kinds, target: "note")
        await applyInterfaceCaptureToTarget(value: trimmed, kinds: kinds, target: "bio")
    }

    // Minimum gap between consecutive interface-capture bio/note sends (anti-bot).
    // Prevents a second accidental lockscreen/clock dismiss from firing a second POST
    // within seconds of the first — same philosophy as interRevealCooldown for unarchives.
    private let interfaceCaptureCooldown: TimeInterval = 90

    private func applyInterfaceCaptureToTarget(value: String, kinds: Set<InterfaceKind>, target: String) async {
        guard targetFeatureEnabled(target) else {
            print("⏭️ [INPUT] \(target) disabled — skipping")
            return
        }
        guard instagram.isLoggedIn, !instagram.isLocked else { return }
        // Don't stack a note/bio POST on top of a running upload (anti-bot).
        guard !UploadManager.shared.isActive else { return }
        // Respect cache-only mode (re-entry too soon safety gate).
        guard performanceRemoteCallsAllowed else {
            print("⏭️ [INPUT] Skipped (\(target)): cache-only mode active")
            return
        }

        // Inter-capture cooldown: block a second send within 90s of the last one for
        // this target, regardless of value. Prevents rapid consecutive POSTs during
        // testing or accidental double-dismiss of the input overlay.
        let cooldownKey = "last_interface_capture_sent_\(target)"
        let lastSentTime = UserDefaults.standard.double(forKey: cooldownKey)
        let timeSinceLast = Date().timeIntervalSince1970 - lastSentTime
        if lastSentTime > 0, timeSinceLast < interfaceCaptureCooldown {
            let remaining = Int(interfaceCaptureCooldown - timeSinceLast)
            print("⏭️ [INPUT] Cooldown: \(remaining)s remaining before next \(target) capture send")
            LogManager.shared.warning("Interface capture \(target) blocked: cooldown \(remaining)s remaining", category: .general)
            return
        }

        let sources: [ApiSource] = target == "note"
            ? [integrations.noteText1Source, integrations.noteText2Source, integrations.noteText3Source, integrations.noteText4Source, integrations.noteText5Source]
            : [integrations.bioText1Source,  integrations.bioText2Source,  integrations.bioText3Source,  integrations.bioText4Source,  integrations.bioText5Source]
        let matchingSlots = sources.enumerated().compactMap { idx, src -> Int? in
            guard let k = src.interfaceKind, kinds.contains(k) else { return nil }
            return idx + 1
        }
        guard !matchingSlots.isEmpty else { return }

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_auto_input"     : "last_biography_text"
        let dateKey = target == "note" ? "last_note_auto_sent_date" : "last_biography_sent_date"

        // Dedup (2h) on the raw captured value — same policy as OCR to avoid duplicate-note spam flags
        if let lastSent = ud.string(forKey: lastKey), lastSent == value {
            let sentDate = ud.object(forKey: dateKey) as? Date ?? .distantPast
            if Date().timeIntervalSince(sentDate) / 3600 < 2 {
                print("⏭️ [INPUT] Dedup: same value sent recently — skipping (\(target))")
                return
            }
            ud.removeObject(forKey: lastKey)
        }

        let tpl = target == "note" ? noteTemplate : bioTemplate
        // Resolve polled API slots in parallel, then overwrite the interface-driven slots.
        var resolvedValues = await integrations.fetchTemplatePlaceholders(for: target)
        for slot in matchingSlots { resolvedValues["text\(slot)"] = value }
        let composed = tpl.isEmpty ? value : applyTemplate(resolvedValues, template: tpl)

        LogManager.shared.info("Interface capture → \(target): \"\(composed.prefix(40))\"", category: .general)

        // ── Immediate UI update (fake profile shows result instantly) ──────────
        // The fake Instagram profile is updated right away so the magician sees
        // the correct bio/note the moment the overlay dismisses. The actual API
        // POST to real Instagram is intentionally delayed below (anti-bot).
        // pendingBioText is pinned for the bio target so that a concurrent
        // loadProfile (fetching old bio from Instagram while POST is in-flight)
        // cannot revert the fake profile via onChange(cachedProfile?.biography).
        let finalText: String
        if target == "note" {
            finalText = truncateAtWordBoundary(composed, limit: 60)
            await MainActor.run { lastNoteText = finalText }
        } else {
            finalText = truncateAtWordBoundary(composed, limit: 150)
            await MainActor.run { pinLocalBiography(finalText) }
        }

        // ── Direct POST — mirrors mentalgram5's proven pattern ───────────────────
        // No cold-start delay or jitter. The previous HTTP 400 "new login from device"
        // was caused by changeBiography sending empty strings for email/phone when
        // edit-profile fields weren't cached — fixed by prefetchEditFieldsIfNeeded().
        // Adding delays here introduced guard-fail-after-sleep bugs where state changes
        // during the sleep window silently aborted the POST and left the bio reverted.
        // Stamp the cooldown timestamp before the POST so a second rapid send is
        // still blocked for 90s even if the request fails.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cooldownKey)

        do {
            if target == "note" {
                let ok = try await instagram.createNote(text: finalText)
                if ok {
                    ud.set(value, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [INPUT] Note sent: \"\(finalText)\"")
                    // Double vibration: confirms the note is live on real Instagram
                    fireDoubleConfirmationVibration()
                }
            } else {
                let ok = try await instagram.changeBiography(text: finalText)
                await MainActor.run { pendingBioText = nil }
                if ok {
                    ud.set(value, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    print("✅ [INPUT] Biography updated: \"\(finalText)\"")
                    // Double vibration: confirms the biography is live on real Instagram
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            await MainActor.run { pendingBioText = nil }
            LogManager.shared.warning("Interface capture send failed (\(target)): \(error.localizedDescription)", category: .general)
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
        Task {
            await MainActor.run {
                // Activate orange ring on the profile avatar for every confirmed Instagram update
                // (note, bio, profile pic, reveal) so the magician always gets visual confirmation.
                postPredRevealRingActive = true
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
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

            if let localBio = activeLocalBioOverride, cached.biography != localBio {
                print("⚡️ [PERF] Preserving local bio override while loading cached profile")
                cached = profileByReplacingBiography(cached, biography: localBio)
            }

            self.profile = cached
            // If highlights are already in cache we know the final state immediately.
            if !cached.cachedHighlights.isEmpty { highlightsLoadedOnce = true }
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
    
    /// Fetches reels and tagged in background, preserving cached highlights.
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

            let reelURLs     = reels.map { $0.imageURL }
            let taggedURLs   = tagged.map { $0.imageURL }

            print("📦 [CACHE] Background fetch: \(reelURLs.count) reels, \(taggedURLs.count) tagged, highlights preserved:\(cached.cachedHighlights.count)")

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
                cachedHighlights: cached.cachedHighlights,
                cachedReelItems: reels,
                cachedNextMaxId: cached.cachedNextMaxId
            )

            self.profile = updated
            ProfileCacheService.shared.saveProfile(updated)

            // Download thumbnails for reels + tagged only. Highlight covers are
            // downloaded when they are explicitly rebuilt outside Performance.
            let allNew = reelURLs + taggedURLs
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
        // Guard against concurrent pulls.
        guard !isPullRefreshInFlight, !isLoading, !isSilentGridRefreshing else {
            print("🚫 [PERF] Pull refresh skipped — refresh already in progress")
            return
        }
        isPullRefreshInFlight = true
        defer { isPullRefreshInFlight = false }

        // ── ALL blocking checks FIRST (before any disk I/O) ──────────────────
        // This guarantees the async func returns in *microseconds* when blocked,
        // so the SwiftUI spinner disappears before the user can pull again.
        // (Previously checkAndLoadProfile — which does disk reads — ran first,
        //  keeping the spinner alive for 300–500 ms even on a blocked pull.)

        guard performanceRemoteCallsAllowed,
              !uploadManager.isActive,
              !instagram.isLocked,
              !instagram.isSessionChallenged,
              !instagram.isUploadingProfilePic else {
            print("🛡️ [PERF] Pull refresh cache-only — session/upload guard")
            return
        }

        let now = Date().timeIntervalSince1970
        let timeSinceGridRefresh = now - lastAutoRefreshTimestamp
        guard lastAutoRefreshTimestamp == 0 || timeSinceGridRefresh >= fullRefreshAfterGridRefreshGap else {
            print("🛡️ [PERF] Pull refresh cache-only — grid refreshed \(Int(timeSinceGridRefresh))s ago")
            LogManager.shared.warning("SAFETY BLOCK — full refresh skipped after recent grid refresh", category: .general)
            return
        }

        let timeSinceLastRefresh = now - lastRefreshTimestamp
        guard lastRefreshTimestamp == 0 || timeSinceLastRefresh >= minRefreshInterval else {
            print("🚫 [PERF] Pull refresh cache-only — \(Int(timeSinceLastRefresh))s since last refresh")
            return
        }

        if instagram.shouldUseCacheOnlyForOptionalCalls {
            let rate = instagram.checkRateLimit()
            print("🛡️ [PERF] Pull refresh blocked — near hourly budget (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("PULL BLOCKED — rate budget (\(rate.actionsUsed)/55)", category: .general)
            InstagramSafetyGate.shared.record(.pullRefresh)
            isRefreshEnabled = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(120) * 1_000_000_000)
                isRefreshEnabled = true
            }
            return
        }

        let safetyCheck = InstagramSafetyGate.shared.decision(for: .pullRefresh)
        guard safetyCheck.allowed else {
            print("🛡️ [PERF] Pull refresh blocked by safety gate — \(safetyCheck.waitSeconds)s remaining")
            let waitSec = max(1, safetyCheck.waitSeconds)
            isRefreshEnabled = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
                isRefreshEnabled = true
            }
            return
        }

        // ── All checks passed: do the cache read + network load ───────────────
        // checkAndLoadProfile renders the latest cache while the network call runs.
        checkAndLoadProfile(allowRemote: false)
        await loadProfile(source: "manual")

        // Keep pull-to-refresh disabled for 120 s (= SafetyGate minGap) so the
        // user can't trigger a second full load right after this one.
        isRefreshEnabled = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(120) * 1_000_000_000)
            isRefreshEnabled = true
        }
    }

    @MainActor
    private func loadProfile(source: String) async {
        guard instagram.isLoggedIn else { return }

        if instagram.shouldUseCacheOnlyForOptionalCalls {
            let rate = instagram.checkRateLimit()
            print("🛡️ [PERF] loadProfile skipped — near hourly budget (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("CACHE ONLY — loadProfile skipped near rate budget (\(rate.actionsUsed)/55)", category: .general)
            // Record a SafetyGate stamp so the CooldownWarningBanner shows the
            // "Performance Refresh" countdown even when the budget is the blocker.
            // The 120 s window keeps the pull gesture disabled for the same duration.
            if source == "manual" {
                InstagramSafetyGate.shared.record(.pullRefresh)
            }
            return
        }

        let safetyAction: InstagramSafetyGate.Action = source == "entry" ? .entryRefresh : .pullRefresh
        let safetyDecision = InstagramSafetyGate.shared.decision(for: safetyAction)
        guard safetyDecision.allowed else {
            print("🛡️ [PERF] loadProfile blocked — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — loadProfile \(source): \(safetyDecision.reason)", category: .general)
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
                var mergedProfile = fetchedProfile
                let preservedProfile = self.profile ?? ProfileCacheService.shared.loadProfile()
                if let preservedProfile {
                    // getProfileInfo() intentionally refreshes only the visible profile
                    // surface (header/followers/posts). Preserve secondary tabs so a
                    // Performance entry refresh does not wipe cached Reels/Tagged/Highlights
                    // and briefly show Instagram's empty-state placeholders.
                    if mergedProfile.cachedReelURLs.isEmpty && !preservedProfile.cachedReelURLs.isEmpty {
                        mergedProfile.cachedReelURLs = preservedProfile.cachedReelURLs
                        mergedProfile.cachedReelItems = preservedProfile.cachedReelItems
                    }
                    if mergedProfile.cachedReelItems.isEmpty && !preservedProfile.cachedReelItems.isEmpty {
                        mergedProfile.cachedReelItems = preservedProfile.cachedReelItems
                    }
                    if mergedProfile.cachedTaggedURLs.isEmpty && !preservedProfile.cachedTaggedURLs.isEmpty {
                        mergedProfile.cachedTaggedURLs = preservedProfile.cachedTaggedURLs
                    }
                    if mergedProfile.cachedHighlights.isEmpty && !preservedProfile.cachedHighlights.isEmpty {
                        mergedProfile.cachedHighlights = preservedProfile.cachedHighlights
                    }
                }
                // Keep the user-scoped image cache during refresh so existing thumbnails
                // remain visible while fresh metadata is saved over the old profile.json.
                mediaItemsByURL.removeAll()
                revealDates.removeAll()
                // Keep cachedImages so existing thumbnails stay visible during transition

                // ── Bridge CDN URL rotation for the profile pic ────────────────────
                // Instagram rotates CDN query-string tokens on every profile fetch.
                // Copy the cached image to the new URL key BEFORE updating self.profile
                // so the header never flashes a blank/placeholder between the two URLs.
                let oldPicURL = self.profile?.profilePicURL ?? ""
                let newPicURL = mergedProfile.profilePicURL
                if !newPicURL.isEmpty, newPicURL != oldPicURL {
                    let bridged = cachedImages[oldPicURL]
                        ?? ProfileCacheService.shared.loadImage(forURL: oldPicURL)
                    if let img = bridged {
                        cachedImages[newPicURL] = img
                        print("⚡️ [PERF] Profile pic bridged old→new CDN URL — no blank frame")
                    }
                }

                if let localBio = activeLocalBioOverride, mergedProfile.biography != localBio {
                    print("⚡️ [PERF] Preserving local bio override during profile refresh")
                    mergedProfile = profileByReplacingBiography(mergedProfile, biography: localBio)
                }

                        self.profile = mergedProfile
                // ── Preserve pagination tail — don't collapse the grid ─────────────
                // loadProfile returns only page-1 items (typically 12). If the grid
                // already shows 24 items (from cache + silent refresh + pagination),
                // overwriting with 12 would cause a visible collapse and then re-grow.
                // Keep the tail items from the previous allMediaURLs; they use old CDN
                // URL tokens that remain valid within the session.
                let newFirst = mergedProfile.cachedMediaURLs
                if allMediaURLs.count > newFirst.count {
                    let tail = Array(allMediaURLs.suffix(allMediaURLs.count - newFirst.count))
                    self.allMediaURLs = newFirst + tail
                } else {
                    self.allMediaURLs = newFirst
                }
                // Seed the pagination cursor so the first scroll-triggered call
                // fetches page 2 directly instead of re-loading page 1.
                if self.nextMaxId == nil {
                    self.nextMaxId = mergedProfile.cachedNextMaxId
                }
                self.hasMorePages = true
                // Populate post viewer data (likes/comments already in items, 0 extra API calls)
                for item in mergedProfile.cachedMediaItems {
                    mediaItemsByURL[item.imageURL] = item
                }
                // If the full refresh already brought reels/tagged, mark them as loaded
                // so the lazy-tab loader doesn't make redundant API calls.
                // For reels we also require the full items (with videoURL); without
                // them the grid would show static thumbnails instead of video.
                if !mergedProfile.cachedReelURLs.isEmpty && !mergedProfile.cachedReelItems.isEmpty {
                    reelsLoadedOnce = true
                }
                if !mergedProfile.cachedTaggedURLs.isEmpty { taggedLoadedOnce = true }
                // Highlights are preserved from cache; Performance no longer rebuilds
                // them automatically to avoid a hidden extra API action during a show.
                if !mergedProfile.cachedHighlights.isEmpty { highlightsLoadedOnce = true }
                        ProfileCacheService.shared.saveProfile(mergedProfile)
                // Migrate the locally-captured pending pic to the new CDN URL key
                // BEFORE clearing it. Instagram may return a different CDN URL on
                // each profile refresh, so without this the new URL would momentarily
                // have no image → brief flash/spinner between pendingProfilePic=nil
                // and the async download completing.
                if let pendingPic = ProfileCacheService.shared.pendingProfilePic,
                   !mergedProfile.profilePicURL.isEmpty {
                    cachedImages[mergedProfile.profilePicURL] = pendingPic
                    ProfileCacheService.shared.saveImage(pendingPic, forURL: mergedProfile.profilePicURL)
                    print("⚡️ [PERF] Pending profile pic migrated to new CDN URL — no flash on transition")
                }
                // New CDN URL is now in fetchedProfile.profilePicURL → pending override no longer needed.
                ProfileCacheService.shared.pendingProfilePic = nil
                        downloadAndCacheImages(profile: mergedProfile)
                // Background preload reels + tagged so they are ready before
                // the user swipes to those tabs. Uses the same fetchReelsIfNeeded /
                // fetchTaggedIfNeeded that tab-swipe uses, so the logic is
                // identical: skip if already cached, respect anti-bot budget.
                // Delay 5s to avoid competing with the posts download burst.
                scheduleBackgroundReelsTaggedPreload(for: mergedProfile)
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
            case .networkError(let message) where message.lowercased().contains("cancelled"):
                print("ℹ️ [PERF] loadProfile cancelled — suppressing connection error alert")
                LogManager.shared.info("loadProfile cancelled; connection alert suppressed", category: .general)
            default:
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ Error loading profile: \(error)")
                    isLoading = false
                guard !isCancellationLike(error) else {
                    print("ℹ️ [PERF] loadProfile task cancelled — alert suppressed")
                    LogManager.shared.info("loadProfile task cancelled; connection alert suppressed", category: .general)
                    return
                }
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

    private func isCancellationLike(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let instagramError = error as? InstagramError,
           case .networkError(let message) = instagramError {
            return message.lowercased().contains("cancelled")
        }
        return error.localizedDescription.lowercased().contains("cancelled")
    }

    @MainActor
    private func noteForbiddenCDNImage(url: String) {
        guard url.contains("fbcdn.net") || url.contains("instagram") else { return }

        let now = Date()
        cdnForbiddenTimestamps = cdnForbiddenTimestamps.filter { now.timeIntervalSince($0) < 20 }
        cdnForbiddenTimestamps.append(now)

        guard cdnForbiddenTimestamps.count >= 8 else { return }
        scheduleCDNURLRefresh(reason: "expired CDN image URLs (\(cdnForbiddenTimestamps.count) HTTP 403s)")
    }

    @MainActor
    private func scheduleCDNURLRefresh(reason: String) {
        guard !cdnRefreshScheduled else { return }
        guard profile != nil else { return }

        cdnRefreshScheduled = true
        print("🔄 [CDN] Scheduling safe URL refresh — \(reason)")
        LogManager.shared.warning("CDN thumbnails expired — scheduling safe profile URL refresh", category: .cache)

        Task { @MainActor in
            defer {
                cdnRefreshScheduled = false
                cdnForbiddenTimestamps.removeAll()
            }

            for attempt in 1...4 {
                guard profile != nil,
                      !instagram.isLocked,
                      !instagram.isSessionChallenged,
                      !instagram.isSessionExpired,
                      !uploadManager.isActive else {
                    print("🔄 [CDN] URL refresh aborted — session/upload guard failed")
                    return
                }

                if InstagramSafetyGate.shared.isInColdStartWindow {
                    let wait = InstagramSafetyGate.shared.coldStartSecondsRemaining + Int.random(in: 5...9)
                    print("⏳ [CDN] URL refresh waiting for cold-start window — \(wait)s")
                    try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                    continue
                }

                let decision = InstagramSafetyGate.shared.decision(for: .silentGridRefresh)
                if !decision.allowed {
                    let wait = max(decision.waitSeconds, 5) + Int.random(in: 2...5)
                    print("⏳ [CDN] URL refresh delayed by safety gate — \(wait)s (\(decision.reason))")
                    try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                    continue
                }

                guard !isLoading, !isPullRefreshInFlight, !isSilentGridRefreshing else {
                    print("⏳ [CDN] URL refresh attempt \(attempt) waiting — another refresh active")
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }

                print("🔄 [CDN] Refreshing profile media URLs after CDN 403 burst")
                await refreshMediaGridSilently()
                return
            }

            print("⚠️ [CDN] URL refresh gave up after repeated safety delays")
            LogManager.shared.warning("CDN URL refresh deferred repeatedly by safety gates", category: .cache)
        }
    }
    
    private func loadCachedImages() {
        guard let profile = profile else { return }
        // Prevent multiple concurrent download storms: if a batch is already
        // in flight, skip — the running batch will cover the same URLs.
        guard !isLoadingImages else {
            print("📦 [CACHE] loadCachedImages skipped — download already in flight")
            return
        }

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

        // ── 2. Skip batch when CDN tokens are already known-expired ──────────
        // If 8+ HTTP 403s were recorded in the last 20s the CDN URLs have
        // rotated — downloading them now would just produce 403s that inflate
        // memory and trigger more OOM pressure.  Wait for the CDN refresh.
        let recentForbidden = cdnForbiddenTimestamps.filter { Date().timeIntervalSince($0) < 20 }.count
        if recentForbidden >= 8 {
            print("📦 [CACHE] Skipping download — CDN URLs known-expired (\(recentForbidden) recent 403s)")
            return
        }

        // ── 3. Download missing images with limited concurrency ───────────────
        // Cap at 4 concurrent tasks to avoid OOM from too many simultaneous
        // URLSession data tasks + UIImage decode operations in memory at once.
        isLoadingImages = true
        Task {
            defer { Task { @MainActor in self.isLoadingImages = false } }
            let concurrencyLimit = 4
            await withTaskGroup(of: (String, UIImage?).self) { group in
                var inFlight = 0
                var iterator = missingURLs.makeIterator()

                // Seed the first batch
                while inFlight < concurrencyLimit, let url = iterator.next() {
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
                            if u == profile.profilePicURL,
                               ProfileCacheService.shared.pendingProfilePic != nil { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.cachedImages[u] = i
                            }
                            ProfileCacheService.shared.saveImage(i, forURL: u)
                        }
                    }
                    // Abort the whole batch early if CDN has gone stale mid-run
                    let forbidden = await MainActor.run {
                        self.cdnForbiddenTimestamps.filter { Date().timeIntervalSince($0) < 20 }.count
                    }
                    guard forbidden < 8 else {
                        print("📦 [CACHE] Aborting download batch — CDN expired mid-run (\(forbidden) 403s)")
                        group.cancelAll()
                        break
                    }
                    // Enqueue next URL as a slot frees up
                    if let url = iterator.next() {
                        let u = url
                        group.addTask { (u, await self.downloadImage(from: u)) }
                        inFlight += 1
                    }
                }
            }
            print("✅ [CACHE] Download batch finished — total \(await MainActor.run { self.cachedImages.count })")
        }
    }
    
    private func downloadAndCacheImages(profile: InstagramProfile) {
        Task {
            // Profile pic — skip if already in memory (bridged from old CDN URL or
            // loaded from disk). The bridge in loadProfile covers CDN-URL-rotation;
            // the download below is only needed when the actual image changed.
            let picAlreadyCached = await MainActor.run { cachedImages[profile.profilePicURL] != nil }
            if picAlreadyCached {
                print("✅ [CACHE] Profile pic already in memory — download skipped")
            } else {
                print("🖼️ [CACHE] Downloading profile pic: \(String(profile.profilePicURL.prefix(80)))...")
                if let image = await downloadImage(from: profile.profilePicURL) {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            cachedImages[profile.profilePicURL] = image
                        }
                        ProfileCacheService.shared.saveImage(image, forURL: profile.profilePicURL)
                        print("✅ [CACHE] Profile pic downloaded and cached")
                    }
                } else {
                    print("❌ [CACHE] Failed to download profile pic")
                }
            }

            // Media thumbnails — skip URLs already in memory to avoid redundant
            // network requests when loadCachedImages already populated the dict.
            let missingMedia = await MainActor.run {
                profile.cachedMediaURLs.filter { cachedImages[$0] == nil }
            }
            if missingMedia.isEmpty {
                print("✅ [CACHE] All \(profile.cachedMediaURLs.count) media thumbnails already in memory — skipped")
            } else {
                print("🖼️ [CACHE] Downloading \(missingMedia.count)/\(profile.cachedMediaURLs.count) media thumbnails…")
                for (index, url) in missingMedia.enumerated() {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                cachedImages[url] = image
                            }
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                        print("✅ [CACHE] Media \(index + 1)/\(missingMedia.count) downloaded")
                    } else {
                        print("❌ [CACHE] Failed to download media \(index + 1)")
                    }
                }
            }

            // Follower profile pics — skip those already cached
            let missingFollower = await MainActor.run {
                profile.followedBy.compactMap { f -> String? in
                    guard let u = f.profilePicURL, !u.isEmpty, cachedImages[u] == nil else { return nil }
                    return u
                }
            }
            print("🖼️ [CACHE] Downloading \(missingFollower.count)/\(profile.followedBy.count) follower profile pics...")
            for picURL in missingFollower {
                if let image = await downloadImage(from: picURL) {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            cachedImages[picURL] = image
                        }
                        ProfileCacheService.shared.saveImage(image, forURL: picURL)
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
                    if httpResponse.statusCode == 403 {
                        await MainActor.run { noteForbiddenCDNImage(url: urlString) }
                    }
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        self.cachedImages[url] = image
                                    }
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
            if isCancellationLike(error) {
                print("ℹ️ [PERF] Silent media refresh cancelled — ignored")
                LogManager.shared.info("Silent refresh cancelled; no connection alert needed", category: .general)
                return
            }
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

        // Optimistic UI: show the chosen gallery image immediately in the fake Instagram
        // profile. This runs BEFORE cold-start/profile-refresh waits. The orange ring and
        // vibration still wait for the real Instagram POST to return OK.
        let picURL = profile?.profilePicURL ?? "autoPic_pending"
        let previousImage = cachedImages[picURL]
        let optimisticImage = UIImage(data: imageData)
        if let optimisticImage {
            cachedImages[picURL] = optimisticImage
            ProfileCacheService.shared.pendingProfilePic = optimisticImage
            print("⚡️ [AUTO PIC] Fake Instagram profile picture updated immediately before safety waits")
        }
        func revertOptimisticProfilePic() {
            if let previousImage {
                cachedImages[picURL] = previousImage
            } else {
                cachedImages.removeValue(forKey: picURL)
            }
            ProfileCacheService.shared.pendingProfilePic = nil
        }

        if isLoading {
            // Profile refresh is running concurrently — wait for it to finish (max 60 s)
            // instead of abandoning the upload entirely.
            print("📷 [AUTO PIC] Profile refresh in progress — waiting up to 60s before upload…")
            LogManager.shared.info("Auto profile pic deferred — waiting for profile refresh", category: .general)
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !isLoading { break }
            }
            guard !isLoading else {
                revertOptimisticProfilePic()
                print("📷 [AUTO PIC] Skipped — profile refresh still active after 60s timeout")
                LogManager.shared.warning("Auto profile pic skipped: profile refresh timed out", category: .general)
                return
            }
            // Re-check safety flags after the wait — state may have changed.
            guard !instagram.isLocked, !instagram.isSessionChallenged else {
                revertOptimisticProfilePic()
                print("📷 [AUTO PIC] Skipped after wait — locked or challenged")
                return
            }
            // Small anti-bot gap after a concurrent refresh.
            try? await Task.sleep(nanoseconds: UInt64.random(in: 2_000_000_000...3_000_000_000))
        }

        // Cold-start guard: defer only the real POST until the window closes so it
        // doesn't stack on top of entry GETs. The fake UI has already been updated.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] Auto profile pic POST deferred — \(remaining)s remaining")
            LogManager.shared.info("[COLD-START] Auto profile pic POST deferred — \(remaining)s", category: .general)
            try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 4...8)) * 1_000_000_000)
        } else {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        guard !instagram.isLocked, !instagram.isSessionChallenged else {
            revertOptimisticProfilePic()
            print("📷 [AUTO PIC] Skipped before POST — locked or challenged after safety wait")
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

                // Keep the successful local image under the current CDN key.
                cachedImages[picURL] = uiImage
                ProfileCacheService.shared.saveImage(uiImage, forURL: picURL)
                // pendingProfilePic keeps the image alive so loadProfile() can migrate it
                // to the new CDN URL when it next runs (no visual glitch at that point).
                profilePicVibratedAlready = true
                ProfileCacheService.shared.pendingProfilePic = uiImage

                // The POST to /accounts/change_profile_picture/ succeeded — the picture IS
                // live on Instagram. Vibrate immediately; do NOT schedule a silent refresh
                // which would cause the post grid to flicker during a performance.
                fireDoubleConfirmationVibration()
                print("📷 [AUTO PIC] ✅ Profile picture updated — shown instantly, vibration fired")
            } else if let previousImage {
                revertOptimisticProfilePic()
                print("📷 [AUTO PIC] Upload returned false — reverted optimistic profile picture")
            } else {
                revertOptimisticProfilePic()
                print("📷 [AUTO PIC] Upload returned false — cleared optimistic profile picture")
            }
        } catch {
            revertOptimisticProfilePic()
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
                            // Not in cache yet — fetch only Date Force counts when possible.
                            if needsAPIDelay {
                                try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_400_000_000))
                            }
                            needsAPIDelay = true
                            if let hint = dateForce.selectedFollowerHints[userId],
                               let p = await instagram.getDateForceProfileCounts(
                                   username: hint.username,
                                   userId: userId,
                                   fullNameHint: hint.fullName,
                                   profilePicURLHint: hint.profilePicURL
                               ) {
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
                            } else if let p = try? await instagram.getProfileInfo(userId: userId) {
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
                        if let p = await instagram.getDateForceProfileCounts(
                            username: follower.username,
                            userId: follower.userId,
                            fullNameHint: follower.fullName,
                            profilePicURLHint: follower.profilePicURL
                        ) {
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

private struct ScreenOffCoverView: View {
    let onTap: () -> Void

    var body: some View {
        Color.black
            .ignoresSafeArea(.all)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}

// MARK: - List Set Input View

struct ListSetInputView: View {
    let set: PhotoSet
    let onSettingsPress: () -> Void
    let onSelect: (String) -> Void
    @State private var listVisible = false

    private var columns: [GridItem] {
        switch set.resolvedListColumns {
        case .automatic:
            return [GridItem(.adaptive(minimum: 150), spacing: 12)]
        case .two:
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        case .three:
            return Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        }
    }

    private var items: [(symbol: String, label: String)] {
        let symbols = set.slotLabels
        let labels = set.listDisplayLabels
        if symbols.isEmpty {
            let fallbackCount = max(labels.count, set.photos.compactMap { Int($0.symbol) }.max() ?? 0, 1)
            return (1...fallbackCount).map { index in
                let label = index <= labels.count ? labels[index - 1] : "Item \(index)"
                return ("\(index)", label)
            }
        }
        return symbols.enumerated().map { index, symbol in
            (symbol, index < labels.count ? labels[index] : "Item \(symbol)")
        }
    }

    private var groups: [[(offset: Int, symbol: String, label: String)]] {
        var result: [[(offset: Int, symbol: String, label: String)]] = []
        var current: [(offset: Int, symbol: String, label: String)] = []
        let separators = Set(set.resolvedListSeparators)

        for (index, item) in items.enumerated() {
            current.append((offset: index, symbol: item.symbol, label: item.label))
            if let slot = Int(item.symbol), separators.contains(slot) {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func buttonColor(at index: Int) -> Color {
        let blue = Color(hex: "0A84FF")
        let green = Color(hex: "30D158")
        let orange = Color(hex: "FF9500")

        switch set.resolvedListColumns {
        case .two:
            return index % 2 == 0 ? blue : green
        case .three:
            switch index % 3 {
            case 0:  return blue
            case 1:  return green
            default: return orange
            }
        case .automatic:
            return Color(hex: "64D2FF")
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if listVisible {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("Tap one item to reveal its linked media.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                                if groupIndex > 0 {
                                    HStack {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.24))
                                            .frame(height: 1)
                                        Text("GROUP \(groupIndex + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.52))
                                        Rectangle()
                                            .fill(Color.white.opacity(0.24))
                                            .frame(height: 1)
                                    }
                                }

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(group, id: \.symbol) { item in
                                        let color = buttonColor(at: item.offset)
                                        Button {
                                            onSelect(item.symbol)
                                        } label: {
                                            Text(item.label)
                                                .font(.system(size: set.resolvedListButtonSize == .large ? 17 : 15, weight: .semibold))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(3)
                                                .minimumScaleFactor(0.7)
                                                .frame(maxWidth: .infinity)
                                                .frame(minHeight: set.resolvedListButtonSize.minHeight)
                                                .padding(.horizontal, 10)
                                                .background(color.opacity(0.30))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(color.opacity(0.78), lineWidth: 1)
                                                )
                                                .cornerRadius(14)
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Rectangle())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                    }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if listVisible {
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSettingsPress()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 54, height: 54)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")

                        Spacer()
                    }
                    .padding(.leading, 18)
                    .padding(.bottom, 22)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !listVisible else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                listVisible = true
            }
                }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Refresh control enabler

/// Invisible UIViewRepresentable placed INSIDE the ScrollView content.
/// Walks UP the UIKit superview chain from inside the UIScrollView's content
/// area to reach the UIScrollView itself, then sets
/// `refreshControl?.isEnabled = isEnabled`.
/// This avoids recreating the view tree (which would reset scroll position).
/// Invisible UIViewRepresentable placed INSIDE the ScrollView content.
/// Walks UP the UIKit superview chain to reach the UIScrollView, then sets
/// both `isEnabled` and `isHidden` on its `refreshControl` so the spinner
/// never appears when refresh is on cooldown.
private struct RefreshControlEnabler: UIViewRepresentable {
    let isEnabled: Bool

    class Coordinator {
        weak var scrollView: UIScrollView?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        // Non-zero size so SwiftUI does NOT optimize the view out of the UIKit tree.
        v.frame                = CGRect(x: 0, y: 0, width: 1, height: 1)
        v.isUserInteractionEnabled = false
        v.backgroundColor      = .clear
        v.alpha                = 0
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        applyEnabled(isEnabled, uiView: uiView, coordinator: context.coordinator)

        // Retry after one layout pass: SwiftUI may add the UIRefreshControl lazily.
        let enabled = isEnabled
        let coordinator = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            applyEnabled(enabled, uiView: uiView, coordinator: coordinator)
        }
    }

    private func applyEnabled(_ enabled: Bool,
                               uiView: UIView,
                               coordinator: Coordinator) {
        func apply(_ scroll: UIScrollView) {
            guard let rc = scroll.refreshControl else { return }
            rc.isEnabled = enabled
            rc.isHidden  = !enabled
        }

        if let cached = coordinator.scrollView {
            apply(cached)
            return
        }

        // Walk up the UIKit superview chain to find the first UIScrollView.
        var current: UIView? = uiView
        for _ in 0..<30 {
            guard let view = current else { break }
            if let scroll = view as? UIScrollView {
                coordinator.scrollView = scroll
                apply(scroll)
                return
            }
            current = view.superview
        }
    }
}

// MARK: - Instagram Profile View

struct InstagramProfileView: View {
    let profile: InstagramProfile
    @Binding var cachedImages: [String: UIImage]
    let onRefresh: () -> Void          // sync — used by header button
    let onAsyncRefresh: () async -> Void  // async — used by pull-to-refresh
    /// When false, the UIRefreshControl is disabled at UIKit level so the pull
    /// gesture produces no spinner.  Changed via RefreshControlEnabler background.
    var isRefreshEnabled: Bool = true
    let onPlusPress: () -> Void
    @Binding var highlightsLoadedOnce: Bool
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
    /// Set by PerformanceView List Set selector; triggers a list slot reveal.
    @Binding var pendingListReveal: Int?
    /// Set by PerformanceView URL-scheme handler; triggers a playing-card reveal.
    @Binding var pendingCardReveal: String?
    /// Set by PerformanceView after the fake lockscreen commits hidden digits.
    @Binding var pendingLockscreenDigits: [Int]?
    /// Called whenever the Posts/Reels/Tagged tab changes so PerformanceView can
    /// trigger lazy loading of secondary tabs on first visit.
    var onTabSelected: ((Int) -> Void)? = nil
    /// Called when a secret input interface (Lockscreen / Number Clock / Card Clock)
    /// captures a value, so PerformanceView can inject it into bio/note {textN} slots
    /// configured for that interface kind and send the note/biography.
    var onInterfaceCapture: ((String, Set<InterfaceKind>) -> Void)? = nil

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

    @discardableResult
    private func captureGridSideEffects(digits: [Int], source: String) -> Bool {
        guard !digits.isEmpty else { return false }

        let capturedNumber = digits.reduce(0) { $0 * 10 + $1 }
        var didCapture = false

        if FollowingMagicSettings.shared.isEnabled {
            FollowingMagicSettings.shared.capture(digits: digits, source: source)
            didCapture = true
        }

        if ForceReelSettings.shared.isEnabled,
           ForceReelSettings.shared.hasReel,
           capturedNumber > 0 {
            ForceReelSettings.shared.pendingPosition = capturedNumber
            print("🎭 [FORCE] Position captured from \(source): \(capturedNumber)")
            didCapture = true
        }

        return didCapture
    }

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

    private var activeDigitGridSet: PhotoSet? {
        if let activeId = ActiveSetSettings.shared.activeSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId }),
           (activeSet.type == .number || activeSet.type == .custom),
           (activeSet.resolvedInputMethod == .digitGrid || ForceNumberRevealSettings.shared.isEnabled) {
            return activeSet
        }

        return nil
    }

    private var isDigitGridInputActive: Bool {
        activeDigitGridSet != nil
    }

    private var shouldCaptureDigitGridCellInput: Bool {
        isDigitGridInputActive
            || followingMagic.isEnabled
            || (ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel)
            || ForceNumberRevealSettings.shared.isEnabled
    }

    private var activeCardClockSet: PhotoSet? {
        guard let activeId = ActiveSetSettings.shared.activeCardSetId,
              let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }),
              activeSet.resolvedInputMethod == .cardClock else {
            return nil
        }
        return activeSet
    }

    private var isCardClockGridInputActive: Bool {
        activeCardClockSet != nil
    }

    private var isSecretGridInputActive: Bool {
        shouldCaptureDigitGridCellInput || isCardClockGridInputActive
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Must be inside the ScrollView content so its UIView is a UIKit
                // descendant of UIScrollView.  1 pt high, alpha 0 — invisible but
                // NOT removed from the hierarchy (zero-size views can be pruned).
                RefreshControlEnabler(isEnabled: isRefreshEnabled)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)

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
        // Pull-to-refresh: always attached so the ScrollView identity is preserved.
        // isEnabled is managed at UIKit level by RefreshControlEnabler above.
            .refreshable {
                await Task { await onAsyncRefresh() }.value
            }
            .background(Color(UIColor.igPageBackground))
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
        // Keep following count display in sync with digit / card buffers
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
        .onChange(of: secretManager.cardSwipeBuffer) { _ in
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
        // ── List Set private selector reveal ────────────────────────────────────
        .onChange(of: pendingListReveal) { slot in
            guard let slot = slot else { return }
            pendingListReveal = nil
            guard let activeId = ActiveSetSettings.shared.activeListSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .list }) else {
                print("⚠️ [LIST-SET] pendingListReveal: no active list set")
                return
            }
            let label = activeSet.listDisplayLabels.indices.contains(slot - 1)
                ? activeSet.listDisplayLabels[slot - 1]
                : "#\(slot)"
            showOCRPeek(label: label)
            Task { await revealByCustomSlot(slot, fromSet: activeSet) }
        }
        // ── URL-scheme: Playing Card reveal ─────────────────────────────────────
        .onChange(of: pendingCardReveal) { symbol in
            guard let symbol = symbol, !symbol.isEmpty else { return }
            pendingCardReveal = nil
            guard SetType.cardSlotLabels.contains(symbol) else {
                print("⚠️ [CARD] pendingCardReveal: '\(symbol)' is not a valid card symbol")
                return
            }
            // Feed the localized card name into any bio/note slot configured for a card
            // interface (Card Clock, Numpad Card, Card Lockscreen, or URL scheme).
            if let comp = cardComponents(fromSymbol: symbol) {
                onInterfaceCapture?(localizedCardName(value: comp.value, suit: comp.suit),
                                    [.cardClock, .cardNumpad, .cardLockscreen])
            }
            // Unarchive the matching slot only when a card set is active.
            guard let activeId = ActiveSetSettings.shared.activeCardSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) else {
                print("ℹ️ [CARD] pendingCardReveal: no active card set — bio/note injection only")
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

        // The fake lockscreen captures digits; whether they mean a CARD or a NUMBER is
        // decided by the single active interface kind (only one can be active at a time).
        let activeKinds = IntegrationsSettings.shared.interfaceKindsInUse()

        // ── Card Lockscreen ─────────────────────────────────────────────────────
        // Digits encode a card (0 + value + suit). Feed the localized card name into any
        // bio/note slot set to Card Lockscreen, and unarchive the active card set's slot.
        if activeKinds.contains(.cardLockscreen), let (value, suit) = decodeCardInput(digits) {
            let symbol = cardSymbol(value: value, suit: suit)
            onInterfaceCapture?(localizedCardName(value: value, suit: suit), [.cardLockscreen])
            if let activeId = ActiveSetSettings.shared.activeCardSetId,
               let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) {
                showOCRPeek(label: symbol)
                Task { await revealByCardSlot(symbol: symbol, fromSet: activeSet) }
            }
            return
        }

        // ── Number Lockscreen / Number Clock ────────────────────────────────────
        // Feed the captured number into any bio/note {textN} configured for Number
        // Lockscreen or Number Clock (both fullscreen digit interfaces funnel through
        // here). Runs independently of the set reveal, so bio/note injection works even
        // with no active set.
        onInterfaceCapture?(input, [.numberLockscreen, .numberClock])

        // Legacy card-code fallback: when no card-lockscreen source is configured but an
        // active card set exists, treat a 0+value+suit code as a card reveal.
        if !activeKinds.contains(.cardLockscreen),
           let activeId = ActiveSetSettings.shared.activeCardSetId,
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
                                        .fill(Color(UIColor.igPageBackground))
                                        .frame(width: picSize + 4, height: picSize + 4)
                                }
                                if let image = cachedImages[profile.profilePicURL] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: picSize, height: picSize)
                                        .clipShape(Circle())
                                        .transition(.opacity)
                                        .onAppear { print("✅ [UI] Profile pic image displayed") }
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: picSize, height: picSize)
                                        .overlay(ProgressView().scaleEffect(0.8))
                                        .transition(.opacity)
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
                    .animation(.easeInOut(duration: 0.25), value: cachedImages[profile.profilePicURL] != nil)
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
                        .foregroundColor(Color(UIColor.label))
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
                        .foregroundColor(Color(UIColor.label))
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
                        .background(Color(UIColor.igButtonFill))
                        .foregroundColor(Color(UIColor.label)).cornerRadius(8)
                }
                        Button(action: {}) {
                    Text("ig.share_profile")
                        .font(.system(size: seAdapt(13, 14), weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: btnH)
                        .background(Color(UIColor.igButtonFill))
                        .foregroundColor(Color(UIColor.label)).cornerRadius(8)
                }
                        Button(action: {}) {
                    IGIcon(asset: "instagram_follow", fallback: "person.badge.plus", size: seAdapt(14, 16))
                        .frame(width: btnH, height: btnH)
                        .background(Color(UIColor.igButtonFill))
                                .cornerRadius(8)
                        }
                    }
                    .responsiveHorizontalPadding()
                    
                    // Only render the highlights row when real highlights exist.
                    // The background fetch still runs, but empty/loading states stay hidden
                    // so profiles without highlights never show gray placeholder circles.
                    if !profile.cachedHighlights.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                    let storySize: CGFloat = seAdapt(56, 64)
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .frame(width: storySize, height: storySize)
                            .overlay(Image(systemName: "plus").foregroundColor(Color(UIColor.label)))
                        Text("ig.new")
                            .font(.system(size: seAdapt(10, 12)))
                            .foregroundColor(Color(UIColor.label))
                    }
                        ForEach(profile.cachedHighlights) { highlight in
                            StoryHighlightCell(highlight: highlight,
                                               image: cachedImages[highlight.coverImageURL])
                                }
                        }
                        .responsiveHorizontalPadding()
                    }
                    .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 12)
    }
                
    @ViewBuilder private var tabBarSection: some View {
                HStack(spacing: 0) {
            TabButton(icon: "square.grid.3x3", activeAsset: "instagram_grid_active", inactiveAsset: "instagram_grid_inactive", isSelected: selectedTab == 0) {
                commitDigitReveal()
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
                    mediaItemsByURL: mediaItemsByURL,
                    onMediaAppear: onMediaAppear,
                    onTapIndex: { index in
                        guard !isSecretGridInputActive else { return }
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
                        guard !isSecretGridInputActive else { return }
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
                        mediaItemsByURL: mediaItemsByURL,
                        onTapIndex: { index in
                            guard !isSecretGridInputActive else { return }
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.7)
                .onEnded { _ in commitDigitReveal() }
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
        }
    }

    // MARK: - Secret number gesture handling

    /// Grid gestures have two independent modes:
    /// - Card Clock captures directions.
    /// - Digit Grid captures the cell where the swipe starts.
    private func handleGridSwipe(_ value: DragGesture.Value) {
        let dx    = value.translation.width
        let dy    = value.translation.height
        let absDx = abs(dx)
        let absDy = abs(dy)
        let minDist: CGFloat = 40
        print("🔢 [GRID SWIPE] digitSet:\(activeDigitGridSet?.name ?? "nil") cardSet:\(activeCardClockSet?.name ?? "nil") captureCell:\(shouldCaptureDigitGridCellInput) followingMagic:\(followingMagic.isEnabled) forceReel:\(ForceReelSettings.shared.isEnabled)/\(ForceReelSettings.shared.hasReel) forceGrid:\(ForceNumberRevealSettings.shared.isEnabled)/\(ForceNumberRevealSettings.shared.gridSwipeEnabled)")

        if let activeSet = activeCardClockSet {
            let dir: SwipeDir
            if absDx >= absDy {
                guard absDx > minDist else { return }
                dir = dx > 0 ? .right : .left
            } else {
                guard absDy > minDist else { return }
                dir = dy > 0 ? .down : .up
            }

            print("🔢 [CARD CLOCK] \(activeSet.name): \(dir)")
            secretManager.addCardSwipe(dir)
            updateFollowingOverride()

            if absDx >= absDy {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = tabAfterSecretSwipe(dx: dx)
                }
            }
            return
        }

        if shouldCaptureDigitGridCellInput {
            let gridWidth = UIScreen.main.bounds.width
            let digit = SecretNumberManager.digit(
                x: value.startLocation.x,
                y: value.startLocation.y,
                gridWidth: gridWidth
            )
            print("🔢 [DIGIT GRID] Cell swipe start x:\(Int(value.startLocation.x)) y:\(Int(value.startLocation.y)) → \(digit)")
            secretManager.addDigit(digit)
            updateFollowingOverride()

            // Horizontal swipes remain visible camouflage: the magician appears
            // to move between Posts/Reels/Tagged while the start cell secretly
            // contributes the digit.
            if absDx >= absDy, absDx > minDist {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = tabAfterSecretSwipe(dx: dx)
                }
            }
            return
        }

        if absDx >= absDy {
            guard absDx > minDist else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tabAfterSecretSwipe(dx: dx)
            }
        }
    }

    private func tabAfterSecretSwipe(dx: CGFloat) -> Int {
        if dx < 0 {
            return selectedTab < 2 ? selectedTab + 1 : 1
        }
        return selectedTab > 0 ? selectedTab - 1 : 1
    }

    /// Commit whatever digits are in the buffer — called by long press on the grid.
    /// Mirrors the reveal logic of the Posts tab button.
    private func commitDigitReveal() {
        guard isDigitGridInputActive || isCardClockGridInputActive else { return }

        // ── Card Clock Input ──────────────────────────────────────────────────
        if let activeId = ActiveSetSettings.shared.activeCardSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }),
           activeSet.resolvedInputMethod == .cardClock,
           let cardSym = secretManager.decodedCard {
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard !UploadManager.shared.isActive else {
                LogManager.shared.warning("Card clock reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            // Feed the captured card into any bio/note {textN} configured for Card Clock.
            if let comp = cardComponents(fromSymbol: cardSym) {
                onInterfaceCapture?(localizedCardName(value: comp.value, suit: comp.suit), [.cardClock])
            }
            showOCRPeek(label: cardSym)
            Task { await revealByCardSlot(symbol: cardSym, fromSet: activeSet) }
            selectedTab = 0
            return
        }

        guard secretManager.hasDigits else { return }

        if let activeSet = activeDigitGridSet, activeSet.type == .number {
            let digits     = secretManager.digitBuffer
            let digitLabel = digits.map(String.init).joined()
            captureGridSideEffects(digits: digits, source: "post-prediction")
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard !UploadManager.shared.isActive else {
                LogManager.shared.warning("Force reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            showOCRPeek(number: digitLabel)
            Task { await revealByDigits(digits, fromSet: activeSet) }

        } else if let activeSet = activeDigitGridSet, activeSet.type == .custom {
            let slot = secretManager.digitBuffer.reduce(0) { $0 * 10 + $1 }
            captureGridSideEffects(digits: secretManager.digitBuffer, source: "post-prediction")
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard !UploadManager.shared.isActive else {
                LogManager.shared.warning("Custom reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            guard slot >= 1 else { return }
            showOCRPeek(label: "#\(slot)")
            Task { await revealByCustomSlot(slot, fromSet: activeSet) }

        } else if let activeId = ActiveSetSettings.shared.activeCardSetId,
                  let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) {
            let digits = secretManager.digitBuffer
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard !UploadManager.shared.isActive else {
                LogManager.shared.warning("Card reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            guard let (value, suit) = decodeCardInput(digits) else {
                LogManager.shared.warning("Card reveal: invalid input \(digits.map(String.init).joined())", category: .general)
                return
            }
            let symbol = cardSymbol(value: value, suit: suit)
            showOCRPeek(label: symbol)
            Task { await revealByCardSlot(symbol: symbol, fromSet: activeSet) }

        } else {
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
        }
    }

    private func updateFollowingOverride() {
        // Card clock input takes priority over digit display
        if let cardText = secretManager.cardDisplayString {
            if followingMagic.targetFollowers {
                followingOverride = nil
                followerOverride  = cardText
            } else {
                followerOverride  = nil
                followingOverride = cardText
            }
            return
        }

        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
            followerOverride  = nil
        } else if followingMagic.targetFollowers {
            followingOverride = nil
            followerOverride = secretManager.followingDisplayString(originalCount: profile.followerCount)
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
        let text = formatMagicCount(startCount, revealingSmallOffset: offset)

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
        let range = max(1, realCount - startCount)
        let stepSize = 1
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
            let text = self.formatMagicCount(displayCurrent, revealingSmallOffset: offset)
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
                print("🎩 [TRANSFER] Inflation complete — back to real: \(self.formatMagicCount(realCount, revealingSmallOffset: offset))")
            }
        }
    }

    /// Formats a count for magic counter display.
    /// Counter Glitch shows full exact counts while the override is active so
    /// small offsets remain visible on 1K+ profiles.
    private func formatMagicCount(_ count: Int, revealingSmallOffset offset: Int? = nil) -> String {
        formatFullCount(count)
    }

    private func formatFullCount(_ count: Int) -> String {
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

    /// Parse a card symbol string (e.g. "A♥", "10♣") back into (value 1-13, suit 1-4).
    private func cardComponents(fromSymbol symbol: String) -> (value: Int, suit: Int)? {
        let suitMap: [Character: Int] = ["♠": 1, "♥": 2, "♣": 3, "♦": 4]
        guard let suitChar = symbol.last, let suit = suitMap[suitChar] else { return nil }
        let valuePart = String(symbol.dropLast())
        let value: Int
        switch valuePart {
        case "A": value = 1
        case "J": value = 11
        case "Q": value = 12
        case "K": value = 13
        default:  value = Int(valuePart) ?? 0
        }
        guard (1...13).contains(value) else { return nil }
        return (value, suit)
    }

    /// Localized human-readable card name for bio/note injection, e.g. "3 of hearts" /
    /// "3 de corazones". Number values stay as digits; face cards use localized words.
    private func localizedCardName(value: Int, suit: Int) -> String {
        let valueName: String
        switch value {
        case 1:  valueName = NSLocalizedString("card.value.ace",   comment: "")
        case 11: valueName = NSLocalizedString("card.value.jack",  comment: "")
        case 12: valueName = NSLocalizedString("card.value.queen", comment: "")
        case 13: valueName = NSLocalizedString("card.value.king",  comment: "")
        default: valueName = String(value)
        }
        let suitKey: String
        switch suit {
        case 1:  suitKey = "card.suit.spades"
        case 2:  suitKey = "card.suit.hearts"
        case 3:  suitKey = "card.suit.clubs"
        default: suitKey = "card.suit.diamonds"
        }
        let suitName = NSLocalizedString(suitKey, comment: "")
        return String(format: NSLocalizedString("card.name.format", comment: ""), valueName, suitName)
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
    /// LTR words are reversed before unarchiving so Instagram's newest-first grid
    /// renders them in normal reading order. RTL alphabets keep their logical order,
    /// so the final grid reads correctly from right to left.
    /// e.g. "hola" → reversed ["a","l","o","h"] → final grid [h,o,l,a]
    ///
    /// Flow:
    ///  Phase 1 — Preparation (sync): find all photos, insert local images instantly into grid.
    ///  Phase 2 — API (async): unarchive each photo on Instagram sequentially.
    ///  Phase 3 — Finish: trigger CDN refresh once, clear override.
    private func revealByLetters(_ word: String, fromSet set: PhotoSet) async {
        let dm          = DataManager.shared
        let instagram   = InstagramService.shared
        let alphabet    = set.selectedAlphabet ?? .latin
        let normalizedWord = word.lowercased()
        let letters: [String] = alphabet.isRightToLeft
            ? normalizedWord.map { String($0) }
            : normalizedWord.reversed().map { String($0) }
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
                Text(username)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if isVerified {
                    InstagramVerifiedBadge(size: 18)
                        .padding(.leading, 1)
                }
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
        .background(Color(UIColor.igPageBackground))
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

private struct InstagramVerifiedBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(red: 0.0, green: 0.58, blue: 0.95))
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.48, weight: .black))
                .foregroundColor(.black.opacity(0.78))
                .offset(y: size * 0.01)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Verified")
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
                .foregroundColor(Color(UIColor.label))
                .monospacedDigit()
            Text(overrideLabel ?? label)
                .font(.system(size: seAdapt(12, 14)))
                .foregroundColor(Color(UIColor.label))
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
                } else if let url = URL(string: highlight.coverImageURL), !highlight.coverImageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(width: innerSize, height: innerSize)
                                .clipShape(Circle())
                        case .failure:
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: innerSize, height: innerSize)
                        default:
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: innerSize, height: innerSize)
                                .overlay(ProgressView().scaleEffect(0.6))
                        }
                    }
                    .frame(width: innerSize, height: innerSize)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: innerSize, height: innerSize)
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
        .overlay(Circle().stroke(Color(UIColor.igPageBackground), lineWidth: 2))
    }

    @ViewBuilder private var textArea: some View {
        if isLoading && visible.isEmpty {
            Text("ig.capturing_followers")
                .font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.isEmpty {
            Text("ig.followed_by")
                .font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count >= 3 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[1].userId, username: visible[1].username) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[2].userId, username: visible[2].username) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize()
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[1].userId, username: visible[1].username) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
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
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[1]) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[2]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visibleFollowers.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).fixedSize().onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[1]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visibleFollowers.count == 1 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
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
        .overlay(Circle().stroke(Color(UIColor.igPageBackground), lineWidth: 2))
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
            .foregroundColor(isSelected ? Color(UIColor.label) : Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(
                    Rectangle()
                    .fill(isSelected ? Color(UIColor.label) : Color.clear)
                        .frame(height: 1),
                    alignment: .bottom
                )
                // Ensure the full 44pt area captures taps, not just the icon bounds.
                // Without this, taps in the empty space below the icon fall through
                // to the first grid cell — on small screens (Mini) this opens post 0.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photos Grid

struct PhotosGridView: View {
    let mediaURLs: [String]
    let cachedImages: [String: UIImage]
    /// Optional: used to detect horizontal-video cells and letterbox them instead of crop.
    var mediaItemsByURL: [String: InstagramMediaItem] = [:]
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
                    .overlay(gridCell(for: url))
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

    /// Builds the thumbnail for a single grid cell.
    /// Horizontal videos are letterboxed (black bars) to match Instagram's behaviour.
    /// Everything else (photos, vertical videos, carousels) is cropped to fill the square.
    @ViewBuilder
    private func gridCell(for url: String) -> some View {
        let item = mediaItemsByURL[url]
        let isHorizontalVideo: Bool = {
            guard let item, item.mediaType == .video else { return false }
            return (item.videoAspectRatio ?? 0) > 1.0
        }()

        if let image = cachedImages[url] {
            if isHorizontalVideo {
                // Letterbox: black background + image scaled to fit (no crop).
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .transition(.opacity)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
                .transition(.opacity)
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
                    .foregroundColor(Color(UIColor.label))
            }

            Text("ig.tagged_empty_title")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(UIColor.label))

            Text("ig.tagged_empty_subtitle")
                .font(.system(size: 15))
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 42)

            Spacer(minLength: 160)
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.igPageBackground))
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
    /// Display order of posts. While the Force Post trick is armed the forced post
    /// is REMOVED from this list (it can never be seen by scrolling). When the
    /// spectator's swipe ends, `insertForced` puts it just below the fold and the
    /// interceptor animates the scroll to show it. nil = original order.
    @State private var displayURLs: [String]? = nil
    /// Triggered after the interceptor inserts the forced post; SwiftUI animates to it.
    @State private var forceScrollTrigger = false

    private var urls: [String] { displayURLs ?? mediaURLs }

    /// A force post exists in the original media list.
    private var forceConfigured: Bool {
        mediaURLs.contains(where: isForcedPostURL)
    }

    private func isForcedPostURL(_ url: String) -> Bool {
        if let mediaId = forcePostMediaId, !mediaId.isEmpty {
            if mediaItemsByURL[url]?.mediaId == mediaId { return true }
            if url.contains(mediaId) { return true }
        }
        if let forcePostURL, url == forcePostURL { return true }
        return false
    }

    /// Inserts the hidden forced post just below the fold (at `slot`, found from real
    /// geometry by the interceptor). The slot is always below the visible viewport, so
    /// the insertion is invisible; the interceptor then animates the scroll to it.
    private func insertForced(at slot: Int) {
        guard let forcedURL = mediaURLs.first(where: isForcedPostURL) else { return }
        var list = urls
        guard !list.contains(where: isForcedPostURL) else { return }
        let target = min(max(slot, 0), list.count)
        list.insert(forcedURL, at: target)
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            displayURLs = list
        }
    }

    private func postID(_ index: Int) -> String { "post_\(index)" }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        // LazyVStack so video cells (AVPlayer-backed) only mount when
                        // they are about to appear on screen. Each cell carries a
                        // per-cell geometry marker so the interceptor can insert the
                        // forced post exactly below the fold.
                        LazyVStack(spacing: 0) {
                            ForEach(urls, id: \.self) { url in
                                PostCardView(
                                    url: url,
                                    item: resolvedItems[url],
                                    cachedImages: cachedImages,
                                    username: username,
                                    profileImage: profileImage,
                                    isForced: isForcedPostURL(url)
                                )
                                Divider().background(Color(UIColor.separator))
                            }
                        }
                    }

                    if forceConfigured {
                        ScrollViewInterceptor(
                            isActive: forceConfigured,
                            totalPostCount: urls.count,
                            insertForced: { slot in insertForced(at: slot) },
                            onInserted: { forceScrollTrigger = true }
                        )
                        .frame(width: 0, height: 0)
                    }
                }
                .onChange(of: forceScrollTrigger) { triggered in
                    guard triggered else { return }
                    forceScrollTrigger = false
                    guard let forcedURL = urls.first(where: isForcedPostURL) else { return }
                    // SwiftUI scrollTo handles coordinates perfectly for any screen/
                    // image size. anchor 0.35 puts the image (which sits below the
                    // ~50pt header) roughly centred in the viewport.
                    withAnimation(.easeOut(duration: 1.1)) {
                        proxy.scrollTo(forcedURL, anchor: UnitPoint(x: 0.5, y: 0.35))
                    }
                }
                .onAppear {
                    resolvedItems = mediaItemsByURL

                    // Hide the forced post from the feed: it must be IMPOSSIBLE to
                    // see it by scrolling. It reappears only when the spectator's
                    // flick commits it (just below the fold, then centered). If the
                    // spectator tapped the forced post itself, keep the list intact.
                    let tappedURL = mediaURLs.indices.contains(initialIndex) ? mediaURLs[initialIndex] : nil
                    if displayURLs == nil,
                       forceConfigured,
                       let tappedURL, !isForcedPostURL(tappedURL) {
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            displayURLs = mediaURLs.filter { !isForcedPostURL($0) }
                        }
                    }

                    // Scroll to the tapped post. IDs are the URL strings themselves.
                    let startURL = tappedURL ?? (urls.indices.contains(initialIndex) ? urls[initialIndex] : nil)
                    if let startURL {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(startURL, anchor: .top)
                        }
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
                            .foregroundColor(Color(UIColor.label))
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
            .background(Color(UIColor.igPageBackground))
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
    var isForced: Bool = false
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
                .background {
                    // Real UIKit marker scoped to the IMAGE → the interceptor settles
                    // the scroll with the image fully visible on any device/size.
                    if isForced { ForcedCardMarker() }
                }

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
                    .foregroundColor(Color(UIColor.tertiaryLabel))
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
            // Inline video playback for feed-style posts/reels.
            // fillMode: false → resizeAspect (no crop, black bars if needed).
            // Aspect ratio drives the container: real w÷h when known, otherwise
            // Instagram's standard 4:5 portrait as fallback.
            let ratio: CGFloat = item.videoAspectRatio ?? (4.0 / 5.0)
            Color.black
                .aspectRatio(ratio, contentMode: .fit)
                .overlay(
                    GridVideoPlayer(
                        videoURL: videoURL,
                        muted: false,
                        fillMode: false,
                        posterImage: cachedImages[url]
                    )
                )
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
                    .foregroundColor(Color(UIColor.label))
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
            .foregroundColor(Color(UIColor.label))
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
            .opacity(configuration.isPressed ? 0.62 : 1.0)
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
    func igGlassPill(isDark: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            // In light mode tint at 0.82 neutralises dark grid photos.
            // In dark mode skip the white tint so the pill stays dark.
            let tint: Color = isDark ? Color.clear : Color.white.opacity(0.82)
            self.glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            let tintOverlay:  Color = isDark ? Color.clear         : Color.white.opacity(0.62)
            let strokeOverlay: Color = isDark ? Color.white.opacity(0.20) : Color.white.opacity(0.90)
            self.background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(tintOverlay))
                    .overlay(Capsule(style: .continuous).strokeBorder(strokeOverlay, lineWidth: 0.7))
                    .shadow(color: .black.opacity(isDark ? 0.4 : 0.08), radius: 20, x: 0, y: 6)
                    .shadow(color: .black.opacity(isDark ? 0.2 : 0.04), radius: 4, x: 0, y: 1)
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

    @Environment(\.colorScheme) private var colorScheme

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
        // Keep the fake bar close to the native tab bar proportions: wide slots,
        // slightly taller capsule, and no pressed-scale shrink.
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
        .frame(height: 54)
        .padding(.vertical, 4)
        .igGlassPill(isDark: colorScheme == .dark)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
            // Dot is anchored relative to the icon, not the full slot
            IGIcon(asset: asset, fallback: fallback, size: 26)
                .overlay(alignment: .bottomTrailing) {
                    if showRedDot {
                        Circle()
                            // Explicit sRGB red so it stays vivid even over dark glass
                            .fill(Color(red: 1.0, green: 0.18, blue: 0.18))
                            .frame(width: 8, height: 8)
                            // White ring separates the dot from any dark background
                            .overlay(Circle().stroke(Color(UIColor.igPageBackground), lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.11 : 0))
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
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
                        .frame(width: 34, height: 34)
                }
                // White gap between ring and photo (Instagram-style)
                Circle()
                    .fill(Color(UIColor.igPageBackground))
                    .frame(width: showRevealRing ? 31 : 30, height: showRevealRing ? 31 : 30)
                // Profile picture
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(showRevealRing ? Color.clear : Color(UIColor.label), lineWidth: 1.5)
                    )
            }
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 28))
                .foregroundColor(Color(UIColor.label))
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
                .foregroundColor(Color(UIColor.label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minWidth: 42, maxWidth: 110)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(UIColor.igSecondaryBackground))
                        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 1)
                )
                .zIndex(1)

            // ── Tiny curved tail, overlaps bubble bottom by 2 pt ─────────
            // No stroke — pure white fill seamlessly joins the capsule.
            NotesTailShape()
                .fill(Color(UIColor.igSecondaryBackground))
                .frame(width: tailW, height: tailH)
                .padding(.leading, tailX)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: -2)
                .zIndex(0)

            // ── Small separate dot — mirrors Instagram's speech-bubble ────
            Circle()
                .fill(Color(UIColor.igSecondaryBackground))
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
                Color(UIColor.igPageBackground).ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text("ig.loading_profile")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    )
            } else {
                Color(UIColor.igPageBackground).ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(errorMessage ?? String(localized: "ig.loading_profile"))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button("action.close", action: onClose)
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
            Color(UIColor.igPageBackground).ignoresSafeArea()

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
                            .stroke(Color(UIColor.label), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: loader.warmupSecondsRemaining)

                        Text("\(loader.warmupSecondsRemaining)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(UIColor.label))
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor.label)))
                            .scaleEffect(1.4)
                    }
                }
                .padding(.bottom, 28)

                Text(loader.progressDescription)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(UIColor.label))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut, value: loader.phase)

                if loader.phase == .grid && loader.gridItemsLoaded > 0 {
                    Text(String(format: String(localized: "ig.posts_count"), loader.gridItemsLoaded))
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

