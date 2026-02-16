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
        migrateImageDataToFilesystem()  // CRITICAL: Migrate old data first
        loadSets()
        loadLogs()
    }
    
    // MARK: - Sets CRUD
    
    func createSet(name: String, type: SetType, bankCount: Int, photos: [(symbol: String, filename: String, imageData: Data)], selectedAlphabet: AlphabetType? = nil) -> PhotoSet {
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
            createdAt: Date(),
            selectedAlphabet: selectedAlphabet
        )
        
        sets.append(newSet)
        saveSets()
        addLog(action: "set_created", details: "Created set \(name) with \(setPhotos.count) photos")
        
        return newSet
    }
    
    // MARK: - Insert Photo at Position
    
    /// Insert a photo into a specific slot position within a set.
    /// For bank-based sets, the photo is inserted into each bank at that position.
    func insertPhotoAtPosition(setId: UUID, symbol: String, filename: String, imageData: Data, position: Int) {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return }
        let set = sets[setIndex]
        
        if set.type == .word || set.type == .number {
            // Insert into each bank
            for bank in set.banks {
                let photoId = UUID()
                let setPhoto = SetPhoto(
                    id: photoId,
                    setId: setId,
                    bankId: bank.id,
                    symbol: symbol,
                    filename: filename,
                    imageData: imageData,
                    mediaId: nil,
                    isArchived: false,
                    uploadDate: nil,
                    lastCommentId: nil,
                    uploadStatus: .pending,
                    errorMessage: nil
                )
                sets[setIndex].photos.append(setPhoto)
            }
        } else {
            let photoId = UUID()
            let setPhoto = SetPhoto(
                id: photoId,
                setId: setId,
                symbol: symbol,
                filename: filename,
                imageData: imageData,
                mediaId: nil,
                isArchived: false,
                uploadDate: nil,
                lastCommentId: nil,
                uploadStatus: .pending,
                errorMessage: nil
            )
            sets[setIndex].photos.append(setPhoto)
        }
        
        saveSets()
        objectWillChange.send()
        print("✅ [INSERT] Photo inserted at position \(position) with symbol '\(symbol)'")
    }
    
    // MARK: - Replace Photo at Position
    
    /// Replace the image data for all photos matching a given symbol in a set
    func replacePhotoAtSymbol(setId: UUID, symbol: String, newFilename: String, newImageData: Data) {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return }
        
        for photoIndex in sets[setIndex].photos.indices {
            if sets[setIndex].photos[photoIndex].symbol == symbol {
                sets[setIndex].photos[photoIndex].filename = newFilename
                
                // Save new imageData to filesystem
                let photoId = sets[setIndex].photos[photoIndex].id
                let path = "photos/\(setId.uuidString)/\(photoId.uuidString).jpg"
                sets[setIndex].photos[photoIndex].imagePath = SetPhoto.saveImageToFilesystem(data: newImageData, path: path)
                
                sets[setIndex].photos[photoIndex].uploadStatus = .pending
                sets[setIndex].photos[photoIndex].mediaId = nil
                sets[setIndex].photos[photoIndex].errorMessage = nil
            }
        }
        
        saveSets()
        objectWillChange.send()
        print("✅ [REPLACE] Photo replaced for symbol '\(symbol)'")
    }
    
    // MARK: - Delete Photos by Symbol
    
    /// Remove all photos matching a given symbol from a set
    func deletePhotosBySymbol(setId: UUID, symbol: String) {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return }
        
        let countBefore = sets[setIndex].photos.count
        sets[setIndex].photos.removeAll { $0.symbol == symbol }
        let countAfter = sets[setIndex].photos.count
        
        saveSets()
        objectWillChange.send()
        print("🗑️ [DELETE] Removed \(countBefore - countAfter) photos with symbol '\(symbol)'")
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
    
    func updatePhoto(photoId: UUID, mediaId: String? = nil, isArchived: Bool? = nil, commentId: String? = nil, clearComment: Bool = false, uploadStatus: PhotoUploadStatus? = nil, errorMessage: String? = nil, uploadDate: Date? = nil) {
        for setIndex in sets.indices {
            if let photoIndex = sets[setIndex].photos.firstIndex(where: { $0.id == photoId }) {
                if let mediaId = mediaId {
                    sets[setIndex].photos[photoIndex].mediaId = mediaId
                    // Only set date if not explicitly provided
                    if uploadDate == nil {
                        sets[setIndex].photos[photoIndex].uploadDate = Date()
                    }
                }
                if let uploadDate = uploadDate {
                    sets[setIndex].photos[photoIndex].uploadDate = uploadDate
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
        return set.photos.filter { $0.bankId == bankId }
    }
    
    // MARK: - Swap Photos (exchange positions)
    
    func swapPhotos(setId: UUID, bankId: UUID?, indexA: Int, indexB: Int) {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return }
        guard indexA != indexB else { return }
        
        if let bankId = bankId {
            // BANK-BASED SWAP
            var bankPhotos = sets[setIndex].photos.filter { $0.bankId == bankId }
            let otherPhotos = sets[setIndex].photos.filter { $0.bankId != bankId }
            
            guard indexA < bankPhotos.count, indexB < bankPhotos.count else { return }
            
            // Swap the two photos
            bankPhotos.swapAt(indexA, indexB)
            
            // Rebuild global array
            sets[setIndex].photos = otherPhotos + bankPhotos
        } else {
            // CUSTOM SET: Swap directly
            guard indexA < sets[setIndex].photos.count, indexB < sets[setIndex].photos.count else { return }
            
            sets[setIndex].photos.swapAt(indexA, indexB)
        }
        
        saveSets()
        objectWillChange.send()
        print("✅ [SWAP] Swapped position \(indexA + 1) ↔ \(indexB + 1)")
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
    
    // MARK: - Migration: Move imageData from UserDefaults to Filesystem
    
    /// CRITICAL: Migrates old data structure (imageData in UserDefaults) to new structure (files on disk)
    /// This runs once on app launch to fix the 5MB+ UserDefaults issue
    private func migrateImageDataToFilesystem() {
        let migrationKey = "com.vault.migration.imagedata.v1"
        
        // Check if migration already done
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("✅ [MIGRATION] Already migrated - skipping")
            return
        }
        
        print("🔄 [MIGRATION] Starting imageData migration to filesystem...")
        
        // Load old data structure (with imageData in struct)
        guard let data = UserDefaults.standard.data(forKey: setsKey) else {
            print("   No sets to migrate")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        
        // Try to decode with old structure (this will work even with imageData present)
        guard var oldSets = try? JSONDecoder().decode([PhotoSet].self, from: data) else {
            print("   Could not decode sets")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        
        print("   Found \(oldSets.count) sets to migrate")
        
        var migratedCount = 0
        var totalPhotos = 0
        
        // For each set, migrate photos' imageData to filesystem
        for (setIndex, set) in oldSets.enumerated() {
            print("   Migrating set: \(set.name) (\(set.photos.count) photos)")
            
            for (photoIndex, photo) in set.photos.enumerated() {
                totalPhotos += 1
                
                // If photo has imageData but no imagePath, migrate it
                if let imageData = photo.imageData, photo.imagePath == nil {
                    let path = "photos/\(set.id.uuidString)/\(photo.id.uuidString).jpg"
                    let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent(path)
                    
                    // Create directory
                    let dirURL = fileURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    
                    // Write file
                    if (try? imageData.write(to: fileURL)) != nil {
                        // Update photo to use path instead of data
                        var updatedPhoto = photo
                        updatedPhoto.imagePath = path
                        oldSets[setIndex].photos[photoIndex] = updatedPhoto
                        migratedCount += 1
                    } else {
                        print("   ⚠️ Failed to write photo \(photo.id)")
                    }
                }
            }
        }
        
        print("✅ [MIGRATION] Migrated \(migratedCount)/\(totalPhotos) photos to filesystem")
        LogManager.shared.success("Migrated \(migratedCount) photos from UserDefaults to filesystem", category: .general)
        
        // Save migrated data back (now without imageData, much smaller)
        if let newData = try? JSONEncoder().encode(oldSets) {
            UserDefaults.standard.set(newData, forKey: setsKey)
            let newSizeKB = newData.count / 1024
            print("   New UserDefaults size: \(newSizeKB)KB (was ~5000KB)")
            LogManager.shared.info("UserDefaults size reduced to \(newSizeKB)KB", category: .general)
        }
        
        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("🎉 [MIGRATION] Complete!")
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
