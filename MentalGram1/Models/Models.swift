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

struct InstagramFollower: Codable, Identifiable, Equatable {
    var id: String { userId }
    let userId: String
    let username: String
    let fullName: String
    let profilePicURL: String?
}

struct InstagramHighlight: Codable, Identifiable {
    let id: String        // e.g. "highlight:17234567"
    let title: String
    let coverImageURL: String
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

struct InstagramProfile: Codable, Identifiable {
    var id: String { userId }
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
    var isFollowing: Bool
    var isFollowRequested: Bool
    
    // Cache info
    var cachedAt: Date
    var cachedMediaURLs: [String]           // Posts grid thumbnails
    var cachedReelURLs: [String]            // Reels tab thumbnails
    var cachedTaggedURLs: [String]          // Tagged tab thumbnails
    var cachedHighlights: [InstagramHighlight] // Story highlights (title + cover image)
    var cachedMediaItems: [InstagramMediaItem] // Full items for post viewer (likes, date, caption)

    // Backward-compatible decoding (old cache files won't have newer fields)
    enum CodingKeys: String, CodingKey {
        case userId, username, fullName, biography, externalUrl, profilePicURL
        case isVerified, isPrivate, followerCount, followingCount, mediaCount
        case followedBy, isFollowing, isFollowRequested, cachedAt
        case cachedMediaURLs, cachedReelURLs, cachedTaggedURLs, cachedHighlights, cachedMediaItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId             = try c.decode(String.self, forKey: .userId)
        username           = try c.decode(String.self, forKey: .username)
        fullName           = try c.decode(String.self, forKey: .fullName)
        biography          = try c.decode(String.self, forKey: .biography)
        externalUrl        = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        profilePicURL      = try c.decode(String.self, forKey: .profilePicURL)
        isVerified         = try c.decode(Bool.self, forKey: .isVerified)
        isPrivate          = try c.decode(Bool.self, forKey: .isPrivate)
        followerCount      = try c.decode(Int.self, forKey: .followerCount)
        followingCount     = try c.decode(Int.self, forKey: .followingCount)
        mediaCount         = try c.decode(Int.self, forKey: .mediaCount)
        followedBy         = try c.decode([InstagramFollower].self, forKey: .followedBy)
        isFollowing        = try c.decode(Bool.self, forKey: .isFollowing)
        isFollowRequested  = try c.decode(Bool.self, forKey: .isFollowRequested)
        cachedAt           = try c.decode(Date.self, forKey: .cachedAt)
        cachedMediaURLs    = try c.decode([String].self, forKey: .cachedMediaURLs)
        cachedReelURLs     = try c.decodeIfPresent([String].self, forKey: .cachedReelURLs) ?? []
        cachedTaggedURLs   = try c.decodeIfPresent([String].self, forKey: .cachedTaggedURLs) ?? []
        cachedHighlights   = try c.decodeIfPresent([InstagramHighlight].self, forKey: .cachedHighlights) ?? []
        cachedMediaItems   = try c.decodeIfPresent([InstagramMediaItem].self, forKey: .cachedMediaItems) ?? []
    }

    init(userId: String, username: String, fullName: String, biography: String,
         externalUrl: String?, profilePicURL: String, isVerified: Bool, isPrivate: Bool,
         followerCount: Int, followingCount: Int, mediaCount: Int,
         followedBy: [InstagramFollower], isFollowing: Bool, isFollowRequested: Bool,
         cachedAt: Date, cachedMediaURLs: [String],
         cachedReelURLs: [String] = [], cachedTaggedURLs: [String] = [],
         cachedHighlights: [InstagramHighlight] = [],
         cachedMediaItems: [InstagramMediaItem] = []) {
        self.userId = userId; self.username = username; self.fullName = fullName
        self.biography = biography; self.externalUrl = externalUrl
        self.profilePicURL = profilePicURL; self.isVerified = isVerified
        self.isPrivate = isPrivate; self.followerCount = followerCount
        self.followingCount = followingCount; self.mediaCount = mediaCount
        self.followedBy = followedBy; self.isFollowing = isFollowing
        self.isFollowRequested = isFollowRequested; self.cachedAt = cachedAt
        self.cachedMediaURLs = cachedMediaURLs
        self.cachedReelURLs = cachedReelURLs; self.cachedTaggedURLs = cachedTaggedURLs
        self.cachedHighlights = cachedHighlights
        self.cachedMediaItems = cachedMediaItems
    }
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
    // Latin variants
    case latin      = "latin"
    case spanish    = "spanish"
    case german     = "german"
    case french     = "french"
    case portuguese = "portuguese"
    case italian    = "italian"
    case swedish    = "swedish"
    case polish     = "polish"
    case turkish    = "turkish"
    case icelandic  = "icelandic"
    // Other European
    case cyrillic   = "cyrillic"
    case greek      = "greek"
    case georgian   = "georgian"
    case armenian   = "armenian"
    // Middle East
    case arabic     = "arabic"
    case hebrew     = "hebrew"
    case persian    = "persian"
    // South Asia
    case hindi      = "hindi"
    case bengali    = "bengali"
    case tamil      = "tamil"
    case gujarati   = "gujarati"
    // East Asia
    case hiragana   = "hiragana"
    case katakana   = "katakana"
    case chinese    = "chinese"
    case korean     = "korean"
    // Southeast Asia
    case thai       = "thai"
    case burmese    = "burmese"
    case khmer      = "khmer"
    case lao        = "lao"
    // Other
    case mongolian  = "mongolian"
    case amharic    = "amharic"
    case tibetan    = "tibetan"

    var displayName: String {
        switch self {
        case .latin:      return "Latin (A-Z)"
        case .spanish:    return "Spanish (A-Z+Ñ)"
        case .german:     return "German (A-Z+Ä Ö Ü)"
        case .french:     return "French (A-Z+accents)"
        case .portuguese: return "Portuguese (A-Z+accents)"
        case .italian:    return "Italian (A-Z, 21)"
        case .swedish:    return "Swedish (A-Ö)"
        case .polish:     return "Polish (A-Ż)"
        case .turkish:    return "Turkish (A-Z+Ç Ğ)"
        case .icelandic:  return "Icelandic (A-Þ)"
        case .cyrillic:   return "Cyrillic (А-Я)"
        case .greek:      return "Greek (Α-Ω)"
        case .georgian:   return "Georgian (ა-ჰ)"
        case .armenian:   return "Armenian (Ա-Ֆ)"
        case .arabic:     return "Arabic (أ-ي)"
        case .hebrew:     return "Hebrew (א-ת)"
        case .persian:    return "Persian (ا-ی)"
        case .hindi:      return "Hindi (अ-ह)"
        case .bengali:    return "Bengali (অ-হ)"
        case .tamil:      return "Tamil (அ-ஹ)"
        case .gujarati:   return "Gujarati (અ-હ)"
        case .hiragana:   return "Hiragana (あ-ん)"
        case .katakana:   return "Katakana (ア-ン)"
        case .chinese:    return "Chinese (一-了)"
        case .korean:     return "Korean (가-코)"
        case .thai:       return "Thai (ก-ฮ)"
        case .burmese:    return "Burmese (က-အ)"
        case .khmer:      return "Khmer (ក-អ)"
        case .lao:        return "Lao (ກ-ຮ)"
        case .mongolian:  return "Mongolian (ᠠ-ᠾ)"
        case .amharic:    return "Amharic (አ-ፐ)"
        case .tibetan:    return "Tibetan (ཀ-ཧ)"
        }
    }

    var flag: String {
        switch self {
        case .latin:      return "🌍"
        case .spanish:    return "🇪🇸"
        case .german:     return "🇩🇪"
        case .french:     return "🇫🇷"
        case .portuguese: return "🇵🇹"
        case .italian:    return "🇮🇹"
        case .swedish:    return "🇸🇪"
        case .polish:     return "🇵🇱"
        case .turkish:    return "🇹🇷"
        case .icelandic:  return "🇮🇸"
        case .cyrillic:   return "🇷🇺"
        case .greek:      return "🇬🇷"
        case .georgian:   return "🇬🇪"
        case .armenian:   return "🇦🇲"
        case .arabic:     return "🇸🇦"
        case .hebrew:     return "🇮🇱"
        case .persian:    return "🇮🇷"
        case .hindi:      return "🇮🇳"
        case .bengali:    return "🇧🇩"
        case .tamil:      return "🇱🇰"
        case .gujarati:   return "🇮🇳"
        case .hiragana:   return "🇯🇵"
        case .katakana:   return "🇯🇵"
        case .chinese:    return "🇨🇳"
        case .korean:     return "🇰🇷"
        case .thai:       return "🇹🇭"
        case .burmese:    return "🇲🇲"
        case .khmer:      return "🇰🇭"
        case .lao:        return "🇱🇦"
        case .mongolian:  return "🇲🇳"
        case .amharic:    return "🇪🇹"
        case .tibetan:    return "🏔️"
        }
    }

    var characters: [String] {
        switch self {
        case .latin:
            return ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        case .spanish:
            return ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","Ñ","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        case .german:
            return ["A","Ä","B","C","D","E","F","G","H","I","J","K","L","M","N","O","Ö","P","Q","R","S","ß","T","U","Ü","V","W","X","Y","Z"]
        case .french:
            return ["A","À","Â","B","C","Ç","D","E","É","È","Ê","Ë","F","G","H","I","Î","Ï","J","K","L","M","N","O","Ô","Œ","P","Q","R","S","T","U","Ù","Û","Ü","V","W","X","Y","Z"]
        case .portuguese:
            return ["A","Á","Â","Ã","À","B","C","Ç","D","E","É","Ê","F","G","H","I","Í","J","K","L","M","N","O","Ó","Ô","Õ","P","Q","R","S","T","U","Ú","V","W","X","Y","Z"]
        case .italian:
            return ["A","B","C","D","E","F","G","H","I","L","M","N","O","P","Q","R","S","T","U","V","Z"]
        case .swedish:
            return ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","Å","Ä","Ö"]
        case .polish:
            return ["A","Ą","B","C","Ć","D","E","Ę","F","G","H","I","J","K","L","Ł","M","N","Ń","O","Ó","P","Q","R","S","Ś","T","U","V","W","X","Y","Z","Ź","Ż"]
        case .turkish:
            return ["A","B","C","Ç","D","E","F","G","Ğ","H","I","İ","J","K","L","M","N","O","Ö","P","R","S","Ş","T","U","Ü","V","Y","Z"]
        case .icelandic:
            return ["A","Á","B","D","Ð","E","É","F","G","H","I","Í","J","K","L","M","N","O","Ó","P","R","S","T","U","Ú","V","X","Y","Ý","Þ","Æ","Ö"]
        case .cyrillic:
            return ["А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ъ","Ы","Ь","Э","Ю","Я"]
        case .greek:
            return ["Α","Β","Γ","Δ","Ε","Ζ","Η","Θ","Ι","Κ","Λ","Μ","Ν","Ξ","Ο","Π","Ρ","Σ","Τ","Υ","Φ","Χ","Ψ","Ω"]
        case .georgian:
            return ["ა","ბ","გ","დ","ე","ვ","ზ","თ","ი","კ","ლ","მ","ნ","ო","პ","ჟ","რ","ს","ტ","უ","ფ","ქ","ღ","ყ","შ","ჩ","ც","ძ","წ","ჭ","ხ","ჯ","ჰ"]
        case .armenian:
            return ["Ա","Բ","Գ","Դ","Ե","Զ","Է","Ը","Թ","Ժ","Ի","Լ","Խ","Ծ","Կ","Հ","Ձ","Ղ","Ճ","Մ","Յ","Ն","Շ","Ո","Չ","Պ","Ջ","Ռ","Ս","Վ","Տ","Ր","Ց","Ւ","Փ","Ք","Օ","Ֆ"]
        case .arabic:
            return ["ا","ب","ت","ث","ج","ح","خ","د","ذ","ر","ز","س","ش","ص","ض","ط","ظ","ع","غ","ف","ق","ك","ل","م","ن","ه","و","ي"]
        case .hebrew:
            return ["א","ב","ג","ד","ה","ו","ז","ח","ט","י","כ","ל","מ","נ","ס","ע","פ","צ","ק","ר","ש","ת"]
        case .persian:
            return ["ا","ب","پ","ت","ث","ج","چ","ح","خ","د","ذ","ر","ز","ژ","س","ش","ص","ض","ط","ظ","ع","غ","ف","ق","ک","گ","ل","م","ن","و","ه","ی"]
        case .hindi:
            return ["अ","आ","इ","ई","उ","ऊ","ए","ऐ","ओ","औ","क","ख","ग","घ","च","छ","ज","झ","ट","ठ","ड","ढ","त","थ","द","ध","न","प","फ","ब","भ","म","य","र","ल","व","श","ष","स","ह"]
        case .bengali:
            return ["অ","আ","ই","ঈ","উ","ঊ","এ","ঐ","ও","ঔ","ক","খ","গ","ঘ","চ","ছ","জ","ঝ","ট","ঠ","ড","ঢ","ত","থ","দ","ধ","ন","প","ফ","ব","ভ","ম","য","র","ল","শ","ষ","স","হ"]
        case .tamil:
            return ["அ","ஆ","இ","ஈ","உ","ஊ","எ","ஏ","ஐ","ஒ","ஓ","ஔ","க","ங","ச","ஞ","ட","ண","த","ந","ப","ம","ய","ர","ல","வ","ழ","ள","ற","ன","ஹ"]
        case .gujarati:
            return ["અ","આ","ઇ","ઈ","ઉ","ઊ","એ","ઐ","ઓ","ઔ","ક","ખ","ગ","ઘ","ચ","છ","જ","ઝ","ટ","ઠ","ડ","ઢ","ત","થ","દ","ધ","ન","પ","ફ","બ","ભ","મ","ય","ર","લ","વ","શ","ષ","સ","હ"]
        case .hiragana:
            return ["あ","い","う","え","お","か","き","く","け","こ","さ","し","す","せ","そ","た","ち","つ","て","と","な","に","ぬ","ね","の","は","ひ","ふ","へ","ほ","ま","み","む","め","も","や","ゆ","よ","ら","り","る","れ","ろ","わ","を","ん"]
        case .katakana:
            return ["ア","イ","ウ","エ","オ","カ","キ","ク","ケ","コ","サ","シ","ス","セ","ソ","タ","チ","ツ","テ","ト","ナ","ニ","ヌ","ネ","ノ","ハ","ヒ","フ","ヘ","ホ","マ","ミ","ム","メ","モ","ヤ","ユ","ヨ","ラ","リ","ル","レ","ロ","ワ","ヲ","ン"]
        case .chinese:
            return ["一","二","三","四","五","六","七","八","九","十","人","大","小","中","国","水","火","山","木","日","月","年","时","上","下","左","右","前","后","好","你","我","他","们","来","去","说","看","听","想","会","能","要","有","是","不","在","和","的","了"]
        case .korean:
            return ["가","나","다","라","마","바","사","아","자","차","카","타","파","하","개","내","대","래","매","배","새","애","재","채","캐","태","패","해","고","노","도","로","모","보","소","오","조","초","코"]
        case .thai:
            return ["ก","ข","ค","ง","จ","ฉ","ช","ซ","ญ","ด","ต","ถ","ท","น","บ","ป","ผ","ฝ","พ","ฟ","ภ","ม","ย","ร","ล","ว","ศ","ส","ห","อ","ฮ"]
        case .burmese:
            return ["က","ခ","ဂ","ဃ","င","စ","ဆ","ဇ","ဈ","ဉ","ည","ဋ","ဌ","ဍ","ဎ","ဏ","တ","ထ","ဒ","ဓ","န","ပ","ဖ","ဗ","ဘ","မ","ယ","ရ","လ","ဝ","သ","ဟ","ဠ","အ"]
        case .khmer:
            return ["ក","ខ","គ","ឃ","ង","ច","ឆ","ជ","ឈ","ញ","ដ","ឋ","ឌ","ឍ","ណ","ត","ថ","ទ","ធ","ន","ប","ផ","ព","ភ","ម","យ","រ","ល","វ","ស","ហ","ឡ","អ"]
        case .lao:
            return ["ກ","ຂ","ຄ","ງ","ຈ","ສ","ຊ","ຍ","ດ","ຕ","ຖ","ທ","ນ","ບ","ປ","ຜ","ຝ","ພ","ຟ","ມ","ຢ","ຣ","ລ","ວ","ຫ","ອ","ຮ"]
        case .mongolian:
            return ["ᠠ","ᠡ","ᠢ","ᠣ","ᠤ","ᠥ","ᠦ","ᠧ","ᠨ","ᠩ","ᠪ","ᠫ","ᠬ","ᠭ","ᠮ","ᠯ","ᠰ","ᠱ","ᠲ","ᠳ","ᠴ","ᠵ","ᠶ","ᠷ","ᠸ","ᠹ","ᠺ","ᠻ","ᠼ","ᠽ","ᠾ"]
        case .amharic:
            return ["አ","ቡ","ቢ","ባ","ቤ","ብ","ቦ","ቀ","ቁ","ቂ","ቃ","ቄ","ቅ","ቆ","ሀ","ሁ","ሂ","ሃ","ሄ","ህ","ሆ","ለ","ሉ","ሊ","ላ","ሌ","ል","ሎ","መ","ሙ","ሚ","ማ","ሜ","ም","ሞ","ሰ","ሱ","ሲ","ሳ","ሴ","ስ","ሶ","ፐ"]
        case .tibetan:
            return ["ཀ","ཁ","ག","ང","ཅ","ཆ","ཇ","ཉ","ཏ","ཐ","ད","ན","པ","ཕ","བ","མ","ཙ","ཚ","ཛ","ཝ","ཞ","ཟ","འ","ཡ","ར","ལ","ཤ","ས","ཧ","ཨ"]
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
    var imagePath: String?  // Path to image file in Documents directory
    var mediaId: String?
    var isArchived: Bool
    var uploadDate: Date?
    var lastCommentId: String?
    var uploadStatus: PhotoUploadStatus
    var errorMessage: String?
    
    // OLD property for backward compatibility during migration - NOT saved to UserDefaults anymore
    private var _legacyImageData: Data?
    
    // Computed property - loads imageData from disk
    var imageData: Data? {
        get {
            // During migration/decode, might still have legacy data
            if let legacy = _legacyImageData {
                return legacy
            }
            
            guard let path = imagePath else { return nil }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(path)
            return try? Data(contentsOf: fileURL)
        }
    }
    
    init(id: UUID, setId: UUID, bankId: UUID? = nil, symbol: String, filename: String, imageData: Data? = nil, mediaId: String? = nil, isArchived: Bool = false, uploadDate: Date? = nil, lastCommentId: String? = nil, uploadStatus: PhotoUploadStatus = .pending, errorMessage: String? = nil) {
        self.id = id
        self.setId = setId
        self.bankId = bankId
        self.symbol = symbol
        self.filename = filename
        self.mediaId = mediaId
        self.isArchived = isArchived
        self.uploadDate = uploadDate
        self.lastCommentId = lastCommentId
        self.uploadStatus = uploadStatus
        self.errorMessage = errorMessage
        self._legacyImageData = nil
        
        // Save imageData to filesystem if provided
        if let data = imageData {
            let path = "photos/\(setId.uuidString)/\(id.uuidString).jpg"
            self.imagePath = SetPhoto.saveImageToFilesystem(data: data, path: path)
        } else {
            self.imagePath = nil
        }
    }
    
    // Helper: Save image data to filesystem
    static func saveImageToFilesystem(data: Data, path: String) -> String? {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(path)
        
        // Create directory if needed
        let dirURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        // Write file
        if (try? data.write(to: fileURL)) != nil {
            return path
        }
        return nil
    }
    
    // Custom coding to handle legacy imageData during decode
    enum CodingKeys: String, CodingKey {
        case id, setId, bankId, symbol, filename, imagePath, mediaId, isArchived
        case uploadDate, lastCommentId, uploadStatus, errorMessage
        case imageData  // Legacy key
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        setId = try container.decode(UUID.self, forKey: .setId)
        bankId = try container.decodeIfPresent(UUID.self, forKey: .bankId)
        symbol = try container.decode(String.self, forKey: .symbol)
        filename = try container.decode(String.self, forKey: .filename)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        uploadDate = try container.decodeIfPresent(Date.self, forKey: .uploadDate)
        lastCommentId = try container.decodeIfPresent(String.self, forKey: .lastCommentId)
        uploadStatus = try container.decode(PhotoUploadStatus.self, forKey: .uploadStatus)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        
        // Handle legacy imageData
        _legacyImageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(setId, forKey: .setId)
        try container.encodeIfPresent(bankId, forKey: .bankId)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(filename, forKey: .filename)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encodeIfPresent(mediaId, forKey: .mediaId)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(uploadDate, forKey: .uploadDate)
        try container.encodeIfPresent(lastCommentId, forKey: .lastCommentId)
        try container.encode(uploadStatus, forKey: .uploadStatus)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        // DO NOT encode imageData anymore - only imagePath
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

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "secretInputEnabled") }
    }

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
        let savedEnabled = UserDefaults.standard.object(forKey: "secretInputEnabled") as? Bool
        self.isEnabled = savedEnabled ?? true

        if let savedMode = UserDefaults.standard.string(forKey: "secretInputMode"),
           let mode = MaskInputMode(rawValue: savedMode) {
            self.mode = mode
        } else {
            self.mode = .latestFollower
        }
        
        self.customUsername = UserDefaults.standard.string(forKey: "secretInputCustomUsername") ?? ""
    }
    
    /// Get the mask text based on current mode. Returns empty string when disabled.
    func getMaskText(latestFollowerUsername: String?) -> String {
        guard isEnabled else { return "" }
        switch mode {
        case .latestFollower:
            return latestFollowerUsername?.lowercased() ?? "user"
        case .customUsername:
            return customUsername.lowercased()
        }
    }
}

