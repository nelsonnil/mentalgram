import SwiftUI
import AVKit
import Combine

/// Video player for grid cells - auto-plays, loops.
/// - `fillMode: true`  → resizeAspectFill (zoom+crop, used in grid thumbnails / Explore)
/// - `fillMode: false` → resizeAspect (no crop, letterbox if needed; used in the post feed viewer)
/// - `muted: false` for feed-style playback (with audio) or leave it true for thumbnail-style.
struct GridVideoPlayer: View {
    let videoURL: String
    var muted: Bool = true
    /// When false, the video is never cropped: it scales to fit the container,
    /// showing black bars for videos whose aspect ratio differs from the container.
    var fillMode: Bool = true
    /// Show a poster image as background while the AVPlayer warms up.
    /// Avoids the "black flash" while AVPlayer loads its first frame.
    var posterImage: UIImage? = nil
    @StateObject private var playerManager = VideoPlayerManager()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background — visible as letterbox bars when fillMode is false.
                Color.black

                // Poster shows the cached thumbnail behind the player. When the
                // player hasn't drawn its first frame yet (or fails to load) we
                // still see the photo instead of an empty black rectangle.
                if let poster = posterImage {
                    Image(uiImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: fillMode ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }

                if let player = playerManager.player {
                    AVPlayerFillView(
                        player: player,
                        videoGravity: fillMode ? .resizeAspectFill : .resizeAspect
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else if posterImage == nil {
                    ProgressView().scaleEffect(0.8)
                }
            }
        }
        .onAppear {
            playerManager.setupPlayer(url: videoURL, muted: muted)
        }
        .onDisappear {
            playerManager.cleanup()
        }
    }
}

/// UIViewRepresentable that uses AVPlayerLayer with adaptive video gravity.
struct AVPlayerFillView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> PlayerFillUIView {
        let view = PlayerFillUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: PlayerFillUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

/// UIView with AVPlayerLayer as its layer class
class PlayerFillUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

// MARK: - Single-audio coordinator
// Guarantees only one unmuted AVPlayer produces audio at any given time.
// Both VideoPlayerManager (grid/feed) and DetailVideoPlayerManager (fullscreen)
// register here when they start unmuted playback.
class VideoPlaybackCoordinator {
    static let shared = VideoPlaybackCoordinator()
    private weak var activeUnmutedPlayer: AVPlayer?

    /// Call when an unmuted player starts. Pauses the previous one automatically.
    func activate(_ newPlayer: AVPlayer) {
        if let old = activeUnmutedPlayer, old !== newPlayer {
            old.pause()
        }
        activeUnmutedPlayer = newPlayer
    }

    /// Call when a player is cleaned up so the reference doesn't linger.
    func deactivate(_ player: AVPlayer) {
        if activeUnmutedPlayer === player {
            activeUnmutedPlayer = nil
        }
    }
}

/// Manages AVPlayer lifecycle for grid videos.
/// The gravity (fill vs fit) is owned by GridVideoPlayer and passed to AVPlayerFillView
/// directly — this manager only handles player lifecycle.
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    private var loopObserver: Any?
    private var isMuted = true

    func setupPlayer(url: String, muted: Bool = true) {
        guard let videoURL = URL(string: url) else {
            print("⚠️ [VIDEO] Invalid URL: \(url.prefix(80))")
            return
        }
        self.isMuted = muted

        // iOS requires an active AVAudioSession for AVPlayer to render video
        // frames even when the player is muted. Without this, the first frame
        // never renders and the cell stays black.
        try? AVAudioSession.sharedInstance().setCategory(
            muted ? .ambient : .playback,
            mode: .default,
            options: muted ? [.mixWithOthers] : []
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        let asset = AVURLAsset(url: videoURL)
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = muted

        if !muted { VideoPlaybackCoordinator.shared.activate(player) }

        player.play()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        self.player = player
    }

    func cleanup() {
        if let p = player {
            if !isMuted { VideoPlaybackCoordinator.shared.deactivate(p) }
            p.pause()
        }
        player = nil
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}
