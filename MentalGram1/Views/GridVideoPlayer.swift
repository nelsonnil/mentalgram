import SwiftUI
import AVKit
import Combine

/// Video player for grid cells - auto-plays, loops silently, fills cell (no black bars)
struct GridVideoPlayer: View {
    let videoURL: String
    @StateObject private var playerManager = VideoPlayerManager()
    
    var body: some View {
        GeometryReader { geometry in
            if let player = playerManager.player {
                // Portrait reels fill the cell like Instagram. Horizontal videos
                // use aspect-fit so they do not look zoomed/cropped.
                AVPlayerFillView(player: player, videoGravity: playerManager.videoGravity)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .onAppear {
            playerManager.setupPlayer(url: videoURL)
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

/// Manages AVPlayer lifecycle for grid videos
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    private var loopObserver: Any?
    
    func setupPlayer(url: String) {
        guard let videoURL = URL(string: url) else { return }
        
        let asset = AVURLAsset(url: videoURL)
        resolveVideoGravity(for: asset)

        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = true // Silent playback
        player.play()
        
        // Loop video when it ends
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
        player?.pause()
        player = nil
        videoGravity = .resizeAspectFill
        
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }

    private func resolveVideoGravity(for asset: AVURLAsset) {
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            guard let self else { return }

            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            guard status == .loaded,
                  let track = asset.tracks(withMediaType: .video).first else {
                return
            }

            let transformedSize = track.naturalSize.applying(track.preferredTransform)
            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)
            let isHorizontal = width > height * 1.05

            DispatchQueue.main.async {
                self.videoGravity = isHorizontal ? .resizeAspect : .resizeAspectFill
                if isHorizontal {
                    print("🎬 [VIDEO] Horizontal reel detected (\(Int(width))x\(Int(height))) — using aspect-fit")
                }
            }
        }
    }
}
