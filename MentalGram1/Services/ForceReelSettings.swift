import Foundation
import Combine
import UIKit

/// Data for a single forced reel slot.
struct ForceReelSlot: Codable, Identifiable {
    var id: Int  // 0, 1, or 2
    var thumbnailURL: String = ""
    var videoURL: String = ""
    var mediaId: String = ""
    var sourceUsername: String = ""
    var likeCount: Int?
    var commentCount: Int?
    var caption: String?

    var hasReel: Bool { !mediaId.isEmpty }

    var localCacheKey: String { "forced_reel_local_\(id)" }

    func asFakeMediaItem(localVideoReady: Bool) -> InstagramMediaItem? {
        guard hasReel else { return nil }

        let effectiveVideoURL: String?
        if localVideoReady, let localURL = Self.localVideoFileURL(for: id) {
            effectiveVideoURL = localURL.absoluteString
        } else if !videoURL.isEmpty {
            effectiveVideoURL = videoURL
        } else {
            effectiveVideoURL = nil
        }

        return InstagramMediaItem(
            id: "forced_reel_\(id)_\(mediaId)",
            mediaId: mediaId,
            imageURL: localCacheKey,
            videoURL: effectiveVideoURL,
            caption: caption,
            takenAt: nil,
            likeCount: likeCount,
            commentCount: commentCount,
            mediaType: .video,
            ownerUsername: sourceUsername.isEmpty ? nil : sourceUsername
        )
    }

    // MARK: - File paths

    static func localThumbnailFileURL(for index: Int) -> URL? {
        appSupportDir?.appendingPathComponent("force_reel_thumbnail_\(index).jpg")
    }

    static func localVideoFileURL(for index: Int) -> URL? {
        appSupportDir?.appendingPathComponent("force_reel_video_\(index).mp4")
    }

    private static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

// MARK: - ForceReelSettings (manages up to 3 slots)

class ForceReelSettings: ObservableObject {
    static let shared = ForceReelSettings()
    static let maxSlots = 3

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceReel_enabled") }
    }

    @Published var slots: [ForceReelSlot] = [] {
        didSet { persistSlots() }
    }

    /// Thumbnail images loaded from disk, keyed by slot index.
    @Published var thumbnailImages: [Int: UIImage] = [:]

    /// Which slots have their video downloaded locally.
    @Published var videoReady: [Int: Bool] = [:]

    /// Which slots are currently downloading video.
    @Published var downloadingVideo: [Int: Bool] = [:]

    // MARK: - Runtime

    var pendingPosition: Int = 0

    // MARK: - Backward-compatible computed properties

    /// Legacy: kept for code that only checks "is there at least one reel?"
    var hasReel: Bool { slots.contains(where: { $0.hasReel }) }

    /// Legacy single-slot cache key (slot 0).
    static let localCacheKey = "forced_reel_local_0"

    var filledSlotCount: Int { slots.filter(\.hasReel).count }

    // MARK: - Init

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "forceReel_enabled")
        slots = Self.loadSlots()

        // Migrate from single-slot format if needed
        if slots.isEmpty {
            migrateFromLegacy()
        }

        // Load thumbnails and check video status
        for slot in slots where slot.hasReel {
            if let img = Self.loadLocalThumbnail(for: slot.id) {
                thumbnailImages[slot.id] = img
            }
            if let videoURL = ForceReelSlot.localVideoFileURL(for: slot.id),
               FileManager.default.fileExists(atPath: videoURL.path) {
                videoReady[slot.id] = true
            }
        }
    }

    // MARK: - Slot management

    func selectReel(slotIndex: Int, thumbnailURL: String, videoURL: String, mediaId: String,
                    username: String, likeCount: Int? = nil, commentCount: Int? = nil, caption: String? = nil) {
        let slot = ForceReelSlot(
            id: slotIndex,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            mediaId: mediaId,
            sourceUsername: username,
            likeCount: likeCount,
            commentCount: commentCount,
            caption: caption
        )

        if let existingIdx = slots.firstIndex(where: { $0.id == slotIndex }) {
            slots[existingIdx] = slot
        } else {
            slots.append(slot)
            slots.sort { $0.id < $1.id }
        }

        videoReady[slotIndex] = false
        print("🎭 [FORCE] Reel selected in slot \(slotIndex): mediaId=\(mediaId) from @\(username)")

        Task {
            await ensureAppSupportDir()
            async let thumb: Void = downloadAndSaveThumbnail(from: thumbnailURL, slotIndex: slotIndex)
            async let video: Void = downloadAndSaveVideo(from: videoURL, slotIndex: slotIndex)
            _ = await (thumb, video)
        }
    }

    func clearSlot(_ index: Int) {
        slots.removeAll { $0.id == index }
        thumbnailImages.removeValue(forKey: index)
        videoReady.removeValue(forKey: index)
        downloadingVideo.removeValue(forKey: index)
        deleteLocalAssets(for: index)
        print("🎭 [FORCE] Slot \(index) cleared")
        compactSlots()
    }

    /// Renumbers remaining slots to fill any gaps (0, 1, 2… sequentially).
    /// Renames local asset files and updates all in-memory dictionary keys so
    /// the UI always shows Slot 1, Slot 2… without holes.
    private func compactSlots() {
        let filled = slots.filter(\.hasReel).sorted { $0.id < $1.id }
        let currentIds = filled.map(\.id)
        let targetIds  = Array(0..<filled.count)
        guard currentIds != targetIds else { return }  // already compact

        let fm = FileManager.default
        var newSlots:             [ForceReelSlot]  = []
        var newThumbnailImages:   [Int: UIImage]   = [:]
        var newVideoReady:        [Int: Bool]      = [:]
        var newDownloadingVideo:  [Int: Bool]      = [:]

        for (newId, slot) in filled.enumerated() {
            let oldId = slot.id
            if oldId != newId {
                // Move thumbnail file
                if let src = ForceReelSlot.localThumbnailFileURL(for: oldId),
                   let dst = ForceReelSlot.localThumbnailFileURL(for: newId),
                   fm.fileExists(atPath: src.path) {
                    try? fm.removeItem(at: dst)
                    try? fm.moveItem(at: src, to: dst)
                }
                // Move video file
                if let src = ForceReelSlot.localVideoFileURL(for: oldId),
                   let dst = ForceReelSlot.localVideoFileURL(for: newId),
                   fm.fileExists(atPath: src.path) {
                    try? fm.removeItem(at: dst)
                    try? fm.moveItem(at: src, to: dst)
                }
            }
            var updated = slot
            updated.id = newId
            newSlots.append(updated)
            if let img  = thumbnailImages[oldId]   { newThumbnailImages[newId]  = img   }
            if let rdy  = videoReady[oldId]        { newVideoReady[newId]       = rdy   }
            if let dl   = downloadingVideo[oldId]  { newDownloadingVideo[newId] = dl    }
        }

        // Apply all changes atomically
        thumbnailImages  = newThumbnailImages
        videoReady       = newVideoReady
        downloadingVideo = newDownloadingVideo
        slots = newSlots  // triggers persistSlots()

        print("🎭 [FORCE] Slots compacted: \(currentIds) → \(newSlots.map(\.id))")
    }

    func clearAllReels() {
        for slot in slots {
            deleteLocalAssets(for: slot.id)
        }
        slots.removeAll()
        thumbnailImages.removeAll()
        videoReady.removeAll()
        downloadingVideo.removeAll()
        pendingPosition = 0
        print("🎭 [FORCE] All reels cleared")
    }

    /// Returns the next available slot index (0, 1, or 2), or nil if all 3 are filled.
    func nextAvailableSlotIndex() -> Int? {
        let usedIds = Set(slots.map(\.id))
        return (0..<Self.maxSlots).first { !usedIds.contains($0) }
    }

    // MARK: - Build fake media items

    func allFakeMediaItems() -> [(item: InstagramMediaItem, slot: ForceReelSlot)] {
        slots.compactMap { slot in
            guard let item = slot.asFakeMediaItem(localVideoReady: videoReady[slot.id] ?? false) else { return nil }
            return (item, slot)
        }
    }

    /// Legacy: returns the first slot's fake item (backward compat).
    func asFakeMediaItem() -> InstagramMediaItem? {
        slots.first(where: \.hasReel)?.asFakeMediaItem(localVideoReady: videoReady[slots.first?.id ?? 0] ?? false)
    }

    // MARK: - Persistence

    private static let slotsKey = "forceReel_slots_v2"

    private func persistSlots() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        UserDefaults.standard.set(data, forKey: Self.slotsKey)
    }

    private static func loadSlots() -> [ForceReelSlot] {
        guard let data = UserDefaults.standard.data(forKey: slotsKey),
              let decoded = try? JSONDecoder().decode([ForceReelSlot].self, from: data) else { return [] }
        return decoded
    }

    /// Migrate from the old single-slot UserDefaults keys.
    private func migrateFromLegacy() {
        let ud = UserDefaults.standard
        guard let mediaId = ud.string(forKey: "forceReel_mediaId"), !mediaId.isEmpty else { return }

        let legacy = ForceReelSlot(
            id: 0,
            thumbnailURL: ud.string(forKey: "forceReel_thumbnailURL") ?? "",
            videoURL: ud.string(forKey: "forceReel_videoURL") ?? "",
            mediaId: mediaId,
            sourceUsername: ud.string(forKey: "forceReel_sourceUsername") ?? "",
            likeCount: ud.object(forKey: "forceReel_likeCount") as? Int,
            commentCount: ud.object(forKey: "forceReel_commentCount") as? Int,
            caption: ud.string(forKey: "forceReel_caption")
        )
        slots = [legacy]

        // Migrate local files: rename old files to slot-0 format
        if let oldThumb = Self.appSupportDir?.appendingPathComponent("force_reel_thumbnail.jpg"),
           let newThumb = ForceReelSlot.localThumbnailFileURL(for: 0),
           FileManager.default.fileExists(atPath: oldThumb.path) {
            try? FileManager.default.moveItem(at: oldThumb, to: newThumb)
        }
        if let oldVideo = Self.appSupportDir?.appendingPathComponent("force_reel_video.mp4"),
           let newVideo = ForceReelSlot.localVideoFileURL(for: 0),
           FileManager.default.fileExists(atPath: oldVideo.path) {
            try? FileManager.default.moveItem(at: oldVideo, to: newVideo)
        }

        // Clean up old keys
        for key in ["forceReel_thumbnailURL", "forceReel_videoURL", "forceReel_mediaId",
                    "forceReel_sourceUsername", "forceReel_likeCount", "forceReel_commentCount", "forceReel_caption"] {
            ud.removeObject(forKey: key)
        }

        print("🎭 [FORCE] Migrated legacy single-slot to new multi-slot format")
    }

    // MARK: - Download helpers

    private static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private func ensureAppSupportDir() async {
        guard let dir = Self.appSupportDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func downloadAndSaveThumbnail(from urlString: String, slotIndex: Int) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92),
              let fileURL = ForceReelSlot.localThumbnailFileURL(for: slotIndex) else {
            print("⚠️ [FORCE] Could not download thumbnail for slot \(slotIndex)")
            return
        }
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            await MainActor.run { self.thumbnailImages[slotIndex] = image }
            print("✅ [FORCE] Thumbnail saved for slot \(slotIndex) (\(jpegData.count / 1024) KB)")
        } catch {
            print("⚠️ [FORCE] Failed to save thumbnail for slot \(slotIndex): \(error)")
        }
    }

    private func downloadAndSaveVideo(from urlString: String, slotIndex: Int) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let destURL = ForceReelSlot.localVideoFileURL(for: slotIndex) else {
            return
        }

        await MainActor.run { self.downloadingVideo[slotIndex] = true }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)

            await MainActor.run {
                self.downloadingVideo[slotIndex] = false
                self.videoReady[slotIndex] = true
            }
            print("✅ [FORCE] Video saved for slot \(slotIndex)")
        } catch {
            await MainActor.run { self.downloadingVideo[slotIndex] = false }
            print("⚠️ [FORCE] Video download failed for slot \(slotIndex): \(error.localizedDescription)")
        }
    }

    private static func loadLocalThumbnail(for index: Int) -> UIImage? {
        guard let fileURL = ForceReelSlot.localThumbnailFileURL(for: index),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func deleteLocalAssets(for index: Int) {
        [ForceReelSlot.localThumbnailFileURL(for: index), ForceReelSlot.localVideoFileURL(for: index)]
            .compactMap { $0 }
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
