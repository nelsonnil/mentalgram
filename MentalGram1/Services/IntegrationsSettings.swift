import Foundation
import Combine

// MARK: - Explore Spy Format

/// What data is sent to Inject 2.0 when the spectator views a profile in Explore.
enum ExploreSpyFormat: Int, CaseIterable {
    case followersOnly          = 0  // "1 234"
    case followersFollowing      = 1  // "1 234, 567"
    case nameFollowers           = 2  // "John Doe, 1 234"
    case nameFollowersFollowing  = 3  // "John Doe, 1 234, 567"

    var displayName: String {
        switch self {
        case .followersOnly:         return "Followers"
        case .followersFollowing:    return "Followers, Following"
        case .nameFollowers:         return "Name, Followers"
        case .nameFollowersFollowing: return "Name, Followers, Following"
        }
    }

    var example: String {
        switch self {
        case .followersOnly:         return "e.g. \"1 234\""
        case .followersFollowing:    return "e.g. \"1 234, 567\""
        case .nameFollowers:         return "e.g. \"John, 1 234\""
        case .nameFollowersFollowing: return "e.g. \"John, 1 234, 567\""
        }
    }
}

// MARK: - AI Screen Detection Mode

enum AIScreenDetectionMode: String, CaseIterable {
    case vision = "vision"
    case likes = "likes"
    case visualMatch = "visual_match"

    var displayName: String {
        switch self {
        case .vision: return "AI Camera"
        case .likes: return "Likes"
        case .visualMatch: return "Visual Match"
        }
    }

    var description: String {
        switch self {
        case .vision: return "Photo reads public profile name, then detect +1 like"
        case .likes: return "Latest follower snapshot + detect +1 like"
        case .visualMatch: return "Photo reads profile, then OpenAI matches against post thumbnails"
        }
    }
}

enum AIScreenRevealAnimationStyle: String, CaseIterable {
    case energyLines = "energy_lines"
    case signalGhost = "signal_ghost"
    case gridPossession = "grid_possession"

    var displayName: String {
        switch self {
        case .energyLines: return "Energy Lines"
        case .signalGhost: return "Signal Ghost"
        case .gridPossession: return "Grid Possession"
        }
    }

    var description: String {
        switch self {
        case .energyLines: return "Fine electric lines and mysterious interference"
        case .signalGhost: return "Analog TV distortion with spectral flashes"
        case .gridPossession: return "The selected image invades the grid cell by cell"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .energyLines: return 1.55
        case .signalGhost: return 1.75
        case .gridPossession: return 2.35
        }
    }
}

enum TranspositionRevealMode: String, CaseIterable {
    case grid = "grid"
    case blackScreen = "black_screen"

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .blackScreen: return "Black Screen"
        }
    }
}

enum TranspositionCaptureMode: String, CaseIterable {
    case videoFrames = "video_frames"
    case hybridStillBurst = "hybrid_still_burst"

    var displayName: String {
        switch self {
        case .videoFrames: return "Video"
        case .hybridStillBurst: return "Hybrid burst"
        }
    }

    var description: String {
        switch self {
        case .videoFrames: return "Faster: pick best video frame after OCR layout is ready."
        case .hybridStillBurst: return "Sharper: video OCR for timing, then a 3-photo still burst for GPT."
        }
    }
}

// MARK: - Auto Input Mode

enum AutoInputMode: String, CaseIterable {
    case off        = "off"
    case clipboard  = "clipboard"
    case api        = "api"
    case ocr        = "ocr"
    case clockInput = "clockInput"

    var displayName: String {
        switch self {
        case .off:        return "Off"
        case .clipboard:  return "Clipboard"
        case .api:        return "API"
        case .ocr:        return "OCR"
        case .clockInput: return "Clock"
        }
    }

    var icon: String {
        switch self {
        case .off:        return "minus.circle"
        case .clipboard:  return "doc.on.clipboard"
        case .api:        return "bolt.fill"
        case .ocr:        return "camera.viewfinder"
        case .clockInput: return "hand.draw.fill"
        }
    }
}

// MARK: - Interface Kind

/// Exclusive performance input interfaces. Only ONE kind may be active across
/// the active set + all bio/note {textN} sources at the same time, because there is
/// a single capture per performance feeding every consumer, and that capture can only
/// produce ONE type of value via ONE device. The same kind may repeat across set/bio/
/// notes (one capture fills all). Different kinds conflict.
///
/// Lockscreen and Clock each have two variants because the same physical device can
/// only be in one mode at a time (numbers OR cards), so e.g. a Number Lockscreen and a
/// Card Lockscreen cannot coexist.
enum InterfaceKind: String, Hashable {
    case ocr, numberClock, cardClock, cardNumpad, numberLockscreen, cardLockscreen, fakeNotes

    var displayName: String {
        switch self {
        case .ocr:              return "Camera (OCR)"
        case .numberClock:      return "Number Clock"
        case .cardClock:        return "Card Clock"
        case .cardNumpad:       return "Numpad Card"
        case .numberLockscreen: return "Number Lockscreen"
        case .cardLockscreen:   return "Card Lockscreen"
        case .fakeNotes:        return "Notes (Typed)"
        }
    }
}

// MARK: - API Source

enum ApiSource: Int, CaseIterable {
    case none             = 0
    case inject           = 1
    case custom1          = 2
    case custom2          = 3
    case custom3          = 4
    case ocr              = 5   // interface: camera recognises a word/card
    case numberLockscreen = 6   // interface: fake lockscreen digit entry → number (was .lockscreen)
    case numberClock      = 7   // interface: black screen swipe → number
    case cardClock        = 8   // interface: black screen swipe → card (value+suit)
    case cardLockscreen   = 9   // interface: fake lockscreen card code → card (value+suit)
    case cardNumpad       = 10  // interface: black screen tap-to-show card selector
    case fakeNotes        = 11  // interface: iOS Notes lookalike, confirm by face-down

    var displayName: String {
        switch self {
        case .none:             return "None"
        case .inject:           return "Inject"
        case .custom1:          return IntegrationsSettings.shared.customApi1Name.isEmpty ? "API 1" : IntegrationsSettings.shared.customApi1Name
        case .custom2:          return IntegrationsSettings.shared.customApi2Name.isEmpty ? "API 2" : IntegrationsSettings.shared.customApi2Name
        case .custom3:          return IntegrationsSettings.shared.customApi3Name.isEmpty ? "API 3" : IntegrationsSettings.shared.customApi3Name
        case .ocr:              return "OCR"
        case .numberLockscreen: return "Number Lockscreen"
        case .numberClock:      return "Number Clock"
        case .cardClock:        return "Card Clock"
        case .cardLockscreen:   return "Card Lockscreen"
        case .cardNumpad:       return "Numpad Card"
        case .fakeNotes:        return "Notes Input"
        }
    }

    /// The exclusive interface kind this source requires (nil for polled API / none).
    var interfaceKind: InterfaceKind? {
        switch self {
        case .ocr:              return .ocr
        case .numberLockscreen: return .numberLockscreen
        case .numberClock:      return .numberClock
        case .cardClock:        return .cardClock
        case .cardLockscreen:   return .cardLockscreen
        case .cardNumpad:       return .cardNumpad
        case .fakeNotes:        return .fakeNotes
        default:                return nil
        }
    }

    /// Interface-family sources need an exclusive fullscreen UI / device event.
    var isInterfaceInput: Bool { interfaceKind != nil }

    /// Only API sources are polled; OCR and the clock/lockscreen interfaces are event-driven.
    var isPolled: Bool { self != .none && interfaceKind == nil }
}

struct ApiFetchedValue {
    let value: String
    let changeToken: String
}

// MARK: - IntegrationsSettings

final class IntegrationsSettings: ObservableObject {
    static let shared = IntegrationsSettings()

    static let defaultAIScreenDetectionPrompt = """
    Analyze this photo of an Instagram screen. Identify the AUTHOR of the visible post. Return ONLY valid JSON:
    {"platform":"instagram","isInstagramPost":true,"username":"","usernameCandidates":[],"displayName":"","dateText":"","relativeDate":"","visibleLikeText":"","visibleCommentText":"","visibleShareText":"","captionVisible":"","imageTextVisible":"","visualDescription":"","mainObjects":[],"peopleVisible":[],"locationText":"","postType":"image|carousel|video|reel|unknown","confidence":0.0,"missingOrUnclear":[]}
    CRITICAL: read the EXACT AUTHOR username from the post header (next to the avatar or under the Posts navigation title in any language). NEVER use usernames from like-rows, comments, music, buttons, or count units (mil/k/thousand/etc.). Preserve dots, underscores, numbers and exact spelling. Read exact like/comment/reshare counters into visibleLikeText/visibleCommentText/visibleShareText — icon order is heart→bubble→repost arrows→plane. If the heart has NO digit, leave visibleLikeText empty and put the bubble number in comments and the repost number in shares (never shift them left into likes). "Liked by…" text can appear even when like count is hidden. For Reels/videos, also read the title/caption under the username with highest priority; do not rely on thumbnail/frame similarity. If caption is missing, leave captionVisible empty and do NOT put comment authors into username. If unsure of the exact author username, leave username and usernameCandidates empty.
    """

    // Inject (receive — 11z.co)
    @Published var injectID: String {
        didSet { UserDefaults.standard.set(injectID, forKey: "integ_injectID") }
    }

    // Explore Spy — sends searched-profile data to Inject 2.0 (gg0.us)
    @Published var exploreSpyEnabled: Bool {
        didSet { UserDefaults.standard.set(exploreSpyEnabled, forKey: "integ_exploreSpyEnabled") }
    }
    @Published var exploreSpy2InjectId: String {
        didSet { UserDefaults.standard.set(exploreSpy2InjectId, forKey: "integ_exploreSpy2InjectId") }
    }
    @Published var exploreSpyFormat: ExploreSpyFormat {
        didSet { UserDefaults.standard.set(exploreSpyFormat.rawValue, forKey: "integ_exploreSpyFormat") }
    }

    /// PROVISIONAL: hide Transposition (settings, guide, runtime) until the feature ships.
    /// Flip to `true` to surface the PRO card again.
    static let transpositionFeatureEnabled = false

    // AI screen detection — camera photo of spectator phone → OpenAI Vision → Instagram post match.
    @Published var aiScreenDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(aiScreenDetectionEnabled, forKey: "integ_aiScreenDetectionEnabled") }
    }
    @Published var aiScreenDetectionMode: AIScreenDetectionMode {
        didSet { UserDefaults.standard.set(aiScreenDetectionMode.rawValue, forKey: "integ_aiScreenDetectionMode") }
    }
    @Published var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: "integ_openAIAPIKey") }
    }
    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "integ_openAIModel") }
    }
    @Published var aiScreenDetectionPrompt: String {
        didSet { UserDefaults.standard.set(aiScreenDetectionPrompt, forKey: "integ_aiScreenDetectionPrompt") }
    }
    @Published var aiScreenCandidateLimit: Int {
        didSet { UserDefaults.standard.set(aiScreenCandidateLimit, forKey: "integ_aiScreenCandidateLimit") }
    }
    @Published var aiScreenCameraZoom: Double {
        didSet {
            let clamped = Self.clampedAIScreenCameraZoom(aiScreenCameraZoom)
            if clamped != aiScreenCameraZoom {
                aiScreenCameraZoom = clamped
                return
            }
            UserDefaults.standard.set(aiScreenCameraZoom, forKey: "integ_aiScreenCameraZoom")
        }
    }
    @Published var aiScreenVerifyLatestFollower: Bool {
        didSet { UserDefaults.standard.set(aiScreenVerifyLatestFollower, forKey: "integ_aiScreenVerifyLatestFollower") }
    }
    @Published var aiScreenRevealAnimationEnabled: Bool {
        didSet { UserDefaults.standard.set(aiScreenRevealAnimationEnabled, forKey: "integ_aiScreenRevealAnimationEnabled") }
    }
    @Published var aiScreenRevealAnimationStyle: AIScreenRevealAnimationStyle {
        didSet { UserDefaults.standard.set(aiScreenRevealAnimationStyle.rawValue, forKey: "integ_aiScreenRevealAnimationStyle") }
    }
    @Published var transpositionRevealMode: TranspositionRevealMode {
        didSet { UserDefaults.standard.set(transpositionRevealMode.rawValue, forKey: "integ_transpositionRevealMode") }
    }
    @Published var transpositionCaptureMode: TranspositionCaptureMode {
        didSet { UserDefaults.standard.set(transpositionCaptureMode.rawValue, forKey: "integ_transpositionCaptureMode") }
    }
    @Published var transpositionSaveSelectedCaptureToPhotos: Bool {
        didSet { UserDefaults.standard.set(transpositionSaveSelectedCaptureToPhotos, forKey: "integ_transpositionSaveSelectedCaptureToPhotos") }
    }
    @Published var transpositionDimBlackScreenBrightness: Bool {
        didSet { UserDefaults.standard.set(transpositionDimBlackScreenBrightness, forKey: "integ_transpositionDimBlackScreenBrightness") }
    }
    @Published var transpositionBlackScreenReadySoundEnabled: Bool {
        didSet { UserDefaults.standard.set(transpositionBlackScreenReadySoundEnabled, forKey: "integ_transpositionBlackScreenReadySoundEnabled") }
    }

    // Custom API names (user-defined labels shown in pickers)
    @Published var customApi1Name: String {
        didSet { UserDefaults.standard.set(customApi1Name, forKey: "integ_custom1Name") }
    }
    @Published var customApi2Name: String {
        didSet { UserDefaults.standard.set(customApi2Name, forKey: "integ_custom2Name") }
    }
    @Published var customApi3Name: String {
        didSet { UserDefaults.standard.set(customApi3Name, forKey: "integ_custom3Name") }
    }

    // Custom APIs
    @Published var customApi1Url: String {
        didSet { UserDefaults.standard.set(customApi1Url, forKey: "integ_custom1Url") }
    }
    @Published var customApi1Field: String {
        didSet { UserDefaults.standard.set(customApi1Field, forKey: "integ_custom1Field") }
    }
    @Published var customApi2Url: String {
        didSet { UserDefaults.standard.set(customApi2Url, forKey: "integ_custom2Url") }
    }
    @Published var customApi2Field: String {
        didSet { UserDefaults.standard.set(customApi2Field, forKey: "integ_custom2Field") }
    }
    @Published var customApi3Url: String {
        didSet { UserDefaults.standard.set(customApi3Url, forKey: "integ_custom3Url") }
    }
    @Published var customApi3Field: String {
        didSet { UserDefaults.standard.set(customApi3Field, forKey: "integ_custom3Field") }
    }

    // Selected source per target ("bio", "note", "pp") — legacy single-source (maps to text1)
    @Published var bioApiSource: ApiSource {
        didSet { UserDefaults.standard.set(bioApiSource.rawValue, forKey: "integ_bioApiSource") }
    }
    @Published var noteApiSource: ApiSource {
        didSet { UserDefaults.standard.set(noteApiSource.rawValue, forKey: "integ_noteApiSource") }
    }
    @Published var ppApiSource: ApiSource {
        didSet { UserDefaults.standard.set(ppApiSource.rawValue, forKey: "integ_ppApiSource") }
    }

    // Per-placeholder sources for Note template
    @Published var noteText1Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText1Source.rawValue, forKey: "integ_noteText1Source") }
    }
    @Published var noteText2Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText2Source.rawValue, forKey: "integ_noteText2Source") }
    }
    @Published var noteText3Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText3Source.rawValue, forKey: "integ_noteText3Source") }
    }
    @Published var noteText4Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText4Source.rawValue, forKey: "integ_noteText4Source") }
    }
    @Published var noteText5Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText5Source.rawValue, forKey: "integ_noteText5Source") }
    }

    // Per-placeholder sources for Bio template
    @Published var bioText1Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText1Source.rawValue, forKey: "integ_bioText1Source") }
    }
    @Published var bioText2Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText2Source.rawValue, forKey: "integ_bioText2Source") }
    }
    @Published var bioText3Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText3Source.rawValue, forKey: "integ_bioText3Source") }
    }
    @Published var bioText4Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText4Source.rawValue, forKey: "integ_bioText4Source") }
    }
    @Published var bioText5Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText5Source.rawValue, forKey: "integ_bioText5Source") }
    }

    private init() {
        let ud = UserDefaults.standard
        injectID              = ud.string(forKey: "integ_injectID")              ?? ""
        exploreSpyEnabled     = ud.bool(forKey: "integ_exploreSpyEnabled")
        exploreSpy2InjectId   = ud.string(forKey: "integ_exploreSpy2InjectId")  ?? ""
        exploreSpyFormat      = ExploreSpyFormat(rawValue: ud.integer(forKey: "integ_exploreSpyFormat")) ?? .nameFollowersFollowing
        // Force-off while Transposition is hidden so a previous enable can't fire in Performance.
        aiScreenDetectionEnabled = Self.transpositionFeatureEnabled
            ? ud.bool(forKey: "integ_aiScreenDetectionEnabled")
            : false
        aiScreenDetectionMode = .visualMatch
        openAIAPIKey          = ud.string(forKey: "integ_openAIAPIKey") ?? ""
        openAIModel           = ud.string(forKey: "integ_openAIModel") ?? "gpt-4o-mini"
        aiScreenDetectionPrompt = ud.string(forKey: "integ_aiScreenDetectionPrompt") ?? Self.defaultAIScreenDetectionPrompt
        aiScreenCandidateLimit = 12
        let savedZoom = ud.double(forKey: "integ_aiScreenCameraZoom")
        aiScreenCameraZoom = savedZoom == 0 ? 1.4 : Self.clampedAIScreenCameraZoom(savedZoom)
        aiScreenVerifyLatestFollower = ud.object(forKey: "integ_aiScreenVerifyLatestFollower") as? Bool ?? true
        aiScreenRevealAnimationEnabled = ud.object(forKey: "integ_aiScreenRevealAnimationEnabled") as? Bool ?? true
        aiScreenRevealAnimationStyle = AIScreenRevealAnimationStyle(rawValue: ud.string(forKey: "integ_aiScreenRevealAnimationStyle") ?? "") ?? .energyLines
        transpositionRevealMode = TranspositionRevealMode(rawValue: ud.string(forKey: "integ_transpositionRevealMode") ?? "") ?? .grid
        // Hybrid still burst is disabled (shutter sound). Always coerce to silent video frames.
        transpositionCaptureMode = .videoFrames
        transpositionSaveSelectedCaptureToPhotos = ud.bool(forKey: "integ_transpositionSaveSelectedCaptureToPhotos")
        transpositionDimBlackScreenBrightness = ud.bool(forKey: "integ_transpositionDimBlackScreenBrightness")
        transpositionBlackScreenReadySoundEnabled = ud.object(forKey: "integ_transpositionBlackScreenReadySoundEnabled") as? Bool ?? true
        customApi1Name  = ud.string(forKey: "integ_custom1Name")    ?? ""
        customApi2Name  = ud.string(forKey: "integ_custom2Name")    ?? ""
        customApi3Name  = ud.string(forKey: "integ_custom3Name")    ?? ""
        customApi1Url   = ud.string(forKey: "integ_custom1Url")     ?? ""
        customApi1Field = ud.string(forKey: "integ_custom1Field")   ?? ""
        customApi2Url   = ud.string(forKey: "integ_custom2Url")     ?? ""
        customApi2Field = ud.string(forKey: "integ_custom2Field")   ?? ""
        customApi3Url   = ud.string(forKey: "integ_custom3Url")     ?? ""
        customApi3Field = ud.string(forKey: "integ_custom3Field")   ?? ""
        bioApiSource    = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteApiSource   = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        ppApiSource     = ApiSource(rawValue: ud.integer(forKey: "integ_ppApiSource"))   ?? .none
        // Per-placeholder sources — migrate legacy single-source on first launch
        let legacyNote  = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        let legacyBio   = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteText1Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText1Source")) ?? legacyNote
        noteText2Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText2Source")) ?? .none
        noteText3Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText3Source")) ?? .none
        noteText4Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText4Source")) ?? .none
        noteText5Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText5Source")) ?? .none
        bioText1Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText1Source"))  ?? legacyBio
        bioText2Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText2Source"))  ?? .none
        bioText3Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText3Source"))  ?? .none
        bioText4Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText4Source"))  ?? .none
        bioText5Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText5Source"))  ?? .none
    }

    /// Wider range for Video + Hybrid still framing (device may clamp further).
    static let aiScreenCameraZoomRange: ClosedRange<Double> = 1.0...3.0

    static func clampedAIScreenCameraZoom(_ value: Double) -> Double {
        min(max(value, aiScreenCameraZoomRange.lowerBound), aiScreenCameraZoomRange.upperBound)
    }

    // MARK: - Reload (call after iCloud restore)

    /// Re-reads all persisted values from UserDefaults.
    /// Must be called on the main thread after CloudBackupService.restoreFromCloud().
    func reloadFromUserDefaults() {
        let ud = UserDefaults.standard
        injectID              = ud.string(forKey: "integ_injectID")              ?? ""
        exploreSpyEnabled     = ud.bool(forKey: "integ_exploreSpyEnabled")
        exploreSpy2InjectId   = ud.string(forKey: "integ_exploreSpy2InjectId")  ?? ""
        exploreSpyFormat      = ExploreSpyFormat(rawValue: ud.integer(forKey: "integ_exploreSpyFormat")) ?? .nameFollowersFollowing
        // Force-off while Transposition is hidden so a previous enable can't fire in Performance.
        aiScreenDetectionEnabled = Self.transpositionFeatureEnabled
            ? ud.bool(forKey: "integ_aiScreenDetectionEnabled")
            : false
        aiScreenDetectionMode = .visualMatch
        openAIAPIKey          = ud.string(forKey: "integ_openAIAPIKey") ?? ""
        openAIModel           = ud.string(forKey: "integ_openAIModel") ?? "gpt-4o-mini"
        aiScreenDetectionPrompt = ud.string(forKey: "integ_aiScreenDetectionPrompt") ?? Self.defaultAIScreenDetectionPrompt
        aiScreenCandidateLimit = 12
        let savedZoom = ud.double(forKey: "integ_aiScreenCameraZoom")
        aiScreenCameraZoom = savedZoom == 0 ? 1.4 : Self.clampedAIScreenCameraZoom(savedZoom)
        aiScreenVerifyLatestFollower = ud.object(forKey: "integ_aiScreenVerifyLatestFollower") as? Bool ?? true
        aiScreenRevealAnimationEnabled = ud.object(forKey: "integ_aiScreenRevealAnimationEnabled") as? Bool ?? true
        aiScreenRevealAnimationStyle = AIScreenRevealAnimationStyle(rawValue: ud.string(forKey: "integ_aiScreenRevealAnimationStyle") ?? "") ?? .energyLines
        transpositionRevealMode = TranspositionRevealMode(rawValue: ud.string(forKey: "integ_transpositionRevealMode") ?? "") ?? .grid
        transpositionCaptureMode = .videoFrames
        transpositionSaveSelectedCaptureToPhotos = ud.bool(forKey: "integ_transpositionSaveSelectedCaptureToPhotos")
        transpositionDimBlackScreenBrightness = ud.bool(forKey: "integ_transpositionDimBlackScreenBrightness")
        transpositionBlackScreenReadySoundEnabled = ud.object(forKey: "integ_transpositionBlackScreenReadySoundEnabled") as? Bool ?? true
        customApi1Name  = ud.string(forKey: "integ_custom1Name")    ?? ""
        customApi2Name  = ud.string(forKey: "integ_custom2Name")    ?? ""
        customApi3Name  = ud.string(forKey: "integ_custom3Name")    ?? ""
        customApi1Url   = ud.string(forKey: "integ_custom1Url")     ?? ""
        customApi1Field = ud.string(forKey: "integ_custom1Field")   ?? ""
        customApi2Url   = ud.string(forKey: "integ_custom2Url")     ?? ""
        customApi2Field = ud.string(forKey: "integ_custom2Field")   ?? ""
        customApi3Url   = ud.string(forKey: "integ_custom3Url")     ?? ""
        customApi3Field = ud.string(forKey: "integ_custom3Field")   ?? ""
        bioApiSource    = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteApiSource   = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        ppApiSource     = ApiSource(rawValue: ud.integer(forKey: "integ_ppApiSource"))   ?? .none
        let legacyNote  = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        let legacyBio   = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteText1Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText1Source")) ?? legacyNote
        noteText2Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText2Source")) ?? .none
        noteText3Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText3Source")) ?? .none
        noteText4Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText4Source")) ?? .none
        noteText5Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText5Source")) ?? .none
        bioText1Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText1Source"))  ?? legacyBio
        bioText2Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText2Source"))  ?? .none
        bioText3Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText3Source"))  ?? .none
        bioText4Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText4Source"))  ?? .none
        bioText5Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText5Source"))  ?? .none
        objectWillChange.send()
        print("🔗 [INTEG] Reloaded integrations from UserDefaults after restore")
    }

    // MARK: - Fetch

    /// Returns the text fetched from the currently configured source for a given target.
    func fetchValue(for source: ApiSource) async -> String? {
        guard let payload = await fetchPayload(for: source) else { return nil }
        return payload.value
    }

    /// Returns the fetched value plus a token used for change detection.
    /// Inject exposes `count`, so we use it to avoid reacting to the last stored input on app launch.
    func fetchPayload(for source: ApiSource) async -> ApiFetchedValue? {
        switch source {
        case .none:    return nil
        case .inject:  return await loadInjectApiPayload(injectID: injectID)
        case .custom1: return await loadCustomApiPayload(url: customApi1Url, field: customApi1Field)
        case .custom2: return await loadCustomApiPayload(url: customApi2Url, field: customApi2Field)
        case .custom3: return await loadCustomApiPayload(url: customApi3Url, field: customApi3Field)
        // Interface-family sources are captured live at performance, never polled here.
        case .ocr, .numberLockscreen, .cardLockscreen, .numberClock, .cardClock, .cardNumpad, .fakeNotes: return nil
        }
    }

    func fetchBioValue()  async -> String? { await fetchValue(for: bioApiSource) }
    func fetchNoteValue() async -> String? { await fetchValue(for: noteApiSource) }
    func fetchPPValue()   async -> String? { await fetchValue(for: ppApiSource) }

    private func normalizedBioTemplateSlot(_ slot: Int? = nil) -> Int {
        let raw = slot ?? UserDefaults.standard.integer(forKey: "bio_active_slot")
        return min(max(raw, 0), 3)
    }

    private func bioSourceKey(templateSlot: Int, textSlot: Int) -> String {
        if templateSlot == 0 {
            return "integ_bioText\(textSlot)Source"
        }
        return "integ_bioTemplate\(templateSlot + 1)Text\(textSlot)Source"
    }

    private func bioSourceForTextSlot(_ textSlot: Int, templateSlot: Int? = nil) -> ApiSource {
        let slot = normalizedBioTemplateSlot(templateSlot)
        switch (slot, textSlot) {
        case (0, 1): return bioText1Source
        case (0, 2): return bioText2Source
        case (0, 3): return bioText3Source
        case (0, 4): return bioText4Source
        case (0, 5): return bioText5Source
        default:
            let key = bioSourceKey(templateSlot: slot, textSlot: textSlot)
            return ApiSource(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .none
        }
    }

    private func setBioSourceForTextSlot(_ source: ApiSource, textSlot: Int, templateSlot: Int? = nil) {
        let slot = normalizedBioTemplateSlot(templateSlot)
        switch (slot, textSlot) {
        case (0, 1): bioText1Source = source
        case (0, 2): bioText2Source = source
        case (0, 3): bioText3Source = source
        case (0, 4): bioText4Source = source
        case (0, 5): bioText5Source = source
        default:
            UserDefaults.standard.set(source.rawValue, forKey: bioSourceKey(templateSlot: slot, textSlot: textSlot))
            objectWillChange.send()
        }
    }

    func bioSources(forTemplateSlot slot: Int? = nil) -> [ApiSource] {
        (1...5).map { bioSourceForTextSlot($0, templateSlot: slot) }
    }

    func bioSource(for token: String, templateSlot: Int? = nil) -> ApiSource {
        bioSourceForTextSlot(Self.textSlot(for: token), templateSlot: templateSlot)
    }

    func setBioSource(_ source: ApiSource, for token: String, templateSlot: Int? = nil) {
        setBioSourceForTextSlot(source, textSlot: Self.textSlot(for: token), templateSlot: templateSlot)
    }

    private static func textSlot(for token: String) -> Int {
        switch token {
        case "{text2}": return 2
        case "{text3}": return 3
        case "{text4}": return 4
        case "{text5}": return 5
        default:        return 1
        }
    }

    /// Fetches all placeholder values for a given target ("note" or "bio") in parallel.
    /// Returns a dict: ["text1": value, ..., "text5": value] (only non-nil entries).
    /// Fetches API-polled placeholder values in parallel (skips .ocr — that is event-driven).
    /// Pass `ocrValues` to inject already-captured OCR words into the correct slots.
    func fetchTemplatePlaceholders(for target: String, ocrValues: [String: String] = [:]) async -> [String: String] {
        guard targetIsEnabled(target) else { return [:] }
        let sources = sourcesForTarget(target)
        let s1 = sources[0]
        let s2 = sources[1]
        let s3 = sources[2]
        let s4 = sources[3]
        let s5 = sources[4]

        async let v1 = s1.isPolled ? fetchValue(for: s1) : nil
        async let v2 = s2.isPolled ? fetchValue(for: s2) : nil
        async let v3 = s3.isPolled ? fetchValue(for: s3) : nil
        async let v4 = s4.isPolled ? fetchValue(for: s4) : nil
        async let v5 = s5.isPolled ? fetchValue(for: s5) : nil
        let (r1, r2, r3, r4, r5) = await (v1, v2, v3, v4, v5)

        var result: [String: String] = [:]
        if let r1 { result["text1"] = r1 }
        if let r2 { result["text2"] = r2 }
        if let r3 { result["text3"] = r3 }
        if let r4 { result["text4"] = r4 }
        if let r5 { result["text5"] = r5 }
        // Inject OCR-captured values for slots assigned to .ocr
        if s1 == .ocr, let v = ocrValues["text1"] { result["text1"] = v }
        if s2 == .ocr, let v = ocrValues["text2"] ?? ocrValues["text1"] { result["text2"] = v }
        if s3 == .ocr, let v = ocrValues["text3"] ?? ocrValues["text1"] { result["text3"] = v }
        if s4 == .ocr, let v = ocrValues["text4"] ?? ocrValues["text1"] { result["text4"] = v }
        if s5 == .ocr, let v = ocrValues["text5"] ?? ocrValues["text1"] { result["text5"] = v }
        return result
    }

    /// Returns true if any placeholder source is configured for the given target (excluding .none).
    func hasTemplateSources(for target: String) -> Bool {
        guard targetIsEnabled(target) else { return false }
        return activeTokenSourceEntries.contains { $0.target == target && $0.source != .none }
    }

    /// Returns which slot (1..5) is assigned to OCR for the given target, or nil if none.
    func ocrSlot(for target: String) -> Int? {
        guard targetIsEnabled(target) else { return nil }
        let sources = sourcesForTarget(target)
        return sources.enumerated().first { idx, source in
            source == .ocr && tokenIsUsed(target: target, token: "{text\(idx + 1)}")
        }.map { $0.offset + 1 }
    }

    // MARK: - Interface conflict validation
    //
    // Only ONE interface kind (OCR / Lockscreen / Number Clock / Card Clock) may be
    // active across the active set + all bio/note {textN} sources at the same time,
    // because each needs its own dedicated screen/event. Polled API sources (Inject,
    // API 1-3) never conflict and may be mixed freely.

    /// Interface kind required by the currently-active set (nil if none / api / grid).
    /// Lockscreen resolves to its number/card variant based on the set type, because the
    /// lockscreen produces a number for number/custom sets and a card for card sets.
    private func activeSetInterfaceKind() -> InterfaceKind? {
        guard let id = ActiveSetSettings.shared.activeSetId,
              let set = DataManager.shared.sets.first(where: { $0.id == id }) else { return nil }
        switch set.resolvedInputMethod {
        case .ocr:        return .ocr
        case .clockInput: return .numberClock
        case .cardClock:  return .cardClock
        case .numpadCard: return .cardNumpad
        case .lockscreen: return set.type == .card ? .cardLockscreen : .numberLockscreen
        case .fakeNotes:  return .fakeNotes
        default:          return nil
        }
    }

    func sourcesForTarget(_ target: String) -> [ApiSource] {
        target == "note"
            ? [noteText1Source, noteText2Source, noteText3Source, noteText4Source, noteText5Source]
            : bioSources()
    }

    /// Source entries for Notes and the currently active Bio template.
    private var allTokenSourceEntries: [(target: String, token: String, source: ApiSource)] {
        let bio = bioSources()
        return [("bio",  "{text1}", bio[0]),  ("bio",  "{text2}", bio[1]),  ("bio",  "{text3}", bio[2]),  ("bio",  "{text4}", bio[3]),  ("bio",  "{text5}", bio[4]),
                ("note", "{text1}", noteText1Source), ("note", "{text2}", noteText2Source), ("note", "{text3}", noteText3Source), ("note", "{text4}", noteText4Source), ("note", "{text5}", noteText5Source)]
    }

    /// Only entries whose token is currently present in the active template.
    /// This prevents stale hidden slots (e.g. user removed {text2}) from keeping
    /// Lockscreen/Clock/OCR blocked forever.
    private var activeTokenSourceEntries: [(target: String, token: String, source: ApiSource)] {
        allTokenSourceEntries.filter {
            targetIsEnabled($0.target) && tokenIsUsed(target: $0.target, token: $0.token)
        }
    }

    private func targetIsEnabled(_ target: String) -> Bool {
        let key = target == "note" ? "note_feature_enabled" : "bio_feature_enabled"
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func tokenIsUsed(target: String, token: String) -> Bool {
        let template = target == "note" ? noteTemplate : activeBioTemplate
        if token == "{text1}" {
            // Acrostic Mode bypasses the biography template entirely and feeds the
            // captured value directly into the acrostic engine. Therefore text1's
            // selected input source must remain active even when the bio field is empty.
            if target == "bio",
               UserDefaults.standard.bool(forKey: "bio_acrostic_enabled") {
                return true
            }
            return template.contains("{text1}") || template.contains("{word}")
        }
        return template.contains(token)
    }

    private var noteTemplate: String {
        UserDefaults.standard.string(forKey: "note_template") ?? ""
    }

    private var activeBioTemplate: String {
        switch UserDefaults.standard.integer(forKey: "bio_active_slot") {
        case 1:  return UserDefaults.standard.string(forKey: "bio_template_2") ?? ""
        case 2:  return UserDefaults.standard.string(forKey: "bio_template_3") ?? ""
        case 3:  return UserDefaults.standard.string(forKey: "bio_template_4") ?? ""
        default: return UserDefaults.standard.string(forKey: "bio_template") ?? ""
        }
    }

    /// Interface kinds currently in use, optionally excluding one token (the one being edited).
    func interfaceKindsInUse(excludingTarget: String? = nil, excludingToken: String? = nil) -> Set<InterfaceKind> {
        var kinds = Set<InterfaceKind>()
        if let k = activeSetInterfaceKind() { kinds.insert(k) }
        for e in activeTokenSourceEntries {
            if e.target == excludingTarget && e.token == excludingToken { continue }
            if let k = e.source.interfaceKind { kinds.insert(k) }
        }
        return kinds
    }

    /// Whether `candidate` can be assigned to (target, token) without an interface conflict.
    /// Polled / none sources (.inject, .custom1/2/3) are always allowed and can be mixed freely.
    /// The same interface kind may be reused across set/bio/note because one capture
    /// feeds all consumers. Different interface kinds conflict (OCR vs Clock, number
    /// lockscreen vs card lockscreen, number clock vs card clock, etc.).
    func canSelectSource(_ candidate: ApiSource, target: String, token: String) -> Bool {
        guard let incomingKind = candidate.interfaceKind else { return true }
        let others = interfaceKindsInUse(excludingTarget: target, excludingToken: token)
        return others.isEmpty || others.allSatisfy { $0 == incomingKind }
    }

    /// The interface kind already established elsewhere that blocks different interface
    /// selections for (target, token), or nil if none is established yet.
    func blockingInterfaceKind(target: String, token: String) -> InterfaceKind? {
        interfaceKindsInUse(excludingTarget: target, excludingToken: token).first
    }

    /// Human-readable list of locations where interface-family inputs are currently
    /// configured (excluding the slot being edited). Used to build conflict alert messages.
    /// Returns e.g. ["Active Set (Lockscreen)", "Biography {text2} (Number Clock)"]
    func conflictLocations(excludingTarget: String, excludingToken: String) -> [String] {
        var locations: [String] = []
        if let k = activeSetInterfaceKind() {
            let name = DataManager.shared.sets
                .first(where: { $0.id == ActiveSetSettings.shared.activeSetId })?.name ?? "Active Set"
            locations.append("\(name) (\(k.displayName))")
        }
        let targetLabels = ["bio": "Biography", "note": "Notes"]
        for e in activeTokenSourceEntries {
            if e.target == excludingTarget && e.token == excludingToken { continue }
            guard let k = e.source.interfaceKind else { continue }
            let tLabel = targetLabels[e.target] ?? e.target
            locations.append("\(tLabel) \(e.token) (\(k.displayName))")
        }
        return locations
    }

    /// Human-readable Bio/Notes locations whose active template slots use one of
    /// the requested interface kinds. Used by Performance entry gates such as
    /// List Input, which cannot share the first fullscreen/private input screen.
    func bioNoteInterfaceLocations(matching kinds: Set<InterfaceKind>) -> [String] {
        let targetLabels = ["bio": "Biography", "note": "Notes"]
        return activeTokenSourceEntries.compactMap { entry in
            guard let kind = entry.source.interfaceKind, kinds.contains(kind) else { return nil }
            let target = targetLabels[entry.target] ?? entry.target
            return "\(target) \(entry.token) (\(kind.displayName))"
        }
    }

    /// Clears all interface-family sources across bio and notes that conflict with
    /// `kind`, then assigns `kind`'s matching source to the given (target, token).
    /// Call this when the user taps "Continue" on the conflict alert.
    func resolveConflictAndSet(source: ApiSource, target: String, token: String) {
        guard let incomingKind = source.interfaceKind else {
            // Not an interface source — just assign directly
            setSource(source, target: target, token: token)
            return
        }
        // Clear any active slot whose interface kind differs from incomingKind.
        // Hidden template slots are ignored so stale removed {textN} sources do not
        // keep influencing current selections.
        for e in activeTokenSourceEntries {
            guard let k = e.source.interfaceKind, k != incomingKind else { continue }
            setSource(.none, target: e.target, token: e.token)
        }
        // Assign the new source to the edited slot
        setSource(source, target: target, token: token)
    }

    /// Sets a single source slot by (target, token).
    func setSource(_ source: ApiSource, target: String, token: String) {
        switch (target, token) {
        case ("note", "{text1}"): noteText1Source = source
        case ("note", "{text2}"): noteText2Source = source
        case ("note", "{text3}"): noteText3Source = source
        case ("note", "{text4}"): noteText4Source = source
        case ("note", "{text5}"): noteText5Source = source
        case ("bio", _): setBioSource(source, for: token)
        default: break
        }
    }

    // MARK: - Inject 2.0 Send (gg0.us)

    /// Sends `value` to Inject 2.0. Returns `true` on HTTP 200.
    @discardableResult
    func sendToInject2(id: String, value: String) async -> Bool {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, !value.isEmpty else { return false }
        guard let url = URL(string: "https://gg0.us/_w/\(cleanId)/selection?") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["value": value, "source": "web"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            print(ok
                  ? "✅ [INJECT2] Sent '\(value)' → id:\(cleanId)"
                  : "❌ [INJECT2] Send failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1)) value:'\(value)' id:\(cleanId)")
            return ok
        } catch {
            print("❌ [INJECT2] Network error: \(error)")
            return false
        }
    }

    /// Formats and sends an Instagram profile to Inject 2.0 using the Explore Spy settings.
    /// Fires-and-forgets; call from a Task context.
    func sendExploreProfile(username: String, fullName: String, followers: Int, following: Int) async {
        guard exploreSpyEnabled else { return }
        let id = exploreSpy2InjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            print("⚠️ [EXPLORE SPY] Inject 2.0 ID is empty — configure it in Settings → Integrations")
            return
        }
        let displayName = fullName.isEmpty ? username : fullName
        let fmtFollowers = formatCount(followers)
        let fmtFollowing = formatCount(following)
        let value: String
        switch exploreSpyFormat {
        case .followersOnly:
            value = fmtFollowers
        case .followersFollowing:
            value = "\(fmtFollowers), \(fmtFollowing)"
        case .nameFollowers:
            value = "\(displayName), \(fmtFollowers)"
        case .nameFollowersFollowing:
            value = "\(displayName), \(fmtFollowers), \(fmtFollowing)"
        }
        LogManager.shared.info("Explore Spy → sending '@\(username)' data to Inject2 id:\(id) value:'\(value)'", category: .general)
        await sendToInject2(id: id, value: value)
    }

    /// Formats an Instagram count with a thousands separator (space), e.g. 1234 → "1 234".
    private func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Inject (11z.co)

    func loadInjectApi(injectID: String) async -> String? {
        await loadInjectApiPayload(injectID: injectID)?.value
    }

    func loadInjectApiPayload(injectID: String) async -> ApiFetchedValue? {
        let cleanID = injectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return nil }
        guard let url = URL(string: "https://11z.co/_w/\(cleanID)/selection") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let token = Self.injectChangeToken(from: json)
                for key in ["value", "word", "selection", "input", "text"] {
                    if let value = Self.nonEmptyString(from: json[key]) {
                        return ApiFetchedValue(value: value, changeToken: token ?? value)
                    }
                }
                for (key, val) in json {
                    if let s = Self.nonEmptyString(from: val), !Self.injectMetadataKeys.contains(key) {
                        return ApiFetchedValue(value: s, changeToken: token ?? s)
                    }
                }
            }
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return ApiFetchedValue(value: text, changeToken: text)
            }
            return nil
        } catch {
            print("❌ [INTEG] Inject fetch error: \(error)")
            return nil
        }
    }

    // MARK: - Custom API

    func loadCustomApi(url: String, field: String) async -> String? {
        await loadCustomApiPayload(url: url, field: field)?.value
    }

    func loadCustomApiPayload(url: String, field: String) async -> ApiFetchedValue? {
        let cleanUrl   = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty, !cleanField.isEmpty,
              let apiURL = URL(string: cleanUrl) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            if let v = json[cleanField] as? String {
                return ApiFetchedValue(value: v, changeToken: v)
            }
            if let v = json[cleanField] {
                let value = String(describing: v)
                return ApiFetchedValue(value: value, changeToken: value)
            }
            return nil
        } catch {
            print("❌ [INTEG] Custom API fetch error: \(error)")
            return nil
        }
    }

    private static let injectMetadataKeys: Set<String> = [
        "count", "id", "status", "created_at", "updated_at", "timestamp"
    ]

    private static func injectChangeToken(from json: [String: Any]) -> String? {
        guard let rawCount = json["count"] else { return nil }
        if let count = rawCount as? Int {
            return "count:\(count)"
        }
        if let count = rawCount as? Int64 {
            return "count:\(count)"
        }
        if let count = rawCount as? Double {
            return "count:\(count)"
        }
        let token = String(describing: rawCount).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : "count:\(token)"
    }

    private static func nonEmptyString(from value: Any?) -> String? {
        guard let value else { return nil }
        let string: String
        if let value = value as? String {
            string = value
        } else if value is NSNull {
            return nil
        } else {
            string = String(describing: value)
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
