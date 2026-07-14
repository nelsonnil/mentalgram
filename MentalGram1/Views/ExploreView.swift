import SwiftUI
import AudioToolbox

// MARK: - Explore View (Instagram Explore Replica)

struct ExploreView: View {
    @ObservedObject var exploreManager = ExploreManager.shared
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var secretInputSettings = SecretInputSettings.shared
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @ObservedObject private var uploadManager = UploadManager.shared
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    @State private var ownProfileImage: UIImage? = nil
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var showingUserProfile = false
    @State private var searchedProfile: InstagramProfile?
    @State private var loadingProfileUserId: String?
    @State private var lastProfileOpenAt: Date = .distantPast
    @State private var failedProfileIds: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?

    // Post detail (fullscreen Instagram-style post viewer)
    @State private var showingPostDetail = false
    @State private var selectedDetailIndex = 0
    
    // Secret Input Masking
    @State private var secretInputBuffer: String = ""  // Real typed letters (what the magician types)
    @State private var maskTextCache: String = ""  // Cached mask text from settings
    @State private var isUpdatingMask: Bool = false  // Flag to ignore programmatic searchText changes
    
    // Reveal task (runs silently in background)
    @State private var revealTask: Task<Void, Never>?
    // Debounce duplicate space triggers (keyboard can fire onChange multiple times)
    @State private var lastSpaceTriggerTime: Date = .distantPast
    @State private var lastCommittedSecretWord: String = ""
    /// Set to true right before secretInputBuffer is cleared after a space-reveal,
    /// so the safety-reset guard in handleSearchTextChange doesn't wipe the visible
    /// masked text that the magician still needs to tap into a profile.
    @State private var revealJustTriggered: Bool = false
    // Debounce task for plain-text search (fires 600ms after last keypress)
    @State private var searchDebounceTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Main Explore view
            ZStack(alignment: .bottom) {
                // White background covering everything
                Color(UIColor.igPageBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                // Search bar at top
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField("ig.searching", text: $searchText)
                            .font(.system(size: 16))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isSearchFieldFocused)
                            .onChange(of: searchText) { newValue in
                                guard !isUpdatingMask else { return }
                                handleSearchTextChange(newValue: newValue)
                            }
                            .onAppear {
                                updateMaskTextCache()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchDebounceTask?.cancel()
                                isUpdatingMask = true
                                searchText = ""
                                secretInputBuffer = ""
                                isUpdatingMask = false
                                searchResults = []
                                isSearchFieldFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.igButtonFill))
                    .cornerRadius(10)
                    
                    if isSearchFieldFocused || !searchText.isEmpty {
                        Button(String(localized: "action.cancel")) {
                            searchDebounceTask?.cancel()
                            isUpdatingMask = true
                            searchText = ""
                            secretInputBuffer = ""
                            isUpdatingMask = false
                            searchResults = []
                            isSearchFieldFocused = false
                        }
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    } else {
                        Button(action: {}) {
                            IGIcon(asset: "instagram_more_horizontal", fallback: "ellipsis", size: 20)
                        }
                    }
                }
                .responsiveHorizontalPadding()
                .padding(.vertical, 8)
                .background(Color(UIColor.igPageBackground))
                
                // Show search results if searching
                if !searchText.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSearching {
                                HStack {
                                    ProgressView()
                                    Text("ig.searching")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            } else if searchResults.isEmpty {
                                VStack(spacing: 12) {
                                    if uploadManager.isUploading && !uploadManager.isPausedByPerformance {
                                        Image(systemName: "arrow.up.circle")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary)
                                        Text("explore.search_blocked_upload")
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 32)
                                    } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                        Text("explore.no_results")
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(searchResults) { result in
                                    SearchResultRow(result: result, isLoading: loadingProfileUserId == result.userId, onTap: {
                                        loadUserProfile(result: result)
                                    })
                                }
                            }
                        }
                    }
                    .background(Color(UIColor.igPageBackground))
                } else {
                    // Grid of explore content
                    if exploreManager.isLoading {
                        // Show skeleton UI (like Instagram real)
                        ExploreGridSkeleton()
                            .padding(.bottom, 65)
                } else if exploreManager.exploreMedia.isEmpty {
                        // Failed to load — show retry option
                        if exploreManager.loadError != nil {
                    VStack(spacing: 20) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.system(size: 44))
                            .foregroundColor(.secondary)
                                Text("explore.load_error")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.secondary)
                                Button(action: { exploreManager.loadExplore() }) {
                                    Text("action.retry")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 28)
                                        .padding(.vertical, 10)
                                        .background(Color.black)
                                        .cornerRadius(8)
                                }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, 65)
                        } else {
                            ExploreGridSkeleton()
                                .padding(.bottom, 65)
                        }
                } else {
                        ScrollView {
                            ExploreGridView(
                                mediaItems: exploreManager.exploreMediaWithForce(),
                                cachedImages: exploreManager.cachedImages,
                                exploreManager: exploreManager,
                                onTapMedia: { index in
                                    selectedDetailIndex = index
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        showingPostDetail = true
                                    }
                                }
                            )
                            .padding(.bottom, 65)
                        }
                        .refreshable {
                            guard !InstagramService.shared.isLocked else { return }
                            await exploreManager.refreshAsync()
                        }
                    }
                }
            }
            
            // Instagram bottom bar
            InstagramBottomBar(
                profileImageURL: profileCache.cachedProfile?.profilePicURL,
                cachedImage: ownProfileImage,
                isHome: false,
                isSearch: true,
                onHomePress: {
                    showingExplore = false
                    selectedTab = 0 // Performance (perfil del usuario)
                },
                onSearchPress: {
                    // Already on search
                },
                onReelsPress: {
                    // Reels (disabled)
                },
                onMessagesPress: {
                    // Messages (disabled)
                },
                onProfilePress: {
                    showingExplore = false
                    selectedTab = 0 // Performance
                }
            )
            }
            .toolbar(.hidden, for: .tabBar)
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarHidden(true)
            
            // Post Detail overlay (fullscreen Instagram-style viewer)
            if showingPostDetail {
                PostDetailView(
                    mediaItems: exploreManager.exploreMediaWithForce(),
                    startIndex: selectedDetailIndex,
                    cachedImages: exploreManager.cachedImages,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showingPostDetail = false
                        }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(999)
            }
            
            // User Profile overlay (full screen on top)
            if showingUserProfile, let profile = searchedProfile {
                UserProfileView(profile: profile, onClose: {
                    withAnimation {
                        showingUserProfile = false
                        searchedProfile = nil
                        loadingProfileUserId = nil
                    }
                })
                // Force SwiftUI to discard @State and re-init when the profile changes.
                .id(profile.userId)
                .transition(.move(edge: .trailing))
                .zIndex(1000)
            }
            
            // Reveal runs silently in background — no visual indicator (spectator must not see anything)
            // Magician gets haptic feedback: medium pulse on space, success/error on completion
        }
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        // ── Progressive: visited profile header arrived ───────────────────────
        // `InstagramService.getProfileInfo` posts this as soon as the searched
        // user's header (avatar, username, counters) is ready, before the
        // posts + followers chain finishes. Present `UserProfileView`
        // immediately with the partial snapshot so the user does not stare at
        // the search-result spinner for 4-5 extra seconds. The Task keeps
        // running in the background and `UserProfileView` listens for the
        // subsequent `.visitedProfileMediaReady` / `.visitedProfileFollowedByReady`
        // notifications to fill the grid and the "Followed by" row.
        .onReceive(NotificationCenter.default.publisher(for: .visitedProfileHeaderReady)) { note in
            guard let snapshot = note.userInfo?["snapshot"] as? InstagramProfile,
                  let userId = note.userInfo?["userId"] as? String else { return }
            // Only adopt the snapshot if it matches the profile we are
            // currently loading — otherwise a stale notification from a
            // previous tap could re-open Explore on the wrong profile.
            guard loadingProfileUserId == userId else {
                print("⚡ [EXPLORE] Ignoring visited header for uid \(userId) (loading \(loadingProfileUserId ?? "nil"))")
                return
            }
            if showingUserProfile, searchedProfile?.userId == userId {
                // Already presented (e.g. via cache hit) — just refresh the
                // header. UserProfileView's onChange will reconcile.
                searchedProfile = snapshot
            } else {
                searchedProfile = snapshot
                withAnimation { showingUserProfile = true }
                loadingProfileUserId = nil
                print("⚡ [EXPLORE] Visited profile presented early — @\(snapshot.username) (background fetch still running)")
                LogManager.shared.info("Visited profile UI presented with progressive header — uid:\(userId) @\(snapshot.username)", category: .general)
            }
            // EXPLORE SPY: fire-and-forget — spectator never sees any indicator
            if IntegrationsSettings.shared.exploreSpyEnabled {
                let uname    = snapshot.username
                let fname    = snapshot.fullName
                let followers = snapshot.followerCount
                let following = snapshot.followingCount
                Task {
                    await IntegrationsSettings.shared.sendExploreProfile(
                        username: uname,
                        fullName: fname,
                        followers: followers,
                        following: following
                    )
                }
            }
        }
        .onChange(of: showingExplore) { isOpen in
            if isOpen {
                updateMaskTextCache()
            }
        }
        .onAppear {
            updateMaskTextCache()

            // If cache has old count (not multiple of 3), clear and force full reload
            let currentCount = exploreManager.exploreMedia.count
            if currentCount > 0 && currentCount % 3 != 0 {
                print("🗑️ [EXPLORE] Cache has \(currentCount) items (not multiple of 3), clearing...")
                exploreManager.clearCache()
            }

            if exploreManager.exploreMedia.isEmpty {
                // No cache — show skeleton and load from API
                exploreManager.loadExplore()
            }
            // Cache present → show as-is, no background refresh.
            // User can pull-to-refresh manually if needed.

            // Load own profile pic for the bottom bar
            if ownProfileImage == nil, let picURL = profileCache.cachedProfile?.profilePicURL,
               !picURL.isEmpty {
                if let cached = profileCache.loadImage(forURL: picURL) {
                    ownProfileImage = cached
                    return
                }
                Task {
                    guard let url = URL(string: picURL) else { return }
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: data) {
                        ProfileCacheService.shared.saveImage(img, forURL: picURL)
                        await MainActor.run { ownProfileImage = img }
                    }
                }
            }
        }
    }
    
    // MARK: - Mask cache search

    /// Filtra los resultados del caché permanente de máscara por la query visible.
    /// Orden: username exacto → username con prefijo → fullName contiene → resto.
    private func filterMaskResults(_ results: [UserSearchResult], query: String) -> [UserSearchResult] {
        let q = query.lowercased()
        let filtered = results.filter {
            $0.username.lowercased().hasPrefix(q)
                || $0.username.lowercased().contains(q)
                || $0.fullName.lowercased().contains(q)
        }
        return filtered.sorted {
            let aExact = $0.username.lowercased() == q
            let bExact = $1.username.lowercased() == q
            if aExact != bExact { return aExact }
            let aPrefix = $0.username.lowercased().hasPrefix(q)
            let bPrefix = $1.username.lowercased().hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            return $0.username.count < $1.username.count
        }
    }

    /// Si existe caché de máscara para el username activo, filtra en local (sin API).
    /// Si no hay caché, cae al performSearch normal.
    private func searchWithMaskCache(query: String) {
        guard activeMaskMode == .customUsername else {
            performSearch(query: query)
            return
        }
        let username = activeMaskCustomUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !username.isEmpty,
              let cached = VisitedProfileCacheService.shared.loadMaskSearchResults(forUsername: username),
              !cached.isEmpty else {
            performSearch(query: query)
            return
        }
        let filtered = filterMaskResults(cached, query: query)
        searchResults = filtered
        isSearching = false
        print("🎯 [MASK CACHE] \(filtered.count)/\(cached.count) resultados para '\(query)' (sin API)")
    }

    // MARK: - Live search

    private func performSearch(query: String) {
        // Cancel previous search task immediately — the new one replaces it
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        // ANTI-BOT: Minimum 3 characters before firing any request (mirrors Instagram)
        guard query.count >= 3 else {
            searchResults = []
            isSearching = false
            return
        }

        if let cachedResults = VisitedProfileCacheService.shared.loadSearchResults(for: query) {
            searchResults = cachedResults
            isSearching = false
            return
        }

        // No additional debounce here — the 400 ms debounce in handleSearchTextChange
        // already ensures only one request fires per typing burst.
        // We keep a cancellable Task so a new query mid-flight cancels the previous one.
        searchTask?.cancel()
        searchTask = Task {
            guard !Task.isCancelled else { return }

            guard !InstagramService.shared.isLocked else {
                print("🚫 [EXPLORE] Search skipped — lockdown active")
                await MainActor.run { isSearching = false }
                return
            }

            guard !UploadManager.shared.isUploading || UploadManager.shared.isPausedByPerformance else {
                print("🛡️ [EXPLORE] Search skipped — upload actively running (not paused by Performance)")
                LogManager.shared.warning("SAFETY BLOCK — Explore search skipped: upload actively running", category: .general)
                await MainActor.run { isSearching = false }
                return
            }

            let safetyDecision = InstagramSafetyGate.shared.decision(for: .searchUsers)
            guard safetyDecision.allowed else {
                print("🛡️ [EXPLORE] Search skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
                LogManager.shared.warning("SAFETY BLOCK — search users: \(safetyDecision.reason)", category: .general)
                await MainActor.run { isSearching = false }
                return
            }
            // Record AFTER the response arrives, not before. This way a task that
            // gets cancelled mid-flight (user still typing) does NOT consume the
            // safety-gate slot, preventing the "20s lockout after typing" bug.
            
            do {
                let results = try await InstagramService.shared.searchUsers(query: query)
                // Only stamp the timestamp when the request actually completed —
                // cancelled tasks skip this line and the gate remains open.
                InstagramSafetyGate.shared.record(.searchUsers)
                VisitedProfileCacheService.shared.saveSearchResults(results, for: query)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = results
                    isSearching = false
                }
            } catch {
                // Search errors are silent — never show a popup (mirrors Instagram UX)
                guard !Task.isCancelled else { return }
                // Non-cancellation errors do count against the gate so we don't
                // spam the API on repeated failures.
                InstagramSafetyGate.shared.record(.searchUsers)
                print("🔍 [SEARCH] Error (silent): \(error)")
                await MainActor.run { isSearching = false }
            }
        }
    }
    
    private func loadUserProfile(result: UserSearchResult) {
        dismissSearchKeyboard()

        let userId = result.userId
        guard loadingProfileUserId == nil else { return }

        // Skip profiles that already failed with a non-retryable error this session.
        guard !failedProfileIds.contains(userId) else {
            print("⏭️ [SEARCH] Skipping \(result.username) — failed previously this session")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Budget guard: block profile opens when fewer than 8 actions remain.
        // Cached profiles are always allowed.
        let rateCheck = instagram.checkRateLimit()
        if rateCheck.remaining < 8,
           VisitedProfileCacheService.shared.loadProfile(userId: userId) == nil {
            print("⚠️ [SEARCH] Profile open blocked — only \(rateCheck.remaining) actions remaining this hour")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }

        // 3-second cooldown between consecutive profile opens from search results.
        // Each new profile costs 4-5 API calls; rapid consecutive opens exhaust the
        // hourly budget and trigger Instagram's challenge_required.
        // Cached profiles bypass this guard since they make no API calls.
        let sinceLastOpen = Date().timeIntervalSince(lastProfileOpenAt)
        if sinceLastOpen < 3.0,
           VisitedProfileCacheService.shared.loadProfile(userId: userId) == nil {
            print("⏳ [SEARCH] Profile open throttled — \(String(format: "%.1f", sinceLastOpen))s since last open (min 3s)")
            return
        }

        loadingProfileUserId = userId

        if let cachedProfile = VisitedProfileCacheService.shared.loadProfile(userId: userId) {
            searchedProfile = cachedProfile
            showingUserProfile = true
            loadingProfileUserId = nil
            print("📦 [PROFILE] Opened @\(cachedProfile.username) from visited cache")
            return
        }

        lastProfileOpenAt = Date()

        guard !InstagramService.shared.isLocked else {
            print("🚫 [SEARCH] Profile load skipped — lockdown active")
            loadingProfileUserId = nil
            return
        }

        guard !UploadManager.shared.isUploading || UploadManager.shared.isPausedByPerformance else {
            print("🛡️ [SEARCH] Profile load skipped — upload actively running (not paused by Performance)")
            LogManager.shared.warning("SAFETY BLOCK — visited profile load skipped: upload actively running", category: .general)
            loadingProfileUserId = nil
            return
        }
        
        print("🔍 [UI] Loading profile for user ID: \(userId)")
        
        Task {
            let safetyDecision = InstagramSafetyGate.shared.decision(for: .visitedProfileOpen)
            guard safetyDecision.allowed else {
                print("🛡️ [PROFILE] Open skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
                LogManager.shared.warning("SAFETY BLOCK — visited profile open: \(safetyDecision.reason)", category: .general)
                await MainActor.run { loadingProfileUserId = nil }
                return
            }
            InstagramSafetyGate.shared.record(.visitedProfileOpen)

            do {
                let profile = try await InstagramService.shared.getProfileInfo(
                    userId: userId,
                    usernameHint: result.username,
                    fullNameHint: result.fullName,
                    profilePicURLHint: result.profilePicURL,
                    isVerifiedHint: result.isVerified
                )
                
                await MainActor.run {
                    if let profile = profile {
                        print("✅ [UI] Profile loaded successfully: @\(profile.username)")
                        print("✅ [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
                        VisitedProfileCacheService.shared.saveProfile(profile)
                        searchedProfile = profile
                        showingUserProfile = true
                        loadingProfileUserId = nil
                        print("✅ [UI] showingUserProfile set to true")
                    } else {
                        print("❌ [UI] Profile is nil")
                        loadingProfileUserId = nil
                    }
                }
            } catch let error as InstagramError {
                print("❌ [PROFILE] Instagram error loading profile: \(error)")
                await MainActor.run {
                    loadingProfileUserId = nil
                    lastError = error
                    showingConnectionError = true
                    // Mark non-retryable errors so re-taps don't waste more API calls.
                    let desc = error.localizedDescription.lowercased()
                    let isHardFailure = desc.contains("400") || desc.contains("not found") || desc.contains("not authorized")
                    if isHardFailure { failedProfileIds.insert(userId) }
                }
            } catch {
                print("❌ [PROFILE] Error loading profile: \(error)")
                await MainActor.run {
                    loadingProfileUserId = nil
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }

    private func dismissSearchKeyboard() {
        searchDebounceTask?.cancel()
        isSearchFieldFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
    
    // MARK: - Secret Input Logic

    private var activeCoverTypingSet: PhotoSet? {
        guard ActiveSetSettings.shared.isPostPredictionEnabled,
              let activeId = ActiveSetSettings.shared.activeWordSetId,
              let set = dataManager.sets.first(where: { $0.id == activeId && $0.type == .word }),
              set.resolvedInputMethod == .coverTyping else {
            return nil
        }
        return set
    }

    private var isBioCoverTypingActive: Bool {
        UserDefaults.standard.bool(forKey: "bio_feature_enabled")
        && UserDefaults.standard.string(forKey: "bioTopInputMode") == "coverTyping"
    }

    private var hasCoverTypingDestination: Bool {
        hasPostPredictionCoverTypingDestination || isBioCoverTypingActive
    }

    private var hasPostPredictionCoverTypingDestination: Bool {
        if activeCoverTypingSet != nil { return true }
        guard secretInputSettings.isEnabled else { return false }
        return findActiveWordRevealSet() != nil
    }

    private var shouldUseSecretMask: Bool {
        secretInputSettings.isEnabled || hasCoverTypingDestination
    }

    /// Returns which mask settings to use based on which Cover Typing destination is active.
    /// PP Cover Typing takes priority; Bio CT uses its own independent mask settings.
    private var activeMaskMode: MaskInputMode {
        hasPostPredictionCoverTypingDestination ? secretInputSettings.mode : secretInputSettings.bioCoverTypingMode
    }

    private var activeMaskCustomUsername: String {
        hasPostPredictionCoverTypingDestination
            ? secretInputSettings.customUsername
            : secretInputSettings.bioCoverTypingCustomUsername
    }

    private func maskText(latestFollowerUsername: String?) -> String {
        guard shouldUseSecretMask else { return "" }
        switch activeMaskMode {
        case .latestFollower:
            return latestFollowerUsername?.lowercased() ?? "user"
        case .customUsername:
            let custom = activeMaskCustomUsername
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return custom.isEmpty ? "user" : custom
        }
    }
    
    private func updateMaskTextCache() {
        // Custom mode — no async needed.
        guard activeMaskMode == .latestFollower else {
            maskTextCache = maskText(latestFollowerUsername: nil)
            return
        }

        guard shouldUseSecretMask else {
            maskTextCache = ""
            return
        }

        // ANTI-BOT: Persisted cache of the last follower username (TTL: 30 min).
        // Use cached value immediately so the UI never blocks on a network fetch
        // and we eliminate ~95% of the /friendships/.../followers/?count=1 calls
        // that previously fired on every Explore entry — that endpoint is what
        // got us a 401 in the most recent bot-detection log.
        let cacheKey = "explore_lastFollowerUsername"
        let timestampKey = "explore_lastFollowerUsername_ts"
        let ttl: TimeInterval = 30 * 60
        let now = Date().timeIntervalSince1970

        let cachedUsername = UserDefaults.standard.string(forKey: cacheKey)
        let cachedAt = UserDefaults.standard.double(forKey: timestampKey)
        let cacheAge = now - cachedAt
        let cacheFresh = cachedUsername != nil && cacheAge < ttl

        // Show cached value (or generic fallback) instantly.
        maskTextCache = maskText(latestFollowerUsername: cachedUsername)

        // Skip network refresh if cache is fresh enough.
        guard !cacheFresh else { return }

        // Background refresh — bail out silently on any guard.
        Task {
            guard !instagram.isLocked, !instagram.isSessionChallenged, !instagram.isSessionExpired else { return }
            // Defer to getLatestFollower's internal guards (cold-start, burst,
            // heavy-op) so this respects all the safety layers.
            guard !instagram.isHeavyOperationActive else { return }
            do {
                let follower = try await instagram.getLatestFollower()
                guard let username = follower?.username else { return }
                UserDefaults.standard.set(username, forKey: cacheKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
                await MainActor.run {
                    let newMask = maskText(latestFollowerUsername: username)
                    // If the mask changes while the user is already typing, the diff
                    // algorithm would compare against the wrong mask and corrupt
                    // secretInputBuffer (real chars would be replaced by mask chars).
                    // Reset the search field so the user gets a clean slate with the
                    // correct mask — this prevents "copper" being revealed instead of
                    // the actual secret word.
                    if newMask != maskTextCache && !searchText.isEmpty {
                        isUpdatingMask = true
                        searchText = ""
                        isUpdatingMask = false
                        secretInputBuffer = ""
                    }
                    maskTextCache = newMask
                }
            } catch {
                // Fallback already in place from the synchronous step above.
            }
        }
    }
    
    /// Handle text change in search field with secret input masking.
    /// Uses secretInputBuffer.count as the "expected" length to detect typed vs deleted chars.
    ///
    /// Search strategy:
    ///   - Secret input ACTIVE (maskTextCache not empty):
    ///       No search on keystrokes. One search fires when SPACE is pressed (word is complete).
    ///   - Secret input INACTIVE (no mask configured):
    ///       Search only when ADDING characters and the visible text reaches 4+ chars.
    ///       Deleting characters never triggers a new search.
    private func handleSearchTextChange(newValue: String) {
        // NOTE: maskTextCache is loaded once on .onAppear — never refresh it here.
        // Doing so would fire a getLatestFollower() API call on every keypress.

        let secretInputActive = !maskTextCache.isEmpty

        // ── Cover typing DISABLED: behave as a plain search field ────────────
        // Do NOT accumulate secretInputBuffer or call handleSpacePressed().
        // Debounce: wait 600ms after the last keypress before hitting the API.
        if !secretInputActive {
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                searchTask?.cancel()
                searchResults = []
                isSearching = false
            } else if newValue.count >= 3 {
                // Show spinner immediately so the user knows the tap registered
                isSearching = true
                let query = newValue
                searchDebounceTask = Task {
                    // 500 ms debounce — waits for the user to pause typing before firing.
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    performSearch(query: query)
                }
            } else {
                searchResults = []
                isSearching = false
            }
            return
        }

        // ── Cover typing ACTIVE ───────────────────────────────────────────────
        // Safety: if secretInputBuffer is empty but multiple characters already exist
        // in the field, the mask activated AFTER the user had already typed some text
        // (e.g. background fetch just completed). Those characters weren't tracked so
        // secretInputBuffer doesn't know about them. Reset the field to start clean.
        // NOTE: newValue.count > 1 (not just non-empty) so we never kill the very first
        // keystroke, which legitimately arrives with an empty buffer.
        // EXCEPTION: skip reset right after a space-reveal — the field intentionally
        // keeps the masked text visible so the magician can tap into the profile.
        if secretInputBuffer.isEmpty && newValue.count > 1 {
            if revealJustTriggered {
                revealJustTriggered = false  // consume the flag, allow this onChange through
            } else {
                isUpdatingMask = true
                searchText = ""
                isUpdatingMask = false
                return
            }
        }

        // When the secret buffer exceeds the mask length the visible field is capped
        // at maskTextCache.count — use the VISIBLE length as the comparison base so
        // add/delete counts are calculated against what iOS actually shows, not the
        // larger internal buffer.
        let visibleLength = maskTextCache.isEmpty
            ? secretInputBuffer.count
            : min(secretInputBuffer.count, maskTextCache.count)
        let expectedLength = visibleLength

        if newValue.count > expectedLength {
            // Character(s) added.
            // Use a diff against the OLD mask (buildMaskedText BEFORE buffer update)
            // to find WHICH characters were inserted and WHERE.
            // This is cursor-position-safe: it works regardless of where iOS placed
            // the cursor (end, middle, beginning) — a critical fix for cases where
            // the user taps to reposition the cursor mid-mask, then types or spaces.
            let addedCount = newValue.count - expectedLength
            let newArr = Array(newValue)
            let oldArr = Array(buildMaskedText())   // current mask before any update

            // Find the first divergence point between old mask and new field value
            var insertPos = 0
            let scanLimit = min(oldArr.count, newArr.count)
            while insertPos < scanLimit && newArr[insertPos] == oldArr[insertPos] {
                insertPos += 1
            }

            // Extract the inserted substring at the divergence point
            let endPos = min(insertPos + addedCount, newArr.count)
            let insertedChars = endPos > insertPos
                ? String(newArr[insertPos..<endPos])
                : String(newValue.suffix(addedCount))   // safe fallback

            var hasSpace = false
            for char in insertedChars {
                if char == " " {
                    hasSpace = true
                } else {
                    secretInputBuffer.append(char)
                }
            }

            // Update visible text to mask characters (strips the space)
            let masked = buildMaskedText()
            isUpdatingMask = true
            searchText = masked
            isUpdatingMask = false

            if hasSpace {
                // SPACE = word complete → reveal + fire final search with the mask text
                handleSpacePressed()
                // handleSpacePressed llama a searchWithMaskCache internamente
            } else if masked.count >= 3 {
                // Búsqueda progresiva: usa caché permanente si está disponible (sin API),
                // o cae a performSearch con debounce si no hay caché.
                searchDebounceTask?.cancel()
                let query = masked
                isSearching = true
                if activeMaskMode == .customUsername {
                    // Caché → resultado instantáneo, sin debounce ni API
                    searchDebounceTask = Task {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { searchWithMaskCache(query: query) }
                    }
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        performSearch(query: query)
                    }
                }
            }

        } else if newValue.count < expectedLength {
            // User deleted character(s)
            let deletedCount = expectedLength - newValue.count
            secretInputBuffer = String(secretInputBuffer.dropLast(deletedCount))

            // Update visible text
            let masked = buildMaskedText()
            isUpdatingMask = true
            searchText = masked
            isUpdatingMask = false

            // Cancel any pending search when deleting
            searchDebounceTask?.cancel()
            searchTask?.cancel()
            if searchText.isEmpty {
                searchResults = []
                isSearching = false
            } else if masked.count >= 3 {
                // Re-búsqueda al borrar: filtra caché si está disponible, si no usa API
                let query = masked
                isSearching = true
                if activeMaskMode == .customUsername {
                    searchDebounceTask = Task {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { searchWithMaskCache(query: query) }
                    }
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        performSearch(query: query)
                    }
                }
            } else {
                searchResults = []
                isSearching = false
            }
        }
        // newValue.count == expectedLength → our own programmatic mask update, ignore
    }
    
    /// Build the masked text that the spectator sees.
    /// Capped at maskTextCache.count so the visible field never grows beyond the
    /// mask word — typing "camaleon" with mask "nelson" shows "nelson" the whole
    /// time once all 6 mask characters are filled in.
    private func buildMaskedText() -> String {
        guard !secretInputBuffer.isEmpty, !maskTextCache.isEmpty else {
            return secretInputBuffer
        }

        let visibleCount = min(secretInputBuffer.count, maskTextCache.count)
        var result = ""
        for i in 0..<visibleCount {
            let char = maskTextCache[maskTextCache.index(maskTextCache.startIndex, offsetBy: i)]
            result.append(char)
        }
        return result
    }
    
    /// Handle SPACE key → Transmit the secret word (trigger Bio and/or reveal in background)
    /// The search field keeps showing the mask text so the magician can tap into the profile
    private func handleSpacePressed() {
        // Debounce: keyboard/onChange can fire this twice in the same millisecond.
        // Require at least 1.5 s between consecutive space triggers.
        let now = Date()
        guard now.timeIntervalSince(lastSpaceTriggerTime) > 1.5 else {
            print("⚠️ [SECRET] Space debounced (called \(String(format: "%.2f", now.timeIntervalSince(lastSpaceTriggerTime)))s after previous)")
            return
        }
        lastSpaceTriggerTime = now

        let word = secretInputBuffer
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] SPACE PRESSED - transmitting secret word: '\(word)' (\(word.count) letters)")
        print("🎩 [SECRET] Search field keeps showing: '\(searchText)' (mask text stays)")
        LogManager.shared.info("Secret input SPACE triggered: '\(word)'", category: .general)

        // Búsqueda final con el texto de máscara visible — usa caché si está disponible
        if !searchText.isEmpty {
            searchWithMaskCache(query: searchText)
        }

        guard !word.isEmpty else {
            print("⚠️ [SECRET] Empty word, ignoring space")
            return
        }
        
        // NOTE: Do NOT clear searchText — the masked text stays visible so the
        // magician can tap to enter the follower's profile after the reveal.
        // DO reset secretInputBuffer so a second covert-typing attempt in the same
        // session doesn't accumulate leftover chars from the first word.
        // Flag prevents the safety-reset guard from wiping the visible masked text
        // when onChange fires with an empty buffer after this reset.
        revealJustTriggered = true
        secretInputBuffer = ""
        
        commitCoverTypingWord(word, trigger: "space")
    }

    private func commitCoverTypingWord(_ rawWord: String, trigger: String) {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        guard word != lastCommittedSecretWord else {
            print("⚠️ [SECRET] Duplicate cover typing commit ignored (\(trigger)): \(word)")
            return
        }
        lastCommittedSecretWord = word

        // Strong system vibration: immediate confirmation that the word was captured.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // Reset after Space commit so this confirmation can only fire once per typed word.
        revealJustTriggered = true
        secretInputBuffer = ""

        NotificationCenter.default.post(
            name: .coverTypingWordCommitted,
            object: nil,
            userInfo: [
                "word": word,
                "trigger": trigger,
                "bioActive": isBioCoverTypingActive,
                "postPredictionActive": hasPostPredictionCoverTypingDestination
            ]
        )

        print("🎩 [SECRET] Cover Typing committed via \(trigger): '\(word)' bio=\(isBioCoverTypingActive) pp=\(hasPostPredictionCoverTypingDestination)")
        LogManager.shared.info("Cover Typing committed via \(trigger): '\(word)'", category: .general)

        // Diagnostics: show all sets and their state
        print("🎩 [SECRET] Total sets in DataManager: \(dataManager.sets.count)")
        for (i, set) in dataManager.sets.enumerated() {
            let archivedWithMedia = set.photos.filter { $0.mediaId != nil && $0.isArchived }.count
            let withMedia = set.photos.filter { $0.mediaId != nil }.count
            let archived = set.photos.filter { $0.isArchived }.count
            print("🎩 [SECRET]   Set[\(i)]: '\(set.name)' type=\(set.type.rawValue) status=\(set.status.rawValue) banks=\(set.banks.count) photos=\(set.photos.count) withMediaId=\(withMedia) archived=\(archived) archivedWithMedia=\(archivedWithMedia)")
        }
    }
    
    /// Find the first completed Word Reveal set that has archived photos ready to reveal
    private func findActiveWordRevealSet() -> PhotoSet? {
        // Prefer explicitly selected active word set
        if let activeId = ActiveSetSettings.shared.activeWordSetId,
           let selected = dataManager.sets.first(where: { $0.id == activeId && $0.type == .word }) {
            if selected.banks.isEmpty || !selected.photos.contains(where: { $0.mediaId != nil && $0.isArchived }) {
                print("⚠️ [SECRET] Active word set '\(selected.name)' has no archived photos ready")
            }
            return selected
        }

        // Fallback heuristic (no set explicitly activated yet)
        if let strict = dataManager.sets.first(where: { set in
            set.type == .word &&
            set.status == .completed &&
            !set.banks.isEmpty &&
            set.photos.contains(where: { $0.mediaId != nil && $0.isArchived })
        }) {
            return strict
        }

        if let fallback = dataManager.sets.first(where: { set in
            set.type == .word &&
            !set.banks.isEmpty &&
            set.photos.contains(where: { $0.mediaId != nil && $0.isArchived })
        }) {
            print("⚠️ [SECRET] Using fallback word set (status: \(fallback.status.rawValue))")
            return fallback
        }

        return nil
    }
    
    /// Reveal word by unarchiving letters one by one (1s delay between each)
    private func revealWord(_ word: String, fromSet set: PhotoSet) async {
        // Letters are read right-to-left: last letter → bank 1 (oldest/bottom of grid),
        // so the spectator reading the grid top-to-bottom sees the word in correct order.
        // e.g. "coche" → bank1=e, bank2=h, bank3=c, bank4=o, bank5=c
        let letters = Array(word.lowercased().reversed())
        let alphabet = set.selectedAlphabet ?? .latin
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] REVEALING '\(word)' (\(letters.count) letters, reversed for grid order)")
        print("🎩 [SECRET] Set: '\(set.name)', Alphabet: \(alphabet.displayName)")
        print("🎩 [SECRET] Banks (sorted): \(sortedBanks.map { "pos\($0.position)=\($0.name)" })")
        
        var successCount = 0
        var failCount = 0
        // Track every mediaId revealed in this word so we can mark them as
        // post-reveal protected at the end (anti-bot: prevents the same media
        // from being archived again within the protection window).
        var revealedMediaIds: [String] = []

        for (index, letter) in letters.enumerated() {
            // Check if task was cancelled
            if Task.isCancelled {
                print("⚠️ [SECRET] Reveal task cancelled at letter \(index)")
                break
            }
            
            // Find the letter character in the alphabet
            guard let charIndex = alphabet.indexFor(String(letter)) else {
                print("❌ [SECRET] Letter '\(letter)' NOT FOUND in alphabet \(alphabet.displayName)")
                failCount += 1
                continue
            }
            
            let symbol = alphabet.characters[charIndex]
            
            // Get the bank by position (1-based), not array index
            let bankPosition = index + 1
            guard let bank = sortedBanks.first(where: { $0.position == bankPosition }) ?? (index < sortedBanks.count ? sortedBanks[index] : nil) else {
                print("❌ [SECRET] No bank for position \(bankPosition)")
                failCount += 1
                break
            }
            
            // Find photo with this symbol in this bank
            let photosInBank = set.photos.filter { $0.bankId == bank.id }

            // Check if the photo was already unarchived in a previous reveal (count as success, no API call needed)
            if let alreadyRevealed = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
                print("ℹ️ [SECRET] [\(index + 1)/\(letters.count)] '\(letter)' already unarchived locally (mediaId: \(alreadyRevealed.mediaId ?? "?")) — skipping API call")
                successCount += 1
                continue
            }

            guard let photo = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }) else {
                print("❌ [SECRET] Photo NOT FOUND for symbol '\(symbol)' in bank '\(bank.name)' (pos \(bank.position))")
                print("❌ [SECRET] Bank has \(photosInBank.count) photos:")
                for p in photosInBank.prefix(5) {
                    print("   - symbol='\(p.symbol)' mediaId=\(p.mediaId ?? "nil") archived=\(p.isArchived) status=\(p.uploadStatus.rawValue)")
                }
                failCount += 1
                continue
            }
            
            guard let mediaId = photo.mediaId else {
                print("❌ [SECRET] Photo has nil mediaId (should not happen)")
                failCount += 1
                continue
            }
            
            print("🎩 [SECRET] [\(index + 1)/\(letters.count)] Revealing '\(letter)' → symbol '\(symbol)' from bank '\(bank.name)' mediaId=\(mediaId)")
            
            // Reveal (unarchive) the photo
            do {
                let result = try await instagram.reveal(mediaId: mediaId)
                
                if result.success {
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            isArchived: false,
                            commentId: result.commentId
                        )
                    }
                    successCount += 1
                    revealedMediaIds.append(mediaId)
                    print("✅ [SECRET] [\(index + 1)/\(letters.count)] Letter '\(letter)' REVEALED OK")
                    LogManager.shared.success("Revealed '\(letter)' (mediaId: \(mediaId))", category: .general)
                } else {
                    failCount += 1
                    print("❌ [SECRET] [\(index + 1)/\(letters.count)] Reveal returned FALSE for '\(letter)'")
                    LogManager.shared.error("Reveal failed for '\(letter)' (mediaId: \(mediaId))", category: .general)
                }
                
                // ANTI-BOT: Random delay between reveals (800ms–2200ms) to avoid machine-like patterns
                if index < letters.count - 1 {
                    let betweenDelay = UInt64.random(in: 800_000_000...2_200_000_000)
                    try? await Task.sleep(nanoseconds: betweenDelay)
                }
            } catch {
                failCount += 1
                print("❌ [SECRET] [\(index + 1)/\(letters.count)] ERROR revealing '\(letter)': \(error)")
                LogManager.shared.error("Reveal error for '\(letter)': \(error)", category: .general)
            }
        }
        
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] REVEAL COMPLETE: \(successCount) ok, \(failCount) failed, total \(letters.count)")
        LogManager.shared.info("Word reveal '\(word)': \(successCount) ok, \(failCount) failed", category: .general)

        // ANTI-BOT: Protect the just-revealed media from being archived again
        // for the protection window. Same hold mechanism Performance already
        // uses for its reveals — prevents the toxic reveal→archive→reveal
        // pattern that strongly signals automation.
        if !revealedMediaIds.isEmpty {
            InstagramSafetyGate.shared.markPostReveal(mediaIds: revealedMediaIds)
        }

        await MainActor.run {
            if successCount > 0 {
                // Notify PerformanceView so it can insert photos, show the ring, and fire CDN refresh.
                // Carries the revealed media IDs so PerformanceView can look up local images.
                NotificationCenter.default.post(
                    name: .exploreWordRevealComplete,
                    object: nil,
                    userInfo: ["mediaIds": revealedMediaIds]
                )

                // Two full-power system vibrations (same as OCR/API reveal path in PerformanceView)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
                }
            } else {
                // All failed: error notification vibration
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}


// MARK: - Explore Grid View

struct ExploreGridView: View {
    let mediaItems: [InstagramMediaItem]
    let cachedImages: [String: UIImage]
    @ObservedObject var exploreManager = ExploreManager.shared
    var onTapMedia: (Int) -> Void = { _ in }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(mediaItems.enumerated()), id: \.element.mediaId) { index, media in
                            ExploreMediaCell(
                    media: media,
                    cachedImage: cachedImages[media.imageURL]
                            )
                .onTapGesture {
                    onTapMedia(index)
                        }
                .onAppear {
                    exploreManager.loadMoreIfNeeded(currentItem: media)
                    }
                }

            if exploreManager.isLoadingMore {
                ProgressView()
                    .padding()
                    .gridCellColumns(3)
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: UserSearchResult
    let isLoading: Bool
    let onTap: () -> Void
    @State private var profileImage: UIImage?
    
    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            onTap()
        }) {
            HStack(spacing: 12) {
                // Profile picture
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(result.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if result.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if !result.fullName.isEmpty {
                        Text(result.fullName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()

                // Loading indicator appears immediately on tap while the profile loads
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .padding(.trailing, 4)
                }
            }
            .responsiveHorizontalPadding()
            .padding(.vertical, 8)
            .background(Color(UIColor.igPageBackground))
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard !result.profilePicURL.isEmpty,
              let url = URL(string: result.profilePicURL) else { return }
        
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
                }
            }
        }
    }
}

// MARK: - Explore Media Cell

struct ExploreMediaCell: View {
    let media: InstagramMediaItem
    let cachedImage: UIImage?
    
    var body: some View {
        // 4:5 portrait container — image fills via scaledToFill, no distortion.
        // LazyVGrid renders only the ~6-9 visible cells at a time, so having
        // an AVPlayer per visible video cell is safe (same as real Instagram).
        // Cells that scroll off screen are destroyed and their players released.
        Color.clear
            .aspectRatio(4/5, contentMode: .fit)
            .overlay(
            ZStack(alignment: .topTrailing) {
                    if media.mediaType == .video, let videoURL = media.videoURL, !videoURL.isEmpty {
                        GridVideoPlayer(
                            videoURL: videoURL,
                            muted: true,
                            posterImage: cachedImage
                        )
                } else if let image = cachedImage {
                    Image(uiImage: image)
                        .resizable()
                            .scaledToFill()
                } else {
                        SkeletonGridItem()
                    }

                    // Video badge only when there's no videoURL (thumbnail-only
                    // fallback) — if it's playing inline no badge is needed.
                    if media.mediaType == .video,
                       (media.videoURL == nil || media.videoURL?.isEmpty == true) {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                                    .padding(.bottom, 6)
                                Spacer()
                            }
                        }
                    }

                    // Carousel indicator
                if media.mediaType == .carousel {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(6)
                }
            }
            )
            .clipped()
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted by ExploreView when Cover Typing is confirmed by pressing Space.
    /// userInfo["word"] -> String
    /// userInfo["bioActive"] -> Bool
    /// userInfo["postPredictionActive"] -> Bool
    static let coverTypingWordCommitted = Notification.Name("com.vault.coverTypingWordCommitted")

    /// Posted by ExploreView when a secret-input word reveal finishes successfully.
    /// userInfo["mediaIds"] → [String]  (the unarchived media IDs)
    static let exploreWordRevealComplete = Notification.Name("com.vault.exploreWordRevealComplete")

    /// Posted by `InstagramService.getProfileInfo` for own profile as soon as the
    /// header (username, profile pic, follower/following/media counts) is ready,
    /// BEFORE the heavy media/reels/tagged/highlights chain starts. Lets the
    /// Performance view render the header progressively while the rest loads.
    /// userInfo["snapshot"] → `InstagramProfile`  (header-only; media arrays empty)
    static let ownProfileHeaderReady = Notification.Name("com.vault.ownProfileHeaderReady")

    /// Posted as soon as `getFollowedByUsers` returns for own profile, before the
    /// posts/reels/tagged calls. Lets PerformanceView paint the "Followed by..."
    /// row right away.
    /// userInfo["followedBy"] → `[InstagramFollower]`
    static let ownProfileFollowedByReady = Notification.Name("com.vault.ownProfileFollowedByReady")

    /// Posted as soon as the first page of posts arrives from `getUserMediaItems`
    /// for own profile, before reels/tagged/highlights. Lets PerformanceView
    /// paint the grid progressively just like the search-profile view does.
    /// userInfo["mediaItems"] → `[InstagramMediaItem]`
    /// userInfo["nextMaxId"]  → `String?`
    static let ownProfileMediaReady = Notification.Name("com.vault.ownProfileMediaReady")

    /// Posted by `InstagramSyncCard` (Settings / Set header) when the user taps
    /// the manual Refresh button. PerformanceView listens and calls `loadProfileSync`.
    static let performanceManualRefresh = Notification.Name("com.vault.performanceManualRefresh")

    /// Posted by PerformanceView after a manual remote refresh finishes.
    /// userInfo["success"] -> Bool
    static let performanceManualRefreshResult = Notification.Name("com.vault.performanceManualRefreshResult")

    /// Posted by PerformanceView while a manual refresh is running.
    /// userInfo["message"] -> String
    static let performanceManualRefreshProgress = Notification.Name("com.vault.performanceManualRefreshProgress")

    /// Posted by PerformanceView the instant it receives `.performanceManualRefresh`,
    /// to acknowledge that a live listener exists. If `InstagramSyncCard` does not
    /// receive this ACK quickly, it runs a headless refresh itself so the button works
    /// even when the Performance tab is not mounted/subscribed.
    static let performanceManualRefreshAck = Notification.Name("com.vault.performanceManualRefreshAck")

    /// Posted by Settings/Sets when the user wants to resume an incomplete
    /// first-time Performance cache preload.
    static let performanceContinuePreload = Notification.Name("com.vault.performanceContinuePreload")

    /// Posted by `InstagramService.getProfileInfo` for a visited (searched)
    /// profile as soon as the header (username, profile pic, follower /
    /// following / media counts) is ready, BEFORE the media + followers chain.
    /// Lets ExploreView present `UserProfileView` immediately with a partial
    /// header while the grid loads in the background.
    /// userInfo["userId"]   → `String`
    /// userInfo["snapshot"] → `InstagramProfile`  (header-only; media arrays empty)
    static let visitedProfileHeaderReady = Notification.Name("com.vault.visitedProfileHeaderReady")

    /// Posted as soon as the posts grid arrives for a visited profile (after
    /// `getUserMediaItems`), before the followers preview call. Lets
    /// UserProfileView paint thumbnails before `getProfileInfo` returns.
    /// userInfo["userId"]     → `String`
    /// userInfo["mediaItems"] → `[InstagramMediaItem]`
    /// userInfo["nextMaxId"]  → `String?`
    static let visitedProfileMediaReady = Notification.Name("com.vault.visitedProfileMediaReady")

    /// Posted as soon as the "followed by" preview row arrives for a visited
    /// profile (after `getFollowedByUsers`).
    /// userInfo["userId"]     → `String`
    /// userInfo["followedBy"] → `[InstagramFollower]`
    static let visitedProfileFollowedByReady = Notification.Name("com.vault.visitedProfileFollowedByReady")
}
