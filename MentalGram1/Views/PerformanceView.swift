import SwiftUI
import Photos
import AVFoundation
import AudioToolbox
import Combine

enum InstagramGridMetrics {
    /// Instagram's modern profile grids use portrait thumbnails rather than
    /// perfect squares. Keep the secret digit-grid hit map in sync with this.
    static let profileCellAspectRatio: CGFloat = 4.0 / 5.0
    static let spacing: CGFloat = 1.0
}

private func safeNumber(fromDigits digits: [Int]) -> Int? {
    var value = 0
    for digit in digits {
        guard (0...9).contains(digit), value <= (Int.max - digit) / 10 else {
            return nil
        }
        value = value * 10 + digit
    }
    return value
}

/// Lowercases only for Latin alphabets; CJK and other scripts keep original form.
private func normalizeWordForReveal(_ word: String, alphabet: AlphabetType) -> String {
    let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        .precomposedStringWithCanonicalMapping
    switch alphabet {
    case .latin, .spanish, .german, .french, .portuguese, .italian, .swedish,
         .polish, .turkish, .icelandic, .vietnamese:
        return trimmed.lowercased()
    default:
        return trimmed
    }
}

private struct AIScreenPostViewerPayload: Identifiable {
    let id = UUID()
    let profile: InstagramProfile
    let mediaItems: [InstagramMediaItem]
    let initialIndex: Int
    let cachedImages: [String: UIImage]
}

struct TranspositionGridEffectPayload {
    let sourceImages: [UIImage]
    let targetImages: [UIImage]
    let matchedItem: InstagramMediaItem
    let duration: TimeInterval
}

struct AIScreenRevealAnimationPayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let style: AIScreenRevealAnimationStyle
}

private enum AIScreenRevealPhase {
    case idle
    case armed
    case matched
}

struct AIScreenRevealAnimationView: View {
    let payload: AIScreenRevealAnimationPayload
    @State private var phase: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            switch payload.style {
            case .energyLines:
                energyLines
            case .signalGhost:
                signalGhost
            case .gridPossession:
                gridPossession
            }
            scanlineVeil
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: payload.style.duration)) { phase = 1 }
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var energyLines: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: payload.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * 0.82)
                    .opacity(0.18 + phase * 0.62)
                    .blur(radius: (1 - phase) * 12)
                    .scaleEffect(0.86 + phase * 0.18)
                    .offset(x: pulse ? 1.5 : -1.5)

                ForEach(0..<32, id: \.self) { i in
                    let y = geo.size.height * CGFloat(i) / 31
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.cyan.opacity(0.1 + phase * 0.45), .white.opacity(0.25), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: i % 5 == 0 ? CGFloat(1.4) : CGFloat(0.65))
                        .offset(
                            x: (phase * geo.size.width * CGFloat(1.4))
                                - geo.size.width * CGFloat(0.75)
                                + CGFloat((i % 4) * 22),
                            y: y
                        )
                        .opacity(Double(phase < CGFloat(0.92) ? CGFloat(1) : CGFloat(1) - (phase - CGFloat(0.92)) * CGFloat(12)))
                }

                Circle()
                    .stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                    .frame(width: geo.size.width * (CGFloat(0.2) + phase * CGFloat(1.15)))
                    .blur(radius: 1.5)
                    .opacity(Double(CGFloat(1) - phase))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var signalGhost: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3, id: \.self) { layer in
                    Image(uiImage: payload.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.62)
                        .clipped()
                        .opacity(layer == 0 ? 0.72 : 0.18)
                        .offset(x: CGFloat(layer - 1) * (pulse ? 10 : -10), y: CGFloat(layer - 1) * 3)
                        .blendMode(layer == 0 ? .normal : (layer == 1 ? .screen : .plusLighter))
                        .saturation(layer == 0 ? 0.7 : 1.8)
                        .contrast(1.1 + phase * 0.45)
                        .blur(radius: layer == 0 ? 0 : 1.6)
                }

                ForEach(0..<14, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.white.opacity(0.38) : Color.cyan.opacity(0.32))
                        .frame(width: geo.size.width, height: CGFloat((i % 3) + 1))
                        .offset(y: -geo.size.height / 2 + CGFloat(i * 58) + phase * 180)
                        .opacity(phase < 0.9 ? 1 : 0)
                }

                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.25 + (pulse ? 0.22 : 0.0)), lineWidth: 1)
                    .frame(width: geo.size.width * 0.76, height: geo.size.height * 0.65)
                    .blur(radius: 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gridPossession: some View {
        GeometryReader { geo in
            let columns = 3
            let rows = 5
            let spacing: CGFloat = 2
            let cellW = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = cellW / InstagramGridMetrics.profileCellAspectRatio
            let startY = (geo.size.height - CGFloat(rows) * cellH - CGFloat(rows - 1) * spacing) / 2
            let order = [0, 4, 2, 6, 8, 1, 3, 5, 7, 10, 9, 11, 12, 13, 14]

            ZStack {
                ForEach(0..<(columns * rows), id: \.self) { index in
                    let col = index % columns
                    let row = index / columns
                    let rank = order.firstIndex(of: index) ?? index
                    let visible = phase > CGFloat(rank) / CGFloat(columns * rows + 2)

                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                        Image(uiImage: payload.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cellW, height: cellH)
                            .clipped()
                            .opacity(visible ? 0.78 : 0)
                            .saturation(1.15)
                            .contrast(1.08)
                        Rectangle()
                            .stroke(visible ? Color.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.7)
                    }
                    .frame(width: cellW, height: cellH)
                    .scaleEffect(visible ? 1 : 0.94)
                    .position(
                        x: CGFloat(col) * (cellW + spacing) + cellW / 2,
                        y: startY + CGFloat(row) * (cellH + spacing) + cellH / 2
                    )
                    .animation(.spring(response: 0.24, dampingFraction: 0.74), value: visible)
                }

                Image(uiImage: payload.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * 0.88)
                    .opacity(max(0, (phase - 0.72) * 3.5))
                    .blur(radius: max(0, 6 - phase * 6))
                    .blendMode(.screen)
            }
        }
    }

    private var scanlineVeil: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<80, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(i % 2 == 0 ? 0.045 : 0.018))
                        .frame(height: 1)
                        .offset(y: CGFloat(i) * geo.size.height / 80)
                }
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.25), Color.black.opacity(0.72)],
                    center: .center,
                    startRadius: 40,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    /// Set by HomeView right before switching to the Performance tab for a "Continue
    /// loading" preload continuation. Suppresses the one-shot secret-input presentation
    /// for that single entry so the magician is never dropped into the fake lockscreen
    /// when they only meant to resume a background download (e.g. in front of a
    /// spectator). Ephemeral on purpose — it resets to false on every app launch, so a
    /// crash mid-flow can never leave a real performance entry without its lockscreen.
    static var suppressSecretInputOnceForPreload = false

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
    @ObservedObject private var instapickSettings = InstapickSettings.shared
    @ObservedObject private var ppTestMode = PostPredictionTestMode.shared
    @StateObject private var ocrCoordinator = OCRCoordinator()
    @State private var isAIScreenDetectionRunning = false
    @State private var aiScreenLastTriggerTime: Date = .distantPast
    @State private var aiScreenPostViewer: AIScreenPostViewerPayload? = nil
    @State private var aiScreenRevealAnimation: AIScreenRevealAnimationPayload? = nil
    @State private var aiScreenRevealPhase: AIScreenRevealPhase = .idle
    @State private var aiScreenPendingViewerPayload: AIScreenPostViewerPayload? = nil
    @State private var aiScreenPendingRevealImage: UIImage? = nil
    @State private var aiScreenFollowingOverride: String? = nil
    @State private var aiScreenFollowingLabelOverride: String? = nil
    @State private var aiScreenProfileNameOverride: String? = nil
    @State private var transpositionGridEffect: TranspositionGridEffectPayload? = nil
    @State private var pendingTranspositionGridEffect: TranspositionGridEffectPayload? = nil
    @State private var transpositionScrollToken = 0
    @State private var transpositionBlackScreenVisible = false
    @State private var transpositionBlackScreenPendingItem: InstagramMediaItem? = nil
    @State private var transpositionErrorHapticsActive = false
    @State private var transpositionOriginalBrightness: CGFloat? = nil
    @State private var transpositionLastProfileFeedback: String = ""
    @State private var transpositionLastProfileFeedbackAt: Date = .distantPast
    @AppStorage("transposition_last_profile_username") private var transpositionLastProfileUsername = ""
    @AppStorage("transposition_cooldown_until") private var transpositionCooldownUntil: Double = 0
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
    @AppStorage("perf_local_bio_override_text") private var persistedLocalBioOverrideText: String = ""
    @AppStorage("perf_local_bio_override_timestamp") private var persistedLocalBioOverrideTimestamp: Double = 0
    @State private var testOriginalNoteText: String? = nil
    @State private var testOriginalNoteTimestamp: Double? = nil
    @State private var testOriginalBiography: String? = nil
    @State private var testOriginalProfilePicImages: [String: UIImage] = [:]
    @State private var testOriginalProfilePicMissingURLs: Set<String> = []
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var cdnForbiddenTimestamps: [Date] = []
    @State private var cdnDownloadBlockedUntil: Date? = nil
    @State private var cdnRefreshScheduled = false
    @State private var lastCDNURLRefreshAttemptAt: Date? = nil
    /// Prevents multiple concurrent loadCachedImages runs from stacking up
    /// and flooding the network with parallel URLSession tasks.
    @State private var isLoadingImages = false
    @State private var showingLockdownSheet = false   // For long-press lockdown details
    @State private var performanceRemoteCallsAllowed = true
    @State private var performanceEntryRecorded = false
    @State private var performanceSessionServicesStarted = false
    @State private var performanceProfileLoadStarted = false
    /// Seconds remaining in the safety-gate pause. Non-zero only when blocked with no cache.
    @State private var safetyGateCountdown: Int = 0
    /// Shown the very first time Performance loads (no cache yet). Stored so it never appears again.
    @AppStorage("perf.hasSeenFirstTimeBanner") private var hasSeenFirstTimeBanner: Bool = false
    @State private var showFirstTimeBanner: Bool = false
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    /// Bound to HomeView's `showLimitsGate`. When true, the Limits & Safety
    /// fullScreenCover is already presenting from HomeView — we must NOT attempt
    /// to present any PerformanceView fullScreenCover simultaneously or iOS will
    /// log "already presenting" and freeze the app.
    @Binding var limitsGateShowing: Bool
    
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
    /// Timestamp of the last loadMoreIfNeeded trigger — debounces rapid-fire
    /// calls that happen when SwiftUI re-renders cells after a grid change.
    @State private var lastLoadMoreTriggeredAt: Date = .distantPast
    private let maxPhotosOwnProfile = 100
    // Lazy-tab loading: track whether each secondary tab has been loaded at least once.
    @State private var reelsLoadedOnce      = false
    @State private var taggedLoadedOnce     = false
    @State private var isLoadingReelsTab    = false
    @State private var isLoadingTaggedTab   = false
    @State private var isLoadingHighlights  = false
    // Highlights: once we know the result (empty or not) we hide the placeholder row.
    @State private var highlightsLoadedOnce = false

    // MARK: - First-time full preload (one-time per account)
    /// True while the blocking "Loading profile…" overlay is shown on the very
    /// first Performance entry for an account, while everything is fetched + saved
    /// to disk. After that, entries are instant with zero API calls.
    @State private var isFirstTimePreloading = false
    /// Set when the preload hit a network error; shows a Retry button.
    @State private var preloadFailed = false
    @State private var firstTimePreloadStartedAt: Date? = nil
    @State private var firstTimeOptionalPreloadTask: Task<Void, Never>? = nil
    @State private var isFirstTimeOptionalPreloadRunning = false
    /// Human-readable progress line shown under the spinner.
    @State private var preloadProgress = ""
    /// How many posts to load on the first-time preload. This may take a bit
    /// longer on a clean install, but it builds the pagination tail so refreshes
    /// cannot collapse the grid back to Instagram's first 12-item page.
    private let preloadTargetPosts = 45
    /// Cancels old post-reveal reconciliation tasks when a new reveal starts or
    /// the app backgrounds. Local paint is already instant; this GET is optional.
    @State private var postRevealGridRefreshGeneration = 0
    @State private var sceneBecameActiveAt = Date()

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
    /// One card reveal per Performance entry. Reset when the user leaves Performance.
    @State private var cardRevealConsumedThisPerformance = false

    // MARK: - List Set input
    @State private var showingListInput = false
    @State private var listInputWasShown = false

    // MARK: - Notes Input (FakeNotes)
    @State private var showingFakeNotes = false
    /// Prevents re-presenting the Notes interface when onAppear re-fires after dismiss.
    @State private var fakeNotesWasShown = false
    /// Lines captured from the Notes interface, routed to Bio/Notes slots or Word set.
    @State private var pendingFakeNotesLines: [String]? = nil

    private var activeListSet: PhotoSet? {
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeListSetId else { return nil }
        return DataManager.shared.sets.first { $0.id == activeId && $0.type == .list }
    }

    private var activePostPredictionInputMethod: InputMethod? {
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeSetId else { return nil }
        return DataManager.shared.sets.first { $0.id == activeId }?.resolvedInputMethod
    }

    init(selectedTab: Binding<Int>, showingExplore: Binding<Bool>, limitsGateShowing: Binding<Bool>) {
        self._selectedTab = selectedTab
        self._showingExplore = showingExplore
        self._limitsGateShowing = limitsGateShowing

        // Paint the cached replica on the very first SwiftUI frame. Previously the
        // view rendered once with profile=nil / urls=0 and then loaded disk cache in
        // onAppear, which looked like a white flash on fast devices even though the
        // cache was complete.
        if let cached = ProfileCacheService.shared.loadProfile() {
            var itemsByURL: [String: InstagramMediaItem] = [:]
            for item in cached.cachedMediaItems + cached.cachedTaggedItems + cached.cachedReelItems {
                itemsByURL[item.imageURL] = item
            }

            var initialImages: [String: UIImage] = [:]
            if let image = ProfileCacheService.shared.pendingProfilePic {
                initialImages[cached.profilePicURL] = image
                ProfileCacheService.shared.saveOwnProfilePic(image, cdnURL: cached.profilePicURL)
            } else if let image = ProfileCacheService.shared.loadOwnProfilePic(forURL: cached.profilePicURL) {
                // URL key OR stable own_profile_pic.jpg (same CDN asset only — token rotation).
                initialImages[cached.profilePicURL] = image
            }
            // Do NOT fall back to Settings reset-photo here: if the user changed their
            // pic in the real Instagram app, last_profile_pic_hash can still match the
            // baseline and we'd paint the wrong face until the next download.

            for url in cached.cachedMediaURLs.prefix(12) {
                if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                    initialImages[url] = image
                    continue
                }
                if let mediaId = itemsByURL[url]?.mediaId,
                   let image = ProfileCacheService.shared.loadImage(forMediaId: mediaId) {
                    initialImages[url] = image
                }
            }

            self._profile = State(initialValue: cached)
            self._allMediaURLs = State(initialValue: cached.cachedMediaURLs)
            self._mediaItemsByURL = State(initialValue: itemsByURL)
            self._nextMaxId = State(initialValue: cached.cachedNextMaxId)
            self._hasMorePages = State(initialValue: cached.cachedNextMaxId != nil && cached.cachedMediaURLs.count < 100)
            self._cachedImages = State(initialValue: initialImages)
        }
    }

    private func resetFullscreenInputPresentationFlags() {
        lockscreenWasShown = false
        clockInputWasShown = false
        cardNumpadWasShown = false
        listInputWasShown = false
        fakeNotesWasShown = false
        showingLockscreen = false
        showingClockInput = false
        showingCardNumpad = false
        showingListInput = false
        showingFakeNotes = false
        cardRevealConsumedThisPerformance = false
    }

    private func resetPerformanceCoverPresentationFlags() {
        performanceCoverWasShown = false
        showingHomeScreenIllusion = false
        showingScreenOffCover = false
    }

    @MainActor
    private func canStartSecretPerformanceInput() -> Bool {
        guard !ppTestMode.isActive else { return true }
        let rate = InstagramService.shared.checkRateLimit()
        guard !rate.limited && rate.remaining > 0 else {
            performanceBudgetAlertMessage = "You have no Instagram action credits left right now. Wait for the hourly budget to recover before starting Performance input."
            showPerformanceBudgetAlert = true
            CrashLoggerService.shared.recordAction("Performance input blocked: no API credits")
            LogManager.shared.warning("Performance input blocked: no API credits (\(rate.actionsUsed)/55)", category: .general)
            return false
        }
        return true
    }

    /// Present whichever secret-input screen (lockscreen, card numpad, clock, list, or
    /// performance cover) is appropriate for the current session.
    ///
    /// This is called both from `onAppear` and from the `onChange(of: limitsGateShowing)`
    /// observer so that inputs are deferred — never shown simultaneously with the
    /// Limits & Safety fullScreenCover that HomeView can present.
    private func presentSecretInputIfNeeded() {
        // Never fight with HomeView's Limits & Safety fullScreenCover.
        guard !limitsGateShowing else {
            print("🎩 [PERF] Secret input deferred — Limits gate is active")
            return
        }

        // "Continue loading" from the red banner switches to the Performance tab purely to
        // resume a background preload. That tab switch fires onAppear → here. Without this
        // guard the magician would be dropped into the fake lockscreen for a maintenance
        // action. Consume the one-shot flag and skip the secret input for this entry only.
        if PerformanceView.suppressSecretInputOnceForPreload {
            PerformanceView.suppressSecretInputOnceForPreload = false
            print("🎩 [PERF] Secret input suppressed — preload-continuation entry")
            return
        }

        let lockscreenActive = isLockscreenActive
        let clockActive      = isClockInputActive
        let cardNumpadActive = isCardNumpadActive
        let listActive       = activeListSet != nil
        let isURLActionPending = !urlAction.pendingMode.isEmpty

        if isURLActionPending {
            print("📲 [URL] Pending action detected — skipping manual Performance input screens")
            LogManager.shared.info("URL action pending: skipped manual Performance input screens", category: .general)
        }
        else if !listInputWasShown && listActive {
            if canStartSecretPerformanceInput() {
                listInputWasShown = true
                showingListInput = true
                print("📋 [LIST-SET] Showing private list selector")
            }
        }
        else if !lockscreenWasShown && lockscreenActive {
            if canStartSecretPerformanceInput() {
                lockscreenWasShown = true
                showingLockscreen = true
                print("🔒 [LOCKSCREEN] Showing fake lockscreen for secret input")
            }
        }
        else if !cardNumpadWasShown && !lockscreenWasShown && cardNumpadActive {
            if canStartSecretPerformanceInput() {
                cardNumpadWasShown = true
                showingCardNumpad = true
                print("🃏 [CARD-NUMPAD] Showing black card selector")
            }
        }
        else if !clockInputWasShown && !lockscreenWasShown && !cardNumpadWasShown && clockActive {
            if canStartSecretPerformanceInput() {
                clockInputWasShown = true
                showingClockInput = true
                print("🖤 [CLOCK-INPUT] Showing black screen for swipe digit input")
            }
        }
        else if !fakeNotesWasShown && isFakeNotesActive {
            if canStartSecretPerformanceInput() {
                fakeNotesWasShown = true
                showingFakeNotes = true
                print("📝 [FAKE-NOTES] Showing Notes lookalike input")
            }
        }
        // Show performance cover if enabled and NO other secret input was already shown.
        else if shouldShowPerformanceCover && !performanceCoverWasShown
                    && !showingLockscreen && !showingClockInput && !showingCardNumpad && !showingListInput
                    && !showingFakeNotes
                    && !lockscreenWasShown && !clockInputWasShown && !cardNumpadWasShown && !listInputWasShown
                    && !fakeNotesWasShown {
            presentPerformanceCoverIfNeeded()
            print("🏠 [ILLUSION] \(effectivePerformanceCoverMode.title) active — tap to reveal profile")
        }
    }

    @MainActor
    private func startPerformanceSessionServicesIfNeeded() {
        guard !performanceSessionServicesStarted else { return }
        performanceSessionServicesStarted = true

        // Live show is active: bot-detection overlays must keep the disguised
        // "No Internet" look while we're here (a spectator must never see a warning).
        instagram.isPerformanceActive = true

        // Performance has priority over setup. Cancel any active/pending upload
        // pipeline before secret inputs run so captured Bio/Notes/PP actions are
        // not blocked by UploadManager.isActive and we avoid POST bursts.
        if uploadManager.isActive || uploadManager.activeTask != nil || uploadManager.isUploading {
            uploadManager.resetAllState()
            didAutoPauseUpload = false
            print("🛑 [PERF] Upload cancelled — entering Performance view")
            LogManager.shared.warning("Upload cancelled: Performance view opened", category: .general)
        }

        // Test Instapick always starts with a clean slot list (no leftover live swaps).
        instapickSettings.preparePerformanceSession()

        // Activate volume button detection for FollowingMagic and/or OCR.
        let hasPlaceholderOCR = integrations.interfaceKindsInUse().contains(.ocr)
        let needsVolume = FollowingMagicSettings.shared.isEnabled
            || (noteFeatureEnabled && noteTopInputMode == "ocr")
            || (bioFeatureEnabled && bioTopInputMode  == "ocr")
            || ppTopInputMode == "ocr"
            || activePostPredictionInputMethod == .ocr
            || hasPlaceholderOCR
            || integrations.aiScreenDetectionEnabled
            || instapickSettings.isReadyForPerformance
        if needsVolume {
            VolumeButtonMonitor.shared.prepareVolume()
            VolumeButtonMonitor.shared.startMonitoring()
        }

        // API polling: watch Inject/Custom API in background.
        startApiPollingIfNeeded()
    }

    @MainActor
    private func startPerformanceProfileLoadIfNeeded() {
        guard !performanceProfileLoadStarted else {
            print("🎩 [PERF] Profile load ignored — already started")
            return
        }
        performanceProfileLoadStarted = true

        if !performanceEntryRecorded {
            let decision = InstagramSafetyGate.shared.recordPerformanceEntry()
            performanceRemoteCallsAllowed = decision.allowRemoteCalls
            performanceEntryRecorded = true
            if !decision.allowRemoteCalls {
                print("🛡️ [PERF] Remote auto-actions blocked — \(decision.reason) (\(decision.waitSeconds)s)")
            }
        }

        guard let cached = ProfileCacheService.shared.loadProfile(),
              ProfileCacheService.shared.isUsableForPerformance(cached, userId: currentSessionUserId()) else {
            print("🚫 [PERF] Entry cancelled — no usable local replica cache")
            LogManager.shared.warning("Performance entry cancelled: no usable local replica cache", category: .general)
            selectedTab = 1
            return
        }

        checkAndLoadProfile(allowRemote: false)
        triggerFirstTimeBannerIfNeeded()
        print("🎩 [PERF] Local replica loaded from cache — no entry GET")
    }

    @MainActor
    private func clearPostPredictionTestModeIfNeeded() {
        guard ppTestMode.isActive || testOriginalNoteText != nil || testOriginalBiography != nil || !testOriginalProfilePicImages.isEmpty || !testOriginalProfilePicMissingURLs.isEmpty else { return }
        let testURLs = ppTestMode.insertedPseudoURLs
        allMediaURLs.removeAll { url in
            url.hasPrefix("reveal://test-") || testURLs.contains(url)
        }
        for url in testURLs {
            cachedImages.removeValue(forKey: url)
            revealDates.removeValue(forKey: url)
        }

        if let originalNote = testOriginalNoteText {
            lastNoteText = originalNote
            lastNoteSentTimestamp = testOriginalNoteTimestamp ?? 0
        }
        if let originalBio = testOriginalBiography {
            applyBiographyToVisibleProfile(originalBio)
            localBioOverride = nil
            persistedLocalBioOverrideText = ""
            persistedLocalBioOverrideTimestamp = 0
            pendingBioText = nil
        }
        for (profilePicURL, originalImage) in testOriginalProfilePicImages {
            cachedImages[profilePicURL] = originalImage
        }
        for profilePicURL in testOriginalProfilePicMissingURLs {
            cachedImages.removeValue(forKey: profilePicURL)
        }

        testOriginalNoteText = nil
        testOriginalNoteTimestamp = nil
        testOriginalBiography = nil
        testOriginalProfilePicImages.removeAll()
        testOriginalProfilePicMissingURLs.removeAll()
        ppTestMode.clearRuntimeState()
        print("🧪 [PP TEST] Cleared temporary test reveal state")
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

    /// True when the Notes Input interface should appear on Performance open.
    private var isFakeNotesActive: Bool {
        integrations.interfaceKindsInUse().contains(.fakeNotes)
    }

    // MARK: - Spectator profile overlay
    @State private var selectedSpectator: InstagramFollower? = nil
    @State private var spectatorProfile: InstagramProfile?  = nil
    @State private var isLoadingSpectator: Bool             = false

    // MARK: - Upload conflict alert (reveal blocked while upload is active)
    @State private var showUploadConflictAlert = false
    @State private var showPerformanceBudgetAlert = false
    @State private var performanceBudgetAlertMessage = ""
    @State private var spectatorLoadError: String? = nil

    // MARK: - Anti-bot: cancel upload before Performance
    // Performance is a live-show surface. Any active upload pipeline is cancelled
    // on entry so Bio/Notes/Post Prediction are never blocked by background uploads.
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
    @State private var lastManualRefreshFailureMessage: String? = nil
    @State private var lastManualRefreshRetrySeconds: Int? = nil
    private let fullRefreshAfterGridRefreshGap: TimeInterval = 90
    /// Controls whether pull-to-refresh is active. Set to false after each refresh
    /// and restored once both local (60 s) and SafetyGate (120 s) cooldowns expire,
    /// so the pull gesture bounces without showing the spinner when blocked.
    @State private var isRefreshEnabled: Bool = true
    @State private var scrollLayoutFixToken = 0

    // MARK: - API Polling (continuous watch mode)
    /// Background task that polls the Inject/Custom API every 4–6 s while the view is visible.
    /// When the spectator's selection arrives, updates bio/note and vibrates — no need to re-open the app.
    @State private var apiPollingTask: Task<Void, Never>? = nil
    /// Last change token received from the API for each target ("bio" / "note" / "pp").
    /// First poll only seeds this baseline; later polls trigger only when the token changes.
    @State private var lastApiPollTokens: [String: String] = [:]
    /// Interface-driven captures can be combined with polled API slots. Keep the
    /// captured slot values long enough for Inject/API to arrive, then compose once.
    @State private var pendingInterfaceTemplateValues: [String: [String: String]] = [:]
    @State private var combinedBioPostPredictionTask: Task<Void, Never>? = nil
    @State private var isCombinedBioPostPredictionGuardActive = false
    @State private var showCombinedProfileNotReadyAlert = false
    @AppStorage("combined_pp_cooldown_bypass_until") private var combinedPPCooldownBypassUntil: Double = 0
    @AppStorage("local_combo_earliest_pp_reveal_at") private var localComboEarliestRevealAt: Double = 0
    @AppStorage("local_combo_bio_pending_until") private var localComboBioPendingUntil: Double = 0
    /// True after Cover Typing biography is confirmed in this Performance session.
    /// Lets Lockscreen PP wait when digits arrive first, then proceed after bio.
    @AppStorage("local_combo_cover_typing_bio_ready") private var coverTypingBioReadyForPP: Bool = false
    /// Seconds to wait after Instagram confirms the biography POST before starting
    /// Post Prediction unarchives. Spectator apps often cache bio longer than the grid,
    /// so a short gap makes posts appear first while bio still looks stale until refresh.
    private let combinedBioPostPredictionDelay: UInt64 = 12

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
            if ppTestMode.isActive {
                testModeFloatingBadge
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
            // First-time blocking preload overlay — covers everything (incl. bottom bar)
            if isFirstTimePreloading {
                firstTimePreloadOverlay
                    .zIndex(2000)
            }
        }
    }

    @MainActor
    private func logPerformanceVisualState(_ reason: String) {
        let visibleURLs = Array(allMediaURLs.prefix(12))
        let missingVisible = visibleURLs.filter { url in
            guard !ProfileMediaReconciler.isOverlayURL(url) else { return false }
            if cachedImages[url] != nil { return false }
            if let mediaId = mediaItemsByURL[url]?.mediaId,
               ProfileCacheService.shared.loadImage(forMediaId: mediaId) != nil { return false }
            return ProfileCacheService.shared.loadImage(forURL: url) == nil
        }.count
        let profilePicCached: Bool = {
            guard let url = profile?.profilePicURL, !url.isEmpty else { return false }
            return cachedImages[url] != nil || ProfileCacheService.shared.loadImage(forURL: url) != nil
        }()
        let whiteSafetyOverlay = !performanceRemoteCallsAllowed && profile == nil && safetyGateCountdown > 0
        let message = "VISUAL \(reason) profile:\(profile != nil) user:\(profile?.username ?? "nil") urls:\(allMediaURLs.count) visibleMissing:\(missingVisible)/\(visibleURLs.count) cachedImages:\(cachedImages.count) picCached:\(profilePicCached) overlays{preload:\(isFirstTimePreloading),safetyWhite:\(whiteSafetyOverlay),firstBanner:\(showFirstTimeBanner),home:\(showingHomeScreenIllusion),screenOff:\(showingScreenOffCover),locked:\(instagram.isLocked)} loading{profile:\(isLoading),images:\(isLoadingImages),silent:\(isSilentGridRefreshing),more:\(isLoadingMore)} selectedTab:\(selectedTab) refreshEnabled:\(isRefreshEnabled)"
        print("🧭 [VISUAL] \(message)")
        LogManager.shared.info(message, category: .general)
    }

    private var testModeFloatingBadge: some View {
        Text("TEST")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.96))
                    .shadow(color: Color.red.opacity(0.35), radius: 8, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .padding(.bottom, 76)
            .allowsHitTesting(false)
    }

    private var firstTimePreloadOverlay: some View {
        ZStack {
            Color(UIColor.igPageBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                if preloadFailed {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.orange)
                    Text(String(localized: "preload.failed.title"))
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(String(localized: "preload.failed.subtitle"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button {
                        let uid = currentSessionUserId()
                        guard !uid.isEmpty else { return }
                        Task { @MainActor in await continueIncompletePerformancePreload(userId: uid) }
                    } label: {
                        Text(String(localized: "preload.retry"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(VaultTheme.Colors.primary)
                            .cornerRadius(10)
                    }
                    .padding(.top, 4)

                    Button {
                        firstTimePreloadStartedAt = nil
                        withAnimation(.easeOut(duration: 0.2)) {
                            isFirstTimePreloading = false
                        }
                        selectedTab = 1
                    } label: {
                        Text("Go to Sets")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Text("Your loaded data is saved. You can continue from the warning banner when the API budget recovers.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 42)
                } else {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text(String(localized: "preload.title"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(preloadProgress.isEmpty ? String(localized: "preload.subtitle") : preloadProgress)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.system(size: 11))
                        Text(String(localized: "preload.wifi"))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 24)
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

        let capturedNumber = safeNumber(fromDigits: digits)
        var didCapture = false

        if FollowingMagicSettings.shared.isEnabled {
            FollowingMagicSettings.shared.capture(digits: digits, source: source)
            didCapture = true
        }

        if ForceReelSettings.shared.isEnabled,
           ForceReelSettings.shared.hasReel {
            if let capturedNumber, capturedNumber > 0 {
                ForceReelSettings.shared.pendingPosition = capturedNumber
                print("🎭 [FORCE] Position captured from \(source): \(capturedNumber)")
                didCapture = true
            } else if capturedNumber == nil {
                LogManager.shared.warning("Grid side effects skipped Force Reel: digit buffer overflow from \(source)", category: .general)
            }
        }

        return didCapture
    }

    private func instagramProfileView(profile: InstagramProfile) -> some View {
        InstagramProfileView(
            profile: profile,
            cachedImages: $cachedImages,
            onRefresh: {
                guard !ppTestMode.isActive else {
                    print("🧪 [TEST MODE] Manual refresh skipped — no Instagram API")
                    return
                }
                loadProfileSync()
            },
            onAsyncRefresh: {
                guard !ppTestMode.isActive else {
                    print("🧪 [TEST MODE] Pull refresh skipped — no Instagram API")
                    return
                }
                await handlePerformancePullToRefresh()
            },
            isRefreshEnabled: isRefreshEnabled && !ppTestMode.isActive,
            scrollLayoutFixToken: scrollLayoutFixToken,
            initialContentLift: (bioFeatureEnabled && bioTopInputMode == "coverTyping") ? 290 : 0,
            onPlusPress: { selectedTab = 1 },
            highlightsLoadedOnce: $highlightsLoadedOnce,
            aiScreenFollowingOverride: aiScreenFollowingOverride,
            aiScreenFollowingLabelOverride: aiScreenFollowingLabelOverride,
            aiScreenProfileNameOverride: aiScreenProfileNameOverride,
            transpositionGridEffect: transpositionGridEffect,
            transpositionScrollToken: transpositionScrollToken,
            mediaURLs: allMediaURLs,
            onMediaAppear: { url in
                guard !ppTestMode.isActive else { return }
                loadMoreIfNeeded(currentURL: url)
            },
            onAutoFollowedByTap: { handleAutoFollowedByTap() },
            onAddLocalImages: { photos in
                batchInsertRevealURLs(photos)
                if ppTestMode.isActive {
                    print("🧪 [PP TEST] \(photos.count) template image(s) inserted into fake grid — no Instagram API")
                } else {
                    print("⚡️ [PERF] \(photos.count) photo(s) pre-inserted instantly as contiguous block — API unarchive in progress")
                }
            },
            onRemoveLocalImages: { mediaIds in
                for mediaId in mediaIds {
                    removeAllGridEntries(mediaId: mediaId)
                }
                persistCurrentRevealState()
                print("↩️ [PERF] Rolled back \(mediaIds.count) local reveal image(s)")
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
                postPredRevealRingActive = true
                // Double full-power vibration (notification-level) — magician confirms photos live on Instagram
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s gap
                    await MainActor.run {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    }
                }
                schedulePostRevealGridRefresh(
                    reason: hasVideoReveal ? "video reveal reconciliation" : "post prediction reconciliation",
                    includesVideo: hasVideoReveal
                )
            },
            onAmnesiaRevealStarted: {
                paintAmnesiaCarouselLocally(revealed: true)
            },
            onAmnesiaRevealFailed: {
                paintAmnesiaCarouselLocally(revealed: false)
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
            cardRevealConsumedThisPerformance: $cardRevealConsumedThisPerformance,
            onTabSelected: { tab in handleTabSelected(tab) },
            onInterfaceCapture: { value, kinds in
                Task { await applyInterfaceCapture(value: value, kinds: kinds) }
            },
            pendingFakeNotesLines: $pendingFakeNotesLines,
            onFakeNotesCapture: { lines in
                Task { await applyFakeNotesCapture(lines: lines) }
            }
        )
    }

    /// Called by InstagramProfileView whenever the Posts/Reels/Tagged tab changes.
    /// Loads reels or tagged content on first tap, without blocking the UI.
    private let secondaryTabVisibleMinimum = 12

    private func handleTabSelected(_ tab: Int) {
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Secondary tab load skipped during Bio + PP queue")
            return
        }
        guard !ppTestMode.isActive else {
            print("🧪 [TEST MODE] Secondary tab remote load skipped")
            return
        }
        guard let profile else { return }
        switch tab {
        case 1:
            let hydratedReels = hydrateCachedImagesForItems(profile.cachedReelItems)
            if hydratedReels > 0 {
                print("🎬 [REELS] Hydrated \(hydratedReels) cached reel thumbnail(s) from disk")
            }
            // Allow re-fetch even if reelsLoadedOnce=true when no images are actually
            // visible — this handles the case where CDN URLs expired so re-download failed.
            // Exception: if a recent fetch confirmed 0 reels (gate active), don't force
            // a re-fetch — there is nothing to show regardless of CDN freshness.
            let hasReelImages = profile.cachedReelURLs.contains { cachedImages[$0] != nil }
            let needsVisibleMinimum = profile.cachedReelURLs.count < secondaryTabVisibleMinimum
            let reelsKnownEmpty = profile.cachedReelURLs.isEmpty && reelsCheckIsFresh(for: profile.userId)
            guard !reelsLoadedOnce || !hasReelImages || needsVisibleMinimum else { return }
            reelsLoadedOnce = true
            Task {
                await fetchReelsIfNeeded(
                    for: profile,
                    forceIfNoImages: !hasReelImages && !reelsKnownEmpty,
                    ensureVisibleMinimum: needsVisibleMinimum
                )
            }
        case 2:
            var hydratedTagged = hydrateCachedImagesForItems(profile.cachedTaggedItems)
            hydratedTagged += hydrateCachedImagesForURLs(profile.cachedTaggedURLs)
            if hydratedTagged > 0 {
                print("🏷️ [TAGGED] Hydrated \(hydratedTagged) cached tagged thumbnail(s) from disk")
            }
            let hasTaggedImages = profile.cachedTaggedURLs.contains { cachedImages[$0] != nil }
            let needsVisibleMinimum = profile.cachedTaggedURLs.count < secondaryTabVisibleMinimum
            let taggedKnownEmpty = profile.cachedTaggedURLs.isEmpty && taggedCheckIsFresh(for: profile.userId)
            guard !taggedLoadedOnce || !hasTaggedImages || needsVisibleMinimum else { return }
            taggedLoadedOnce = true
            Task {
                await fetchTaggedIfNeeded(
                    for: profile,
                    forceIfNoImages: !hasTaggedImages && !taggedKnownEmpty,
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
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Background reels/tagged preload skipped during Bio + PP queue")
            return
        }
        guard !isFirstTimeOptionalPreloadRunning else {
            print("🎬 [BG] Secondary preload skipped — first-time optional preload already running")
            return
        }
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
            guard !isCombinedBioPostPredictionGuardActive else {
                print("🔗 [COMBO] Background preload cancelled during Bio + PP queue")
                return
            }
            guard !instagram.isLocked,
                  !instagram.isSessionChallenged,
                  !instagram.isUploadingProfilePic,
                  instagram.isLoggedIn else {
                print("🚫 [BG] Reels/tagged/highlights preload deferred — locked/challenged/uploading")
                return
            }
            guard let current = profile else { return }
            // Highlights are part of the visible header surface, so warm them
            // before secondary tabs when the cache is incomplete.
            let highlightCoversReady = !current.cachedHighlights.isEmpty
                && cachedHighlightCoversAreReady(current.cachedHighlights)
            if !current.cachedHighlights.isEmpty && !highlightCoversReady {
                print("🌟 [BG] Highlight covers missing — refreshing metadata…")
                await fetchHighlightsIfNeeded(for: current)
            } else if current.cachedHighlights.isEmpty && !highlightsCheckIsFresh(for: current.userId) {
                print("🌟 [BG] Highlights not cached — auto-fetching…")
                await fetchHighlightsIfNeeded(for: current)
            } else if current.cachedHighlights.isEmpty {
                print("🌟 [BG] Highlights checked recently — skipping empty refresh")
                highlightsLoadedOnce = true
            } else {
                print("🌟 [BG] Highlights already cached (\(current.cachedHighlights.count)) — skipping fetch")
                highlightsLoadedOnce = true
            }

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

    private func highlightsCheckIsFresh(for userId: String) -> Bool {
        checkIsFresh(key: "highlights_checked_at_\(userId)")
    }
    private func markHighlightsChecked(for userId: String) {
        markChecked(key: "highlights_checked_at_\(userId)")
    }
    private func reelsCheckIsFresh(for userId: String) -> Bool {
        checkIsFresh(key: "reels_checked_at_\(userId)")
    }
    private func markReelsChecked(for userId: String) {
        markChecked(key: "reels_checked_at_\(userId)")
    }
    private func taggedCheckIsFresh(for userId: String) -> Bool {
        checkIsFresh(key: "tagged_checked_at_\(userId)")
    }
    private func markTaggedChecked(for userId: String) {
        markChecked(key: "tagged_checked_at_\(userId)")
    }
    private func checkIsFresh(key: String, interval: TimeInterval = 12 * 60 * 60) -> Bool {
        let last = UserDefaults.standard.double(forKey: key)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < interval
    }
    private func markChecked(key: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
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
        guard !isLoadingReelsTab else {
            print("🎬 [REELS] Fetch already in progress — skipping duplicate")
            return
        }
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Reels fetch skipped during Bio + PP queue")
            return
        }
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
        let reelsPreloadTarget = 30
        let needsVisibleMinimum = ensureVisibleMinimum && cached.cachedReelURLs.count < reelsPreloadTarget
        // Gate: if a previous fetch confirmed 0 reels, skip for 12h (same pattern as highlights).
        // forceIfNoImages is also gated: if we know reels are empty, fresh CDN URLs won't help.
        let reelsKnownEmpty = cached.cachedReelURLs.isEmpty && reelsCheckIsFresh(for: cached.userId)
        let effectiveForce = forceIfNoImages && !reelsKnownEmpty
        let needsFetch = (cached.cachedReelURLs.isEmpty && !reelsKnownEmpty)
                      || cached.cachedReelItems.isEmpty
                      || looksLikeOldSinglePage
                      || needsVisibleMinimum
                      || effectiveForce
        guard needsFetch else {
            if reelsKnownEmpty {
                print("🎬 [REELS] Confirmed empty < 12h ago — skipping fetch (forceIfNoImages ignored)")
            } else {
                print("🎬 [REELS] Already cached (\(cached.cachedReelURLs.count) URLs, \(cached.cachedReelItems.count) items) — skipping fetch")
            }
            return
        }
        if forceIfNoImages {
            print("🎬 [REELS] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🎬 [REELS] Lazy-loading reels progressively (page by page)…")
        isLoadingReelsTab = true
        defer { isLoadingReelsTab = false }
        do {
            // Random human-like delay before the first API call.
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))

            let reelsPaginationKey = "reels_paginated_\(cached.userId)"
            let maxPages = ensureVisibleMinimum ? 3 : 1
            let targetItems = ensureVisibleMinimum ? reelsPreloadTarget : secondaryTabVisibleMinimum
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
                for item in pageItems where cachedImages[item.imageURL] == nil {
                    if let img = ProfileCacheService.shared.loadImage(forURL: item.imageURL)
                        ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) {
                        cachedImages[item.imageURL] = img
                        ProfileCacheService.shared.saveImage(img, forURL: item.imageURL)
                        ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                    } else if let img = await downloadImageWithRetry(from: item.imageURL, mediaId: item.mediaId, attempts: 3) {
                        cachedImages[item.imageURL] = img
                        ProfileCacheService.shared.saveImage(img, forURL: item.imageURL)
                        ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                    }
                }

                nextCursor = nextId
                page += 1

                // Anti-bot: small pause between pages
                if nextCursor != nil && page < maxPages && allItems.count < targetItems {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...6_000_000_000))
                }
            } while nextCursor != nil && page < maxPages && allItems.count < targetItems

            // Persist final state
            var final = profile ?? cached
            final.cachedReelURLs  = allItems.map { $0.imageURL }
            final.cachedReelItems = allItems
            profile = final
            ProfileCacheService.shared.saveProfile(final)
            UserDefaults.standard.set(true, forKey: reelsPaginationKey)
            // Gate: if confirmed empty, don't retry for 12h
            if allItems.isEmpty { markReelsChecked(for: cached.userId) }
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
        guard !isLoadingTaggedTab else {
            print("🏷️ [TAGGED] Fetch already in progress — skipping duplicate")
            return
        }
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Tagged fetch skipped during Bio + PP queue")
            return
        }
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
        let taggedPreloadTarget = 24
        let needsVisibleMinimum = ensureVisibleMinimum && cached.cachedTaggedURLs.count < taggedPreloadTarget
        let taggedKnownEmpty = cached.cachedTaggedURLs.isEmpty && taggedCheckIsFresh(for: cached.userId)
        let effectiveForceTagged = forceIfNoImages && !taggedKnownEmpty
        guard (cached.cachedTaggedURLs.isEmpty && !taggedKnownEmpty) || taggedLooksOld || needsVisibleMinimum || effectiveForceTagged else {
            if taggedKnownEmpty {
                print("🏷️ [TAGGED] Confirmed empty < 12h ago — skipping fetch (forceIfNoImages ignored)")
            } else {
                print("🏷️ [TAGGED] Already cached (\(cached.cachedTaggedURLs.count)) — skipping fetch")
            }
            return
        }
        if forceIfNoImages {
            print("🏷️ [TAGGED] No visible images — forcing fresh URL fetch (CDN may have expired)")
        }
        print("🏷️ [TAGGED] Lazy-loading tagged for first tab visit…")
        isLoadingTaggedTab = true
        defer { isLoadingTaggedTab = false }
        do {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserTagged(
                userId: cached.userId,
                amount: 50,
                maxPages: ensureVisibleMinimum ? 2 : 1,
                minimumItems: ensureVisibleMinimum ? taggedPreloadTarget : 0
            )
            let taggedURLs = items.map { $0.imageURL }
            var updated = cached
            updated.cachedTaggedURLs = taggedURLs
            updated.cachedTaggedItems = items
            profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            UserDefaults.standard.set(true, forKey: "tagged_paginated_\(cached.userId)")
            // Gate: if confirmed empty, don't retry for 12h
            if items.isEmpty { markTaggedChecked(for: cached.userId) }
            for item in items { mediaItemsByURL[item.imageURL] = item }
            for item in items where cachedImages[item.imageURL] == nil {
                if let img = ProfileCacheService.shared.loadImage(forURL: item.imageURL)
                    ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) {
                    cachedImages[item.imageURL] = img
                    ProfileCacheService.shared.saveImage(img, forURL: item.imageURL)
                    ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                } else if let img = await downloadImageWithRetry(from: item.imageURL, mediaId: item.mediaId, attempts: 3) {
                    cachedImages[item.imageURL] = img
                    ProfileCacheService.shared.saveImage(img, forURL: item.imageURL)
                    ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
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
        guard !isLoadingHighlights else {
            print("🌟 [HIGHLIGHTS] Fetch already in progress — skipping duplicate")
            return
        }
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Highlights fetch skipped during Bio + PP queue")
            return
        }
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
        isLoadingHighlights = true
        defer { isLoadingHighlights = false }
        do {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_800_000_000))
            let items = try await instagram.getUserHighlights(userId: cached.userId)
            if items.isEmpty {
                // Mark as checked even when empty: this account genuinely has no
                // highlights right now. The 12-hour gate in highlightsCheckIsFresh
                // will suppress redundant calls until the next day (or manual refresh).
                markHighlightsChecked(for: cached.userId)
                print("🌟 [HIGHLIGHTS] Fetch returned 0 items — marked as checked for 12h to avoid repeated calls")
                LogManager.shared.warning("Highlights fetch returned 0 items; marked checked for 12h", category: .general)
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

    @MainActor
    private func advanceAIScreenRevealFlow() async {
        if integrations.transpositionRevealMode == .blackScreen,
           transpositionBlackScreenPendingItem != nil {
            print("🤖 [BLACK SCREEN] Post ready — waiting for swipe up")
            return
        }

        if integrations.aiScreenDetectionMode == .visualMatch,
           pendingTranspositionGridEffect != nil {
            triggerPendingVisualTransposition(reason: "volume")
            return
        }

        switch aiScreenRevealPhase {
        case .idle:
            switch integrations.aiScreenDetectionMode {
            case .vision:
                await armAIScreenVisionProfile()
            case .likes:
                await armAIScreenLatestFollower()
            case .visualMatch:
                await runAIScreenVisualMatch()
            }
        case .armed:
            await detectAIScreenLikeIncrease()
        case .matched:
            revealPendingAIScreenPost()
        }
    }

    @MainActor
    private func runAIScreenVisualMatch() async {
        isAIScreenDetectionRunning = true
        defer { isAIScreenDetectionRunning = false }

        do {
            print("🤖 [VISUAL MATCH] Capturing spectator screen")
            let screenPhoto = try await AIScreenCameraCaptureService.shared.capturePhoto(
                zoom: CGFloat(integrations.aiScreenCameraZoom)
            )
            signalTranspositionPhotoCaptured()

            async let authorOCRTask = AIScreenPostDetectionService.shared.extractAuthorOCR(from: screenPhoto)
            let analysis = try await AIScreenPostDetectionService.shared.analyzeScreenPhoto(screenPhoto, allowMissingUsername: true)
            let authorOCR = await authorOCRTask
            // Smart-capture OCR helps caption/post matching only — never author username selection.
            let smartCaptureOCRText = AIScreenCameraCaptureService.shared.lastSmartCaptureOCRText
            let localOCRText = [authorOCR.matchingText, smartCaptureOCRText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")

            print("🤖 [VISUAL MATCH] GPT screen fields username='\(analysis.username)' candidates=\(analysis.usernameCandidates ?? []) likes='\(analysis.visibleLikeText ?? "")' comments='\(analysis.visibleCommentText ?? "")' shares='\(analysis.visibleShareText ?? "")' caption='\(analysis.captionVisible ?? "")' imageText='\(analysis.imageTextVisible ?? "")' postType=\(analysis.postType ?? "") confidence=\(analysis.confidence)")
            LogManager.shared.info(
                "Visual match GPT fields username=\(analysis.username) likes=\(analysis.visibleLikeText ?? "") comments=\(analysis.visibleCommentText ?? "") shares=\(analysis.visibleShareText ?? "") caption=\(analysis.captionVisible ?? "") postType=\(analysis.postType ?? "")",
                category: .general
            )

            var openAIQueries = analysis.profileSearchQueries
                .filter { AIScreenPostDetectionService.shared.isPlausibleAuthorUsername($0) }
            if openAIQueries.isEmpty, let displayFallback = analysis.displayNameSearchQuery,
               AIScreenPostDetectionService.shared.isPlausibleAuthorUsername(displayFallback) {
                openAIQueries = [displayFallback]
            }
            let localAuthorQueries = authorOCR.authorCandidates
            let profileQueries = AIScreenPostDetectionService.shared.rankedAuthorSearchQueries(
                openAI: openAIQueries,
                localTop: localAuthorQueries
            )
            guard !profileQueries.isEmpty else { throw AIScreenDetectionError.noUsername }

            print("🤖 [VISUAL MATCH] Author resolve openAI=\(openAIQueries) localTop=\(localAuthorQueries) ranked=\(profileQueries)")
            LogManager.shared.info(
                "Visual match authors openAI=\(openAIQueries.joined(separator: ", ")) localTop=\(localAuthorQueries.joined(separator: ", ")) ranked=\(profileQueries.joined(separator: ", "))",
                category: .general
            )

            let (selectedProfile, candidates) = try await resolveAIScreenProfileAndCandidates(
                analysis: analysis,
                profileQueries: profileQueries
            )
            guard !isTranspositionDuplicateProfile(selectedProfile.username) else {
                print("🚫 [TRANSPOSITION] Duplicate profile @\(selectedProfile.username) blocked by cooldown")
                LogManager.shared.warning("Transposition duplicate profile blocked: @\(selectedProfile.username)", category: .general)
                showAIScreenErrorFeedback()
                return
            }
            markTranspositionProfileUsed(selectedProfile.username)
            // Feedback only after validated Instagram resolve.
            showAIScreenDetectedProfileFeedback(selectedProfile.username)
            let match: AIScreenResolvedPostMatch
            do {
                match = try await AIScreenPostDetectionService.shared.matchPostHybrid(
                    screenPhoto: screenPhoto,
                    analysis: analysis,
                    candidates: candidates,
                    localOCRText: localOCRText
                )
                if match.isLowConfidence {
                    showAIScreenErrorFeedback()
                }
            } catch {
                print("⚠️ [VISUAL MATCH] Hybrid match failed, using fallback: \(error.localizedDescription)")
                LogManager.shared.warning("Visual match fallback used: \(error.localizedDescription)", category: .general)
                showAIScreenErrorFeedback()
                match = try await makeVisualMatchFallback(from: candidates)
            }
            if integrations.transpositionRevealMode == .blackScreen {
                prepareBlackScreenTranspositionReveal(item: match.candidate.item)
            } else {
                await prepareVisualTranspositionGridEffect(matched: match.candidate, candidates: candidates)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            print("✅ [VISUAL MATCH] Matched @\(selectedProfile.username) mediaId=\(match.candidate.item.mediaId) confidence=\(match.confidence) low=\(match.isLowConfidence) reason=\(match.reason)")
            LogManager.shared.success("Visual match selected @\(selectedProfile.username) mediaId=\(match.candidate.item.mediaId) confidence=\(match.confidence) low=\(match.isLowConfidence)", category: .general)
        } catch {
            print("❌ [VISUAL MATCH] Failed: \(error.localizedDescription)")
            LogManager.shared.error("Visual match failed: \(error.localizedDescription)", category: .general)
            handleTranspositionDetectionError(error)
        }
    }

    private func makeVisualMatchFallback(from candidates: [InstagramMediaItem]) async throws -> AIScreenResolvedPostMatch {
        guard !candidates.isEmpty else { throw AIScreenDetectionError.noCandidates }
        let fallbackIndex = candidates.contains(where: { $0.isPinned == true })
            ? 0
            : min(max(candidates.count / 2, 0), candidates.count - 1)
        let item = candidates[fallbackIndex]
        let image = await downloadImage(from: item.imageURL) ?? UIImage()
        return AIScreenResolvedPostMatch(
            candidate: AIScreenCandidateImage(item: item, image: image),
            confidence: 0,
            reason: "fallback_center_candidate",
            isLowConfidence: true
        )
    }

    private func normalizedTranspositionUsername(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    private func isTranspositionDuplicateProfile(_ username: String) -> Bool {
        let clean = normalizedTranspositionUsername(username)
        guard !clean.isEmpty else { return false }
        guard Date().timeIntervalSince1970 < transpositionCooldownUntil else { return false }
        return clean == normalizedTranspositionUsername(transpositionLastProfileUsername)
    }

    private func markTranspositionProfileUsed(_ username: String) {
        let clean = normalizedTranspositionUsername(username)
        guard !clean.isEmpty else { return }
        transpositionLastProfileUsername = clean
        transpositionCooldownUntil = Date().addingTimeInterval(120).timeIntervalSince1970
    }

    private func transpositionUsernameSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalizedTranspositionUsername(lhs)
        let b = normalizedTranspositionUsername(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.hasPrefix(b) || b.hasPrefix(a) {
            let shorter = Double(min(a.count, b.count))
            let longer = Double(max(a.count, b.count))
            return shorter / longer
        }
        let distance = transpositionLevenshtein(a, b)
        let longer = Double(max(a.count, b.count))
        return max(0, 1 - (Double(distance) / longer))
    }

    private func transpositionLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    @MainActor
    private func handleTranspositionDetectionError(_ error: Error) {
        showAIScreenErrorFeedback()
        startTranspositionErrorHaptics()
        prewarmTranspositionCameraIfNeeded()
    }

    @MainActor
    private func startTranspositionErrorHaptics() {
        guard !transpositionErrorHapticsActive else { return }
        transpositionErrorHapticsActive = true
        pulseTranspositionErrorHaptic()
    }

    @MainActor
    private func stopTranspositionErrorHaptics() {
        transpositionErrorHapticsActive = false
    }

    @MainActor
    private func pulseTranspositionErrorHaptic() {
        guard transpositionErrorHapticsActive else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        AudioServicesPlaySystemSound(1519)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            Task { @MainActor in
                pulseTranspositionErrorHaptic()
            }
        }
    }

    @MainActor
    private func configureTranspositionBlackScreenForEntry() {
        guard integrations.aiScreenDetectionEnabled,
              integrations.aiScreenDetectionMode == .visualMatch,
              integrations.transpositionRevealMode == .blackScreen else {
            resetTranspositionBlackScreen()
            return
        }
        transpositionBlackScreenVisible = true
        transpositionBlackScreenPendingItem = nil
        dimBlackScreenBrightnessIfNeeded()
    }

    @MainActor
    private func resetTranspositionBlackScreen() {
        transpositionBlackScreenVisible = false
        transpositionBlackScreenPendingItem = nil
        restoreTranspositionBrightnessIfNeeded(maximum: false)
    }

    @MainActor
    private func prewarmTranspositionCameraIfNeeded() {
        guard integrations.aiScreenDetectionEnabled else { return }
        guard integrations.aiScreenDetectionMode == .visualMatch
                || integrations.aiScreenDetectionMode == .vision else { return }
        let zoom = CGFloat(integrations.aiScreenCameraZoom)
        Task {
            await AIScreenCameraCaptureService.shared.prewarm(zoom: zoom)
        }
    }

    @MainActor
    private func configureTranspositionVolumeForEntry() {
        guard integrations.aiScreenDetectionEnabled else { return }
        VolumeButtonMonitor.shared.setVolumeToMiddle()
    }

    @MainActor
    private func markTranspositionReadyForReveal() {
        postPredRevealRingActive = true
        VolumeButtonMonitor.shared.setVolumeToMaximum()
        if integrations.transpositionRevealMode == .blackScreen {
            restoreTranspositionBrightnessIfNeeded(maximum: integrations.transpositionDimBlackScreenBrightness)
        }
        if integrations.transpositionRevealMode == .blackScreen,
           integrations.transpositionBlackScreenReadySoundEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                AudioServicesPlaySystemSound(1007)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    private func dimBlackScreenBrightnessIfNeeded() {
        guard integrations.transpositionDimBlackScreenBrightness,
              integrations.transpositionRevealMode == .blackScreen else { return }
        if transpositionOriginalBrightness == nil {
            transpositionOriginalBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = 0.02
    }

    @MainActor
    private func restoreTranspositionBrightnessIfNeeded(maximum: Bool) {
        guard let original = transpositionOriginalBrightness else { return }
        UIScreen.main.brightness = maximum ? 1.0 : original
        transpositionOriginalBrightness = nil
    }

    @MainActor
    private func signalTranspositionPhotoCaptured() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    @MainActor
    private func prepareBlackScreenTranspositionReveal(item: InstagramMediaItem) {
        transpositionBlackScreenPendingItem = item
        markTranspositionReadyForReveal()
        TranspositionHandGestureService.shared.stop()
    }

    @MainActor
    private func revealBlackScreenTranspositionPost() {
        guard let item = transpositionBlackScreenPendingItem else { return }
        transpositionBlackScreenPendingItem = nil
        withAnimation(.easeInOut(duration: 0.32)) {
            transpositionBlackScreenVisible = false
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        openInstagramPost(item)
    }

    @MainActor
    private func prepareVisualTranspositionGridEffect(
        matched: AIScreenCandidateImage,
        candidates: [InstagramMediaItem]
    ) async {
        let sourceImages = currentVisibleGridImages(limit: 12)
        var targetImages: [UIImage] = []
        for item in candidates.prefix(12) {
            if let image = await downloadImage(from: item.imageURL) {
                targetImages.append(image)
            }
        }
        if targetImages.isEmpty {
            targetImages = [matched.image]
        }

        pendingTranspositionGridEffect = TranspositionGridEffectPayload(
            sourceImages: sourceImages,
            targetImages: targetImages,
            matchedItem: matched.item,
            duration: 4.0
        )
        startTranspositionHandDetection()
        markTranspositionReadyForReveal()
    }

    @MainActor
    private func triggerPendingVisualTransposition(reason: String) {
        guard let payload = pendingTranspositionGridEffect else { return }
        pendingTranspositionGridEffect = nil
        TranspositionHandGestureService.shared.stop()
        transpositionGridEffect = payload
        transpositionScrollToken += 1
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let item = payload.matchedItem
        let openDelay = max(0.1, payload.duration - 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            openInstagramPost(item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + payload.duration) {
            transpositionGridEffect = nil
        }
    }

    @MainActor
    private func startTranspositionHandDetection() {
        TranspositionHandGestureService.shared.start {
            Task { @MainActor in
                guard pendingTranspositionGridEffect != nil,
                      integrations.aiScreenDetectionMode == .visualMatch else {
                    print("🖐️ [TRANSPOSITION] Hand ignored — transposition not ready")
                    return
                }
                triggerPendingVisualTransposition(reason: "hand")
            }
        }
    }

    private func currentVisibleGridImages(limit: Int) -> [UIImage] {
        var images: [UIImage] = []
        for url in allMediaURLs.prefix(limit) {
            if let image = cachedImages[url] ?? ProfileCacheService.shared.loadImage(forURL: url) {
                images.append(image)
            }
        }
        return images
    }

    private func openInstagramPost(_ item: InstagramMediaItem) {
        let mediaPk = mediaIdKey(item.mediaId)
        if let appURL = URL(string: "instagram://media?id=\(mediaPk)") {
            UIApplication.shared.open(appURL) { success in
                if !success {
                    openInstagramPostWebFallback(mediaPk: mediaPk)
                }
            }
        } else {
            openInstagramPostWebFallback(mediaPk: mediaPk)
        }
    }

    private func openInstagramPostWebFallback(mediaPk: String) {
        guard let shortcode = shortcode(fromMediaPk: mediaPk),
              let url = URL(string: "https://www.instagram.com/p/\(shortcode)/") else {
            if let fallback = URL(string: "https://www.instagram.com/") {
                UIApplication.shared.open(fallback)
            }
            return
        }
        UIApplication.shared.open(url)
    }

    private func shortcode(fromMediaPk mediaPk: String) -> String? {
        guard var value = UInt64(mediaPk) else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var chars: [Character] = []
        repeat {
            chars.insert(alphabet[Int(value % 64)], at: 0)
            value /= 64
        } while value > 0
        return String(chars)
    }

    @MainActor
    private func armAIScreenVisionProfile() async {
        isAIScreenDetectionRunning = true
        defer { isAIScreenDetectionRunning = false }

        do {
            print("🤖 [AI SCREEN] Capturing spectator profile screen")
            let screenPhoto = try await AIScreenCameraCaptureService.shared.capturePhoto(
                zoom: CGFloat(integrations.aiScreenCameraZoom)
            )
            signalTranspositionPhotoCaptured()

            showAIScreenConfirmation("Foto...")
            showAIScreenConfirmation("AI...")
            let analysis = try await AIScreenPostDetectionService.shared.analyzeScreenPhoto(screenPhoto)
            print("🤖 [AI SCREEN] OpenAI profile queries=\(analysis.profileSearchQueries) confidence=\(analysis.confidence)")
            LogManager.shared.info("AI screen profile queries: \(analysis.profileSearchQueries.joined(separator: ", "))", category: .general)
            if let detected = analysis.profileSearchQueries.first {
                showAIScreenConfirmation("@\(detected)")
                showAIScreenDetectedProfileFeedback(detected)
            }

            showAIScreenConfirmation("IG...")
            let armed: String
            let expectedLikerUsername: String?
            if integrations.aiScreenVerifyLatestFollower {
                guard let spectator = try await InstagramService.shared.getLatestFollower() else {
                    throw AIScreenLikeDetectionError.noLatestFollower
                }
                armed = try await armAIScreenProfileFromQueries(
                    analysis.profileSearchQueries,
                    expectedLiker: spectator
                )
                expectedLikerUsername = spectator.username
            } else {
                armed = try await armAIScreenProfileFromQueries(analysis.profileSearchQueries)
                expectedLikerUsername = nil
            }
            showAIScreenConfirmation("@\(armed)")
            showAIScreenDetectedProfileFeedback(armed)
            aiScreenRevealPhase = .armed
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let expectedLikerUsername {
                print("✅ [AI SCREEN] Armed target @\(armed); expected liker @\(expectedLikerUsername)")
                LogManager.shared.success("AI screen armed target @\(armed), expected liker @\(expectedLikerUsername)", category: .general)
            } else {
                print("✅ [AI SCREEN] Armed target @\(armed); liker verification disabled")
                LogManager.shared.success("AI screen armed target @\(armed), liker verification disabled", category: .general)
            }
        } catch {
            print("❌ [AI SCREEN] Arm failed: \(error.localizedDescription)")
            LogManager.shared.error("AI screen arm failed: \(error.localizedDescription)", category: .general)
            handleTranspositionDetectionError(error)
        }
    }

    private func armAIScreenProfileFromQueries(_ queries: [String], expectedLiker: InstagramFollower) async throws -> String {
        var lastError: Error?
        for query in queries.prefix(6) {
            do {
                return try await AIScreenLikeDetectionService.shared.armTargetUsername(
                    query,
                    expectedLiker: expectedLiker,
                    limit: integrations.aiScreenCandidateLimit
                )
            } catch {
                lastError = error
                print("🤖 [AI SCREEN] Arm query '\(query)' failed: \(error.localizedDescription)")
                if let likeError = error as? AIScreenLikeDetectionError,
                   case .privateProfile = likeError {
                    await MainActor.run { showAIScreenConfirmation("Privado") }
                }
            }
        }
        if let lastError { throw lastError }
        throw AIScreenDetectionError.noUsername
    }

    private func armAIScreenProfileFromQueries(_ queries: [String]) async throws -> String {
        var lastError: Error?
        for query in queries.prefix(6) {
            do {
                return try await AIScreenLikeDetectionService.shared.armUsername(
                    query,
                    limit: integrations.aiScreenCandidateLimit
                )
            } catch {
                lastError = error
                print("🤖 [AI SCREEN] Arm query '\(query)' failed: \(error.localizedDescription)")
                if let likeError = error as? AIScreenLikeDetectionError,
                   case .privateProfile = likeError {
                    await MainActor.run { showAIScreenConfirmation("Privado") }
                }
            }
        }
        if let lastError { throw lastError }
        throw AIScreenDetectionError.noUsername
    }

    @MainActor
    private func armAIScreenLatestFollower() async {
        isAIScreenDetectionRunning = true
        defer { isAIScreenDetectionRunning = false }

        do {
            print("❤️ [LIKE DETECT] Arming latest follower")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let username = try await AIScreenLikeDetectionService.shared.armLatestFollower(
                limit: integrations.aiScreenCandidateLimit
            )
            showAIScreenConfirmation("@\(username)")
            aiScreenRevealPhase = .armed
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            LogManager.shared.success("Like detection armed @\(username)", category: .general)
        } catch {
            print("❌ [LIKE DETECT] Arm failed: \(error.localizedDescription)")
            LogManager.shared.error("Like detection arm failed: \(error.localizedDescription)", category: .general)
            showAIScreenErrorFeedback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func detectAIScreenLikeIncrease() async {
        isAIScreenDetectionRunning = true
        defer { isAIScreenDetectionRunning = false }

        do {
            print("❤️ [LIKE DETECT] Checking armed profile for +1 like")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let result = try await AIScreenLikeDetectionService.shared.detectLikeIncrease(
                limit: integrations.aiScreenCandidateLimit
            )
            let revealImage = await downloadImage(from: result.matchedItem.imageURL)
            let payload = makeAIScreenLikePayload(result, revealImage: revealImage)
            aiScreenPendingViewerPayload = payload
            aiScreenPendingRevealImage = revealImage
            aiScreenRevealPhase = .matched
            showAIScreenConfirmation("OK @\(result.profile.username)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            LogManager.shared.success("Like detection matched @\(result.profile.username) mediaId=\(result.matchedItem.mediaId)", category: .general)
        } catch {
            print("❌ [LIKE DETECT] Match failed: \(error.localizedDescription)")
            LogManager.shared.error("Like detection match failed: \(error.localizedDescription)", category: .general)
            showAIScreenErrorFeedback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func revealPendingAIScreenPost() {
        guard let payload = aiScreenPendingViewerPayload else {
            aiScreenRevealPhase = .idle
            return
        }
        presentAIScreenResult(payload, revealImage: aiScreenPendingRevealImage)
        aiScreenPendingViewerPayload = nil
        aiScreenPendingRevealImage = nil
        aiScreenRevealPhase = .idle
    }

    @MainActor
    private func resetAIScreenRevealFlow() {
        aiScreenRevealPhase = .idle
        aiScreenPendingViewerPayload = nil
        aiScreenPendingRevealImage = nil
        aiScreenFollowingOverride = nil
        aiScreenFollowingLabelOverride = nil
        aiScreenProfileNameOverride = nil
        pendingTranspositionGridEffect = nil
        transpositionGridEffect = nil
        stopTranspositionErrorHaptics()
        resetTranspositionBlackScreen()
        AIScreenCameraCaptureService.shared.stop()
        TranspositionHandGestureService.shared.stop()
    }

    @MainActor
    private func showAIScreenErrorFeedback() {
        withAnimation(.easeInOut(duration: 0.18)) {
            aiScreenFollowingLabelOverride = "ERROR"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if aiScreenFollowingLabelOverride == "ERROR" {
                    aiScreenFollowingLabelOverride = nil
                }
            }
        }
    }

    @MainActor
    private func showAIScreenConfirmation(_ text: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            aiScreenFollowingOverride = text
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if aiScreenFollowingOverride == text {
                    aiScreenFollowingOverride = nil
                }
            }
        }
    }

    @MainActor
    private func showAIScreenDetectedProfileFeedback(_ username: String) {
        let clean = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !clean.isEmpty else { return }
        let text = "@\(clean)"
        if text == transpositionLastProfileFeedback,
           Date().timeIntervalSince(transpositionLastProfileFeedbackAt) < 4.0 {
            return
        }
        transpositionLastProfileFeedback = text
        transpositionLastProfileFeedbackAt = Date()
        withAnimation(.easeInOut(duration: 0.16)) {
            aiScreenProfileNameOverride = text
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.22)) {
                if aiScreenProfileNameOverride == text {
                    aiScreenProfileNameOverride = nil
                }
            }
        }
    }

    private func resolveAIScreenProfileAndCandidates(
        analysis: AIScreenPostAnalysis,
        profileQueries: [String]? = nil
    ) async throws -> (InstagramProfile, [InstagramMediaItem]) {
        var lastError: Error?
        var triedUserIds = Set<String>()
        let queries = (profileQueries ?? analysis.profileSearchQueries)
            .map { normalizedTranspositionUsername($0) }
            .filter { AIScreenPostDetectionService.shared.isPlausibleAuthorUsername($0) }
        guard !queries.isEmpty else { throw AIScreenDetectionError.noUsername }

        for query in queries.prefix(6) {
            do {
                print("🤖 [VISUAL MATCH] Searching Instagram for query='\(query)'")
                let results = try await instagram.searchUsers(query: query)
                print("🤖 [VISUAL MATCH] Search query='\(query)' returned \(results.count) result(s): \(results.prefix(6).map { "@\($0.username)" }.joined(separator: ", "))")
                LogManager.shared.info(
                    "Visual match search '\(query)' returned \(results.count): \(results.prefix(6).map { "@\($0.username)" }.joined(separator: ", "))",
                    category: .general
                )

                let requireExact = query.count < 8
                let accepted = results
                    .map { result -> (result: UserSearchResult, score: Double, exact: Bool)? in
                        let username = normalizedTranspositionUsername(result.username)
                        let exact = username == query
                        let score = transpositionUsernameSimilarity(query, username)
                        if requireExact {
                            guard exact else { return nil }
                        } else {
                            // Long queries may allow one high-similarity fuzzy, never weak fuzzy.
                            guard exact || score >= 0.9 else { return nil }
                        }
                        return (result, score, exact)
                    }
                    .compactMap { $0 }
                    .sorted { lhs, rhs in
                        if lhs.exact != rhs.exact { return lhs.exact && !rhs.exact }
                        return lhs.score > rhs.score
                    }

                if accepted.isEmpty {
                    print("🤖 [VISUAL MATCH] No exact/high-confidence username match for query='\(query)'")
                    continue
                }

                for entry in accepted.prefix(3) {
                    let result = entry.result
                    guard triedUserIds.insert(result.userId).inserted else { continue }
                    guard let profile = try await instagram.getProfileInfo(
                        userId: result.userId,
                        usernameHint: result.username,
                        fullNameHint: result.fullName,
                        profilePicURLHint: result.profilePicURL,
                        isVerifiedHint: result.isVerified
                    ) else {
                        continue
                    }
                    guard !profile.isPrivate || profile.isFollowing else {
                        print("🤖 [AI SCREEN] Skipping @\(profile.username) — private/unavailable")
                        continue
                    }
                    let candidates = try await loadAIScreenCandidates(from: profile)
                    if !candidates.isEmpty {
                        print("🤖 [AI SCREEN] Using @\(profile.username) exact=\(entry.exact) score=\(String(format: "%.2f", entry.score)) with \(candidates.count) candidates")
                        LogManager.shared.info(
                            "Visual match using @\(profile.username) exact=\(entry.exact) score=\(String(format: "%.2f", entry.score)) with \(candidates.count) candidates",
                            category: .general
                        )
                        return (profile, candidates)
                    }
                    print("🤖 [AI SCREEN] @\(profile.username) has no candidate posts, trying next result")
                    LogManager.shared.warning("Visual match @\(profile.username) had no candidate posts", category: .general)
                }
            } catch {
                lastError = error
                print("🤖 [AI SCREEN] Query '\(query)' failed: \(error.localizedDescription)")
                LogManager.shared.warning("Visual match query '\(query)' failed: \(error.localizedDescription)", category: .general)
            }
        }

        if let lastError { throw lastError }
        LogManager.shared.error(
            "Visual match no candidates after queries: \(queries.joined(separator: ", "))",
            category: .general
        )
        throw AIScreenDetectionError.noCandidates
    }

    private func loadAIScreenCandidates(from selectedProfile: InstagramProfile) async throws -> [InstagramMediaItem] {
        // Visual Match: keep first grid page only (12) to limit private-API pagination.
        let isVisualMatch = integrations.aiScreenDetectionMode == .visualMatch
        let limit = isVisualMatch ? 12 : min(max(integrations.aiScreenCandidateLimit, 12), 48)
        var candidates = selectedProfile.cachedMediaItems
        var next = selectedProfile.cachedNextMaxId
        var pages = 0
        let maxPages = isVisualMatch ? 0 : 2

        while candidates.count < limit,
              let cursor = next,
              !cursor.isEmpty,
              pages < maxPages {
            let (items, nextCursor) = try await instagram.getUserMediaItems(
                userId: selectedProfile.userId,
                amount: 18,
                maxId: cursor
            )
            candidates.append(contentsOf: items)
            next = nextCursor
            pages += 1
        }

        var seen = Set<String>()
        let deduped = candidates.filter { item in
            guard !item.imageURL.isEmpty else { return false }
            let key = item.mediaId.isEmpty ? item.imageURL : mediaIdKey(item.mediaId)
            return seen.insert(key).inserted
        }
        // Keep Instagram feed order for Visual Match so grid position matches the profile.
        // (Feed already returns real pins first; forced re-sort scrambled positions before.)
        if isVisualMatch {
            return Array(deduped.prefix(limit))
        }
        return Array(pinnedFirstAIScreenCandidates(deduped).prefix(limit))
    }

    private func pinnedFirstAIScreenCandidates(_ items: [InstagramMediaItem]) -> [InstagramMediaItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let leftPinned = lhs.element.isPinned == true
                let rightPinned = rhs.element.isPinned == true
                if leftPinned != rightPinned {
                    return leftPinned && !rightPinned
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    @MainActor
    private func openAIScreenMatchedPost(
        _ matched: AIScreenCandidateImage,
        in selectedProfile: InstagramProfile,
        candidates: [InstagramMediaItem]
    ) {
        var mediaItems = candidates
        if !mediaItems.contains(where: { mediaIdKey($0.mediaId) == mediaIdKey(matched.item.mediaId) }) {
            mediaItems.insert(matched.item, at: 0)
        }

        let initialIndex = mediaItems.firstIndex {
            mediaIdKey($0.mediaId) == mediaIdKey(matched.item.mediaId)
        } ?? 0

        var imageMap: [String: UIImage] = [:]
        imageMap[matched.item.imageURL] = matched.image
        if let profileImage = cachedImages[selectedProfile.profilePicURL] {
            imageMap[selectedProfile.profilePicURL] = profileImage
        }

        let payload = AIScreenPostViewerPayload(
            profile: selectedProfile,
            mediaItems: mediaItems,
            initialIndex: initialIndex,
            cachedImages: imageMap
        )
        presentAIScreenResult(payload, revealImage: matched.image)
        print("⚡️ [AI SCREEN] Matched post ready at index \(initialIndex)")
    }

    @MainActor
    private func openAIScreenLikeMatchedPost(_ result: AIScreenLikeDetectionResult, revealImage: UIImage?) {
        let payload = makeAIScreenLikePayload(result, revealImage: revealImage)
        presentAIScreenResult(payload, revealImage: revealImage)
        print("⚡️ [LIKE DETECT] Matched post ready at index \(payload.initialIndex)")
    }

    @MainActor
    private func makeAIScreenLikePayload(_ result: AIScreenLikeDetectionResult, revealImage: UIImage?) -> AIScreenPostViewerPayload {
        let initialIndex = result.mediaItems.firstIndex {
            mediaIdKey($0.mediaId) == mediaIdKey(result.matchedItem.mediaId)
        } ?? 0

        var imageMap: [String: UIImage] = [:]
        if let revealImage {
            imageMap[result.matchedItem.imageURL] = revealImage
        }
        if let profileImage = cachedImages[result.profile.profilePicURL] {
            imageMap[result.profile.profilePicURL] = profileImage
        }

        return AIScreenPostViewerPayload(
            profile: result.profile,
            mediaItems: result.mediaItems,
            initialIndex: initialIndex,
            cachedImages: imageMap
        )
    }

    @MainActor
    private func presentAIScreenResult(_ payload: AIScreenPostViewerPayload, revealImage: UIImage?) {
        guard integrations.aiScreenRevealAnimationEnabled,
              let revealImage else {
            aiScreenPostViewer = payload
            return
        }

        let style = integrations.aiScreenRevealAnimationStyle
        aiScreenRevealAnimation = AIScreenRevealAnimationPayload(
            image: revealImage,
            style: style
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + style.duration) {
            aiScreenRevealAnimation = nil
            aiScreenPostViewer = payload
        }
    }

    private var ocrModifiers: some View {
        ZStack {
            performanceRoot
            spectatorOverlay
            // Instapick floating card mounts inside PostScrollView (above the IG chrome),
            // not here — a PerformanceView overlay would cover/replace the feed.
        }
            .onChange(of: volumeMonitor.upCount) { _ in
                handleVolumeUpForOCRAndAIScreen()
            }
            .onChange(of: volumeMonitor.downCount) { _ in
                // Instapick: volume DOWN while on a color page arms the card overlay.
                _ = instapickSettings.tryBeginOverlayFromVolume()
            }
            .onChange(of: ocrCoordinator.recognizedText) { text in
                guard let text = text, !text.isEmpty else { return }
                print("📷 [OCR] Recognized: \"\(text)\"")

                // INTER-REVEAL COOLDOWN (anti-bot): block reveal if the previous one
                // finished less than `interRevealCooldown` seconds ago. This prevents
                // back-to-back unarchive+comment POST pairs that Instagram flags.
                if !ppTestMode.isActive {
                    let timeSinceLastReveal = Date().timeIntervalSince1970 - lastRevealCompletedTimestamp
                    if timeSinceLastReveal < interRevealCooldown {
                        let remaining = Int(interRevealCooldown - timeSinceLastReveal)
                        print("🚫 [OCR] Reveal blocked — inter-reveal cooldown active (\(remaining)s remaining)")
                        LogManager.shared.warning("Reveal blocked: cooldown \(remaining)s remaining (anti-bot)", category: .api)
                        return
                    }
                }

                // Lock OCR for the rest of this Performance session — one reveal per trick.
                ocrUsedInSession = true
                // Execute all active OCR targets sequentially (bio → note → post prediction)
                // to avoid concurrent API calls that could trigger bot detection.
                Task {
                    // Active when legacy OCR mode is set, any slot has .ocr as its
                    // source, or the active PP set uses OCR.
                    let hasBio  = bioFeatureEnabled && (bioTopInputMode  == "ocr" || integrations.ocrSlot(for: "bio")  != nil)
                    let hasNote = noteFeatureEnabled && (noteTopInputMode == "ocr" || integrations.ocrSlot(for: "note") != nil)
                    let hasPost = ppTopInputMode == "ocr" || activePostPredictionInputMethod == .ocr

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

    private func handleVolumeUpForOCRAndAIScreen() {
        if integrations.aiScreenDetectionEnabled {
            if transpositionErrorHapticsActive {
                stopTranspositionErrorHaptics()
                aiScreenLastTriggerTime = .distantPast
            }
            guard !isAIScreenDetectionRunning else {
                print("🤖 [AI SCREEN] Ignored — detection already running")
                return
            }
            guard Date().timeIntervalSince(aiScreenLastTriggerTime) > 2.0 else {
                print("🤖 [AI SCREEN] Ignored — debounce")
                return
            }
            aiScreenLastTriggerTime = Date()
            Task { await advanceAIScreenRevealFlow() }
            return
        }

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
        let noteOcr     = noteFeatureEnabled && (integrations.ocrSlot(for: "note") != nil || noteTopInputMode == "ocr")
        let bioOcr      = bioFeatureEnabled && (integrations.ocrSlot(for: "bio")  != nil || bioTopInputMode  == "ocr")
        let postPredOcr = ppTopInputMode == "ocr" || activePostPredictionInputMethod == .ocr
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

    @ViewBuilder
    private var performanceRootContent: some View {
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
            // NOTE: Performance entry is cache-only. HomeView prepares a local
            // replica before this screen mounts, so secret input never competes with
            // getProfileInfo() and the fake profile can paint immediately.
        }
    }

    private var performanceChromeAndAlerts: some View {
        performanceRootContent
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
            .alert("Profile not ready", isPresented: $showCombinedProfileNotReadyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Bio + Post Prediction needs your Instagram replica to be loaded first. Open Performance once and let it finish loading, then try this combined effect again.")
            }
            .alert("No credits available", isPresented: $showPerformanceBudgetAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(performanceBudgetAlertMessage)
            }
    }

    private var performanceCoversView: some View {
        performanceChromeAndAlerts
            .overlay {
                if let animation = aiScreenRevealAnimation {
                    AIScreenRevealAnimationView(payload: animation)
                        .transition(.opacity)
                        .zIndex(50_000)
                }
            }
            .overlay {
                if transpositionBlackScreenVisible,
                   integrations.aiScreenDetectionEnabled,
                   integrations.transpositionRevealMode == .blackScreen {
                    TranspositionBlackScreenOverlay(
                        isReady: transpositionBlackScreenPendingItem != nil,
                        onSwipeUp: revealBlackScreenTranspositionPost
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(60_000)
                }
            }
            .statusBarHidden(transpositionBlackScreenVisible && integrations.transpositionRevealMode == .blackScreen)
            .persistentSystemOverlays((transpositionBlackScreenVisible && integrations.transpositionRevealMode == .blackScreen) ? .hidden : .automatic)
            // Spectator profile: bound to selectedSpectator to avoid the nil→item race
            // condition that caused stale profiles when tapping a second follower.
            .fullScreenCover(item: $selectedSpectator) { follower in
                SpectatorProfileCover(follower: follower, onClose: {
                    selectedSpectator = nil
                })
            }
            .fullScreenCover(item: $aiScreenPostViewer) { payload in
                let mediaURLs = payload.mediaItems.map { $0.imageURL }
                let itemsByURL = payload.mediaItems.reduce(into: [String: InstagramMediaItem]()) { dict, item in
                    dict[item.imageURL] = item
                }
                PostScrollView(
                    mediaURLs: mediaURLs,
                    mediaItemsByURL: itemsByURL,
                    cachedImages: payload.cachedImages,
                    initialIndex: payload.initialIndex,
                    username: payload.profile.username,
                    profileImage: payload.cachedImages[payload.profile.profilePicURL],
                    userId: payload.profile.userId
                )
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
                        // Only show the cover after a real digit entry, not on cancel/empty dismiss.
                        presentPerformanceCoverIfNeeded()
                    }
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
                        SecretNumberManager.shared.reset()
                        showingClockInput = false
                        // Show the performance cover after a successful clock reveal (tap to dismiss).
                        presentPerformanceCoverIfNeeded()
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
                        // Show the performance cover after the card is selected and the view tapped to dismiss.
                        presentPerformanceCoverIfNeeded()
                    }
                )
            }
            .fullScreenCover(isPresented: $showingFakeNotes) {
                FakeNotesInputView(
                    onCapture: { lines in
                        showingFakeNotes = false
                        pendingFakeNotesLines = lines
                        presentPerformanceCoverIfNeeded()
                    },
                    onCancel: {
                        showingFakeNotes = false
                    }
                )
            }
    }

    private var performanceObservedView: some View {
        performanceCoversView
        // Force standard text size and scale — ignore system Display Zoom and Text Size settings.
        // Instagram's native app uses fixed layouts, not dynamic type, so we match that behavior
        // to prevent the profile view from being cut off on devices with zoomed displays.
            .dynamicTypeSize(.medium)
            .environment(\.sizeCategory, .medium)
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
            handlePendingProfilePicChange(newPic)
        }
        // Instantly reflect a biography update in the fake Instagram profile view.
        // changeBiography() saves to ProfileCacheService on success; we pick it up here.
        .onChange(of: profileCache.cachedProfile?.biography) { newBio in
            handleCachedBiographyChange(newBio)
        }
        // React to local profile cache changes (archive/unarchive, etc.)
        // without making any extra API call.
        .onChange(of: profileCache.cachedProfile?.cachedMediaURLs) { newURLs in
            handleCachedMediaURLsChange(newURLs)
        }
        // Persist reveal:// state whenever the grid changes so it survives app restarts.
        .onChange(of: allMediaURLs) { _ in
            persistCurrentRevealState()
            logPerformanceVisualState("allMediaURLs changed")
        }
        .onChange(of: profile?.userId) { _ in
            logPerformanceVisualState("profile identity changed")
        }
        .onChange(of: cachedImages.count) { _ in
            logPerformanceVisualState("cachedImages count changed")
        }
        .onChange(of: isFirstTimePreloading) { value in
            logPerformanceVisualState("isFirstTimePreloading=\(value)")
        }
        .onChange(of: showingHomeScreenIllusion) { value in
            logPerformanceVisualState("showingHomeScreenIllusion=\(value)")
        }
        .onChange(of: showingScreenOffCover) { value in
            logPerformanceVisualState("showingScreenOffCover=\(value)")
        }
        .onChange(of: showFirstTimeBanner) { value in
            logPerformanceVisualState("showFirstTimeBanner=\(value)")
        }
        .onChange(of: performanceRemoteCallsAllowed) { value in
            logPerformanceVisualState("performanceRemoteCallsAllowed=\(value)")
        }
        .onChange(of: isRefreshEnabled) { value in
            logPerformanceVisualState("isRefreshEnabled=\(value)")
        }
        // When the Limits & Safety gate (owned by HomeView) dismisses, re-run the
        // secret-input presentation that was deferred in onAppear.
        // A short delay lets the fullScreenCover finish its dismiss animation before
        // we ask UIKit to present another one on the same hosting controller.
        .onChange(of: limitsGateShowing) { isShowing in
            guard !isShowing, selectedTab == 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                presentSecretInputIfNeeded()
                startPerformanceSessionServicesIfNeeded()
                startPerformanceProfileLoadIfNeeded()
            }
        }
    }

    var body: some View {
        performanceObservedView
        .onAppear {
            scrollLayoutFixToken += 1
            CrashLoggerService.shared.recordScreen("Performance")
            ppTestMode.restorePendingSessionIfNeeded(availableSets: DataManager.shared.sets)

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
            coverTypingBioReadyForPP = false
            localComboBioPendingUntil = 0
            localComboEarliestRevealAt = 0

            configureTranspositionVolumeForEntry()
            configureTranspositionBlackScreenForEntry()
            prewarmTranspositionCameraIfNeeded()

            // Screen always on — managed globally by MentalGram1App
            // Show fake lockscreen for secret digit entry (one-shot per session).
            // Guard required: onAppear re-fires when fullScreenCover is dismissed,
            // which would instantly re-present the lockscreen in an infinite loop.
            let interfaceKinds   = integrations.interfaceKindsInUse()
            print("🎩 [PERF] onAppear — limitsGate=\(limitsGateShowing) listActive=\(activeListSet != nil) lockscreenActive=\(isLockscreenActive) cardNumpadActive=\(isCardNumpadActive) clockActive=\(isClockInputActive) urlPending=\(!urlAction.pendingMode.isEmpty) interfaceKinds=\(interfaceKinds) listInputWasShown=\(listInputWasShown) lockscreenWasShown=\(lockscreenWasShown) cardNumpadWasShown=\(cardNumpadWasShown) clockInputWasShown=\(clockInputWasShown)")
            logPerformanceVisualState("Performance onAppear")

            // Present the appropriate secret-input or performance cover.
            // Guards internally against limitsGateShowing — if HomeView's Limits &
            // Safety fullScreenCover is active we defer until it dismisses.
            presentSecretInputIfNeeded()

            // Entry is cache-first: opening Performance with a saved profile must cost
            // 0 Instagram calls. When Limits & Safety is still presented, defer all
            // profile loading so no remote work happens behind another fullScreenCover.
            guard !limitsGateShowing else {
                print("🎩 [PERF] Profile load deferred — Limits gate is active")
                return
            }
            startPerformanceSessionServicesIfNeeded()
            startPerformanceProfileLoadIfNeeded()

            // Serialize all auto-actions in a single sequential Task.
            // Running them in parallel creates concurrent API calls from the
            // same session → strong bot signal (especially POST+GET combos).
            Task { @MainActor in
                guard !showingLockscreen, !showingClockInput, !showingCardNumpad,
                      !showingListInput, !showingFakeNotes, !showingHomeScreenIllusion, !showingScreenOffCover else {
                    print("🛡️ [PERF] Auto-actions skipped — fullscreen input active")
                    LogManager.shared.warning("SAFETY BLOCK — Performance auto-actions skipped while fullscreen input is active", category: .general)
                    return
                }
                guard ppTestMode.isActive || !uploadManager.isActive || didAutoPauseUpload else {
                    print("🛡️ [PERF] Auto-actions skipped — upload active/paused")
                    LogManager.shared.warning("SAFETY BLOCK — Performance auto-actions skipped: upload active", category: .general)
                    return
                }
                
                // 1. Auto profile pic — ALWAYS runs when toggle is active (user explicitly enabled it).
                // The function handles its own anti-bot protections (locked, challenged, cooldowns).
                // We do NOT block it with performanceRemoteCallsAllowed because the local UI update
                // should be instant, and the real Instagram POST has its own safety gates inside.
                if autoProfilePicOnPerformance {
                    guard ppTestMode.isActive || (!instagram.isLocked && !instagram.isSessionChallenged) else {
                        print("📷 [AUTO PIC] Skipped — locked or challenged")
                        return
                    }
                    await autoUploadLatestGalleryPhoto()
                }
                
                // 2. Other auto-actions (URL schemes, clipboard) — blocked in cache-only mode.
                // These are more aggressive/bot-like, so we respect the safety gate.
                guard ppTestMode.isActive || performanceRemoteCallsAllowed else {
                    print("🛡️ [PERF] Other auto-actions skipped — cache-only safety entry")
                    LogManager.shared.warning("SAFETY BLOCK — URL/clipboard auto-actions skipped in cache-only mode", category: .general)
                    return
                }
                guard ppTestMode.isActive || !instagram.isSessionExpired else {
                    print("🚫 [PERF] Other auto-actions skipped — session expired")
                    return
                }

                // URL scheme action OR clipboard (API mode is handled only by polling).
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

        }
        .onChange(of: integrations.transpositionRevealMode) { mode in
            guard mode != .blackScreen else { return }
            resetTranspositionBlackScreen()
        }
        .onChange(of: integrations.aiScreenDetectionEnabled) { enabled in
            guard !enabled else { return }
            resetTranspositionBlackScreen()
        }
        .onChange(of: ppTestMode.isEnabled) { enabled in
            // Instapick local carousel follows the app-wide Performance Test Mode.
            if enabled && instapickSettings.isEnabled {
                instapickSettings.preparePerformanceSession()
                paintInstapickCarouselLocally()
            } else if !enabled {
                removeInstapickCarouselLocally()
                if instapickSettings.isLiveReady {
                    paintInstapickCarouselLocally()
                }
            }
        }
        .onChange(of: instapickSettings.isEnabled) { enabled in
            if enabled && (ppTestMode.isActive || instapickSettings.isLiveReady) {
                paintInstapickCarouselLocally()
            } else if !enabled {
                removeInstapickCarouselLocally()
            }
        }
        .onChange(of: instapickSettings.swappedSlots) { _ in
            paintInstapickCarouselLocally()
        }
        .onChange(of: instapickSettings.carouselMediaId) { _ in
            paintInstapickCarouselLocally()
        }
        .onChange(of: scenePhase) { phase in
            // Pause / resume full-profile pre-loader with app lifecycle.
            switch phase {
            case .inactive:
                if fullLoader.isBlockingPerformance { fullLoader.pause() }
            case .background:
                if fullLoader.isBlockingPerformance { fullLoader.pause() }
                cancelCombinedBioPostPredictionQueue(reason: "app backgrounded")
                clearPostPredictionTestModeIfNeeded()
            case .active:
                if fullLoader.isBlockingPerformance { fullLoader.startOrResume() }
                recoverFirstTimePreloadAfterForegroundIfNeeded()
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
                showingListInput = false
                showingLockscreen = false
                showingClockInput = false
                showingCardNumpad = false
                showingFakeNotes = false
                showingHomeScreenIllusion = false
                showingScreenOffCover = false
                print("📲 [URL] In-view action detected — dismissed manual input screens")
                guard let action = urlAction.consume() else { return }
                guard ppTestMode.isActive || !instagram.isSessionExpired else { return }
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
                cachedTaggedItems: current.cachedTaggedItems,
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
            // Don't clobber an authoritative/silent grid swap that's mid-flight: that
            // path already has the freshest data and is repositioning reveal overlays.
            // Letting a parallel progressive notification rewrite allMediaURLs here is a
            // primary cause of the grid flashing.
            guard !isSilentGridRefreshing else {
                print("⚡ [PERF] Progressive media-ready skipped — silent grid refresh in progress")
                return
            }
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

            // ── Preserve only known real pagination tail, deduped by mediaId ─────
            // Never preserve reveal:// here; those overlays are managed by the
            // reveal pipeline and must not be duplicated by progressive profile data.
            for item in mediaItems { mediaItemsByURL[item.imageURL] = item }
            var newMediaIds = Set<String>()
            for item in mediaItems where !item.mediaId.isEmpty {
                newMediaIds.insert(item.mediaId)
                newMediaIds.insert(mediaIdKey(item.mediaId))
            }
            let existingTail = allMediaURLs.filter { url -> Bool in
                guard !ProfileMediaReconciler.isOverlayURL(url) else { return false }
                guard let item = mediaItemsByURL[url] else { return false }
                return !newMediaIds.contains(item.mediaId) && !newMediaIds.contains(mediaIdKey(item.mediaId))
            }
            var finalURLs = deduplicatedGridURLs(mediaURLs + existingTail)

            // ── Preserve unconfirmed reveal:// overlays ─────────────────────────
            // Progressive profile data must NEVER drop the magician's revealed posts.
            // Any reveal:// whose mediaId is not yet present in this fetch is re-inserted
            // at its chronological position so it stays visible until a later refresh
            // brings its real CDN URL. Without this, a progressive repaint makes the
            // revealed posts blink out and back in.
            let revealURLsBefore = allMediaURLs.filter { $0.hasPrefix("reveal://") }
            let pendingReveals = revealURLsBefore.filter { revealURL in
                let mediaId = String(revealURL.dropFirst("reveal://".count))
                if newMediaIds.contains(mediaId) || newMediaIds.contains(mediaIdKey(mediaId)) { return false }
                if finalURLs.contains(revealURL) { return false }
                return true
            }
            if !pendingReveals.isEmpty {
                let pendingRevealDates = revealDates.filter { pendingReveals.contains($0.key) }
                finalURLs = restoredGridURLsByPositioningRevealState(
                    baseURLs: finalURLs,
                    revealURLs: pendingReveals,
                    storedDates: pendingRevealDates
                )
                print("⚡ [PERF] Progressive media-ready preserved \(pendingReveals.count) reveal overlay(s)")
            }

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
                cachedTaggedItems: current.cachedTaggedItems,
                cachedNextMaxId: nextCursor
            )
            profile = updated
            allMediaURLs = finalURLs
            nextMaxId = nextCursor
            hasMorePages = nextCursor != nil && finalURLs.count < maxPhotosOwnProfile
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
                var headerURLs = deduplicatedGridURLs(merged.cachedMediaURLs)
                // Preserve any reveal:// overlays currently on screen so adopting the
                // header snapshot doesn't make revealed posts blink out.
                let revealURLsBefore = allMediaURLs.filter { $0.hasPrefix("reveal://") }
                let pendingReveals = revealURLsBefore.filter { !headerURLs.contains($0) }
                if !pendingReveals.isEmpty {
                    let pendingRevealDates = revealDates.filter { pendingReveals.contains($0.key) }
                    headerURLs = restoredGridURLsByPositioningRevealState(
                        baseURLs: headerURLs,
                        revealURLs: pendingReveals,
                        storedDates: pendingRevealDates
                    )
                }
                allMediaURLs = headerURLs
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
                await refreshMediaGridSilently(reason: "explore reveal reconciliation", amount: 60)
                print("🔄 [PERF] Silent CDN refresh after Explore word reveal")
            }
        }
        // Cover Typing confirmation comes ONLY from pressing Space in Explore.
        // If both Biography and Post Prediction use Cover Typing, sequence is:
        // 1) update biography, 2) wait a short anti-bot gap, 3) reveal posts.
        .onReceive(NotificationCenter.default.publisher(for: .coverTypingWordCommitted)) { note in
            guard let rawWord = note.userInfo?["word"] as? String else { return }
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return }

            let bioActive = ((note.userInfo?["bioActive"] as? Bool) ?? false)
                && bioFeatureEnabled
                && bioTopInputMode == "coverTyping"
            let ppActive = ((note.userInfo?["postPredictionActive"] as? Bool) ?? false)
                || activePostPredictionInputMethod == .coverTyping

            print("⌨️ [COVER] Word committed: '\(word)' bio=\(bioActive) pp=\(ppActive)")
            LogManager.shared.info("Cover Typing committed: '\(word)' bio=\(bioActive) pp=\(ppActive)", category: .general)

            Task { @MainActor in
                if bioActive {
                    await applyCoverTypingToBiography(word: word)
                }

                if bioActive && ppActive {
                    // Same settle window as Local Bio + PP combo: give Instagram time to
                    // push the new biography before unarchives make the grid change.
                    let delaySeconds = combinedBioPostPredictionDelay
                    print("⏳ [COVER] Waiting \(delaySeconds)s between Biography and Post Prediction")
                    try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                }

                if ppActive {
                    // Route through the existing Post Prediction reveal pipeline.
                    // urlRevealActive intentionally bypasses OCR-only gating while still
                    // preserving reveal cooldowns, upload guards and safety checks.
                    ForceNumberRevealSettings.shared.urlRevealActive = true
                    pendingOCRWord = word
                }
            }
        }
        // Refresh triggered from Settings / Set screen via InstagramSyncCard button.
        .onReceive(NotificationCenter.default.publisher(for: .performanceManualRefresh)) { note in
            // Acknowledge immediately so the sync button knows a live listener exists.
            // Without this, if Performance is not mounted the button would time out and
            // nothing would sync. The ACK lets the button fall back to a headless refresh.
            NotificationCenter.default.post(name: .performanceManualRefreshAck, object: nil)
            guard !ppTestMode.isActive else {
                print("🧪 [TEST MODE] External manual refresh skipped — no Instagram API")
                postManualRefreshResult(success: false, message: "Refresh disabled in test mode")
                return
            }
            guard !instagram.isRevealOperationActive else {
                print("🛡️ [PERF] Manual refresh skipped — reveal operation active")
                LogManager.shared.warning("Manual refresh skipped while reveal is active", category: .general)
                postManualRefreshResult(success: false, message: "Reveal in progress")
                return
            }
            guard !isCombinedBioPostPredictionGuardActive else {
                print("🔗 [COMBO] Manual refresh skipped during Bio + PP queue")
                LogManager.shared.warning("Manual refresh skipped during combined Bio + PP queue", category: .general)
                postManualRefreshResult(success: false, message: "Action in progress")
                return
            }
            if uploadManager.activeTask != nil || uploadManager.isUploading || uploadManager.isActive {
                uploadManager.resetAllState()
                print("🛑 [PERF] Upload cancelled — manual Instagram refresh requested")
                LogManager.shared.warning("Upload cancelled before manual Instagram refresh", category: .upload)
            }
            let postPages = (note.userInfo?["postPages"] as? Int).map { max(1, $0) } ?? 1
            let repairMode = (note.userInfo?["repairMode"] as? Bool) ?? false
            print("🔄 [PERF] Manual refresh requested from Settings/Set — starting loadProfileSync (pages=\(postPages), repair=\(repairMode))")
            loadProfileSync(source: "manual_remote", postPages: postPages, repairMode: repairMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .performanceContinuePreload)) { _ in
            // Safety net: if onAppear didn't fire (TabView kept the view alive), make sure
            // the one-shot suppression flag never lingers into a future real entry.
            PerformanceView.suppressSecretInputOnceForPreload = false
            guard !ppTestMode.isActive else { return }
            let userId = currentSessionUserId()
            guard !userId.isEmpty else { return }
            print("📦 [PRELOAD] Continue requested from warning banner")
            Task { @MainActor in await continueIncompletePerformancePreload(userId: userId) }
        }
        .onDisappear {
            // When any fullScreenCover is presented on top of PerformanceView, iOS fires
            // onDisappear on the parent. The modal flags are still true at this point, so
            // we can detect the transient case and skip the flag reset entirely.
            // This prevents the race where showingClockInput/showingLockscreen is set to
            // false mid-presentation, causing the black screen to vanish immediately.
            guard !showingLockscreen, !showingClockInput, !showingCardNumpad,
                  !showingListInput, !showingFakeNotes, !showingHomeScreenIllusion, !showingScreenOffCover else {
                print("🎩 [PERF] Transient onDisappear (modal active) — keeping input flags")
                return
            }
            guard selectedTab != 0 else {
                print("🎩 [PERF] Transient onDisappear while still in Performance — keeping cover/OCR/API active")
                return
            }
            // Reset one-shot flags so they fire again on the next entry into Performance
            resetFullscreenInputPresentationFlags()
            performanceEntryRecorded = false
            performanceSessionServicesStarted = false
            performanceProfileLoadStarted = false

            // Stop volume monitoring and OCR when leaving Performance
            print("🎩 [TRANSFER] PerformanceView.onDisappear — stopping monitoring (transferOffset:\(FollowingMagicSettings.shared.transferOffset))")
            VolumeButtonMonitor.shared.stopMonitoring()
            ocrCoordinator.stop()
            resetAIScreenRevealFlow()
            stopApiPolling()
            cancelCombinedBioPostPredictionQueue(reason: "left Performance")
            clearPostPredictionTestModeIfNeeded()
            instapickSettings.endPerformanceSession()

            // Clear the performance-context pause flag regardless of how we got here.
            uploadManager.isPausedByPerformance = false
            // Left the live show: bot-detection overlays go back to explicit mode.
            instagram.isPerformanceActive = false

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
            if tab == 0 {
                // Entering / selecting the Performance tab → live show is active.
                instagram.isPerformanceActive = true
                if uploadManager.isActive || uploadManager.activeTask != nil || uploadManager.isUploading {
                    uploadManager.resetAllState()
                    didAutoPauseUpload = false
                    print("🛑 [PERF] Upload cancelled — Performance tab selected")
                    LogManager.shared.warning("Upload cancelled: Performance tab selected", category: .general)
                }
                return
            }
            // Any non-Performance tab → live show ended.
            instagram.isPerformanceActive = false
            // TabView can keep PerformanceView alive, so onDisappear is not always
            // enough. Reset the one-shot fullscreen input flags when the user leaves
            // Performance so Card Numpad / Lockscreen / Clock / List show again next time.
            resetFullscreenInputPresentationFlags()
            resetPerformanceCoverPresentationFlags()
            performanceEntryRecorded = false
            performanceSessionServicesStarted = false
            performanceProfileLoadStarted = false
            print("🎩 [TRANSFER] Performance tab changed — stopping monitoring (transferOffset:\(FollowingMagicSettings.shared.transferOffset))")
            VolumeButtonMonitor.shared.stopMonitoring()
            ocrCoordinator.stop()
            resetAIScreenRevealFlow()
            stopApiPolling()
            cancelCombinedBioPostPredictionQueue(reason: "Performance tab changed")
            clearPostPredictionTestModeIfNeeded()
            instapickSettings.endPerformanceSession()
            uploadManager.isPausedByPerformance = false
            if didAutoPauseUpload && uploadManager.isPaused {
                uploadManager.autoResumePending = true
                print("▶️ [PERF] Leaving Performance — signalling upload to auto-resume")
                LogManager.shared.info("Upload auto-resume pending: leaving Performance view", category: .general)
            }
            didAutoPauseUpload = false
        }
    }

    private func handlePendingProfilePicChange(_ newPic: UIImage?) {
        if let pic = newPic {
            guard let url = profile?.profilePicURL, !url.isEmpty else { return }
            cachedImages[url] = pic
            ProfileCacheService.shared.saveImage(pic, forURL: url)
            ProfileCacheService.shared.saveOwnProfilePic(pic, cdnURL: url)
            print("⚡️ [PERF] Profile pic updated instantly from local image (no CDN GET needed)")
            LogManager.shared.info("Profile pic shown instantly from local storage", category: .general)
        } else {
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

    private func handleCachedBiographyChange(_ newBio: String?) {
        guard let newBio else { return }
        if isLoading && pendingBioText == nil && activeLocalBioOverride == nil { return }
        if let pending = pendingBioText, newBio != pending {
            print("⚡️ [PERF] onChange bio: ignored revert to '\(newBio.prefix(30))' — pending POST for '\(pending.prefix(30))'")
            return
        }
        if activeLocalBioOverride == newBio {
            localBioOverride = nil
            persistedLocalBioOverrideText = ""
            persistedLocalBioOverrideTimestamp = 0
        }
        guard let current = profile, current.biography != newBio else { return }
        profile = profileByReplacingBiography(current, biography: newBio)
        print("⚡️ [PERF] Biography updated instantly in fake profile (no GET needed)")
        LogManager.shared.info("Biography updated instantly in profile view", category: .general)
    }

    private func handleCachedMediaURLsChange(_ newURLs: [String]?) {
        guard let newURLs else { return }
        guard !isLoading else {
            print("🔄 [PERF] onChange cachedMediaURLs fired but isLoading=true — skipped")
            return
        }
        // A silent/authoritative grid swap (or pull-to-refresh) owns the grid while it
        // runs and already saved the freshest data; reacting to its own saveProfile here
        // would reassign allMediaURLs mid-swap and cause a flash. Let the swap finish.
        guard !isSilentGridRefreshing, !isPullRefreshInFlight else {
            print("🔄 [PERF] onChange cachedMediaURLs skipped — grid swap/refresh in progress")
            return
        }
        let rawNewSet = Set(newURLs)
        if let cachedItems = profileCache.cachedProfile?.cachedMediaItems {
            for item in cachedItems where rawNewSet.contains(item.imageURL) {
                mediaItemsByURL[item.imageURL] = item
            }
        }
        let mergedURLs = cachedProfileURLsPreservingRevealOverlays(newURLs)
        let currentSet = Set(allMediaURLs)
        let newSet = Set(mergedURLs)
        guard currentSet != newSet else {
            print("🔄 [PERF] onChange cachedMediaURLs fired — no diff (both \(mergedURLs.count) items), skipped")
            return
        }
        let removed = currentSet.subtracting(newSet).count
        let added = newSet.subtracting(currentSet).count
        print("🔄 [PERF] onChange cachedMediaURLs: \(allMediaURLs.count)→\(mergedURLs.count) (-\(removed) +\(added))")
        if profile == nil, let cached = profileCache.cachedProfile { profile = cached }
        allMediaURLs = deduplicatedGridURLs(mergedURLs)

        let mergedRealIds = realMediaIds(in: newURLs)
        allMediaURLs.removeAll { url in
            guard let mediaId = revealMediaId(from: url), mergedRealIds.contains(mediaId) else { return false }
            cachedImages.removeValue(forKey: url)
            revealDates.removeValue(forKey: url)
            mediaItemsByURL.removeValue(forKey: url)
            return true
        }
        let urlsToKeep = Set(allMediaURLs)
        mediaItemsByURL = mediaItemsByURL.filter { key, _ in
            urlsToKeep.contains(key)
                || key.hasPrefix("reveal://")
                || key.hasPrefix("amnesia://carousel/")
                || key.hasPrefix("instapick://")
        }
        revealDates = revealDates.filter { key, _ in urlsToKeep.contains(key) }
        paintAmnesiaCarouselLocally(revealed: amnesiaSettings.isRevealed)
        paintInstapickCarouselLocally()
        let missing = mergedURLs.filter {
            cachedImages[$0] == nil
                && !$0.hasPrefix("reveal://")
                && !$0.hasPrefix("amnesia://carousel/")
                && !$0.hasPrefix("instapick://")
        }
        if !missing.isEmpty { downloadImagesForURLs(missing) }
        print("🔄 [PERF] Grid updated locally — \(mergedURLs.count) items (no API call)")
    }
    
    // MARK: - URL Scheme Profile Pic Action

    /// Handles vault://profilepic in its three variants.
    private func applyURLProfilePicAction(mode: String, data: String) async {
        guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked) else {
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

        if ppTestMode.isActive {
            guard let uiImage = UIImage(data: finalData) else { return }
            await MainActor.run { applyTestProfilePicture(uiImage) }
            LogManager.shared.info("TEST MODE — profile picture painted locally via URL scheme", category: .general)
            return
        }

        do {
            let success = try await instagram.changeProfilePicture(imageData: finalData, userInitiated: true)
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

    @discardableResult
    private func applyURLBiography(text: String, values: [String: String]) async -> Bool {
        // URL scheme bio is an explicit user-initiated command: bypass the bioFeatureEnabled
        // toggle (which only guards automatic/passive updates inside Performance).
        let effectiveValues: [String: String] = values.isEmpty ? ["text1": text] : values
        let tpl = bioTemplate
        let composed = tpl.isEmpty ? expandEscapes(text) : applyTemplate(effectiveValues, template: tpl)
        let acrosticInput = ["text1", "text2", "text3", "text4", "text5"]
            .compactMap { effectiveValues[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? text
        let inputForBio = bioAcrosticEnabled ? expandEscapes(acrosticInput) : composed
        let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
        let final = truncateAtWordBoundary(acrosticComposed, limit: 150)
        if final.count < acrosticComposed.count {
            print("✂️ [URL] Bio truncated: \(acrosticComposed.count)→\(final.count) chars")
        }

        if ppTestMode.isActive {
            await MainActor.run { applyTestBiography(final) }
            LogManager.shared.info("TEST MODE — URL bio painted locally", category: .general)
            return true
        }

        await MainActor.run {
            pinLocalBiography(final)
            beginLocalBioPostPredictionBioSend(source: "url-bio")
        }
        do {
            let ok = try await instagram.changeBiography(text: final, userInitiated: true)
            await MainActor.run {
                pendingBioText = nil
                completeLocalBioPostPredictionBioSend(success: ok, source: "url-bio")
            }
            if ok {
                print("✅ [URL] Biography updated via URL scheme")
                LogManager.shared.success("Biography updated via URL scheme (\(final.count) chars)", category: .general)
                fireDoubleConfirmationVibration()
            }
            return ok
        } catch {
            print("⚠️ [URL] Bio change failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme bio failed: \(error.localizedDescription)", category: .general)
            await MainActor.run {
                pendingBioText = nil
                completeLocalBioPostPredictionBioSend(success: false, source: "url-bio")
            }
            return false
        }
    }

    private func composedURLBiography(text: String, values: [String: String]) -> String {
        let effectiveValues: [String: String] = values.isEmpty ? ["text1": text] : values
        let tpl = bioTemplate
        let composed = tpl.isEmpty ? expandEscapes(text) : applyTemplate(effectiveValues, template: tpl)
        let acrosticInput = ["text1", "text2", "text3", "text4", "text5"]
            .compactMap { effectiveValues[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? text
        let inputForBio = bioAcrosticEnabled ? expandEscapes(acrosticInput) : composed
        let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
        return truncateAtWordBoundary(acrosticComposed, limit: 150)
    }

    private func normalizedURLCardSymbol(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard compact.count >= 2 else { return nil }

        if SetType.cardSlotLabels.contains(compact) {
            return compact
        }

        let suitMap: [Character: String] = [
            "S": "♠",
            "H": "♥",
            "C": "♣",
            "D": "♦"
        ]
        guard let suitCode = compact.last,
              let suit = suitMap[suitCode] else { return nil }

        var value = String(compact.dropLast())
        if value == "T" { value = "10" }

        let validValues = Set(["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"])
        guard validValues.contains(value) else { return nil }

        let symbol = "\(value)\(suit)"
        return SetType.cardSlotLabels.contains(symbol) ? symbol : nil
    }

    private func applyCombinedBioPostPredictionAction(values: [String: String]) async {
        let bioValues = Dictionary(uniqueKeysWithValues: values.compactMap { key, value -> (String, String)? in
            guard key.hasPrefix("text") else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (key, trimmed)
        })
        guard let bioText = (bioValues["text1"] ?? values["bio"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bioText.isEmpty else {
            LogManager.shared.warning("Combined Bio + PP blocked: missing bio", category: .general)
            return
        }

        let revealWord = (values["reveal"] ?? values["word"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slotText = values["slot"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardText = values["card"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (revealWord?.isEmpty == false) || (slotText?.isEmpty == false) || (cardText?.isEmpty == false) else {
            LogManager.shared.warning("Combined Bio + PP blocked: missing reveal target", category: .general)
            return
        }

        let effectiveBioValues = bioValues.isEmpty ? ["text1": bioText] : bioValues
        let finalLocalBio = composedURLBiography(text: bioText, values: effectiveBioValues)
        localBioOverride = (finalLocalBio, Date())
        applyBiographyToVisibleProfile(finalLocalBio)

        if profile == nil || ProfileCacheService.shared.loadProfile() == nil {
            guard !isFirstTimePreloading else {
                showCombinedProfileNotReadyAlert = true
                LogManager.shared.warning("Combined Bio + PP blocked: first-time preload already running", category: .general)
                return
            }
            print("🔗 [COMBO] No cached profile — loading profile before sending bio")
            LogManager.shared.info("Combined Bio + PP loading missing profile cache", category: .general)
            isCombinedBioPostPredictionGuardActive = true
            let loaded = await loadProfile(source: "combo_preload")
            guard loaded, profile != nil else {
                isCombinedBioPostPredictionGuardActive = false
                showCombinedProfileNotReadyAlert = true
                LogManager.shared.warning("Combined Bio + PP blocked: profile preload failed", category: .general)
                return
            }
        }

        combinedBioPostPredictionTask?.cancel()
        isCombinedBioPostPredictionGuardActive = true
        combinedBioPostPredictionTask = Task { @MainActor in
            defer {
                combinedBioPostPredictionTask = nil
            }

            print("🔗 [COMBO] Starting Bio + Post Prediction queue")
            LogManager.shared.info("Combined Bio + PP queue started", category: .general)
            let bioOK = await applyURLBiography(text: bioText, values: effectiveBioValues)
            guard bioOK, !Task.isCancelled else {
                isCombinedBioPostPredictionGuardActive = false
                LogManager.shared.warning("Combined Bio + PP stopped: bio failed or cancelled", category: .general)
                return
            }

            print("🔗 [COMBO] Bio confirmed — waiting \(combinedBioPostPredictionDelay)s before Post Prediction")
            LogManager.shared.info("Combined Bio + PP waiting \(combinedBioPostPredictionDelay)s", category: .general)
            try? await Task.sleep(nanoseconds: combinedBioPostPredictionDelay * 1_000_000_000)
            guard !Task.isCancelled else {
                isCombinedBioPostPredictionGuardActive = false
                return
            }

            isCombinedBioPostPredictionGuardActive = false
            combinedPPCooldownBypassUntil = Date().addingTimeInterval(90).timeIntervalSince1970

            let activeCardSet = ActiveSetSettings.shared.activeCardSetId != nil
            let normalizedCard = normalizedURLCardSymbol(cardText)
                ?? (activeCardSet ? normalizedURLCardSymbol(revealWord) : nil)

            if let card = normalizedCard {
                pendingCardReveal = card
                print("🔗 [COMBO] Queued Post Prediction card: \(card)")
            } else if let word = revealWord, !word.isEmpty {
                if let setName = values["set"], !setName.isEmpty {
                    guard activateURLWordSet(named: setName) else {
                        LogManager.shared.warning("Combined Bio + PP blocked: set '\(setName)' not found", category: .general)
                        return
                    }
                }
                ForceNumberRevealSettings.shared.urlRevealActive = true
                pendingOCRWord = word
                print("🔗 [COMBO] Queued Post Prediction word: \(word)")
            } else if let slotText, let slot = Int(slotText), (1...100).contains(slot) {
                let activeSettings = ActiveSetSettings.shared
                if let activeId = activeSettings.activeCustomSetId ?? activeSettings.activeListSetId,
                   let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && ($0.type == .custom || $0.type == .list) }) {
                    if activeSet.type == .list {
                        pendingListReveal = slot
                    } else {
                        pendingSlotReveal = slot
                    }
                    print("🔗 [COMBO] Queued Post Prediction slot: \(slot)")
                }
            } else if let card = cardText, !card.isEmpty {
                print("⚠️ [COMBO] Invalid card code: \(card)")
                LogManager.shared.warning("Combined Bio + PP invalid card code: \(card)", category: .general)
            }
        }
    }

    private func cancelCombinedBioPostPredictionQueue(reason: String) {
        guard combinedBioPostPredictionTask != nil || isCombinedBioPostPredictionGuardActive else { return }
        combinedBioPostPredictionTask?.cancel()
        combinedBioPostPredictionTask = nil
        isCombinedBioPostPredictionGuardActive = false
        print("🔗 [COMBO] Queue cancelled — \(reason)")
        LogManager.shared.info("Combined Bio + PP queue cancelled: \(reason)", category: .general)
    }

    /// Activates a Word/Number set by name for URL-scheme reveals.
    @discardableResult
    private func activateURLWordSet(named setName: String) -> Bool {
        let normalized = setName.precomposedStringWithCanonicalMapping
        guard let matchingSet = DataManager.shared.sets.first(where: {
            $0.name.precomposedStringWithCanonicalMapping.compare(
                normalized, options: .caseInsensitive, range: nil, locale: .current
            ) == .orderedSame && ($0.type == .word || $0.type == .number)
        }) else {
            return false
        }
        print("📲 [URL] Activating set '\(matchingSet.name)' for word reveal")
        ActiveSetSettings.shared.setActive(matchingSet)
        LogManager.shared.info("URL reveal activated set: \(matchingSet.name)", category: .general)
        return true
    }

    private func applyURLAction(mode: String, text: String, values: [String: String] = [:]) async {
        guard ppTestMode.isActive || !instagram.isLocked else {
            print("🚫 [URL] Lockdown active — skipping URL action")
            return
        }
        print("📲 [URL] Executing action=\(mode), text=\"\(text.prefix(40))\"")
        LogManager.shared.info("URL scheme action: \(mode) — \"\(text.prefix(40))\"", category: .general)

        if mode == "perform" {
            await applyCombinedBioPostPredictionAction(values: values)
            return
        }

        // ── Word reveal via vault://reveal?word= ─────────────────────────────
        if mode == "reveal" {
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !word.isEmpty else { return }
            
            // If a set name was provided, activate it first
            if let setName = values["set"], !setName.isEmpty {
                if !activateURLWordSet(named: setName) {
                    print("⚠️ [URL] Set '\(setName)' not found — aborting word reveal")
                    LogManager.shared.warning("URL reveal: set '\(setName)' not found", category: .general)
                    return
                }
            }
            
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
            
            let dataManager = DataManager.shared
            let activeSettings = ActiveSetSettings.shared
            var activeSet: PhotoSet?
            
            // If a set name was provided, find and activate it
            if let setName = values["set"], !setName.isEmpty {
                if let matchingSet = dataManager.sets.first(where: {
                    $0.name.lowercased() == setName.lowercased() && ($0.type == .custom || $0.type == .list)
                }) {
                    print("📲 [URL] Activating set '\(matchingSet.name)' for slot reveal")
                    activeSettings.activeSetId = matchingSet.id
                    activeSettings.activeSetType = matchingSet.type
                    activeSettings.isPostPredictionEnabled = true
                    activeSet = matchingSet
                    LogManager.shared.info("URL reveal activated set: \(matchingSet.name)", category: .general)
                } else {
                    print("⚠️ [URL] Set '\(setName)' not found or not a custom/list set")
                    LogManager.shared.warning("URL slot reveal: set '\(setName)' not found", category: .general)
                    return
                }
            } else {
                // Use currently active set
                guard let activeId = activeSettings.activeCustomSetId ?? activeSettings.activeListSetId,
                      let active = dataManager.sets.first(where: { $0.id == activeId && ($0.type == .custom || $0.type == .list) }) else {
                    print("🚫 [URL] Slot reveal: no active custom/list set and no 'set' parameter provided")
                    LogManager.shared.warning("URL slot reveal: no active custom/list set", category: .general)
                    return
                }
                activeSet = active
            }
            
            guard let finalSet = activeSet else { return }
            
            if !ppTestMode.isActive && UploadManager.shared.isActive && !didAutoPauseUpload {
                print("⚠️ [URL] Custom slot reveal blocked: upload is active and not paused by Performance")
                return
            }
            print("📲 [URL] Slot reveal: slot=\(slot) from '\(finalSet.name)'")
            LogManager.shared.info("URL reveal → slot \(slot) from '\(finalSet.name)'", category: .general)
            await MainActor.run {
                if finalSet.type == .list {
                    pendingListReveal = slot
                } else {
                    pendingSlotReveal = slot
                }
            }
            return
        }

        // ── Playing Card reveal via vault://reveal?card= ──────────────────────
        if mode == "reveal_card" {
            let rawSymbol = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawSymbol.isEmpty else { return }
            
            let dataManager = DataManager.shared
            let activeSettings = ActiveSetSettings.shared
            var activeSet: PhotoSet?
            
            // If a set name was provided, find and activate it
            if let setName = values["set"], !setName.isEmpty {
                if let matchingSet = dataManager.sets.first(where: {
                    $0.name.lowercased() == setName.lowercased() && $0.type == .card
                }) {
                    print("📲 [URL] Activating card set '\(matchingSet.name)'")
                    activeSettings.activeSetId = matchingSet.id
                    activeSettings.activeSetType = matchingSet.type
                    activeSettings.isPostPredictionEnabled = true
                    activeSet = matchingSet
                    LogManager.shared.info("URL reveal activated card set: \(matchingSet.name)", category: .general)
                } else {
                    print("⚠️ [URL] Card set '\(setName)' not found")
                    LogManager.shared.warning("URL card reveal: set '\(setName)' not found", category: .general)
                    return
                }
            } else {
                // Use currently active card set
                guard let activeId = activeSettings.activeCardSetId,
                      let active = dataManager.sets.first(where: { $0.id == activeId && $0.type == .card }) else {
                    print("🚫 [URL] Card reveal: no active card set and no 'set' parameter provided")
                    LogManager.shared.warning("URL card reveal: no active card set", category: .general)
                    return
                }
                activeSet = active
            }
            
            guard let finalSet = activeSet else { return }
            
            guard let symbol = normalizedURLCardSymbol(rawSymbol) else {
                print("⚠️ [URL] Card reveal: '\(rawSymbol)' is not a valid card symbol")
                LogManager.shared.warning("URL card reveal invalid code: \(rawSymbol)", category: .general)
                return
            }
            if !ppTestMode.isActive && UploadManager.shared.isActive && !didAutoPauseUpload {
                print("⚠️ [URL] Card reveal blocked: upload is active and not paused by Performance")
                return
            }
            print("📲 [URL] Card reveal: \(symbol) from '\(finalSet.name)'")
            LogManager.shared.info("URL reveal → card \(symbol) from '\(finalSet.name)'", category: .general)
            await MainActor.run { pendingCardReveal = symbol }
            return
        }

        // URL scheme commands are explicit user-initiated requests — they bypass the
        // bio/note feature toggles, which were designed to block automatic updates only
        // (OCR, API polling, lockscreen captures). A direct vault:// command always executes.

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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestNote(final) }
                    LogManager.shared.info("TEST MODE — URL note painted locally", category: .general)
                    return
                }
                // Optimistic: show note bubble immediately
                await MainActor.run { lastNoteText = final }
                let ok = try await instagram.createNote(text: final, userInitiated: true)
                if ok {
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [URL] Note sent via URL scheme")
                    LogManager.shared.success("Note sent via URL scheme (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            } else if mode == "bio" {
                _ = await applyURLBiography(text: text, values: effectiveValues)
            }
        } catch {
            print("⚠️ [URL] Action failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme action failed: \(error.localizedDescription)", category: .general)
        }
    }

    private var activeLocalBioOverride: String? {
        if let override = localBioOverride,
           Date().timeIntervalSince(override.timestamp) < 5 * 60 {
            return override.text
        }

        guard !persistedLocalBioOverrideText.isEmpty,
              persistedLocalBioOverrideTimestamp > 0 else { return nil }
        let timestamp = Date(timeIntervalSince1970: persistedLocalBioOverrideTimestamp)
        guard Date().timeIntervalSince(timestamp) < 5 * 60 else { return nil }
        return persistedLocalBioOverrideText
    }

    @MainActor
    private func pinLocalBiography(_ text: String) {
        pendingBioText = text
        localBioOverride = (text, Date())
        persistedLocalBioOverrideText = text
        persistedLocalBioOverrideTimestamp = Date().timeIntervalSince1970
        applyBiographyToVisibleProfile(text)
    }

    @MainActor
    private func armLocalBioPostPredictionCombo(source: String) {
        guard !ppTestMode.isActive,
              bioFeatureEnabled,
              ActiveSetSettings.shared.isPostPredictionEnabled,
              ActiveSetSettings.shared.activeSetId != nil else { return }

        let now = Date().timeIntervalSince1970
        localComboEarliestRevealAt = now + Double(combinedBioPostPredictionDelay)
        combinedPPCooldownBypassUntil = now + 90
        UserDefaults.standard.set(localComboEarliestRevealAt, forKey: "local_combo_earliest_pp_reveal_at")
        UserDefaults.standard.set(combinedPPCooldownBypassUntil, forKey: "combined_pp_cooldown_bypass_until")
        print("🔗 [LOCAL COMBO] Armed by \(source) — PP allowed after \(combinedBioPostPredictionDelay)s")
        LogManager.shared.info("Local Bio + PP combo armed by \(source): \(combinedBioPostPredictionDelay)s", category: .general)
    }

    @MainActor
    private func beginLocalBioPostPredictionBioSend(source: String) {
        guard !ppTestMode.isActive,
              bioFeatureEnabled,
              ActiveSetSettings.shared.isPostPredictionEnabled,
              ActiveSetSettings.shared.activeSetId != nil else { return }

        let now = Date().timeIntervalSince1970
        localComboBioPendingUntil = now + 45
        localComboEarliestRevealAt = 0
        combinedPPCooldownBypassUntil = now + 90
        UserDefaults.standard.set(localComboBioPendingUntil, forKey: "local_combo_bio_pending_until")
        UserDefaults.standard.set(localComboEarliestRevealAt, forKey: "local_combo_earliest_pp_reveal_at")
        UserDefaults.standard.set(combinedPPCooldownBypassUntil, forKey: "combined_pp_cooldown_bypass_until")
        print("🔗 [LOCAL COMBO] Bio update in-flight by \(source) — PP locked until confirmation")
        LogManager.shared.info("Local Bio + PP waiting for bio confirmation by \(source)", category: .general)
    }

    @MainActor
    private func completeLocalBioPostPredictionBioSend(success: Bool, source: String) {
        if success {
            armLocalBioPostPredictionCombo(source: source)
            if source.contains("cover-typing") {
                coverTypingBioReadyForPP = true
                UserDefaults.standard.set(true, forKey: "local_combo_cover_typing_bio_ready")
                print("🔗 [LOCAL COMBO] Cover Typing bio ready — Lockscreen PP may proceed after settle")
            }
        } else {
            localComboEarliestRevealAt = 0
            if source.contains("cover-typing") {
                coverTypingBioReadyForPP = false
                UserDefaults.standard.set(false, forKey: "local_combo_cover_typing_bio_ready")
            }
            print("🔗 [LOCAL COMBO] Bio update failed by \(source) — PP combo not armed")
            LogManager.shared.warning("Local Bio + PP not armed because bio update failed by \(source)", category: .general)
        }
        localComboBioPendingUntil = 0
        UserDefaults.standard.set(localComboBioPendingUntil, forKey: "local_combo_bio_pending_until")
        UserDefaults.standard.set(localComboEarliestRevealAt, forKey: "local_combo_earliest_pp_reveal_at")
    }

    @MainActor
    private func applyTestNote(_ text: String) {
        if testOriginalNoteText == nil {
            testOriginalNoteText = lastNoteText
            testOriginalNoteTimestamp = lastNoteSentTimestamp
        }
        lastNoteText = text
        lastNoteSentTimestamp = Date().timeIntervalSince1970
        print("🧪 [TEST MODE] Note painted locally only")
    }

    @MainActor
    private func applyTestBiography(_ text: String) {
        if testOriginalBiography == nil {
            testOriginalBiography = profile?.biography ?? profileCache.cachedProfile?.biography ?? ""
        }
        pinLocalBiography(text)
        pendingBioText = nil
        print("🧪 [TEST MODE] Biography painted locally only")
    }

    @MainActor
    private func applyTestProfilePicture(_ image: UIImage) {
        let profilePicURL = profile?.profilePicURL ?? profileCache.cachedProfile?.profilePicURL ?? "test_profile_pic"
        if testOriginalProfilePicImages[profilePicURL] == nil,
           !testOriginalProfilePicMissingURLs.contains(profilePicURL) {
            if let originalImage = cachedImages[profilePicURL] {
                testOriginalProfilePicImages[profilePicURL] = originalImage
            } else {
                testOriginalProfilePicMissingURLs.insert(profilePicURL)
            }
        }
        cachedImages[profilePicURL] = image
        print("🧪 [TEST MODE] Profile picture painted locally only")
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
            cachedTaggedItems: current.cachedTaggedItems,
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
        guard ppTestMode.isActive || !instagram.isLocked else {
            print("🚫 [CLIPBOARD] Lockdown active — skipping clipboard auto-mode")
            return
        }
        // Cold-start guard: clipboard often contains stale text from before the
        // app was opened. Defer until the window closes so a stale note/bio
        // POST doesn't fire right on top of the entry GETs.
        if !ppTestMode.isActive && InstagramSafetyGate.shared.isInColdStartWindow {
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestNote(final) }
                    clipboardAutoLastSent = text
                    LogManager.shared.info("TEST MODE — clipboard note painted locally", category: .general)
                    return
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestBiography(final) }
                    clipboardAutoLastSent = text
                    LogManager.shared.info("TEST MODE — clipboard bio painted locally", category: .general)
                    return
                }
                // Optimistic: show bio immediately
                await MainActor.run {
                    pinLocalBiography(final)
                    beginLocalBioPostPredictionBioSend(source: "clipboard-bio")
                }
                let ok = try await instagram.changeBiography(text: final)
                await MainActor.run {
                    completeLocalBioPostPredictionBioSend(success: ok, source: "clipboard-bio")
                }
                if ok {
                    clipboardAutoLastSent = text  // track original clipboard text to avoid re-sends
                    print("✅ [CLIPBOARD] Biography updated from clipboard")
                    LogManager.shared.success("Auto-bio updated from clipboard (\(final.count) chars)", category: .general)
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            await MainActor.run {
                completeLocalBioPostPredictionBioSend(success: false, source: "clipboard-bio")
            }
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
        guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked) else {
            print("🚫 [API AUTO] Lockdown active or not logged in — skipping")
            return
        }
        // Cold-start guard: if a fresh value arrives during the first 45s the
        // POST (createNote / changeBiography) would stack on top of the entry
        // GETs and trigger challenge_required. Wait until the window closes.
        if !ppTestMode.isActive && InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] API auto-mode (\(target)) deferred — \(remaining)s remaining")
            LogManager.shared.info("[COLD-START] API auto-mode (\(target)) deferred — \(remaining)s", category: .general)
            try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 3...6)) * 1_000_000_000)
            guard instagram.isLoggedIn, !instagram.isLocked, !instagram.isSessionChallenged else { return }
        }

        // Determine primary source (text1) — falls back to legacy single source
        let targetSources = target == "note"
            ? integrations.sourcesForTarget("note")
            : integrations.bioSources(forTemplateSlot: bioActiveSlot)
        let primarySource = target == "note"
            ? (integrations.noteText1Source != .none ? integrations.noteText1Source : integrations.noteApiSource)
            : (targetSources[0] != .none ? targetSources[0] : integrations.bioApiSource)
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
        if !ppTestMode.isActive,
           !trimmed.isEmpty,
           let lastSent = ud.string(forKey: lastKey),
           lastSent == trimmed {
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

        let src2 = targetSources[1]
        let src3 = targetSources[2]
        let src4 = targetSources[3]
        let src5 = targetSources[4]
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestNote(final) }
                    LogManager.shared.info("TEST MODE — API note painted locally", category: .general)
                    return
                }
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestBiography(final) }
                    LogManager.shared.info("TEST MODE — API bio painted locally", category: .general)
                    return
                }
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run {
                    pinLocalBiography(final)
                    beginLocalBioPostPredictionBioSend(source: "api-bio")
                }
                let ok = try await instagram.changeBiography(text: final)
                await MainActor.run {
                    completeLocalBioPostPredictionBioSend(success: ok, source: "api-bio")
                }
                if ok {
                    print("✅ [API AUTO] Biography updated: \"\(final)\"")
                    ud.set(trimmed, forKey: lastKey)          // raw text for dedup
                    ud.set(Date(), forKey: dateKey)           // timestamp so dedup expires in 2h
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            if target != "note" {
                await MainActor.run {
                    completeLocalBioPostPredictionBioSend(success: false, source: "api-bio")
                }
            }
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
        let activeBioSources = integrations.bioSources(forTemplateSlot: bioActiveSlot)
        let bioActive  = activeBioSources.contains { $0.isPolled } || integrations.bioApiSource.isPolled
        let noteActive = integrations.noteText1Source.isPolled || integrations.noteText2Source.isPolled || integrations.noteText3Source.isPolled || integrations.noteText4Source.isPolled || integrations.noteText5Source.isPolled || integrations.noteApiSource.isPolled
        let ppActive   = integrations.ppApiSource   != .none && (ppTopInputMode == "api" || activePostPredictionInputMethod == .api)
        guard bioActive || noteActive || ppActive else { return }
        guard apiPollingTask == nil else { return }

        print("🔔 [API POLL] Starting — bio=\(bioActive) note=\(noteActive) pp=\(ppActive) interval=2s")
        let configuredEntries = ["bio", "note"].flatMap { target in
            templateSourceEntries(for: target)
                .filter { $0.source.isPolled }
                .map { "\(target) text\($0.slot)=\($0.source.displayName)" }
        }
        let ppConfig = ppActive ? ["pp=\(integrations.ppApiSource.displayName)"] : []
        let configLine = (configuredEntries + ppConfig).joined(separator: ", ")
        if !configLine.isEmpty {
            LogManager.shared.info("API poll configured: \(configLine)", category: .general)
            print("🔔 [API POLL] Configured: \(configLine)")
        }
        apiPollingTask = Task { @MainActor in
            await seedApiPollingBaselines(bioActive: bioActive, noteActive: noteActive, ppActive: ppActive)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked && !instagram.isSessionExpired) else { continue }
                guard !isCombinedBioPostPredictionGuardActive else { continue }

                // ── bio / note ────────────────────────────────────────────────
                // When both bio and note are active and detect new values simultaneously,
                // execute them sequentially with a delay to avoid note getting cancelled
                // while waiting for bio's quiet window to expire.
                var pendingApiTasks: [(target: String, value: String?)] = []
                
                for target in ["bio", "note"] {
                    let polledEntries = templateSourceEntries(for: target).filter { $0.source.isPolled }
                    guard !polledEntries.isEmpty else { continue }

                    for entry in polledEntries {
                        guard let payload = await integrations.fetchPayload(for: entry.source) else { continue }
                        let newValue = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !newValue.isEmpty else { continue }

                        let tokenKey = apiPollTokenKey(target: target, slot: entry.slot, source: entry.source)
                        if lastApiPollTokens[tokenKey] == nil {
                            lastApiPollTokens[tokenKey] = payload.changeToken
                            print("🔔 [API POLL] Baseline for \(target) text\(entry.slot) seeded — waiting for fresh change")
                            LogManager.shared.info("API poll baseline seeded for \(target) text\(entry.slot); waiting for fresh input", category: .general)
                            continue
                        }
                        guard payload.changeToken != lastApiPollTokens[tokenKey] else { continue }

                        if hasPendingInterfaceRequirement(for: target) {
                            if let pendingValues = pendingInterfaceTemplateValues[target],
                               let pendingValue = pendingValues.values
                                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                                    .first(where: { !$0.isEmpty }) {
                                let pendingKinds = Set(templateSourceEntries(for: target).compactMap { entry -> InterfaceKind? in
                                    let key = "text\(entry.slot)"
                                    guard pendingValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
                                    return entry.source.interfaceKind
                                })
                                if !pendingKinds.isEmpty {
                                    print("🔔 [API POLL] Fresh \(target) text\(entry.slot) detected — completing pending interface input")
                                    LogManager.shared.info("API poll completed pending interface \(target) text\(entry.slot)", category: .general)
                                    await applyInterfaceCaptureToTarget(value: pendingValue, kinds: pendingKinds, target: target)
                                    continue
                                }
                            }
                            print("🔔 [API POLL] Fresh \(target) text\(entry.slot) detected — waiting for interface input before send")
                            LogManager.shared.info("API poll detected \(target) text\(entry.slot); waiting for interface input", category: .general)
                            continue
                        }

                        lastApiPollTokens[tokenKey] = payload.changeToken
                        print("🔔 [API POLL] New value for \(target) text\(entry.slot): \"\(newValue.prefix(40))\"")
                        LogManager.shared.info("API poll detected new \(target) text\(entry.slot): \"\(newValue.prefix(40))\"", category: .general)
                        
                        // Queue the task instead of executing immediately
                        pendingApiTasks.append((target: target, value: entry.slot == 1 ? newValue : nil))
                    }
                }
                
                // Execute queued tasks sequentially with appropriate delays
                if !pendingApiTasks.isEmpty {
                    for (index, task) in pendingApiTasks.enumerated() {
                        await applyApiAutoMode(target: task.target, preloadedValue: task.value)
                        // Add delay between bio and note to prevent note cancellation
                        if index < pendingApiTasks.count - 1 {
                            let delaySeconds = 4 // Brief anti-bot gap between consecutive API writes
                            print("⏳ [API POLL] Waiting \(delaySeconds)s between \(task.target) and next API write")
                            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                        }
                    }
                }

                // ── Post Prediction word reveal ───────────────────────────────
                guard integrations.ppApiSource != .none,
                      ppTopInputMode == "api" || activePostPredictionInputMethod == .api else { continue }
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
        let targetEntries: [(target: String, slot: Int, source: ApiSource)] =
            (noteActive ? templateSourceEntries(for: "note").filter { $0.source.isPolled }.map { ("note", $0.slot, $0.source) } : []) +
            (bioActive  ? templateSourceEntries(for: "bio").filter  { $0.source.isPolled }.map { ("bio",  $0.slot, $0.source) } : [])

        for entry in targetEntries {
            guard let payload = await integrations.fetchPayload(for: entry.source) else { continue }
            let value = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let tokenKey = apiPollTokenKey(target: entry.target, slot: entry.slot, source: entry.source)
            lastApiPollTokens[tokenKey] = payload.changeToken
            print("🔔 [API POLL] Baseline for \(entry.target) text\(entry.slot) seeded immediately — waiting for fresh change")
            LogManager.shared.info("API poll baseline seeded for \(entry.target) text\(entry.slot); waiting for fresh input", category: .general)
        }

        if ppActive, integrations.ppApiSource != .none {
            guard let payload = await integrations.fetchPayload(for: integrations.ppApiSource) else { return }
            let value = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            let tokenKey = "pp:\(integrations.ppApiSource.rawValue)"
            lastApiPollTokens[tokenKey] = payload.changeToken
            print("🔔 [API POLL] Baseline for pp seeded immediately — waiting for fresh change")
            LogManager.shared.info("API poll baseline seeded for pp; waiting for fresh input", category: .general)
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
        guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked) else {
            print("🚫 [OCR] Not logged in or lockdown active — skipping")
            return
        }

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_auto_input"      : "last_biography_text"
        let dateKey = target == "note" ? "last_note_auto_sent_date"  : "last_biography_sent_date"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Dedup on the raw detected word — expires after 2 hours
        if !ppTestMode.isActive, let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestNote(final) }
                    LogManager.shared.info("TEST MODE — OCR note painted locally", category: .general)
                    return
                }
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
                if ppTestMode.isActive {
                    await MainActor.run { applyTestBiography(final) }
                    LogManager.shared.info("TEST MODE — OCR bio painted locally", category: .general)
                    return
                }

                // ── Optimistic UI update (fake profile shows result instantly) ────────
                // Pin pendingBioText so that a concurrent loadProfile (fetching the old
                // bio from Instagram while our POST is in-flight) cannot revert the fake
                // profile via onChange(of: profileCache.cachedProfile?.biography).
                await MainActor.run {
                    pinLocalBiography(final)
                    beginLocalBioPostPredictionBioSend(source: "ocr-bio")
                }

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
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: ok, source: "ocr-bio")
                }
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // raw word for dedup
                    ud.set(Date(), forKey: dateKey)   // timestamp so dedup expires in 2h
                    print("✅ [OCR] Biography updated: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            if target != "note" {
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: false, source: "ocr-bio")
                }
            } else {
                await MainActor.run { pendingBioText = nil }
            }
            print("⚠️ [OCR] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("OCR auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Cover Typing → Biography

    @MainActor
    private func applyCoverTypingToBiography(word: String) async {
        guard bioFeatureEnabled, bioTopInputMode == "coverTyping" else { return }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ud = UserDefaults.standard
        let lastKey = "last_biography_text"
        let dateKey = "last_biography_sent_date"

        // Use Cover Typing as text1/word. Other API-polled slots can still resolve.
        var resolvedValues = await integrations.fetchTemplatePlaceholders(for: "bio")
        resolvedValues["text1"] = trimmed
        let composed = bioTemplate.isEmpty ? trimmed : applyTemplate(resolvedValues, template: bioTemplate)
        let inputForBio = bioAcrosticEnabled ? trimmed : composed
        let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
        let final = truncateAtWordBoundary(acrosticComposed, limit: 150)

        // Match OCR/API dedup policy: avoid reposting the same captured word within 2h.
        // If Lockscreen PP is waiting on this bio, still release it (bio already on Instagram).
        if !ppTestMode.isActive, let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
            let sentDate = ud.object(forKey: dateKey) as? Date ?? .distantPast
            let hoursSince = Date().timeIntervalSince(sentDate) / 3600
            if hoursSince < 2 {
                print("⏭️ [COVER] Bio dedup: same word sent \(String(format: "%.0f", hoursSince * 60))m ago")
                pinLocalBiography(final)
                // Release any Lockscreen PP that is waiting on this Cover Typing bio.
                completeLocalBioPostPredictionBioSend(success: true, source: "cover-typing-bio")
                return
            }
            ud.removeObject(forKey: lastKey)
        }

        if ppTestMode.isActive {
            applyTestBiography(final)
            completeLocalBioPostPredictionBioSend(success: true, source: "cover-typing-bio")
            LogManager.shared.info("TEST MODE — Cover Typing bio painted locally", category: .general)
            return
        }

        guard instagram.isLoggedIn && !instagram.isLocked else {
            print("⏭️ [COVER] Bio skipped: not logged in or locked")
            completeLocalBioPostPredictionBioSend(success: false, source: "cover-typing-bio")
            return
        }
        guard !UploadManager.shared.isActive else {
            print("⏭️ [COVER] Bio skipped: upload active")
            LogManager.shared.warning("Cover Typing bio skipped: upload active", category: .general)
            completeLocalBioPostPredictionBioSend(success: false, source: "cover-typing-bio")
            return
        }

        let cooldownKey = "last_cover_typing_bio_sent"
        let lastSentTime = ud.double(forKey: cooldownKey)
        let timeSinceLast = Date().timeIntervalSince1970 - lastSentTime
        if lastSentTime > 0, timeSinceLast < interfaceCaptureCooldown {
            let remaining = Int(interfaceCaptureCooldown - timeSinceLast)
            print("⏭️ [COVER] Bio cooldown: \(remaining)s remaining")
            LogManager.shared.warning("Cover Typing bio blocked: cooldown \(remaining)s remaining", category: .general)
            // Previous bio POST is recent — unblock Lockscreen PP instead of leaving it hung.
            pinLocalBiography(final)
            completeLocalBioPostPredictionBioSend(success: true, source: "cover-typing-bio")
            return
        }

        pinLocalBiography(final)
        beginLocalBioPostPredictionBioSend(source: "cover-typing-bio")
        ud.set(Date().timeIntervalSince1970, forKey: cooldownKey)

        do {
            let ok = try await instagram.changeBiography(text: final, userInitiated: true)
            pendingBioText = nil
            completeLocalBioPostPredictionBioSend(success: ok, source: "cover-typing-bio")
            if ok {
                ud.set(trimmed, forKey: lastKey)
                ud.set(Date(), forKey: dateKey)
                print("✅ [COVER] Biography updated: \"\(final)\"")
                fireDoubleConfirmationVibration()
            }
        } catch {
            pendingBioText = nil
            completeLocalBioPostPredictionBioSend(success: false, source: "cover-typing-bio")
            LogManager.shared.warning("Cover Typing bio failed: \(error.localizedDescription)", category: .general)
            print("⚠️ [COVER] Bio failed: \(error.localizedDescription)")
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

    // MARK: - Notes Input capture routing

    /// Routes lines from FakeNotesInputView to bio/note {textN} slots configured for
    /// .fakeNotes, assigning each line sequentially (line[0] → first fakeNotes slot,
    /// line[1] → second fakeNotes slot, etc.). If the active Word Set uses .fakeNotes,
    /// line[0] is also sent to the post-prediction reveal pipeline.
    private func applyFakeNotesCapture(lines: [String]) async {
        guard !lines.isEmpty else { return }
        // Route to word set if active
        if let activeId = ActiveSetSettings.shared.activeSetId,
           let set = DataManager.shared.sets.first(where: { $0.id == activeId }),
           set.resolvedInputMethod == .fakeNotes,
           let firstLine = lines.first, !firstLine.isEmpty {
            await MainActor.run {
                ForceNumberRevealSettings.shared.urlRevealActive = true
                pendingOCRWord = firstLine
            }
            print("📝 [FAKE-NOTES] Word set reveal queued: \(firstLine)")
        }
        // Route lines to note/bio text slots
        await applyFakeNotesCaptureToTarget(lines: lines, target: "note")
        await applyFakeNotesCaptureToTarget(lines: lines, target: "bio")
    }

    private func applyFakeNotesCaptureToTarget(lines: [String], target: String) async {
        guard targetFeatureEnabled(target) else { return }

        let sources: [ApiSource] = target == "note"
            ? [integrations.noteText1Source, integrations.noteText2Source, integrations.noteText3Source, integrations.noteText4Source, integrations.noteText5Source]
            : integrations.bioSources(forTemplateSlot: bioActiveSlot)

        let fakeNotesSlots = sources.enumerated().compactMap { idx, src -> Int? in
            src == .fakeNotes ? (idx + 1) : nil
        }
        guard !fakeNotesSlots.isEmpty else { return }

        // Build per-slot values: each captured line goes to the next fakeNotes slot in order
        var resolvedValues: [String: String] = [:]
        for (lineIdx, slot) in fakeNotesSlots.enumerated() {
            guard lineIdx < lines.count else { break }
            let line = lines[lineIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            resolvedValues["text\(slot)"] = line
        }
        guard !resolvedValues.isEmpty else { return }

        // Merge API-polled values for any non-fakeNotes slots
        guard let polledValues = await waitForPolledTemplateValues(
            target: target,
            excluding: Set(fakeNotesSlots)
        ) else { return }
        for (key, val) in polledValues { resolvedValues[key] = val }

        // Check all required slots are filled
        let requiredEntries = templateSourceEntries(for: target)
        let missingSlots = requiredEntries.compactMap { entry -> String? in
            let key = "text\(entry.slot)"
            return (resolvedValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? key : nil
        }
        guard missingSlots.isEmpty else {
            print("⏳ [FAKE-NOTES] \(target) waiting for slots: \(missingSlots.joined(separator: ", "))")
            return
        }

        let tpl = target == "note" ? noteTemplate : bioTemplate
        let firstLine = lines.first ?? ""
        let composed = tpl.isEmpty ? firstLine : applyTemplate(resolvedValues, template: tpl)

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_auto_input"     : "last_biography_text"
        let dateKey = target == "note" ? "last_note_auto_sent_date" : "last_biography_sent_date"

        let finalText: String
        if target == "note" {
            finalText = truncateAtWordBoundary(composed, limit: 60)
            if ppTestMode.isActive {
                await MainActor.run { applyTestNote(finalText) }
                LogManager.shared.info("TEST MODE — Notes Input note painted locally", category: .general)
                return
            }
            await MainActor.run { lastNoteText = finalText }
        } else {
            let inputForBio = bioAcrosticEnabled ? firstLine : composed
            let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
            finalText = truncateAtWordBoundary(acrosticComposed, limit: 150)
            if ppTestMode.isActive {
                await MainActor.run { applyTestBiography(finalText) }
                LogManager.shared.info("TEST MODE — Notes Input bio painted locally", category: .general)
                return
            }
            await MainActor.run { pinLocalBiography(finalText) }
        }

        guard instagram.isLoggedIn && !instagram.isLocked else { return }
        guard !UploadManager.shared.isActive else { return }

        let cooldownKey = "last_interface_capture_sent_\(target)"
        let lastSentTime = UserDefaults.standard.double(forKey: cooldownKey)
        let timeSinceLast = Date().timeIntervalSince1970 - lastSentTime
        if lastSentTime > 0, timeSinceLast < interfaceCaptureCooldown {
            print("⏭️ [FAKE-NOTES] \(target) cooldown: \(Int(interfaceCaptureCooldown - timeSinceLast))s remaining")
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cooldownKey)
        if target != "note" {
            await MainActor.run { beginLocalBioPostPredictionBioSend(source: "fake-notes-bio") }
        }

        do {
            if target == "note" {
                let ok = try await instagram.createNote(text: finalText)
                if ok {
                    ud.set(firstLine, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [FAKE-NOTES] Note sent: \"\(finalText)\"")
                    fireDoubleConfirmationVibration()
                }
            } else {
                let ok = try await instagram.changeBiography(text: finalText)
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: ok, source: "fake-notes-bio")
                }
                if ok {
                    ud.set(firstLine, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    print("✅ [FAKE-NOTES] Biography updated: \"\(finalText)\"")
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            if target != "note" {
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: false, source: "fake-notes-bio")
                }
            }
            LogManager.shared.warning("Notes Input send failed (\(target)): \(error.localizedDescription)", category: .general)
        }
    }

    private func templateSourceEntries(for target: String) -> [(slot: Int, source: ApiSource)] {
        let sources: [ApiSource] = target == "note"
            ? [integrations.noteText1Source, integrations.noteText2Source, integrations.noteText3Source, integrations.noteText4Source, integrations.noteText5Source]
            : integrations.bioSources(forTemplateSlot: bioActiveSlot)

        return sources.enumerated().compactMap { idx, source in
            let slot = idx + 1
            guard source != .none, templateUsesSlot(target: target, slot: slot) else { return nil }
            return (slot, source)
        }
    }

    private func templateUsesSlot(target: String, slot: Int) -> Bool {
        if target == "bio", bioAcrosticEnabled {
            return slot == 1
        }

        let tpl = target == "note" ? noteTemplate : bioTemplate
        if slot == 1 {
            return tpl.contains("{text1}") || tpl.contains("{word}") || tpl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return tpl.contains("{text\(slot)}")
    }

    private func apiPollTokenKey(target: String, slot: Int, source: ApiSource) -> String {
        "\(target):text\(slot):\(source.rawValue)"
    }

    private func hasPendingInterfaceRequirement(for target: String) -> Bool {
        templateSourceEntries(for: target).contains { $0.source.isInterfaceInput }
    }

    private func waitForPolledTemplateValues(
        target: String,
        excluding interfaceSlots: Set<Int>,
        timeoutSeconds: TimeInterval = 14
    ) async -> [String: String]? {
        let entries = templateSourceEntries(for: target).filter {
            $0.source.isPolled && !interfaceSlots.contains($0.slot)
        }
        guard !entries.isEmpty else { return [:] }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var values: [String: String] = [:]

        while Date() < deadline {
            var allReady = true
            for entry in entries {
                guard let payload = await integrations.fetchPayload(for: entry.source) else {
                    allReady = false
                    continue
                }

                let value = payload.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    allReady = false
                    continue
                }

                let tokenKey = apiPollTokenKey(target: target, slot: entry.slot, source: entry.source)
                if let baseline = lastApiPollTokens[tokenKey], payload.changeToken == baseline {
                    allReady = false
                    continue
                }

                values["text\(entry.slot)"] = value
            }

            if allReady {
                for entry in entries {
                    if let payload = await integrations.fetchPayload(for: entry.source) {
                        let tokenKey = apiPollTokenKey(target: target, slot: entry.slot, source: entry.source)
                        lastApiPollTokens[tokenKey] = payload.changeToken
                    }
                }
                return values
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        print("⏳ [INPUT] \(target) waiting for API slot timed out — not sending partial template")
        LogManager.shared.warning("Interface capture \(target) timed out waiting for API slot", category: .general)
        return nil
    }

    private func applyInterfaceCaptureToTarget(value: String, kinds: Set<InterfaceKind>, target: String) async {
        guard targetFeatureEnabled(target) else {
            print("⏭️ [INPUT] \(target) disabled — skipping")
            return
        }
        let sources: [ApiSource] = target == "note"
            ? [integrations.noteText1Source, integrations.noteText2Source, integrations.noteText3Source, integrations.noteText4Source, integrations.noteText5Source]
            : integrations.bioSources(forTemplateSlot: bioActiveSlot)
        let matchingSlots = sources.enumerated().compactMap { idx, src -> Int? in
            guard let k = src.interfaceKind, kinds.contains(k) else { return nil }
            return idx + 1
        }
        guard !matchingSlots.isEmpty else { return }

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_auto_input"     : "last_biography_text"
        let dateKey = target == "note" ? "last_note_auto_sent_date" : "last_biography_sent_date"

        let tpl = target == "note" ? noteTemplate : bioTemplate
        let matchingSlotSet = Set(matchingSlots)
        var resolvedValues = pendingInterfaceTemplateValues[target] ?? [:]
        for slot in matchingSlots { resolvedValues["text\(slot)"] = value }
        pendingInterfaceTemplateValues[target] = resolvedValues

        // If this Bio/Note template mixes a physical input with Inject/API, wait
        // for the API slots to receive a fresh value before composing. Otherwise
        // the first input would publish a partial bio and the second input would
        // be blocked by the biography cooldown.
        guard let polledValues = await waitForPolledTemplateValues(target: target, excluding: matchingSlotSet) else {
            return
        }
        for (key, value) in polledValues { resolvedValues[key] = value }

        let requiredEntries = templateSourceEntries(for: target)
        let missingSlots = requiredEntries.compactMap { entry -> String? in
            let key = "text\(entry.slot)"
            return (resolvedValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? key : nil
        }
        guard missingSlots.isEmpty else {
            print("⏳ [INPUT] \(target) waiting for slots: \(missingSlots.joined(separator: ", "))")
            LogManager.shared.info("Interface capture \(target) waiting for \(missingSlots.joined(separator: ", "))", category: .general)
            return
        }

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
            if ppTestMode.isActive {
                await MainActor.run {
                    applyTestNote(finalText)
                    pendingInterfaceTemplateValues[target] = nil
                }
                LogManager.shared.info("TEST MODE — interface note painted locally", category: .general)
                return
            }
            await MainActor.run { lastNoteText = finalText }
        } else {
            let inputForBio = bioAcrosticEnabled ? value : composed
            let acrosticComposed = applyAcrosticIfNeeded(inputForBio)
            finalText = truncateAtWordBoundary(acrosticComposed, limit: 150)
            if finalText.count < acrosticComposed.count {
                print("✂️ [INPUT] Biography truncated at word boundary: \(acrosticComposed.count)→\(finalText.count) chars")
            }
            if ppTestMode.isActive {
                await MainActor.run {
                    applyTestBiography(finalText)
                    pendingInterfaceTemplateValues[target] = nil
                }
                LogManager.shared.info("TEST MODE — interface bio painted locally", category: .general)
                return
            }
            await MainActor.run { pinLocalBiography(finalText) }
        }

        guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked) else {
            print("⏭️ [INPUT] \(target) painted locally, but real send skipped: not logged in or locked")
            return
        }
        // Don't stack a note/bio POST on top of a running upload (anti-bot).
        guard ppTestMode.isActive || !UploadManager.shared.isActive else {
            print("⏭️ [INPUT] \(target) painted locally, but real send skipped: upload active")
            LogManager.shared.warning("Interface capture \(target) real send skipped: upload active", category: .general)
            return
        }

        // Dedup (2h) on the raw captured value — same policy as OCR to avoid
        // duplicate-note spam flags. This runs after local paint so repeated
        // rehearsals still update the fake profile even when the real POST is skipped.
        if !ppTestMode.isActive, let lastSent = ud.string(forKey: lastKey), lastSent == value {
            let sentDate = ud.object(forKey: dateKey) as? Date ?? .distantPast
            if Date().timeIntervalSince(sentDate) / 3600 < 2 {
                print("⏭️ [INPUT] \(target) painted locally, real send deduped")
                LogManager.shared.info("Interface capture \(target) real send deduped after local paint", category: .general)
                return
            }
            ud.removeObject(forKey: lastKey)
        }

        // Inter-capture cooldown: block a second send within 90s of the last one for
        // this target, regardless of value. Prevents rapid consecutive POSTs during
        // testing or accidental double-dismiss of the input overlay.
        let cooldownKey = "last_interface_capture_sent_\(target)"
        let lastSentTime = UserDefaults.standard.double(forKey: cooldownKey)
        let timeSinceLast = Date().timeIntervalSince1970 - lastSentTime
        if !ppTestMode.isActive, lastSentTime > 0, timeSinceLast < interfaceCaptureCooldown {
            let remaining = Int(interfaceCaptureCooldown - timeSinceLast)
            print("⏭️ [INPUT] \(target) painted locally, real send cooldown: \(remaining)s remaining")
            LogManager.shared.warning("Interface capture \(target) blocked: cooldown \(remaining)s remaining", category: .general)
            return
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
        if target != "note" {
            await MainActor.run { beginLocalBioPostPredictionBioSend(source: "interface-bio") }
        }

        do {
            if target == "note" {
                let ok = try await instagram.createNote(text: finalText)
                if ok {
                    ud.set(value, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    await MainActor.run { pendingInterfaceTemplateValues[target] = nil }
                    await MainActor.run { lastNoteSentTimestamp = Date().timeIntervalSince1970 }
                    print("✅ [INPUT] Note sent: \"\(finalText)\"")
                    // Double vibration: confirms the note is live on real Instagram
                    fireDoubleConfirmationVibration()
                }
            } else {
                let ok = try await instagram.changeBiography(text: finalText)
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: ok, source: "interface-bio")
                }
                if ok {
                    ud.set(value, forKey: lastKey)
                    ud.set(Date(), forKey: dateKey)
                    await MainActor.run { pendingInterfaceTemplateValues[target] = nil }
                    print("✅ [INPUT] Biography updated: \"\(finalText)\"")
                    // Double vibration: confirms the biography is live on real Instagram
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            if target != "note" {
                await MainActor.run {
                    pendingBioText = nil
                    completeLocalBioPostPredictionBioSend(success: false, source: "interface-bio")
                }
            } else {
                await MainActor.run { pendingBioText = nil }
            }
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

    @MainActor
    private func paintAmnesiaCarouselLocally(revealed: Bool) {
        guard amnesiaSettings.isEnabled,
              amnesiaSettings.isReady,
              amnesiaSettings.images.count >= 5 else { return }

        let mediaId = revealed ? amnesiaSettings.fullCarouselMediaId : amnesiaSettings.shortCarouselMediaId
        let oppositeMediaId = revealed ? amnesiaSettings.shortCarouselMediaId : amnesiaSettings.fullCarouselMediaId
        guard let mediaId, !mediaId.isEmpty else { return }

        let imageIndices = revealed ? [0, 1, 4, 2, 3] : [0, 1, 2, 3]
        let imageCount = imageIndices.count
        let images = imageIndices.map { amnesiaSettings.images[$0] }
        guard images.count == imageCount, images.allSatisfy({ $0 != nil }) else { return }

        let oppositeURL = oppositeMediaId.flatMap { id in
            allMediaURLs.first { url in mediaItemsByURL[url]?.mediaId == id || url.contains(id) }
        }
        let existingURL = allMediaURLs.first { url in
            mediaItemsByURL[url]?.mediaId == mediaId || url.contains(mediaId)
        }
        let fallbackURL = "amnesia://carousel/\(mediaId)/cover"
        let gridURL = existingURL ?? fallbackURL
        let insertIndex = oppositeURL.flatMap { allMediaURLs.firstIndex(of: $0) }
            ?? existingURL.flatMap { allMediaURLs.firstIndex(of: $0) }
            ?? amnesiaLocalInsertionIndex()

        if let oppositeMediaId {
            let urlsToRemove = allMediaURLs.filter { url in
                url != gridURL && (mediaItemsByURL[url]?.mediaId == oppositeMediaId || url.contains(oppositeMediaId))
            }
            for url in urlsToRemove {
                mediaItemsByURL.removeValue(forKey: url)
                cachedImages.removeValue(forKey: url)
            }
            allMediaURLs.removeAll { urlsToRemove.contains($0) }
        }
        allMediaURLs.removeAll { $0.hasPrefix("amnesia://carousel/") && $0 != gridURL }

        let childURLs = (0..<imageCount).map { "amnesia://carousel/\(mediaId)/\($0)" }
        for (index, url) in childURLs.enumerated() {
            if let image = images[index] {
                cachedImages[url] = image
            }
        }
        if let cover = images[0] {
            cachedImages[gridURL] = cover
        }

        mediaItemsByURL[gridURL] = InstagramMediaItem(
            id: mediaId,
            mediaId: mediaId,
            imageURL: gridURL,
            videoURL: nil,
            caption: nil,
            takenAt: Date(),
            likeCount: nil,
            commentCount: nil,
            mediaType: .carousel,
            carouselImageURLs: childURLs,
            ownerUsername: profile?.username
        )

        if !allMediaURLs.contains(gridURL) {
            allMediaURLs.insert(gridURL, at: min(insertIndex, allMediaURLs.count))
        }

        print("🎭 [AMNESIA] Painted local \(revealed ? "full" : "short") carousel (\(imageCount) image(s))")
    }

    /// Paints Instapick into the grid (test `instapick://` or live parent mediaId).
    /// Re-pins across Instagram refresh so new posts don't shove the carousel away.
    @MainActor
    private func paintInstapickCarouselLocally() {
        guard instapickSettings.isEnabled, instapickSettings.bundledAssetsAvailable else { return }
        let useTest = instapickSettings.isUsingLocalTestCarousel
        let useLive = instapickSettings.isLiveReady && !useTest
        guard useTest || useLive else { return }

        let images = instapickSettings.visibleCarouselImages()
        guard images.count == 5 else {
            print("🃏 [INSTAPICK] Paint skipped — expected 5 images, got \(images.count)")
            return
        }

        let mediaId = useLive
            ? (instapickSettings.visibleLiveMediaId ?? InstapickSettings.testMediaId)
            : InstapickSettings.testMediaId
        let fallbackURL = "instapick://carousel/\(mediaId)/cover"
        let existingURL = allMediaURLs.first { url in
            mediaItemsByURL[url]?.mediaId == mediaId
                || url.contains(mediaId)
                || url.hasPrefix("instapick://carousel/")
        }
        let gridURL = existingURL ?? fallbackURL
        // Prefer persisted pin so newer Instagram posts don't bury Instapick.
        if instapickSettings.gridPinIndex == nil,
           let idx = existingURL.flatMap({ allMediaURLs.firstIndex(of: $0) }) {
            instapickSettings.rememberGridPinIndex(idx)
        }
        let insertIndex = instapickSettings.gridPinIndex
            ?? existingURL.flatMap { allMediaURLs.firstIndex(of: $0) }
            ?? amnesiaLocalInsertionIndex()

        // Drop stale synthetic overlays but keep a real CDN URL if sync already found it.
        allMediaURLs.removeAll { $0.hasPrefix("instapick://carousel/") && $0 != gridURL }

        let childURLs = (0..<images.count).map { "instapick://carousel/\(mediaId)/\($0)" }
        for (index, url) in childURLs.enumerated() {
            cachedImages[url] = images[index]
        }
        cachedImages[gridURL] = images[0]

        let existingItem = mediaItemsByURL[gridURL]
        mediaItemsByURL[gridURL] = InstagramMediaItem(
            id: mediaId,
            mediaId: mediaId,
            imageURL: gridURL,
            videoURL: nil,
            caption: existingItem?.caption ?? "Instapick",
            takenAt: existingItem?.takenAt ?? Date(),
            likeCount: existingItem?.likeCount,
            commentCount: existingItem?.commentCount,
            mediaType: .carousel,
            carouselImageURLs: childURLs,
            ownerUsername: existingItem?.ownerUsername ?? profile?.username
        )

        if let idx = allMediaURLs.firstIndex(of: gridURL) {
            if idx != insertIndex {
                allMediaURLs.remove(at: idx)
                allMediaURLs.insert(gridURL, at: min(insertIndex, allMediaURLs.count))
            }
            instapickSettings.rememberGridPinIndex(min(insertIndex, allMediaURLs.count - 1))
        } else {
            let clamped = min(insertIndex, allMediaURLs.count)
            allMediaURLs.insert(gridURL, at: clamped)
            instapickSettings.rememberGridPinIndex(clamped)
        }

        print("🃏 [INSTAPICK] Painted \(useLive ? "live" : "test") carousel @\(instapickSettings.gridPinIndex ?? -1) (swapped: \(instapickSettings.swappedSlots.sorted()))")
    }

    @MainActor
    private func removeInstapickCarouselLocally() {
        instapickSettings.activeOverlaySlot = nil
        // Only strip synthetic overlays — keep the real Instagram CDN post when live.
        let removed = allMediaURLs.filter { $0.hasPrefix("instapick://") }
        allMediaURLs.removeAll { $0.hasPrefix("instapick://") }
        for url in removed {
            mediaItemsByURL.removeValue(forKey: url)
            cachedImages.removeValue(forKey: url)
        }
        mediaItemsByURL = mediaItemsByURL.filter { $0.value.mediaId != InstapickSettings.testMediaId }
        if !removed.isEmpty {
            print("🃏 [INSTAPICK] Removed local test carousel overlay")
        }
    }

    private func amnesiaLocalInsertionIndex() -> Int {
        var maxDate: Date = .distantPast
        var maxDateIndex = 0

        for (index, url) in allMediaURLs.enumerated() {
            // Skip synthetic carousel overlays; reveal:// placeholders still count for dating.
            guard !url.hasPrefix("amnesia://carousel/"),
                  !url.hasPrefix("instapick://"),
                  let date = url.hasPrefix("reveal://") ? revealDates[url] : mediaItemsByURL[url]?.takenAt else {
                continue
            }
            if date > maxDate {
                maxDate = date
                maxDateIndex = index
            }
        }

        return maxDate == .distantPast ? 0 : maxDateIndex
    }

    private func revealMediaId(from url: String) -> String? {
        guard url.hasPrefix("reveal://"), !url.hasPrefix("reveal://test-") else { return nil }
        let raw = String(url.dropFirst("reveal://".count))
        return raw.isEmpty ? nil : raw
    }

    private func mediaIdKey(_ mediaId: String) -> String {
        mediaId.split(separator: "_").first.map(String.init) ?? mediaId
    }

    private func mediaIdsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || mediaIdKey(lhs) == mediaIdKey(rhs)
    }

    private func mediaIdForGridURL(_ url: String) -> String? {
        if let revealId = revealMediaId(from: url) { return revealId }
        guard !url.hasPrefix("amnesia://carousel/"),
              !url.hasPrefix("instapick://") else { return nil }
        return mediaItemsByURL[url]?.mediaId
    }

    @MainActor
    private func removeAllGridEntries(mediaId: String, clearPersistedReveal: Bool = false) {
        let key = mediaIdKey(mediaId)
        let removedURLs = allMediaURLs.filter { url in
            guard let currentId = mediaIdForGridURL(url) else { return false }
            return mediaIdKey(currentId) == key
        }
        guard !removedURLs.isEmpty || clearPersistedReveal else {
            return
        }

        allMediaURLs.removeAll { removedURLs.contains($0) }
        for url in removedURLs {
            cachedImages.removeValue(forKey: url)
            revealDates.removeValue(forKey: url)
            mediaItemsByURL.removeValue(forKey: url)
        }
        mediaItemsByURL = mediaItemsByURL.filter { _, item in mediaIdKey(item.mediaId) != key }

        if clearPersistedReveal, let userId = profile?.userId, !userId.isEmpty {
            ProfileCacheService.shared.removeMediaEverywhere(mediaId: mediaId, userId: userId)
        }
        print("🧹 [GRID] Removed \(removedURLs.count) grid entrie(s) for mediaId=\(mediaId)")
    }

    @MainActor
    private func deduplicatedGridURLs(_ urls: [String]) -> [String] {
        var seenMediaIds = Set<String>()
        var seenURLs = Set<String>()
        var result: [String] = []
        for url in urls {
            if let mediaId = mediaIdForGridURL(url) {
                let key = mediaIdKey(mediaId)
                guard seenMediaIds.insert(key).inserted else {
                    cachedImages.removeValue(forKey: url)
                    revealDates.removeValue(forKey: url)
                    mediaItemsByURL.removeValue(forKey: url)
                    continue
                }
            } else {
                guard seenURLs.insert(url).inserted else { continue }
            }
            result.append(url)
        }
        return result
    }

    @MainActor
    private func cachedProfileURLsPreservingRevealOverlays(_ urls: [String]) -> [String] {
        var merged = urls
        let realIds = realMediaIds(in: urls)
        let currentRevealURLs = allMediaURLs.filter {
            $0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-")
        }
        guard !currentRevealURLs.isEmpty else { return urls }

        var preserved = 0
        for revealURL in currentRevealURLs {
            guard let mediaId = revealMediaId(from: revealURL) else { continue }
            let key = mediaIdKey(mediaId)
            guard !realIds.contains(mediaId), !realIds.contains(key) else { continue }
            guard !merged.contains(revealURL) else { continue }

            let targetIndex = allMediaURLs.firstIndex(of: revealURL) ?? merged.count
            merged.insert(revealURL, at: min(targetIndex, merged.count))
            preserved += 1
        }

        if preserved > 0 {
            print("⚡️ [REVEAL PRESERVE] Kept \(preserved) reveal overlay(s) during cache onChange")
        }
        return deduplicatedGridURLs(merged)
    }

    @MainActor
    private func restoredGridURLsByPositioningRevealState(
        baseURLs: [String],
        revealURLs: [String],
        storedDates: [String: Date]
    ) -> [String] {
        let pendingRevealURLs = revealURLs.filter { !baseURLs.contains($0) }
        guard !pendingRevealURLs.isEmpty else { return baseURLs }

        var dateByURL = storedDates
        for revealURL in pendingRevealURLs where dateByURL[revealURL] == nil {
            guard let mediaId = revealMediaId(from: revealURL),
                  let uploadDate = revealUploadDate(for: mediaId) else { continue }
            dateByURL[revealURL] = uploadDate
        }

        let positionedRevealURLs = pendingRevealURLs.filter { dateByURL[$0] != nil }
        let fallbackRevealURLs = pendingRevealURLs.filter { dateByURL[$0] == nil }
        revealDates.merge(dateByURL.filter { pendingRevealURLs.contains($0.key) }) { _, new in new }

        if let minRevealDate = positionedRevealURLs.compactMap({ dateByURL[$0] }).min(),
           let maxRevealDate = positionedRevealURLs.compactMap({ dateByURL[$0] }).max(),
           minRevealDate < maxRevealDate {
            let realPostInside = baseURLs.contains { url in
                guard !ProfileMediaReconciler.isOverlayURL(url),
                      let d = mediaItemsByURL[url]?.takenAt else { return false }
                return d > minRevealDate && d < maxRevealDate
            }
            if realPostInside {
                var merged = baseURLs
                func itemDate(for url: String) -> Date? {
                    if url.hasPrefix("reveal://") { return dateByURL[url] ?? revealDates[url] }
                    return mediaItemsByURL[url]?.takenAt
                }
                func insertIndex(for date: Date, in urls: [String]) -> Int {
                    var maxDate: Date = .distantPast
                    var maxDateIndex = 0
                    for (i, url) in urls.enumerated() {
                        guard let d = itemDate(for: url) else { continue }
                        if d > maxDate {
                            maxDate = d
                            maxDateIndex = i
                        }
                    }
                    let pinnedEnd = maxDate == .distantPast ? 0 : maxDateIndex
                    for i in pinnedEnd..<urls.count {
                        guard let d = itemDate(for: urls[i]) else { continue }
                        if d <= date { return i }
                    }
                    return urls.count
                }
                for revealURL in positionedRevealURLs {
                    guard let d = dateByURL[revealURL] else { continue }
                    merged.removeAll { $0 == revealURL }
                    merged.insert(revealURL, at: min(insertIndex(for: d, in: merged), merged.count))
                }
                if !fallbackRevealURLs.isEmpty {
                    merged.insert(contentsOf: fallbackRevealURLs, at: min(1, merged.count))
                }
                print("💾 [REVEAL] Restored \(pendingRevealURLs.count) non-contiguous reveal URL(s) by individual date")
                return deduplicatedGridURLs(merged)
            }
        }

        guard let anchorDate = positionedRevealURLs.compactMap({ dateByURL[$0] }).max() else {
            var fallback = baseURLs
            let insertAt = min(1, fallback.count)
            fallback.insert(contentsOf: pendingRevealURLs, at: insertAt)
            print("💾 [REVEAL] Restored \(pendingRevealURLs.count) reveal URL(s) at safe fallback pos \(insertAt)")
            return fallback
        }

        var maxDate: Date = .distantPast
        var maxDateIndex = 0
        for (i, url) in baseURLs.enumerated() {
            guard let date = mediaItemsByURL[url]?.takenAt else { continue }
            if date > maxDate {
                maxDate = date
                maxDateIndex = i
            }
        }
        let pinnedEnd = maxDate == .distantPast ? 0 : maxDateIndex

        var insertAt = baseURLs.count
        for i in pinnedEnd..<baseURLs.count {
            guard let itemDate = mediaItemsByURL[baseURLs[i]]?.takenAt else { continue }
            if itemDate <= anchorDate {
                insertAt = i
                break
            }
        }

        var merged = baseURLs
        merged.insert(contentsOf: positionedRevealURLs, at: min(insertAt, merged.count))
        if !fallbackRevealURLs.isEmpty {
            let fallbackIndex = min(insertAt + positionedRevealURLs.count, merged.count)
            merged.insert(contentsOf: fallbackRevealURLs, at: fallbackIndex)
        }
        print("💾 [REVEAL] Positioned restored reveal block at pos \(insertAt) (count:\(pendingRevealURLs.count), pinnedEnd:\(pinnedEnd))")
        return deduplicatedGridURLs(merged)
    }

    @MainActor
    private func applyAuthoritativeMediaSnapshot(
        items: [InstagramMediaItem],
        nextCursor: String?,
        source: String,
        clearRevealState: Bool
    ) {
        var seen = Set<String>()
        var snapshotItems: [InstagramMediaItem] = []
        for item in items {
            let key = item.mediaId.isEmpty ? item.imageURL : mediaIdKey(item.mediaId)
            guard seen.insert(key).inserted else { continue }
            snapshotItems.append(item)
        }

        // Bridge already-loaded thumbnails from their OLD url keys to the NEW snapshot
        // url keys by stable mediaId BEFORE we rebuild mediaItemsByURL. CDN URLs rotate
        // every refresh, so without this the filter below would drop every thumbnail and
        // the whole grid would flash gray until re-download.
        var imagesByMediaId: [String: UIImage] = [:]
        for (url, image) in cachedImages {
            if let oldItem = mediaItemsByURL[url], !oldItem.mediaId.isEmpty {
                imagesByMediaId[mediaIdKey(oldItem.mediaId)] = image
            } else if url.hasPrefix("reveal://") {
                let id = String(url.dropFirst("reveal://".count))
                if !id.isEmpty { imagesByMediaId[mediaIdKey(id)] = image }
            }
        }

        mediaItemsByURL.removeAll()
        for item in snapshotItems {
            mediaItemsByURL[item.imageURL] = item
        }

        let snapshotURLs = snapshotItems.map(\.imageURL)
        // Re-key bridged images onto the new snapshot URLs so they survive the filter.
        for item in snapshotItems where cachedImages[item.imageURL] == nil {
            guard !item.mediaId.isEmpty, let bridged = imagesByMediaId[mediaIdKey(item.mediaId)] else { continue }
            cachedImages[item.imageURL] = bridged
            ProfileCacheService.shared.saveImage(bridged, forURL: item.imageURL)
            ProfileCacheService.shared.saveImage(bridged, forMediaId: item.mediaId)
        }

        let removedRevealCount = allMediaURLs.filter { $0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }.count
        allMediaURLs = snapshotURLs
        revealDates.removeAll()
        cachedImages = cachedImages.filter { key, _ in snapshotURLs.contains(key) || key == profile?.profilePicURL }
        nextMaxId = nextCursor
        hasMorePages = nextCursor != nil && snapshotURLs.count < maxPhotosOwnProfile

        if let userId = profile?.userId, clearRevealState {
            ProfileCacheService.shared.clearRevealState(userId: userId)
        }
        // Use authoritative replacement so archived posts are not re-introduced via tail merge.
        ProfileCacheService.shared.replaceMediaURLsAndItems(snapshotURLs, items: snapshotItems)
        print("✅ [GRID AUTH] \(source): applied \(snapshotURLs.count) Instagram item(s), cleared \(removedRevealCount) reveal overlay(s)")
    }

    private func realMediaIds(in urls: [String]? = nil) -> Set<String> {
        let sourceURLs = urls ?? allMediaURLs
        var ids = Set<String>()
        for url in sourceURLs {
            guard !url.hasPrefix("reveal://"),
                  !url.hasPrefix("amnesia://carousel/"),
                  let mediaId = mediaItemsByURL[url]?.mediaId,
                  !mediaId.isEmpty else { continue }
            ids.insert(mediaId)
            ids.insert(mediaIdKey(mediaId))
        }
        return ids
    }

    private func removeRevealURLIfRealPostExists(_ url: String, realIds: Set<String>? = nil) -> Bool {
        guard let mediaId = revealMediaId(from: url) else { return false }
        let ids = realIds ?? realMediaIds()
        guard ids.contains(mediaId) || ids.contains(mediaIdKey(mediaId)) else { return false }
        allMediaURLs.removeAll { $0 == url }
        cachedImages.removeValue(forKey: url)
        revealDates.removeValue(forKey: url)
        mediaItemsByURL.removeValue(forKey: url)
        return true
    }

    private func persistCurrentRevealState() {
        guard let userId = profile?.userId, !userId.isEmpty else { return }
        let currentRealIds = realMediaIds()
        // The reveal:// overlays currently in `allMediaURLs` ARE the source of truth for
        // what's revealed on screen. We must NOT gate persistence on the SetPhoto's
        // `isArchived` flag: the pre-insert persist runs BEFORE the unarchive flips that
        // flag to false, so filtering on it would drop every overlay and clearRevealState()
        // would wipe the just-revealed posts — they'd vanish on the next Performance entry
        // (exactly what happened when the post-reveal silent refresh failed on a budget
        // block). A re-archived post is removed from `allMediaURLs` directly, so it can
        // never linger here.
        let revealURLs = allMediaURLs.filter { url in
            guard let mediaId = revealMediaId(from: url) else { return false }
            return !currentRealIds.contains(mediaId) && !currentRealIds.contains(mediaIdKey(mediaId))
        }
        guard !revealURLs.isEmpty else {
            ProfileCacheService.shared.clearRevealState(userId: userId)
            return
        }

        let revealSet = Set(revealURLs)
        let dates = revealDates.filter { revealSet.contains($0.key) }
        ProfileCacheService.shared.saveRevealState(urls: revealURLs, dates: dates, userId: userId)
    }

    private func clearLocalRevealPlaceholders(userId: String? = nil) {
        let revealURLs = allMediaURLs.filter { $0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }
        guard !revealURLs.isEmpty else {
            if let userId {
                ProfileCacheService.shared.clearRevealState(userId: userId)
            }
            return
        }

        allMediaURLs.removeAll { revealURLs.contains($0) }
        for url in revealURLs {
            cachedImages.removeValue(forKey: url)
            revealDates.removeValue(forKey: url)
            mediaItemsByURL.removeValue(forKey: url)
        }
        if let userId {
            ProfileCacheService.shared.clearRevealState(userId: userId)
        }
        print("💾 [REVEAL] Cleared \(revealURLs.count) local reveal placeholder(s)")
    }

    private func reconcileArchivedStateForClearedReveals(_ revealIds: Set<String>, visibleMediaIds: Set<String>) {
        guard !revealIds.isEmpty else { return }
        let visiblePkOnly = Set(visibleMediaIds.map { $0.split(separator: "_").first.map(String.init) ?? $0 })
        for set in DataManager.shared.sets {
            for photo in set.photos {
                guard let mediaId = photo.mediaId,
                      !photo.isArchived,
                      revealIds.contains(mediaId) || revealIds.contains(mediaId.split(separator: "_").first.map(String.init) ?? mediaId) else {
                    continue
                }
                let pkOnly = mediaId.split(separator: "_").first.map(String.init) ?? mediaId
                guard !visibleMediaIds.contains(mediaId), !visiblePkOnly.contains(pkOnly) else { continue }
                DataManager.shared.updatePhoto(
                    photoId: photo.id,
                    mediaId: mediaId,
                    isArchived: true,
                    uploadStatus: .completed,
                    errorMessage: nil,
                    uploadDate: photo.uploadDate
                )
                ProfileCacheService.shared.removeMediaEverywhere(mediaId: mediaId, userId: profile?.userId)
                print("🔄 [REVEAL] Reconciled \(mediaId) as archived after manual refresh")
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

            // Start from the cached posts, then re-inject any persisted reveal://
            // URLs so unarchived photos survive app restarts.
            var restoredURLs = cached.cachedMediaURLs
            for item in cached.cachedMediaItems {
                mediaItemsByURL[item.imageURL] = item
            }
            if let revealState = ProfileCacheService.shared.loadRevealState(userId: cached.userId) {
                let visibleCachedURLs = Set(cached.cachedMediaURLs)
                let cachedRealIds = Set(cached.cachedMediaItems.compactMap { item in
                    visibleCachedURLs.contains(item.imageURL) ? item.mediaId : nil
                })
                let filteredRevealURLs = revealState.urls.filter { url in
                    guard let mediaId = revealMediaId(from: url) else { return false }
                    return !cachedRealIds.contains(mediaId)
                }
                let filteredRevealSet = Set(filteredRevealURLs)
                revealDates.merge(revealState.dates.filter { filteredRevealSet.contains($0.key) }) { _, new in new }
                restoredURLs = restoredGridURLsByPositioningRevealState(
                    baseURLs: restoredURLs,
                    revealURLs: filteredRevealURLs,
                    storedDates: revealState.dates
                )
                if filteredRevealURLs.count != revealState.urls.count {
                    ProfileCacheService.shared.saveRevealState(urls: filteredRevealURLs, dates: revealDates, userId: cached.userId)
                }
                print("💾 [REVEAL] Restored \(filteredRevealURLs.count)/\(revealState.urls.count) reveal URL(s) from disk")
            }
            self.allMediaURLs = restoredURLs

            // Restore pagination state: if a previous session confirmed there are no
            // more pages (all posts loaded), don't re-fetch page 1 from the API.
            let noMorePagesKey = "perf_no_more_pages_\(cached.userId)"
            let allPagesCached = UserDefaults.standard.bool(forKey: noMorePagesKey)
            self.nextMaxId = cached.cachedNextMaxId
            let expectedCachedCount = cached.mediaCount > 0
                ? min(cached.mediaCount, maxPhotosOwnProfile)
                : maxPhotosOwnProfile
            let noMoreFlagLooksTrustworthy = allPagesCached && cached.cachedMediaURLs.count >= expectedCachedCount
            // If a cursor exists, trust it even if an old session accidentally set
            // the "no more pages" flag. Otherwise users can get stuck at page 1.
            self.hasMorePages = cached.cachedNextMaxId != nil || (!noMoreFlagLooksTrustworthy && cached.cachedMediaURLs.count < maxPhotosOwnProfile)
            if noMoreFlagLooksTrustworthy && cached.cachedNextMaxId == nil {
                print("📦 [CACHE] All pages already loaded — pagination disabled until next refresh")
            } else if let cursor = cached.cachedNextMaxId {
                print("📦 [CACHE] Restored pagination cursor \(cursor.prefix(12))…")
            } else if allPagesCached {
                print("📦 [CACHE] Ignored stale no-more-pages flag — cached \(cached.cachedMediaURLs.count)/\(expectedCachedCount)")
            }

            // Build mediaItemsByURL in O(n) using a dictionary keyed by imageURL.
            // Drop stale CDN entries; preserve reveal:// (local-only placeholders).
            let activeURLs = Set(cached.cachedMediaURLs)
            mediaItemsByURL = mediaItemsByURL.filter { key, _ in
                activeURLs.contains(key)
                    || key.hasPrefix("reveal://")
                    || key.hasPrefix("amnesia://carousel/")
                    || key.hasPrefix("instapick://")
            }
            for item in cached.cachedMediaItems + cached.cachedTaggedItems { mediaItemsByURL[item.imageURL] = item }
            persistExistingImagesByMediaId(cached.cachedMediaItems + cached.cachedReelItems + cached.cachedTaggedItems)
            paintAmnesiaCarouselLocally(revealed: amnesiaSettings.isRevealed)
            paintInstapickCarouselLocally()

            loadCachedImages()
            warmSecondaryTabImagesFromDisk(for: cached)

            // Do not auto-fetch secondary tabs from a normal cache entry. Performance
            // must be visually stable and zero-API on entry; Reels/Tagged/Highlights
            // lazy-load only when their tabs are opened, or during first-time/manual sync.

            // No automatic entry refresh. The profile is fully cached on disk
            // (photos in Application Support, never purged). The user refreshes
            // manually when they need to pick up changes made on Instagram directly.
            // Exception: fire ONE refresh when the cached header is broken
            // (empty username/pic) so the view never shows a blank profile.
            let headerMissing = cached.username.isEmpty || cached.profilePicURL.isEmpty
            let zeroStats     = cached.followerCount == 0 && cached.followingCount == 0 && cached.mediaCount == 0
            if headerMissing || zeroStats {
                if allowRemote
                    && !instagram.shouldUseCacheOnlyForOptionalCalls
                    && !instagram.isSessionChallenged {
                    print("📦 [CACHE] Cached header broken — single recovery refresh")
                    loadProfileSync(source: "entry")
                }
            } else {
                print("📦 [CACHE] Entry refresh skipped — using cached profile (manual refresh only)")
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

    /// Counter Glitch + Transfer Effect helper. When both are enabled, the magician
    /// needs the own profile's follower/following numbers to be live before the trick.
    /// This fires ONE header refresh on entry so they don't have to tap Refresh first.
    /// It respects every anti-bot gate (rate budget, SafetyGate, throttle), so it can
    /// only fire as often as a manual refresh would. Skipped while an offset transfer
    /// is mid-flight (transferOffset != 0) to avoid a count flicker right before the reveal.
    @MainActor
    private func maybeAutoRefreshCountsForTransferEffect() {
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Transfer count auto-refresh skipped during Bio + PP queue")
            return
        }
        let magic = FollowingMagicSettings.shared
        guard magic.isEnabled, magic.transferEnabled, magic.transferOffset == 0 else { return }
        guard !instagram.isUploadingProfilePic,
              !uploadManager.isActive,
              !didAutoPauseUpload,
              !instagram.isSessionChallenged else { return }
        print("🎩 [MAGIC] Transfer Effect active — auto-refreshing counts on entry")
        LogManager.shared.info("Counter Glitch transfer: auto-refresh counts on entry", category: .profile)
        loadProfileSync(source: "entry")
    }

    // MARK: - First-time full preload

    /// Returns the logged-in user's Instagram numeric id (from the Keychain session).
    private func currentSessionUserId() -> String {
        KeychainService.shared.loadSession()?.userId ?? (profile?.userId ?? "")
    }

    /// Decides whether the blocking first-time preload should run for this account.
    /// - Runs only when there is no "fully preloaded" flag AND no complete-enough cache.
    /// - Existing accounts that already have a populated cache (e.g. users updating
    ///   the app) are migrated silently: the flag is set and the spinner is skipped.
    private func shouldRunFirstTimePreload(userId: String) -> Bool {
        guard !userId.isEmpty else { return false }
        // Don't preload if remote calls aren't possible right now.
        guard instagram.isLoggedIn,
              !instagram.isLocked,
              !instagram.isSessionChallenged,
              !instagram.shouldUseCacheOnlyForOptionalCalls else { return false }

        let key = "perf_fully_preloaded_\(userId)"
        if UserDefaults.standard.bool(forKey: key) { return false }

        // Migration: only mark complete when the existing cache has a real tail.
        // A clean install often starts with exactly Instagram's first 12 posts;
        // treating that as "fully preloaded" makes refresh collapse back to 12.
        if let cached = ProfileCacheService.shared.loadProfile(),
           cached.userId == userId,
           hasCompleteFirstTimePreloadCache(cached, userId: userId) {
            UserDefaults.standard.set(true, forKey: key)
            print("📦 [PRELOAD] Complete cache detected — marked preloaded, skipping spinner")
            return false
        }
        return true
    }

    private func requiredFirstTimePreloadPosts(for cached: InstagramProfile) -> Int {
        ProfileCacheService.shared.requiredPerformancePreloadPosts(
            for: cached,
            targetPosts: preloadTargetPosts,
            maxPosts: maxPhotosOwnProfile
        )
    }

    private func hasCompleteFirstTimePreloadCache(_ cached: InstagramProfile, userId: String) -> Bool {
        ProfileCacheService.shared.hasCompletePerformancePreloadCache(
            cached,
            userId: userId,
            targetPosts: preloadTargetPosts,
            maxPosts: maxPhotosOwnProfile
        )
    }

    private func hasCriticalPreloadCache(userId: String) -> Bool {
        guard let cached = ProfileCacheService.shared.loadProfile(),
              cached.userId == userId else { return false }
        return !cached.cachedMediaURLs.isEmpty
    }

    private func continueIncompletePerformancePreload(userId: String) async {
        let snapshot = ProfileCacheService.shared.performancePreloadSnapshot(userId: userId)
        print("📦 [PRELOAD] Continue start — \(snapshot)")
        LogManager.shared.info("Performance continue preload start: \(snapshot)", category: .general)
        guard let cached = ProfileCacheService.shared.loadProfile(), cached.userId == userId else {
            print("📦 [PRELOAD] No same-user cache — starting first-time preload from scratch")
            await runFirstTimePreload(userId: userId)
            return
        }

        if hasCompleteFirstTimePreloadCache(cached, userId: userId) {
            // Posts already cached — show overlay and run only the optional stage.
            print("📦 [PRELOAD] Posts complete — continuing optional preload only (blocking)")
            withAnimation(.easeIn(duration: 0.2)) {
                isFirstTimePreloading = true
                preloadFailed = false
            }
            firstTimePreloadStartedAt = Date()
            preloadProgress = "Loading highlights, reels and tagged posts…"

            // Wait out the cold-start API lockdown window (max 50 s) so API calls are allowed.
            if InstagramSafetyGate.shared.isInColdStartWindow {
                preloadProgress = "Waiting for Instagram safety window…"
                var waited = 0
                while InstagramSafetyGate.shared.isInColdStartWindow, waited < 50 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    waited += 2
                }
                preloadProgress = "Loading highlights, reels and tagged posts…"
            }

            UserDefaults.standard.set(true, forKey: "perf_fully_preloaded_\(userId)")
            UserDefaults.standard.set(false, forKey: "perf_optional_preloaded_\(userId)")
            checkAndLoadProfile(allowRemote: false)

            let optionalComplete = await runFirstTimeOptionalPreloadNow(profile: cached, userId: userId)
            if optionalComplete {
                firstTimePreloadStartedAt = nil
                withAnimation(.easeOut(duration: 0.3)) { isFirstTimePreloading = false }
                print("✅ [PRELOAD] Optional-only continue finished for \(userId)")
            } else {
                // Posts are already complete. Optional tabs can be lazy-loaded when
                // opened, so do not flip the whole profile back to "incomplete" and
                // show a red Continue button that may appear to do nothing.
                UserDefaults.standard.set(true, forKey: "perf_fully_preloaded_\(userId)")
                preloadProgress = ""
                withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
                print("⚠️ [PRELOAD] Optional-only continue incomplete for \(userId)")
            }
        } else {
            // Posts incomplete but we have a cached cursor — resume from where we stopped
            // rather than re-fetching the full profile from scratch (which wastes 2 feedUserRead
            // budget slots before even reaching the next page).
            let canResume = (cached.cachedNextMaxId != nil)
                && !cached.cachedMediaItems.isEmpty
            if canResume {
                print("📦 [PRELOAD] Route: resume from cursor")
                await resumePostsPaginationFromCache(cached: cached, userId: userId)
            } else {
                print("📦 [PRELOAD] Route: restart first-time preload")
                await runFirstTimePreload(userId: userId)
            }
        }
    }

    /// Resumes posts pagination from the cursor already saved in the profile cache.
    /// Only makes calls to /feed/user/ for the pages we haven't fetched yet — avoids
    /// re-fetching the profile header and page 1 that were already loaded.
    @MainActor
    private func resumePostsPaginationFromCache(cached: InstagramProfile, userId: String) async {
        withAnimation(.easeIn(duration: 0.2)) {
            isFirstTimePreloading = true
            preloadFailed = false
        }
        firstTimePreloadStartedAt = Date()
        preloadProgress = String(localized: "preload.posts")

        do {
            var working = cached
            var items   = working.cachedMediaItems
            var cursor  = working.cachedNextMaxId
            let requiredPosts = requiredFirstTimePreloadPosts(for: working)
            var calls = 0
            var safetyRetries = 0
            let maxPageCalls = 5
            let deadline = Date().addingTimeInterval(12 * 60)
            var exitReason = "unknown"

            while items.count < requiredPosts, calls < maxPageCalls, cursor != nil, Date() < deadline {
                // Human-like pacing between pages.
                try await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000...7_000_000_000))

                // Check gate before calling. Continue waits through long feed windows so
                // the red button can genuinely finish the first-time load when possible.
                var feedDecision = InstagramSafetyGate.shared.decision(for: .feedUserRead)
                while !feedDecision.allowed, Date() < deadline {
                    print("📦 [PRELOAD-RESUME] Waiting \(feedDecision.waitSeconds)s for feed slot (total \(items.count)/\(requiredPosts))")
                    let chunk = UInt64(min(max(1, feedDecision.waitSeconds), 2))
                    try await Task.sleep(nanoseconds: chunk * 1_000_000_000)
                    feedDecision = InstagramSafetyGate.shared.decision(for: .feedUserRead)
                }
                if Date() >= deadline, !feedDecision.allowed {
                    exitReason = "budget_deadline"
                    print("📦 [PRELOAD-RESUME] Deadline reached while feedUserRead blocked — saving \(items.count) post(s)")
                    break
                }

                do {
                    let (page, next) = try await instagram.getUserMediaItems(
                        userId: userId, amount: 21, maxId: cursor)
                    calls += 1
                    safetyRetries = 0
                    let existingIds = Set(items.map { $0.mediaId })
                    let fresh = page.filter { !$0.mediaId.isEmpty && !existingIds.contains($0.mediaId) }
                    items += fresh
                    cursor = next
                    working.cachedMediaItems = items
                    working.cachedMediaURLs  = items.map { $0.imageURL }
                    working.cachedNextMaxId  = cursor
                    ProfileCacheService.shared.saveProfile(working)
                    self.profile = working
                    print("📦 [PRELOAD-RESUME] Page \(calls) cached \(fresh.count) fresh post(s), total \(items.count)/\(requiredPosts)")
                    if next == nil { break }
                } catch {
                    let msg = error.localizedDescription
                    if msg.localizedCaseInsensitiveContains("Safety pause"), safetyRetries < 3 {
                        safetyRetries += 1
                        let wait = 12 + (safetyRetries * 4)
                        print("📦 [PRELOAD-RESUME] Safety pause retry \(safetyRetries)/3 in \(wait)s")
                        try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                        continue
                    }
                    print("📦 [PRELOAD-RESUME] Stopped: \(msg)")
                    exitReason = "error:\(msg)"
                    break
                }
            }

            // Persist completion state
            let complete = cursor == nil || items.count >= requiredPosts
            UserDefaults.standard.set(complete, forKey: "perf_fully_preloaded_\(userId)")
            if cursor == nil { UserDefaults.standard.set(true, forKey: "perf_no_more_pages_\(userId)") }
            if complete {
                exitReason = cursor == nil ? "complete_no_more_pages" : "complete_target"
            } else if exitReason == "unknown" {
                exitReason = Date() >= deadline ? "deadline" : (calls >= maxPageCalls ? "max_pages" : "partial_unknown")
            }
            ProfileCacheService.shared.recordPerformancePreloadExit(
                reason: exitReason,
                userId: userId,
                cachedCount: items.count,
                requiredCount: requiredPosts,
                context: "resume calls=\(calls)"
            )
            print("📦 [PRELOAD-RESUME] \(complete ? "Complete" : "Partial") reason=\(exitReason) — \(items.count)/\(requiredPosts) posts")

            checkAndLoadProfile(allowRemote: false)
            firstTimePreloadStartedAt = nil
            withAnimation(.easeOut(duration: 0.3)) { isFirstTimePreloading = false }

            if !complete {
                withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
            } else {
                scheduleFirstTimeOptionalPreload(profile: working, userId: userId)
            }
        } catch {
            print("📦 [PRELOAD-RESUME] Failed: \(error.localizedDescription)")
            firstTimePreloadStartedAt = nil
            withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
        }
    }

    @MainActor
    private func recoverFirstTimePreloadAfterForegroundIfNeeded() {
        guard isFirstTimePreloading else { return }
        let userId = currentSessionUserId()
        if let cached = ProfileCacheService.shared.loadProfile(),
           hasCompleteFirstTimePreloadCache(cached, userId: userId) {
            UserDefaults.standard.set(true, forKey: "perf_fully_preloaded_\(userId)")
            firstTimePreloadStartedAt = nil
            preloadFailed = false
            preloadProgress = ""
            withAnimation(.easeOut(duration: 0.25)) { isFirstTimePreloading = false }
            checkAndLoadProfile(allowRemote: false)
            if let cached = ProfileCacheService.shared.loadProfile() {
                scheduleFirstTimeOptionalPreload(profile: cached, userId: userId)
            }
            LogManager.shared.info("First-time preload recovered from cached critical data after foreground", category: .general)
            return
        }

        if let started = firstTimePreloadStartedAt,
           Date().timeIntervalSince(started) > 60 {
            preloadProgress = ""
            withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
            LogManager.shared.warning("First-time preload timed out after foreground without critical cache", category: .general)
        }
    }

    @MainActor
    private func canRunOptionalFirstTimePreload(stage: String) -> Bool {
        guard scenePhase == .active,
              UIApplication.shared.applicationState == .active,
              !InstagramSafetyGate.shared.isInColdStartWindow,
              !instagram.shouldUseCacheOnlyForOptionalCalls else {
            LogManager.shared.info("First-time optional preload skipped/deferred: \(stage) not safe", category: .general)
            return false
        }

        let rate = instagram.checkRateLimit()
        guard rate.remaining > 12 else {
            LogManager.shared.warning("First-time optional preload skipped: \(stage) low API budget (\(rate.actionsUsed)/55)", category: .general)
            return false
        }
        return true
    }

    /// One-time, sequential, human-paced preload of the critical profile surface.
    /// Optional tabs continue in the background so first install cannot get stuck
    /// waiting for reels/tagged/highlights/Explore.
    @MainActor
    private func runFirstTimePreload(userId: String) async {
        guard !userId.isEmpty else { return }
        withAnimation(.easeIn(duration: 0.2)) {
            isFirstTimePreloading = true
            preloadFailed = false
        }
        firstTimePreloadStartedAt = Date()
        preloadProgress = String(localized: "preload.profile")

        do {
            try await instagram.waitForNetworkStability()

            // 1) Header + first page of posts (1 call).
            guard var working = try await instagram.getProfileInfo() else {
                throw PreloadError.noProfile
            }

            // 2) Paginate posts up to the target, human-paced.
            preloadProgress = String(localized: "preload.posts")
            var items = working.cachedMediaItems
            var cursor = working.cachedNextMaxId
            let requiredPosts = requiredFirstTimePreloadPosts(for: working)
            var calls = 0
            var safetyRetries = 0
            let maxPageCalls = 5
            let deadline = Date().addingTimeInterval(12 * 60)
            var exitReason = "unknown"
            while items.count < requiredPosts, calls < maxPageCalls, Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...8_000_000_000))
                do {
                    var feedDecision = InstagramSafetyGate.shared.decision(for: .feedUserRead)
                    while !feedDecision.allowed, Date() < deadline {
                        print("📦 [PRELOAD] Waiting \(feedDecision.waitSeconds)s for feed slot before page \(calls + 1) (total \(items.count)/\(requiredPosts))")
                        let chunk = UInt64(min(max(1, feedDecision.waitSeconds), 2))
                        try await Task.sleep(nanoseconds: chunk * 1_000_000_000)
                        feedDecision = InstagramSafetyGate.shared.decision(for: .feedUserRead)
                    }
                    if Date() >= deadline, !feedDecision.allowed {
                        exitReason = "budget_deadline"
                        print("📦 [PRELOAD] Deadline reached while feedUserRead blocked — saving \(items.count) post(s)")
                        break
                    }
                    // Some profile header responses include the first page but omit the
                    // pagination cursor. In that case, re-read page 1 once to discover
                    // its next cursor, then continue to page 2 instead of stopping at 12.
                    let requestedMaxId = cursor
                    let (page, next) = try await instagram.getUserMediaItems(
                        userId: working.userId, amount: 21, maxId: requestedMaxId
                    )
                    calls += 1
                    safetyRetries = 0
                    let existingIds = Set(items.map { $0.mediaId })
                    let fresh = page.filter { !$0.mediaId.isEmpty && !existingIds.contains($0.mediaId) }
                    items += fresh
                    cursor = next
                    print("📦 [PRELOAD] Page \(calls) cached \(fresh.count) fresh post(s), total \(items.count)")
                    if next == nil {
                        break
                    }
                    if requestedMaxId == nil && fresh.isEmpty {
                        print("📦 [PRELOAD] Recovered missing cursor from duplicated first page; continuing with next page")
                    }
                } catch {
                    let message = error.localizedDescription
                    if message.localizedCaseInsensitiveContains("Safety pause"), safetyRetries < 3 {
                        safetyRetries += 1
                        let wait = 12 + (safetyRetries * 4)
                        print("📦 [PRELOAD] Safety pause during pagination — retry \(safetyRetries)/3 in \(wait)s")
                        LogManager.shared.warning("First-time preload pagination paused by SafetyGate; retrying in \(wait)s", category: .general)
                        try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                        continue
                    }
                    LogManager.shared.warning("First-time preload pagination skipped: \(error.localizedDescription)", category: .general)
                    exitReason = "error:\(error.localizedDescription)"
                    break
                }
            }
            working.cachedMediaURLs = items.map { $0.imageURL }
            working.cachedMediaItems = items
            working.cachedNextMaxId = cursor

            // Persist the post metadata now so images can be keyed against it.
            ProfileCacheService.shared.saveProfile(working)
            self.profile = working

            // 3) Download all cached post thumbnails before letting the user in.
            preloadProgress = String(localized: "preload.images")
            for item in items {
                if cachedImages[item.imageURL] != nil { continue }
                if let cached = ProfileCacheService.shared.loadImage(forURL: item.imageURL)
                    ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) {
                    cachedImages[item.imageURL] = cached
                    ProfileCacheService.shared.saveImage(cached, forMediaId: item.mediaId)
                    continue
                }
                if let img = await downloadImage(from: item.imageURL) {
                    cachedImages[item.imageURL] = img
                    ProfileCacheService.shared.saveImage(img, forURL: item.imageURL)
                    ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                }
            }

            // 4) Profile picture.
            if !working.profilePicURL.isEmpty, cachedImages[working.profilePicURL] == nil,
               let pic = await downloadImage(from: working.profilePicURL) {
                cachedImages[working.profilePicURL] = pic
                ProfileCacheService.shared.saveImage(pic, forURL: working.profilePicURL)
                ProfileCacheService.shared.saveOwnProfilePic(pic, cdnURL: working.profilePicURL)
            }

            // Remember whether all pages are already loaded so pagination won't
            // re-fetch page 1 in later sessions.
            if cursor == nil {
                UserDefaults.standard.set(true, forKey: "perf_no_more_pages_\(userId)")
            }

            // Stamp refresh timestamps so the manual-refresh throttle starts fresh.
            let now = Date().timeIntervalSince1970
            lastRefreshTimestamp = now
            lastAutoRefreshTimestamp = now

            // Mark fully preloaded when we have enough posts OR have exhausted all pages.
            // Note: calls == 0 is valid — the first page can already satisfy requiredPosts.
            let preloadComplete = cursor == nil || items.count >= requiredPosts
            UserDefaults.standard.set(preloadComplete, forKey: "perf_fully_preloaded_\(userId)")
            UserDefaults.standard.set(false, forKey: "perf_optional_preloaded_\(userId)")
            if preloadComplete {
                exitReason = cursor == nil ? "complete_no_more_pages" : "complete_target"
            } else if exitReason == "unknown" {
                exitReason = Date() >= deadline ? "deadline" : (calls >= maxPageCalls ? "max_pages" : "partial_unknown")
            }
            ProfileCacheService.shared.recordPerformancePreloadExit(
                reason: exitReason,
                userId: userId,
                cachedCount: items.count,
                requiredCount: requiredPosts,
                context: "performance_first_time calls=\(calls)"
            )
            print("✅ [PRELOAD] Critical first-time preload \(preloadComplete ? "complete" : "partial") reason=\(exitReason) for \(userId) — \(items.count)/\(requiredPosts) posts cached")
            LogManager.shared.info("First-time critical preload complete: \(items.count) posts", category: .general)

            // 5) Critical posts are loaded. Open Performance immediately; optional content
            // (highlights, reels, tagged) loads in the background. A banner appears if it
            // doesn't complete before the user switches to those tabs.
            if preloadComplete {
                firstTimePreloadStartedAt = nil
                withAnimation(.easeOut(duration: 0.3)) { isFirstTimePreloading = false }
                checkAndLoadProfile(allowRemote: false)
                scheduleFirstTimeOptionalPreload(profile: working, userId: userId)
                print("✅ [PRELOAD] Overlay dismissed — optional preload scheduled in background")
                LogManager.shared.info("First-time preload: overlay dismissed, optional loading in background", category: .general)
            } else {
                // Not enough posts (may have been interrupted). Show retry.
                UserDefaults.standard.set(false, forKey: "perf_fully_preloaded_\(userId)")
                preloadProgress = "Profile cache incomplete. Tap Retry to continue loading."
                withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
                print("⚠️ [PRELOAD] Critical preload incomplete — showing retry")
                LogManager.shared.warning("First-time preload incomplete: showing retry state", category: .general)
            }
        } catch {
            print("❌ [PRELOAD] Failed: \(error.localizedDescription)")
            LogManager.shared.warning("First-time preload failed: \(error.localizedDescription)", category: .general)
            if hasCriticalPreloadCache(userId: userId) {
                if let cached = ProfileCacheService.shared.loadProfile(),
                   hasCompleteFirstTimePreloadCache(cached, userId: userId) {
                    UserDefaults.standard.set(true, forKey: "perf_fully_preloaded_\(userId)")
                } else {
                    UserDefaults.standard.set(false, forKey: "perf_fully_preloaded_\(userId)")
                }
                firstTimePreloadStartedAt = nil
                preloadProgress = ""
                preloadFailed = false
                withAnimation(.easeOut(duration: 0.25)) { isFirstTimePreloading = false }
                checkAndLoadProfile(allowRemote: false)
                LogManager.shared.info("First-time preload failed after critical cache; entering Performance cache-only", category: .general)
                return
            }
            preloadProgress = ""
            withAnimation(.easeIn(duration: 0.2)) { preloadFailed = true }
        }
    }

    @MainActor
    private func scheduleFirstTimeOptionalPreload(profile working: InstagramProfile, userId: String) {
        firstTimeOptionalPreloadTask?.cancel()
        firstTimeOptionalPreloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            for attempt in 1...6 {
                guard !Task.isCancelled else { return }
                let finished = await runFirstTimeOptionalPreloadNow(profile: working, userId: userId)
                if finished { return }

                // The first attempt often lands inside the anti-bot cold-start
                // window. Retry instead of leaving Reels/Tagged red forever.
                let waitSeconds = attempt == 1 ? 10 : 20
                print("📦 [PRELOAD] Optional preload not ready — retry \(attempt)/6 in \(waitSeconds)s")
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)
            }
            LogManager.shared.warning("First-time optional preload gave up after safe retries", category: .general)
        }
    }

    @MainActor
    private func runFirstTimeOptionalPreloadNow(profile working: InstagramProfile, userId: String) async -> Bool {
        guard !isFirstTimeOptionalPreloadRunning else {
            print("📦 [PRELOAD] Optional preload already running")
            return false
        }
        isFirstTimeOptionalPreloadRunning = true
        defer { isFirstTimeOptionalPreloadRunning = false }

        guard !Task.isCancelled else { return false }
        guard instagram.isLoggedIn,
              !instagram.isLocked,
              !instagram.isSessionChallenged else {
            LogManager.shared.warning("First-time optional preload skipped: Instagram not ready", category: .general)
            return false
        }

        let remainingPostURLs = working.cachedMediaURLs.filter { cachedImages[$0] == nil }
        if !remainingPostURLs.isEmpty {
            LogManager.shared.info("First-time optional preload: downloading \(remainingPostURLs.count) remaining post thumbnails", category: .general)
            for url in remainingPostURLs {
                guard cachedImages[url] == nil else { continue }
                let image = ProfileCacheService.shared.loadImage(forURL: url) ?? {
                    nil
                }()
                if let image {
                    cachedImages[url] = image
                    ProfileCacheService.shared.saveImage(image, forURL: url)
                    continue
                }
                if let image = await downloadImage(from: url) {
                    cachedImages[url] = image
                    ProfileCacheService.shared.saveImage(image, forURL: url)
                }
            }
        }

        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_600_000_000...2_600_000_000))
        guard !Task.isCancelled, canRunOptionalFirstTimePreload(stage: "highlights") else { return false }
        await fetchHighlightsIfNeeded(for: self.profile ?? working)

        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_600_000_000...2_600_000_000))
        guard !Task.isCancelled, canRunOptionalFirstTimePreload(stage: "reels") else { return false }
        await fetchReelsIfNeeded(for: self.profile ?? working, ensureVisibleMinimum: true)

        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_600_000_000...2_600_000_000))
        guard !Task.isCancelled, canRunOptionalFirstTimePreload(stage: "tagged") else { return false }
        await fetchTaggedIfNeeded(for: self.profile ?? working, ensureVisibleMinimum: true)

        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_200_000_000...2_000_000_000))
        guard !Task.isCancelled, canRunOptionalFirstTimePreload(stage: "explore") else { return false }
        await ExploreManager.shared.preloadIfNeeded()
        UserDefaults.standard.set(true, forKey: "perf_optional_preloaded_\(userId)")
        LogManager.shared.info("First-time optional preload finished for \(userId)", category: .general)
        return true
    }

    private enum PreloadError: Error { case noProfile }

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
                cachedTaggedItems: tagged,
                cachedNextMaxId: cached.cachedNextMaxId
            )

            self.profile = updated
            for item in tagged { mediaItemsByURL[item.imageURL] = item }
            ProfileCacheService.shared.saveProfile(updated)

            // Download thumbnails for reels + tagged only. Highlight covers are
            // downloaded when they are explicitly rebuilt outside Performance.
            for item in reels + tagged {
                let url = item.imageURL
                if let img = cachedImages[url]
                    ?? ProfileCacheService.shared.loadImage(forURL: url)
                    ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                    ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                    continue
                }
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                    ProfileCacheService.shared.saveImage(img, forMediaId: item.mediaId)
                }
            }
            print("✅ [CACHE] Background supplementary fetch complete")
        } catch {
            print("⚠️ [CACHE] Background supplementary fetch failed (non-critical): \(error)")
        }
    }
    
    @MainActor
    private func loadProfile() async {
        _ = await loadProfile(source: "manual")
    }

    @MainActor
    private func syncCurrentNoteFromInstagramAfterManualRefresh() async {
        guard !ppTestMode.isActive,
              instagram.isLoggedIn,
              !instagram.isLocked,
              !instagram.isSessionChallenged,
              !instagram.shouldUseCacheOnlyForOptionalCalls,
              !InstagramSafetyGate.shared.isInColdStartWindow else {
            print("📝 [NOTE] Note refresh skipped — safety/session guard")
            return
        }

        do {
            // Keep this read clearly separated from the profile refresh GET.
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_400_000_000...2_400_000_000))
            let remoteNote = try await instagram.getCurrentNoteText()
            if let remoteNote, !remoteNote.isEmpty {
                lastNoteText = remoteNote
                lastNoteSentTimestamp = Date().timeIntervalSince1970
                UserDefaults.standard.set(remoteNote, forKey: "last_note_sent_text")
                print("📝 [NOTE] Refreshed active Instagram note")
                LogManager.shared.info("Manual refresh synced active Instagram note", category: .general)
            } else {
                lastNoteText = ""
                lastNoteSentTimestamp = 0
                UserDefaults.standard.removeObject(forKey: "last_note_sent_text")
                UserDefaults.standard.removeObject(forKey: "note_duplicate_warning_text")
                print("📝 [NOTE] No active Instagram note — local bubble cleared")
                LogManager.shared.info("Manual refresh cleared stale local note", category: .general)
            }
        } catch {
            // Do not clear local state on endpoint failure; only a successful read that
            // finds no own note should remove the bubble.
            print("⚠️ [NOTE] Note refresh failed — keeping local state: \(error.localizedDescription)")
            LogManager.shared.warning("Manual note refresh failed; local note preserved: \(error.localizedDescription)", category: .general)
        }
    }

    @MainActor
    private func handlePerformancePullToRefresh() async {
        CrashLoggerService.shared.recordAction("Performance pull refresh")
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Pull refresh skipped during Bio + PP queue")
            return
        }
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
        let didRefreshProfile = await loadProfile(source: "manual")
        if didRefreshProfile {
            await syncCurrentNoteFromInstagramAfterManualRefresh()
        }

        // Keep pull-to-refresh disabled for 120 s (= SafetyGate minGap) so the
        // user can't trigger a second full load right after this one.
        isRefreshEnabled = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(120) * 1_000_000_000)
            isRefreshEnabled = true
        }
    }

    @MainActor
    @discardableResult
    private func loadProfile(source: String, postPages: Int = 1, repairMode: Bool = false) async -> Bool {
        guard instagram.isLoggedIn else { return false }
        if source == "manual_remote" {
            lastManualRefreshFailureMessage = nil
            lastManualRefreshRetrySeconds = nil
        }

        if instagram.shouldUseCacheOnlyForOptionalCalls {
            let rate = instagram.checkRateLimit()
            print("🛡️ [PERF] loadProfile skipped — near hourly budget (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("CACHE ONLY — loadProfile skipped near rate budget (\(rate.actionsUsed)/55)", category: .general)
            if source == "manual_remote" {
                lastManualRefreshFailureMessage = "Instagram cooldown: API budget is low (\(rate.actionsUsed)/55 used). Try later."
            }
            // Record a SafetyGate stamp so the CooldownWarningBanner shows the
            // "Performance Refresh" countdown even when the budget is the blocker.
            // The 120 s window keeps the pull gesture disabled for the same duration.
            if source == "manual" {
                InstagramSafetyGate.shared.record(.pullRefresh)
            }
            return false
        }

        let isComboPreload = source == "combo_preload"
        let safetyAction: InstagramSafetyGate.Action = (source == "entry" || isComboPreload) ? .entryRefresh : .pullRefresh
        let safetyDecision = InstagramSafetyGate.shared.decision(for: safetyAction)
        guard safetyDecision.allowed else {
            print("🛡️ [PERF] loadProfile blocked — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — loadProfile \(source): \(safetyDecision.reason)", category: .general)
            if source == "manual_remote" {
                lastManualRefreshRetrySeconds = safetyDecision.waitSeconds
                lastManualRefreshFailureMessage = "Instagram cooldown: \(safetyDecision.reason). Wait \(safetyDecision.waitSeconds)s."
            }
            return false
        }
        InstagramSafetyGate.shared.record(safetyAction)

        // Prevent concurrent loads (double swipe-to-refresh)
        guard !isLoading else {
            print("🚫 [PERF] loadProfile skipped — already loading")
            LogManager.shared.warning("loadProfile skipped: already loading", category: .general)
            return false
        }

        // Throttle: block refreshes faster than minRefreshInterval (persisted across restarts)
        let now = Date().timeIntervalSince1970
        let timeSinceLastRefresh = now - lastRefreshTimestamp
        let isManualRemoteRefresh = source == "manual_remote"
        if !isComboPreload && !isManualRemoteRefresh && lastRefreshTimestamp > 0 && timeSinceLastRefresh < minRefreshInterval {
            let waited = Int(timeSinceLastRefresh)
            print("🚫 [PERF] loadProfile throttled — \(waited)s since last refresh (min \(Int(minRefreshInterval))s)")
            LogManager.shared.warning("loadProfile throttled: \(waited)s since last refresh", category: .general)
            return false
        }

        // Anti-bot: skip if profile-pic POST is running, OR if the session is in a challenged
        // state (challenge_required detected recently). Making more calls while challenged
        // escalates bot signals and can cause action_blocked lockdowns.
        if instagram.isUploadingProfilePic {
            print("🚫 [PERF] loadProfile skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("loadProfile skipped: profile pic upload active", category: .general)
            return false
        }
        // Stamp both timestamps so neither the throttle nor the auto-refresh fires again soon
        lastRefreshTimestamp = now
        lastAutoRefreshTimestamp = now

        print("🔄 [PERF] loadProfile starting — full profile refresh (repair=\(repairMode))")
        LogManager.shared.info("Profile refresh started repair=\(repairMode)", category: .general)

        isLoading = true

        do {
            // ANTI-BOT: Wait if network changed recently
            try await instagram.waitForNetworkStability()

            if repairMode {
                postManualRefreshProgress("Repairing replica")
                let userId = currentSessionUserId()
                ProfileCacheService.shared.preparePublicReplicaRebuild(userId: userId.isEmpty ? nil : userId)
                mediaItemsByURL.removeAll()
                revealDates.removeAll()
                allMediaURLs.removeAll()
                nextMaxId = nil
                hasMorePages = true
            } else {
                postManualRefreshProgress(postPages > 1 ? "Syncing page 1/\(postPages)" : "Syncing recent posts")
            }
            
                let fetchedProfile = try await instagram.getProfileInfo()
                
                    if let fetchedProfile = fetchedProfile {
                var mergedProfile = fetchedProfile
                let preservedProfile: InstagramProfile? = repairMode
                    ? nil
                    : (self.profile ?? ProfileCacheService.shared.loadProfile())
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
                // Manual Instagram refresh fetches only the first page. Keep a snapshot
                // of the current/disk grid BEFORE clearing transient maps so we can paint
                // first fresh page + cached tail immediately, like older builds did.
                let previousGridURLsForRefresh = allMediaURLs.isEmpty
                    ? (preservedProfile?.cachedMediaURLs ?? [])
                    : allMediaURLs
                var previousItemsByURLForRefresh = preservedProfile?.cachedMediaItems.reduce(into: [String: InstagramMediaItem]()) {
                    $0[$1.imageURL] = $1
                } ?? [:]
                for (url, item) in mediaItemsByURL {
                    previousItemsByURLForRefresh[url] = item
                }
                // Keep the user-scoped image cache during refresh so existing thumbnails
                // remain visible while fresh metadata is saved over the old profile.json.
                mediaItemsByURL.removeAll()
                revealDates.removeAll()
                // Keep cachedImages so existing thumbnails stay visible during transition

                // ── Bridge CDN URL rotation for the profile pic ────────────────────
                // Instagram rotates CDN query-string tokens on every profile fetch.
                // Only bridge when the CDN *asset path* is unchanged (token rotation) or
                // we have a pending local upload. If the path changed, the user (or IG)
                // replaced the photo — do NOT reuse own_profile_pic or we'd show a stale face.
                let oldPicURL = self.profile?.profilePicURL ?? ""
                let newPicURL = mergedProfile.profilePicURL
                if !newPicURL.isEmpty, newPicURL != oldPicURL {
                    let oldId = ProfileCacheService.profilePicCDNIdentity(for: oldPicURL)
                    let newId = ProfileCacheService.profilePicCDNIdentity(for: newPicURL)
                    let sameCDNAsset = !oldId.isEmpty && oldId == newId
                    let hasPendingUpload = ProfileCacheService.shared.pendingProfilePic != nil
                    if sameCDNAsset || hasPendingUpload {
                        let bridged = cachedImages[oldPicURL]
                            ?? ProfileCacheService.shared.loadImage(forURL: oldPicURL)
                            ?? (sameCDNAsset ? ProfileCacheService.shared.loadOwnProfilePic() : nil)
                            ?? ProfileCacheService.shared.pendingProfilePic
                        if let img = bridged {
                            cachedImages[newPicURL] = img
                            ProfileCacheService.shared.saveImage(img, forURL: newPicURL)
                            ProfileCacheService.shared.saveOwnProfilePic(img, cdnURL: newPicURL)
                            print("⚡️ [PERF] Profile pic bridged old→new CDN URL — no blank frame (sameAsset=\(sameCDNAsset) pending=\(hasPendingUpload))")
                        }
                    } else {
                        // Real photo change (e.g. edited in Instagram app). Drop any stale
                        // mapping under the new URL and force a fresh CDN download below.
                        cachedImages.removeValue(forKey: newPicURL)
                        print("🔄 [PERF] Profile pic CDN asset changed — will re-download (not bridging stale own pic)")
                        LogManager.shared.info("Profile pic CDN asset changed; forcing fresh download", category: .cache)
                    }
                }

                if let localBio = activeLocalBioOverride, mergedProfile.biography != localBio {
                    print("⚡️ [PERF] Preserving local bio override during profile refresh")
                    mergedProfile = profileByReplacingBiography(mergedProfile, biography: localBio)
                }

                self.profile = mergedProfile
                let isManualRefresh = source.hasPrefix("manual")
                let isAuthoritativeRefresh = isManualRefresh || source == "authoritative_after_archive"
                let manualRevealIdsBeforeRefresh: Set<String> = isAuthoritativeRefresh
                    ? Set(allMediaURLs.compactMap { revealMediaId(from: $0) })
                    : []
                // Capture Instagram page-1 payload BEFORE local reconcile mutates the grid.
                let page1APIItems = mergedProfile.cachedMediaItems
                let page1EndCursor = mergedProfile.cachedNextMaxId

                if isAuthoritativeRefresh {
                    // Exact Instagram page-1 prefix — ghosts in the first slots drop here.
                    let page1Result = ProfileMediaReconciler.applyExactFetchedPrefix(
                        currentURLs: previousGridURLsForRefresh,
                        currentItemsByURL: previousItemsByURLForRefresh,
                        freshItems: page1APIItems,
                        endCursor: page1EndCursor
                    )
                    let authoritativeItems = page1Result.urls.compactMap { page1Result.itemsByURL[$0] }

                    mergedProfile.cachedMediaItems = authoritativeItems
                    mergedProfile.cachedMediaURLs = authoritativeItems.map(\.imageURL)
                    mergedProfile.cachedNextMaxId = page1EndCursor
                    self.profile = mergedProfile

                    if page1Result.removedCount > 0 || page1Result.replacedURLCount > 0 || page1Result.appendedCount > 0 {
                        print("🧭 [GRID AUTH] Page 1 exact prefix — +\(page1Result.appendedCount), -\(page1Result.removedCount), url↻\(page1Result.replacedURLCount)")
                        LogManager.shared.info("Page 1 exact prefix: +\(page1Result.appendedCount), -\(page1Result.removedCount), replaced=\(page1Result.replacedURLCount)", category: .general)
                    }

                    let previousGridURLsBeforeAuthoritative = previousGridURLsForRefresh

                    // Determine which reveal:// placeholders are NOT yet confirmed by this
                    // refresh (their mediaId absent from the fresh API page). They must be
                    // preserved — Instagram hasn't indexed them yet (CDN propagation delay).
                    // applyAuthoritativeMediaSnapshot wipes allMediaURLs, so capture dates
                    // and URLs before calling it, then re-insert afterwards.
                    // Confirm reveals only against Instagram's fresh page-1 payload,
                    // not the older local tail kept after exact-prefix reconcile.
                    let authIds = Set(page1APIItems.flatMap { [$0.mediaId, mediaIdKey($0.mediaId)] })
                    let confirmedRevealIds   = manualRevealIdsBeforeRefresh.filter {
                        authIds.contains($0) || authIds.contains(mediaIdKey($0))
                    }
                    let unconfirmedRevealIds = manualRevealIdsBeforeRefresh.subtracting(confirmedRevealIds)
                    let pendingRevealURLs = allMediaURLs.filter { url in
                        guard url.hasPrefix("reveal://"), !url.hasPrefix("reveal://test-") else { return false }
                        guard let mediaId = revealMediaId(from: url) else { return false }
                        return unconfirmedRevealIds.contains(mediaId)
                    }
                    let pendingRevealDates = revealDates.filter { pendingRevealURLs.contains($0.key) }
                    let confirmedRevealReplacements: [(index: Int, revealURL: String, item: InstagramMediaItem)] =
                        previousGridURLsBeforeAuthoritative.enumerated().compactMap { index, revealURL in
                            guard revealURL.hasPrefix("reveal://"),
                                  !revealURL.hasPrefix("reveal://test-"),
                                  let mediaId = revealMediaId(from: revealURL),
                                  confirmedRevealIds.contains(mediaId) || confirmedRevealIds.contains(mediaIdKey(mediaId)),
                                  let item = page1APIItems.first(where: {
                                      $0.mediaId == mediaId || mediaIdKey($0.mediaId) == mediaIdKey(mediaId)
                                  }) else { return nil }
                            return (index: index, revealURL: revealURL, item: item)
                        }

                    applyAuthoritativeMediaSnapshot(
                        items: authoritativeItems,
                        nextCursor: page1EndCursor,
                        source: source,
                        clearRevealState: unconfirmedRevealIds.isEmpty
                    )

                    // If Instagram confirms a reveal, replace the local reveal cell without
                    // blindly reusing its old absolute index. A manual Instagram refresh may
                    // also include brand-new real posts above it; inserting at the old index
                    // would push those new posts down. Use the confirmed item's takenAt date
                    // so new real posts stay first while revealed posts still don't jump to top.
                    if !confirmedRevealReplacements.isEmpty {
                        var stableURLs = allMediaURLs
                        func insertIndex(for date: Date, in urls: [String]) -> Int {
                            var maxDate: Date = .distantPast
                            var maxDateIndex = 0
                            for (i, url) in urls.enumerated() {
                                guard let d = mediaItemsByURL[url]?.takenAt else { continue }
                                if d > maxDate {
                                    maxDate = d
                                    maxDateIndex = i
                                }
                            }
                            let pinnedEnd = maxDate == .distantPast ? 0 : maxDateIndex
                            for i in pinnedEnd..<urls.count {
                                guard let d = mediaItemsByURL[urls[i]]?.takenAt else { continue }
                                // Strictly older only: equal-date siblings keep their existing
                                // relative order instead of being reversed one by one.
                                if d < date { return i }
                            }
                            return urls.count
                        }
                        for replacement in confirmedRevealReplacements.sorted(by: { $0.index < $1.index }) {
                            let realURL = replacement.item.imageURL
                            stableURLs.removeAll { $0 == replacement.revealURL || $0 == realURL }
                            let targetIndex = replacement.item.takenAt.map {
                                insertIndex(for: $0, in: stableURLs)
                            } ?? min(replacement.index, stableURLs.count)
                            stableURLs.insert(realURL, at: min(targetIndex, stableURLs.count))
                            if cachedImages[realURL] == nil,
                               let revealImage = cachedImages[replacement.revealURL] {
                                cachedImages[realURL] = revealImage
                            }
                            cachedImages.removeValue(forKey: replacement.revealURL)
                            revealDates.removeValue(forKey: replacement.revealURL)
                            mediaItemsByURL.removeValue(forKey: replacement.revealURL)
                        }
                        allMediaURLs = deduplicatedGridURLs(stableURLs)
                        let stableItems = allMediaURLs.compactMap { mediaItemsByURL[$0] }
                        if var stableProfile = profile {
                            stableProfile.cachedMediaURLs = allMediaURLs
                            stableProfile.cachedMediaItems = stableItems
                            self.profile = stableProfile
                        }
                        ProfileCacheService.shared.replaceMediaURLsAndItems(allMediaURLs, items: stableItems)
                        print("⚡️ [REVEAL CONFIRM] Replaced \(confirmedRevealReplacements.count) reveal cell(s) by takenAt after Instagram confirmation")
                    }

                    // Re-insert unconfirmed reveals at their chronological position.
                    // (applyAuthoritativeMediaSnapshot cleared them; Instagram hasn't
                    // returned them in the feed yet so they're still pending.)
                    if !pendingRevealURLs.isEmpty {
                        revealDates.merge(pendingRevealDates) { _, new in new }
                        allMediaURLs = restoredGridURLsByPositioningRevealState(
                            baseURLs: allMediaURLs,
                            revealURLs: pendingRevealURLs,
                            storedDates: pendingRevealDates
                        )
                        print("⚡️ [REVEAL PRESERVE] Manual refresh kept \(pendingRevealURLs.count) unconfirmed reveal(s)")
                        persistCurrentRevealState()
                    }

                    // Only reconcile reveals that were fully confirmed in this refresh.
                    // Unconfirmed reveals are still pending — don't mark them as archived.
                    reconcileArchivedStateForClearedReveals(
                        confirmedRevealIds,
                        visibleMediaIds: Set(mergedProfile.cachedMediaItems.map(\.mediaId))
                    )
                } else {
                    // ── Preserve pagination tail — don't collapse the grid ─────────
                    // Non-manual entry remains cache-friendly. Manual refresh is
                    // handled above as Instagram-authoritative.
                    let newFirst = mergedProfile.cachedMediaURLs
                    if allMediaURLs.count > newFirst.count {
                        let tail = Array(allMediaURLs.suffix(allMediaURLs.count - newFirst.count)).filter { url in
                            !url.hasPrefix("reveal://")
                        }
                        self.allMediaURLs = deduplicatedGridURLs(newFirst + tail)
                    } else {
                        self.allMediaURLs = deduplicatedGridURLs(newFirst)
                    }
                    // Seed the pagination cursor so the first scroll-triggered call
                    // fetches page 2 directly instead of re-loading page 1.
                    if self.nextMaxId == nil {
                        self.nextMaxId = mergedProfile.cachedNextMaxId
                    }
                    self.hasMorePages = mergedProfile.cachedNextMaxId != nil && self.allMediaURLs.count < maxPhotosOwnProfile
                }
                // Populate post viewer data (likes/comments already in items, 0 extra API calls)
                for item in mergedProfile.cachedMediaItems + mergedProfile.cachedTaggedItems {
                    mediaItemsByURL[item.imageURL] = item
                }
                persistExistingImagesByMediaId(mergedProfile.cachedMediaItems + mergedProfile.cachedReelItems + mergedProfile.cachedTaggedItems)
                paintAmnesiaCarouselLocally(revealed: amnesiaSettings.isRevealed)
                paintInstapickCarouselLocally()
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
                if isAuthoritativeRefresh {
                    var authoritativeProfile = mergedProfile
                    let remoteURLs = allMediaURLs.filter {
                        !ProfileMediaReconciler.isOverlayURL($0)
                    }
                    let remoteItems = remoteURLs.compactMap { mediaItemsByURL[$0] }
                    authoritativeProfile.cachedMediaURLs = remoteURLs
                    authoritativeProfile.cachedMediaItems = remoteItems
                    ProfileCacheService.shared.saveProfileAuthoritative(authoritativeProfile)
                } else {
                    ProfileCacheService.shared.saveProfile(mergedProfile)
                }
                // A successful refresh means Instagram is the source of truth.
                // Clear the persisted reveal state so re-opening the app after
                // a refresh shows the clean profile, not stale reveal:// entries.
                if !isAuthoritativeRefresh {
                    ProfileCacheService.shared.clearRevealState(userId: mergedProfile.userId)
                }
                // Reset all session gates after a successful manual refresh so new
                // posts, reels, tagged, and highlights are picked up on next preload.
                let uid = mergedProfile.userId
                UserDefaults.standard.removeObject(forKey: "highlights_checked_at_\(uid)")
                UserDefaults.standard.removeObject(forKey: "reels_checked_at_\(uid)")
                UserDefaults.standard.removeObject(forKey: "tagged_checked_at_\(uid)")
                // Allow pagination to re-discover any newly uploaded posts
                UserDefaults.standard.removeObject(forKey: "perf_no_more_pages_\(uid)")
                // Migrate the locally-captured pending pic to the new CDN URL key
                // BEFORE clearing it. Instagram may return a different CDN URL on
                // each profile refresh, so without this the new URL would momentarily
                // have no image → brief flash/spinner between pendingProfilePic=nil
                // and the async download completing.
                if let pendingPic = ProfileCacheService.shared.pendingProfilePic,
                   !mergedProfile.profilePicURL.isEmpty {
                    cachedImages[mergedProfile.profilePicURL] = pendingPic
                    ProfileCacheService.shared.saveImage(pendingPic, forURL: mergedProfile.profilePicURL)
                    ProfileCacheService.shared.saveOwnProfilePic(pendingPic, cdnURL: mergedProfile.profilePicURL)
                    print("⚡️ [PERF] Pending profile pic migrated to new CDN URL — no flash on transition")
                }
                // New CDN URL is now in fetchedProfile.profilePicURL → pending override no longer needed.
                ProfileCacheService.shared.pendingProfilePic = nil
                cdnForbiddenTimestamps.removeAll()
                cdnDownloadBlockedUntil = nil
                        downloadAndCacheImages(profile: mergedProfile)
                // Background preload reels + tagged so they are ready before
                // the user swipes to those tabs. Uses the same fetchReelsIfNeeded /
                // fetchTaggedIfNeeded that tab-swipe uses, so the logic is
                // identical: skip if already cached, respect anti-bot budget.
                // Delay 5s to avoid competing with the posts download burst.
                if repairMode {
                    print("🧹 [REPAIR] Secondary tabs deferred until user opens them")
                    LogManager.shared.info("Repair deferred reels/tagged/highlights to avoid API burst", category: .general)
                } else {
                    scheduleBackgroundReelsTaggedPreload(for: mergedProfile)
                }

                // Release the loading spinner after page 1 so the UI is usable
                // while extra pages are being fetched in the background.
                isLoading = false

                // ── Extra-page deep refresh (postPages > 1) ──────────────────────
                // Fetch pages 2…postPages; each page extends the exact Instagram prefix.
                var syncedFetchedItems = page1APIItems
                var syncedEndCursor = page1EndCursor
                if postPages > 1 {
                    let extra = await fetchExtraRefreshPages(
                        postPages: postPages,
                        userId: mergedProfile.userId,
                        page1Items: page1APIItems,
                        repairMode: repairMode
                    )
                    syncedFetchedItems = extra.accumulatedItems
                    syncedEndCursor = extra.endCursor
                }

                // Set photos inside the synced window but absent from Instagram → archived.
                // Protect pending reveal:// mediaIds (Instagram may not have indexed them yet).
                if isAuthoritativeRefresh {
                    let pendingRevealKeys = Set(allMediaURLs.compactMap { url -> String? in
                        guard url.hasPrefix("reveal://"), !url.hasPrefix("reveal://test-") else { return nil }
                        return revealMediaId(from: url)
                    })
                    ProfileMediaReconciler.reconcileSetPhotosMissingFromSyncedFeed(
                        fetchedKeys: ProfileMediaReconciler.mediaKeys(from: syncedFetchedItems),
                        syncedWindowEndPk: ProfileMediaReconciler.cursorPK(syncedEndCursor),
                        userId: mergedProfile.userId,
                        protectedMediaIds: pendingRevealKeys
                    )
                }

                if repairMode {
                    let required = ProfileCacheService.shared.requiredPerformancePreloadPosts(
                        for: profile ?? mergedProfile,
                        targetPosts: preloadTargetPosts,
                        maxPosts: maxPhotosOwnProfile
                    )
                    let complete = allMediaURLs.count >= required || nextMaxId == nil
                    UserDefaults.standard.set(complete, forKey: "perf_fully_preloaded_\(mergedProfile.userId)")
                    ProfileCacheService.shared.recordPerformancePreloadExit(
                        reason: complete ? "repair_complete" : "repair_partial",
                        userId: mergedProfile.userId,
                        cachedCount: allMediaURLs.count,
                        requiredCount: required,
                        context: "manual_repair"
                    )
                } else if source == "manual_remote" {
                    UserDefaults.standard.set(true, forKey: "perf_manual_depth_synced_\(mergedProfile.userId)")
                }

                return true
                    } else {
                        print("⚠️ [PERF] getProfileInfo returned nil — profile data unavailable")
                        LogManager.shared.error("loadProfile: getProfileInfo returned nil for userId \(instagram.session.userId)", category: .general)
                        isLoading = false
                        return false
                    }
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
                return false
            case .networkError(let message) where message.lowercased().contains("cancelled"):
                print("ℹ️ [PERF] loadProfile cancelled — suppressing connection error alert")
                LogManager.shared.info("loadProfile cancelled; connection alert suppressed", category: .general)
                return false
            default:
                    if source == "manual_remote" {
                        let message = error.localizedDescription
                        lastManualRefreshFailureMessage = friendlyManualRefreshFailureMessage(from: message)
                        lastManualRefreshRetrySeconds = waitSeconds(from: message)
                    }
                    lastError = error
                    showingConnectionError = true
                    return false
                }
            } catch {
                print("❌ Error loading profile: \(error)")
                    isLoading = false
                guard !isCancellationLike(error) else {
                    print("ℹ️ [PERF] loadProfile task cancelled — alert suppressed")
                    LogManager.shared.info("loadProfile task cancelled; connection alert suppressed", category: .general)
                    return false
                }
                    if source == "manual_remote" {
                        let message = error.localizedDescription
                        lastManualRefreshFailureMessage = friendlyManualRefreshFailureMessage(from: message)
                        lastManualRefreshRetrySeconds = waitSeconds(from: message)
                    }
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                    return false
                }
            }
    
    // Sync wrapper for non-async call sites (onRefresh button, header "@" button)
    private struct ExtraRefreshPagesResult {
        let accumulatedItems: [InstagramMediaItem]
        let endCursor: String?
    }

    /// Fetches post pages 2…postPages and applies the accumulated Instagram window
    /// as an exact grid prefix (same rule as page 1). Older local tail past the
    /// deepest endCursor is preserved; anything inside the window but missing from
    /// Instagram is dropped (deleted/archived).
    @MainActor
    private func fetchExtraRefreshPages(
        postPages: Int,
        userId: String,
        page1Items: [InstagramMediaItem],
        repairMode: Bool = false
    ) async -> ExtraRefreshPagesResult {
        guard postPages > 1, !userId.isEmpty else {
            return ExtraRefreshPagesResult(accumulatedItems: page1Items, endCursor: nextMaxId)
        }

        let pagesNeeded = postPages - 1   // page 1 already fetched by getProfileInfo
        var fetchedCount = 0
        var accumulatedItems = page1Items
        var endCursor = nextMaxId

        for _ in 0..<pagesNeeded {
            postManualRefreshProgress(repairMode ? "Repairing page \(fetchedCount + 2)/\(postPages)" : "Syncing page \(fetchedCount + 2)/\(postPages)")
            guard let cursor = nextMaxId, !cursor.isEmpty else {
                print("📄 [EXTRA PAGES] No cursor — stopping at page \(fetchedCount + 1)")
                break
            }

            let gateMaxWaitNs: UInt64 = 30_000_000_000
            var gateWaited: UInt64 = 0
            var gate = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
            while !gate.allowed, gateWaited < gateMaxWaitNs {
                let sliceNs: UInt64 = 2_000_000_000
                print("⏳ [EXTRA PAGES] Gate blocked (\(gate.reason), \(gate.waitSeconds)s) — waiting 2s…")
                postManualRefreshProgress("Waiting anti-bot gate \(max(gate.waitSeconds, 1))s")
                try? await Task.sleep(nanoseconds: sliceNs)
                gateWaited += sliceNs
                gate = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
            }
            guard gate.allowed else {
                print("🛡️ [EXTRA PAGES] Timed out waiting for gate — stopping after \(fetchedCount) page(s)")
                LogManager.shared.warning("Extra-page refresh gate timed out after \(Int(gateWaited / 1_000_000_000))s", category: .general)
                break
            }
            InstagramSafetyGate.shared.record(.ownProfilePagination)

            let humanDelay = UInt64.random(in: 1_400_000_000...2_600_000_000)
            try? await Task.sleep(nanoseconds: humanDelay)

            do {
                let (newItems, newCursor) = try await instagram.getUserMediaItems(
                    userId: userId,
                    amount: 18,
                    maxId: cursor
                )
                guard !newItems.isEmpty else {
                    print("📄 [EXTRA PAGES] Empty page — no more posts")
                    hasMorePages = false
                    break
                }

                fetchedCount += 1
                accumulatedItems.append(contentsOf: newItems)
                endCursor = newCursor
                print("📄 [EXTRA PAGES] Page \(fetchedCount + 1): fetched \(newItems.count) items (cursor: \(newCursor ?? "nil"))")
                LogManager.shared.info("Extra refresh page \(fetchedCount + 1): \(newItems.count) items", category: .general)

                let pageResult = ProfileMediaReconciler.applyExactFetchedPrefix(
                    currentURLs: allMediaURLs,
                    currentItemsByURL: mediaItemsByURL,
                    freshItems: accumulatedItems,
                    endCursor: newCursor
                )
                allMediaURLs = pageResult.urls
                mediaItemsByURL = pageResult.itemsByURL

                if pageResult.removedCount > 0 {
                    print("🗑️ [EXTRA PAGES] Removed \(pageResult.removedCount) deleted/archived post(s) from synced window")
                    LogManager.shared.info("Deep refresh removed \(pageResult.removedCount) deleted post(s) at page \(fetchedCount + 1)", category: .general)
                }

                nextMaxId = newCursor
                hasMorePages = newCursor != nil && allMediaURLs.count < maxPhotosOwnProfile

                if var cached = ProfileCacheService.shared.loadProfile(), cached.userId == userId {
                    let visibleURLs = allMediaURLs.filter { !ProfileMediaReconciler.isOverlayURL($0) }
                    let visibleItems = visibleURLs.compactMap { mediaItemsByURL[$0] }
                    cached.cachedMediaURLs = visibleURLs
                    cached.cachedMediaItems = visibleItems
                    cached.cachedNextMaxId = newCursor
                    ProfileCacheService.shared.saveProfileAuthoritative(cached)
                }

                print("📄 [EXTRA PAGES] Page \(fetchedCount + 1) exact window — +\(pageResult.appendedCount) new, -\(pageResult.removedCount) deleted, url↻\(pageResult.replacedURLCount), grid=\(allMediaURLs.count)")
            } catch {
                print("⚠️ [EXTRA PAGES] Fetch failed: \(error.localizedDescription)")
                LogManager.shared.warning("Extra refresh page fetch failed: \(error.localizedDescription)", category: .general)
                break
            }
        }

        print("📄 [EXTRA PAGES] Done — fetched \(fetchedCount) extra page(s), grid now \(allMediaURLs.count) items")
        return ExtraRefreshPagesResult(accumulatedItems: accumulatedItems, endCursor: endCursor)
    }

    private func loadProfileSync() {
        loadProfileSync(source: "manual")
    }

    private func loadProfileSync(source: String, postPages: Int = 1, repairMode: Bool = false) {
        Task {
            let success = await loadProfile(source: source, postPages: postPages, repairMode: repairMode)
            if success, source.hasPrefix("manual") {
                await syncCurrentNoteFromInstagramAfterManualRefresh()
            }
            if source == "manual_remote" {
                await MainActor.run {
                    postManualRefreshResult(
                        success: success,
                        message: lastManualRefreshFailureMessage,
                        retrySeconds: lastManualRefreshRetrySeconds
                    )
                }
            }
        }
    }

    private func postManualRefreshResult(success: Bool, message: String? = nil, retrySeconds: Int? = nil) {
        var userInfo: [String: Any] = ["success": success]
        if let message { userInfo["message"] = message }
        if let retrySeconds { userInfo["retrySeconds"] = retrySeconds }
        NotificationCenter.default.post(
            name: .performanceManualRefreshResult,
            object: nil,
            userInfo: userInfo
        )
    }

    private func postManualRefreshProgress(_ message: String) {
        NotificationCenter.default.post(
            name: .performanceManualRefreshProgress,
            object: nil,
            userInfo: ["message": message]
        )
    }

    private func waitSeconds(from message: String) -> Int? {
        let pattern = #"Wait\s+(\d+)s"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, options: [], range: range),
              match.numberOfRanges > 1,
              let secondsRange = Range(match.range(at: 1), in: message) else { return nil }
        return Int(message[secondsRange])
    }

    private func friendlyManualRefreshFailureMessage(from message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("safety pause") || lower.contains("feeduserread") || lower.contains("budget exceeded") {
            if let seconds = waitSeconds(from: message) {
                return "Instagram cooldown: wait \(seconds)s, then tap Refresh again."
            }
            return "Instagram cooldown active. Try Refresh again later."
        }
        if lower.contains("cancelled") { return "Refresh cancelled. Try again." }
        return "Refresh failed. Check connection and try again."
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
        cdnForbiddenTimestamps = cdnForbiddenTimestamps.filter { now.timeIntervalSince($0) < 60 }
        cdnForbiddenTimestamps.append(now)

        guard cdnForbiddenTimestamps.count >= 8 else { return }

        let blockedUntil = now.addingTimeInterval(90)
        if cdnDownloadBlockedUntil.map({ $0 < blockedUntil }) ?? true {
            cdnDownloadBlockedUntil = blockedUntil
        }

        LogManager.shared.warning(
            "CDN thumbnail downloads paused for 90s after \(cdnForbiddenTimestamps.count) HTTP 403s",
            category: .cache
        )
    }

    @MainActor
    private func cdnDownloadBlockSecondsRemaining() -> Int {
        guard let blockedUntil = cdnDownloadBlockedUntil else { return 0 }
        let remaining = Int(blockedUntil.timeIntervalSinceNow)
        if remaining <= 0 {
            cdnDownloadBlockedUntil = nil
            cdnForbiddenTimestamps.removeAll()
            return 0
        }
        return remaining
    }

    @MainActor
    private func shouldSkipCDNImageDownload(url: String) -> Bool {
        guard url.contains("fbcdn.net") || url.contains("instagram") else { return false }
        let remaining = cdnDownloadBlockSecondsRemaining()
        guard remaining > 0 else { return false }
        return true
    }

    @MainActor
    private func persistExistingImagesByMediaId(_ items: [InstagramMediaItem]) {
        var persisted = 0
        for item in items where !item.mediaId.isEmpty {
            if let image = cachedImages[item.imageURL] ?? ProfileCacheService.shared.loadImage(forURL: item.imageURL) {
                ProfileCacheService.shared.saveImage(image, forMediaId: item.mediaId)
                persisted += 1
            }
        }
        if persisted > 0 {
            print("📦 [CACHE] Persisted \(persisted) existing image(s) by mediaId")
        }
    }

    @MainActor
    private func hydrateCachedImagesForItems(_ items: [InstagramMediaItem]) -> Int {
        var hydrated = 0
        for item in items where cachedImages[item.imageURL] == nil {
            guard let image = ProfileCacheService.shared.loadImage(forURL: item.imageURL)
                    ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) else { continue }
            cachedImages[item.imageURL] = image
            ProfileCacheService.shared.saveImage(image, forURL: item.imageURL)
            if !item.mediaId.isEmpty {
                ProfileCacheService.shared.saveImage(image, forMediaId: item.mediaId)
            }
            hydrated += 1
        }
        return hydrated
    }

    @MainActor
    private func hydrateCachedImagesForURLs(_ urls: [String]) -> Int {
        var hydrated = 0
        for url in urls where cachedImages[url] == nil {
            guard let image = ProfileCacheService.shared.loadImage(forURL: url) else { continue }
            cachedImages[url] = image
            hydrated += 1
        }
        return hydrated
    }

    private func warmSecondaryTabImagesFromDisk(for cached: InstagramProfile) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let reels = hydrateCachedImagesForItems(cached.cachedReelItems)
            var tagged = hydrateCachedImagesForItems(cached.cachedTaggedItems)
            tagged += hydrateCachedImagesForURLs(cached.cachedTaggedURLs)
            if reels + tagged > 0 {
                print("📦 [CACHE] Warmed secondary tab thumbnails from disk — reels:\(reels) tagged:\(tagged)")
            }
        }
    }

    @MainActor
    private func scheduleCDNURLRefresh(reason: String) {
        guard !cdnRefreshScheduled else { return }
        guard profile != nil else { return }
        if let last = lastCDNURLRefreshAttemptAt, Date().timeIntervalSince(last) < 10 * 60 {
            print("🔄 [CDN] URL refresh skipped — recent attempt already made")
            LogManager.shared.warning("CDN URL refresh skipped — recent attempt already made", category: .cache)
            cdnForbiddenTimestamps.removeAll()
            return
        }

        cdnRefreshScheduled = true
        lastCDNURLRefreshAttemptAt = Date()
        print("🔄 [CDN] Scheduling safe URL refresh — \(reason)")
        LogManager.shared.warning("CDN thumbnails expired — scheduling safe profile URL refresh", category: .cache)

        Task { @MainActor in
            defer {
                cdnRefreshScheduled = false
                cdnForbiddenTimestamps.removeAll()
            }

            guard profile != nil,
                  !instagram.isLocked,
                  !instagram.isSessionChallenged,
                  !instagram.isSessionExpired,
                  !uploadManager.isActive,
                  !uploadManager.isSyncArchiveActive,
                  !uploadManager.isReverifying else {
                print("🔄 [CDN] URL refresh aborted — session/upload/reverify guard failed")
                LogManager.shared.warning("CDN URL refresh aborted by safety guard", category: .cache)
                return
            }

            guard !InstagramSafetyGate.shared.isInColdStartWindow,
                  InstagramSafetyGate.shared.postMutationQuietSecondsRemaining == 0 else {
                print("🔄 [CDN] URL refresh skipped — cold-start/quiet window active")
                LogManager.shared.warning("CDN URL refresh skipped during cold-start or quiet window", category: .cache)
                return
            }

            let decision = InstagramSafetyGate.shared.decision(for: .silentGridRefresh)
            guard decision.allowed else {
                print("🔄 [CDN] URL refresh skipped by safety gate — \(decision.reason) (\(decision.waitSeconds)s)")
                LogManager.shared.warning("CDN URL refresh skipped: \(decision.reason)", category: .cache)
                return
            }

            guard !isLoading, !isPullRefreshInFlight, !isSilentGridRefreshing else {
                print("🔄 [CDN] URL refresh skipped — another refresh active")
                LogManager.shared.warning("CDN URL refresh skipped because another refresh is active", category: .cache)
                return
            }

            print("🔄 [CDN] Refreshing profile media URLs after CDN 403 burst (single attempt)")
            await refreshMediaGridSilently(reason: "expired CDN image URLs")
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
            ProfileCacheService.shared.saveOwnProfilePic(pending, cdnURL: profile.profilePicURL)
        } else if let image = ProfileCacheService.shared.loadOwnProfilePic(forURL: profile.profilePicURL) {
            cachedImages[profile.profilePicURL] = image
        }

        let followerPicURLs    = profile.followedBy.compactMap { $0.profilePicURL }
        // Include persisted reveal:// images so they load from disk on app restart.
        let revealURLs: [String] = allMediaURLs.filter { $0.hasPrefix("reveal://") }
        var allURLs: [String] = [profile.profilePicURL]
        allURLs += profile.cachedMediaURLs
        allURLs += followerPicURLs
        // Do not batch-download Reels/Tagged/Highlights from the Profile tab.
        // Those secondary URLs are often stale and can block post thumbnails.

        var missingURLs: [String] = []
        var hitCount = 0
        for url in revealURLs where cachedImages[url] == nil {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                hitCount += 1
            } else if let mediaId = revealMediaId(from: url),
                      let image = ProfileCacheService.shared.loadImage(forMediaId: mediaId) {
                cachedImages[url] = image
                hitCount += 1
            }
        }
        for url in allURLs where cachedImages[url] == nil {
            // 1st try: URL-keyed file (works when CDN token hasn't rotated)
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                hitCount += 1
            // 2nd try: mediaId-keyed file (survives CDN URL rotation between sessions)
            } else if let mediaId = mediaItemsByURL[url]?.mediaId,
                      let image = ProfileCacheService.shared.loadImage(forMediaId: mediaId) {
                cachedImages[url] = image
                // Re-save with the new CDN URL so future URL lookups are instant
                ProfileCacheService.shared.saveImage(image, forURL: url)
                hitCount += 1
            } else {
                missingURLs.append(url)
            }
        }
        print("📦 [CACHE] disk-hit \(hitCount), to-download \(missingURLs.count) — total \(cachedImages.count)")

        guard !missingURLs.isEmpty else { return }
        if cdnDownloadBlockSecondsRemaining() > 0 {
            print("📦 [CACHE] Skipping download batch — CDN 403 backoff active")
            LogManager.shared.warning("Image download batch skipped: CDN 403 backoff active", category: .cache)
            return
        }

        // ── 2. Skip batch when CDN tokens are already known-expired ──────────
        // If 8+ HTTP 403s were recorded in the last 60s the CDN URLs have
        // rotated — downloading them now would just produce 403s that inflate
        // memory and look like automated traffic. Wait for manual refresh.
        let recentForbidden = cdnForbiddenTimestamps.filter { Date().timeIntervalSince($0) < 60 }.count
        if recentForbidden >= 8 {
            print("📦 [CACHE] Skipping download — CDN URLs known-expired (\(recentForbidden) recent 403s)")
            cdnDownloadBlockedUntil = Date().addingTimeInterval(90)
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
                    group.addTask { (u, await self.downloadImageWithRetry(from: u, attempts: 2)) }
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
                            self.cachedImages[u] = i
                            ProfileCacheService.shared.saveImage(i, forURL: u)
                            // Also save by stable mediaId so the image survives CDN URL rotation
                            if let mediaId = self.mediaItemsByURL[u]?.mediaId {
                                ProfileCacheService.shared.saveImage(i, forMediaId: mediaId)
                            }
                        }
                    }
                    // Abort the whole batch early if CDN has gone stale mid-run
                    let forbidden = await MainActor.run {
                        self.cdnForbiddenTimestamps.filter { Date().timeIntervalSince($0) < 60 }.count
                    }
                    guard forbidden < 8 else {
                        print("📦 [CACHE] Aborting download batch — CDN expired mid-run (\(forbidden) 403s)")
                        await MainActor.run {
                            self.cdnDownloadBlockedUntil = Date().addingTimeInterval(90)
                        }
                        group.cancelAll()
                        break
                    }
                    // Enqueue next URL as a slot frees up
                    if let url = iterator.next() {
                        let u = url
                        group.addTask { (u, await self.downloadImageWithRetry(from: u, attempts: 2)) }
                        inFlight += 1
                    }
                }
            }
            print("✅ [CACHE] Download batch finished — total \(await MainActor.run { self.cachedImages.count })")
        }
    }
    
    private func downloadAndCacheImages(profile: InstagramProfile) {
        Task {
            // Profile pic — skip only when memory already has THIS CDN asset.
            // After a real Instagram-side photo change the bridge leaves the slot empty
            // (or identity mismatches) so we re-download. Token rotation bridges
            // same-asset bytes and skips the GET.
            let picURL = profile.profilePicURL
            let (picAlreadyCached, mustRedownload) = await MainActor.run { () -> (Bool, Bool) in
                let has = !picURL.isEmpty && cachedImages[picURL] != nil
                let savedIdentity = ProfileCacheService.shared.savedOwnProfilePicCDNIdentity()
                let identityMatches = ProfileCacheService.shared.ownProfilePicMatchesCDNIdentity(of: picURL)
                let pending = ProfileCacheService.shared.pendingProfilePic != nil
                // Force CDN GET only when we previously knew an asset and Instagram
                // replaced it (path changed). Nil identity = first run / legacy — don't
                // clear last_profile_pic_hash or spam a redundant GET.
                let force = !picURL.isEmpty && savedIdentity != nil && !identityMatches && !pending
                return (has, force)
            }
            if picAlreadyCached && !mustRedownload {
                print("✅ [CACHE] Profile pic already in memory — download skipped")
            } else {
                print("🖼️ [CACHE] Downloading profile pic: \(String(picURL.prefix(80)))...")
                if let image = await downloadImage(from: picURL) {
                    await MainActor.run {
                        cachedImages[picURL] = image
                        ProfileCacheService.shared.saveImage(image, forURL: picURL)
                        ProfileCacheService.shared.saveOwnProfilePic(image, cdnURL: picURL)
                        // External IG change: hash of last Vault upload is still valid for
                        // anti-bot duplicate checks, but display/reset drift must warn.
                        if mustRedownload {
                            UserDefaults.standard.set(true, forKey: "profile_pic_external_change")
                            ProfileResetSettings.shared.refreshDriftState()
                            print("🔄 [CACHE] Marked external profile-pic change (IG app) for reset drift")
                        }
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
                var mediaByURL: [String: InstagramMediaItem] = [:]
                for item in profile.cachedMediaItems where mediaByURL[item.imageURL] == nil {
                    mediaByURL[item.imageURL] = item
                }
                for (index, url) in missingMedia.enumerated() {
                    if let mediaId = mediaByURL[url]?.mediaId,
                       let image = ProfileCacheService.shared.loadImage(forMediaId: mediaId) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                        print("✅ [CACHE] Media \(index + 1)/\(missingMedia.count) restored by mediaId")
                        continue
                    }
                    if let image = await downloadImageWithRetry(from: url, mediaId: mediaByURL[url]?.mediaId, attempts: 3) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                            if let mediaId = mediaByURL[url]?.mediaId {
                                ProfileCacheService.shared.saveImage(image, forMediaId: mediaId)
                            }
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
                        cachedImages[picURL] = image
                        ProfileCacheService.shared.saveImage(image, forURL: picURL)
                    }
                }
            }

            // Do not eagerly download Reels/Tagged/Highlights from the Profile tab.
            // Expired secondary-tab CDN URLs were triggering 403 storms and blocking
            // post thumbnails during live Performance. Those tabs lazy-load on tap.
            print("✅ [CACHE] Primary profile images cached; secondary tabs deferred")
            
            print("✅ [CACHE] All images download process completed")
        }
    }
    
    // MARK: - Infinite Scroll
    
    private func loadMoreMedia() {
        guard !isLoadingMore, hasMorePages, allMediaURLs.count < maxPhotosOwnProfile else {
            print("📜 [PROFILE] Cannot load more - loading: \(isLoadingMore), hasMore: \(hasMorePages), count: \(allMediaURLs.count)")
            return
        }
        if nextMaxId == nil,
           let knownCount = profile?.mediaCount,
           knownCount > 0,
           allMediaURLs.count >= knownCount {
            hasMorePages = false
            print("📜 [PROFILE] Pagination skipped — no cursor and all \(knownCount) post(s) already loaded")
            LogManager.shared.info("Performance pagination disabled: no cursor and full known media count loaded", category: .profile)
            return
        }
        let preloadUserId = currentSessionUserId()
        if !preloadUserId.isEmpty,
           let cached = ProfileCacheService.shared.loadProfile(),
           cached.userId == preloadUserId,
           !ProfileCacheService.shared.hasCompletePerformancePreloadCache(cached, userId: preloadUserId) {
            print("📜 [PROFILE] Pagination skipped — first-time preload incomplete; use Continue loading")
            LogManager.shared.info("Performance pagination skipped until incomplete preload is continued explicitly", category: .profile)
            return
        }
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Pagination skipped during Bio + PP queue")
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
                            // Human-like pause before the internal second call. This is
                            // still one extra /feed/user/ read, so keep it far away from
                            // the first request to avoid the repeated-feed pattern.
                            let pauseNs = UInt64.random(in: 8_000_000_000...14_000_000_000)
                            try? await Task.sleep(nanoseconds: pauseNs)
                            InstagramSafetyGate.shared.record(.ownProfilePagination)
                            let nextPage = try await instagram.getUserMediaItems(userId: profile?.userId, amount: 21, maxId: discoveredMaxId)
                            mediaItems = nextPage.0
                            newMaxId = nextPage.1
                        } else {
                            print("🛡️ [PROFILE] Skipping internal nextPage — SafetyGate (\(nextPageDecision.reason), wait \(nextPageDecision.waitSeconds)s)")
                            LogManager.shared.warning("SAFETY BLOCK — internal nextPage skipped: \(nextPageDecision.reason)", category: .general)
                            await MainActor.run {
                                nextMaxId = discoveredMaxId
                                hasMorePages = true
                                isLoadingMore = false
                                schedulePaginationRetry(
                                    after: max(8, nextPageDecision.waitSeconds + 1),
                                    reason: "internal nextPage gate"
                                )
                            }
                            return
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
                    // Persist "all pages loaded" so the next session doesn't re-fetch page 1
                    if !hasMorePages, let uid = profile?.userId, !uid.isEmpty {
                        UserDefaults.standard.set(true, forKey: "perf_no_more_pages_\(uid)")
                        print("📦 [CACHE] All pages loaded — flagged to skip pagination on next session")
                    }
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

        let preloadUserId = currentSessionUserId()
        if !preloadUserId.isEmpty,
           let cached = ProfileCacheService.shared.loadProfile(),
           cached.userId == preloadUserId,
           !ProfileCacheService.shared.hasCompletePerformancePreloadCache(cached, userId: preloadUserId) {
            return
        }

        // Skip while another page load or silent refresh is already running.
        guard !isLoadingMore, !isSilentGridRefreshing else { return }

        guard let index = allMediaURLs.firstIndex(of: currentURL) else { return }
        // 85% threshold: avoid automatic /feed/user/ bursts while SwiftUI mounts
        // the initial grid. This fires only when the user is genuinely near the end.
        let threshold = max(1, Int(Double(allMediaURLs.count) * 0.85))

        if index >= threshold {
            // Debounce: SwiftUI can re-render many cells at once after a grid change
            // (reveal reconciliation, silent refresh). Without this a single scroll
            // event can fire loadMoreIfNeeded 6+ times in 100ms.
            let now = Date()
            guard now.timeIntervalSince(lastLoadMoreTriggeredAt) > 1.5 else { return }
            lastLoadMoreTriggeredAt = now
            print("📜 [PROFILE] User reached 85% (\(index)/\(allMediaURLs.count)) — loading more…")
            // If pagination is still in the SafetyGate cooldown (e.g. 6s after
            // silent refresh), schedule a SINGLE automatic retry so the user
            // never sees a blank grid — no manual action needed.
            // paginationRetryScheduled prevents the thundering-herd problem where
            // 12 onAppear callbacks each schedule their own retry.
            if performanceRemoteCallsAllowed {
                let decision = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
                if decision.allowed {
                    loadMoreMedia()
                } else {
                    schedulePaginationRetry(
                        after: max(8, decision.waitSeconds + 1),
                        reason: decision.reason
                    )
                }
            } else {
                loadMoreMedia()  // cache-only guard handled inside loadMoreMedia itself
            }
        }
    }

    private func schedulePaginationRetry(after wait: Int, reason: String) {
        guard !paginationRetryScheduled else { return }
        paginationRetryScheduled = true
        let jitteredWait = wait + Int.random(in: 1...4)
        print("⏳ [PROFILE] Pagination gated (\(reason), \(jitteredWait)s) — will retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(jitteredWait) + 0.3) {
            paginationRetryScheduled = false
            guard !isLoadingMore,
                  !isSilentGridRefreshing,
                  hasMorePages,
                  performanceRemoteCallsAllowed,
                  !uploadManager.isActive,
                  !uploadManager.isSyncArchiveActive else { return }
            loadMoreMedia()
        }
    }
    
    private func downloadImagesForURLs(_ urls: [String]) {
        Task {
            for url in urls {
                if cachedImages[url] == nil {
                    if let image = ProfileCacheService.shared.loadImage(forURL: url)
                        ?? mediaItemsByURL[url].flatMap({ ProfileCacheService.shared.loadImage(forMediaId: $0.mediaId) }) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                        continue
                    }
                }
                if await MainActor.run(body: { shouldSkipCDNImageDownload(url: url) }) {
                    break
                }
                if cachedImages[url] == nil, let image = await downloadImage(from: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                        ProfileCacheService.shared.saveImage(image, forURL: url)
                        if let mediaId = mediaItemsByURL[url]?.mediaId {
                            ProfileCacheService.shared.saveImage(image, forMediaId: mediaId)
                        }
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

        if await MainActor.run(body: { shouldSkipCDNImageDownload(url: urlString) }) {
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

    private func downloadImageWithRetry(from urlString: String, mediaId: String? = nil, attempts: Int = 3) async -> UIImage? {
        if let image = ProfileCacheService.shared.loadImage(forURL: urlString) {
            return image
        }
        if let mediaId, !mediaId.isEmpty,
           let image = ProfileCacheService.shared.loadImage(forMediaId: mediaId) {
            ProfileCacheService.shared.saveImage(image, forURL: urlString)
            return image
        }

        let totalAttempts = max(1, attempts)
        for attempt in 1...totalAttempts {
            if let image = await downloadImage(from: urlString) {
                if attempt > 1 {
                    print("✅ [DOWNLOAD] Thumbnail recovered on retry \(attempt) mediaId=\(mediaId ?? "unknown")")
                    LogManager.shared.info("Thumbnail recovered on retry \(attempt) mediaId=\(mediaId ?? "unknown")", category: .cache)
                }
                return image
            }
            guard attempt < totalAttempts else { break }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
        }
        return nil
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
        let currentRealIds = realMediaIds()
        let photos = photos.filter { item in
            guard let mediaId = revealMediaId(from: item.pseudoURL) else {
                return item.pseudoURL.hasPrefix("reveal://test-")
            }
            return !currentRealIds.contains(mediaId) && !currentRealIds.contains(mediaIdKey(mediaId))
        }
        guard !photos.isEmpty else {
            print("⚡️ [REVEAL BATCH] Skipped reveal placeholders — real posts already exist")
            return
        }

        // Cache images in memory + persist to disk (Application Support) so they
        // survive app restarts without needing an API call.
        for item in photos {
            if let mediaId = revealMediaId(from: item.pseudoURL) {
                removeAllGridEntries(mediaId: mediaId)
            }
            guard let img = item.image else { continue }
            cachedImages[item.pseudoURL] = img
            guard !item.pseudoURL.hasPrefix("reveal://test-") else { continue }
            ProfileCacheService.shared.saveImage(img, forURL: item.pseudoURL)
        }

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

        // ── Contiguity check ────────────────────────────────────────────────────
        // The single-anchor "block" below glues the whole batch together at the
        // newest date. That is correct ONLY when the revealed posts are adjacent in
        // Instagram's true chronological order (a word set uploaded together).
        //
        // Force Number banks can be uploaded on different days, so a normal post (or
        // carousel) may sit BETWEEN them in Instagram's real grid. Example "963":
        // the "9" bank was uploaded AFTER the carousel while "6"/"3" were uploaded
        // BEFORE it. Blocking them together puts "963" in the wrong place vs the real
        // profile. When ANY real post's date falls strictly inside the batch's date
        // span, the batch is NOT contiguous → place each reveal at its OWN date so the
        // grid matches Instagram exactly. `insertRevealURL` already does date-accurate
        // single insertion (and persists), so we just delegate per item.
        let batchDates = photos.compactMap { revealDates[$0.pseudoURL] }
        if let minBatch = batchDates.min(), let maxBatch = batchDates.max(), minBatch < maxBatch {
            let realPostInside = allMediaURLs.contains { url in
                guard !ProfileMediaReconciler.isOverlayURL(url),
                      let d = mediaItemsByURL[url]?.takenAt else { return false }
                return d > minBatch && d < maxBatch
            }
            if realPostInside {
                for item in photos { insertRevealURL(item.pseudoURL) }
                persistCurrentRevealState()
                print("⚡️ [REVEAL BATCH] Non-contiguous (real post within batch date span) — placed \(photos.count) reveals each at its own date")
                return
            }
        }

        // Anchor = newest date in the batch (position the whole group here)
        guard let anchorDate = photos.compactMap({ revealDates[$0.pseudoURL] }).max() else {
            // No dates at all — never prepend. Fallback below the newest real post
            // so newly uploaded Instagram posts still remain above Post Prediction.
            let safeIndex = safeRevealFallbackInsertIndex()
            for item in photos {
                guard !allMediaURLs.contains(item.pseudoURL) else { continue }
                allMediaURLs.insert(item.pseudoURL, at: safeIndex)
            }
            persistCurrentRevealState()
            print("⚡️ [REVEAL BATCH] No dates — \(photos.count) photos at safe pos \(safeIndex) (fallback, never top)")
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
        persistCurrentRevealState()
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
    ///  4. Fallback: if no date can be repaired, insert below the newest real post,
    ///     never at position 0. Position 0 makes hidden prediction posts look newer
    ///     than real Instagram posts uploaded after the set was prepared.
    ///
    /// Example — word "julia", grid has two new real posts (Mar 28) and old posts (Jan 10):
    ///   Each magic photo has uploadDate in Feb 2026 → they land AFTER the Mar 28 posts, BEFORE Jan 10.
    ///   Final: [new1(Mar28), new2(Mar28), J, U, L, I, A, old(Jan10)] ✓
    @MainActor
    private func insertRevealURL(_ pseudoURL: String) {
        let mediaId = String(pseudoURL.dropFirst("reveal://".count))
        guard !allMediaURLs.contains(pseudoURL) else { return }
        guard !realMediaIds().contains(mediaId) else {
            cachedImages.removeValue(forKey: pseudoURL)
            revealDates.removeValue(forKey: pseudoURL)
            mediaItemsByURL.removeValue(forKey: pseudoURL)
            print("⚡️ [REVEAL] Skipped \(mediaId) placeholder — real post already exists")
            return
        }
        removeAllGridEntries(mediaId: mediaId)

        // Persist the reveal image to Application Support so it survives app restarts.
        if let img = cachedImages[pseudoURL] {
            ProfileCacheService.shared.saveImage(img, forURL: pseudoURL)
        }

        // Look up the upload date from DataManager — equals the taken_at sent to Instagram
        // (or the actual upload time for older sets uploaded before the grid-anchor feature).
        let uploadDate = revealUploadDate(for: mediaId)

        guard let revealDate = uploadDate else {
            let safeIndex = safeRevealFallbackInsertIndex()
            allMediaURLs.insert(pseudoURL, at: safeIndex)
            persistCurrentRevealState()
            print("⚡️ [REVEAL] No uploadDate for \(mediaId) — inserted at safe pos \(safeIndex) (fallback, never top)")
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
                persistCurrentRevealState()
                print("⚡️ [REVEAL] \(mediaId) (taken_at≈\(revealDate)) → inserted at pos \(i) (pinnedEnd=\(pinnedEnd))")
                return
            }
        }

        // Older than everything in the non-pinned section → append at the end.
        allMediaURLs.append(pseudoURL)
        persistCurrentRevealState()
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

            let validSiblingDates = set.photos.compactMap { sibling -> Date? in
                guard sibling.mediaId != mediaId, let date = sibling.uploadDate else { return nil }
                if let completedAt = set.completedAt {
                    return date <= completedAt.addingTimeInterval(300) ? date : nil
                }
                return date
            }.sorted()

            guard let rawDate = photo.uploadDate else {
                if !validSiblingDates.isEmpty {
                    let repairedDate = validSiblingDates[validSiblingDates.count / 2]
                    DataManager.shared.updatePhoto(photoId: photo.id, uploadDate: repairedDate)
                    print("🛠️ [REVEAL] Missing uploadDate for \(mediaId) repaired from siblings → \(repairedDate)")
                    return repairedDate
                }
                if let completedAt = set.completedAt {
                    DataManager.shared.updatePhoto(photoId: photo.id, uploadDate: completedAt)
                    print("🛠️ [REVEAL] Missing uploadDate for \(mediaId) repaired from set.completedAt → \(completedAt)")
                    return completedAt
                }
                return nil
            }

            guard let completedAt = set.completedAt,
                  rawDate > completedAt.addingTimeInterval(300) else {
                return rawDate
            }

            guard !validSiblingDates.isEmpty else {
                DataManager.shared.updatePhoto(photoId: photo.id, uploadDate: completedAt)
                print("🛠️ [REVEAL] Future uploadDate for \(mediaId) repaired from set.completedAt: \(rawDate) → \(completedAt)")
                return completedAt
            }

            let repairedDate = validSiblingDates[validSiblingDates.count / 2]
            DataManager.shared.updatePhoto(photoId: photo.id, uploadDate: repairedDate)
            print("🛠️ [REVEAL] Repaired uploadDate for \(mediaId): \(rawDate) → \(repairedDate)")
            return repairedDate
        }

        return nil
    }

    @MainActor
    private func safeRevealFallbackInsertIndex() -> Int {
        // Find the newest dated real grid item. In normal Instagram order, any
        // hidden prediction post with unknown date should never appear above it.
        var newestIndex: Int? = nil
        var newestDate: Date = .distantPast
        for (index, url) in allMediaURLs.enumerated() where !url.hasPrefix("reveal://") {
            guard let date = mediaItemsByURL[url]?.takenAt else { continue }
            if date > newestDate {
                newestDate = date
                newestIndex = index
            }
        }

        if let newestIndex {
            return min(newestIndex + 1, allMediaURLs.count)
        }

        // If no dates are available, append rather than prepend. Appending is less
        // visually risky than making the prediction look like the newest post.
        return allMediaURLs.count
    }

    private enum MediaGridRefreshMode {
        case preserveUnconfirmedReveal
        case authoritative
    }

    @MainActor
    private func schedulePostRevealGridRefresh(reason: String, includesVideo: Bool) {
        postRevealGridRefreshGeneration += 1
        let generation = postRevealGridRefreshGeneration
        let delays: [UInt64] = includesVideo ? [5, 25, 55] : [5, 18]

        for delaySeconds in delays {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                guard generation == postRevealGridRefreshGeneration else {
                    print("🔄 [PERF] Post-reveal refresh cancelled — newer reveal/background")
                    return
                }
                if delaySeconds > delays[0],
                   !allMediaURLs.contains(where: { $0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }) {
                    print("🔄 [PERF] Post-reveal retry skipped — no local reveal overlays remain")
                    return
                }
                guard scenePhase == .active,
                      UIApplication.shared.applicationState == .active else {
                    print("🔄 [PERF] Post-reveal refresh skipped — app not active")
                    LogManager.shared.warning("Post-reveal refresh skipped: app not active", category: .general)
                    return
                }
                await refreshMediaGridSilently(
                    bypassQuietWindow: true,
                    reason: reason,
                    mode: .authoritative,
                    amount: includesVideo ? 60 : 21
                )
            }
        }
    }

    /// Does NOT touch profile stats, bio, follower count, etc. — zero visible disruption.
    @MainActor
    private func refreshMediaGridSilently(
        bypassQuietWindow: Bool = false,
        reason: String = "silent grid refresh",
        mode: MediaGridRefreshMode = .preserveUnconfirmedReveal,
        amount: Int = 21
    ) async {
        guard !isCombinedBioPostPredictionGuardActive else {
            print("🔗 [COMBO] Silent refresh skipped during Bio + PP queue")
            return
        }
        guard !isLoading, !isPullRefreshInFlight, !isSilentGridRefreshing else {
            print("⚠️ [PERF] Silent refresh skipped — another refresh is active")
            return
        }
        // Cold-start guard: never run an automatic silent refresh during the
        // first ~45s of the app session — this is the API burst Instagram
        // fingerprints as bot behaviour.
        guard bypassQuietWindow || InstagramSafetyGate.shared.allowAutoCall(reason) else {
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
        if !bypassQuietWindow {
            let safetyDecision = InstagramSafetyGate.shared.decision(for: .silentGridRefresh)
            guard safetyDecision.allowed else {
                print("🛡️ [PERF] Silent refresh skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
                LogManager.shared.warning("SAFETY BLOCK — silent grid refresh: \(safetyDecision.reason)", category: .general)
                return
            }
            InstagramSafetyGate.shared.record(.silentGridRefresh)
        } else {
            InstagramSafetyGate.shared.record(.silentGridRefresh)
            LogManager.shared.info("Silent media refresh bypassed optional-call throttle for reveal position reconciliation", category: .general)
        }

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
        print("🔄 [PERF] Silent refresh: fetching updated media grid (reason: \(reason), bypassQuiet:\(bypassQuietWindow))…")
        LogManager.shared.info("Silent media refresh triggered (\(reason), bypassQuiet:\(bypassQuietWindow))", category: .general)

        do {
            let (items, refreshedMaxId) = try await instagram.getUserMediaItems(userId: userId, amount: amount, maxId: nil)
            let newURLs = items.map { $0.imageURL }
            guard !newURLs.isEmpty else {
                print("⚠️ [PERF] Silent refresh: empty response from Instagram")
                return
            }

            // CDN URLs rotate across feed refreshes. Before downloading, bridge any
            // already-visible thumbnail from its old URL to the new URL by stable mediaId.
            // This is especially important for video covers after a reveal: the metadata
            // refresh can return new cover URLs for every existing video post, and if we
            // drop the old URL-keyed images before bridging, those cells turn gray until
            // the next app open.
            let oldItemsByMediaId: [String: InstagramMediaItem] = mediaItemsByURL.values.reduce(into: [:]) { result, item in
                guard !item.mediaId.isEmpty else { return }
                result[mediaIdKey(item.mediaId)] = item
            }
            for item in items where cachedImages[item.imageURL] == nil {
                guard let oldItem = oldItemsByMediaId[mediaIdKey(item.mediaId)] else { continue }
                if let bridged = cachedImages[oldItem.imageURL]
                    ?? ProfileCacheService.shared.loadImage(forURL: oldItem.imageURL)
                    ?? ProfileCacheService.shared.loadImage(forMediaId: oldItem.mediaId) {
                    cachedImages[item.imageURL] = bridged
                    ProfileCacheService.shared.saveImage(bridged, forURL: item.imageURL)
                    ProfileCacheService.shared.saveImage(bridged, forMediaId: item.mediaId)
                }
            }

            // Pre-download all new images BEFORE swapping allMediaURLs.
            // This prevents blank cells: cells keep showing local reveal:// images
            // until the real CDN images are fully cached and ready.
            let missingItems = items.filter { item in
                cachedImages[item.imageURL] == nil &&
                ProfileCacheService.shared.loadImage(forURL: item.imageURL) == nil &&
                ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) == nil
            }
            if !missingItems.isEmpty {
                print("🔄 [PERF] Silent refresh: pre-downloading \(missingItems.count) CDN image(s) before swap…")
                await withTaskGroup(of: Void.self) { group in
                    for item in missingItems {
                        group.addTask {
                            let url = item.imageURL
                            if let image = await self.downloadImageWithRetry(from: url, mediaId: item.mediaId, attempts: 3) {
                                await MainActor.run {
                                    self.cachedImages[url] = image
                                    ProfileCacheService.shared.saveImage(image, forURL: url)
                                    ProfileCacheService.shared.saveImage(image, forMediaId: item.mediaId)
                                }
                            }
                        }
                    }
                }
                let stillMissing = items.filter { item in
                    cachedImages[item.imageURL] == nil &&
                    ProfileCacheService.shared.loadImage(forURL: item.imageURL) == nil &&
                    ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) == nil
                }
                guard stillMissing.isEmpty else {
                    print("⚠️ [PERF] Silent refresh postponed — \(stillMissing.count) thumbnail(s) still missing after retry; keeping current grid to avoid gray video cells")
                    LogManager.shared.warning("Silent media refresh postponed: \(stillMissing.count) thumbnails missing after retry", category: .cache)
                    return
                }
                print("🔄 [PERF] Silent refresh: all CDN images cached — swapping grid now")
            } else {
                await MainActor.run {
                    for item in items {
                        if self.cachedImages[item.imageURL] == nil,
                           let image = ProfileCacheService.shared.loadImage(forURL: item.imageURL)
                            ?? ProfileCacheService.shared.loadImage(forMediaId: item.mediaId) {
                            self.cachedImages[item.imageURL] = image
                            ProfileCacheService.shared.saveImage(image, forMediaId: item.mediaId)
                        }
                    }
                }
            }

            if mode == .authoritative {
                let pendingRevealIds = Set(allMediaURLs.compactMap { url -> String? in
                    guard let mediaId = revealMediaId(from: url) else { return nil }
                    return mediaIdKey(mediaId)
                })
                let refreshedIds = Set(items.flatMap { item -> [String] in
                    guard !item.mediaId.isEmpty else { return [] }
                    return [item.mediaId, mediaIdKey(item.mediaId)]
                })
                let missingRevealIds = pendingRevealIds.subtracting(refreshedIds)

                // Preserve pending reveals for ANY authoritative refresh — not just ones
                // labelled "post prediction reconciliation". A manual pull-to-refresh also
                // goes through the authoritative path and must not wipe reveals whose
                // unarchived posts haven't appeared in Instagram's first page yet.
                if !missingRevealIds.isEmpty {
                    let isPostRevealReconciliation = reason.localizedCaseInsensitiveContains("reveal")
                        || reason.localizedCaseInsensitiveContains("post prediction")
                    if isPostRevealReconciliation {
                        print("🔄 [PERF] Authoritative refresh not ready — keeping \(missingRevealIds.count) reveal overlay(s)")
                        LogManager.shared.info("Post-reveal refresh kept local overlays; Instagram missing \(missingRevealIds.count) mediaId(s)", category: .general)
                    } else {
                        print("🔄 [PERF] Silent authoritative refresh has \(missingRevealIds.count) unconfirmed reveal(s) — falling through to merge path")
                    }
                } else {
                    applyAuthoritativeMediaSnapshot(
                        items: items,
                        nextCursor: refreshedMaxId,
                        source: reason,
                        clearRevealState: true
                    )
                    let newCount = newURLs.filter { !allMediaURLs.contains($0) }.count
                    print("🔄 [PERF] Authoritative silent refresh done — \(items.count) items, \(newCount) newly visible")
                    LogManager.shared.info("Authoritative silent refresh done: \(items.count) items", category: .general)
                    return
                }
            }

            // Atomic swap: reveal:// placeholders replaced with real CDN URLs.
            // All images are already in cache so no blank frames appear.
            let revealURLsBefore = allMediaURLs.filter { $0.hasPrefix("reveal://") }
            let cleanedExisting  = allMediaURLs.filter { !$0.hasPrefix("reveal://") }

            // Build existingTail by mediaId — NOT by URL string.
            // CDN URLs rotate per session, so the same post has different URL strings
            // between fetches. Comparing URL strings causes every previously-seen
            // post to land in existingTail, creating duplicates in the grid.
            var newMediaIds = Set<String>()
            for item in items where !item.mediaId.isEmpty {
                newMediaIds.insert(item.mediaId)
                newMediaIds.insert(mediaIdKey(item.mediaId))
            }
            for item in items { mediaItemsByURL[item.imageURL] = item }
            let existingTail = cleanedExisting.filter { url -> Bool in
                // Only keep URLs whose mediaId is known AND not covered by the new fetch.
                // Stale/orphan URLs (no matching item) are always discarded.
                guard let item = mediaItemsByURL[url] else { return false }
                return !newMediaIds.contains(item.mediaId) && !newMediaIds.contains(mediaIdKey(item.mediaId))
            }
            var merged = deduplicatedGridURLs(newURLs + existingTail)

            // ── Preserve unconfirmed reveal:// placeholders ───────────────────────
            // When a photo was uploaded with an old taken_at (grid anchor), it lives
            // BELOW the first 21 posts Instagram returns. The silent refresh won't
            // include its real CDN URL, so without this step the reveal:// placeholder
            // would simply be dropped and the photo would disappear from the fake grid.
            // Solution: any reveal:// whose mediaId is NOT yet in the CDN results is
            // re-inserted at the chronologically correct position so it stays visible
            // until a later refresh (or full reload) brings the real CDN URL.
            //
            // IMPORTANT: use the shared pinned-aware positioning helper. Profiles with
            // pinned posts have OLD dates at the top of the grid (e.g. a 2023 post pinned
            // at position 0). A naive "first item older than anchorDate" scan would match
            // that pinned post and wrongly insert the reveal at position 0. The helper
            // computes `pinnedEnd` (the newest post index) and only positions reveals
            // within the chronological region after the pinned block.
            let pendingRevealURLs = revealURLsBefore.filter { revealURL in
                let mediaId = String(revealURL.dropFirst("reveal://".count))
                if newMediaIds.contains(mediaId) || newMediaIds.contains(mediaIdKey(mediaId)) { return false }
                if merged.contains(revealURL) { return false }
                return true
            }
            if !pendingRevealURLs.isEmpty {
                let pendingRevealDates = revealDates.filter { pendingRevealURLs.contains($0.key) }
                merged = restoredGridURLsByPositioningRevealState(
                    baseURLs: merged,
                    revealURLs: pendingRevealURLs,
                    storedDates: pendingRevealDates
                )
                print("⚡️ [REVEAL PRESERVE] Positioned \(pendingRevealURLs.count) unconfirmed reveal(s) with pinned-aware helper")
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

            allMediaURLs = deduplicatedGridURLs(merged)
            nextMaxId = refreshedMaxId
            hasMorePages = refreshedMaxId != nil && allMediaURLs.count < maxPhotosOwnProfile
            // No local pagination suppression needed — `isLoadingMore` and the
            // SafetyGate cross-action pause already prevent another /feed/user/
            // call from firing right after a silent refresh.

            // Clear cached reveal dates only for placeholders that WERE replaced by real CDN URLs.
            // Preserved reveal:// URLs (still in merged) keep their cached date for future refreshes.
            let stillPresentRevealURLs = Set(allMediaURLs.filter { $0.hasPrefix("reveal://") })
            revealDates = revealDates.filter { stillPresentRevealURLs.contains($0.key) }
            persistCurrentRevealState()

            // Keep mediaItemsByURL in sync so removeMediaItem(byMediaId:) can resolve fresh URLs.
            for item in items { mediaItemsByURL[item.imageURL] = item }

            // Persist both URLs and items — this keeps cachedMediaItems fresh so that
            // removeMediaItem(byMediaId:) can find the correct CDN URL to remove.
            ProfileCacheService.shared.updateMediaURLsAndItems(allMediaURLs, items: items)

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
        guard ppTestMode.isActive || (instagram.isLoggedIn && !instagram.isLocked) else {
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

        if ppTestMode.isActive {
            guard let uiImage = UIImage(data: imageData) else { return }
            applyTestProfilePicture(uiImage)
            print("🧪 [TEST MODE] Auto profile picture painted locally — no Instagram upload")
            LogManager.shared.info("TEST MODE — auto profile picture painted locally", category: .general)
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

private struct TranspositionBlackScreenOverlay: View {
    let isReady: Bool
    let onSwipeUp: () -> Void
    @State private var isDismissing = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)
                if isReady {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .position(x: geo.size.width - 16, y: geo.size.height - 34)
                }
            }
            .offset(y: isDismissing ? -geo.size.height * 0.18 : 0)
            .opacity(isDismissing ? 0 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onEnded { value in
                        guard isReady,
                              value.translation.height < -44,
                              abs(value.translation.height) > abs(value.translation.width) else { return }
                        withAnimation(.easeInOut(duration: 0.32)) {
                            isDismissing = true
                        }
                        onSwipeUp()
                    }
            )
        }
        .background(Color.black.ignoresSafeArea(.all))
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

/// Invisible UIViewRepresentable attached to the ScrollView content tree.
/// Walks UP the UIKit superview chain to reach the UIScrollView, then sets
/// both `isEnabled` and `isHidden` on its `refreshControl` so the spinner
/// never appears when refresh is on cooldown.
///
/// Also repairs a layout glitch on Performance entry (especially cold launch with
/// "Launch directly to Performance"): the scroll view can rest at y=0 instead of
/// the correct negative inset offset, making the profile appear shifted upward.
private struct RefreshControlEnabler: UIViewRepresentable {
    let isEnabled: Bool
    /// Incremented on each InstagramProfileView.onAppear to re-run layout repair.
    let fixToken: Int
    /// Positive points to lift the initial Performance scroll. Used only for
    /// Bio Cover Typing so the biography is hidden when the magician enters.
    let initialContentLift: CGFloat

    class Coordinator: NSObject {
        weak var scrollView: UIScrollView?
        weak var observedRefreshControl: UIRefreshControl?
        var lastFixToken: Int = -1
        var lastInitialContentLift: CGFloat = -1

        @objc func refreshControlDidBegin(_ sender: UIRefreshControl) {
            sender.alpha = 1
            sender.isHidden = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.alpha = 0
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastFixToken != fixToken || coordinator.lastInitialContentLift != initialContentLift {
            coordinator.lastFixToken = fixToken
            coordinator.lastInitialContentLift = initialContentLift
        }

        apply(isEnabled, uiView: uiView, coordinator: coordinator, forceLayoutFix: true)

        let enabled = isEnabled
        let token = fixToken
        for delay in [0.05, 0.15, 0.35, 0.7, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard coordinator.lastFixToken == token else { return }
                apply(enabled, uiView: uiView, coordinator: coordinator, forceLayoutFix: true)
            }
        }
    }

    private func apply(_ enabled: Bool,
                       uiView: UIView,
                       coordinator: Coordinator,
                       forceLayoutFix: Bool) {
        guard let scroll = resolveScrollView(from: uiView, coordinator: coordinator) else { return }

        if let rc = scroll.refreshControl {
            rc.isEnabled = enabled
            rc.isHidden  = !enabled
            if coordinator.observedRefreshControl !== rc {
                coordinator.observedRefreshControl?.removeTarget(
                    coordinator,
                    action: #selector(Coordinator.refreshControlDidBegin(_:)),
                    for: .valueChanged
                )
                rc.addTarget(
                    coordinator,
                    action: #selector(Coordinator.refreshControlDidBegin(_:)),
                    for: .valueChanged
                )
                coordinator.observedRefreshControl = rc
            }
            if initialContentLift > 0, !rc.isRefreshing {
                rc.alpha = 0
            } else {
                rc.isHidden = !enabled
                rc.alpha = 1
            }
        }

        if forceLayoutFix {
            fixPerformanceScrollLayoutIfNeeded(on: scroll)
        }
    }

    private func resolveScrollView(from uiView: UIView,
                                   coordinator: Coordinator) -> UIScrollView? {
        if let cached = coordinator.scrollView { return cached }

        var current: UIView? = uiView
        for _ in 0..<30 {
            guard let view = current else { break }
            if let scroll = view as? UIScrollView {
                coordinator.scrollView = scroll
                return scroll
            }
            current = view.superview
        }
        return nil
    }

    private func fixPerformanceScrollLayoutIfNeeded(on scroll: UIScrollView) {
        guard !scroll.isDragging, !scroll.isTracking, !scroll.isDecelerating else { return }

        let refreshControl = scroll.refreshControl
        if refreshControl?.isRefreshing == true {
            refreshControl?.endRefreshing()
        }
        if initialContentLift > 0, refreshControl?.isRefreshing != true {
            refreshControl?.alpha = 0
        }

        scroll.layoutIfNeeded()

        // With UIRefreshControl the natural resting offset is NEGATIVE, not zero.
        // Resting at y=0 makes the profile header sit too high on screen.
        let restingTop = -scroll.adjustedContentInset.top
        let maxScrollableY = max(restingTop, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let expectedTop = min(restingTop + max(0, initialContentLift), maxScrollableY)
        let currentY = scroll.contentOffset.y
        let tooHigh = currentY > expectedTop + 1
        let tooPulledDown = currentY < expectedTop - 12

        guard tooHigh || tooPulledDown else { return }

        scroll.setContentOffset(CGPoint(x: 0, y: expectedTop), animated: false)
        print("🔄 [SCROLL] Corrected Performance scroll offset \(String(format: "%.1f", currentY)) → \(String(format: "%.1f", expectedTop)) lift:\(String(format: "%.1f", initialContentLift))")
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
    var scrollLayoutFixToken: Int = 0
    var initialContentLift: CGFloat = 0
    let onPlusPress: () -> Void
    @Binding var highlightsLoadedOnce: Bool
    var aiScreenFollowingOverride: String? = nil
    var aiScreenFollowingLabelOverride: String? = nil
    var aiScreenProfileNameOverride: String? = nil
    var transpositionGridEffect: TranspositionGridEffectPayload? = nil
    var transpositionScrollToken: Int = 0
    @State private var selectedTab = 0
    @State private var measuredSecretGridWidth: CGFloat = 0

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
    @AppStorage("combined_pp_cooldown_bypass_until") private var combinedPPCooldownBypassUntil: Double = 0
    @AppStorage("local_combo_earliest_pp_reveal_at") private var localComboEarliestRevealAt: Double = 0
    @AppStorage("local_combo_bio_pending_until") private var localComboBioPendingUntil: Double = 0
    @AppStorage("local_combo_cover_typing_bio_ready") private var coverTypingBioReadyForPP: Bool = false
    /// Must stay in sync with `combinedBioPostPredictionDelay` above.
    /// Used when Bio (Cover Typing / OCR / API) and PP (Lockscreen) are separate inputs.
    private let localComboPostPredictionDelay: TimeInterval = 12
    /// Max time Lockscreen PP will wait for a later Cover Typing bio confirmation.
    private let coverTypingBioAwaitTimeout: TimeInterval = 120

    // Error alert for when reveal fails (e.g. set not uploaded)
    @State private var revealErrorTitle: String = ""
    @State private var revealErrorMessage: String = ""
    @State private var showRevealError: Bool = false
    @State private var didShowUnsupportedTestSetAlert = false

    // Called after a successful Force Number Reveal with local images already loaded.
    // Each element: pseudo-URL key + optional UIImage from local storage.
    // PerformanceView inserts them into the grid immediately (no GET needed).
    /// Inserts local images into the grid immediately — does NOT trigger CDN refresh.
    /// Use before API unarchive calls so images appear before Instagram processes them.
    var onAddLocalImages: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil
    /// Removes previously-painted local reveal overlays if Instagram rejects the action.
    var onRemoveLocalImages: (([String]) -> Void)? = nil
    /// Called after all API unarchives complete — inserts any remaining images AND triggers CDN refresh.
    var onRevealComplete: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil
    /// Called immediately when Amnesia starts, before Instagram confirms the swap.
    var onAmnesiaRevealStarted: (() -> Void)? = nil
    /// Called if the real Instagram swap fails after the optimistic local paint.
    var onAmnesiaRevealFailed: (() -> Void)? = nil
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
    /// Prevents more than one card reveal while the user remains in Performance.
    @Binding var cardRevealConsumedThisPerformance: Bool
    /// Called whenever the Posts/Reels/Tagged tab changes so PerformanceView can
    /// trigger lazy loading of secondary tabs on first visit.
    var onTabSelected: ((Int) -> Void)? = nil
    /// Called when a secret input interface (Lockscreen / Number Clock / Card Clock)
    /// captures a value, so PerformanceView can inject it into bio/note {textN} slots
    /// configured for that interface kind and send the note/biography.
    var onInterfaceCapture: ((String, Set<InterfaceKind>) -> Void)? = nil
    /// Set by PerformanceView after FakeNotesInputView commits lines.
    @Binding var pendingFakeNotesLines: [String]?
    /// Called when pendingFakeNotesLines changes so PerformanceView can route the lines.
    var onFakeNotesCapture: (([String]) -> Void)? = nil

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
    @ObservedObject private var ppTestMode         = PostPredictionTestMode.shared
    @ObservedObject private var volumeMonitor      = VolumeButtonMonitor.shared
    @State private var followingOverride: String?   = nil
    @State private var followerOverride: String?    = nil

    @discardableResult
    private func captureGridSideEffects(digits: [Int], source: String) -> Bool {
        guard !digits.isEmpty else { return false }

        let capturedNumber = safeNumber(fromDigits: digits)
        var didCapture = false

        if FollowingMagicSettings.shared.isEnabled {
            FollowingMagicSettings.shared.capture(digits: digits, source: source)
            didCapture = true
        }

        if ForceReelSettings.shared.isEnabled,
           ForceReelSettings.shared.hasReel {
            if let capturedNumber, capturedNumber > 0 {
                ForceReelSettings.shared.pendingPosition = capturedNumber
                print("🎭 [FORCE] Position captured from \(source): \(capturedNumber)")
                didCapture = true
            } else if capturedNumber == nil {
                LogManager.shared.warning("Grid side effects skipped Force Reel: digit buffer overflow from \(source)", category: .profile)
            }
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
        if ActiveSetSettings.shared.isPostPredictionEnabled,
           let activeId = ActiveSetSettings.shared.activeSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId }),
           (activeSet.type == .number || activeSet.type == .custom),
           activeSet.resolvedInputMethod == .digitGrid {
            return activeSet
        }

        return nil
    }

    private var activePostPredictionInputMethod: InputMethod? {
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeSetId else { return nil }
        return DataManager.shared.sets.first { $0.id == activeId }?.resolvedInputMethod
    }

    private var isDigitGridInputActive: Bool {
        activeDigitGridSet != nil
    }

    private var isForceReelGridInputActive: Bool {
        ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel
    }

    private var shouldCaptureDigitGridCellInput: Bool {
        isDigitGridInputActive
            || followingMagic.isEnabled
            || isForceReelGridInputActive
            || (ForceNumberRevealSettings.shared.isEnabled && ForceNumberRevealSettings.shared.gridSwipeEnabled)
    }

    /// Bio uses Cover Typing and PP uses Lockscreen: hold unarchives until bio is confirmed.
    private var expectsCoverTypingBioBeforePostPrediction: Bool {
        guard !PostPredictionTestMode.shared.isActive else { return false }
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              ActiveSetSettings.shared.activeSetId != nil else { return false }
        let bioEnabled = UserDefaults.standard.object(forKey: "bio_feature_enabled") == nil
            || UserDefaults.standard.bool(forKey: "bio_feature_enabled")
        guard bioEnabled else { return false }
        let bioMode = UserDefaults.standard.string(forKey: "bioTopInputMode") ?? "off"
        return bioMode == "coverTyping"
    }

    /// When Lockscreen commits first, park PP until Cover Typing confirms the bio.
    /// Skipped if Cover Typing already succeeded earlier in this Performance session.
    private func beginAwaitingCoverTypingBioBeforePostPredictionIfNeeded() {
        guard expectsCoverTypingBioBeforePostPrediction else { return }
        if coverTypingBioReadyForPP {
            print("🔗 [LOCAL COMBO] Cover Typing bio already ready — Lockscreen PP not held")
            return
        }
        let now = Date().timeIntervalSince1970
        if localComboBioPendingUntil > now {
            print("🔗 [LOCAL COMBO] Bio already in-flight — Lockscreen PP will wait")
            return
        }
        localComboBioPendingUntil = now + coverTypingBioAwaitTimeout
        localComboEarliestRevealAt = 0
        combinedPPCooldownBypassUntil = now + coverTypingBioAwaitTimeout + 90
        UserDefaults.standard.set(localComboBioPendingUntil, forKey: "local_combo_bio_pending_until")
        UserDefaults.standard.set(localComboEarliestRevealAt, forKey: "local_combo_earliest_pp_reveal_at")
        UserDefaults.standard.set(combinedPPCooldownBypassUntil, forKey: "combined_pp_cooldown_bypass_until")
        print("🔗 [LOCAL COMBO] Lockscreen held — waiting up to \(Int(coverTypingBioAwaitTimeout))s for Cover Typing bio before unarchive")
        LogManager.shared.info("Local Bio + PP: Lockscreen waiting for Cover Typing bio", category: .general)
    }

    private func waitForLocalBioPostPredictionComboIfNeeded() async -> Bool {
        guard !PostPredictionTestMode.shared.isActive else { return true }

        var now = Date().timeIntervalSince1970
        let defaults = UserDefaults.standard
        let pendingKey = "local_combo_bio_pending_until"
        let earliestKey = "local_combo_earliest_pp_reveal_at"
        var pendingUntil = defaults.double(forKey: pendingKey)
        let waitedForBioConfirmation = pendingUntil > now
        if pendingUntil > now {
            print("🔗 [LOCAL COMBO] Waiting for bio confirmation before Post Prediction")
            LogManager.shared.info("Local Bio + PP waiting for biography confirmation", category: .general)
        }
        while pendingUntil > now {
            let waitSeconds = min(0.25, max(0, pendingUntil - now))
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            now = Date().timeIntervalSince1970
            pendingUntil = defaults.double(forKey: pendingKey)
        }

        now = Date().timeIntervalSince1970
        let earliestRevealAt = defaults.double(forKey: earliestKey)
        guard earliestRevealAt > now else {
            if earliestRevealAt > 0, now > earliestRevealAt + 90 {
                await MainActor.run { localComboEarliestRevealAt = 0 }
            }
            if waitedForBioConfirmation {
                print("🔗 [LOCAL COMBO] Bio did not confirm — cancelling Post Prediction reveal")
                LogManager.shared.warning("Local Bio + PP reveal cancelled because biography did not confirm", category: .general)
                return false
            }
            return true
        }

        let waitSeconds = earliestRevealAt - now
        print("🔗 [LOCAL COMBO] Waiting \(String(format: "%.1f", waitSeconds))s before Post Prediction")
        LogManager.shared.info("Local Bio + PP waiting \(Int(ceil(waitSeconds)))s before reveal", category: .general)
        try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
        return true
    }

    private func preArmLocalBioPostPredictionDelayIfNeeded(kinds: Set<InterfaceKind>) {
        guard !PostPredictionTestMode.shared.isActive,
              ActiveSetSettings.shared.isPostPredictionEnabled,
              ActiveSetSettings.shared.activeSetId != nil else { return }

        let bioEnabled = UserDefaults.standard.object(forKey: "bio_feature_enabled") == nil
            || UserDefaults.standard.bool(forKey: "bio_feature_enabled")
        guard bioEnabled else { return }

        let sources = IntegrationsSettings.shared.bioSources()
        let bioUsesThisInterface = sources.contains { source in
            guard let kind = source.interfaceKind else { return false }
            return kinds.contains(kind)
        }
        guard bioUsesThisInterface else { return }

        let earliest = Date().timeIntervalSince1970 + localComboPostPredictionDelay
        if localComboEarliestRevealAt < earliest {
            localComboEarliestRevealAt = earliest
            print("🔗 [LOCAL COMBO] Pre-armed \(Int(localComboPostPredictionDelay))s delay for shared Bio input")
            LogManager.shared.info("Local Bio + PP pre-armed by shared interface input", category: .general)
        }
    }

    @MainActor
    private func showPostPredictionTestError(_ message: String) {
        revealErrorTitle = "Test unavailable"
        revealErrorMessage = message
        showRevealError = true
        clearOCRPeek()
    }

    @MainActor
    private func ensureRevealBudget(requiredActions: Int) -> Bool {
        guard requiredActions > 0 else { return true }
        let rate = InstagramService.shared.checkRateLimit()
        guard !rate.limited && rate.remaining >= requiredActions else {
            revealErrorTitle = "No credits available"
            if rate.remaining <= 0 {
                revealErrorMessage = "You have no Instagram action credits left right now. Wait for the hourly budget to recover before revealing."
            } else {
                revealErrorMessage = "This reveal needs about \(requiredActions) Instagram action credits, but only \(rate.remaining) remain. Wait for the hourly budget to recover before revealing."
            }
            showRevealError = true
            clearOCRPeek()
            CrashLoggerService.shared.recordAction("Reveal blocked: insufficient API credits")
            LogManager.shared.warning("Reveal blocked: required \(requiredActions), remaining \(rate.remaining), used \(rate.actionsUsed)/55", category: .general)
            return false
        }
        return true
    }

    @MainActor
    private func consumeCardRevealSlot(source: String) -> Bool {
        guard !cardRevealConsumedThisPerformance else {
            secretManager.reset()
            followingOverride = nil
            followerOverride = nil
            LogManager.shared.warning("Card reveal ignored: already used this Performance entry (\(source))", category: .general)
            CrashLoggerService.shared.recordAction("Card reveal ignored: already consumed")
            return false
        }
        guard PostPredictionTestMode.shared.isActive || !InstagramService.shared.isRevealOperationActive else {
            LogManager.shared.warning("Card reveal ignored: another reveal is already active (\(source))", category: .general)
            return false
        }
        cardRevealConsumedThisPerformance = true
        CrashLoggerService.shared.recordAction("Card reveal consumed from \(source)")
        return true
    }

    @MainActor
    private func beginRevealOperation(kind: String) -> Bool {
        guard !InstagramService.shared.isRevealOperationActive else {
            secretManager.reset()
            followingOverride = nil
            followerOverride = nil
            clearOCRPeek()
            LogManager.shared.warning("\(kind) reveal ignored: another reveal is already active", category: .general)
            CrashLoggerService.shared.recordAction("\(kind) reveal ignored: busy")
            return false
        }
        InstagramService.shared.isRevealOperationActive = true
        CrashLoggerService.shared.recordAction("\(kind) reveal started")
        return true
    }

    @MainActor
    private func endRevealOperation(kind: String) {
        InstagramService.shared.isRevealOperationActive = false
        CrashLoggerService.shared.recordAction("\(kind) reveal ended")
    }

    private func showUnsupportedTestSetAlertIfNeeded() {
        guard PostPredictionTestMode.shared.isActive,
              !didShowUnsupportedTestSetAlert,
              ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeSetId,
              let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId }),
              activeSet.type == .custom || activeSet.type == .card || activeSet.type == .list,
              !hasAnyReadyTestPhoto(in: activeSet) else { return }

        didShowUnsupportedTestSetAlert = true
        revealErrorTitle = "Test unavailable"
        revealErrorMessage = activeSet.type == .card
            ? "This card set has no photos yet. Create a new card set using a card template, or open the set and upload the card images manually."
            : "\(activeSet.type.title) sets do not support templates. Test Mode can use this set only after you upload photos to it."
        showRevealError = true
    }

    private func testReadyBankCount(in set: PhotoSet) -> Int {
        set.banks.filter { bank in
            set.photos.contains { photo in
                photo.bankId == bank.id && photo.imageData != nil
            }
        }.count
    }

    private func shouldUseSetPhotosInTest(set: PhotoSet) -> Bool {
        switch set.type {
        case .word, .number:
            return testReadyBankCount(in: set) > 3
        case .custom, .card, .list:
            return true
        }
    }

    private func ensureSetPhotoBanksAvailable(set: PhotoSet, requiredBankCount: Int, inputDescription: String) async -> Bool {
        let readyCount = testReadyBankCount(in: set)
        let availableCount = min(set.banks.count, readyCount)
        guard set.banks.count >= requiredBankCount, readyCount >= requiredBankCount else {
            await showPostPredictionTestError(
                "\(inputDescription) needs \(requiredBankCount) banks, but this set only has \(availableCount) ready bank(s). Add more banks/photos or switch Test Mode to Templates."
            )
            return false
        }
        return true
    }

    private func testPhotoFromSet(_ set: PhotoSet, bankIndex: Int, symbol: String) -> SetPhoto? {
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        guard sortedBanks.indices.contains(bankIndex) else { return nil }
        let bank = sortedBanks[bankIndex]
        return set.photos.first { photo in
            photo.bankId == bank.id
                && photo.symbol.caseInsensitiveCompare(symbol) == .orderedSame
                && photo.imageData != nil
        }
    }

    private func testPhotoFromSet(_ set: PhotoSet, symbol: String) -> SetPhoto? {
        set.photos.first { photo in
            photo.symbol.caseInsensitiveCompare(symbol) == .orderedSame
                && photo.imageData != nil
        }
    }

    private func hasAnyReadyTestPhoto(in set: PhotoSet) -> Bool {
        set.photos.contains { $0.imageData != nil }
    }

    private func insertTestPhotos(_ photos: [(pseudoURL: String, image: UIImage?)], logMessage: String) async {
        await MainActor.run {
            ppTestMode.markInserted(photos.map(\.pseudoURL))
            onAddLocalImages?(photos)
            clearOCRPeek()
        }
        print(logMessage)
    }

    private func revealTestSlot(symbol: String, label: String, fromSet set: PhotoSet) async {
        guard ppTestMode.isTesting(set) else { return }

        // 1. Try uploaded / template-populated image stored in the set.
        if let photo = testPhotoFromSet(set, symbol: symbol),
           let data = photo.imageData,
           let image = UIImage(data: data) {
            let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "set-\(label)-\(symbol)", index: 0)
            await insertTestPhotos(
                [(pseudoURL: pseudoURL, image: image)],
                logMessage: "🧪 [PP TEST] Inserted local \(label) image from set '\(set.name)'"
            )
            return
        }

        // 2. Fallback: load directly from the bundle card template (same as number/word sets do).
        if set.type == .card, let template = ppTestMode.cardTemplate,
           let data = TemplateManager.shared.cardImageData(for: symbol, template: template),
           let image = UIImage(data: data) {
            let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "card-tmpl-\(symbol)", index: 0)
            await insertTestPhotos(
                [(pseudoURL: pseudoURL, image: image)],
                logMessage: "🧪 [PP TEST] Inserted card template image '\(symbol)' from bundle template '\(template.name)'"
            )
            return
        }

        // 3. No image available anywhere.
        let hint = set.type == .card
            ? "No card template found in the app bundle. Make sure at least one card template is included."
            : "No image found for '\(symbol)' in this set. Upload photos to use Test Mode with \(set.type.title) sets."
        await showPostPredictionTestError(hint)
    }

    private func revealTestDigits(_ digits: [Int], fromSet set: PhotoSet) async {
        guard ppTestMode.isTesting(set) else { return }

        let reversedDigits = Array(digits.reversed())
        if shouldUseSetPhotosInTest(set: set) {
            guard await ensureSetPhotoBanksAvailable(
                set: set,
                requiredBankCount: reversedDigits.count,
                inputDescription: "This number"
            ) else { return }

            var setPhotos: [(pseudoURL: String, image: UIImage?)] = []
            for (index, digit) in reversedDigits.enumerated() {
                let symbol = String(digit)
                guard let photo = testPhotoFromSet(set, bankIndex: index, symbol: symbol),
                      let data = photo.imageData,
                      let image = UIImage(data: data) else {
                    await showPostPredictionTestError("The selected set photo source is missing digit \(symbol) in bank \(index + 1).")
                    return
                }

                let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "set-digit-\(symbol)", index: index)
                setPhotos.append((pseudoURL: pseudoURL, image: image))
            }

            if !setPhotos.isEmpty {
                await insertTestPhotos(
                    setPhotos,
                    logMessage: "🧪 [PP TEST] Inserted \(setPhotos.count) digit image(s) from set '\(set.name)'"
                )
                return
            }
        }

        guard let template = ppTestMode.numberTemplate else {
            await showPostPredictionTestError("No number template is available for Test Mode.")
            return
        }

        var photos: [(pseudoURL: String, image: UIImage?)] = []

        for (index, digit) in reversedDigits.enumerated() {
            let symbol = String(digit)
            guard let data = TemplateManager.shared.numberImageData(for: symbol, template: template),
                  let image = UIImage(data: data) else {
                await showPostPredictionTestError("The selected number template is missing image \(symbol).")
                return
            }

            let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "digit-\(symbol)", index: index)
            photos.append((pseudoURL: pseudoURL, image: image))
        }

        await insertTestPhotos(
            photos,
            logMessage: "🧪 [PP TEST] Inserted \(photos.count) digit template image(s) for '\(set.name)'"
        )
    }

    private func revealTestLetters(_ word: String, fromSet set: PhotoSet) async {
        guard ppTestMode.isTesting(set) else { return }

        let alphabet = set.selectedAlphabet ?? .latin
        let normalizedWord = word.lowercased()
        let letters: [String] = alphabet.isRightToLeft
            ? normalizedWord.map { String($0) }
            : normalizedWord.reversed().map { String($0) }
        if shouldUseSetPhotosInTest(set: set) {
            guard await ensureSetPhotoBanksAvailable(
                set: set,
                requiredBankCount: letters.count,
                inputDescription: "The word \"\(word)\""
            ) else { return }

            var setPhotos: [(pseudoURL: String, image: UIImage?)] = []
            for (index, letter) in letters.enumerated() {
                guard let charIndex = alphabet.indexFor(letter) else {
                    await showPostPredictionTestError("The letter \(letter.uppercased()) is not part of this set alphabet.")
                    return
                }
                let symbol = alphabet.characters[charIndex]
                guard let photo = testPhotoFromSet(set, bankIndex: index, symbol: symbol),
                      let data = photo.imageData,
                      let image = UIImage(data: data) else {
                    await showPostPredictionTestError("The selected set photo source is missing \(symbol.uppercased()) in bank \(index + 1).")
                    return
                }

                let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "set-letter-\(symbol)", index: index)
                setPhotos.append((pseudoURL: pseudoURL, image: image))
            }

            if !setPhotos.isEmpty {
                await insertTestPhotos(
                    setPhotos,
                    logMessage: "🧪 [PP TEST] Inserted \(setPhotos.count) letter image(s) from set '\(set.name)'"
                )
                return
            }
        }

        guard let template = ppTestMode.letterTemplate else {
            await showPostPredictionTestError("No letter template is available for this alphabet in Test Mode.")
            return
        }

        var photos: [(pseudoURL: String, image: UIImage?)] = []

        for (index, letter) in letters.enumerated() {
            guard let charIndex = alphabet.indexFor(letter) else {
                await showPostPredictionTestError("The letter \(letter.uppercased()) is not part of this set alphabet.")
                return
            }

            let symbol = alphabet.characters[charIndex]
            guard let data = TemplateManager.shared.imageData(for: symbol, template: template),
                  let image = UIImage(data: data) else {
                await showPostPredictionTestError("The selected letter template is missing image \(symbol).")
                return
            }

            let pseudoURL = ppTestMode.makePseudoURL(setId: set.id, token: "letter-\(symbol)", index: index)
            photos.append((pseudoURL: pseudoURL, image: image))
        }

        await insertTestPhotos(
            photos,
            logMessage: "🧪 [PP TEST] Inserted \(photos.count) letter template image(s) for '\(set.name)'"
        )
    }

    private var activeCardClockSet: PhotoSet? {
        guard !cardRevealConsumedThisPerformance,
              let activeId = ActiveSetSettings.shared.activeCardSetId,
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

    private func isAmnesiaCarouselIndex(_ index: Int) -> Bool {
        guard amnesiaSettings.isEnabled, amnesiaSettings.isReady else { return false }
        let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
        guard urlsToShow.indices.contains(index) else { return false }

        let url = urlsToShow[index]
        let item = mediaItemsByURL[url]
        let ids = [amnesiaSettings.shortCarouselMediaId, amnesiaSettings.fullCarouselMediaId].compactMap { $0 }
        return url.hasPrefix("amnesia://carousel/")
            || ids.contains { id in item?.mediaId == id || url.contains(id) }
    }

    private func isInstapickCarouselIndex(_ index: Int) -> Bool {
        guard InstapickSettings.shared.isReadyForPerformance else { return false }
        let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
        guard urlsToShow.indices.contains(index) else { return false }

        let url = urlsToShow[index]
        let item = mediaItemsByURL[url]
        if url.hasPrefix("instapick://") { return true }
        if item?.mediaId == InstapickSettings.testMediaId { return true }
        if let liveId = InstapickSettings.shared.carouselMediaId,
           item?.mediaId == liveId || url.contains(liveId) {
            return true
        }
        return false
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    InstagramHeaderView(
                        username: aiScreenProfileNameOverride ?? profile.username,
                        isVerified: profile.isVerified,
                        onRefresh: onRefresh,
                        onPlusPress: onPlusPress
                    )
                    profileInfoSection
                        .padding(.top, 12)
                    tabBarSection
                    Divider()
                    tabTapSafetySpacer
                    tabContentSection
                        .id("profile-grid")
                    // Bottom spacer so the last row of the grid can always be scrolled
                    // fully above the floating pill (~54 pt pill height + 8 pt bottom gap + 32 pt margin).
                    Color.clear.frame(height: 94)
                }
                .background(
                    RefreshControlEnabler(
                        isEnabled: isRefreshEnabled,
                        fixToken: scrollLayoutFixToken,
                        initialContentLift: initialContentLift
                    )
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .allowsHitTesting(false)
                )
            }
            .onChange(of: transpositionScrollToken) { token in
                guard token > 0 else { return }
                selectedTab = 0
                withAnimation(.easeInOut(duration: 0.55)) {
                    proxy.scrollTo("profile-grid", anchor: .top)
                }
            }
        }
        .onAppear {
            showUnsupportedTestSetAlertIfNeeded()
            applyPendingTransferDeflation()
            logVisibleCountState(reason: "profile appear")
        }
        .onChange(of: followingMagic.transferOffset) { _ in
            applyPendingTransferDeflation()
        }
        .onChange(of: followingMagic.isEnabled) { enabled in
            guard !enabled else { return }
            followingOverride = nil
            followerOverride = nil
            followingMagic.transferOffset = 0
            followingMagic.isTransferCounting = false
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
        .onAppear { replayMissedPendingRevealsIfNeeded() }
        // Keep following count display in sync with digit / card buffers
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
        .onChange(of: secretManager.cardSwipeBuffer) { _ in
            updateFollowingOverride()
        }
        // Instapick: volume DOWN while a color page is open arms the card overlay
        // (must run here — PostScrollView is a fullScreenCover above PerformanceView).
        .onChange(of: volumeMonitor.upCount) { _ in
            // Transfer effect: volume UP on own profile inflates count by saved offset
            guard followingMagic.isEnabled else {
                followingOverride = nil
                followerOverride = nil
                followingMagic.transferOffset = 0
                followingMagic.isTransferCounting = false
                return
            }
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
        .onChange(of: volumeMonitor.downCount) { _ in
            _ = InstapickSettings.shared.tryBeginOverlayFromVolume()
        }
        .overlay {
            if showTransferGlitch {
                GlitchOverlayView {
                    showTransferGlitch = false
                    startTransferInflation()
                }
            }
        }
        .onChange(of: showTransferGlitch) { value in
            let message = "VISUAL transferGlitch=\(value) followingEnabled:\(followingMagic.isEnabled) transferEnabled:\(followingMagic.transferEnabled) offset:\(followingMagic.transferOffset)"
            print("🧭 [VISUAL] \(message)")
            LogManager.shared.info(message, category: .general)
        }
        .onChange(of: pendingOCRWord) { word in
            handlePendingOCRWordChange(word)
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
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCustomSlot(slot, fromSet: activeSet)
            }
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
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCustomSlot(slot, fromSet: activeSet)
            }
        }
        // ── URL-scheme: Playing Card reveal ─────────────────────────────────────
        .onChange(of: pendingCardReveal) { symbol in
            guard let symbol = symbol, !symbol.isEmpty else { return }
            pendingCardReveal = nil
            guard SetType.cardSlotLabels.contains(symbol) else {
                print("⚠️ [CARD] pendingCardReveal: '\(symbol)' is not a valid card symbol")
                return
            }
            guard consumeCardRevealSlot(source: "pendingCardReveal") else { return }
            // Feed the localized card name into any bio/note slot configured for a card
            // interface (Card Clock, Numpad Card, Card Lockscreen, or URL scheme).
            if let comp = cardComponents(fromSymbol: symbol) {
                preArmLocalBioPostPredictionDelayIfNeeded(kinds: [.cardClock, .cardNumpad, .cardLockscreen])
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
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCardSlot(symbol: symbol, fromSet: activeSet)
            }
        }
        // ── Fake lockscreen: Number / Custom / Playing Card reveal ──────────────
        .onChange(of: pendingLockscreenDigits) { digits in
            guard let digits = digits, !digits.isEmpty else { return }
            pendingLockscreenDigits = nil
            routeDigitsFromLockscreen(digits)
        }
        // ── Notes Input: route captured lines to bio/note slots or word set ──────
        .onChange(of: pendingFakeNotesLines) { lines in
            guard let lines = lines, !lines.isEmpty else { return }
            pendingFakeNotesLines = nil
            onFakeNotesCapture?(lines)
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

    private func replayMissedPendingRevealsIfNeeded() {
        // SwiftUI's onChange does not fire for an initial non-nil binding value.
        // List input can be selected before InstagramProfileView mounts, so replay
        // pending values once the profile view appears.
        if let word = pendingOCRWord, !word.isEmpty {
            pendingOCRWord = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingOCRWord = word }
        }
        if let slot = pendingSlotReveal {
            pendingSlotReveal = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingSlotReveal = slot }
        }
        if let slot = pendingListReveal {
            pendingListReveal = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingListReveal = slot }
        }
        if let symbol = pendingCardReveal, !symbol.isEmpty {
            pendingCardReveal = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingCardReveal = symbol }
        }
        if let digits = pendingLockscreenDigits, !digits.isEmpty {
            pendingLockscreenDigits = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingLockscreenDigits = digits }
        }
        if let lines = pendingFakeNotesLines, !lines.isEmpty {
            pendingFakeNotesLines = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pendingFakeNotesLines = lines }
        }
    }

    private func handlePendingOCRWordChange(_ word: String?) {
        guard let word = word, !word.isEmpty else { return }
        pendingOCRWord = nil

        let fromURL = ForceNumberRevealSettings.shared.urlRevealActive
        ForceNumberRevealSettings.shared.urlRevealActive = false

        guard ppTopInputMode == "ocr" || activePostPredictionInputMethod == .ocr || fromURL else { return }
        guard ppTestMode.isActive || !UploadManager.shared.isActive else {
            print("⚠️ [OCR-PP] Reveal blocked: upload is active")
            return
        }

        let bypassInterRevealCooldown = fromURL && Date().timeIntervalSince1970 < combinedPPCooldownBypassUntil
        if !ppTestMode.isActive && !bypassInterRevealCooldown {
            let timeSinceLastReveal = Date().timeIntervalSince1970 - lastRevealCompletedTimestamp
            if timeSinceLastReveal < interRevealCooldown {
                let remaining = Int(interRevealCooldown - timeSinceLastReveal)
                print("🚫 [OCR-PP] Reveal blocked — inter-reveal cooldown active (\(remaining)s remaining)")
                LogManager.shared.warning("PP reveal blocked: cooldown \(remaining)s remaining (anti-bot)", category: .api)
                return
            }
        } else if bypassInterRevealCooldown {
            print("🔗 [COMBO] Inter-reveal cooldown bypassed for queued URL Post Prediction")
            LogManager.shared.info("Combined Bio + PP bypassed inter-reveal cooldown", category: .general)
        }

        guard ppTestMode.isActive || !InstagramService.shared.isUploadingProfilePic else {
            print("⚠️ [OCR-PP] Reveal blocked: profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("OCR reveal blocked: profile pic upload active", category: .general)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !InstagramService.shared.isUploadingProfilePic else {
                    print("⚠️ [OCR-PP] Reveal still blocked after 3s wait — aborting")
                    return
                }
                await MainActor.run { pendingOCRWord = word }
            }
            return
        }

        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.precomposedStringWithCanonicalMapping
        if normalized.allSatisfy({ $0.isNumber }) {
            handleNumericOCRPostPrediction(normalized)
        } else {
            handleWordOCRPostPrediction(normalized)
        }
    }

    private func handleNumericOCRPostPrediction(_ cleaned: String) {
        let digits = cleaned.compactMap { Int(String($0)) }
        guard !digits.isEmpty,
              let activeId = ActiveSetSettings.shared.activeNumberSetId,
              let set = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) else {
            print("⚠️ [OCR-PP] No active number set for '\(cleaned)'")
            return
        }

        print("📷 [OCR-PP] Numeric '\(cleaned)' → revealByDigits \(digits)")
        LogManager.shared.info("OCR Post Prediction (numeric): \(cleaned)", category: .general)
        showOCRPeek(number: cleaned)
        Task {
            guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
            await revealByDigits(digits, fromSet: set)
        }
    }

    private func handleWordOCRPostPrediction(_ cleaned: String) {
        let dataManager = DataManager.shared
        let activeWordSet = ActiveSetSettings.shared.activeWordSetId.flatMap { activeId in
            dataManager.sets.first { $0.id == activeId && $0.type == .word }
        }
        let fallbackWordSet = dataManager.sets.first {
            $0.type == .word
                && !$0.banks.isEmpty
                && $0.photos.contains { $0.mediaId != nil && $0.isArchived }
        }

        guard let set = activeWordSet ?? fallbackWordSet else {
            print("⚠️ [OCR-PP] No active word set for '\(cleaned)'")
            return
        }

        print("📷 [OCR-PP] Word '\(cleaned)' → revealByLetters")
        LogManager.shared.info("OCR Post Prediction (word): \(cleaned)", category: .general)
        showOCRPeek(label: cleaned)
        Task {
            guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
            await revealByLetters(cleaned, fromSet: set)
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

        // The fake lockscreen captures digits; whether they mean a CARD or a NUMBER is
        // decided by the single active interface kind (only one can be active at a time).
        let activeKinds = IntegrationsSettings.shared.interfaceKindsInUse()

        // ── Card Lockscreen ─────────────────────────────────────────────────────
        // Digits encode a card (0 + value + suit). Feed the localized card name into any
        // bio/note slot set to Card Lockscreen, and unarchive the active card set's slot.
        if activeKinds.contains(.cardLockscreen), let (value, suit) = decodeCardInput(digits) {
            let symbol = cardSymbol(value: value, suit: suit)
            preArmLocalBioPostPredictionDelayIfNeeded(kinds: [.cardLockscreen])
            onInterfaceCapture?(localizedCardName(value: value, suit: suit), [.cardLockscreen])
            guard PostPredictionTestMode.shared.isActive || !UploadManager.shared.isActive else {
                print("⚠️ [LOCKSCREEN] Card reveal blocked: upload is active; bio/note capture already routed")
                LogManager.shared.warning("Lockscreen card reveal blocked: upload in progress", category: .general)
                onUploadConflict?()
                return
            }
            guard consumeCardRevealSlot(source: "cardLockscreen") else { return }
            if let activeId = ActiveSetSettings.shared.activeCardSetId,
               let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }) {
                showOCRPeek(label: symbol)
                beginAwaitingCoverTypingBioBeforePostPredictionIfNeeded()
                Task {
                    guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                    await revealByCardSlot(symbol: symbol, fromSet: activeSet)
                }
            }
            return
        }

        // ── Number Lockscreen / Number Clock ────────────────────────────────────
        // Feed the captured number into any bio/note {textN} configured for Number
        // Lockscreen or Number Clock (both fullscreen digit interfaces funnel through
        // here). Runs independently of the set reveal, so bio/note injection works even
        // with no active set.
        preArmLocalBioPostPredictionDelayIfNeeded(kinds: [.numberLockscreen, .numberClock])
        onInterfaceCapture?(input, [.numberLockscreen, .numberClock])

        guard PostPredictionTestMode.shared.isActive || !UploadManager.shared.isActive else {
            print("⚠️ [LOCKSCREEN] Reveal blocked: upload is active; bio/note capture already routed")
            LogManager.shared.warning("Lockscreen reveal blocked: upload in progress", category: .general)
            onUploadConflict?()
            return
        }

        let slot = safeNumber(fromDigits: digits)
        if let slot,
           slot >= 1,
           let activeId = ActiveSetSettings.shared.activeCustomSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .custom }) {
            showOCRPeek(label: "#\(slot)")
            beginAwaitingCoverTypingBioBeforePostPredictionIfNeeded()
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCustomSlot(slot, fromSet: activeSet)
            }
            return
        } else if slot == nil {
            LogManager.shared.warning("Lockscreen/clock custom reveal skipped: digit buffer overflow", category: .profile)
        }

        if let activeId = ActiveSetSettings.shared.activeNumberSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) {
            showOCRPeek(number: input)
            beginAwaitingCoverTypingBioBeforePostPredictionIfNeeded()
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByDigits(digits, fromSet: activeSet)
            }
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
                                     overrideText: postsOCRNumberOverride ?? aiScreenFollowingOverride ?? effectiveFollowingOverride,
                                     overrideLabel: postsOCRLabelOverride ?? aiScreenFollowingLabelOverride)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
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
                .background(Color(UIColor.igPageBackground))
                .contentShape(Rectangle())
                .zIndex(2)
    }

    private var tabTapSafetySpacer: some View {
        // A tiny tap shield between the tab icons and the first grid row.
        // On very small devices a low tap on the Posts icon can land close to the
        // grid boundary; this absorbs that near-miss instead of opening post 0.
        Color(UIColor.igPageBackground)
            .frame(height: 6)
            .contentShape(Rectangle())
            .onTapGesture { }
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
                    transpositionGridEffect: transpositionGridEffect,
                    onMediaAppear: onMediaAppear,
                    onTapIndex: { index in
                        guard !isSecretGridInputActive
                                || isAmnesiaCarouselIndex(index)
                                || isInstapickCarouselIndex(index) else { return }
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
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        measuredSecretGridWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { width in
                        measuredSecretGridWidth = width
                    }
            }
        )
        .highPriorityGesture(
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
                    userId: profile.userId,
                    onCarouselIndexChange: { url, page in
                        let itemId = mediaItemsByURL[url]?.mediaId
                        let liveId = InstapickSettings.shared.carouselMediaId
                        if url.hasPrefix("instapick://")
                            || itemId == InstapickSettings.testMediaId
                            || (liveId != nil && (itemId == liveId || url.contains(liveId!))) {
                            InstapickSettings.shared.liveCarouselPage = page
                            // Re-park mid volume on every color/cover page so DOWN
                            // cannot be stuck at 0 after a previous system change.
                            InstapickSettings.shared.armSilentMidVolumeForCarousel()
                            print("🃏 [INSTAPICK] liveCarouselPage → \(page)")
                        }
                    }
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
        guard isSecretGridInputActive else { return }
        print("🔢 [GRID SWIPE] digitSet:\(activeDigitGridSet?.name ?? "nil") cardSet:\(activeCardClockSet?.name ?? "nil") captureCell:\(shouldCaptureDigitGridCellInput) followingMagic:\(followingMagic.isEnabled) forceReel:\(ForceReelSettings.shared.isEnabled)/\(ForceReelSettings.shared.hasReel) forceGrid:\(ForceNumberRevealSettings.shared.isEnabled)/\(ForceNumberRevealSettings.shared.gridSwipeEnabled)")

        if shouldCaptureDigitGridCellInput,
           isDigitGridInputActive || isForceReelGridInputActive || activeCardClockSet == nil {
            let gridWidth = measuredSecretGridWidth > 0 ? measuredSecretGridWidth : UIScreen.main.bounds.width
            let digit = SecretNumberManager.digit(
                x: value.startLocation.x,
                y: value.startLocation.y,
                gridWidth: gridWidth,
                cellAspectRatio: InstagramGridMetrics.profileCellAspectRatio,
                spacing: InstagramGridMetrics.spacing
            )
            print("🔢 [DIGIT GRID] Cell swipe start x:\(Int(value.startLocation.x)) y:\(Int(value.startLocation.y)) gridW:\(Int(gridWidth)) → \(digit)")
            secretManager.pendingDir = nil
            secretManager.cardSwipeBuffer.removeAll()
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
        let isForceReelOnlyCommit = isForceReelGridInputActive && activeDigitGridSet == nil
        guard isDigitGridInputActive || isCardClockGridInputActive || isForceReelOnlyCommit else { return }

        if isForceReelOnlyCommit, secretManager.hasDigits {
            let digits = secretManager.digitBuffer
            if captureGridSideEffects(digits: digits, source: "force-reel-grid") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                secretManager.reset()
                followingOverride = nil; followerOverride = nil
                return
            }
        }

        // ── Card Clock Input ──────────────────────────────────────────────────
        if let activeId = ActiveSetSettings.shared.activeCardSetId,
           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .card }),
           activeSet.resolvedInputMethod == .cardClock,
           !isDigitGridInputActive,
           !isForceReelGridInputActive,
           let cardSym = secretManager.decodedCard {
            guard PostPredictionTestMode.shared.isActive || !UploadManager.shared.isActive else {
                LogManager.shared.warning("Card clock reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            guard consumeCardRevealSlot(source: "cardClockGrid") else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            // Feed the captured card into any bio/note {textN} configured for Card Clock.
            if let comp = cardComponents(fromSymbol: cardSym) {
                preArmLocalBioPostPredictionDelayIfNeeded(kinds: [.cardClock])
                onInterfaceCapture?(localizedCardName(value: comp.value, suit: comp.suit), [.cardClock])
            }
            showOCRPeek(label: cardSym)
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCardSlot(symbol: cardSym, fromSet: activeSet)
            }
            selectedTab = 0
            return
        }

        guard secretManager.hasDigits else { return }
        // Haptic confirmation — only fires when there are actual digits to reveal
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let activeSet = activeDigitGridSet, activeSet.type == .number {
            let digits     = secretManager.digitBuffer
            let digitLabel = digits.map(String.init).joined()
            captureGridSideEffects(digits: digits, source: "post-prediction")
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard PostPredictionTestMode.shared.isActive || !UploadManager.shared.isActive else {
                LogManager.shared.warning("Force reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            showOCRPeek(number: digitLabel)
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByDigits(digits, fromSet: activeSet)
            }

        } else if let activeSet = activeDigitGridSet, activeSet.type == .custom {
            let slot = safeNumber(fromDigits: secretManager.digitBuffer)
            captureGridSideEffects(digits: secretManager.digitBuffer, source: "post-prediction")
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
            guard PostPredictionTestMode.shared.isActive || !UploadManager.shared.isActive else {
                LogManager.shared.warning("Custom reveal blocked: upload in progress", category: .general)
                onUploadConflict?(); return
            }
            guard let slot, slot >= 1 else {
                LogManager.shared.warning("Custom grid reveal skipped: digit buffer overflow or invalid slot", category: .profile)
                return
            }
            showOCRPeek(label: "#\(slot)")
            Task {
                guard await waitForLocalBioPostPredictionComboIfNeeded() else { return }
                await revealByCustomSlot(slot, fromSet: activeSet)
            }

        } else {
            secretManager.reset()
            followingOverride = nil; followerOverride = nil
        }
    }

    private func updateFollowingOverride() {
        guard followingMagic.isEnabled else {
            followingOverride = nil
            followerOverride = nil
            return
        }
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
        guard followingMagic.isEnabled,
              followingMagic.transferEnabled,
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
        CrashLoggerService.shared.recordAction("Post Prediction reveal digits \(digits.map(String.init).joined()) set=\(set.name)")
        ppTestMode.restorePendingSessionIfNeeded(availableSets: DataManager.shared.sets)
        if ppTestMode.isTesting(set) {
            await revealTestDigits(digits, fromSet: set)
            return
        }
        guard !ppTestMode.isActive else {
            print("🧪 [TEST MODE] Number reveal blocked because no test template is available")
            await MainActor.run { clearOCRPeek() }
            return
        }
        print("🧪 [PP TEST] Not active for digits reveal — using real flow")

        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        // Signal operation start — blocks pull-to-refresh and overlapping reveals while running.
        guard await MainActor.run(body: { beginRevealOperation(kind: "Number") }) else { return }
        defer { Task { await MainActor.run { endRevealOperation(kind: "Number") } } }

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
        let requiredUnarchives = reversedDigits.enumerated().reduce(into: 0) { count, item in
            let (i, digit) = item
            guard i < sortedBanks.count else { return }
            let bank = sortedBanks[i]
            let symbol = String(digit)
            let photosInBank = set.photos.filter { $0.bankId == bank.id }
            if photosInBank.contains(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }) {
                count += 1
            }
        }
        guard await MainActor.run(body: { ensureRevealBudget(requiredActions: requiredUnarchives) }) else { return }

        print("🔢 [FORCE#] ═══════════════════════════════════════")
        print("🔢 [FORCE#] Revealing digits: \(digits.map { String($0) }.joined()) (reversed: \(reversedDigits.map { String($0) }.joined())) from set '\(set.name)'")
        LogManager.shared.info("Force number reveal: \(digits.map { String($0) }.joined()) from set '\(set.name)'", category: .general)

        // Paint matching local images immediately after the lockscreen closes.
        // Confirmation vibration/ring still happens later, after Instagram accepts
        // the unarchive calls.
        let instantPhotos: [(pseudoURL: String, image: UIImage?)] = reversedDigits.enumerated().compactMap { item in
            let (i, digit) = item
            guard i < sortedBanks.count else { return nil }
            let bank = sortedBanks[i]
            let symbol = String(digit)
            let photosInBank = set.photos.filter { $0.bankId == bank.id }
            guard let photo = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil }) else { return nil }
            guard let mediaId = photo.mediaId else { return nil }
            // Prefer the local file; fall back to the CDN thumbnail cached by mediaId
            // (covers reinstall / restore scenarios where the local file may be missing).
            let localImage = photo.imageData.flatMap { UIImage(data: $0) }
            let fallbackImage = localImage ?? ProfileCacheService.shared.loadImage(forMediaId: mediaId)
            return (pseudoURL: "reveal://\(mediaId)", image: fallbackImage)
        }
        if !instantPhotos.isEmpty {
            await MainActor.run { onAddLocalImages?(instantPhotos) }
            print("⚡️ [FORCE#] \(instantPhotos.count) local image(s) painted before Instagram confirmation")
        }

        var successCount  = 0
        var skipCount     = 0
        var failCount     = 0
        var revealedIds: [String] = []           // only IDs actually unarchived via API in this session
        var revealedPhotos: [(pseudoURL: String, image: UIImage?)] = [] // for instant grid update
        var failedPaintedIds: [String] = []

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

                    // Load local image so PerformanceView can insert it instantly (no GET needed).
                    // Fall back to CDN cache if local file is missing (e.g. after a restore).
                    let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
                        ?? ProfileCacheService.shared.loadImage(forMediaId: mediaId)
                    revealedPhotos.append((pseudoURL: "reveal://\(mediaId)", image: localImage))
                    print("🖼️ [FORCE#] Local image \(localImage != nil ? "loaded" : "not found") for \(mediaId)")
                } else {
                    print("⚠️ [FORCE#] Digit \(digit) bank \(i + 1): unarchive returned false")
                    failedPaintedIds.append(mediaId)
                    failCount += 1
                }
            } catch {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1) error: \(error)")
                LogManager.shared.error("Force reveal error digit \(digit) bank \(i + 1): \(error.localizedDescription)", category: .general)
                failedPaintedIds.append(mediaId)
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
        if !failedPaintedIds.isEmpty {
            await MainActor.run { onRemoveLocalImages?(failedPaintedIds) }
        }

        // Paint every matched prediction photo, including ones that were already
        // marked visible locally. Otherwise a stale local `isArchived=false` state
        // can skip the API call and also skip the fake-grid update.
        if !revealedPhotos.isEmpty {
            if successCount > 0 {
                InstagramSafetyGate.shared.markPostMutationQuietWindow(action: .unarchive)
            }
            if !revealedIds.isEmpty {
                InstagramSafetyGate.shared.markPostReveal(mediaIds: revealedIds)
            }
            onRevealComplete?(successCount > 0 ? [] : revealedPhotos)
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
        if PostPredictionTestMode.shared.isActive {
            await revealTestSlot(symbol: String(slot), label: set.type == .list ? "list" : "custom", fromSet: set)
            return
        }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared
        let symbol = String(slot)

        guard await MainActor.run(body: { beginRevealOperation(kind: set.type == .list ? "List" : "Custom") }) else { return }
        defer { Task { await MainActor.run { endRevealOperation(kind: set.type == .list ? "List" : "Custom") } } }

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
        guard await MainActor.run(body: { ensureRevealBudget(requiredActions: 1) }) else { return }

        let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
            ?? ProfileCacheService.shared.loadImage(forMediaId: mediaId)
        await MainActor.run {
            onAddLocalImages?([(pseudoURL: "reveal://\(mediaId)", image: localImage)])
        }
        print("⚡️ [CUSTOM] Slot \(slot) painted locally before Instagram confirmation")

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
                InstagramSafetyGate.shared.markPostMutationQuietWindow(action: .unarchive)
                InstagramSafetyGate.shared.markPostReveal(mediaIds: [mediaId])

                await MainActor.run {
                    onRevealComplete?([])
                }
            } else {
                print("⚠️ [CUSTOM] Slot \(slot): unarchive returned false")
                await MainActor.run { onRemoveLocalImages?([mediaId]) }
            }
        } catch {
            print("❌ [CUSTOM] Slot \(slot) error: \(error)")
            LogManager.shared.error("Custom reveal slot \(slot) error: \(error.localizedDescription)", category: .general)
            await MainActor.run { onRemoveLocalImages?([mediaId]) }
            let msg = error.localizedDescription.lowercased()
            if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                UploadManager.shared.sendSessionExpiredNotification()
            }
        }

        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - Playing Card Reveal

    /// Decode the lockscreen digit buffer into a card value (1–13) and suit (1–4).
    ///
    /// Normal flow matches Number Lockscreen:
    /// enter the hidden card code, tap outside to validate, then fill the remaining
    /// lockscreen dots with any digits. In that case this receives only the hidden
    /// 2- or 3-digit code.
    ///
    /// As a fallback for users who type a full 6-digit value without tapping outside,
    /// leading zeros are ignored (e.g. 000122 → Q♥).
    ///
    /// - 2 digits [v, s]      → value = v  (1=A … 9=9), suit = s
    /// - 3 digits [0, v, s]   → value = v  (leading-zero alias, e.g. 061 = 6♠)
    /// - 3 digits [t, u, s]   → value = t×10+u (10, 11=J, 12=Q, 13=K), suit = s
    ///
    /// Returns `nil` for invalid input (wrong digit count, out-of-range value/suit).
    private func decodeCardInput(_ digits: [Int]) -> (value: Int, suit: Int)? {
        let normalized = {
            let withoutLeadingZeros = Array(digits.drop { $0 == 0 })
            return withoutLeadingZeros.isEmpty ? digits : withoutLeadingZeros
        }()

        switch normalized.count {
        case 2:
            let value = normalized[0], suit = normalized[1]
            guard (1...9).contains(value), (1...4).contains(suit) else { return nil }
            return (value, suit)
        case 3:
            let value = normalized[0] == 0 ? normalized[1] : normalized[0] * 10 + normalized[1]
            let suit = normalized[2]
            let validValue = normalized[0] == 0 ? (1...9).contains(value) : (10...13).contains(value)
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
        if PostPredictionTestMode.shared.isActive {
            await revealTestSlot(symbol: symbol, label: "card", fromSet: set)
            return
        }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        guard await MainActor.run(body: { beginRevealOperation(kind: "Card") }) else { return }
        defer { Task { await MainActor.run { endRevealOperation(kind: "Card") } } }

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
        guard await MainActor.run(body: { ensureRevealBudget(requiredActions: 1) }) else { return }

        let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
            ?? ProfileCacheService.shared.loadImage(forMediaId: mediaId)
        await MainActor.run {
            onAddLocalImages?([(pseudoURL: "reveal://\(mediaId)", image: localImage)])
        }
        print("⚡️ [CARD] \(symbol) painted locally before Instagram confirmation")

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
                InstagramSafetyGate.shared.markPostMutationQuietWindow(action: .unarchive)
                InstagramSafetyGate.shared.markPostReveal(mediaIds: [mediaId])

                await MainActor.run {
                    onRevealComplete?([])
                }
            } else {
                print("⚠️ [CARD] \(symbol): unarchive returned false")
                await MainActor.run { onRemoveLocalImages?([mediaId]) }
            }
        } catch {
            print("❌ [CARD] \(symbol) error: \(error)")
            LogManager.shared.error("Card reveal \(symbol) error: \(error.localizedDescription)", category: .general)
            await MainActor.run { onRemoveLocalImages?([mediaId]) }
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
        ppTestMode.restorePendingSessionIfNeeded(availableSets: DataManager.shared.sets)
        if ppTestMode.isTesting(set) {
            await revealTestLetters(word, fromSet: set)
            return
        }
        guard !ppTestMode.isActive else {
            print("🧪 [TEST MODE] Letter reveal blocked because no test template is available")
            await MainActor.run { clearOCRPeek() }
            return
        }
        print("🧪 [PP TEST] Not active for word reveal — using real flow")

        let dm          = DataManager.shared
        let instagram   = InstagramService.shared
        let alphabet    = set.selectedAlphabet ?? .latin
        let normalizedWord = normalizeWordForReveal(word, alphabet: alphabet)
        let letters: [String] = alphabet.isRightToLeft
            ? normalizedWord.map { String($0) }
            : normalizedWord.reversed().map { String($0) }
        let sortedBanks = set.banks.sorted { $0.position < $1.position }

        guard await MainActor.run(body: { beginRevealOperation(kind: "Word") }) else { return }
        defer { Task { await MainActor.run { endRevealOperation(kind: "Word") } } }

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
                ?? ProfileCacheService.shared.loadImage(forMediaId: mediaId)
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
        let requiredUnarchives = jobs.filter(\.requiresUnarchive).count
        guard await MainActor.run(body: { ensureRevealBudget(requiredActions: requiredUnarchives) }) else { return }

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
        if !revealedIds.isEmpty {
            InstagramSafetyGate.shared.markPostMutationQuietWindow(action: .reveal)
        }
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

        onAmnesiaRevealStarted?()
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
                await MainActor.run {
                    amnesiaSettings.uploadState = .ready
                    onAmnesiaRevealFailed?()
                }
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
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing),
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing),
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing)
    ]

    var body: some View {
        let placeholderCount = max(0, minCells - reelURLs.count)
        LazyVGrid(columns: columns, spacing: InstagramGridMetrics.spacing) {
            ForEach(Array(reelURLs.enumerated()), id: \.element) { index, url in
                Color.clear
                    .aspectRatio(InstagramGridMetrics.profileCellAspectRatio, contentMode: .fit)
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
                        .aspectRatio(InstagramGridMetrics.profileCellAspectRatio, contentMode: .fit)
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
                    .truncationMode(.tail)
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
                    .lineLimit(1).truncationMode(.tail)
                    .onTapGesture { openProfile(userId: visible[0].userId, username: visible[0].username) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visible[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail)
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
                    .lineLimit(1).truncationMode(.tail)
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
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                Text(", ").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[1]) }
                Text("ig.and").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[2]) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if visibleFollowers.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(UIColor.secondaryLabel)).fixedSize()
                Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(UIColor.label))
                    .lineLimit(1).truncationMode(.tail).onTapGesture { onFollowerTap?(visibleFollowers[0]) }
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
            // contentShape inside the Button label so SwiftUI uses it for the
            // button's own hit-test area. Moving it outside breaks all taps because
            // the tap reaches the outer frame container but never fires the Button action.
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
    var transpositionGridEffect: TranspositionGridEffectPayload? = nil
    var onMediaAppear: ((String) -> Void)? = nil
    var onTapIndex: ((Int) -> Void)? = nil
    /// Always render at least this many cells so swipe digit-detection works
    /// even on tabs with few or no photos. 12 = 4 rows (row 4 maps to digit 0).
    var minCells: Int = 12

    let columns = [
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing),
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing),
        GridItem(.flexible(), spacing: InstagramGridMetrics.spacing)
    ]

    /// Resolves the stable mediaId for a grid entry. CDN URLs rotate per session,
    /// so the URL string is NOT a stable identity. reveal:// pseudo-URLs already
    /// embed the mediaId; real CDN URLs are mapped via `mediaItemsByURL`.
    private func mediaId(for url: String) -> String? {
        // Normalize by stripping the "_userId" suffix so a reveal:// pseudo-URL (which
        // may carry the short mediaId) and the confirmed CDN item (long "id_userId"
        // form) resolve to the same stable identity.
        func normalize(_ raw: String) -> String? {
            let key = raw.split(separator: "_").first.map(String.init) ?? raw
            return key.isEmpty ? nil : key
        }
        if url.hasPrefix("reveal://") {
            return normalize(String(url.dropFirst("reveal://".count)))
        }
        guard let id = mediaItemsByURL[url]?.mediaId, !id.isEmpty else { return nil }
        return normalize(id)
    }

    /// In-memory image index keyed by stable mediaId. Built from `cachedImages`
    /// (which is keyed by URL) so a cell can still find its thumbnail after the
    /// CDN rotates its URL — this is what prevents gray flashes / blank first page
    /// after a reveal or silent refresh.
    private var imagesByMediaId: [String: UIImage] {
        var map: [String: UIImage] = [:]
        for (url, image) in cachedImages {
            guard let id = mediaId(for: url) else { continue }
            map[id] = image
        }
        return map
    }

    var body: some View {
        let placeholderCount = max(0, minCells - mediaURLs.count)
        let mediaIdImages = imagesByMediaId
        // Build a render list with a STABLE identity per cell. Using the mediaId
        // (when known) instead of the raw URL means a reveal:// placeholder and the
        // confirmed CDN URL for the same post are treated as the SAME cell — no fade
        // transition, no flash, no re-layout when URLs rotate. Identities are
        // deduplicated to avoid SwiftUI duplicate-id crashes during reconciliation.
        let renderCells: [(index: Int, url: String, id: String)] = {
            var seen = Set<String>()
            var out: [(index: Int, url: String, id: String)] = []
            for (index, url) in mediaURLs.enumerated() {
                let identity = mediaId(for: url).map { "m:\($0)" } ?? "u:\(url)"
                guard seen.insert(identity).inserted else { continue }
                out.append((index: index, url: url, id: identity))
            }
            return out
        }()
        LazyVGrid(columns: columns, spacing: InstagramGridMetrics.spacing) {
            ForEach(renderCells, id: \.id) { cell in
                Color.clear
                    .aspectRatio(InstagramGridMetrics.profileCellAspectRatio, contentMode: .fit)
                    .overlay(
                        ZStack {
                            gridCell(for: cell.url, mediaIdImages: mediaIdImages)
                            if let effect = transpositionGridEffect, cell.index < 12 {
                                TranspositionGridCellEffectView(
                                    index: cell.index,
                                    sourceImages: effect.sourceImages,
                                    targetImages: effect.targetImages,
                                    duration: effect.duration
                                )
                            }
                        }
                    )
                    .clipped()
                    .onAppear { onMediaAppear?(cell.url) }
                    .onTapGesture { onTapIndex?(cell.index) }
            }
            // Placeholder cells
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(InstagramGridMetrics.profileCellAspectRatio, contentMode: .fit)
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
    private func gridCell(for url: String, mediaIdImages: [String: UIImage]) -> some View {
        let item = mediaItemsByURL[url]
        let isHorizontalVideo: Bool = {
            guard let item, item.mediaType == .video else { return false }
            return (item.videoAspectRatio ?? 0) > 1.0
        }()

        // Resolve the image by URL first, then fall back to the stable mediaId index.
        // The fallback keeps the thumbnail painted across CDN URL rotations so cells
        // never flash gray while a silent refresh swaps in fresh URLs.
        let resolvedImage: UIImage? = cachedImages[url] ?? mediaId(for: url).flatMap { mediaIdImages[$0] }

        if let image = resolvedImage {
            if isHorizontalVideo {
                // Letterbox: black background + image scaled to fit (no crop).
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }
}

struct TranspositionGridCellEffectView: View {
    let index: Int
    let sourceImages: [UIImage]
    let targetImages: [UIImage]
    let duration: TimeInterval

    @State private var startedAt = Date()
    @State private var tick = 0
    @State private var progress: CGFloat = 0
    private let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(isSettled ? 1.0 : 1.2 + Double(1 - progress) * 1.1)
                    .contrast(isSettled ? 1.0 : 1.08 + Double(1 - progress) * 0.35)
                    .offset(x: jitterX, y: jitterY)
                    .scaleEffect(isSettled ? 1.0 : 1.04 + CGFloat((tick + index) % 3) * 0.012)
            }

            Rectangle()
                .fill(scanColor)
                .blendMode(.screen)
                .opacity(isSettled ? 0 : Double((1 - progress) * 0.34))

            VStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { line in
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: line % 2 == 0 ? 1.0 : 0.55)
                        .offset(x: CGFloat(((tick + line * 7 + index) % 18) - 9) * 3)
                }
            }
            .opacity(isSettled ? 0 : Double((1 - progress) * 0.65))

            if progress > settleStartProgress, let finalImage = targetImage {
                Image(uiImage: finalImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(Double(min(1, (progress - settleStartProgress) / 0.12)))
            }
        }
        .clipped()
        .onReceive(timer) { _ in
            let elapsed = Date().timeIntervalSince(startedAt)
            progress = min(1, CGFloat(elapsed / max(duration, 0.1)))
            tick += 1
        }
        .onAppear {
            startedAt = Date()
            tick = index * 3
            progress = 0
        }
    }

    private var targetImage: UIImage? {
        guard !targetImages.isEmpty else { return nil }
        return targetImages[index % targetImages.count]
    }

    private var currentImage: UIImage? {
        guard !sourceImages.isEmpty || !targetImages.isEmpty else { return nil }
        if isSettled { return targetImage }

        let localProgress = min(1, progress / max(settleStartProgress, 0.01))
        let targetBias = Int(pow(Double(localProgress), 1.35) * 10)
        let shouldUseTarget = ((tick + index * 5) % 10) < targetBias
        let pool = shouldUseTarget || sourceImages.isEmpty ? targetImages : sourceImages
        guard !pool.isEmpty else { return targetImage }
        let scrambled = abs((tick * 7) + (index * 11) + ((tick + index) % 5) * 13)
        return pool[scrambled % pool.count]
    }

    private var settleStartProgress: CGFloat {
        // Cell-by-cell resolution: 12 visible cells complete across the effect.
        let visibleIndex = CGFloat(min(index, 11))
        return 0.24 + visibleIndex * 0.055
    }

    private var isSettled: Bool {
        progress >= settleStartProgress + 0.12
    }

    private var jitterX: CGFloat {
        guard !isSettled, progress < 0.82 else { return 0 }
        return CGFloat(((tick + index * 3) % 7) - 3) * (1 - progress) * 1.8
    }

    private var jitterY: CGFloat {
        guard !isSettled, progress < 0.82 else { return 0 }
        return CGFloat(((tick * 2 + index) % 5) - 2) * (1 - progress) * 1.2
    }

    private var scanColor: Color {
        switch (tick + index) % 4 {
        case 0: return .cyan
        case 1: return .purple
        case 2: return .white
        default: return .blue
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

// MARK: - Post feed audio focus (visibility)

/// Reports how visible each post's media frame is (0…1) so only one video plays sound.
private struct PostMediaVisibilityKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { max($0, $1) })
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
    var onCarouselIndexChange: ((String, Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var instapickSettings = InstapickSettings.shared
    @State private var resolvedItems: [String: InstagramMediaItem] = [:]
    /// Display order of posts. While the Force Post trick is armed the forced post
    /// is REMOVED from this list (it can never be seen by scrolling). When the
    /// spectator's swipe ends, `insertForced` puts it just below the fold and the
    /// interceptor animates the scroll to show it. nil = original order.
    @State private var displayURLs: [String]? = nil
    /// Triggered after the interceptor inserts the forced post; SwiftUI animates to it.
    @State private var forceScrollTrigger = false
    /// Only the most-visible post may play audio (Instagram-like + keeps volume buttons reliable).
    @State private var mediaVisibility: [String: CGFloat] = [:]
    @State private var audioFocusURL: String? = nil

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

    private func isInstapickMedia(url: String, item: InstagramMediaItem?) -> Bool {
        if url.hasPrefix("instapick://") { return true }
        if item?.mediaId == InstapickSettings.testMediaId { return true }
        if let liveId = InstapickSettings.shared.carouselMediaId {
            return item?.mediaId == liveId || url.contains(liveId)
        }
        return false
    }

    var body: some View {
        ZStack {
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
                                    item: resolvedItems[url] ?? mediaItemsByURL[url],
                                    cachedImages: cachedImages,
                                    username: username,
                                    profileImage: profileImage,
                                    isForced: isForcedPostURL(url),
                                    allowSound: audioFocusURL == url,
                                    onCarouselIndexChange: { index in
                                        onCarouselIndexChange?(url, index)
                                    }
                                )
                                Divider().background(Color(UIColor.separator))
                            }
                        }
                        .onPreferenceChange(PostMediaVisibilityKey.self) { values in
                            mediaVisibility = values
                            let next = values
                                .filter { $0.value >= 0.55 }
                                .max(by: { $0.value < $1.value })?
                                .key
                            if next != audioFocusURL {
                                audioFocusURL = next
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

                    // Instapick: silent mid-volume so volume DOWN always works (no HUD).
                    if let startURL,
                       isInstapickMedia(url: startURL, item: mediaItemsByURL[startURL]) {
                        // Kill any neighbouring reel audio before arming volume.
                        VideoPlaybackCoordinator.shared.muteActive()
                        InstapickSettings.shared.armSilentMidVolumeForCarousel()
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

            // Floating card only — Instagram chrome underneath stays intact.
            // No opacity transition: a fade-in reads as a flash over the lift.
            if let slot = instapickSettings.activeOverlaySlot,
               let card = instapickSettings.cardOverlay() {
                InstapickOverlayView(card: card) {
                    instapickSettings.completeOverlayDrag()
                }
                .id("instapick-card-\(slot)")
                .transition(.identity)
                .zIndex(50)
            }
        }
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
    /// When false, inline videos stay muted (default until this card is the feed focus).
    var allowSound: Bool = false
    var onCarouselIndexChange: ((Int) -> Void)? = nil
    @ObservedObject private var instapickSettings = InstapickSettings.shared
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

    private var isInstapickPost: Bool {
        if url.hasPrefix("instapick://") { return true }
        if item?.mediaId == InstapickSettings.testMediaId { return true }
        if let liveId = instapickSettings.carouselMediaId {
            return item?.mediaId == liveId || url.contains(liveId)
        }
        return false
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
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: PostMediaVisibilityKey.self,
                            value: [url: Self.visibleFraction(of: geo)]
                        )
                    }
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
        .onChange(of: carouselIndex) { index in
            onCarouselIndexChange?(index)
        }
        .onAppear {
            onCarouselIndexChange?(carouselIndex)
            if isInstapickPost {
                VideoPlaybackCoordinator.shared.muteActive()
                InstapickSettings.shared.armSilentMidVolumeForCarousel()
            }
        }
    }

    /// How much of this media frame sits inside the screen (0…1).
    private static func visibleFraction(of geo: GeometryProxy) -> CGFloat {
        let frame = geo.frame(in: .global)
        let screen = UIScreen.main.bounds
        let overlap = frame.intersection(screen)
        guard frame.height > 1, overlap.height > 0 else { return 0 }
        return min(1, overlap.height / frame.height)
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
                            postImage(for: imageURL, pageIndex: index)
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
            // Large post viewer should behave like an Instagram media surface:
            // sound enabled and aspectFill so videos fill the cell without side bars.
            let ratio: CGFloat = item.videoAspectRatio ?? (4.0 / 5.0)
            Color.black
                .aspectRatio(ratio, contentMode: .fit)
                .overlay(
                    GridVideoPlayer(
                        videoURL: videoURL,
                        // Only the focused (mostly on-screen) post may play audio.
                        muted: !allowSound || instapickSettings.activeOverlaySlot != nil,
                        fillMode: true,
                        posterImage: cachedImages[url]
                    )
                    .id(videoURL)
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

    /// Nb underlay while the floating card is armed (same frame as the overlay —
    /// never remount the base Image or SwiftUI flashes a blank cell).
    private func liftUnderlayImage(pageIndex: Int) -> UIImage? {
        guard isInstapickPost,
              let slot = instapickSettings.activeOverlaySlot,
              pageIndex == slot else { return nil }
        return instapickSettings.imageB(slot)
    }

    @ViewBuilder
    private func postImage(for imageURL: String, pageIndex: Int = 0) -> some View {
        // Instagram feed crops to the 4:5 cell (top/bottom). Fit would letterbox
        // tall Instapick screenshots and shrink the printed card.
        let base = cachedImages[imageURL] ?? (imageURL == url ? cachedImages[url] : nil)
        let underlay = liftUnderlayImage(pageIndex: pageIndex)
        if let base {
            ZStack {
                Image(uiImage: base)
                    .resizable()
                    .scaledToFill()
                if let underlay {
                    Image(uiImage: underlay)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .transaction { $0.animation = nil }
            .id(imageURL)
        } else if let remoteURL = URL(string: imageURL),
                  remoteURL.scheme == "http" || remoteURL.scheme == "https" {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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

