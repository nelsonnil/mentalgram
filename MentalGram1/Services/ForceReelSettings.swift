import Foundation
import Combine
import UIKit

/// Stores configuration for the "Force Reel" effect.
/// The magician pre-selects a reel from any Instagram profile.
/// During the trick, the secret number input selects a grid position,
/// and opening Explore shows that reel at exactly that position.
///
/// Both the thumbnail image and the video are saved permanently to
/// Application Support so the reel always works — even if the CDN URLs
/// expire, the original user deletes the post, or the device is offline.
class ForceReelSettings: ObservableObject {
    static let shared = ForceReelSettings()

    // MARK: - Persisted settings (CDN URLs kept as fallback only)

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceReel_enabled") }
    }

    @Published var thumbnailURL: String {
        didSet { UserDefaults.standard.set(thumbnailURL, forKey: "forceReel_thumbnailURL") }
    }

    @Published var videoURL: String {
        didSet { UserDefaults.standard.set(videoURL, forKey: "forceReel_videoURL") }
    }

    @Published var mediaId: String {
        didSet { UserDefaults.standard.set(mediaId, forKey: "forceReel_mediaId") }
    }

    @Published var sourceUsername: String {
        didSet { UserDefaults.standard.set(sourceUsername, forKey: "forceReel_sourceUsername") }
    }

    // MARK: - Local permanent assets

    /// Thumbnail loaded from permanent local storage (never expires).
    @Published private(set) var localThumbnailImage: UIImage?

    /// True when the video has been fully downloaded to local storage.
    @Published private(set) var localVideoReady: Bool = false

    /// True while the video is being downloaded in the background.
    @Published private(set) var isDownloadingVideo: Bool = false

    /// Stable key used in ExploreManager.cachedImages for the forced reel thumbnail.
    static let localCacheKey = "forced_reel_local"

    // MARK: - Runtime (not persisted)

    var pendingPosition: Int = 0

    // MARK: - Computed

    var hasReel: Bool { localThumbnailImage != nil || !thumbnailURL.isEmpty }

    // MARK: - File URLs (Application Support — never cleared by iOS)

    private static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static var localThumbnailFileURL: URL? {
        appSupportDir?.appendingPathComponent("force_reel_thumbnail.jpg")
    }

    private static var localVideoFileURL: URL? {
        appSupportDir?.appendingPathComponent("force_reel_video.mp4")
    }

    // MARK: - Init

    private init() {
        isEnabled      = UserDefaults.standard.bool(forKey: "forceReel_enabled")
        thumbnailURL   = UserDefaults.standard.string(forKey: "forceReel_thumbnailURL") ?? ""
        videoURL       = UserDefaults.standard.string(forKey: "forceReel_videoURL") ?? ""
        mediaId        = UserDefaults.standard.string(forKey: "forceReel_mediaId") ?? ""
        sourceUsername = UserDefaults.standard.string(forKey: "forceReel_sourceUsername") ?? ""

        // Load thumbnail from disk
        localThumbnailImage = Self.loadLocalThumbnail()
        if localThumbnailImage != nil {
            print("🎭 [FORCE] Local thumbnail loaded from disk")
        }

        // Check whether video was previously downloaded
        if let videoURL = Self.localVideoFileURL,
           FileManager.default.fileExists(atPath: videoURL.path) {
            localVideoReady = true
            print("🎭 [FORCE] Local video found on disk")
        }
    }

    // MARK: - Select reel

    /// Saves the reel configuration and immediately starts downloading
    /// the thumbnail and video to permanent local storage.
    func selectReel(thumbnailURL: String, videoURL: String, mediaId: String, username: String) {
        self.thumbnailURL   = thumbnailURL
        self.videoURL       = videoURL
        self.mediaId        = mediaId
        self.sourceUsername = username

        // Reset local asset state so UI reflects that a fresh download is starting
        localVideoReady = false
        print("🎭 [FORCE] Reel selected: mediaId=\(mediaId) from @\(username)")

        Task {
            await ensureAppSupportDir()
            async let thumb: Void = downloadAndSaveThumbnail(from: thumbnailURL)
            async let video: Void = downloadAndSaveVideo(from: videoURL)
            _ = await (thumb, video)
        }
    }

    func clearReel() {
        thumbnailURL    = ""
        videoURL        = ""
        mediaId         = ""
        sourceUsername  = ""
        pendingPosition = 0
        localThumbnailImage = nil
        localVideoReady     = false
        isDownloadingVideo  = false
        deleteLocalAssets()
        print("🎭 [FORCE] Reel cleared")
    }

    // MARK: - Build fake media item

    /// Creates a placeholder media item for the Explore grid.
    /// Uses stable local keys so the image/video are always available
    /// regardless of CDN URL expiry.
    func asFakeMediaItem() -> InstagramMediaItem? {
        guard hasReel else { return nil }

        // Prefer local file:// URL for video (never expires, works offline)
        let effectiveVideoURL: String?
        if localVideoReady, let localURL = Self.localVideoFileURL {
            effectiveVideoURL = localURL.absoluteString
        } else if !videoURL.isEmpty {
            effectiveVideoURL = videoURL   // CDN fallback
        } else {
            effectiveVideoURL = nil
        }

        return InstagramMediaItem(
            id: "forced_reel_\(mediaId)",
            mediaId: mediaId,
            imageURL: Self.localCacheKey,   // stable key → always in cachedImages
            videoURL: effectiveVideoURL,
            caption: nil,
            takenAt: nil,
            likeCount: nil,
            commentCount: nil,
            mediaType: .video
        )
    }

    // MARK: - Download helpers

    private func ensureAppSupportDir() async {
        guard let dir = Self.appSupportDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func downloadAndSaveThumbnail(from urlString: String) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92),
              let fileURL = Self.localThumbnailFileURL else {
            print("⚠️ [FORCE] Could not download thumbnail for permanent storage")
            return
        }
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            await MainActor.run { self.localThumbnailImage = image }
            print("✅ [FORCE] Thumbnail saved permanently (\(jpegData.count / 1024) KB)")
        } catch {
            print("⚠️ [FORCE] Failed to save thumbnail: \(error)")
        }
    }

    private func downloadAndSaveVideo(from urlString: String) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let destURL = Self.localVideoFileURL else {
            print("⚠️ [FORCE] No video URL — skipping video download")
            return
        }

        await MainActor.run { self.isDownloadingVideo = true }
        print("🎬 [FORCE] Downloading video for permanent storage...")

        do {
            // URLSession.download writes directly to a temp file — memory efficient
            let (tempURL, response) = try await URLSession.shared.download(from: url)

            let mb = (response.expectedContentLength > 0)
                ? "\(response.expectedContentLength / 1_000_000) MB"
                : "size unknown"
            print("🎬 [FORCE] Video downloaded (\(mb)), moving to Application Support...")

            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)

            await MainActor.run {
                self.isDownloadingVideo = false
                self.localVideoReady    = true
            }
            print("✅ [FORCE] Video saved permanently — will always play offline")
        } catch {
            await MainActor.run { self.isDownloadingVideo = false }
            print("⚠️ [FORCE] Video download failed: \(error.localizedDescription)")
        }
    }

    private static func loadLocalThumbnail() -> UIImage? {
        guard let fileURL = localThumbnailFileURL,
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func deleteLocalAssets() {
        [Self.localThumbnailFileURL, Self.localVideoFileURL]
            .compactMap { $0 }
            .forEach { try? FileManager.default.removeItem(at: $0) }
        print("🗑️ [FORCE] Local thumbnail and video deleted")
    }
}
