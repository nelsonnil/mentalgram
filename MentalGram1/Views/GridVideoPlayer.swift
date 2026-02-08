import SwiftUI
import AVKit

/// Video player for grid cells - auto-plays and loops silently
struct GridVideoPlayer: View {
    let videoURL: String
    @StateObject private var playerManager = VideoPlayerManager()
    
    var body: some View {
        GeometryReader { geometry in
            if let player = playerManager.player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .disabled(true) // Disable controls
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(.white)
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
