import SwiftUI

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    @ObservedObject var instagram = InstagramService.shared
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
            // Main content (Instagram replica)
            ZStack {
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
                        onMediaAppear: loadMoreIfNeeded
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
                    // Capture pending digit buffer as the force position
                    if ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel {
                        let buffer = SecretNumberManager.shared.digitBuffer
                        if !buffer.isEmpty {
                            let position = buffer.reduce(0) { $0 * 10 + $1 }
                            ForceReelSettings.shared.pendingPosition = position
                            print("🎭 [FORCE] Position captured: \(position) — will force reel at slot \(position) in Explore")
                            // Reset buffer — InstagramProfileView's onChange will clear followingOverride automatically
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
        .onAppear {
            // CRITICAL: Keep screen on during performance (magic trick needs screen always on)
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔆 [SCREEN] Screen sleep DISABLED (Performance mode)")
            checkAndLoadProfile()
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
            
            // If reels or tagged are missing from old cache, fetch them silently in background
            if cached.cachedReelURLs.isEmpty || cached.cachedTaggedURLs.isEmpty {
                print("📦 [CACHE] Reels/tagged missing from cache — fetching in background...")
                Task { await fetchAndUpdateReelsTagged(for: cached) }
            }
        } else {
            print("📦 [CACHE] No cached profile found, loading fresh")
            loadProfileSync()
        }
    }
    
    /// Fetches only reels and tagged in background, updates the cached profile
    @MainActor
    private func fetchAndUpdateReelsTagged(for cached: InstagramProfile) async {
        guard instagram.isLoggedIn else { return }
        do {
            async let reelsTask = instagram.getUserReels(userId: cached.userId, amount: 18)
            async let taggedTask = instagram.getUserTagged(userId: cached.userId, amount: 18)
            
            let reels = try await reelsTask
            let tagged = try await taggedTask
            
            let reelURLs = reels.map { $0.imageURL }
            let taggedURLs = tagged.map { $0.imageURL }
            
            print("📦 [CACHE] Background fetch: \(reelURLs.count) reels, \(taggedURLs.count) tagged")
            
            // Build updated profile with new data
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
                cachedTaggedURLs: taggedURLs
            )
            
            self.profile = updated
            ProfileCacheService.shared.saveProfile(updated)
            
            // Download thumbnails for reels + tagged
            let allNew = reelURLs + taggedURLs
            for url in allNew {
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            print("✅ [CACHE] Reels/tagged background fetch complete")
        } catch {
            print("⚠️ [CACHE] Background reels/tagged fetch failed (non-critical): \(error)")
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
        
        // Load reel + tagged thumbnails from disk cache
        let allExtraURLs = profile.cachedReelURLs + profile.cachedTaggedURLs
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
                        HStack(spacing: 0) {
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
                        
                        if !profile.biography.isEmpty {
                            Text(profile.biography)
                                .font(.system(size: 14))
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
                    if !profile.followedBy.isEmpty {
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
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Text("Compartir perfil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                    }
                    .responsiveHorizontalPadding()
                    
                    // Story Highlights (placeholder)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.primary)
                                    )
                                Text("Nuevo")
                                    .font(.system(size: 12))
                            }
                            
                            // Placeholder highlights
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 64, height: 64)
                                    Text("Historia")
                                        .font(.system(size: 12))
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
                        selectedTab = 0
                        secretManager.reset()
                        followingOverride = nil
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
        .background(Color(uiColor: .systemBackground))
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
    // Prevent accidental rapid-fire refresh taps (min 10s between taps)
    @State private var lastRefreshTap: Date = .distantPast

    var body: some View {
        HStack {
            // Plus button (closes Performance and goes to Sets)
            Button(action: onPlusPress) {
                Image(systemName: "plus.app")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                // At symbol button (refresh) — debounced to 10 s between taps
                Button(action: {
                    let now = Date()
                    guard now.timeIntervalSince(lastRefreshTap) > 10 else {
                        print("⚠️ [PROFILE] @ refresh debounced (too fast)")
                        return
                    }
                    lastRefreshTap = now
                    onRefresh()
                }) {
                    Image(systemName: "at")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                // Menu button
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                }
            }
        }
        .responsiveHorizontalPadding()
        .frame(height: 44)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Stat View

struct StatView: View {
    let number: Int
    let label: String
    /// When set, displayed instead of the formatted number (used for secret digit feedback)
    var overrideText: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(overrideText ?? formatNumber(number))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1f M", Double(num) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        } else if num >= 1_000 {
            return String(format: "%.1f K", Double(num) / 1_000).replacingOccurrences(of: ".", with: ",")
        } else {
            return "\(num)"
        }
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
                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    }
                }
            }
            
            // Text
            if followers.count >= 2 {
                Text("Seguido/a por ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text(followers[0].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                + Text(", ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text(followers[1].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                + Text(" y ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text("\(max(0, followers.count - 2)) más")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
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
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(
                    Rectangle()
                        .fill(isSelected ? Color.primary : Color.clear)
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
