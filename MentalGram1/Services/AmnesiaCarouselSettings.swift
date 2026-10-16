import Foundation
import UIKit
import Combine

// MARK: - Upload state

/// Live archive state of the two carousel posts on Instagram (from `/media/info/`).
enum AmnesiaInstagramPhase: Equatable {
    case unknown
    case initial          // short public, full archived — ready to perform
    case revealed         // full public, short archived — needs reset before next show
    case bothPublic       // abnormal; still needs reset (archive full)
    case bothArchived     // abnormal
    case indeterminate
}

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

    /// Source slot indices for the visible 4-image carousel (images 1–4).
    static let shortCarouselSlotOrder = [0, 1, 2, 3]
    /// Source slot indices for the revealed 5-image carousel — hidden image is 3rd slide.
    static let revealedCarouselSlotOrder = [0, 1, 4, 2, 3]
    /// Index in `images` for the hidden / extra slide (ESP star).
    static let hiddenImageSlotIndex = 4

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// 5 image slots.  nil = not yet selected by the user.
    @Published var images: [UIImage?] = Array(repeating: nil, count: 5)

    /// Media ID of the short carousel (4 images) — visible initially.
    @Published var shortCarouselMediaId: String? {
        didSet {
            UserDefaults.standard.set(shortCarouselMediaId, forKey: Keys.shortId)
            if shortCarouselMediaId != nil { stampOwner() }
        }
    }

    /// Media ID of the full carousel (5 images) — archived initially.
    @Published var fullCarouselMediaId: String? {
        didSet {
            UserDefaults.standard.set(fullCarouselMediaId, forKey: Keys.fullId)
            if fullCarouselMediaId != nil { stampOwner() }
        }
    }

    /// false = short carousel visible (before effect)
    /// true  = full carousel visible (after effect)
    @Published var isRevealed: Bool {
        didSet { UserDefaults.standard.set(isRevealed, forKey: Keys.revealed) }
    }

    @Published var uploadState: AmnesiaUploadState = .idle

    /// Last known Instagram phase (refreshed from API when Sets/Settings banners appear).
    @Published private(set) var instagramPhase: AmnesiaInstagramPhase = .unknown

    /// `taken_at` of the short carousel — same upload session as the full carousel for date verification.
    @Published var carouselTakenAt: Date? {
        didSet {
            if let carouselTakenAt {
                UserDefaults.standard.set(carouselTakenAt.timeIntervalSince1970, forKey: Keys.carouselTakenAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.carouselTakenAt)
            }
        }
    }

    /// Performance grid index for the carousel post (re-applied after Instagram refresh).
    @Published private(set) var gridPinIndex: Int? {
        didSet {
            if let gridPinIndex {
                UserDefaults.standard.set(gridPinIndex, forKey: Keys.gridPin)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.gridPin)
            }
        }
    }

    // MARK: - Computed helpers

    var isReady: Bool { shortCarouselMediaId != nil && fullCarouselMediaId != nil }

    /// Number of image slots that have been filled.
    var filledCount: Int { images.filter { $0 != nil }.count }

    var allImagesFilled: Bool { filledCount == 5 }

    /// True when the effect must be reset before the next performance (local flag and/or Instagram).
    var needsReset: Bool {
        guard isEnabled, isReady else { return false }
        if isRevealed { return true }
        switch instagramPhase {
        case .revealed, .bothPublic:
            return true
        default:
            return false
        }
    }

    private var lastInstagramPhaseRefresh: Date?
    private let instagramPhaseRefreshInterval: TimeInterval = 45

    // MARK: - Keys

    private enum Keys {
        static let enabled  = "amnesia_enabled"
        static let shortId  = "amnesia_shortCarouselMediaId"
        static let fullId   = "amnesia_fullCarouselMediaId"
        static let revealed = "amnesia_isRevealed"
        static let carouselTakenAt = "amnesia_carouselTakenAt"
        static let gridPin = "amnesia_grid_pin_index"
        /// Instagram userId that owns the two uploaded carousel posts. Lets account
        /// switching tell "same account / reinstall" from "a genuinely different account".
        static let owner    = "amnesia_ownerUserId"
    }

    func rememberGridPinIndex(_ index: Int) {
        gridPinIndex = max(0, index)
        print("🎭 [AMNESIA] Grid pin → \(gridPinIndex!)")
    }

    func clearGridPin() {
        gridPinIndex = nil
    }

    /// Records which Instagram account the carousel posts belong to (current session).
    private func stampOwner() {
        let uid = InstagramService.shared.session.userId
        guard !uid.isEmpty else { return }
        UserDefaults.standard.set(uid, forKey: Keys.owner)
    }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard
        isEnabled            = ud.bool(forKey: Keys.enabled)
        shortCarouselMediaId = ud.string(forKey: Keys.shortId)
        fullCarouselMediaId  = ud.string(forKey: Keys.fullId)
        isRevealed           = ud.bool(forKey: Keys.revealed)
        if ud.object(forKey: Keys.carouselTakenAt) != nil {
            carouselTakenAt = Date(timeIntervalSince1970: ud.double(forKey: Keys.carouselTakenAt))
        } else {
            carouselTakenAt = nil
        }
        if ud.object(forKey: Keys.gridPin) != nil {
            gridPinIndex = ud.integer(forKey: Keys.gridPin)
        } else {
            gridPinIndex = nil
        }
        loadImagesFromDisk()
        applyRevealStateSafetyMigrationIfNeeded()

        // Derive upload state from persisted data
        if isReady {
            uploadState = .ready
        }
    }

    func reloadFromUserDefaults() {
        let ud = UserDefaults.standard
        isEnabled            = ud.bool(forKey: Keys.enabled)
        shortCarouselMediaId = ud.string(forKey: Keys.shortId)
        fullCarouselMediaId  = ud.string(forKey: Keys.fullId)
        isRevealed           = ud.bool(forKey: Keys.revealed)
        if ud.object(forKey: Keys.carouselTakenAt) != nil {
            carouselTakenAt = Date(timeIntervalSince1970: ud.double(forKey: Keys.carouselTakenAt))
        } else {
            carouselTakenAt = nil
        }
        if ud.object(forKey: Keys.gridPin) != nil {
            gridPinIndex = ud.integer(forKey: Keys.gridPin)
        } else {
            gridPinIndex = nil
        }
        loadImagesFromDisk()
        uploadState = isReady ? .ready : .idle
        print("🎭 [AMNESIA] Reloaded settings from UserDefaults after restore")
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

    /// Reconcile `isRevealed` / banner state with Instagram (short vs full archive flags).
    func refreshInstagramPhaseIfNeeded(force: Bool = false) async {
        guard isReady,
              let shortId = shortCarouselMediaId,
              let fullId = fullCarouselMediaId,
              InstagramService.shared.isLoggedIn
        else {
            await MainActor.run { instagramPhase = .unknown }
            return
        }

        if !force,
           let last = lastInstagramPhaseRefresh,
           Date().timeIntervalSince(last) < instagramPhaseRefreshInterval {
            return
        }
        lastInstagramPhaseRefresh = Date()

        do {
            async let fullTask = InstagramService.shared.getMediaIsArchived(mediaId: fullId)
            async let shortTask = InstagramService.shared.getMediaIsArchived(mediaId: shortId)
            let (fullArchived, shortArchived) = try await (fullTask, shortTask)

            await MainActor.run {
                let phase: AmnesiaInstagramPhase
                if let fullArchived, let shortArchived {
                    if !fullArchived && shortArchived {
                        phase = .revealed
                    } else if fullArchived && !shortArchived {
                        phase = .initial
                    } else if !fullArchived && !shortArchived {
                        phase = .bothPublic
                    } else if fullArchived && shortArchived {
                        phase = .bothArchived
                    } else {
                        phase = .indeterminate
                    }
                } else {
                    phase = .indeterminate
                }
                instagramPhase = phase

                if phase == .revealed || phase == .bothPublic {
                    if !isRevealed {
                        isRevealed = true
                        print("🎭 [AMNESIA] Synced isRevealed=true from Instagram phase=\(phase)")
                        LogManager.shared.info("Amnesia synced revealed=true from Instagram (\(phase))", category: .api)
                    }
                } else if phase == .initial, isRevealed {
                    isRevealed = false
                    print("🎭 [AMNESIA] Synced isRevealed=false from Instagram (initial phase)")
                    LogManager.shared.info("Amnesia synced revealed=false from Instagram (initial)", category: .api)
                }

                print("🎭 [AMNESIA] Phase refresh — enabled=\(isEnabled) ready=\(isReady) revealed=\(isRevealed) igPhase=\(phase) needsReset=\(needsReset)")
            }
        } catch {
            print("🎭 [AMNESIA] Phase refresh failed: \(error.localizedDescription)")
            LogManager.shared.warning("Amnesia Instagram phase refresh failed: \(error.localizedDescription)", category: .api)
        }
    }

    private func applyRevealStateSafetyMigrationIfNeeded() {
        let key = "amnesia_reveal_state_safety_migration_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        // Builds before the validated swap flow could persist `isRevealed = true`
        // after an optimistic local paint even when Instagram still showed the
        // 4-image carousel. Start updated users from the safe initial state once.
        if isRevealed {
            isRevealed = false
            print("🎭 [AMNESIA] Safety migration reset revealed state to initial")
        }
    }

    // MARK: - Reset

    /// Clears carousel IDs and resets to initial state (short visible, full archived).
    /// Call after a successful reset swap so the next performance starts fresh.
    func resetToInitialState() {
        isRevealed           = false
        uploadState          = isReady ? .ready : .idle
    }

    /// Called when the logged-in Instagram account changes. The two carousel posts live on
    /// the PREVIOUS account, so their IDs are meaningless for a different one. We clear the
    /// post IDs + reveal state ONLY when switching to a genuinely different account — never
    /// on logout (empty) or when re-logging into the same account (e.g. after a reinstall
    /// + restore), so the owner can keep their setup. Source images are kept for quick
    /// re-upload on the new account.
    func resetForAccountChange(to newUserId: String) {
        guard shortCarouselMediaId != nil || fullCarouselMediaId != nil || isRevealed else { return }

        // Logging out (empty) — keep data; it belongs to `owner` and may be re-used on re-login.
        guard !newUserId.isEmpty else { return }

        let owner = UserDefaults.standard.string(forKey: Keys.owner) ?? ""
        if owner.isEmpty {
            // Legacy/untagged setup — assume it belongs to whoever is logged in now; tag it
            // and keep it rather than risk wiping a valid configuration.
            UserDefaults.standard.set(newUserId, forKey: Keys.owner)
            return
        }
        if owner == newUserId { return }  // same account → keep

        // Genuinely different account → clear the stale posts.
        shortCarouselMediaId = nil
        fullCarouselMediaId  = nil
        isRevealed           = false
        carouselTakenAt      = nil
        clearGridPin()
        uploadState          = .idle
        UserDefaults.standard.set(newUserId, forKey: Keys.owner)
        print("🎭 [AMNESIA] Account changed \(owner) → \(newUserId) — cleared carousel post IDs (kept source images)")
    }

    /// Full wipe: clears IDs, images and all persisted data.
    func clearAll() {
        shortCarouselMediaId = nil
        fullCarouselMediaId  = nil
        isRevealed           = false
        carouselTakenAt      = nil
        clearGridPin()
        images               = Array(repeating: nil, count: 5)
        uploadState          = .idle
        if let dir = Self.imagesDir { try? FileManager.default.removeItem(at: dir) }
        deleteImagesFromCloud()
        print("🎭 [AMNESIA] All data cleared")
    }

    // MARK: - iCloud Drive sync (5 source slots)
    //
    // The carousel EFFECT itself is preserved by the saved media IDs (the two posts
    // already live on Instagram). These 5 source images are the setup-screen guide; we
    // back them up too so the configuration looks exactly as left after a reinstall.

    private static let cloudFolder = "AmnesiaCarousel"

    /// Uploads the 5 source slot images to iCloud Drive.
    func uploadImagesToCloud() {
        let fm = FileManager.default
        Task.detached(priority: .background) {
            guard let base = fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else {
                print("🎭 [AMNESIA] iCloud container unavailable — slots not backed up")
                return
            }
            let cloudDir = base.appendingPathComponent("Documents/\(Self.cloudFolder)", isDirectory: true)
            try? fm.createDirectory(at: cloudDir, withIntermediateDirectories: true)
            var uploaded = 0
            for slot in 0..<5 {
                guard let localURL = Self.imageURL(for: slot),
                      fm.fileExists(atPath: localURL.path) else { continue }
                let dest = cloudDir.appendingPathComponent("slot_\(slot).jpg")
                do {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: localURL, to: dest)
                    uploaded += 1
                } catch {
                    print("🎭 [AMNESIA] Slot \(slot) upload failed: \(error.localizedDescription)")
                }
            }
            print("🎭 [AMNESIA] ✅ \(uploaded) carousel slot image(s) synced to iCloud Drive")
        }
    }

    /// Restores the 5 source slot images from iCloud Drive into Application Support.
    func downloadImagesFromCloud(completion: @escaping (Int) -> Void = { _ in }) {
        guard let dir = Self.imagesDir else { completion(0); return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let group = DispatchGroup()
        var restored = 0
        let lock = NSLock()
        for slot in 0..<5 {
            guard let localURL = Self.imageURL(for: slot) else { continue }
            group.enter()
            iCloudDriveSync.shared.restoreContainerFile(
                named: "\(Self.cloudFolder)/slot_\(slot).jpg", to: localURL
            ) { success in
                if success { lock.lock(); restored += 1; lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if restored > 0 {
                self.loadImagesFromDisk()
                self.objectWillChange.send()
            }
            print("🎭 [AMNESIA] Restored \(restored) carousel slot image(s) from iCloud Drive")
            completion(restored)
        }
    }

    private func deleteImagesFromCloud() {
        let fm = FileManager.default
        Task.detached(priority: .background) {
            guard let base = fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else { return }
            let cloudDir = base.appendingPathComponent("Documents/\(Self.cloudFolder)", isDirectory: true)
            try? fm.removeItem(at: cloudDir)
            print("🎭 [AMNESIA] Deleted carousel slots from iCloud Drive")
        }
    }
}
