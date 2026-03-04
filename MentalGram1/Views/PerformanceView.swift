import SwiftUI
import Photos

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject private var dateForce = DateForceSettings.shared
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @AppStorage("autoProfilePicOnPerformance") private var autoProfilePicOnPerformance = false
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var showingMagicianDebug = false  // For long-press debug info
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    
    // MARK: - Infinite Scroll State
    @State private var allMediaURLs: [String] = [] // All loaded media URLs
    @State private var nextMaxId: String? = nil
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    private let maxPhotosOwnProfile = 100 // Anti-bot limit for own profile
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea() // Prevents black flash before profile loads

            // Main content (Instagram replica)
            ZStack {
                Color.white.ignoresSafeArea()
                if let profile = profile {
                    InstagramProfileView(
                        profile: profile,
                        cachedImages: $cachedImages,
                        onRefresh: loadProfileSync,
                        onPlusPress: {
                            // Back to Sets tab
                            selectedTab = 1
                        },
                        mediaURLs: allMediaURLs,
                        onMediaAppear: loadMoreIfNeeded,
                        onAutoFollowedByTap: {
                            handleAutoFollowedByTap()
                        },
                        onRevealComplete: {
                            Task { await refreshMediaGridSilently() }
                        }
                    )
                } else {
                    // Show skeleton UI (like Instagram real)
                    // Shown when: loading, network stabilizing, or no data
                    // Includes back button so user can navigate away
                    InstagramProfileSkeleton(onPlusPress: {
                        selectedTab = 1
                    })
                }
                
                // PERFORMANCE MODE LOCKDOWN: Hide technical errors from spectators
                if instagram.isLocked {
                    performanceLockdownOverlay
                }
            }
            .padding(.bottom, 65) // Space for Instagram bottom bar (matches bar height)
            
            // Instagram-style bottom bar (white bar with icons)
            InstagramBottomBar(
                profileImageURL: profile?.profilePicURL,
                cachedImage: profile?.profilePicURL != nil ? cachedImages[profile!.profilePicURL] : nil,
                isHome: true,
                isSearch: false,
                onHomePress: {
                    // Already on home/profile, do nothing
                },
                onSearchPress: {
                    // 1. Capture offset for Following Counter Magic FIRST (before buffer is cleared)
                    if FollowingMagicSettings.shared.isEnabled && SecretNumberManager.shared.hasDigits {
                        FollowingMagicSettings.shared.captureFromBuffer() // also resets buffer
                    }
                    // 2. Capture digit buffer as force-reel position
                    if ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel {
                        let buffer = SecretNumberManager.shared.digitBuffer
                        if !buffer.isEmpty {
                            let position = buffer.reduce(0) { $0 * 10 + $1 }
                            ForceReelSettings.shared.pendingPosition = position
                            print("🎭 [FORCE] Position captured: \(position) — will force reel at slot \(position) in Explore")
                            SecretNumberManager.shared.reset()
                        }
                    }
                    showingExplore = true
                },
                onReelsPress: {
                    // Reels action (disabled for now)
                },
                onMessagesPress: {
                    // Messages action (disabled for now)
                },
                onProfilePress: {
                    // Already on profile, do nothing
                }
            )
        }
        .background(Color.white.ignoresSafeArea()) // Always white — like Instagram
        .toolbar(.hidden, for: .tabBar) // HIDE native TabBar in Performance
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
        .preferredColorScheme(.light) // CRITICAL: Performance must look exactly like Instagram (light mode)
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        // When Explore closes, reset digit buffer (InstagramProfileView's onChange clears followingOverride)
        .onChange(of: showingExplore) { isOpen in
            if !isOpen {
                SecretNumberManager.shared.reset()
            }
        }
        // React to local profile cache changes (archive/unarchive, etc.)
        // without making any extra API call.
        .onChange(of: profileCache.cachedProfile?.cachedMediaURLs) { newURLs in
            guard let newURLs else { return }
            // Only sync if the change came from somewhere else (not from our own full reload)
            guard !isLoading else { return }
            let currentSet = Set(allMediaURLs)
            let newSet = Set(newURLs)
            guard currentSet != newSet else { return }
            allMediaURLs = newURLs
            // Download thumbnails for any new URLs not yet cached
            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty { downloadImagesForURLs(missing) }
            print("🔄 [PERF] Grid updated locally — \(newURLs.count) items (no API call)")
        }
        .onAppear {
            // CRITICAL: Keep screen on during performance (magic trick needs screen always on)
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔆 [SCREEN] Screen sleep DISABLED (Performance mode)")
            // Set volume to 50% so volume buttons are always detectable
            if FollowingMagicSettings.shared.isEnabled {
                VolumeButtonMonitor.shared.prepareVolume()
            }
            checkAndLoadProfile()
            // Auto profile pic: run silently in background, no UI disruption
            if autoProfilePicOnPerformance {
                Task { await autoUploadLatestGalleryPhoto() }
            }
        }
        .onDisappear {
            // Re-enable sleep when leaving Performance
            UIApplication.shared.isIdleTimerDisabled = false
            print("🌙 [SCREEN] Screen sleep RE-ENABLED")
        }
    }
    
    private func checkAndLoadProfile() {
        // ALWAYS try to load from cache first (anti-bot: no automatic requests)
        if let cached = ProfileCacheService.shared.loadProfile() {
            print("📦 [CACHE] Loading profile from cache (no auto-request)")
            self.profile = cached
            self.allMediaURLs = cached.cachedMediaURLs
            self.hasMorePages = cached.cachedMediaURLs.count >= 18
            loadCachedImages()
            
            // If supplementary data is missing from old cache, fetch silently in background
            if cached.cachedReelURLs.isEmpty || cached.cachedTaggedURLs.isEmpty || cached.cachedHighlights.isEmpty {
                print("📦 [CACHE] Supplementary data missing from cache — fetching in background...")
                Task { await fetchAndUpdateReelsTagged(for: cached) }
            }
        } else {
            print("📦 [CACHE] No cached profile found, loading fresh")
            loadProfileSync()
        }
    }
    
    /// Fetches reels, tagged and highlights in background, updates the cached profile
    @MainActor
    private func fetchAndUpdateReelsTagged(for cached: InstagramProfile) async {
        guard instagram.isLoggedIn else { return }
        do {
            async let reelsTask      = instagram.getUserReels(userId: cached.userId, amount: 18)
            async let taggedTask     = instagram.getUserTagged(userId: cached.userId, amount: 18)
            async let highlightsTask = instagram.getUserHighlights(userId: cached.userId)

            let reels      = try await reelsTask
            let tagged     = try await taggedTask
            let highlights = (try? await highlightsTask) ?? cached.cachedHighlights

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
                cachedHighlights: highlights
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
        guard instagram.isLoggedIn else { return }
        
        isLoading = true
        
        // Clear old cache first
        print("🗑️ [CACHE] Clearing old cache before fresh load")
        ProfileCacheService.shared.clearAll()
        cachedImages.removeAll()
        
        do {
            // ANTI-BOT: Wait if network changed recently
            try await instagram.waitForNetworkStability()
            
            let fetchedProfile = try await instagram.getProfileInfo()
            
            if let fetchedProfile = fetchedProfile {
                self.profile = fetchedProfile
                self.allMediaURLs = fetchedProfile.cachedMediaURLs
                self.hasMorePages = fetchedProfile.cachedMediaURLs.count >= 18
                ProfileCacheService.shared.saveProfile(fetchedProfile)
                downloadAndCacheImages(profile: fetchedProfile)
            }
            isLoading = false
        } catch let error as InstagramError {
            print("⚠️ Instagram error detected: \(error)")
            isLoading = false
            lastError = error
            showingConnectionError = true
        } catch {
            print("❌ Error loading profile: \(error)")
            isLoading = false
            lastError = .apiError(error.localizedDescription)
            showingConnectionError = true
        }
    }
    
    // Sync wrapper for non-async call sites (onRefresh button, header "@" button)
    private func loadProfileSync() {
        Task { await loadProfile() }
    }
    
    private func loadCachedImages() {
        guard let profile = profile else { return }
        
        print("📦 [CACHE] Loading cached images...")
        
        // Load profile pic
        print("📦 [CACHE] Looking for profile pic: \(String(profile.profilePicURL.prefix(80)))")
        if let image = ProfileCacheService.shared.loadImage(forURL: profile.profilePicURL) {
            cachedImages[profile.profilePicURL] = image
            print("✅ [CACHE] Profile pic loaded from cache")
        } else {
            print("⚠️ [CACHE] Profile pic not found in cache, will download")
            // If not in cache, download it now
            Task {
                if let image = await downloadImage(from: profile.profilePicURL) {
                    await MainActor.run {
                        cachedImages[profile.profilePicURL] = image
                        ProfileCacheService.shared.saveImage(image, forURL: profile.profilePicURL)
                        print("✅ [CACHE] Profile pic downloaded and cached")
                    }
                }
            }
        }
        
        // Load media thumbnails
        var loadedCount = 0
        var missingMediaURLs: [String] = []
        for url in profile.cachedMediaURLs {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                loadedCount += 1
            } else {
                missingMediaURLs.append(url)
            }
        }
        print("📦 [CACHE] Loaded \(loadedCount)/\(profile.cachedMediaURLs.count) media thumbnails from cache")
        
        // If some media thumbnails are missing, download them
        if !missingMediaURLs.isEmpty {
            print("🖼️ [CACHE] Downloading \(missingMediaURLs.count) missing media thumbnails...")
            Task {
                for url in missingMediaURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
                print("✅ [CACHE] Finished downloading missing media thumbnails")
            }
        }
        
        // Load followed by profile pics
        var followerPicsLoaded = 0
        var missingFollowerURLs: [String] = []
        for follower in profile.followedBy {
            if let picURL = follower.profilePicURL {
                if let image = ProfileCacheService.shared.loadImage(forURL: picURL) {
                    cachedImages[picURL] = image
                    followerPicsLoaded += 1
                } else {
                    missingFollowerURLs.append(picURL)
                }
            }
        }
        print("📦 [CACHE] Loaded \(followerPicsLoaded)/\(profile.followedBy.count) follower pics from cache")
        
        // If some follower pics are missing, download them
        if !missingFollowerURLs.isEmpty {
            print("🖼️ [CACHE] Downloading \(missingFollowerURLs.count) missing follower pics...")
            Task {
                for url in missingFollowerURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
                print("✅ [CACHE] Finished downloading missing follower pics")
            }
        }
        
        // Load reel + tagged + highlight cover thumbnails from disk cache
        let highlightCoverURLs = profile.cachedHighlights.map { $0.coverImageURL }
        let allExtraURLs = profile.cachedReelURLs + profile.cachedTaggedURLs + highlightCoverURLs
        var missingExtraURLs: [String] = []
        for url in allExtraURLs {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
            } else {
                missingExtraURLs.append(url)
            }
        }
        if !missingExtraURLs.isEmpty {
            Task {
                for url in missingExtraURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }
        }

        print("📦 [CACHE] Total cached images loaded: \(cachedImages.count)")
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
        
        isLoadingMore = true
        print("📜 [PROFILE] Loading more media (current count: \(allMediaURLs.count))...")
        
        Task {
            do {
                // Fetch next batch
                let (mediaItems, newMaxId) = try await instagram.getUserMediaItems(userId: profile?.userId, amount: 21, maxId: nextMaxId)
                
                await MainActor.run {
                    // Calculate how many we can add without exceeding limit
                    let remainingSlots = maxPhotosOwnProfile - allMediaURLs.count
                    let itemsToAdd = min(mediaItems.count, remainingSlots)
                    
                    let newURLs = mediaItems.prefix(itemsToAdd).map { $0.imageURL }
                    
                    // Filter to multiples of 3 to avoid UI gaps
                    let totalAfterAdd = allMediaURLs.count + newURLs.count
                    let remainder = totalAfterAdd % 3
                    let urlsToDisplay = remainder == 0 ? newURLs : Array(newURLs.dropLast(remainder))
                    
                    allMediaURLs.append(contentsOf: urlsToDisplay)
                    nextMaxId = newMaxId
                    hasMorePages = (newMaxId != nil) && (allMediaURLs.count < maxPhotosOwnProfile)
                    isLoadingMore = false
                    
                    print("📜 [PROFILE] Loaded \(urlsToDisplay.count) more, total now: \(allMediaURLs.count), hasMore: \(hasMorePages)")
                    
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
        // Trigger load when user reaches 80% of loaded items
        guard let index = allMediaURLs.firstIndex(of: currentURL) else { return }
        let threshold = max(1, Int(Double(allMediaURLs.count) * 0.8))
        
        if index >= threshold {
            print("📜 [PROFILE] User reached 80% (\(index)/\(allMediaURLs.count)) - loading more...")
            loadMoreMedia()
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
            return nil
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ [DOWNLOAD] Invalid URL: \(urlString)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 [DOWNLOAD] HTTP \(httpResponse.statusCode) for: \(String(urlString.prefix(60)))...")
                
                if httpResponse.statusCode != 200 {
                    print("❌ [DOWNLOAD] Non-200 status code")
                    return nil
                }
            }
            
            guard let image = UIImage(data: data) else {
                print("❌ [DOWNLOAD] Failed to create UIImage from data")
                return nil
            }
            
            return image
        } catch {
            print("❌ [DOWNLOAD] Error: \(error.localizedDescription)")
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
                    Text("No Internet Connection")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("Check your connection and try again")
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
        .alert("🔓 Debug Info (Magician Only)", isPresented: $showingMagicianDebug) {
            Button("Close", role: .cancel) { }
        } message: {
            if let lockUntil = instagram.lockUntil {
                let remaining = max(0, Int(lockUntil.timeIntervalSinceNow))
                let mins = remaining / 60
                let secs = remaining % 60
                
                Text("""
                Real Cause: \(instagram.lockReason)
                
                ⚠️ STOP THE TRICK - DO NOT CONTINUE
                
                Countdown: \(mins):\(String(format: "%02d", secs)) remaining
                
                Instructions:
                • Do NOT reveal/hide more photos
                • Do NOT open Instagram
                • End the trick naturally
                • Wait for countdown to finish
                • Check logs in Settings > Developer > Logs
                
                The app has stopped all requests to prevent account suspension.
                """)
            } else {
                Text("""
                Real Cause: \(instagram.lockReason)
                
                ⚠️ STOP THE TRICK - DO NOT CONTINUE
                
                Check logs in Settings > Developer > Logs for details.
                """)
            }
        }
    }
    
    private func showMagicianDebugInfo() {
        print("🔓 [MAGICIAN] Debug info requested")
        LogManager.shared.info("Magician accessed debug info during performance lockdown", category: .general)
        showingMagicianDebug = true
    }

    // MARK: - Silent Media Grid Refresh (after Force Number Reveal unarchive)

    /// Fetches only the first page of media and updates the grid locally.
    /// Does NOT touch profile stats, bio, follower count, etc. — zero visible disruption.
    @MainActor
    private func refreshMediaGridSilently() async {
        guard !instagram.isLocked, let userId = profile?.userId else { return }
        print("🔄 [PERF] Silent media refresh after unarchive…")
        do {
            let (items, _) = try await instagram.getUserMediaItems(userId: userId, amount: 21, maxId: nil)
            let newURLs = items.map { $0.imageURL }
            guard !newURLs.isEmpty else { return }

            // Merge: new first-page items + tail items not in the new page
            let existingTail = allMediaURLs.filter { !newURLs.contains($0) }
            let merged = newURLs + existingTail
            allMediaURLs = merged

            ProfileCacheService.shared.updateMediaURLs(merged)

            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty { downloadImagesForURLs(missing) }

            print("🔄 [PERF] Silent refresh done — \(merged.count) items")
        } catch {
            print("⚠️ [PERF] Silent media refresh failed (non-critical): \(error)")
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

        print("📷 [AUTO PIC] Uploading new profile picture (\(imageData.count / 1024) KB)…")

        // ── Upload ──
        do {
            let success = try await instagram.changeProfilePicture(imageData: imageData)
            if success, let uiImage = UIImage(data: imageData) {
                UserDefaults.standard.set(assetId, forKey: Self.lastUploadedAssetKey)
                UserDefaults.standard.set(hash,    forKey: Self.lastUploadedHashKey)

                // Show new image in the fake profile immediately
                // Use current profilePicURL as cache key — visually correct until next full refresh
                let picURL = profile?.profilePicURL ?? "autoPic_pending"
                cachedImages[picURL] = uiImage
                ProfileCacheService.shared.saveImage(uiImage, forURL: picURL)

                print("📷 [AUTO PIC] ✅ Profile picture updated successfully")
            }
        } catch {
            print("📷 [AUTO PIC] Upload skipped: \(error.localizedDescription)")
        }
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

    /// Called when the magician taps the "Followed by" area in Auto mode.
    /// First tap: fetches recent followers and loads spectators (date group shown).
    /// Subsequent taps: toggles between date group and time group display.
    private func handleAutoFollowedByTap() {
        guard dateForce.isEnabled && dateForce.mode == .auto else { return }
        guard !dateForce.isAutoLoading else { return }

        if dateForce.hasSpectators {
            // Already loaded: just toggle group display
            dateForce.toggleAutoDisplayGroup()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            // First tap: fetch new followers
            loadAutoFollowers()
        }
    }

    @MainActor
    private func loadAutoFollowers() {
        guard !dateForce.isAutoLoading else { return }
        dateForce.isAutoLoading = true

        Task {
            do {
                let count = dateForce.autoMaxFollowers
                print("🤖 [AUTO] Fetching \(count) recent followers...")
                let followers = try await instagram.getRecentFollowers(count: count)
                print("🤖 [AUTO] Got \(followers.count) followers, fetching profiles one by one...")

                // Pre-calculate groups based on actual number returned (≤ count)
                await MainActor.run {
                    dateForce.beginAutoLoad(totalExpected: followers.count)
                }

                for (i, follower) in followers.enumerated() {
                    // Anti-bot delay between each profile lookup
                    if i > 0 {
                        try? await Task.sleep(nanoseconds: UInt64.random(in: 700_000_000...1_500_000_000))
                    }

                    if let p = try? await instagram.getProfileInfo(userId: follower.userId) {
                        // Add immediately → UI updates with this spectator right away
                        await MainActor.run {
                            dateForce.appendAutoSpectator(
                                username: follower.username,
                                followingCount: p.followingCount
                            )
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } else {
                        print("⚠️ [AUTO] Could not fetch profile for @\(follower.username)")
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
    let onRefresh: () -> Void
    let onPlusPress: () -> Void
    @State private var selectedTab = 0

    // Infinite scroll support
    var mediaURLs: [String]? = nil // If provided, use instead of profile.cachedMediaURLs
    var onMediaAppear: ((String) -> Void)? = nil // Called when a media cell appears

    // Date Force Auto mode
    @ObservedObject private var dateForce = DateForceSettings.shared
    var onAutoFollowedByTap: (() -> Void)? = nil

    // Called after a successful Force Number Reveal — triggers silent media grid refresh
    var onRevealComplete: (() -> Void)? = nil

    // Secret number input
    @ObservedObject private var secretManager = SecretNumberManager.shared
    @State private var followingOverride: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                InstagramHeaderView(username: profile.username, isVerified: profile.isVerified, onRefresh: onRefresh, onPlusPress: onPlusPress)

                
                // Profile Info
                VStack(spacing: 16) {
                    // Profile Picture + Stats
                    HStack(alignment: .center, spacing: 0) {
                        // Profile Picture
                        ZStack(alignment: .bottomTrailing) {
                            if let image = cachedImages[profile.profilePicURL] {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 86, height: 86)
                                    .clipShape(Circle())
                                    .onAppear {
                                        print("✅ [UI] Profile pic image displayed")
                                    }
                            }                             else {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 86, height: 86)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    )
                                    .onAppear {
                                        print("⚠️ [UI] Profile pic not in cache")
                                        print("⚠️ [UI] Looking for URL: \(String(profile.profilePicURL.prefix(80)))")
                                        print("⚠️ [UI] Available cached URLs: \(cachedImages.keys.map { String($0.prefix(40)) }.joined(separator: ", "))")
                                    }
                            }
                            
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .padding(.leading, UIScreen.main.bounds.width * 0.04)
                        
                        Spacer(minLength: 8)
                        
                        // Stats
                        HStack(spacing: UIScreen.main.bounds.width < 400 ? 20 : 40) {
                            StatView(number: profile.mediaCount, label: "publicaciones")
                            StatView(number: profile.followerCount, label: "seguidores")
                            StatView(number: profile.followingCount, label: "seguidos",
                                     overrideText: followingOverride)
                        }
                        .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                    }
                    
                    // Name + Bio
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.fullName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                        
                        if !profile.biography.isEmpty {
                            Text(profile.biography)
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if let url = profile.externalUrl {
                            Link(url, destination: URL(string: "https://\(url)")!)
                                .font(.system(size: 14))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
                    // Followed by
                    if dateForce.isEnabled && dateForce.mode == .auto {
                        AutoFollowedByView(dateForce: dateForce, onTap: onAutoFollowedByTap)
                            .responsiveHorizontalPadding()
                    } else if !profile.followedBy.isEmpty {
                        FollowedByView(followers: profile.followedBy, cachedImages: cachedImages)
                            .responsiveHorizontalPadding()
                    }
                    
                    // Edit Profile + Share Profile buttons
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Text("Editar perfil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Text("Compartir perfil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                    }
                    .responsiveHorizontalPadding()
                    
                    // Story Highlights
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // "New" button (always shown, Instagram-style)
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.black)
                                    )
                                Text("Nuevo")
                                    .font(.system(size: 12))
                                    .foregroundColor(.black)
                            }

                            if profile.cachedHighlights.isEmpty {
                                // Skeleton placeholders while loading
                                ForEach(0..<4, id: \.self) { _ in
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 64, height: 64)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 44, height: 10)
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
                
                // Tabs — tapping a tab resets the secret digit buffer
                HStack(spacing: 0) {
                    TabButton(icon: "square.grid.3x3", isSelected: selectedTab == 0) {
                        // Force Number Reveal: if enabled and digits are buffered, trigger reveal
                        if ForceNumberRevealSettings.shared.isEnabled,
                           secretManager.hasDigits,
                           let activeId = ActiveSetSettings.shared.activeNumberSetId,
                           let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) {
                            let digits = secretManager.digitBuffer
                            secretManager.reset()
                            followingOverride = nil
                            Task { await revealByDigits(digits, fromSet: activeSet) }
                        } else {
                            secretManager.reset()
                            followingOverride = nil
                        }
                        selectedTab = 0
                    }
                    TabButton(icon: "play.rectangle", isSelected: selectedTab == 1) {
                        selectedTab = 1
                        secretManager.reset()
                        followingOverride = nil
                    }
                    TabButton(icon: "person.crop.square", isSelected: selectedTab == 2) {
                        selectedTab = 2
                        secretManager.reset()
                        followingOverride = nil
                    }
                }
                .frame(height: 44)
                
                Divider()
                
                // Tab content — always show the full grid (with placeholders if needed)
                // so swipe digit-detection works regardless of how many photos exist.
                Group {
                    switch selectedTab {
                    case 0:
                        let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
                        PhotosGridView(mediaURLs: urlsToShow, cachedImages: cachedImages,
                                       onMediaAppear: onMediaAppear)
                    case 1:
                        ReelsGridView(reelURLs: profile.cachedReelURLs, cachedImages: cachedImages)
                    case 2:
                        PhotosGridView(mediaURLs: profile.cachedTaggedURLs, cachedImages: cachedImages)
                    default:
                        EmptyView()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in handleGridSwipe(value) }
                )
            }
        }
        // Pull-to-refresh: calls onRefresh which reloads profile + reels + tagged
        .refreshable {
            onRefresh()
        }
        .background(Color.white)
        // Keep following count display in sync with digit buffer
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
    }

    // MARK: - Secret number gesture handling

    private func handleGridSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let absDx = abs(dx)
        let absDy = abs(dy)

        let isHorizontal = absDx > absDy && absDx > 30
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

        // Natural tab navigation: swipe left = next tab, right = previous tab
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = dx < 0
                ? min(2, selectedTab + 1)
                : max(0, selectedTab - 1)
        }
    }

    private func updateFollowingOverride() {
        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
        } else {
            followingOverride = secretManager.followingDisplayString(originalCount: profile.followingCount)
        }
    }

    // MARK: - Force Number Reveal

    /// Unarchives the photo matching each digit in the corresponding bank, sequentially.
    /// Digit at position i (0-based) → bank i+1 → find photo with symbol == String(digit).
    private func revealByDigits(_ digits: [Int], fromSet set: PhotoSet) async {
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        // Digits are read right-to-left: last digit → bank 1, second-to-last → bank 2, etc.
        // e.g. 568 → bank1=8, bank2=6, bank3=5
        let reversedDigits = digits.reversed()

        print("🔢 [FORCE#] ═══════════════════════════════════════")
        print("🔢 [FORCE#] Revealing digits: \(digits.map { String($0) }.joined()) (reversed: \(reversedDigits.map { String($0) }.joined())) from set '\(set.name)'")
        LogManager.shared.info("Force number reveal: \(digits.map { String($0) }.joined()) from set '\(set.name)'", category: .general)

        var successCount  = 0
        var skipCount     = 0
        var failCount     = 0
        var revealedIds: [String] = [] // collected for auto re-archive

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

            // Already unarchived locally → count as success, still add to re-archive list
            if let already = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }),
               let mediaId = already.mediaId {
                print("ℹ️ [FORCE#] Digit \(digit) bank \(i + 1): already unarchived locally — skipping API")
                revealedIds.append(mediaId)
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
                let unarchived = try await instagram.unarchivePhoto(mediaId: mediaId)
                if unarchived {
                    dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                            isArchived: false, uploadStatus: .completed, errorMessage: nil)
                    print("✅ [FORCE#] Digit \(digit) bank \(i + 1): unarchived (ID: \(mediaId))")
                    LogManager.shared.success("Force reveal digit \(digit) bank \(i + 1) (ID: \(mediaId))", category: .general)
                    revealedIds.append(mediaId)
                    successCount += 1
                } else {
                    print("⚠️ [FORCE#] Digit \(digit) bank \(i + 1): unarchive returned false")
                    failCount += 1
                }
            } catch {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1) error: \(error)")
                LogManager.shared.error("Force reveal error digit \(digit) bank \(i + 1): \(error.localizedDescription)", category: .general)
                failCount += 1
            }
        }

        print("🔢 [FORCE#] Done — \(successCount) ok, \(skipCount) skipped, \(failCount) failed")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Schedule auto re-archive if enabled and we have IDs to re-archive
        if !revealedIds.isEmpty {
            ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: revealedIds)
        }

        // If at least one photo was actually unarchived via API, silently refresh
        // the media grid so the photo appears without the magician pulling to refresh.
        if successCount > 0 {
            onRevealComplete?()
        }
    }

}

// MARK: - Reels Grid View (4:5 aspect with play icon overlay)

struct ReelsGridView: View {
    let reelURLs: [String]
    let cachedImages: [String: UIImage]
    /// 12 cells = 4 rows, so digit 0 (row 4+) is reachable
    var minCells: Int = 12

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        let placeholderCount = max(0, minCells - reelURLs.count)
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(reelURLs, id: \.self) { url in
                ZStack(alignment: .bottomLeading) {
                    if let image = cachedImages[url] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(4/5, contentMode: .fill) // Same size as Posts grid
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(4/5, contentMode: .fill)
                    }
                    // Play icon overlay (like Instagram reels tab)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            // Placeholder cells — same size, same play icon
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(4/5, contentMode: .fill)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(6)
                    }
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
    var body: some View {
        HStack {
            // Plus button (closes Performance and goes to Sets)
            Button(action: onPlusPress) {
                Image(systemName: "plus.app")
                    .font(.system(size: 24))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            // Username with dropdown
            HStack(spacing: 4) {
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                Text(username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "at")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.black)
                }
                
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22))
                        .foregroundColor(.black)
                }
            }
        }
        .responsiveHorizontalPadding()
        .frame(height: 44)
        .background(Color.white)
    }
}

// MARK: - Stat View

struct StatView: View {
    let number: Int
    let label: String
    var overrideText: String? = nil

    private static let textBlack = Color.black
    private static let textGray = Color(white: 0.56)

    var body: some View {
        VStack(spacing: 2) {
            Text(overrideText ?? formatCount(number))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Self.textBlack)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Self.textGray)
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
                    .frame(width: 68, height: 68)

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 62, height: 62)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }

            Text(highlight.title)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 68)
        }
    }
}

// MARK: - Auto Followed By View (Date Force Auto Mode)

struct AutoFollowedByView: View {
    @ObservedObject var dateForce: DateForceSettings
    let onTap: (() -> Void)?

    private var displayedSpectators: [DateForceSpectator] {
        dateForce.spectators.filter { $0.group == dateForce.autoDisplayGroup }
    }

    private var isDateGroup: Bool { dateForce.autoDisplayGroup == .date }
    private var isLoading: Bool { dateForce.isAutoLoading }
    private var loaded: Int { dateForce.spectators.count }
    private var total: Int { dateForce.autoMaxFollowers }

    // Index of the last spectator in the date group
    private var lastDateIndex: Int {
        let dateCount = (total + 1) / 2
        return dateCount - 1
    }

    private func label(for spec: DateForceSpectator, at index: Int) -> String {
        let name = "@\(spec.username)"
        // Append a dash only to the last date-group spectator — subtle group separator
        return (spec.group == .date && index == lastDateIndex) ? "\(name) —" : name
    }

    var body: some View {
        Button(action: { onTap?() }) {
            if isLoading && loaded == 0 {
                // Nothing yet: spinner
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).frame(width: 20, height: 20)
                    Text("Capturing followers…")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.56))
                }

            } else if isLoading && loaded > 0 {
                // Progressive: names appearing one by one, plain text
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(dateForce.spectators.enumerated()), id: \.element.id) { index, spec in
                        Text(label(for: spec, at: index))
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: loaded)

            } else if loaded > 0 {
                // Fully loaded: compact tap-to-toggle view
                HStack(spacing: 6) {
                    Text(displayedSpectators.map { "@\($0.username)" }.joined(separator: "  "))
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.7))
                }

            } else {
                // Idle
                HStack(spacing: 6) {
                    Text("Seguido/a por")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.56))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Followed By View

struct FollowedByView: View {
    let followers: [InstagramFollower]
    let cachedImages: [String: UIImage]
    
    var body: some View {
        HStack(spacing: 4) {
            // Profile pictures
            HStack(spacing: -8) {
                ForEach(followers.prefix(3), id: \.username) { follower in
                    if let picURL = follower.profilePicURL,
                       let image = cachedImages[picURL] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            
            // Text
            if followers.count >= 2 {
                Text("Seguido/a por ")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.56))
                + Text(followers[0].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                + Text(", ")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.56))
                + Text(followers[1].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                + Text(" y ")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.56))
                + Text("\(max(0, followers.count - 2)) más")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
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
            ForEach(mediaURLs, id: \.self) { url in
                if let image = cachedImages[url] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(4/5, contentMode: .fill)
                        .clipped()
                        .onAppear { onMediaAppear?(url) }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(4/5, contentMode: .fill)
                        .onAppear { onMediaAppear?(url) }
                }
            }
            // Placeholder cells — look like loading skeletons, enable digit-detection anywhere
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .aspectRatio(4/5, contentMode: .fill)
                }
            }
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
    
    var body: some View {
        ZStack(alignment: .top) {
            // White background with top border
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 0, x: 0, y: -0.33)
            
            // Icons aligned to top
            HStack(spacing: 0) {
                // Home button (house outline)
                Button(action: onHomePress) {
                    Image(systemName: isHome ? "house.fill" : "house")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Search button (magnifying glass)
                Button(action: onSearchPress) {
                    Image(systemName: isSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Reels button (play in rounded rectangle)
                Button(action: onReelsPress) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Messages button (paper plane with red dot)
                Button(action: onMessagesPress) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.black)
                        
                        // Red notification dot
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 6, y: -3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Profile button (circular profile pic)
                Button(action: onProfilePress) {
                    if let image = cachedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 1.5)
                            )
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 26))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .frame(height: 65) // Taller bar
        }
        .frame(height: 65)
    }
}
