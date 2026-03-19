import SwiftUI
import AVKit
import Combine

// MARK: - Post Detail View (vertical swipe, Instagram Reels style)

struct PostDetailView: View {
    let mediaItems: [InstagramMediaItem]
    let startIndex: Int
    let cachedImages: [String: UIImage]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var likedItems: Set<String> = []
    @State private var savedItems: Set<String> = []

    // Vertical swipe state
    @State private var dragOffset: CGFloat = 0
    /// Decided at the START of each drag: will the next page be the forced reel?
    @State private var isForcedNext: Bool = false
    /// True while the forced reel is the page currently on screen.
    @State private var showingForcedReel: Bool = false

    @ObservedObject private var forceSettings = ForceReelSettings.shared

    // Velocity threshold to commit a swipe even if displacement is small
    private let velocityThreshold: CGFloat = 350
    private let displacementThreshold: CGFloat = 80

    init(
        mediaItems: [InstagramMediaItem],
        startIndex: Int,
        cachedImages: [String: UIImage],
        onClose: @escaping () -> Void
    ) {
        self.mediaItems = mediaItems
        self.startIndex = startIndex
        self.cachedImages = cachedImages
        self.onClose = onClose
        self._currentIndex = State(initialValue: max(0, min(startIndex, mediaItems.count - 1)))
    }

    private var statusBarHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }

    // MARK: - Item helpers

    /// The page currently filling the screen.
    private var currentItem: InstagramMediaItem? {
        if showingForcedReel { return forceSettings.asFakeMediaItem() }
        guard currentIndex < mediaItems.count else { return nil }
        return mediaItems[currentIndex]
    }

    /// The page that will slide up from below during a swipe-up gesture.
    private var peekItem: InstagramMediaItem? {
        if isForcedNext { return forceSettings.asFakeMediaItem() }
        // After showing forced reel, "next" is the real item at currentIndex
        // (forced reel sits between currentIndex-1 and currentIndex conceptually)
        let nextIdx = showingForcedReel ? currentIndex : currentIndex + 1
        return nextIdx < mediaItems.count ? mediaItems[nextIdx] : nil
    }

    /// Resolves the cached thumbnail for an item, handling the forced reel's stable key.
    private func cachedImg(for item: InstagramMediaItem) -> UIImage? {
        if item.id.hasPrefix("forced_reel_") {
            return ExploreManager.shared.cachedImages[ForceReelSettings.localCacheKey]
        }
        return cachedImages[item.imageURL]
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                // ── Peek page: slides up from below while dragging ──────────
                if let peek = peekItem, dragOffset < 0 {
                    PostPageView(
                        item: peek,
                        cachedImage: cachedImg(for: peek),
                        isLiked: likedItems.contains(peek.id),
                        isSaved: savedItems.contains(peek.id),
                        onLike: { toggleLike(peek.id) },
                        onSave: { toggleSave(peek.id) }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Starts just below the screen; follows the drag so both pages move together
                    .offset(y: geo.size.height + dragOffset)
                }

                // ── Current page ─────────────────────────────────────────────
                if let item = currentItem {
                    PostPageView(
                        item: item,
                        cachedImage: cachedImg(for: item),
                        isLiked: likedItems.contains(item.id),
                        isSaved: savedItems.contains(item.id),
                        onLike: { toggleLike(item.id) },
                        onSave: { toggleSave(item.id) }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: dragOffset)
                }

                // ── Navigation bar (always on top) ───────────────────────────
                HStack(spacing: 0) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.leading, 4)
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(.trailing, 16)
                }
                .padding(.top, statusBarHeight)
            }
            .ignoresSafeArea()
            .gesture(swipeGesture(geo: geo))
        }
        .environment(\.colorScheme, .dark)
        .onDisappear {
            if DateForceSettings.shared.isEnabled && DateForceSettings.shared.hasSpectators {
                DateForceSettings.shared.resetSpectators()
                print("🎯 [DATE FORCE] Spectators auto-reset after post closed")
            }
        }
    }

    // MARK: - Vertical drag gesture

    private func swipeGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dy = value.translation.height

                // Only handle upward swipes (negative dy)
                guard dy < 0 else { return }

                // ── Decide target on the very first movement of this drag ────
                if dragOffset == 0 {
                    let startedInBottomHalf = value.startLocation.y > geo.size.height / 2
                    let canForce = forceSettings.isEnabled
                                   && forceSettings.hasReel
                                   && !showingForcedReel   // don't double-trigger

                    isForcedNext = startedInBottomHalf && canForce

                    if isForcedNext {
                        print("🎭 [FORCE] Secret swipe detected — forced reel queued")
                    }
                }

                // Apply rubber-band resistance when there is no next page
                if peekItem == nil {
                    dragOffset = dy * 0.12
                } else {
                    dragOffset = dy
                }
            }
            .onEnded { value in
                let dy       = value.translation.height
                let velocity = value.predictedEndTranslation.height   // negative = fast upward

                let committed = (dy < -displacementThreshold || velocity < -velocityThreshold)
                              && peekItem != nil

                if committed {
                    // Animate both pages off / on screen
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        dragOffset = -geo.size.height
                    }
                    // After animation completes, swap state and snap back to 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        commitSwipeUp()   // updates currentItem
                        dragOffset = 0   // instant — new item is already at y:0 conceptually
                    }
                } else {
                    // Cancel: snap back
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        dragOffset = 0
                    }
                    isForcedNext = false
                }
            }
    }

    /// Called once the transition animation finishes. Updates which item is "current".
    private func commitSwipeUp() {
        if isForcedNext {
            // Secret swipe: reveal the forced reel
            showingForcedReel = true
            print("🎭 [FORCE] Forced reel now on screen")
        } else if showingForcedReel {
            // Was showing forced reel; normal swipe-up moves to the real next
            showingForcedReel = false
            if currentIndex < mediaItems.count - 1 { currentIndex += 1 }
        } else {
            // Normal swipe: advance real index
            if currentIndex < mediaItems.count - 1 { currentIndex += 1 }
        }
        isForcedNext = false
    }

    // MARK: - Actions

    private func toggleLike(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if likedItems.contains(id) { likedItems.remove(id) }
            else { likedItems.insert(id) }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleSave(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if savedItems.contains(id) { savedItems.remove(id) }
            else { savedItems.insert(id) }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Single Post Page
// Layout: media fills full screen, UI overlaid on top, comment bar pinned at bottom.

struct PostPageView: View {
    let item: InstagramMediaItem
    let cachedImage: UIImage?
    let isLiked: Bool
    let isSaved: Bool
    let onLike: () -> Void
    let onSave: () -> Void

    @State private var showHeartAnimation = false
    @ObservedObject private var dateForce = DateForceSettings.shared

    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 34
    }

    private let commentBarHeight: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let totalHeight     = geo.size.height
            let commentBarTotal = commentBarHeight + bottomSafeArea
            let mediaHeight     = totalHeight - commentBarTotal

            VStack(spacing: 0) {

                // ── LAYER 1: Media + overlays (fixed height) ──────────────
                ZStack(alignment: .bottom) {
                    mediaContent
                        .frame(width: geo.size.width, height: mediaHeight)
                        .clipped()
                        .onTapGesture(count: 2) { handleDoubleTap() }
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.system(size: 90))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 10)
                                .opacity(showHeartAnimation ? 1 : 0)
                                .scaleEffect(showHeartAnimation ? 1 : 0.4)
                                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: showHeartAnimation)
                        )

                    // Right-side action bar — anchored 16pt above bottom of media
                    rightActionBar
                        .padding(.trailing, 12)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    // Bottom info overlay — anchored at bottom of media with gradient
                    // Fixed height so it NEVER overflows into the comment bar
                    bottomInfoOverlay
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        )
                }
                .frame(width: geo.size.width, height: mediaHeight)

                // ── LAYER 2: Comment bar — fixed height, always visible ──
                commentBar
                    .frame(width: geo.size.width, height: commentBarTotal)
            }
            .frame(width: geo.size.width, height: totalHeight)
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Media content (scaledToFill — no black bars)

    @ViewBuilder
    private var mediaContent: some View {
        if item.mediaType == .video, let videoURL = item.videoURL {
            DetailVideoPlayer(videoURL: videoURL)
        } else if let image = cachedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            AsyncImage(url: URL(string: item.imageURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView().tint(.white))
                }
            }
        }
    }

    // MARK: - Right action bar (heart, comment, share, send)

    private var rightActionBar: some View {
        VStack(spacing: 22) {
            PostActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: (item.likeCount ?? 0) + (isLiked ? 1 : 0),
                color: isLiked ? .red : .white,
                action: onLike
            )

            PostActionButton(
                icon: "bubble.right",
                count: item.commentCount,
                color: .white,
                action: {}
            )

            PostActionButton(
                icon: "arrow.2.squarepath",
                count: nil,
                color: .white,
                action: {}
            )

            // Send / DM — inverted-triangle style (▽)
            PostActionButton(
                icon: "arrowtriangle.down",
                count: nil,
                color: .white,
                action: {}
            )

            // Options (···)
            Image(systemName: "ellipsis")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)

            // Small thumbnail of the post (bottom-right, like Instagram)
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white, lineWidth: 1.5)
                    )
            }
        }
    }

    // MARK: - Bottom info overlay

    private var bottomInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Username + verified + Follow
            HStack(spacing: 8) {
                // Profile pic — reuse the already-cached thumbnail (no extra API call)
                Group {
                    if let image = cachedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    } else {
                        Circle()
                            .fill(Color(white: 0.35))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                            )
                    }
                }

                // Username
                Text("usuario")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)

                // Verified badge
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2)

                // Follow button
                Text("Follow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    )
            }

            // Forced followers/following stats (Date Force active)
            if dateForce.isEnabled && dateForce.hasSpectators {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text(DateForceSettings.formatExact(dateForce.overrideFollowers))
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                        Text("followers")
                            .font(.system(size: 13))
                    }
                    HStack(spacing: 4) {
                        Text(DateForceSettings.formatExact(dateForce.overrideFollowing))
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                        Text("following")
                            .font(.system(size: 13))
                    }
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
            }

            // Caption
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }

            // Followed by
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(white: 0.4))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white)
                    )
                (Text("Followed by ").font(.system(size: 12)) +
                 Text("oriana_gomez").font(.system(size: 12, weight: .semibold)))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .padding(.trailing, 80) // leave space for right action bar
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Comment bar (dark grey strip below the media, matches Instagram)

    private var commentBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(white: 0.25))

            // Wide dark capsule — no icon, white text, full width minus small margins
            Text("Add a comment...")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Color(white: 0.20))
                .clipShape(Capsule())
                .padding(.horizontal, 6)
                .padding(.vertical, 8)

            Spacer() // absorbs bottom safe area
        }
        .background(Color(white: 0.08)) // very dark grey, not pure black
    }

    // MARK: - Helpers

    private func handleDoubleTap() {
        if !isLiked { onLike() }
        withAnimation(.easeOut(duration: 0.1)) { showHeartAnimation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeIn(duration: 0.2)) { showHeartAnimation = false }
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }
}

// MARK: - Action Button (right side bar)

struct PostActionButton: View {
    let icon: String
    let count: Int?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(color)
                    .shadow(color: .black.opacity(0.55), radius: 3)

                if let count = count, count > 0 {
                    Text(formatCount(count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.55), radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }
}

// MARK: - Detail Video Player (autoplay + sound + tap to pause)

struct DetailVideoPlayer: View {
    let videoURL: String
    @StateObject private var manager = DetailVideoPlayerManager()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player = manager.player {
                    AVPlayerFillView(player: player)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay(ProgressView().tint(.white))
                }

                // Play/Pause indicator (shown briefly when paused)
                if !manager.isPlaying && manager.player != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
            }
            .onTapGesture {
                manager.togglePlayPause()
            }
        }
        .onAppear  { manager.setup(url: videoURL) }
        .onDisappear { manager.cleanup() }
    }
}

/// AVPlayer with sound enabled, loops automatically, supports tap-to-pause
private class DetailVideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    private var loopObserver: Any?

    func setup(url: String) {
        guard let videoURL = URL(string: url) else { return }

        // Allow audio to play even when silent switch is on
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.play()
        isPlaying = true

        // Loop
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player, weak self] _ in
            player?.seek(to: .zero)
            player?.play()
            self?.isPlaying = true
        }

        self.player = player
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func cleanup() {
        player?.pause()
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        player = nil
        isPlaying = false
    }
}
