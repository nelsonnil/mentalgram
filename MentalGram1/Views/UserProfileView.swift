import SwiftUI

/// Vista de perfil de usuario buscado (réplica exacta de Instagram)
struct UserProfileView: View {
    let profile: InstagramProfile
    let onClose: () -> Void
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isLoadingImages = true
    @State private var selectedTab = 0
    @State private var isFollowing: Bool
    @State private var isFollowRequested: Bool
    @State private var isFollowActionLoading = false
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var currentProfile: InstagramProfile
    
    // MARK: - Infinite Scroll State
    @State private var allMediaURLs: [String] = []
    @State private var mediaItemsByURL: [String: InstagramMediaItem] = [:]
    @State private var nextMaxId: String? = nil
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    private let maxPhotosOtherProfile = 50 // Anti-bot limit for other profiles

    // Post viewer state
    @State private var showingPostViewer = false
    @State private var selectedPostIndex = 0

    // Secret number input
    @ObservedObject private var secretManager = SecretNumberManager.shared
    @State private var followingOverride: String? = nil

    // Following Counter Magic
    @ObservedObject private var followingMagic = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor = VolumeButtonMonitor.shared
    @State private var magicFollowingText: String? = nil   // overrides "following" column
    @State private var magicFollowerText: String?  = nil   // overrides "followers" column
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer? = nil
    @State private var showGlitch = false

    // Date Force ("El Oráculo Social")
    @ObservedObject private var dateForce = DateForceSettings.shared
    @State private var dateForceCancelled = false  // Tap on profile pic = cancel this profile

    // Force Post
    @ObservedObject private var forcePost = ForcePostSettings.shared
    
    init(profile: InstagramProfile, onClose: @escaping () -> Void) {
        self.profile = profile
        self.onClose = onClose
        self._isFollowing = State(initialValue: profile.isFollowing)
        self._isFollowRequested = State(initialValue: profile.isFollowRequested)
        self._currentProfile = State(initialValue: profile)
        self._allMediaURLs = State(initialValue: profile.cachedMediaURLs)
        self._hasMorePages = State(initialValue: profile.cachedMediaURLs.count >= 18)
        var initialItems: [String: InstagramMediaItem] = [:]
        for item in profile.cachedMediaItems { initialItems[item.imageURL] = item }
        self._mediaItemsByURL = State(initialValue: initialItems)
    }

    // MARK: - Force Post computed helpers

    private var isForcePostTarget: Bool {
        guard forcePost.isEnabled, !forcePost.forcedMediaURL.isEmpty else { return false }
        // Compare numerically to handle cases where one ID has leading zeros or different format
        return forcePost.targetUserId == currentProfile.userId
            || forcePost.targetUsername.lowercased() == currentProfile.username.lowercased()
    }

    private var forcePostActiveURL: String? {
        isForcePostTarget ? forcePost.forcedMediaURL : nil
    }

    /// Grid URLs with the forced post removed (spectator doesn't see it in grid)
    private var gridURLsForDisplay: [String] {
        guard isForcePostTarget else { return allMediaURLs }
        let filtered = allMediaURLs.filter { !urlMatchesForced($0) }
        print("🎯 [FORCE] Grid: \(allMediaURLs.count) → \(filtered.count) (removed forced post)")
        return filtered
    }

    /// Checks whether a media URL belongs to the forced post.
    /// CDN URLs expire and change between sessions, so we match by mediaId
    /// which is stable and embedded in the URL path (e.g. /t51.../3849022646_...).
    /// We also try direct equality and path equality as fallbacks.
    private func urlMatchesForced(_ url: String) -> Bool {
        let forced = forcePost.forcedMediaURL
        let mediaId = forcePost.forcedMediaId
        if url == forced { return true }
        // Match by mediaId — the numeric ID appears in CDN URL paths
        if !mediaId.isEmpty && (url.contains(mediaId) || forced.contains(mediaId)) {
            return url.contains(mediaId)
        }
        // Compare path component only (strips CDN query params)
        guard let u1 = URL(string: url), let u2 = URL(string: forced) else { return false }
        return u1.path == u2.path
    }

    /// Post viewer URLs with the forced post inserted at the middle
    private var postViewerURLs: [String] {
        guard isForcePostTarget else { return allMediaURLs }
        var urls = allMediaURLs.filter { !urlMatchesForced($0) }
        let insertAt = min(urls.count / 2, urls.count)
        urls.insert(forcePost.forcedMediaURL, at: insertAt)
        return urls
    }

    /// Media items dict enriched with the forced post's metadata
    private var postViewerItems: [String: InstagramMediaItem] {
        guard isForcePostTarget, let item = forcePost.forcedMediaItem else { return mediaItemsByURL }
        var items = mediaItemsByURL
        items[forcePost.forcedMediaURL] = item
        return items
    }

    /// Cached images enriched with the forced post's thumbnail
    private var postViewerCachedImages: [String: UIImage] {
        guard isForcePostTarget, let img = forcePost.localThumbnailImage else { return cachedImages }
        var images = cachedImages
        images[forcePost.forcedMediaURL] = img
        return images
    }

    /// Maps a grid index to the correct post viewer index (accounting for the inserted forced post)
    private func mappedPostViewerIndex(_ gridIndex: Int) -> Int {
        guard isForcePostTarget else { return gridIndex }
        let filteredURLs = gridURLsForDisplay
        let insertAt = min(filteredURLs.count / 2, filteredURLs.count)
        return gridIndex >= insertAt ? gridIndex + 1 : gridIndex
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (igual que Instagram)
                HStack(spacing: 8) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                    }
                    
                    // Username con candado si es privado — pegado al botón de retroceso
                    HStack(spacing: 4) {
                        if profile.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                        }
                        Text(profile.username)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                    }
                }
                .responsiveHorizontalPadding()
                .padding(.vertical, 12)
                .background(Color.white)
                
                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile Picture + Stats
                        HStack(alignment: .center, spacing: 0) {
                            // Profile Picture con círculo de historia
                            // TAP AQUÍ = Refresh inteligente (discreto, solo haptic)
                            ZStack(alignment: .bottomTrailing) {
                                if !profile.profilePicURL.isEmpty,
                                   let image = cachedImages[profile.profilePicURL] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 86, height: 86)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.purple, .red, .orange],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 3.5
                                                )
                                                .padding(-3.5)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 86, height: 86)
                                }
                                
                            }
                            .padding(.leading, UIScreen.main.bounds.width * 0.04)
                            .onTapGesture {
                                if dateForce.isEnabled {
                                    cancelDateForceSpectator()
                                } else {
                                    performIntelligentRefresh()
                                }
                            }
                            
                            Spacer(minLength: 4)

                            // Columna derecha: nombre encima de los stats
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.fullName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.black)
                                    .lineLimit(1)

                                HStack(spacing: 0) {
                                    StatView(number: currentProfile.mediaCount, label: "posts")
                                        .frame(maxWidth: .infinity)
                                    StatView(number: currentProfile.followerCount, label: "followers",
                                             overrideText: magicFollowerText)
                                        .frame(maxWidth: .infinity)
                                    StatView(number: currentProfile.followingCount, label: "following",
                                             overrideText: magicFollowingText ?? followingOverride)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                        }

                        // Bio
                        VStack(alignment: .leading, spacing: 4) {
                            if !profile.biography.isEmpty {
                                Text(profile.biography)
                                    .font(.system(size: 14))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let url = profile.externalUrl, !url.isEmpty {
                                Link(url, destination: URL(string: "https://\(url)")!)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .responsiveHorizontalPadding()
                        
                        // Followed by
                        if !currentProfile.followedBy.isEmpty {
                            FollowedByView(followers: currentProfile.followedBy, cachedImages: cachedImages)
                                .responsiveHorizontalPadding()
                        }
                        
                        // Following/Follow + Message buttons
                        HStack(spacing: 8) {
                            // Follow/Following/Requested button (FUNCIONAL)
                            Button(action: toggleFollow) {
                                if isFollowActionLoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .cornerRadius(8)
                                } else if isFollowing {
                                    // Already following - show "Following" with dropdown
                                    HStack(spacing: 4) {
                                        Text("Following")
                                            .font(.system(size: 14, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                                } else if isFollowRequested {
                                    // Request pending - show "Requested" (NO dropdown)
                                    Text("Requested")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(Color(uiColor: .systemGray5))
                                        .foregroundColor(.primary)
                                        .cornerRadius(8)
                                } else {
                                    // Not following - show "Follow" in blue
                                    Text("Follow")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .disabled(isFollowActionLoading)
                            
                            Button(action: {}) {
                                Text("Message")
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
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .cornerRadius(8)
                            }
                        }
                        .responsiveHorizontalPadding()
                    }
                    .padding(.vertical, 12)

                    // Story Highlights
                    if !currentProfile.cachedHighlights.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(currentProfile.cachedHighlights) { highlight in
                                    StoryHighlightCell(highlight: highlight,
                                                       image: cachedImages[highlight.coverImageURL])
                                }
                            }
                            .responsiveHorizontalPadding()
                        }
                        .padding(.vertical, 8)
                    }

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
                    Group {
                        switch selectedTab {
                        case 0:
                            PhotosGridView(
                                mediaURLs: gridURLsForDisplay,
                                cachedImages: cachedImages,
                                onMediaAppear: loadMoreIfNeeded,
                                onTapIndex: { index in
                                    selectedPostIndex = index
                                    showingPostViewer = true
                                }
                            )
                        case 1:
                            ReelsGridView(reelURLs: currentProfile.cachedReelURLs, cachedImages: cachedImages)
                        case 2:
                            PhotosGridView(mediaURLs: currentProfile.cachedTaggedURLs, cachedImages: cachedImages)
                        default:
                            EmptyView()
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in handleGridSwipe(value) }
                    )
                    .fullScreenCover(isPresented: $showingPostViewer) {
                        PostScrollView(
                            mediaURLs: postViewerURLs,
                            mediaItemsByURL: postViewerItems,
                            cachedImages: postViewerCachedImages,
                            initialIndex: mappedPostViewerIndex(selectedPostIndex),
                            username: currentProfile.username,
                            profileImage: cachedImages[currentProfile.profilePicURL],
                            userId: currentProfile.userId,
                            forcePostURL: forcePostActiveURL
                        )
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        .overlay {
            if showGlitch {
                GlitchOverlayView {
                    showGlitch = false
                    startMagicCountdown()
                }
            }
        }
        .onAppear {
            print("🎨 [UI] UserProfileView appeared for @\(profile.username)")
            print("🎨 [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
            print("🎨 [UI] Profile pic URL: \(profile.profilePicURL)")
            loadImages()
            // Start Following Counter Magic if a secret offset was captured
            print("🎩 [MAGIC] enabled=\(followingMagic.isEnabled) offset=\(followingMagic.pendingOffset)")
            if followingMagic.isEnabled && followingMagic.pendingOffset > 0 {
                let useFollowers = followingMagic.targetFollowers
                let realCount = useFollowers ? currentProfile.followerCount : currentProfile.followingCount
                if followingMagic.transferEnabled {
                    let deflated = max(0, realCount - followingMagic.pendingOffset)
                    if useFollowers { magicFollowerText  = formatFollowing(deflated) }
                    else            { magicFollowingText = formatFollowing(deflated) }
                    print("🎩 [TRANSFER] Deflated count: \(deflated) (real:\(realCount) offset:\(followingMagic.pendingOffset)) column:\(useFollowers ? "followers" : "following")")
                } else {
                    let inflated = realCount + followingMagic.pendingOffset
                    if useFollowers { magicFollowerText  = formatFollowing(inflated) }
                    else            { magicFollowingText = formatFollowing(inflated) }
                    print("🎩 [MAGIC] Inflated count: \(inflated) (real:\(realCount) offset:\(followingMagic.pendingOffset)) column:\(useFollowers ? "followers" : "following")")
                }
                VolumeButtonMonitor.shared.startMonitoring()
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
            magicFollowingText = nil
            magicFollowerText  = nil
            // Keep monitoring alive when Transfer deflation just finished
            // so own profile can still receive the volume press for phase 2.
            if followingMagic.transferEnabled && followingMagic.transferOffset > 0 {
                print("🎩 [TRANSFER] Keeping monitoring alive for own-profile phase 2")
            } else {
                VolumeButtonMonitor.shared.stopMonitoring()
            }
            followingMagic.clear()

            // Date Force: auto-register on close unless cancelled by tapping profile pic
            if dateForce.isEnabled {
                if dateForceCancelled {
                    print("🎯 [DATE FORCE] Profile @\(currentProfile.username) cancelled — not registered")
                } else {
                    // Don't register the forced reel profile or duplicates
                    let isAlreadyRegistered = dateForce.spectators.contains { $0.username == currentProfile.username }
                    if !isAlreadyRegistered {
                        dateForce.addSpectator(username: currentProfile.username, followingCount: currentProfile.followingCount)
                    }
                }
            }
        }
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
        .onChange(of: volumeMonitor.triggerCount) { _ in
            guard followingMagic.pendingOffset > 0 && !isCountingDown && !showGlitch else { return }
            let delay = followingMagic.triggerDelay
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    guard followingMagic.pendingOffset > 0 && !isCountingDown && !showGlitch else { return }
                    launchGlitchOrCountdown()
                }
            } else {
                launchGlitchOrCountdown()
            }
        }
    }

    // MARK: - Secret number gesture handling

    private func handleGridSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let absDx = abs(dx)
        let absDy = abs(value.translation.height)
        guard absDx > absDy && absDx > 30 else { return }

        let gridWidth = UIScreen.main.bounds.width
        let digit = SecretNumberManager.digit(
            x: value.startLocation.x,
            y: value.startLocation.y,
            gridWidth: gridWidth
        )
        secretManager.addDigit(digit)
        updateFollowingOverride()

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = dx < 0
                ? min(2, selectedTab + 1)
                : max(0, selectedTab - 1)
        }
    }

    // MARK: - Following Counter Magic

    private func formatFollowing(_ count: Int) -> String {
        return "\(count)"
    }

    private func launchGlitchOrCountdown() {
        if followingMagic.glitchEnabled {
            GlitchSoundPlayer.shared.play(style: .electricBuzz)
            showGlitch = true
            // Countdown starts via GlitchOverlayView.onComplete
        } else {
            startMagicCountdown()
        }
    }

    private func startMagicCountdown() {
        guard followingMagic.pendingOffset > 0 else { return }
        isCountingDown = true

        let steps = followingMagic.pendingOffset
        let totalMs = followingMagic.countdownDuration * 1000
        let intervalMs = max(16, totalMs / steps)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let useFollowers = followingMagic.targetFollowers

        // Helper: write count to the correct column
        func setMagicText(_ value: String?) {
            if useFollowers { magicFollowerText  = value }
            else            { magicFollowingText = value }
        }

        if followingMagic.transferEnabled {
            // Transfer illusion: DEFLATE the searched profile (realCount - steps → realCount)
            let realCount = useFollowers ? currentProfile.followerCount : currentProfile.followingCount
            var current = realCount - steps

            countdownTimer = Timer.scheduledTimer(withTimeInterval: Double(intervalMs) / 1000.0, repeats: true) { timer in
                current += 1
                setMagicText(self.formatFollowing(current))

                if current >= realCount {
                    timer.invalidate()
                    self.countdownTimer = nil
                    setMagicText(nil)
                    self.isCountingDown = false
                    self.followingMagic.transferOffset = steps
                    self.followingMagic.clear()
                    // Keep monitoring alive so own profile can receive volume press for phase 2
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    print("🎩 [TRANSFER] Deflation complete — offset \(steps) saved for own profile")
                }
            }
        } else {
            // Classic mode: INFLATE then count down to real count
            let target = useFollowers ? currentProfile.followerCount : currentProfile.followingCount
            var current = target + steps

            countdownTimer = Timer.scheduledTimer(withTimeInterval: Double(intervalMs) / 1000.0, repeats: true) { timer in
                current -= 1
                setMagicText(self.formatFollowing(current))

                if current <= target {
                    timer.invalidate()
                    self.countdownTimer = nil
                    setMagicText(nil)
                    self.isCountingDown = false
                    self.followingMagic.clear()
                    VolumeButtonMonitor.shared.stopMonitoring()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    print("🎩 [MAGIC] Countdown complete — showing real count: \(target)")
                }
            }
        }
    }

    private func updateFollowingOverride() {
        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
        } else {
            followingOverride = secretManager.followingDisplayString(originalCount: currentProfile.followingCount)
        }
    }

    // MARK: - Date Force (El Oráculo Social)

    private func cancelDateForceSpectator() {
        dateForceCancelled = true
        print("🎯 [DATE FORCE] @\(currentProfile.username) marked as cancelled")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func loadImages(from profileToLoad: InstagramProfile? = nil) {
        let targetProfile = profileToLoad ?? currentProfile
        
        print("🖼️ [UI] Starting to load images...")
        print("🖼️ [UI] Loading from profile: @\(targetProfile.username)")
        print("🖼️ [UI] Profile has \(targetProfile.cachedMediaURLs.count) media URLs")
        print("🖼️ [UI] Profile has \(targetProfile.followedBy.count) followers")
        
        Task {
            // Load profile pic
            print("🖼️ [UI] Loading profile pic: \(targetProfile.profilePicURL)")
            if !targetProfile.profilePicURL.isEmpty,
               let url = URL(string: targetProfile.profilePicURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    cachedImages[targetProfile.profilePicURL] = image
                    print("✅ [UI] Profile pic loaded and cached")
                }
            } else {
                print("❌ [UI] Failed to load profile pic")
            }
            
            // Load follower pics
            print("🖼️ [UI] Loading \(targetProfile.followedBy.count) follower pics...")
            for follower in targetProfile.followedBy {
                if let picURL = follower.profilePicURL,
                   !picURL.isEmpty,
                   let url = URL(string: picURL),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        cachedImages[picURL] = image
                    }
                }
            }
            print("✅ [UI] Follower pics loaded")
            
            // Load all thumbnails (posts + reels + tagged + highlight covers) in one pass
            let highlightCoverURLs = targetProfile.cachedHighlights.map { $0.coverImageURL }
            let allURLs = targetProfile.cachedMediaURLs + targetProfile.cachedReelURLs + targetProfile.cachedTaggedURLs + highlightCoverURLs
            print("🖼️ [UI] Loading \(allURLs.count) thumbnails (posts:\(targetProfile.cachedMediaURLs.count) reels:\(targetProfile.cachedReelURLs.count) tagged:\(targetProfile.cachedTaggedURLs.count) highlights:\(highlightCoverURLs.count))...")
            for mediaURL in allURLs {
                guard !mediaURL.isEmpty,
                      let url = URL(string: mediaURL),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { continue }
                
                await MainActor.run {
                    cachedImages[mediaURL] = image
                }
            }
            print("✅ [UI] All thumbnails loaded")
            
            await MainActor.run {
                isLoadingImages = false
            }
        }
    }
    
    // MARK: - Infinite Scroll
    
    private func loadMoreMedia() {
        guard !isLoadingMore, hasMorePages, allMediaURLs.count < maxPhotosOtherProfile else {
            print("📜 [USER] Cannot load more - loading: \(isLoadingMore), hasMore: \(hasMorePages), count: \(allMediaURLs.count)")
            return
        }
        guard !InstagramService.shared.isLocked, !InstagramService.shared.isSessionChallenged else {
            print("🚫 [USER] Load more skipped — locked or challenged")
            return
        }
        
        isLoadingMore = true
        print("📜 [USER] Loading more media for @\(profile.username) (current count: \(allMediaURLs.count))...")
        
        Task {
            do {
                // Fetch next batch
                let (mediaItems, newMaxId) = try await InstagramService.shared.getUserMediaItems(userId: profile.userId, amount: 21, maxId: nextMaxId)
                
                await MainActor.run {
                    // Calculate how many we can add without exceeding limit
                    let remainingSlots = maxPhotosOtherProfile - allMediaURLs.count
                    let itemsToAdd = min(mediaItems.count, remainingSlots)
                    let newItems = Array(mediaItems.prefix(itemsToAdd))
                    for item in newItems { mediaItemsByURL[item.imageURL] = item }
                    let newURLs = newItems.map { $0.imageURL }
                    
                    // Filter to multiples of 3 to avoid UI gaps
                    let totalAfterAdd = allMediaURLs.count + newURLs.count
                    let remainder = totalAfterAdd % 3
                    let urlsToDisplay = remainder == 0 ? newURLs : Array(newURLs.dropLast(remainder))
                    
                    allMediaURLs.append(contentsOf: urlsToDisplay)
                    nextMaxId = newMaxId
                    hasMorePages = (newMaxId != nil) && (allMediaURLs.count < maxPhotosOtherProfile)
                    isLoadingMore = false
                    
                    print("📜 [USER] Loaded \(urlsToDisplay.count) more, total now: \(allMediaURLs.count), hasMore: \(hasMorePages)")
                    
                    // Download images for new URLs
                    downloadImagesForURLs(urlsToDisplay)
                }
            } catch {
                print("❌ [USER] Error loading more: \(error)")
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
            print("📜 [USER] User reached 80% (\(index)/\(allMediaURLs.count)) - loading more...")
            loadMoreMedia()
        }
    }
    
    private func downloadImagesForURLs(_ urls: [String]) {
        Task {
            for url in urls {
                guard !url.isEmpty,
                      let urlObj = URL(string: url),
                      let (data, _) = try? await URLSession.shared.data(from: urlObj),
                      let image = UIImage(data: data) else { continue }
                
                await MainActor.run {
                    cachedImages[url] = image
                }
            }
        }
    }
    
    private func toggleFollow() {
        print("🔘 [UI] toggleFollow() called — isFollowing:\(isFollowing) userId:\(profile.userId)")

        guard !isFollowActionLoading else { return }
        guard !InstagramService.shared.isLocked else {
            print("🚫 [UI] Follow action skipped — lockdown active")
            lastError = .apiError("App is in safety lockdown. Wait a moment and try again.")
            showingConnectionError = true
            return
        }
        
        isFollowActionLoading = true
        print("🔄 [UI] Set loading to true")
        
        Task {
            do {
                let wasFollowing = isFollowing
                let wasRequested = isFollowRequested
                let success: Bool

                if wasFollowing {
                    print("➖ [UI] Unfollowing @\(profile.username)...")
                    success = try await InstagramService.shared.unfollowUser(userId: profile.userId)
                } else if wasRequested {
                    print("🚫 [UI] Canceling follow request for @\(profile.username)...")
                    success = try await InstagramService.shared.unfollowUser(userId: profile.userId)
                } else {
                    print("➕ [UI] Following @\(profile.username)...")
                    success = try await InstagramService.shared.followUser(userId: profile.userId)
                }

                print("📊 [UI] API returned success: \(success)")

                await MainActor.run {
                    if success {
                        if wasFollowing || wasRequested {
                            isFollowing = false
                            isFollowRequested = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            print("✅ [UI] Unfollowed / request canceled")
                        } else {
                            if currentProfile.isPrivate {
                                isFollowRequested = true
                                isFollowing = false
                                print("✅ [UI] Follow request sent (private)")
                            } else {
                                isFollowing = true
                                isFollowRequested = false
                                print("✅ [UI] Now following")
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    } else {
                        print("❌ [UI] Follow action returned false")
                        lastError = .apiError("Follow action failed. Please try again.")
                        showingConnectionError = true
                    }
                    isFollowActionLoading = false
                }
            } catch let error as InstagramError {
                print("❌ [UI] Instagram error toggling follow: \(error)")
                await MainActor.run {
                    isFollowActionLoading = false
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ [UI] Error toggling follow: \(error)")
                await MainActor.run {
                    isFollowActionLoading = false
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }
    
    // MARK: - Refresh inteligente (discreto, solo haptic)
    // Ejecutado al tocar el círculo de la foto de perfil
    private func performIntelligentRefresh() {
        print("🔄 [REFRESH] Intelligent refresh triggered by tap on profile photo")
        
        guard !InstagramService.shared.isLocked else {
            print("🚫 [REFRESH] Intelligent refresh skipped — lockdown active")
            return
        }

        // Haptic feedback (discreto, solo para el mago)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                print("🔍 [REFRESH] Fetching updated profile...")
                
                // Solo obtener info básica del perfil para verificar estado
                guard let updatedProfile = try await InstagramService.shared.getProfileInfo(userId: profile.userId) else {
                    print("❌ [REFRESH] Failed to fetch updated profile")
                    return
                }
                
                await MainActor.run {
                    print("✅ [REFRESH] Profile refreshed successfully")
                    print("📊 [REFRESH] Following: \(updatedProfile.isFollowing), Requested: \(updatedProfile.isFollowRequested)")
                    print("📊 [REFRESH] Updated profile has \(updatedProfile.cachedMediaURLs.count) media URLs")
                    print("📊 [REFRESH] Updated profile has \(updatedProfile.followedBy.count) followers")
                    
                    // Actualizar estados
                    isFollowing = updatedProfile.isFollowing
                    isFollowRequested = updatedProfile.isFollowRequested
                    currentProfile = updatedProfile
                    
                    // Actualizar imágenes solo si ahora tenemos acceso
                    if updatedProfile.isFollowing && !updatedProfile.isFollowRequested {
                        print("✅ [REFRESH] Access granted! Loading photos and followers...")
                        print("🔄 [REFRESH] Clearing cached images...")
                        // Limpiar caché de imágenes antiguas
                        cachedImages = [:]
                        print("🔄 [REFRESH] Loading images from updated profile...")
                        // Cargar imágenes del perfil actualizado
                        loadImages(from: updatedProfile)
                    } else if updatedProfile.isFollowRequested {
                        print("⏳ [REFRESH] Still pending approval, not loading protected data")
                    } else {
                        print("ℹ️ [REFRESH] Not following and no request, maintaining current state")
                    }
                    
                    // Segundo haptic feedback para confirmar que terminó (discreto)
                    let confirmGenerator = UIImpactFeedbackGenerator(style: .rigid)
                    confirmGenerator.impactOccurred()
                }
                
            } catch {
                print("❌ [REFRESH] Error: \(error)")
                // Haptic de error (diferente vibración)
                await MainActor.run {
                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }
}

