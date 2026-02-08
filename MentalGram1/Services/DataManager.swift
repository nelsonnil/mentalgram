import Foundation
import Combine

/// Manages local data persistence for sets, banks, and photos
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var sets: [PhotoSet] = []
    @Published var logs: [LogEntry] = []
    
    private let setsKey = "com.mindup.sets"
    private let logsKey = "com.mindup.logs"
    
    // Photos stored in Documents directory (not in UserDefaults - too large)
    private var photosDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos")
    }
    
    private init() {
        // Create photos directory
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        
        loadSets()
        loadLogs()
    }
    
    // MARK: - Photo File Management
    
    private func savePhotoToDisk(_ imageData: Data, photoId: UUID) -> String? {
        let filename = "\(photoId.uuidString).jpg"
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            return filename
        } catch {
            print("❌ Error saving photo to disk: \(error)")
            return nil
        }
    }
    
    func loadPhotoFromDisk(filename: String) -> Data? {
        let fileURL = photosDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }
    
    private func deletePhotoFromDisk(filename: String) {
        let fileURL = photosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
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
                    name: type == .word ? "Bank \(i + 1)" : "Digit \(i + 1)"
                )
                banks.append(bank)
            }
        }
        
        // Create photos
        for (index, photo) in photos.enumerated() {
            if type == .word || type == .number {
                // One photo per bank for each symbol
                for bank in banks {
                    let photoId = UUID()
                    
                    // Save photo to disk
                    let photoPath = savePhotoToDisk(photo.imageData, photoId: photoId)
                    
                    let setPhoto = SetPhoto(
                        id: photoId,
                        setId: setId,
                        bankId: bank.id,
                        symbol: photo.symbol,
                        filename: photo.filename,
                        photoFilePath: photoPath,
                        mediaId: nil,
                        isArchived: false,
                        uploadDate: nil,
                        lastCommentId: nil
                    )
                    setPhotos.append(setPhoto)
                }
            } else {
                // Custom: one photo per symbol
                let photoId = UUID()
                
                // Save photo to disk
                let photoPath = savePhotoToDisk(photo.imageData, photoId: photoId)
                
                let setPhoto = SetPhoto(
                    id: photoId,
                    setId: setId,
                    symbol: photo.symbol,
                    filename: photo.filename,
                    photoFilePath: photoPath,
                    mediaId: nil,
                    isArchived: false,
                    uploadDate: nil,
                    lastCommentId: nil
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
            createdAt: Date(),
            completedAt: nil
        )
        
        sets.insert(newSet, at: 0)
        saveSets()
        addLog(action: "set_created", details: "Created set: \(name) (\(type.rawValue))")
        
        return newSet
    }
    
    func deleteSet(id: UUID) {
        // Delete photos from disk first
        if let set = sets.first(where: { $0.id == id }) {
            for photo in set.photos {
                if let path = photo.photoFilePath {
                    deletePhotoFromDisk(filename: path)
                }
            }
        }
        
        sets.removeAll { $0.id == id }
        saveSets()
        addLog(action: "set_deleted", details: "Deleted set \(id)")
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
    
    func updatePhoto(photoId: UUID, mediaId: String?, isArchived: Bool? = nil, commentId: String? = nil, clearComment: Bool = false) {
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
                saveSets()
                return
            }
        }
    }
    
    func getPhotosForBank(setId: UUID, bankId: UUID) -> [SetPhoto] {
        guard let set = sets.first(where: { $0.id == setId }) else { return [] }
        return set.photos.filter { $0.bankId == bankId }.sorted { ($0.filename) < ($1.filename) }
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
    
    // MARK: - Logs
    
    func addLog(action: String, details: String) {
        let entry = LogEntry(action: action, details: details)
        logs.insert(entry, at: 0)
        
        // Keep max 100 logs
        if logs.count > 100 {
            logs = Array(logs.prefix(100))
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
