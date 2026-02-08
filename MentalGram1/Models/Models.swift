import Foundation
import SwiftUI

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
    
    var totalPhotos: Int {
        photos.count
    }
    
    var uploadedPhotos: Int {
        photos.filter { $0.mediaId != nil }.count
    }
}

struct Bank: Identifiable, Codable {
    let id: UUID
    var position: Int
    var name: String
}

struct SetPhoto: Identifiable, Codable {
    let id: UUID
    var setId: UUID
    var bankId: UUID?
    var symbol: String
    var filename: String
    var photoFilePath: String? // Path to photo on disk (not the full Data to save memory)
    var mediaId: String?
    var isArchived: Bool
    var uploadDate: Date?
    var lastCommentId: String?
    
    // Computed - not stored
    var imageData: Data? {
        get {
            guard let path = photoFilePath else { return nil }
            return DataManager.shared.loadPhotoFromDisk(filename: path)
        }
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
