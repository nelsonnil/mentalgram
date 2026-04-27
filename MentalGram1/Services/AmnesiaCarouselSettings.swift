import Foundation
import UIKit
import Combine

// MARK: - Upload state

enum AmnesiaUploadState: Equatable {
    case idle
    case uploading(step: Int, total: Int)   // step = current upload index (1-based)
    case ready
    case swapping
    case error(String)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle:                       return String(localized: "amnesia.state.idle")
        case .uploading(let s, let t):    return String(format: String(localized: "amnesia.state.uploading"), s, t)
        case .ready:                      return String(localized: "amnesia.state.ready")
        case .swapping:                   return String(localized: "amnesia.state.swapping")
        case .error(let msg):             return "\(String(localized: "amnesia.state.error")) \(msg)"
        }
    }
}

// MARK: - AmnesiaCarouselSettings

/// Manages the "Amnesia Carousel" mentalism effect.
///
/// Two carousel posts are uploaded to Instagram with the user's 5 images:
///   - **Short carousel** (images 1–4): initially visible on Instagram
///   - **Full carousel**  (images 1–5): initially archived
///
/// When the magician closes the carousel in Performance view,
/// both posts are swapped (short archived, full unarchived)
/// so the spectator sees 5 images where they counted 4.
final class AmnesiaCarouselSettings: ObservableObject {
    static let shared = AmnesiaCarouselSettings()

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// 5 image slots.  nil = not yet selected by the user.
    @Published var images: [UIImage?] = Array(repeating: nil, count: 5)

    /// Media ID of the short carousel (4 images) — visible initially.
    @Published var shortCarouselMediaId: String? {
        didSet { UserDefaults.standard.set(shortCarouselMediaId, forKey: Keys.shortId) }
    }

    /// Media ID of the full carousel (5 images) — archived initially.
    @Published var fullCarouselMediaId: String? {
        didSet { UserDefaults.standard.set(fullCarouselMediaId, forKey: Keys.fullId) }
    }

    /// false = short carousel visible (before effect)
    /// true  = full carousel visible (after effect)
    @Published var isRevealed: Bool {
        didSet { UserDefaults.standard.set(isRevealed, forKey: Keys.revealed) }
    }

    @Published var uploadState: AmnesiaUploadState = .idle

    // MARK: - Computed helpers

    var isReady: Bool { shortCarouselMediaId != nil && fullCarouselMediaId != nil }

    /// Number of image slots that have been filled.
    var filledCount: Int { images.filter { $0 != nil }.count }

    var allImagesFilled: Bool { filledCount == 5 }

    // MARK: - Keys

    private enum Keys {
        static let enabled  = "amnesia_enabled"
        static let shortId  = "amnesia_shortCarouselMediaId"
        static let fullId   = "amnesia_fullCarouselMediaId"
        static let revealed = "amnesia_isRevealed"
    }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard
        isEnabled            = ud.bool(forKey: Keys.enabled)
        shortCarouselMediaId = ud.string(forKey: Keys.shortId)
        fullCarouselMediaId  = ud.string(forKey: Keys.fullId)
        isRevealed           = ud.bool(forKey: Keys.revealed)
        loadImagesFromDisk()

        // Derive upload state from persisted data
        if isReady {
            uploadState = .ready
        }
    }

    // MARK: - Image persistence

    private static var imagesDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("AmnesiaCarousel")
    }

    private static func imageURL(for slot: Int) -> URL? {
        imagesDir?.appendingPathComponent("slot_\(slot).jpg")
    }

    func setImage(_ image: UIImage?, for slot: Int) {
        guard slot >= 0, slot < 5 else { return }
        images[slot] = image
        Task.detached(priority: .background) { [weak self] in
            self?.saveImageToDisk(image, slot: slot)
        }
    }

    private func saveImageToDisk(_ image: UIImage?, slot: Int) {
        guard let dir = Self.imagesDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let url = Self.imageURL(for: slot) else { return }
        if let img = image, let data = img.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadImagesFromDisk() {
        for slot in 0..<5 {
            guard let url = Self.imageURL(for: slot),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }
            images[slot] = image
        }
    }

    // MARK: - Reset

    /// Clears carousel IDs and resets to initial state (short visible, full archived).
    /// Call after a successful reset swap so the next performance starts fresh.
    func resetToInitialState() {
        isRevealed           = false
        uploadState          = isReady ? .ready : .idle
    }

    /// Full wipe: clears IDs, images and all persisted data.
    func clearAll() {
        shortCarouselMediaId = nil
        fullCarouselMediaId  = nil
        isRevealed           = false
        images               = Array(repeating: nil, count: 5)
        uploadState          = .idle
        if let dir = Self.imagesDir { try? FileManager.default.removeItem(at: dir) }
        print("🎭 [AMNESIA] All data cleared")
    }
}
