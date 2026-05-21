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
    /// Separate metadata map for tagged posts. InstagramProfile does not persist tagged
    /// items, so we hold them here and pass them to the tagged viewer. Without this, the
    /// viewer would receive the posts-only map and show empty/mismatched captions & dates.
    @State private var taggedMediaItemsByURL: [String: InstagramMediaItem] = [:]
    @State private var nextMaxId: String? = nil
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var paginationRetryScheduled = false
    @State private var profileOpenedAt: Date = Date()
    private let maxPhotosOtherProfile = 300 // Enough depth for natural browsing/Force Post presentation.

    // Single fullScreenCover controlled by an enum — avoids SwiftUI bugs when
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

    // Convenience aliases kept so the rest of the code compiles without changes
    private var showingPostViewer: Bool { if case .posts = activeViewer { return true }; return false }
    private var selectedPostIndex: Int {
        if case .posts(let i) = activeViewer { return i }; return 0
    }
    private var selectedReelIndex: Int {
        if case .reels(let i) = activeViewer { return i }; return 0
    }
    private var selectedTaggedIndex: Int {
        if case .tagged(let i) = activeViewer { return i }; return 0
    }

    // Lazy tab loading (reels/tagged are deferred for visited profiles)
    @State private var reelsLoaded = false
    @State private var taggedLoaded = false
    @State private var isLoadingReels = false
    @State private var isLoadingTagged = false

    // Secret number input
    @ObservedObject private var secretManager = SecretNumberManager.shared
    @State private var followingOverride: String? = nil

    // Following Counter Magic
    @ObservedObject private var followingMagic = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor = VolumeButtonMonitor.shared
    @State private var magicFollowingText: String? = nil   // overrides "following" column
    @State private var magicFollowerText: String?  = nil   // overrides "followers" column
    @State private var digitFollowerPreviewText: String? = nil
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer? = nil
    @State private var showGlitch = false

    // Date Force ("El Oráculo Social")
    @ObservedObject private var dateForce = DateForceSettings.shared
    @State private var dateForceCancelled = false  // Tap on profile pic = cancel this profile

    // Force Post
    @ObservedObject private var forcePost = ForcePostSettings.shared

    // Budget indicator (reactive — triggers re-render when actionsThisHour changes)
    @ObservedObject private var instagram = InstagramService.shared
    
    init(profile: InstagramProfile, onClose: @escaping () -> Void) {
        self.profile = profile
        self.onClose = onClose
        self._isFollowing = State(initialValue: profile.isFollowing)
        self._isFollowRequested = State(initialValue: profile.isFollowRequested)
        self._currentProfile = State(initialValue: profile)
        if !profile.cachedMediaItems.isEmpty {
            var seenMediaIds = Set<String>()
            let uniqueURLs = profile.cachedMediaItems.compactMap { item -> String? in
                let key = item.mediaId.isEmpty ? item.imageURL : item.mediaId
                guard seenMediaIds.insert(key).inserted else { return nil }
                return item.imageURL
            }
            self._allMediaURLs = State(initialValue: uniqueURLs)
        } else {
            var seenURLs = Set<String>()
            self._allMediaURLs = State(initialValue: profile.cachedMediaURLs.filter { seenURLs.insert($0).inserted })
        }
        // Start from the cursor returned during getProfileInfo so the first
        // pagination call fetches page 2 directly, without re-loading page 1.
        self._nextMaxId = State(initialValue: profile.cachedNextMaxId)
        self._hasMorePages = State(initialValue: true)
        var initialItems: [String: InstagramMediaItem] = [:]
        for item in profile.cachedMediaItems { initialItems[item.imageURL] = item }
        self._mediaItemsByURL = State(initialValue: initialItems)
    }

    // MARK: - Force Post computed helpers

    /// The active forced post entry for the profile currently being viewed.
    private var activeForceEntry: ForcedPostEntry? {
        guard forcePost.isEnabled else { return nil }
        return forcePost.entry(forUserId: currentProfile.userId, orUsername: currentProfile.username)
    }

    private var isForcePostTarget: Bool { activeForceEntry != nil }

    private var forcePostActiveURL: String? {
        activeForceEntry?.mediaURL
    }

    private var forcePostActiveMediaId: String? {
        activeForceEntry?.mediaId
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
    /// which is stable and embedded in the URL path.
    private func urlMatchesForced(_ url: String) -> Bool {
        guard let entry = activeForceEntry else { return false }
        let forced  = entry.mediaURL
        let mediaId = entry.mediaId
        if url == forced { return true }
        if !mediaId.isEmpty && (url.contains(mediaId) || forced.contains(mediaId)) {
            return url.contains(mediaId)
        }
        guard let u1 = URL(string: url), let u2 = URL(string: forced) else { return false }
        return u1.path == u2.path
    }

    /// Post viewer URLs with the forced post inserted at the middle
    private var postViewerURLs: [String] {
        guard let entry = activeForceEntry else { return allMediaURLs }
        var urls = allMediaURLs.filter { !urlMatchesForced($0) }
        let insertAt = min(urls.count / 2, urls.count)
        urls.insert(entry.mediaURL, at: insertAt)
        return urls
    }

    /// Media items dict enriched with the forced post's metadata
    private var postViewerItems: [String: InstagramMediaItem] {
        guard let entry = activeForceEntry, let item = entry.mediaItem else { return mediaItemsByURL }
        var items = mediaItemsByURL
        items[entry.mediaURL] = item
        return items
    }

    /// Cached images enriched with the forced post's thumbnail
    private var postViewerCachedImages: [String: UIImage] {
        guard let entry = activeForceEntry,
              let img = forcePost.thumbnail(forUserId: entry.userId) else { return cachedImages }
        var images = cachedImages
        images[entry.mediaURL] = img
        return images
    }

    /// Maps a grid index to the correct post viewer index (accounting for the inserted forced post)
    private func mappedPostViewerIndex(_ gridIndex: Int) -> Int {
        guard isForcePostTarget else { return gridIndex }
        let filteredURLs = gridURLsForDisplay
        let insertAt = min(filteredURLs.count / 2, filteredURLs.count)
        return gridIndex >= insertAt ? gridIndex + 1 : gridIndex
    }

    /// Thumbnail of the active forced post, for passing to the scroll interceptor.
    private var forcePostThumbnail: UIImage? {
        guard let entry = activeForceEntry else { return nil }
        return forcePost.thumbnail(forUserId: entry.userId)
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
                            
                            Spacer(minLength: 8)

                            // Columna derecha: nombre encima de los stats
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.fullName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.black)
                                    .lineLimit(1)

                                HStack(spacing: 0) {
                                    StatView(number: currentProfile.mediaCount, label: String(localized: "ig.stat.posts"))
                                        .frame(maxWidth: .infinity)
                                    StatView(number: currentProfile.followerCount, label: String(localized: "ig.stat.followers"),
                                             overrideText: magicFollowerText ?? digitFollowerPreviewText)
                                        .frame(maxWidth: .infinity)
                                    StatView(number: currentProfile.followingCount, label: String(localized: "ig.stat.following"),
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
                                        Text("ig.following_btn")
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
                                    Text("ig.follow_requested")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(Color(uiColor: .systemGray5))
                                        .foregroundColor(.primary)
                                        .cornerRadius(8)
                                } else {
                                    // Not following - show "Follow" in blue
                                    Text("ig.follow")
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
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 16))
                                        .foregroundColor(.primary)
                                        .frame(width: 32, height: 32)
                                        .background(Color(uiColor: .systemGray5))
                                        .cornerRadius(8)
                                    // Red dot: only when API budget is critically low.
                                    if instagram.checkRateLimit().remaining < 8 {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .overlay(Circle().stroke(Color(uiColor: .systemGray5), lineWidth: 1.5))
                                            .offset(x: 3, y: -3)
                                    }
                                }
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

                    // Private & not following → show lock wall (no tabs)
                    // Public or following → show tabs + grid as normal
                    if currentProfile.isPrivate && !isFollowing {
                        privateAccountEmptyState
                    } else {
                        // Tabs
                        HStack(spacing: 0) {
                            TabButton(icon: "square.grid.3x3", activeAsset: "instagram_grid_active", inactiveAsset: "instagram_grid_inactive", isSelected: selectedTab == 0) {
                                selectedTab = 0
                                secretManager.reset()
                                followingOverride = nil
                                digitFollowerPreviewText = nil
                            }
                            TabButton(icon: "play.rectangle", activeAsset: "instagram_reels_active", inactiveAsset: "instagram_reels_inactive", isSelected: selectedTab == 1) {
                                selectedTab = 1
                                secretManager.reset()
                                followingOverride = nil
                                digitFollowerPreviewText = nil
                                fetchReelsIfNeeded()
                            }
                            TabButton(icon: "person.crop.square", activeAsset: "instagram_tagged_active", inactiveAsset: "instagram_tagged_inactive", isSelected: selectedTab == 2) {
                                selectedTab = 2
                                secretManager.reset()
                                followingOverride = nil
                                digitFollowerPreviewText = nil
                                fetchTaggedIfNeeded()
                            }
                        }
                        .frame(height: 44)

                        // Tab content
                        Group {
                            switch selectedTab {
                            case 0:
                                PhotosGridView(
                                    mediaURLs: gridURLsForDisplay,
                                    cachedImages: cachedImages,
                                    onMediaAppear: loadMoreIfNeeded,
                                    onTapIndex: { index in
                                        activeViewer = .posts(index: index)
                                    }
                                )
                            case 1:
                                if isLoadingReels {
                                    VStack { Spacer(); ProgressView(); Spacer() }
                                        .frame(minHeight: 200)
                                } else {
                                    ReelsGridView(
                                        reelURLs: currentProfile.cachedReelURLs,
                                        cachedImages: cachedImages,
                                    reelItems: currentProfile.cachedReelItems,
                                    onTapIndex: { index in
                                        activeViewer = .reels(index: index)
                                    }
                                    )
                                }
                            case 2:
                                if isLoadingTagged {
                                    VStack { Spacer(); ProgressView(); Spacer() }
                                        .frame(minHeight: 200)
                                } else if currentProfile.cachedTaggedURLs.isEmpty {
                                    TaggedEmptyStateView()
                                } else {
                                    PhotosGridView(
                                        mediaURLs: currentProfile.cachedTaggedURLs,
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
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                                .onEnded { value in handleGridSwipe(value) }
                        )
                        .fullScreenCover(item: $activeViewer) { sheet in
                            switch sheet {
                            case .posts(let index):
                                PostScrollView(
                                    mediaURLs: postViewerURLs,
                                    mediaItemsByURL: postViewerItems,
                                    cachedImages: postViewerCachedImages,
                                    initialIndex: mappedPostViewerIndex(index),
                                    username: currentProfile.username,
                                    profileImage: cachedImages[currentProfile.profilePicURL],
                                    userId: currentProfile.userId,
                                    forcePostURL: forcePostActiveURL,
                                    forcePostMediaId: forcePostActiveMediaId,
                                    forcedThumbnail: forcePostThumbnail
                                )
                            case .reels(let index):
                                let reelMap = Dictionary(uniqueKeysWithValues: currentProfile.cachedReelItems.map { ($0.imageURL, $0) })
                                PostScrollView(
                                    mediaURLs: currentProfile.cachedReelURLs,
                                    mediaItemsByURL: reelMap,
                                    cachedImages: cachedImages,
                                    initialIndex: index,
                                    username: currentProfile.username,
                                    profileImage: cachedImages[currentProfile.profilePicURL],
                                    userId: currentProfile.userId
                                )
                            case .tagged(let index):
                                PostScrollView(
                                    mediaURLs: currentProfile.cachedTaggedURLs,
                                    mediaItemsByURL: taggedMediaItemsByURL,
                                    cachedImages: cachedImages,
                                    initialIndex: index,
                                    username: currentProfile.username,
                                    profileImage: cachedImages[currentProfile.profilePicURL],
                                    userId: currentProfile.userId
                                )
                            }
                        }
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
        // ── Progressive: parent updated the profile after presentation ─────────
        // ExploreView presents `UserProfileView` early with a header-only
        // snapshot (via `.visitedProfileHeaderReady`). When `getProfileInfo`
        // finishes in the background, the parent reassigns `searchedProfile`
        // with the full profile. SwiftUI does NOT call init again because
        // `.id(profile.userId)` is unchanged, so we must reconcile `currentProfile`
        // ourselves to keep the grid, counters, etc. in sync.
        //
        // We key the observation on `cachedAt` because `InstagramProfile` is
        // not `Equatable` (would force every nested model to conform). Every
        // reassignment in ExploreView builds a profile with a fresh `Date()`,
        // so this triggers reliably.
        .onChange(of: profile.cachedAt) { _ in
            let newProfile = profile
            // Only adopt fields that bring fresh data — never overwrite already
            // loaded posts with an empty array, etc.
            var merged = currentProfile
            if currentProfile.username.isEmpty, !newProfile.username.isEmpty {
                merged = newProfile
            } else {
                // Field-by-field merge: prefer non-empty new values.
                merged = InstagramProfile(
                    userId: newProfile.userId,
                    username: newProfile.username.isEmpty ? currentProfile.username : newProfile.username,
                    fullName: newProfile.fullName.isEmpty ? currentProfile.fullName : newProfile.fullName,
                    biography: newProfile.biography.isEmpty ? currentProfile.biography : newProfile.biography,
                    externalUrl: newProfile.externalUrl ?? currentProfile.externalUrl,
                    profilePicURL: newProfile.profilePicURL.isEmpty ? currentProfile.profilePicURL : newProfile.profilePicURL,
                    isVerified: newProfile.isVerified || currentProfile.isVerified,
                    isPrivate: newProfile.isPrivate,
                    followerCount: newProfile.followerCount > 0 ? newProfile.followerCount : currentProfile.followerCount,
                    followingCount: newProfile.followingCount > 0 ? newProfile.followingCount : currentProfile.followingCount,
                    mediaCount: newProfile.mediaCount > 0 ? newProfile.mediaCount : currentProfile.mediaCount,
                    followedBy: newProfile.followedBy.isEmpty ? currentProfile.followedBy : newProfile.followedBy,
                    isFollowing: newProfile.isFollowing,
                    isFollowRequested: newProfile.isFollowRequested,
                    cachedAt: newProfile.cachedAt,
                    cachedMediaURLs: newProfile.cachedMediaURLs.isEmpty ? currentProfile.cachedMediaURLs : newProfile.cachedMediaURLs,
                    cachedReelURLs: newProfile.cachedReelURLs.isEmpty ? currentProfile.cachedReelURLs : newProfile.cachedReelURLs,
                    cachedTaggedURLs: newProfile.cachedTaggedURLs.isEmpty ? currentProfile.cachedTaggedURLs : newProfile.cachedTaggedURLs,
                    cachedHighlights: newProfile.cachedHighlights.isEmpty ? currentProfile.cachedHighlights : newProfile.cachedHighlights,
                    cachedMediaItems: newProfile.cachedMediaItems.isEmpty ? currentProfile.cachedMediaItems : newProfile.cachedMediaItems,
                    cachedReelItems: newProfile.cachedReelItems.isEmpty ? currentProfile.cachedReelItems : newProfile.cachedReelItems,
                    cachedNextMaxId: newProfile.cachedNextMaxId ?? currentProfile.cachedNextMaxId
                )
            }
            currentProfile = merged

            // Refresh the grid state if the parent brought new posts.
            if !newProfile.cachedMediaURLs.isEmpty,
               newProfile.cachedMediaURLs != allMediaURLs {
                allMediaURLs = merged.cachedMediaURLs
                for item in merged.cachedMediaItems { mediaItemsByURL[item.imageURL] = item }
                if nextMaxId == nil { nextMaxId = merged.cachedNextMaxId }
                loadImages()
            }
            print("⚡ [UI] UserProfileView synced with parent update for @\(merged.username)")
        }
        // ── Progressive: posts arrived while UI is already on screen ─────────
        .onReceive(NotificationCenter.default.publisher(for: .visitedProfileMediaReady)) { note in
            guard let notifUid = note.userInfo?["userId"] as? String,
                  notifUid == currentProfile.userId,
                  let items = note.userInfo?["mediaItems"] as? [InstagramMediaItem],
                  !items.isEmpty else { return }
            let cursor = note.userInfo?["nextMaxId"] as? String
            let urls = items.map { $0.imageURL }
            let updated = InstagramProfile(
                userId: currentProfile.userId,
                username: currentProfile.username,
                fullName: currentProfile.fullName,
                biography: currentProfile.biography,
                externalUrl: currentProfile.externalUrl,
                profilePicURL: currentProfile.profilePicURL,
                isVerified: currentProfile.isVerified,
                isPrivate: currentProfile.isPrivate,
                followerCount: currentProfile.followerCount,
                followingCount: currentProfile.followingCount,
                mediaCount: currentProfile.mediaCount > 0 ? currentProfile.mediaCount : urls.count,
                followedBy: currentProfile.followedBy,
                isFollowing: currentProfile.isFollowing,
                isFollowRequested: currentProfile.isFollowRequested,
                cachedAt: currentProfile.cachedAt,
                cachedMediaURLs: urls,
                cachedReelURLs: currentProfile.cachedReelURLs,
                cachedTaggedURLs: currentProfile.cachedTaggedURLs,
                cachedHighlights: currentProfile.cachedHighlights,
                cachedMediaItems: items,
                cachedReelItems: currentProfile.cachedReelItems,
                cachedNextMaxId: cursor ?? currentProfile.cachedNextMaxId
            )
            currentProfile = updated
            allMediaURLs = urls
            for item in items { mediaItemsByURL[item.imageURL] = item }
            if nextMaxId == nil { nextMaxId = cursor }
            print("⚡ [UI] Progressive visited posts painted (\(urls.count) items) for @\(currentProfile.username)")
            loadImages()
        }
        // ── Progressive: "Followed by..." row arrived ────────────────────────
        .onReceive(NotificationCenter.default.publisher(for: .visitedProfileFollowedByReady)) { note in
            guard let notifUid = note.userInfo?["userId"] as? String,
                  notifUid == currentProfile.userId,
                  let followers = note.userInfo?["followedBy"] as? [InstagramFollower],
                  !followers.isEmpty else { return }
            let updated = InstagramProfile(
                userId: currentProfile.userId,
                username: currentProfile.username,
                fullName: currentProfile.fullName,
                biography: currentProfile.biography,
                externalUrl: currentProfile.externalUrl,
                profilePicURL: currentProfile.profilePicURL,
                isVerified: currentProfile.isVerified,
                isPrivate: currentProfile.isPrivate,
                followerCount: currentProfile.followerCount,
                followingCount: currentProfile.followingCount,
                mediaCount: currentProfile.mediaCount,
                followedBy: followers,
                isFollowing: currentProfile.isFollowing,
                isFollowRequested: currentProfile.isFollowRequested,
                cachedAt: currentProfile.cachedAt,
                cachedMediaURLs: currentProfile.cachedMediaURLs,
                cachedReelURLs: currentProfile.cachedReelURLs,
                cachedTaggedURLs: currentProfile.cachedTaggedURLs,
                cachedHighlights: currentProfile.cachedHighlights,
                cachedMediaItems: currentProfile.cachedMediaItems,
                cachedReelItems: currentProfile.cachedReelItems,
                cachedNextMaxId: currentProfile.cachedNextMaxId
            )
            currentProfile = updated
            print("⚡ [UI] Progressive visited followedBy painted (\(followers.count)) for @\(currentProfile.username)")
            // Preload follower thumbnails so the row doesn't ghost
            Task { @MainActor in
                for follower in followers {
                    guard let urlStr = follower.profilePicURL, !urlStr.isEmpty,
                          cachedImages[urlStr] == nil,
                          let url = URL(string: urlStr) else { continue }
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: data) {
                        cachedImages[urlStr] = img
                        VisitedProfileCacheService.shared.saveImage(img, forURL: urlStr)
                    }
                }
            }
        }
        .onAppear {
            profileOpenedAt = Date()
            print("🎨 [UI] UserProfileView appeared for @\(profile.username)")
            print("🎨 [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
            print("🎨 [UI] Profile pic URL: \(profile.profilePicURL)")
            logVisibleCountState(reason: "profile appear")
            loadImages()
            // Start Following Counter Magic if a secret offset was captured
            print("🎩 [MAGIC] enabled=\(followingMagic.isEnabled) offset=\(followingMagic.pendingOffset)")
            if followingMagic.isEnabled && followingMagic.pendingOffset > 0 {
                let useFollowers = followingMagic.targetFollowers
                let realCount = useFollowers ? currentProfile.followerCount : currentProfile.followingCount
                let rawOffset = followingMagic.pendingOffset
                let offset = followingMagic.effectiveOffset(for: realCount, rawOffset: rawOffset)
                let offsetMode = followingMagic.offsetMode(for: realCount)
                let inflated = realCount + offset
                if useFollowers { magicFollowerText  = formatFollowing(inflated) }
                else            { magicFollowingText = formatFollowing(inflated) }
                LogManager.shared.info(
                    "Counter visited-deflate prepared @\(currentProfile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) input:\(rawOffset) effectiveOffset:\(offset) mode:\(offsetMode) start:\(inflated) end:\(realCount)",
                    category: .profile
                )
                logVisibleCountState(reason: "magic override applied")
                if followingMagic.transferEnabled {
                    print("🎩 [TRANSFER] Pre-inflated to \(formatFollowing(inflated)) (real:\(formatFollowing(realCount)) +\(offset)) — deflate to real on volume press")
                } else {
                    print("🎩 [MAGIC] Showing inflated: \(formatFollowing(inflated)) (real:\(formatFollowing(realCount)) +\(offset))")
                }
                VolumeButtonMonitor.shared.startMonitoring()
            }
        }
        .onDisappear {
            // If deflation was still running when the user navigated away, it was
            // interrupted — clear any stale transferOffset so the own-profile phase 2
            // does not fire with an invalid (or leftover) offset.
            if isCountingDown {
                countdownTimer?.invalidate()
                countdownTimer = nil
                followingMagic.transferOffset = 0
                VolumeButtonMonitor.shared.stopMonitoring()
                print("🎩 [MAGIC] Deflation interrupted on navigate-away — transferOffset cleared")
            } else {
                countdownTimer?.invalidate()
                countdownTimer = nil
            }
            magicFollowingText = nil
            magicFollowerText  = nil
            digitFollowerPreviewText = nil
            // Keep monitoring alive when Transfer deflation fully finished
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
                        dateForce.addSpectator(username: currentProfile.username, userId: currentProfile.userId, profilePicURL: currentProfile.profilePicURL, followingCount: currentProfile.followingCount, followerCount: currentProfile.followerCount)
                    }
                }
            }
        }
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
            logVisibleCountState(reason: "digit buffer changed")
        }
        .onChange(of: volumeMonitor.upCount) { _ in
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
        // Require a clearly horizontal gesture: horizontal travel must be
        // at least 2.5× the vertical drift AND at least 60 pt in total.
        guard absDx > absDy * 2.5 && absDx > 60 else { return }

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

    private func logVisibleCountState(reason: String) {
        LogManager.shared.info(
            "Visible counts (\(reason)) @\(currentProfile.username) real followers:\(currentProfile.followerCount) following:\(currentProfile.followingCount) magicFollower:\(magicFollowerText ?? "nil") digitFollowerPreview:\(digitFollowerPreviewText ?? "nil") magicFollowing:\(magicFollowingText ?? "nil") followingOverride:\(followingOverride ?? "nil") pendingOffset:\(followingMagic.pendingOffset) transferOffset:\(followingMagic.transferOffset)",
            category: .profile
        )
    }

    // MARK: - Following Counter Magic

    /// Formats a count for the magic countdown display.
    /// For counts >= 10K, uses K notation (e.g. "206K") so the countdown looks natural.
    /// For counts < 10K, shows the raw integer (e.g. "1025").
    private func formatFollowing(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000
            return value == value.rounded() ? String(format: "%.0fM", value) : String(format: "%.1fM", value)
        } else if count >= 10_000 {
            let value = Double(count) / 1_000
            return value == value.rounded() ? String(format: "%.0fK", value) : String(format: "%.1fK", value)
        }
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

        let rawOffset = followingMagic.pendingOffset
        let useFollowers = followingMagic.targetFollowers
        let realCount = useFollowers ? currentProfile.followerCount : currentProfile.followingCount
        let offset = followingMagic.effectiveOffset(for: realCount, rawOffset: rawOffset)
        let offsetMode = followingMagic.offsetMode(for: realCount)
        // Step size scales with offset so the animation always finishes in countdownDuration.
        // For K-mode the minimum step is 100 (= 0.1 K per visual update, smooth appearance).
        let minStep = realCount >= 10_000 ? 100 : 1
        let stepSize = max(minStep, offset / 200)
        let visibleSteps = max(1, offset / stepSize)
        let totalMs = followingMagic.countdownDuration * 1000
        let intervalMs = max(16, totalMs / max(1, visibleSteps))

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        func setMagicText(_ value: String?) {
            if useFollowers { magicFollowerText  = value }
            else            { magicFollowingText = value }
        }

        if followingMagic.transferEnabled {
            var current = realCount + offset
            LogManager.shared.info(
                "Counter visited-deflate started @\(currentProfile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) input:\(rawOffset) effectiveOffset:\(offset) mode:\(offsetMode) start:\(current) end:\(realCount)",
                category: .profile
            )

            countdownTimer = Timer.scheduledTimer(withTimeInterval: Double(intervalMs) / 1000.0, repeats: true) { timer in
                current -= stepSize
                setMagicText(self.formatFollowing(max(current, realCount)))

                if current <= realCount {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.isCountingDown = false
                    setMagicText(nil)
                    self.followingMagic.transferOffset = offset
                    self.followingMagic.clear()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    LogManager.shared.info(
                        "Counter visited-deflate completed @\(self.currentProfile.username) target:\(useFollowers ? "followers" : "following") real:\(realCount) input:\(rawOffset) effectiveOffset:\(offset) mode:\(offsetMode)",
                        category: .profile
                    )
                    print("🎩 [TRANSFER] Deflation complete — back to real: \(self.formatFollowing(realCount)), offset \(offset) saved for phase 2")
                }
            }
        } else {
            let target = realCount
            var current = target + offset

            countdownTimer = Timer.scheduledTimer(withTimeInterval: Double(intervalMs) / 1000.0, repeats: true) { timer in
                current -= stepSize
                let displayCurrent = max(current, realCount)
                setMagicText(self.formatFollowing(displayCurrent))

                if displayCurrent <= target {
                    timer.invalidate()
                    self.countdownTimer = nil
                    setMagicText(nil)
                    self.isCountingDown = false
                    self.followingMagic.clear()
                    VolumeButtonMonitor.shared.stopMonitoring()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    print("🎩 [MAGIC] Countdown complete — showing real count: \(self.formatFollowing(target))")
                }
            }
        }
    }

    private func updateFollowingOverride() {
        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
            digitFollowerPreviewText = nil
        } else if followingMagic.targetFollowers {
            followingOverride = nil
            digitFollowerPreviewText = secretManager.followingDisplayString(originalCount: currentProfile.followerCount)
        } else {
            digitFollowerPreviewText = nil
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
               let image = VisitedProfileCacheService.shared.loadImage(forURL: targetProfile.profilePicURL) {
                await MainActor.run {
                    cachedImages[targetProfile.profilePicURL] = image
                    print("✅ [UI] Profile pic loaded from visited cache")
                }
            } else if !targetProfile.profilePicURL.isEmpty,
                      let url = URL(string: targetProfile.profilePicURL),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) {
                VisitedProfileCacheService.shared.saveImage(image, forURL: targetProfile.profilePicURL)
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
                guard let picURL = follower.profilePicURL, !picURL.isEmpty else { continue }
                if let image = VisitedProfileCacheService.shared.loadImage(forURL: picURL) {
                    await MainActor.run {
                        cachedImages[picURL] = image
                    }
                } else if let url = URL(string: picURL),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let image = UIImage(data: data) {
                    VisitedProfileCacheService.shared.saveImage(image, forURL: picURL)
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
                guard !mediaURL.isEmpty else { continue }
                if let image = VisitedProfileCacheService.shared.loadImage(forURL: mediaURL) {
                    await MainActor.run {
                        cachedImages[mediaURL] = image
                    }
                } else if let url = URL(string: mediaURL),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let image = UIImage(data: data) {
                    VisitedProfileCacheService.shared.saveImage(image, forURL: mediaURL)
                    await MainActor.run {
                        cachedImages[mediaURL] = image
                    }
                }
            }
            print("✅ [UI] All thumbnails loaded")
            
            await MainActor.run {
                isLoadingImages = false
            }
        }
    }
    
    // MARK: - Private account empty state (matches real Instagram layout)

    private var privateAccountEmptyState: some View {
        VStack(spacing: 0) {
            // Thin separator that replaces the tabs line
            Rectangle()
                .fill(Color(white: 0.88))
                .frame(height: 1)

            VStack(spacing: 12) {
                // Lock circle — matches Instagram's private account icon
                Image(systemName: "lock.circle")
                    .font(.system(size: 62, weight: .light))
                    .foregroundColor(.black)
                    .padding(.top, 36)

                Text("ig.private.title")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)

                Text("ig.private.subtitle")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                // Follow button — same style as Instagram's blue CTA
                Button(action: toggleFollow) {
                    Group {
                        if isFollowActionLoading {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        } else if isFollowRequested {
                            Text("ig.follow_requested")
                        } else {
                            Text("ig.follow")
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(isFollowRequested ? Color(white: 0.7) : Color(hex: "0095F6"))
                    .cornerRadius(8)
                }
                .disabled(isFollowActionLoading || isFollowRequested)
                .padding(.horizontal, 40)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity)
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
        guard !UploadManager.shared.isActive else {
            print("🛡️ [USER] Pagination skipped — upload active/paused")
            LogManager.shared.warning("SAFETY BLOCK — visited profile pagination skipped: upload active", category: .general)
            return
        }
        let safetyDecision = InstagramSafetyGate.shared.decision(for: .visitedProfilePagination)
        guard safetyDecision.allowed else {
            print("🛡️ [USER] Pagination skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — visited profile pagination: \(safetyDecision.reason)", category: .general)
            return
        }
        InstagramSafetyGate.shared.record(.visitedProfilePagination)
        
        isLoadingMore = true
        let cursorInfo = nextMaxId != nil ? "cursor=\(nextMaxId!.prefix(12))…" : "cursor=nil(p1)"
        print("📜 [USER] Loading more media for @\(profile.username) (count:\(allMediaURLs.count) \(cursorInfo))...")
        LogManager.shared.debug("Pagination start — @\(profile.username) count:\(allMediaURLs.count) \(cursorInfo)", category: .profile)

        let existingURLsBeforeRequest = Set(allMediaURLs)
        let existingMediaIdsBeforeRequest = Set(mediaItemsByURL.values.map { $0.mediaId })
        
        Task {
            do {
                // Fetch next batch
                let requestedMaxId = nextMaxId
                var (mediaItems, newMaxId) = try await InstagramService.shared.getUserMediaItems(userId: profile.userId, amount: 36, maxId: requestedMaxId)

                // First pagination after opening a searched profile may rediscover page 1
                // because getProfileInfo does not persist the feed cursor. If everything
                // returned is already visible, use the cursor for the real next page.
                // CRITICAL: this internal 2nd call must respect the SafetyGate and add
                // a human-like delay (3-4s), otherwise we produce a 3-GETs-in-5s burst
                // to the same userId — the exact pattern Instagram fingerprints as bot.
                if requestedMaxId == nil, let discoveredMaxId = newMaxId {
                    let hasFreshItem = mediaItems.contains { item in
                        if !item.mediaId.isEmpty, existingMediaIdsBeforeRequest.contains(item.mediaId) { return false }
                        return !existingURLsBeforeRequest.contains(item.imageURL)
                    }
                    if !hasFreshItem {
                        let nextPageDecision = InstagramSafetyGate.shared.decision(for: .visitedProfilePagination)
                        if nextPageDecision.allowed {
                            print("📜 [USER] First pagination returned cached first page — fetching next cursor after pause")
                            // Human-like 1.5–2.0s pause. cachedNextMaxId now prevents this
                            // path for most users; this only fires for very short accounts
                            // or stale cache without a saved cursor.
                            let pauseNs = UInt64.random(in: 1_500_000_000...2_000_000_000)
                            try? await Task.sleep(nanoseconds: pauseNs)
                            InstagramSafetyGate.shared.record(.visitedProfilePagination)
                            let nextPage = try await InstagramService.shared.getUserMediaItems(userId: profile.userId, amount: 36, maxId: discoveredMaxId)
                            mediaItems = nextPage.0
                            newMaxId = nextPage.1
                        } else {
                            print("🛡️ [USER] Skipping internal nextPage — SafetyGate (\(nextPageDecision.reason), wait \(nextPageDecision.waitSeconds)s)")
                            LogManager.shared.warning("SAFETY BLOCK — internal nextPage skipped: \(nextPageDecision.reason)", category: .general)
                        }
                    }
                }
                
                await MainActor.run {
                    // Deduplicate by stable mediaId first. CDN image URLs can change
                    // between pages/sessions and make the same post look "new".
                    let existingURLs = Set(allMediaURLs)
                    let existingMediaIds = Set(mediaItemsByURL.values.map { $0.mediaId })
                    var seenIncomingIds = Set<String>()
                    let freshItems = mediaItems.filter { item in
                        let key = item.mediaId.isEmpty ? item.imageURL : item.mediaId
                        guard seenIncomingIds.insert(key).inserted else { return false }
                        if !item.mediaId.isEmpty, existingMediaIds.contains(item.mediaId) { return false }
                        return !existingURLs.contains(item.imageURL)
                    }

                    for item in freshItems { mediaItemsByURL[item.imageURL] = item }

                    // Respect limit
                    let remainingSlots = maxPhotosOtherProfile - allMediaURLs.count
                    let urlsToAppend = Array(freshItems.prefix(remainingSlots).map { $0.imageURL })

                    // Filter to multiples of 3 to avoid UI gaps
                    let totalAfterAdd = allMediaURLs.count + urlsToAppend.count
                    let remainder = totalAfterAdd % 3
                    let urlsToDisplay = remainder == 0 ? urlsToAppend : Array(urlsToAppend.dropLast(remainder))

                    allMediaURLs.append(contentsOf: urlsToDisplay)
                    nextMaxId = newMaxId
                    hasMorePages = (newMaxId != nil) && (newMaxId != requestedMaxId) && (allMediaURLs.count < maxPhotosOtherProfile)
                    isLoadingMore = false
                    currentProfile.cachedMediaURLs = allMediaURLs
                    currentProfile.cachedMediaItems = allMediaURLs.compactMap { mediaItemsByURL[$0] }
                    currentProfile.cachedAt = Date()
                    VisitedProfileCacheService.shared.saveProfile(currentProfile)

                    print("📜 [USER] Loaded \(urlsToDisplay.count) new (skipped \(mediaItems.count - freshItems.count) dupes), total: \(allMediaURLs.count), hasMore: \(hasMorePages)")
                    
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
        guard !isLoadingMore else { return }
        guard let index = allMediaURLs.firstIndex(of: currentURL) else { return }

        // TIME GUARD: on large phones (iPhone 15 Pro Max) the entire initial 12-item
        // load is visible without scrolling, so every item's .onAppear fires immediately
        // on render — including the threshold item. This produces an unwanted
        // /feed/user/ call on every profile open even without user interaction.
        // Require the profile to have been open for at least 5 seconds before
        // pagination fires. Once count > 12 (first page already loaded) this guard
        // is lifted so subsequent pages load normally while the user scrolls.
        let sinceOpen = Date().timeIntervalSince(profileOpenedAt)
        guard allMediaURLs.count > 12 || sinceOpen > 5.0 else {
            print("⏳ [USER] Pagination suppressed — \(allMediaURLs.count) items / \(String(format: "%.1f", sinceOpen))s since open")
            return
        }

        let threshold = max(1, Int(Double(allMediaURLs.count) * 0.85))

        if index >= threshold {
            print("📜 [USER] Pagination trigger: index \(index)/\(allMediaURLs.count) — loading more…")
            let decision = InstagramSafetyGate.shared.decision(for: .visitedProfilePagination)
            if decision.allowed {
                loadMoreMedia()
            } else if !paginationRetryScheduled {
                paginationRetryScheduled = true
                let wait = max(1, decision.waitSeconds)
                print("⏳ [USER] Pagination gated (\(decision.reason), \(wait)s) — will retry")
                let openedSnapshot = profileOpenedAt
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(wait) + 0.3) {
                    paginationRetryScheduled = false
                    guard !isLoadingMore, hasMorePages else { return }
                    // Re-apply time guard in retry path — if SafetyGate cleared quickly
                    // (e.g. 2-3s) the user might still be in the initial-render phase.
                    let sinceOpenNow = Date().timeIntervalSince(openedSnapshot)
                    guard allMediaURLs.count > 12 || sinceOpenNow > 5.0 else {
                        print("⏳ [USER] Pagination retry suppressed — still within 5s time guard")
                        return
                    }
                    loadMoreMedia()
                }
            }
        }
    }
    
    // MARK: - Lazy Tab Loading (reels / tagged)

    /// Fetches reels for this profile the first time the reels tab is tapped.
    private func fetchReelsIfNeeded() {
        guard !reelsLoaded, !isLoadingReels else { return }
        guard !UploadManager.shared.isActive else {
            print("🛡️ [USER] Reels fetch skipped — upload active/paused")
            LogManager.shared.warning("SAFETY BLOCK — visited profile reels skipped: upload active", category: .general)
            return
        }
        // If reels were already loaded as part of getProfileInfo (own profile or
        // any future change), skip the extra request.
        if !currentProfile.cachedReelURLs.isEmpty {
            reelsLoaded = true
            return
        }
        isLoadingReels = true
        Task {
            do {
                let reels = try await InstagramService.shared.getUserReels(userId: currentProfile.userId, amount: 18)
                let reelURLs = reels.map { $0.imageURL }
                await MainActor.run {
                    currentProfile.cachedReelURLs = reelURLs
                    currentProfile.cachedReelItems = reels
                    reelsLoaded = true
                    isLoadingReels = false
                    downloadImagesForURLs(reelURLs)
                    LogManager.shared.info("Lazy reels loaded — \(reels.count) reels for @\(currentProfile.username)", category: .profile)
                }
            } catch {
                await MainActor.run {
                    reelsLoaded = true  // don't retry on every tap
                    isLoadingReels = false
                    LogManager.shared.warning("Lazy reels fetch failed for @\(currentProfile.username): \(error.localizedDescription)", category: .profile)
                }
            }
        }
    }

    /// Fetches tagged posts for this profile the first time the tagged tab is tapped.
    private func fetchTaggedIfNeeded() {
        guard !taggedLoaded, !isLoadingTagged else { return }
        guard !UploadManager.shared.isActive else {
            print("🛡️ [USER] Tagged fetch skipped — upload active/paused")
            LogManager.shared.warning("SAFETY BLOCK — visited profile tagged skipped: upload active", category: .general)
            return
        }
        if !currentProfile.cachedTaggedURLs.isEmpty {
            taggedLoaded = true
            return
        }
        isLoadingTagged = true
        Task {
            do {
                let tagged = try await InstagramService.shared.getUserTagged(userId: currentProfile.userId, amount: 18)
                let taggedURLs = tagged.map { $0.imageURL }
                await MainActor.run {
                    currentProfile.cachedTaggedURLs = taggedURLs
                    // Store full metadata for the tagged viewer (captions, dates, mediaId).
                    for item in tagged { taggedMediaItemsByURL[item.imageURL] = item }
                    taggedLoaded = true
                    isLoadingTagged = false
                    downloadImagesForURLs(taggedURLs)
                    LogManager.shared.info("Lazy tagged loaded — \(tagged.count) posts for @\(currentProfile.username)", category: .profile)
                }
            } catch {
                await MainActor.run {
                    taggedLoaded = true  // don't retry on every tap
                    isLoadingTagged = false
                    LogManager.shared.warning("Lazy tagged fetch failed for @\(currentProfile.username): \(error.localizedDescription)", category: .profile)
                }
            }
        }
    }

    private func downloadImagesForURLs(_ urls: [String]) {
        Task {
            for url in urls {
                guard !url.isEmpty else { continue }
                if let image = VisitedProfileCacheService.shared.loadImage(forURL: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                    }
                    continue
                }
                guard let urlObj = URL(string: url),
                      let (data, _) = try? await URLSession.shared.data(from: urlObj),
                      let image = UIImage(data: data) else { continue }
                VisitedProfileCacheService.shared.saveImage(image, forURL: url)
                
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
        guard !UploadManager.shared.isActive else {
            print("🛡️ [REFRESH] Intelligent refresh skipped — upload active/paused")
            LogManager.shared.warning("SAFETY BLOCK — visited profile refresh skipped: upload active", category: .general)
            return
        }
        let safetyDecision = InstagramSafetyGate.shared.decision(for: .visitedProfileRefresh)
        guard safetyDecision.allowed else {
            print("🛡️ [REFRESH] Intelligent refresh skipped — \(safetyDecision.reason) (\(safetyDecision.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — visited profile refresh: \(safetyDecision.reason)", category: .general)
            return
        }
        InstagramSafetyGate.shared.record(.visitedProfileRefresh)

        // Haptic feedback (discreto, solo para el mago)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                print("🔍 [REFRESH] Fetching updated profile...")
                
                // Solo obtener info básica del perfil para verificar estado
                guard let updatedProfile = try await InstagramService.shared.getProfileInfo(
                    userId: profile.userId,
                    usernameHint: profile.username,
                    fullNameHint: profile.fullName,
                    profilePicURLHint: profile.profilePicURL,
                    isVerifiedHint: profile.isVerified
                ) else {
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
                    VisitedProfileCacheService.shared.saveProfile(updatedProfile)
                    
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

