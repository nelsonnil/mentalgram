import Foundation
import SwiftUI
import Combine

// MARK: - Instagram Models

struct InstagramSession: Codable {
    var sessionId: String
    var csrfToken: String
    var userId: String
    var username: String
    var isLoggedIn: Bool
    
    static var empty: InstagramSession {
        InstagramSession(sessionId: "", csrfToken: "", userId: "", username: "", isLoggedIn: false)
    }
}

struct InstagramMedia: Identifiable, Codable {
    let id: String          // media_pk
    let mediaId: String     // media_id (pk)
    let imageURL: String
    let caption: String
    let takenAt: Date?
    var isArchived: Bool
    
    var thumbnailURL: URL? {
        URL(string: imageURL)
    }
}

struct InstagramFollower: Codable {
    let userId: String
    let username: String
    let fullName: String
    let profilePicURL: String?
}

// MARK: - Instagram Profile Models

struct UserSearchResult: Identifiable {
    let id: String
    let userId: String
    let username: String
    let fullName: String
    let profilePicURL: String
    let isVerified: Bool
    
    init(userId: String, username: String, fullName: String, profilePicURL: String, isVerified: Bool) {
        self.id = userId
        self.userId = userId
        self.username = username
        self.fullName = fullName
        self.profilePicURL = profilePicURL
        self.isVerified = isVerified
    }
}

struct InstagramProfile: Codable {
    let userId: String
    let username: String
    let fullName: String
    let biography: String
    let externalUrl: String?
    let profilePicURL: String
    let isVerified: Bool
    let isPrivate: Bool
    let followerCount: Int
    let followingCount: Int
    let mediaCount: Int
    let followedBy: [InstagramFollower]  // "Followed by X, Y and Z others"
    var isFollowing: Bool  // Si el usuario autenticado sigue a este perfil
    var isFollowRequested: Bool  // Si hay solicitud de follow pendiente (para perfiles privados)
    
    // Cache info
    var cachedAt: Date
    var cachedMediaURLs: [String]  // URLs of cached media thumbnails
}

struct InstagramMediaItem: Identifiable, Codable {
    let id: String
    let mediaId: String
    let imageURL: String
    let videoURL: String? // NEW: Video URL for playback
    let caption: String?
    let takenAt: Date?
    let likeCount: Int?
    let commentCount: Int?
    let mediaType: MediaType
    
    enum MediaType: String, Codable {
        case photo = "photo"
        case video = "video"
        case carousel = "carousel"
    }
}

// MARK: - Alphabet Type

enum AlphabetType: String, Codable, CaseIterable {
    case latin = "latin"
    case cyrillic = "cyrillic"
    case greek = "greek"
    case arabic = "arabic"
    case hebrew = "hebrew"
    case hiragana = "hiragana"
    case katakana = "katakana"
    
    var displayName: String {
        switch self {
        case .latin: return "Latin (A-Z)"
        case .cyrillic: return "Cyrillic (А-Я)"
        case .greek: return "Greek (Α-Ω)"
        case .arabic: return "Arabic (أ-ي)"
        case .hebrew: return "Hebrew (א-ת)"
        case .hiragana: return "Hiragana (あ-ん)"
        case .katakana: return "Katakana (ア-ン)"
        }
    }
    
    var flag: String {
        switch self {
        case .latin: return "🌍"
        case .cyrillic: return "🇷🇺"
        case .greek: return "🇬🇷"
        case .arabic: return "🇸🇦"
        case .hebrew: return "🇮🇱"
        case .hiragana: return "🇯🇵"
        case .katakana: return "🇯🇵"
        }
    }
    
    var characters: [String] {
        switch self {
        case .latin:
            return ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        case .cyrillic:
            return ["А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ъ","Ы","Ь","Э","Ю","Я"]
        case .greek:
            return ["Α","Β","Γ","Δ","Ε","Ζ","Η","Θ","Ι","Κ","Λ","Μ","Ν","Ξ","Ο","Π","Ρ","Σ","Τ","Υ","Φ","Χ","Ψ","Ω"]
        case .arabic:
            return ["ا","ب","ت","ث","ج","ح","خ","د","ذ","ر","ز","س","ش","ص","ض","ط","ظ","ع","غ","ف","ق","ك","ل","م","ن","ه","و","ي"]
        case .hebrew:
            return ["א","ב","ג","ד","ה","ו","ז","ח","ט","י","כ","ל","מ","נ","ס","ע","פ","צ","ק","ר","ש","ת"]
        case .hiragana:
            return ["あ","い","う","え","お","か","き","く","け","こ","さ","し","す","せ","そ","た","ち","つ","て","と","な","に","ぬ","ね","の","は","ひ","ふ","へ","ほ","ま","み","む","め","も","や","ゆ","よ","ら","り","る","れ","ろ","わ","を","ん"]
        case .katakana:
            return ["ア","イ","ウ","エ","オ","カ","キ","ク","ケ","コ","サ","シ","ス","セ","ソ","タ","チ","ツ","テ","ト","ナ","ニ","ヌ","ネ","ノ","ハ","ヒ","フ","ヘ","ホ","マ","ミ","ム","メ","モ","ヤ","ユ","ヨ","ラ","リ","ル","レ","ロ","ワ","ヲ","ン"]
        }
    }
    
    var count: Int { characters.count }
    
    /// Find the index of a character in this alphabet (case-insensitive for latin)
    func indexFor(_ char: String) -> Int? {
        let upper = char.uppercased()
        return characters.firstIndex(of: upper) ?? characters.firstIndex(of: char)
    }
}

// MARK: - Set Models

enum SetType: String, Codable, CaseIterable {
    case word = "word"
    case number = "number"
    case custom = "custom"
    
    var icon: String {
        switch self {
        case .word: return "textformat.abc"
        case .number: return "number"
        case .custom: return "square.grid.2x2"
        }
    }
    
    var title: String {
        switch self {
        case .word: return "Word Reveal"
        case .number: return "Number Reveal"
        case .custom: return "Custom Set"
        }
    }
    
    var description: String {
        switch self {
        case .word: return "Multiple banks of letters (A-Z)"
        case .number: return "Multiple banks of digits (0-9)"
        case .custom: return "Single bank of custom images"
        }
    }
    
    /// Expected number of photos per bank
    func expectedPhotoCount(alphabet: AlphabetType?) -> Int {
        switch self {
        case .number: return 10  // 0-9
        case .word: return alphabet?.count ?? 26
        case .custom: return 0  // No fixed count
        }
    }
    
    /// Labels for each slot position
    func slotLabels(alphabet: AlphabetType?) -> [String] {
        switch self {
        case .number: return (0...9).map { "\($0)" }
        case .word: return alphabet?.characters ?? AlphabetType.latin.characters
        case .custom: return []
        }
    }
}

enum SetStatus: String, Codable {
    case ready = "ready"
    case uploading = "uploading"
    case paused = "paused"
    case error = "error"
    case completed = "completed"
    
    var label: String {
        switch self {
        case .ready: return "Ready to upload"
        case .uploading: return "Uploading..."
        case .paused: return "Paused"
        case .error: return "Error"
        case .completed: return "Uploaded"
        }
    }
    
    var color: Color {
        switch self {
        case .ready: return .blue
        case .uploading: return .orange
        case .paused: return .gray
        case .error: return .red
        case .completed: return .green
        }
    }
    
    var icon: String {
        switch self {
        case .ready: return "doc.badge.plus"
        case .uploading: return "arrow.up.circle"
        case .paused: return "pause.circle"
        case .error: return "exclamationmark.circle"
        case .completed: return "checkmark.circle"
        }
    }
}

struct PhotoSet: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: SetType
    var status: SetStatus
    var banks: [Bank]
    var photos: [SetPhoto]
    var createdAt: Date
    var completedAt: Date?
    var selectedAlphabet: AlphabetType?  // For Word Reveal: which alphabet to use
    
    var totalPhotos: Int {
        photos.count
    }
    
    var uploadedPhotos: Int {
        photos.filter { $0.mediaId != nil }.count
    }
    
    /// Expected number of unique photos per bank
    var expectedPhotosPerBank: Int {
        type.expectedPhotoCount(alphabet: selectedAlphabet)
    }
    
    /// Labels for each slot
    var slotLabels: [String] {
        type.slotLabels(alphabet: selectedAlphabet)
    }
}

struct Bank: Identifiable, Codable {
    let id: UUID
    var position: Int
    var name: String
}

enum PhotoUploadStatus: String, Codable {
    case pending = "pending"           // Not uploaded yet
    case uploading = "uploading"       // Uploading now
    case uploaded = "uploaded"         // Upload OK, waiting archive
    case archiving = "archiving"       // Archiving now
    case completed = "completed"       // Upload + Archive complete
    case error = "error"               // Failed (manual retry needed)
}

struct SetPhoto: Identifiable, Codable {
    let id: UUID
    var setId: UUID
    var bankId: UUID?
    var symbol: String
    var filename: String
    var imageData: Data?
    var mediaId: String?
    var isArchived: Bool
    var uploadDate: Date?
    var lastCommentId: String?
    var uploadStatus: PhotoUploadStatus
    var errorMessage: String?
    
    init(id: UUID, setId: UUID, bankId: UUID? = nil, symbol: String, filename: String, imageData: Data? = nil, mediaId: String? = nil, isArchived: Bool = false, uploadDate: Date? = nil, lastCommentId: String? = nil, uploadStatus: PhotoUploadStatus = .pending, errorMessage: String? = nil) {
        self.id = id
        self.setId = setId
        self.bankId = bankId
        self.symbol = symbol
        self.filename = filename
        self.imageData = imageData
        self.mediaId = mediaId
        self.isArchived = isArchived
        self.uploadDate = uploadDate
        self.lastCommentId = lastCommentId
        self.uploadStatus = uploadStatus
        self.errorMessage = errorMessage
    }
}

// MARK: - Activity Log

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let action: String
    let details: String
    let timestamp: Date
    
    init(action: String, details: String) {
        self.id = UUID()
        self.action = action
        self.details = details
        self.timestamp = Date()
    }
}

// MARK: - Secret Input Mask

enum MaskInputMode: String, Codable, CaseIterable {
    case latestFollower = "latest_follower"
    case customUsername = "custom_username"
    
    var displayName: String {
        switch self {
        case .latestFollower: return "Latest Follower"
        case .customUsername: return "Custom Username"
        }
    }
    
    var icon: String {
        switch self {
        case .latestFollower: return "person.badge.plus"
        case .customUsername: return "textformat.abc"
        }
    }
}

// MARK: - Secret Input Settings

class SecretInputSettings: ObservableObject {
    static let shared = SecretInputSettings()
    
    @Published var mode: MaskInputMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "secretInputMode")
        }
    }
    
    @Published var customUsername: String {
        didSet {
            UserDefaults.standard.set(customUsername, forKey: "secretInputCustomUsername")
        }
    }
    
    private init() {
        if let savedMode = UserDefaults.standard.string(forKey: "secretInputMode"),
           let mode = MaskInputMode(rawValue: savedMode) {
            self.mode = mode
        } else {
            self.mode = .latestFollower
        }
        
        self.customUsername = UserDefaults.standard.string(forKey: "secretInputCustomUsername") ?? ""
    }
    
    /// Get the mask text based on current mode
    func getMaskText(latestFollowerUsername: String?) -> String {
        switch mode {
        case .latestFollower:
            return latestFollowerUsername?.lowercased() ?? "user"
        case .customUsername:
            return customUsername.lowercased()
        }
    }
}

