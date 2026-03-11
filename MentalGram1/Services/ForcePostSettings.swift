import Foundation
import Combine
import UIKit

/// Stores configuration for the "Force Post" trick.
/// The magician pre-selects a specific post from any Instagram user.
/// During performance, that post is hidden from the grid but present in
/// the post viewer feed. A UIScrollView deceleration intercept ensures
/// the scroll always stops on the forced post.
class ForcePostSettings: ObservableObject {
    static let shared = ForcePostSettings()

    // MARK: - Persisted settings

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forcePost_enabled") }
    }

    @Published var targetUserId: String {
        didSet { UserDefaults.standard.set(targetUserId, forKey: "forcePost_userId") }
    }

    @Published var targetUsername: String {
        didSet { UserDefaults.standard.set(targetUsername, forKey: "forcePost_username") }
    }

    @Published var forcedMediaId: String {
        didSet { UserDefaults.standard.set(forcedMediaId, forKey: "forcePost_mediaId") }
    }

    @Published var forcedMediaURL: String {
        didSet { UserDefaults.standard.set(forcedMediaURL, forKey: "forcePost_mediaURL") }
    }

    // MARK: - Codable media item (caption, likes, date, etc.)

    @Published var forcedMediaItem: InstagramMediaItem? {
        didSet {
            if let item = forcedMediaItem, let data = try? JSONEncoder().encode(item) {
                UserDefaults.standard.set(data, forKey: "forcePost_mediaItem")
            } else {
                UserDefaults.standard.removeObject(forKey: "forcePost_mediaItem")
            }
        }
    }

    // MARK: - Local thumbnail (Application Support — never cleared by iOS)

    @Published private(set) var localThumbnailImage: UIImage?

    // MARK: - Computed

    var hasPost: Bool { localThumbnailImage != nil || !forcedMediaURL.isEmpty }

    // MARK: - File paths

    private static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static var thumbnailDir: URL? {
        appSupportDir?.appendingPathComponent("ForcePost")
    }

    private static var localThumbnailFileURL: URL? {
        thumbnailDir?.appendingPathComponent("thumbnail.jpg")
    }

    // MARK: - Init

    private init() {
        isEnabled       = UserDefaults.standard.bool(forKey: "forcePost_enabled")
        targetUserId    = UserDefaults.standard.string(forKey: "forcePost_userId") ?? ""
        targetUsername  = UserDefaults.standard.string(forKey: "forcePost_username") ?? ""
        forcedMediaId   = UserDefaults.standard.string(forKey: "forcePost_mediaId") ?? ""
        forcedMediaURL  = UserDefaults.standard.string(forKey: "forcePost_mediaURL") ?? ""

        if let data = UserDefaults.standard.data(forKey: "forcePost_mediaItem"),
           let item = try? JSONDecoder().decode(InstagramMediaItem.self, from: data) {
            forcedMediaItem = item
        }

        localThumbnailImage = Self.loadLocalThumbnail()
        if localThumbnailImage != nil {
            print("🎯 [FORCE POST] Local thumbnail loaded from disk")
        }
    }

    // MARK: - Select post

    func selectPost(item: InstagramMediaItem, username: String, userId: String) {
        self.targetUserId   = userId
        self.targetUsername  = username
        self.forcedMediaId   = item.mediaId
        self.forcedMediaURL  = item.imageURL
        self.forcedMediaItem = item
        print("🎯 [FORCE POST] Post selected: mediaId=\(item.mediaId) from @\(username)")

        Task {
            await ensureDir()
            await downloadAndSaveThumbnail(from: item.imageURL)
        }
    }

    func clearPost() {
        targetUserId    = ""
        targetUsername  = ""
        forcedMediaId   = ""
        forcedMediaURL  = ""
        forcedMediaItem = nil
        localThumbnailImage = nil
        deleteLocalAssets()
        print("🎯 [FORCE POST] Post cleared")
    }

    // MARK: - Download helpers

    private func ensureDir() async {
        guard let dir = Self.thumbnailDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func downloadAndSaveThumbnail(from urlString: String) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92),
              let fileURL = Self.localThumbnailFileURL else {
            print("⚠️ [FORCE POST] Could not download thumbnail")
            return
        }
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            await MainActor.run { self.localThumbnailImage = image }
            print("✅ [FORCE POST] Thumbnail saved (\(jpegData.count / 1024) KB)")
        } catch {
            print("⚠️ [FORCE POST] Failed to save thumbnail: \(error)")
        }
    }

    private static func loadLocalThumbnail() -> UIImage? {
        guard let fileURL = localThumbnailFileURL,
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func deleteLocalAssets() {
        if let fileURL = Self.localThumbnailFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        print("🗑️ [FORCE POST] Local thumbnail deleted")
    }
}
