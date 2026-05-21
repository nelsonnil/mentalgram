import Foundation
import Combine
import UIKit

// MARK: - ForcedPostEntry

/// A single forced post entry — one per target profile.
struct ForcedPostEntry: Codable, Identifiable {
    var userId: String
    var username: String
    var mediaId: String
    var mediaURL: String
    var mediaItem: InstagramMediaItem?

    var id: String { userId }
}

// MARK: - ForcePostSettings

/// Stores configuration for the "Force Post" trick.
/// Supports multiple entries — one forced post per target profile.
/// When visiting any configured profile, the scroll lands on that profile's forced post.
class ForcePostSettings: ObservableObject {
    static let shared = ForcePostSettings()

    // MARK: - Persisted settings

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forcePost_enabled") }
    }

    /// All active forced post entries (one per profile).
    @Published var entries: [ForcedPostEntry] = [] {
        didSet { persistEntries() }
    }

    /// Thumbnail images keyed by userId.
    @Published var thumbnailImages: [String: UIImage] = [:]

    // MARK: - Backward-compatible helpers (first entry)

    var hasPost: Bool { !entries.isEmpty }

    // MARK: - Lookup

    func entry(forUserId userId: String) -> ForcedPostEntry? {
        entries.first { $0.userId == userId }
    }

    func entry(forUsername username: String) -> ForcedPostEntry? {
        entries.first { $0.username.lowercased() == username.lowercased() }
    }

    func entry(forUserId userId: String, orUsername username: String) -> ForcedPostEntry? {
        entry(forUserId: userId) ?? entry(forUsername: username)
    }

    func thumbnail(forUserId userId: String) -> UIImage? {
        thumbnailImages[userId]
    }

    // MARK: - Init

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "forcePost_enabled")
        entries   = Self.loadEntries()

        // Migrate from old single-slot format if needed
        if entries.isEmpty {
            migrateFromLegacy()
        }

        // Load cached thumbnails from disk
        for entry in entries {
            if let img = Self.loadLocalThumbnail(for: entry.userId) {
                thumbnailImages[entry.userId] = img
            }
        }
    }

    // MARK: - Select / clear

    func selectPost(item: InstagramMediaItem, username: String, userId: String) {
        var entry = ForcedPostEntry(
            userId: userId,
            username: username,
            mediaId: item.mediaId,
            mediaURL: item.imageURL,
            mediaItem: item
        )
        _ = entry  // suppress warning

        if let idx = entries.firstIndex(where: { $0.userId == userId }) {
            entries[idx] = ForcedPostEntry(
                userId: userId, username: username,
                mediaId: item.mediaId, mediaURL: item.imageURL, mediaItem: item
            )
        } else {
            entries.append(ForcedPostEntry(
                userId: userId, username: username,
                mediaId: item.mediaId, mediaURL: item.imageURL, mediaItem: item
            ))
        }

        print("🎯 [FORCE POST] Post selected for @\(username): mediaId=\(item.mediaId)")

        Task {
            await ensureDir(for: userId)
            await downloadAndSaveThumbnail(from: item.imageURL, userId: userId)
        }
    }

    func clearEntry(userId: String) {
        entries.removeAll { $0.userId == userId }
        thumbnailImages.removeValue(forKey: userId)
        deleteLocalAssets(for: userId)
        print("🎯 [FORCE POST] Entry cleared for userId=\(userId)")
    }

    /// Legacy: clears the first (and historically only) entry.
    func clearPost() {
        guard let first = entries.first else { return }
        clearEntry(userId: first.userId)
    }

    func clearAll() {
        for entry in entries { deleteLocalAssets(for: entry.userId) }
        entries.removeAll()
        thumbnailImages.removeAll()
        print("🎯 [FORCE POST] All entries cleared")
    }

    // MARK: - Persistence

    private static let entriesKey = "forcePost_entries_v2"

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.entriesKey)
    }

    private static func loadEntries() -> [ForcedPostEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([ForcedPostEntry].self, from: data) else { return [] }
        return decoded
    }

    // MARK: - Legacy migration (single-slot → multi-entry)

    private func migrateFromLegacy() {
        let ud = UserDefaults.standard
        guard let mediaId = ud.string(forKey: "forcePost_mediaId"), !mediaId.isEmpty else { return }

        let userId   = ud.string(forKey: "forcePost_userId")   ?? "legacy_0"
        let username = ud.string(forKey: "forcePost_username") ?? ""
        let mediaURL = ud.string(forKey: "forcePost_mediaURL") ?? ""

        var mediaItem: InstagramMediaItem?
        if let data = ud.data(forKey: "forcePost_mediaItem"),
           let item = try? JSONDecoder().decode(InstagramMediaItem.self, from: data) {
            mediaItem = item
        }

        let legacyEntry = ForcedPostEntry(
            userId: userId, username: username,
            mediaId: mediaId, mediaURL: mediaURL, mediaItem: mediaItem
        )
        entries = [legacyEntry]

        // Migrate thumbnail file
        if let oldPath = Self.legacyThumbnailURL(),
           let newPath = Self.localThumbnailFileURL(for: userId),
           FileManager.default.fileExists(atPath: oldPath.path) {
            try? FileManager.default.createDirectory(
                at: newPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: oldPath, to: newPath)
        }

        // Remove old keys
        ["forcePost_userId", "forcePost_username", "forcePost_mediaId",
         "forcePost_mediaURL", "forcePost_mediaItem"].forEach { ud.removeObject(forKey: $0) }

        print("🎯 [FORCE POST] Migrated legacy single post to multi-entry format")
    }

    // MARK: - File paths

    private static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static func entryDir(for userId: String) -> URL? {
        appSupportDir?.appendingPathComponent("ForcePost/\(userId)")
    }

    static func localThumbnailFileURL(for userId: String) -> URL? {
        entryDir(for: userId)?.appendingPathComponent("thumbnail.jpg")
    }

    /// Legacy single-slot thumbnail path.
    private static func legacyThumbnailURL() -> URL? {
        appSupportDir?.appendingPathComponent("ForcePost/thumbnail.jpg")
    }

    // MARK: - Download helpers

    private func ensureDir(for userId: String) async {
        guard let dir = Self.entryDir(for: userId) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func downloadAndSaveThumbnail(from urlString: String, userId: String) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92),
              let fileURL = Self.localThumbnailFileURL(for: userId) else {
            print("⚠️ [FORCE POST] Could not download thumbnail for \(userId)")
            return
        }
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            await MainActor.run { self.thumbnailImages[userId] = image }
            print("✅ [FORCE POST] Thumbnail saved for \(userId) (\(jpegData.count / 1024) KB)")
        } catch {
            print("⚠️ [FORCE POST] Failed to save thumbnail for \(userId): \(error)")
        }
    }

    private static func loadLocalThumbnail(for userId: String) -> UIImage? {
        guard let fileURL = localThumbnailFileURL(for: userId),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func deleteLocalAssets(for userId: String) {
        if let dir = Self.entryDir(for: userId) {
            try? FileManager.default.removeItem(at: dir)
        }
        print("🗑️ [FORCE POST] Assets deleted for \(userId)")
    }
}
