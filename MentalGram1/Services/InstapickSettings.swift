import Foundation
import UIKit
import SwiftUI
import Combine
import AudioToolbox

/// How the floating card responds to device orientation.
enum InstapickTiltStyle: String, CaseIterable, Identifiable {
    case slide = "slide"
    /// Specular shine that moves with tilt (raw `"3d"` kept for saved settings).
    case reflection = "3d"
    /// Slide + moving reflection (raw `"slide3d"` kept for saved settings).
    case slideAndReflection = "slide3d"
    case softFloat = "float"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slide: return "Classic slide"
        case .reflection: return "Reflection only"
        case .slideAndReflection: return "Slide + reflection"
        case .softFloat: return "Soft float"
        }
    }

    var detail: String {
        switch self {
        case .slide: return "Card slides on the screen like on a table when you tilt. Flat — no warp."
        case .reflection: return "Card stays flat; a glossy highlight slides across it as you tilt."
        case .slideAndReflection: return "Slides on tilt and shows a moving light reflection (shape stays flat)."
        case .softFloat: return "Gentle float with a soft shine — less aggressive."
        }
    }

    var usesSlide: Bool {
        self == .slide || self == .slideAndReflection || self == .softFloat
    }

    var usesReflection: Bool {
        self == .reflection || self == .slideAndReflection || self == .softFloat
    }
}

/// Which floating-card artwork to use in the Instapick overlay.
enum InstapickCardArt: String, CaseIterable, Identifiable {
    case classic = "card"
    case bicycle = "card_bicycle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic card"
        case .bicycle: return "Bicycle red"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Original Instapick overlay card."
        case .bicycle: return "Red bicycle-back card (transparent background)."
        }
    }

    /// Bundled resource name inside InstapickAssets (without extension).
    var assetName: String { rawValue }
}

/// Extra motion when volume DOWN is pressed while the card is floating
/// (and a light entrance impulse when the overlay first arms).
enum InstapickVolumeFx: String, CaseIterable, Identifiable {
    case none = "none"
    case hopSpin = "hop"
    case blowBounce = "blow"
    case tumbleKick = "tumble"
    case pulse = "pulse"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None (drag only)"
        case .hopSpin: return "Hop + spin"
        case .blowBounce: return "Blow up & bounce"
        case .tumbleKick: return "Tumble kick"
        case .pulse: return "Pulse bounce"
        }
    }

    var detail: String {
        switch self {
        case .none: return "No volume impulse — tilt/drag only."
        case .hopSpin: return "Volume makes the card jump and twist, then fall with inertia."
        case .blowBounce: return "Like a breath upward — hits the top, bounces, settles naturally."
        case .tumbleKick: return "Sideways kick with a tumbling spin."
        case .pulse: return "Small lively bounce in place."
        }
    }
}

/// One row in the Instapick upload checklist (upload / publish / archive).
struct InstapickUploadStepItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case active
        case done
        case failed
    }

    let id: String
    let title: String
    var status: Status
}

/// Upload / live-ready state for Instapick (mirrors Amnesia’s compact states).
enum InstapickUploadState: Equatable {
    case idle
    case uploading(step: Int, total: Int, detail: String)
    case ready
    case swapping
    case error(String)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "Upload to Instagram"
        case .uploading(let s, let t, let detail):
            if detail.isEmpty { return "Uploading \(s)/\(t)…" }
            return "\(detail)  ·  \(s)/\(t)"
        case .ready: return "Ready on Instagram"
        case .swapping: return "Swapping…"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    /// Five whole Instagram carousels: Base (visible) + Color 1…4 (hidden until reveal).
    static var pipelineChecklist: [InstapickUploadStepItem] {
        [
            .init(id: "post-base", title: "Publish Base (cover + 4 colors)", status: .pending),
            .init(id: "post-v1", title: "Publish Color 1 (hidden)", status: .pending),
            .init(id: "post-v2", title: "Publish Color 2 (hidden)", status: .pending),
            .init(id: "post-v3", title: "Publish Color 3 (hidden)", status: .pending),
            .init(id: "post-v4", title: "Publish Color 4 (hidden)", status: .pending),
        ]
    }
}

/// Disk checkpoint so Instapick upload can resume after minimize / kill / bot pause.
enum InstapickUploadCheckpointPhase: String {
    case none
    /// Mid-upload of one of the five carousels (partial rupload ids).
    case uploading
}

extension InstagramError {
    /// Magician-facing copy + whether the Instapick checkpoint should be kept.
    var instapickRecoveryMessage: (text: String, keepCheckpoint: Bool) {
        switch self {
        case .botDetected(let msg):
            return (
                "Instagram safety lockdown: \(msg). Wait for the timer, then tap Continue upload.",
                true
            )
        case .challengeRequired:
            return (
                "Instagram asks for verification. Complete it in the Instagram app, wait a few minutes, then tap Continue upload.",
                true
            )
        case .sessionExpired:
            return (
                "Session expired. Sign in again in Vault, then tap Continue upload.",
                true
            )
        case .networkError:
            return (
                "Network error. When you have a good connection, tap Continue upload.",
                true
            )
        case .apiError(let msg):
            let lower = msg.lowercased()
            if lower.contains("lockdown") || lower.contains("safety") || lower.contains("budget") {
                return ("Safety pause: \(msg). Wait, then tap Continue upload.", true)
            }
            if lower.contains("archiv") {
                return (msg, true)
            }
            return (msg, true)
        default:
            return (localizedDescription, true)
        }
    }
}

/// Instapick mentalism effect — fixed asset pack (`o`, `1a/1b`…`4a/4b`).
///
/// - **Test:** Performance Test Mode paints a local carousel (`instapick://…`).
/// - **Live:** Five whole Instagram carousels (Base + Color 1…4). Base stays public;
///   Color posts start archived. Reveal archives Base and unarchives that Color post.
final class InstapickSettings: ObservableObject {
    static let shared = InstapickSettings()

    /// Synthetic media id used for the local test carousel.
    static let testMediaId = "instapick-test-carousel"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Device-orientation feel for the floating card.
    @Published var tiltStyle: InstapickTiltStyle {
        didSet { UserDefaults.standard.set(tiltStyle.rawValue, forKey: Keys.tiltStyle) }
    }

    /// Volume-DOWN impulse while the card is floating (also a soft entrance kick).
    @Published var volumeFx: InstapickVolumeFx {
        didSet { UserDefaults.standard.set(volumeFx.rawValue, forKey: Keys.volumeFx) }
    }

    /// Floating card artwork shown in the overlay.
    @Published var cardArt: InstapickCardArt {
        didSet { UserDefaults.standard.set(cardArt.rawValue, forKey: Keys.cardArt) }
    }

    /// Base carousel media id on Instagram (cover + 4a colors). Visible before reveal.
    @Published var carouselMediaId: String? {
        didSet {
            UserDefaults.standard.set(carouselMediaId, forKey: Keys.carouselId)
            if carouselMediaId != nil { stampOwner() }
        }
    }

    /// Color variant carousel ids: keys `"1"`…`"4"` → full post media id (starts archived).
    @Published var variantMediaIds: [String: String] = [:] {
        didSet {
            UserDefaults.standard.set(variantMediaIds, forKey: Keys.variantIds)
        }
    }

    /// Preferred grid index so Instapick stays in place across Instagram refreshes.
    @Published private(set) var gridPinIndex: Int? {
        didSet {
            if let gridPinIndex {
                UserDefaults.standard.set(gridPinIndex, forKey: Keys.gridPin)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.gridPin)
            }
        }
    }

    @Published var uploadState: InstapickUploadState = .idle

    /// Live checklist while uploading (one row per carousel post).
    @Published var uploadChecklist: [InstapickUploadStepItem] = []

    /// Persisted mid-upload phase (survives minimize / kill).
    @Published private(set) var checkpointPhase: InstapickUploadCheckpointPhase = .none

    /// Partial sidecar `upload_id`s for the carousel currently being uploaded.
    @Published private(set) var checkpointUploadIds: [String] = []

    /// Which of the 5 posts is in progress (0 = Base, 1…4 = Color).
    @Published private(set) var checkpointPostIndex: Int = 0

    /// Last human-readable status for the resume banner.
    @Published private(set) var checkpointDetail: String = ""

    /// Color slots (1…4) already revealed this show (live: typically one).
    @Published private(set) var swappedSlots: Set<Int> = []

    /// Live carousel page while the Instapick post is open (0 = cover `o`).
    @Published var liveCarouselPage: Int = 0

    /// When non-nil, Performance shows the full-screen card-drag overlay for that slot (1…4).
    @Published var activeOverlaySlot: Int? = nil

    /// Base + all four Color posts are linked.
    var hasLiveMediaIds: Bool {
        guard carouselMediaId != nil else { return false }
        return (1...4).allSatisfy { variantMediaIds["\($0)"] != nil }
    }

    /// Live Instagram pack ready for Performance.
    var isLiveReady: Bool { hasLiveMediaIds }

    /// Local practice (Test Mode) or live Instagram pack ready.
    var isReadyForPerformance: Bool {
        guard isEnabled, bundledAssetsAvailable else { return false }
        if PostPredictionTestMode.shared.isActive { return true }
        return isLiveReady
    }

    /// True when Instapick is enabled but waiting for Test Mode or Upload.
    var needsSetupHint: Bool {
        isEnabled && bundledAssetsAvailable && !isReadyForPerformance
    }

    /// Using the synthetic local carousel (not the real IG post).
    var isUsingLocalTestCarousel: Bool {
        isEnabled && bundledAssetsAvailable && PostPredictionTestMode.shared.isActive
    }

    /// Live Instagram slots were revealed and need the inverse archive/unarchive.
    var needsRestore: Bool {
        isEnabled && isLiveReady && !swappedSlots.isEmpty
    }

    /// Clears overlay / session state when leaving Performance.
    /// Test mode: full local reset so the effect can be repeated immediately.
    /// Live mode: keeps `swappedSlots` so the restore banner can reverse IG.
    func endPerformanceSession() {
        activeOverlaySlot = nil
        liveCarouselPage = 0
        if isUsingLocalTestCarousel || !isLiveReady {
            resetSwaps()
            print("🔄 [INSTAPICK] Performance session ended — local swaps cleared")
        } else if needsRestore {
            print("🔄 [INSTAPICK] Performance session ended — \(swappedSlots.count) slot(s) need IG restore")
        } else {
            print("🔄 [INSTAPICK] Performance session ended")
        }
    }

    private enum Keys {
        static let enabled = "instapick_enabled"
        static let swapped = "instapick_swapped_slots"
        static let carouselId = "instapick_carousel_media_id"
        static let variantIds = "instapick_variant_media_ids"
        static let legacyChildIds = "instapick_child_media_ids"
        static let gridPin = "instapick_grid_pin_index"
        static let owner = "instapick_ownerUserId"
        static let legacyTestReady = "instapick_test_ready"
        static let tiltStyle = "instapick_tilt_style"
        static let volumeFx = "instapick_volume_fx"
        static let cardArt = "instapick_card_art"
        static let cpPhase = "instapick_cp_phase"
        static let cpUploadIds = "instapick_cp_upload_ids"
        static let cpPostIndex = "instapick_cp_post_index"
        static let cpDetail = "instapick_cp_detail"
        static let legacyArchivedB = "instapick_archived_b_labels"
        static let legacyCpParent = "instapick_cp_parent_id"
    }

    private init() {
        let ud = UserDefaults.standard
        isEnabled = ud.bool(forKey: Keys.enabled)
        tiltStyle = InstapickTiltStyle(rawValue: ud.string(forKey: Keys.tiltStyle) ?? "") ?? .slideAndReflection
        volumeFx = InstapickVolumeFx(rawValue: ud.string(forKey: Keys.volumeFx) ?? "") ?? .blowBounce
        cardArt = InstapickCardArt(rawValue: ud.string(forKey: Keys.cardArt) ?? "") ?? .classic
        ud.removeObject(forKey: Keys.legacyTestReady)
        ud.removeObject(forKey: Keys.legacyArchivedB)
        ud.removeObject(forKey: Keys.legacyCpParent)
        // Old 9-slide child-id packs cannot be used with the 5-post model — clear them.
        if ud.dictionary(forKey: Keys.legacyChildIds) != nil {
            ud.removeObject(forKey: Keys.legacyChildIds)
            ud.removeObject(forKey: Keys.carouselId)
            print("🃏 [INSTAPICK] Cleared legacy single-carousel child IDs (need re-upload)")
        }
        carouselMediaId = ud.string(forKey: Keys.carouselId)
        if let stored = ud.dictionary(forKey: Keys.variantIds) as? [String: String] {
            variantMediaIds = stored
        }
        if isLiveReady,
           !PostPredictionTestMode.shared.isActive,
           let raw = ud.array(forKey: Keys.swapped) as? [Int] {
            swappedSlots = Set(raw.filter { (1...4).contains($0) })
        } else {
            swappedSlots = []
            if !isLiveReady {
                ud.removeObject(forKey: Keys.swapped)
            }
        }
        if ud.object(forKey: Keys.gridPin) != nil {
            gridPinIndex = ud.integer(forKey: Keys.gridPin)
        }
        loadCheckpointFromDisk()
        if isLiveReady && !hasResumableCheckpoint {
            uploadState = .ready
        } else if hasResumableCheckpoint {
            uploadState = .error(checkpointDetail.isEmpty
                ? "Upload interrupted. Tap Continue upload."
                : checkpointDetail)
        }
    }

    /// True when a previous upload can continue without starting from zero.
    var hasResumableCheckpoint: Bool {
        resumeKind != .none
    }

    /// How many of the 5 posts are already saved (Base + variants).
    var completedPostCount: Int {
        var n = 0
        if carouselMediaId != nil { n += 1 }
        n += (1...4).filter { variantMediaIds["\($0)"] != nil }.count
        return n
    }

    /// Resume target derived from checkpoint + live ids.
    var resumeKind: InstapickUploadCheckpointPhase {
        if isLiveReady && checkpointPhase == .none { return .none }
        if !checkpointUploadIds.isEmpty || checkpointPhase == .uploading { return .uploading }
        if completedPostCount > 0 && completedPostCount < 5 { return .uploading }
        return .none
    }

    func markChecklistItem(id: String, status: InstapickUploadStepItem.Status) {
        guard let idx = uploadChecklist.firstIndex(where: { $0.id == id }) else { return }
        uploadChecklist[idx].status = status
    }

    private func loadCheckpointFromDisk() {
        let ud = UserDefaults.standard
        let rawPhase = ud.string(forKey: Keys.cpPhase) ?? ""
        // Map legacy phase names to the new uploading checkpoint.
        if rawPhase == "rupload" || rawPhase == "published" || rawPhase == "archive" {
            checkpointPhase = .uploading
        } else {
            checkpointPhase = InstapickUploadCheckpointPhase(rawValue: rawPhase) ?? .none
        }
        checkpointUploadIds = ud.stringArray(forKey: Keys.cpUploadIds) ?? []
        checkpointPostIndex = ud.integer(forKey: Keys.cpPostIndex)
        checkpointDetail = ud.string(forKey: Keys.cpDetail) ?? ""
    }

    func saveCheckpoint(
        phase: InstapickUploadCheckpointPhase,
        uploadIds: [String]? = nil,
        postIndex: Int? = nil,
        detail: String? = nil
    ) {
        checkpointPhase = phase
        if let uploadIds { checkpointUploadIds = uploadIds }
        if let postIndex { checkpointPostIndex = postIndex }
        if let detail { checkpointDetail = detail }
        let ud = UserDefaults.standard
        ud.set(phase.rawValue, forKey: Keys.cpPhase)
        ud.set(checkpointUploadIds, forKey: Keys.cpUploadIds)
        ud.set(checkpointPostIndex, forKey: Keys.cpPostIndex)
        ud.set(checkpointDetail, forKey: Keys.cpDetail)
        print("🃏 [INSTAPICK] Checkpoint → \(phase.rawValue) post:\(checkpointPostIndex) ids:\(checkpointUploadIds.count)")
    }

    func markUploadInterrupted(detail: String) {
        saveCheckpoint(phase: .uploading, detail: detail)
        if !uploadState.isUploading {
            uploadState = .error(detail)
        }
    }

    func clearUploadCheckpoint() {
        checkpointPhase = .none
        checkpointUploadIds = []
        checkpointPostIndex = 0
        checkpointDetail = ""
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Keys.cpPhase)
        ud.removeObject(forKey: Keys.cpUploadIds)
        ud.removeObject(forKey: Keys.cpPostIndex)
        ud.removeObject(forKey: Keys.cpDetail)
        print("🃏 [INSTAPICK] Checkpoint cleared")
    }

    /// Call when entering Performance so test practice always starts clean.
    func preparePerformanceSession() {
        activeOverlaySlot = nil
        liveCarouselPage = 0
        if isUsingLocalTestCarousel {
            swappedSlots = []
            print("🃏 [INSTAPICK] Test session prepared — swaps cleared for practice")
        }
    }

    private func stampOwner() {
        let uid = InstagramService.shared.session.userId
        guard !uid.isEmpty else { return }
        UserDefaults.standard.set(uid, forKey: Keys.owner)
    }

    func rememberGridPinIndex(_ index: Int) {
        gridPinIndex = max(0, index)
        print("🃏 [INSTAPICK] Grid pin → \(gridPinIndex!)")
    }

    func reloadFromUserDefaults() {
        let ud = UserDefaults.standard
        isEnabled = ud.bool(forKey: Keys.enabled)
        tiltStyle = InstapickTiltStyle(rawValue: ud.string(forKey: Keys.tiltStyle) ?? "") ?? .slideAndReflection
        volumeFx = InstapickVolumeFx(rawValue: ud.string(forKey: Keys.volumeFx) ?? "") ?? .blowBounce
        cardArt = InstapickCardArt(rawValue: ud.string(forKey: Keys.cardArt) ?? "") ?? .classic
        carouselMediaId = ud.string(forKey: Keys.carouselId)
        if let stored = ud.dictionary(forKey: Keys.variantIds) as? [String: String] {
            variantMediaIds = stored
        } else {
            variantMediaIds = [:]
        }
        if isLiveReady,
           !PostPredictionTestMode.shared.isActive,
           let raw = ud.array(forKey: Keys.swapped) as? [Int] {
            swappedSlots = Set(raw.filter { (1...4).contains($0) })
        } else {
            swappedSlots = []
            if !isLiveReady {
                ud.removeObject(forKey: Keys.swapped)
            }
        }
        if ud.object(forKey: Keys.gridPin) != nil {
            gridPinIndex = ud.integer(forKey: Keys.gridPin)
        } else {
            gridPinIndex = nil
        }
        uploadState = isLiveReady ? .ready : .idle
        print("🃏 [INSTAPICK] Reloaded settings from UserDefaults after restore")
    }

    /// Clears live Instagram IDs when switching to a different account (same as Amnesia).
    func resetForAccountChange(to newUserId: String) {
        guard carouselMediaId != nil || !variantMediaIds.isEmpty || !swappedSlots.isEmpty else { return }
        guard !newUserId.isEmpty else { return }

        let owner = UserDefaults.standard.string(forKey: Keys.owner) ?? ""
        if owner.isEmpty {
            UserDefaults.standard.set(newUserId, forKey: Keys.owner)
            return
        }
        if owner == newUserId { return }

        carouselMediaId = nil
        variantMediaIds = [:]
        gridPinIndex = nil
        clearUploadCheckpoint()
        resetSwaps()
        uploadState = .idle
        UserDefaults.standard.set(newUserId, forKey: Keys.owner)
        UserDefaults.standard.removeObject(forKey: Keys.carouselId)
        UserDefaults.standard.removeObject(forKey: Keys.variantIds)
        UserDefaults.standard.removeObject(forKey: Keys.gridPin)
        print("🃏 [INSTAPICK] Account changed \(owner) → \(newUserId) — cleared live carousel IDs")
    }

    // MARK: - Bundled assets

    var bundledAssetsAvailable: Bool {
        imageO() != nil
            && (1...4).allSatisfy { imageA($0) != nil && imageB($0) != nil }
            && cardOverlay() != nil
    }

    func imageO() -> UIImage? { loadBundled("o") }
    func imageA(_ slot: Int) -> UIImage? { loadBundled("\(slot)a") }
    func imageB(_ slot: Int) -> UIImage? { loadBundled("\(slot)b") }

    /// Selected overlay artwork (falls back to classic `card` if missing).
    func cardOverlay() -> UIImage? {
        if let img = loadBundled(cardArt.assetName) { return img }
        if cardArt != .classic { return loadBundled(InstapickCardArt.classic.assetName) }
        return nil
    }

    /// Five Instagram carousels to publish: Base (visible) + Color 1…4 (archived).
    /// Each array is `[o, …]` with five images.
    func uploadCarouselImageSets() -> [[UIImage]]? {
        guard let o = imageO() else { return nil }
        var a: [UIImage] = []
        var b: [UIImage] = []
        for slot in 1...4 {
            guard let ai = imageA(slot), let bi = imageB(slot) else { return nil }
            a.append(ai)
            b.append(bi)
        }
        // Base: o, 1a, 2a, 3a, 4a
        let base = [o] + a
        // Color N: o + a's with slot N replaced by b
        var sets: [[UIImage]] = [base]
        for slot in 1...4 {
            var pages = [o] + a
            pages[slot] = b[slot - 1]
            sets.append(pages)
        }
        return sets
    }

    /// Human labels for the five posts (checklist / progress).
    static let postLabels: [String] = [
        "Base", "Color 1", "Color 2", "Color 3", "Color 4"
    ]

    /// Visible carousel pages for Performance paint:
    /// `o` + slot images (`a` until revealed, then `b`).
    func visibleCarouselImages() -> [UIImage] {
        var images: [UIImage] = []
        if let o = imageO() { images.append(o) }
        for slot in 1...4 {
            if let img = swappedSlots.contains(slot) ? imageB(slot) : imageA(slot) {
                images.append(img)
            }
        }
        return images
    }

    /// Maps carousel page index → color slot (1…4). Page 0 is cover `o`.
    func colorSlot(forCarouselPage page: Int) -> Int? {
        guard page >= 1, page <= 4 else { return nil }
        return page
    }

    func variantMediaId(forSlot slot: Int) -> String? {
        guard (1...4).contains(slot) else { return nil }
        return variantMediaIds["\(slot)"]
    }

    /// Media id of the post currently public on Instagram (Base, or Color N after reveal).
    var visibleLiveMediaId: String? {
        if let slot = swappedSlots.sorted().first, let id = variantMediaId(forSlot: slot) {
            return id
        }
        return carouselMediaId
    }

    func rememberVariantId(slot: Int, mediaId: String) {
        guard (1...4).contains(slot) else { return }
        var next = variantMediaIds
        next["\(slot)"] = mediaId
        variantMediaIds = next
        stampOwner()
        print("🃏 [INSTAPICK] Saved Color \(slot) id=\(mediaId)")
    }

    func rememberBaseId(_ mediaId: String) {
        carouselMediaId = mediaId
        stampOwner()
        rememberGridPinIndex(0)
        print("🃏 [INSTAPICK] Saved Base id=\(mediaId)")
    }

    /// Marks Ready when Base + Color 1…4 ids are present.
    func applyLiveUploadReady() {
        stampOwner()
        rememberGridPinIndex(0)
        resetSwaps()
        guard isLiveReady else {
            saveCheckpoint(
                phase: .uploading,
                postIndex: completedPostCount,
                detail: "Upload incomplete (\(completedPostCount)/5 posts). Tap Continue upload."
            )
            uploadState = .error("Upload incomplete. Tap Continue upload.")
            return
        }
        uploadState = .ready
        uploadChecklist = []
        clearUploadCheckpoint()
        print("✅ [INSTAPICK] Live ready — base=\(carouselMediaId ?? "?") variants=\(variantMediaIds.count)")
    }

    func beginUploadChecklist() {
        uploadChecklist = InstapickUploadState.pipelineChecklist
    }

    /// Marks pipeline rows: indices `< completed` done, `completed` active (if in range).
    /// Never overwrites an existing `.failed` row with `.done`.
    func updateUploadChecklist(completed: Int, failedId: String? = nil) {
        guard !uploadChecklist.isEmpty else { return }
        var items = uploadChecklist
        for i in items.indices {
            if let failedId, items[i].id == failedId {
                items[i].status = .failed
            } else if items[i].status == .failed {
                continue
            } else if i < completed {
                items[i].status = .done
            } else if i == completed {
                items[i].status = .active
            } else {
                items[i].status = .pending
            }
        }
        uploadChecklist = items
    }

    func markUploadChecklistFailed(atIndex index: Int) {
        guard uploadChecklist.indices.contains(index) else { return }
        uploadChecklist[index].status = .failed
    }

    func clearLiveUpload() {
        carouselMediaId = nil
        variantMediaIds = [:]
        gridPinIndex = nil
        uploadState = .idle
        resetSwaps()
        clearUploadCheckpoint()
        UserDefaults.standard.removeObject(forKey: Keys.carouselId)
        UserDefaults.standard.removeObject(forKey: Keys.variantIds)
        UserDefaults.standard.removeObject(forKey: Keys.gridPin)
    }

    func resetSwaps() {
        swappedSlots = []
        activeOverlaySlot = nil
        liveCarouselPage = 0
        if isUsingLocalTestCarousel {
            // Practice only — leave any live restore list on disk untouched.
            print("🔄 [INSTAPICK] Swaps cleared (test memory)")
            return
        }
        UserDefaults.standard.removeObject(forKey: Keys.swapped)
        print("🔄 [INSTAPICK] Swaps cleared")
    }

    func markSwapped(slot: Int) {
        guard (1...4).contains(slot) else { return }
        swappedSlots.insert(slot)
        persistSwappedIfNeeded()
        print("🃏 [INSTAPICK] Slot \(slot) swapped → showing \(slot)b")
    }

    /// Volume DOWN trigger while viewing a color page — arms the card overlay.
    @discardableResult
    func tryBeginOverlayFromVolume() -> Bool {
        guard isReadyForPerformance, activeOverlaySlot == nil else { return false }
        guard let slot = colorSlot(forCarouselPage: liveCarouselPage) else {
            print("🃏 [INSTAPICK] Volume DOWN ignored — on cover or invalid page \(liveCarouselPage)")
            return false
        }
        guard swappedSlots.isEmpty else {
            print("🃏 [INSTAPICK] Volume DOWN ignored — already revealed this show (reset first)")
            return false
        }
        // No SwiftUI animation — Na→Nb + floating card must land in the same frame
        // or the spectator sees a flash.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            activeOverlaySlot = slot
        }
        print("🃏 [INSTAPICK] Overlay armed for slot \(slot) via volume DOWN")
        return true
    }

    /// Arms silent mid-volume so volume DOWN always registers inside the Instapick carousel.
    /// Uses the hidden MPVolumeView path — no system HUD.
    @MainActor
    func armSilentMidVolumeForCarousel() {
        guard isReadyForPerformance else { return }
        VideoPlaybackCoordinator.shared.muteActive()
        let monitor = VolumeButtonMonitor.shared
        monitor.prepareVolume()
        // startMonitoring already ensures mid volume (and re-parks if drifted to 0/1).
        // Avoid a second forced park — that used to open a long dead-zone on every appear.
        monitor.startMonitoring()
        print("🃏 [INSTAPICK] Volume armed at 50% (silent, no HUD) for carousel")
    }

    func finishOverlay(markSwapped: Bool) {
        if markSwapped, let slot = activeOverlaySlot {
            self.markSwapped(slot: slot)
        }
        activeOverlaySlot = nil
    }

    /// Completes the volume→drag reveal (test repaint via `swappedSlots`, or live IG swap).
    @MainActor
    func completeOverlayDrag() {
        guard let slot = activeOverlaySlot else { return }
        if isUsingLocalTestCarousel {
            finishOverlay(markSwapped: true)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            print("🃏 [INSTAPICK] Overlay finished (test) — slot \(slot) → \(slot)b")
            return
        }
        guard isLiveReady else {
            finishOverlay(markSwapped: false)
            return
        }
        Task {
            do {
                try await InstagramService.shared.swapInstapickSlot(slot: slot)
                await MainActor.run {
                    finishOverlay(markSwapped: true)
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    print("🃏 [INSTAPICK] Overlay finished (live) — slot \(slot) swapped on Instagram")
                }
            } catch {
                await MainActor.run {
                    finishOverlay(markSwapped: false)
                    print("❌ [INSTAPICK] Live swap failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func persistSwapped() {
        persistSwappedIfNeeded()
    }

    /// Persist only live reveals (needed for the restore banner). Never write practice swaps.
    private func persistSwappedIfNeeded() {
        let ud = UserDefaults.standard
        if isLiveReady && !PostPredictionTestMode.shared.isActive {
            ud.set(Array(swappedSlots).sorted(), forKey: Keys.swapped)
        } else if !isLiveReady {
            ud.removeObject(forKey: Keys.swapped)
        }
        // Test mode: keep any prior live disk swaps untouched so restore still works later.
    }

    private func loadBundled(_ name: String) -> UIImage? {
        let extensions = ["png", "jpg", "jpeg", "PNG", "JPG"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "InstapickAssets"),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        if let root = Bundle.main.resourceURL {
            for ext in extensions {
                let url = root.appendingPathComponent("InstapickAssets/\(name).\(ext)")
                if let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
            }
        }
        if let image = UIImage(named: name) { return image }
        for ext in extensions {
            if let path = Bundle.main.path(forResource: name, ofType: ext),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
}
