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
    @State private var magicFollowingText: String? = nil
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer? = nil
    @State private var showGlitch = false

    // Date Force ("El Oráculo Social")
    @ObservedObject private var dateForce = DateForceSettings.shared
    @State private var dateForceCancelled = false  // Tap on profile pic = cancel this profile
    
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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (igual que Instagram)
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Username con candado si es privado
                    HStack(spacing: 4) {
                        if profile.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                        }
                        Text(profile.username)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Image(systemName: "bell")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
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
                                                    lineWidth: 2
                                                )
                                                .padding(-2)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 86, height: 86)
                                }
                                
                                // Plus button azul
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
                            .onTapGesture {
                                if dateForce.isEnabled {
                                    cancelDateForceSpectator()
                                } else {
                                    performIntelligentRefresh()
                                }
                            }
                            
                            Spacer(minLength: 8)
                            
                            // Stats (con más espacio entre números)
                            HStack(spacing: UIScreen.main.bounds.width < 400 ? 20 : 40) {
                                UserStatView(number: currentProfile.mediaCount, label: "posts")
                                UserStatView(number: currentProfile.followerCount, label: "followers")
                                UserStatView(number: currentProfile.followingCount, label: "following",
                                             overrideText: magicFollowingText ?? followingOverride)
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
                            
                            if let url = profile.externalUrl, !url.isEmpty {
                                Link(url, destination: URL(string: "https://\(url)")!)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                            }
                            
                            // "@" + Name badge
                            HStack(spacing: 4) {
                                Image(systemName: "at.circle.fill")
                                    .font(.system(size: 12))
                                Text(profile.fullName)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.top, 4)
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
                                mediaURLs: allMediaURLs,
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
                            mediaURLs: allMediaURLs,
                            mediaItemsByURL: mediaItemsByURL,
                            cachedImages: cachedImages,
                            initialIndex: selectedPostIndex,
                            username: currentProfile.username,
                            profileImage: cachedImages[currentProfile.profilePicURL],
                            userId: currentProfile.userId
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
                let inflated = currentProfile.followingCount + followingMagic.pendingOffset
                magicFollowingText = formatFollowing(inflated)
                VolumeButtonMonitor.shared.startMonitoring()
                print("🎩 [MAGIC] Showing inflated following: \(inflated) (real: \(currentProfile.followingCount) + offset: \(followingMagic.pendingOffset))")
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
            VolumeButtonMonitor.shared.stopMonitoring()
            magicFollowingText = nil
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

    /// Always returns a raw integer string so the countdown is visible
    /// even when the real count is in the K/M range (e.g. 7212 not "7.2K").
    private func formatFollowing(_ count: Int) -> String {
        return "\(count)"
    }

    private func launchGlitchOrCountdown() {
        if followingMagic.glitchEnabled {
            showGlitch = true
            // Countdown starts via GlitchOverlayView.onComplete
        } else {
            startMagicCountdown()
        }
    }

    private func startMagicCountdown() {
        guard followingMagic.pendingOffset > 0 else { return }
        isCountingDown = true

        let target = currentProfile.followingCount
        let steps = followingMagic.pendingOffset          // one decrement per step
        let totalMs = followingMagic.countdownDuration * 1000
        let intervalMs = max(16, totalMs / steps)         // ≥60fps, spread over chosen duration
        var current = target + steps

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: Double(intervalMs) / 1000.0, repeats: true) { timer in
            current -= 1
            magicFollowingText = formatFollowing(current)

            if current <= target {
                timer.invalidate()
                countdownTimer = nil
                // Snap to real count and clean up
                magicFollowingText = nil
                isCountingDown = false
                followingMagic.clear()
                VolumeButtonMonitor.shared.stopMonitoring()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                print("🎩 [MAGIC] Countdown complete — showing real following count: \(target)")
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
        print("🔘 [UI] toggleFollow() called")
        print("🔘 [UI] Current isFollowing: \(isFollowing)")
        print("🔘 [UI] Profile userId: \(profile.userId)")
        print("🔘 [UI] Profile username: @\(profile.username)")
        
        guard !isFollowActionLoading else {
            print("⚠️ [UI] Already loading, ignoring tap")
            return
        }
        
        isFollowActionLoading = true
        print("🔄 [UI] Set loading to true")
        
        Task {
            do {
                // OPCIÓN 2: Confiar en estado local (más natural, menos detectable)
                // Estado se verificó al cargar perfil (fresco y correcto)
                // Si algo está mal, Instagram simplemente rechaza el request
                print("🔘 [UI] Using local state for follow action")
                print("📊 [UI] Local state - Following: \(isFollowing), Requested: \(isFollowRequested)")
                
                let success: Bool
                
                if isFollowing {
                    // Ya lo estamos siguiendo, hacer unfollow
                    print("➖ [UI] Unfollowing @\(profile.username) (ID: \(profile.userId))...")
                    success = try await InstagramService.shared.unfollowUser(userId: profile.userId)
                } else if isFollowRequested {
                    // Tiene solicitud pendiente, cancelarla (unfollow)
                    print("🚫 [UI] Canceling follow request for @\(profile.username)...")
                    success = try await InstagramService.shared.unfollowUser(userId: profile.userId)
                } else {
                    // No lo estamos siguiendo NI hay solicitud, hacer follow
                    print("➕ [UI] Following @\(profile.username) (ID: \(profile.userId))...")
                    success = try await InstagramService.shared.followUser(userId: profile.userId)
                }
                
                print("📊 [UI] API returned success: \(success)")
                
                await MainActor.run {
                    if success {
                        if isFollowing {
                            // Hicimos unfollow de un perfil que seguíamos
                            isFollowing = false
                            isFollowRequested = false
                            print("✅ [UI] Unfollowed successfully")
                        } else if isFollowRequested {
                            // Cancelamos una solicitud pendiente
                            isFollowing = false
                            isFollowRequested = false
                            print("✅ [UI] Follow request canceled")
                        } else {
                            // Enviamos un follow nuevo
                            if currentProfile.isPrivate {
                                // Si es privado, el follow crea una solicitud pendiente
                                isFollowRequested = true
                                isFollowing = false
                                print("✅ [UI] Follow request sent (private profile, pending approval)")
                            } else {
                                // Si es público, follow inmediato
                                isFollowing = true
                                isFollowRequested = false
                                print("✅ [UI] Now following (public profile)")
                            }
                        }
                    } else {
                        print("❌ [UI] Follow action failed - API returned false")
                    }
                    isFollowActionLoading = false
                    print("🔄 [UI] Set loading to false")
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
                print("❌ [UI] Error type: \(type(of: error))")
                print("❌ [UI] Error description: \(error.localizedDescription)")
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

private struct UserStatView: View {
    let number: Int
    let label: String
    var overrideText: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(overrideText ?? formatCount(number))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
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
