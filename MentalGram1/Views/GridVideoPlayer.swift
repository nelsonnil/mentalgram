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
                // Use AVPlayerLayer directly to get resizeAspectFill (no black bars)
                AVPlayerFillView(player: player)
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

/// UIViewRepresentable that uses AVPlayerLayer with .resizeAspectFill
/// This eliminates black bars on videos (zooms to fill, crops excess)
struct AVPlayerFillView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerFillUIView {
        let view = PlayerFillUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill // KEY: Fill, no black bars
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: PlayerFillUIView, context: Context) {
        uiView.playerLayer.player = player
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
    private var loopObserver: Any?
    
    func setupPlayer(url: String) {
        guard let videoURL = URL(string: url) else { return }
        
        let player = AVPlayer(url: videoURL)
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
        
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}
