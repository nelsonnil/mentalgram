import Foundation
import Combine
import UIKit

/// Stores configuration for the "Force Reel" effect.
/// The magician pre-selects a reel from any Instagram profile.
/// During the trick, the secret number input selects a grid position,
/// and opening Explore shows that reel at exactly that position.
class ForceReelSettings: ObservableObject {
    static let shared = ForceReelSettings()

    // MARK: - Persisted settings

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceReel_enabled") }
    }

    /// Thumbnail image URL of the forced reel (used in the Explore grid)
    @Published var thumbnailURL: String {
        didSet { UserDefaults.standard.set(thumbnailURL, forKey: "forceReel_thumbnailURL") }
    }

    /// Video URL (future use — for playing the reel)
    @Published var videoURL: String {
        didSet { UserDefaults.standard.set(videoURL, forKey: "forceReel_videoURL") }
    }

    /// Instagram media ID of the forced reel
    @Published var mediaId: String {
        didSet { UserDefaults.standard.set(mediaId, forKey: "forceReel_mediaId") }
    }

    /// Username of the profile from which the reel was selected
    @Published var sourceUsername: String {
        didSet { UserDefaults.standard.set(sourceUsername, forKey: "forceReel_sourceUsername") }
    }

    // MARK: - Runtime (not persisted)

    /// The target position (1-based) set by the secret number swipe.
    /// Reset to 0 after it has been consumed by the Explore grid.
    var pendingPosition: Int = 0

    // MARK: - Computed

    var hasReel: Bool { !thumbnailURL.isEmpty }

    private init() {
        isEnabled     = UserDefaults.standard.bool(forKey: "forceReel_enabled")
        thumbnailURL  = UserDefaults.standard.string(forKey: "forceReel_thumbnailURL") ?? ""
        videoURL      = UserDefaults.standard.string(forKey: "forceReel_videoURL") ?? ""
        mediaId       = UserDefaults.standard.string(forKey: "forceReel_mediaId") ?? ""
        sourceUsername = UserDefaults.standard.string(forKey: "forceReel_sourceUsername") ?? ""
    }

    // MARK: - Save selected reel

    func selectReel(thumbnailURL: String, videoURL: String, mediaId: String, username: String) {
        self.thumbnailURL  = thumbnailURL
        self.videoURL      = videoURL
        self.mediaId       = mediaId
        self.sourceUsername = username
        print("🎭 [FORCE] Reel selected: mediaId=\(mediaId) from @\(username)")
    }

    func clearReel() {
        thumbnailURL   = ""
        videoURL       = ""
        mediaId        = ""
        sourceUsername = ""
        pendingPosition = 0
        print("🎭 [FORCE] Reel cleared")
    }

    // MARK: - Build a fake InstagramMediaItem for the Explore grid

    /// Creates a placeholder media item representing the forced reel.
    /// It looks identical to any other reel cell in the grid.
    func asFakeMediaItem() -> InstagramMediaItem? {
        guard !thumbnailURL.isEmpty else { return nil }
        return InstagramMediaItem(
            id: "forced_reel_\(mediaId)",
            mediaId: mediaId,
            imageURL: thumbnailURL,
            videoURL: videoURL.isEmpty ? nil : videoURL,
            caption: nil,
            takenAt: nil,
            likeCount: nil,
            commentCount: nil,
            mediaType: .video
        )
    }
}
