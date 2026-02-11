import Foundation
import Combine

/// Manages local data persistence for sets, banks, and photos
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var sets: [PhotoSet] = []
    @Published var logs: [LogEntry] = []
    
    private let setsKey = "com.vault.sets"
    private let logsKey = "com.vault.logs"
    
    private init() {
        loadSets()
        loadLogs()
    }
    
    // MARK: - Sets CRUD
    
    func createSet(name: String, type: SetType, bankCount: Int, photos: [(symbol: String, filename: String, imageData: Data)]) -> PhotoSet {
        var banks: [Bank] = []
        var setPhotos: [SetPhoto] = []
        let setId = UUID()
        
        // Create banks for word/number types
        if type == .word || type == .number {
            for i in 0..<bankCount {
                let bank = Bank(
                    id: UUID(),
                    position: i + 1,
                    name: "Bank \(i + 1)"
                )
                banks.append(bank)
            }
        }
        
        // Create photos
        // ANTI-BOT: Group by bank to avoid consecutive duplicate uploads
        // Safe order: All photos from bank 1, then bank 2, then bank 3...
        // This separates duplicate images by ~10-50 minutes instead of 2-5 minutes
        if type == .word || type == .number {
            // Group by bank (NOT by symbol) to avoid consecutive duplicates
            for bank in banks {
                for (index, photo) in photos.enumerated() {
                    let photoId = UUID()
                    
                    let setPhoto = SetPhoto(
                        id: photoId,
                        setId: setId,
                        bankId: bank.id,
                        symbol: photo.symbol,
                        filename: photo.filename,
                        imageData: photo.imageData,
                        mediaId: nil,
                        isArchived: false,
                        uploadDate: nil,
                        lastCommentId: nil,
                        uploadStatus: .pending,
                        errorMessage: nil
                    )
                    setPhotos.append(setPhoto)
                }
            }
        } else {
            // Custom type
            for (index, photo) in photos.enumerated() {
                // Custom: one photo per symbol
                let photoId = UUID()
                
                let setPhoto = SetPhoto(
                    id: photoId,
                    setId: setId,
                    symbol: photo.symbol,
                    filename: photo.filename,
                    imageData: photo.imageData,
                    mediaId: nil,
                    isArchived: false,
                    uploadDate: nil,
                    lastCommentId: nil,
                    uploadStatus: .pending,
                    errorMessage: nil
                )
                setPhotos.append(setPhoto)
            }
        }
        
        let newSet = PhotoSet(
            id: setId,
            name: name,
            type: type,
            status: .ready,
            banks: banks,
            photos: setPhotos,
            createdAt: Date()
        )
        
        sets.append(newSet)
        saveSets()
        addLog(action: "set_created", details: "Created set \(name) with \(setPhotos.count) photos")
        
        return newSet
    }
    
    func updateSetStatus(id: UUID, status: SetStatus) {
        if let index = sets.firstIndex(where: { $0.id == id }) {
            sets[index].status = status
            if status == .completed {
                sets[index].completedAt = Date()
            }
            saveSets()
        }
    }
    
    func updatePhoto(photoId: UUID, mediaId: String? = nil, isArchived: Bool? = nil, commentId: String? = nil, clearComment: Bool = false, uploadStatus: PhotoUploadStatus? = nil, errorMessage: String? = nil) {
        for setIndex in sets.indices {
            if let photoIndex = sets[setIndex].photos.firstIndex(where: { $0.id == photoId }) {
                if let mediaId = mediaId {
                    sets[setIndex].photos[photoIndex].mediaId = mediaId
                    sets[setIndex].photos[photoIndex].uploadDate = Date()
                }
                if let isArchived = isArchived {
                    sets[setIndex].photos[photoIndex].isArchived = isArchived
                }
                if let commentId = commentId {
                    sets[setIndex].photos[photoIndex].lastCommentId = commentId
                }
                if clearComment {
                    sets[setIndex].photos[photoIndex].lastCommentId = nil
                }
                if let uploadStatus = uploadStatus {
                    sets[setIndex].photos[photoIndex].uploadStatus = uploadStatus
                }
                if let errorMessage = errorMessage {
                    sets[setIndex].photos[photoIndex].errorMessage = errorMessage
                }
                saveSets()
                return
            }
        }
    }
    
    func getUploadProgress(setId: UUID) -> (pending: Int, completed: Int, error: Int) {
        guard let set = sets.first(where: { $0.id == setId }) else { return (0, 0, 0) }
        let pending = set.photos.filter { $0.uploadStatus == .pending || $0.uploadStatus == .uploading || $0.uploadStatus == .uploaded || $0.uploadStatus == .archiving }.count
        let completed = set.photos.filter { $0.uploadStatus == .completed }.count
        let error = set.photos.filter { $0.uploadStatus == .error }.count
        return (pending, completed, error)
    }
    
    func getNextPendingPhoto(setId: UUID) -> SetPhoto? {
        guard let set = sets.first(where: { $0.id == setId }) else { return nil }
        return set.photos.first(where: { $0.uploadStatus == .pending || $0.uploadStatus == .error })
    }
    
    func hasIncompleteUpload(setId: UUID) -> Bool {
        guard let set = sets.first(where: { $0.id == setId }) else { return false }
        let hasStarted = set.photos.contains(where: { $0.uploadStatus != .pending })
        let hasIncomplete = set.photos.contains(where: { $0.uploadStatus != .completed })
        return hasStarted && hasIncomplete
    }
    
    func getPhotosForBank(setId: UUID, bankId: UUID) -> [SetPhoto] {
        guard let set = sets.first(where: { $0.id == setId }) else { return [] }
        return set.photos.filter { $0.bankId == bankId }.sorted { ($0.filename) < ($1.filename) }
    }
    
    func deleteSet(id: UUID) {
        sets.removeAll { $0.id == id }
        saveSets()
        addLog(action: "set_deleted", details: "Deleted set \(id)")
    }
    
    // MARK: - Persistence
    
    private func saveSets() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: setsKey)
        }
    }
    
    private func loadSets() {
        if let data = UserDefaults.standard.data(forKey: setsKey),
           let decoded = try? JSONDecoder().decode([PhotoSet].self, from: data) {
            sets = decoded
        }
    }
    
    // MARK: - Activity Logs
    
    func addLog(action: String, details: String) {
        let log = LogEntry(action: action, details: details)
        logs.insert(log, at: 0)
        
        // Keep only last 50 logs
        if logs.count > 50 {
            logs = Array(logs.prefix(50))
        }
        
        saveLogs()
    }
    
    private func saveLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: logsKey)
        }
    }
    
    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: logsKey),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            logs = decoded
        }
    }
}
