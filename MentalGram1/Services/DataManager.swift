import Foundation
import Combine

/// Manages local data persistence for sets, banks, and photos
class DataManager: ObservableObject {
    static let shared = DataManager()

    @Published var sets: [PhotoSet] = []
    @Published var logs: [LogEntry] = []

    // Sets key is account-scoped: each Instagram user ID gets its own slot.
    // Falls back to a shared guest key when no user is logged in.
    private var currentUserId: String = ""
    private var setsKey: String { "com.vault.sets.\(currentUserId.isEmpty ? "guest" : currentUserId)" }
    private let legacySetsKey = "com.vault.sets"   // Pre-account-scoping key
    private let logsKey = "com.vault.logs"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Capture initial userId from whatever session was restored from Keychain
        currentUserId = InstagramService.shared.session.userId

        migrateImageDataToFilesystem()  // CRITICAL: Migrate old data first

        // Migrate legacy (unscoped) sets to the current account's key on first run
        migrateLegacySetsIfNeeded()

        loadSets()
        loadLogs()

        // React to account changes (login with a different user, logout)
        InstagramService.shared.$session
            .map(\.userId)
            .removeDuplicates()
            .dropFirst()          // skip the initial value already captured above
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newUserId in
                guard let self else { return }
                print("👤 [ACCOUNT] User changed → '\(newUserId.isEmpty ? "guest" : newUserId)' — reloading sets")
                self.currentUserId = newUserId
                self.migrateGuestRestoreToCurrentUserIfNeeded()
                self.migrateImageDataToFilesystem()
                self.migrateLegacySetsIfNeeded()
                self.loadSets()
                // Clear account-bound Instagram state that would be nonsense on a different
                // account (the Amnesia Carousel posts live on the previous account). Guarded
                // so it never wipes a same-account re-login/restore.
                AmnesiaCarouselSettings.shared.resetForAccountChange(to: newUserId)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Sets CRUD
    
    func createSet(name: String, type: SetType, bankCount: Int, photos: [(symbol: String, filename: String, imageData: Data)], selectedAlphabet: AlphabetType? = nil) -> PhotoSet {
        var banks: [Bank] = []
        var setPhotos: [SetPhoto] = []
        let setId = UUID()

        // Determine slot labels (used when photos array is empty)
        let slotLabels: [String] = {
            switch type {
            case .word:   return selectedAlphabet?.characters ?? AlphabetType.latin.characters
            case .number: return (0...9).map { "\($0)" }
            case .custom: return []
            case .card:   return SetType.cardSlotLabels
            case .list:   return (1...max(bankCount, 1)).map { "\($0)" }
            }
        }()

        // Create banks for word/number types
        if type == .word || type == .number {
            for i in 0..<bankCount {
                let bank = Bank(id: UUID(), position: i + 1, name: "Bank \(i + 1)")
                banks.append(bank)
            }
        }

        if type == .word || type == .number {
            if photos.isEmpty {
                // Empty set creation: create placeholder slots with no imageData
                for bank in banks {
                    for symbol in slotLabels {
                        setPhotos.append(SetPhoto(
                            id: UUID(),
                            setId: setId,
                            bankId: bank.id,
                            symbol: symbol,
                            filename: "\(symbol.lowercased())_\(bank.position).jpg",
                            imageData: nil,
                            mediaId: nil,
                            isArchived: false,
                            uploadDate: nil,
                            lastCommentId: nil,
                            uploadStatus: .pending,
                            errorMessage: nil
                        ))
                    }
                }
            } else {
                // Photos provided: group by bank (anti-bot: bank1 all, then bank2 all…)
                for bank in banks {
                    for photo in photos {
                        setPhotos.append(SetPhoto(
                            id: UUID(),
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
                        ))
                    }
                }
            }
        } else if type == .card {
            // Card type: 52 fixed slots — one per card (A♠…K♦), no banks
            if photos.isEmpty {
                for symbol in SetType.cardSlotLabels {
                    setPhotos.append(SetPhoto(
                        id: UUID(),
                        setId: setId,
                        symbol: symbol,
                        filename: "card_\(symbol.lowercased().replacingOccurrences(of: "♠", with: "s").replacingOccurrences(of: "♥", with: "h").replacingOccurrences(of: "♣", with: "c").replacingOccurrences(of: "♦", with: "d")).jpg",
                        imageData: nil,
                        mediaId: nil,
                        isArchived: false,
                        uploadDate: nil,
                        lastCommentId: nil,
                        uploadStatus: .pending,
                        errorMessage: nil
                    ))
                }
            } else {
                for photo in photos {
                    setPhotos.append(SetPhoto(
                        id: UUID(),
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
                    ))
                }
            }
        } else if type == .list {
            let count = max(bankCount, 1)
            for i in 1...count {
                setPhotos.append(SetPhoto(
                    id: UUID(),
                    setId: setId,
                    symbol: "\(i)",
                    filename: "list_\(i).jpg",
                    imageData: nil,
                    mediaId: nil,
                    isArchived: false,
                    uploadDate: nil,
                    lastCommentId: nil,
                    uploadStatus: .pending,
                    errorMessage: nil
                ))
            }
        } else {
            // Custom type: create numbered placeholder slots (1…bankCount) or use provided photos
            if photos.isEmpty {
                for i in 1...max(bankCount, 1) {
                    setPhotos.append(SetPhoto(
                        id: UUID(),
                        setId: setId,
                        symbol: "\(i)",
                        filename: "custom_\(i).jpg",
                        imageData: nil,
                        mediaId: nil,
                        isArchived: false,
                        uploadDate: nil,
                        lastCommentId: nil,
                        uploadStatus: .pending,
                        errorMessage: nil
                    ))
                }
            } else {
                for photo in photos {
                    setPhotos.append(SetPhoto(
                        id: UUID(),
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
                    ))
                }
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
            selectedAlphabet: selectedAlphabet,
            targetBankCount: (type == .word || type == .number) ? bankCount : nil,
            inputMethod: nil,
            listItems: type == .list ? (1...max(bankCount, 1)).map { "Item \($0)" } : nil,
            listColumns: type == .list ? .automatic : nil,
            listButtonSize: type == .list ? .normal : nil,
            listSeparators: type == .list ? [] : nil
        )
        
        sets.append(newSet)
        saveSets()
        addLog(action: "set_created", details: "Created set \(name) with \(setPhotos.count) photos")

        // Sync new set's photos to iCloud Drive so they survive a reinstall.
        let newSetId = newSet.id
        iCloudDriveSync.shared.syncSetPhotos(setId: newSetId)

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
        iCloudDriveSync.shared.syncSetPhotos(setId: setId)
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
        iCloudDriveSync.shared.syncSetPhotos(setId: setId)
        objectWillChange.send()
        print("✅ [REPLACE] Photo replaced for symbol '\(symbol)'")
    }

    /// Replace image data for a single slot. Used by bank-aware bulk imports so
    /// filling Bank 2 does not accidentally replace the same symbol in every bank.
    func replacePhoto(photoId: UUID, newFilename: String, newImageData: Data) {
        for setIndex in sets.indices {
            if let photoIndex = sets[setIndex].photos.firstIndex(where: { $0.id == photoId }) {
                sets[setIndex].photos[photoIndex].filename = newFilename
                let setId = sets[setIndex].photos[photoIndex].setId
                let path = "photos/\(setId.uuidString)/\(photoId.uuidString).jpg"
                sets[setIndex].photos[photoIndex].imagePath = SetPhoto.saveImageToFilesystem(data: newImageData, path: path)
                sets[setIndex].photos[photoIndex].mediaId = nil
                sets[setIndex].photos[photoIndex].isArchived = false
                sets[setIndex].photos[photoIndex].uploadStatus = .pending
                sets[setIndex].photos[photoIndex].errorMessage = nil
                sets[setIndex].photos[photoIndex].uploadDate = nil
                sets[setIndex].photos[photoIndex].lastCommentId = nil
                sets[setIndex].photos[photoIndex].isVideo = false
                sets[setIndex].photos[photoIndex].videoURL = nil
                sets[setIndex].photos[photoIndex].videoAspectRatio = nil
                saveSets()
                iCloudDriveSync.shared.syncSetPhotos(setId: setId)
                objectWillChange.send()
                print("✅ [REPLACE] Photo replaced for id '\(photoId)'")
                return
            }
        }
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
    
    func updatePhoto(photoId: UUID, mediaId: String? = nil, isArchived: Bool? = nil,
                     commentId: String? = nil, clearComment: Bool = false,
                     uploadStatus: PhotoUploadStatus? = nil, errorMessage: String? = nil,
                     uploadDate: Date? = nil,
                     isVideo: Bool? = nil, videoURL: String? = nil, videoAspectRatio: CGFloat? = nil) {
        for setIndex in sets.indices {
            if let photoIndex = sets[setIndex].photos.firstIndex(where: { $0.id == photoId }) {
                if let mediaId = mediaId {
                    let previousMediaId = sets[setIndex].photos[photoIndex].mediaId
                    sets[setIndex].photos[photoIndex].mediaId = mediaId
                    // Only assign a default upload date when this is the first time
                    // the photo receives a mediaId (fresh upload/import). Reveal/archive
                    // updates pass the same mediaId again and must preserve the original
                    // date, otherwise revealed cards/posts jump to the top of the grid.
                    if uploadDate == nil && previousMediaId == nil {
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
                if let isVideo = isVideo {
                    sets[setIndex].photos[photoIndex].isVideo = isVideo
                }
                if let videoURL = videoURL {
                    sets[setIndex].photos[photoIndex].videoURL = videoURL
                }
                if let videoAspectRatio = videoAspectRatio {
                    sets[setIndex].photos[photoIndex].videoAspectRatio = videoAspectRatio
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

    // MARK: - Add / Remove Bank

    /// Adds a new bank to a word/number set, duplicating all slot symbols from bank 1.
    /// Returns the new Bank, or nil if the set is custom or not found.
    @discardableResult
    func addBank(setId: UUID) -> Bank? {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return nil }
        let set = sets[setIndex]
        guard set.type == .word || set.type == .number else { return nil }

        let newPosition = (set.banks.map(\.position).max() ?? 0) + 1
        let newBank = Bank(id: UUID(), position: newPosition, name: "Bank \(newPosition)")

        // Find previous bank to copy images from
        let prevBank = set.banks.max(by: { $0.position < $1.position })
        let prevPhotos = prevBank.map { pb in set.photos.filter { $0.bankId == pb.id } } ?? []
        let prevBySymbol = Dictionary(uniqueKeysWithValues: prevPhotos.compactMap { p -> (String, Data)? in
            guard let data = p.imageData else { return nil }
            return (p.symbol, data)
        })

        let slotLabels = set.slotLabels
        var newPhotos: [SetPhoto] = []
        for symbol in slotLabels {
            let photo = SetPhoto(
                id: UUID(),
                setId: setId,
                bankId: newBank.id,
                symbol: symbol,
                filename: "\(symbol.lowercased())_bank\(newPosition).jpg",
                imageData: prevBySymbol[symbol],  // copy image from previous bank if available
                mediaId: nil,
                isArchived: false,
                uploadDate: nil,
                lastCommentId: nil,
                uploadStatus: .pending,
                errorMessage: nil
            )
            newPhotos.append(photo)
        }

        sets[setIndex].banks.append(newBank)
        sets[setIndex].photos.append(contentsOf: newPhotos)
        saveSets()
        let copied = newPhotos.filter { $0.imageData != nil }.count
        print("➕ [BANK] Added bank \(newPosition) to set '\(set.name)' — \(newPhotos.count) slots, \(copied) images copied from previous bank")
        return newBank
    }

    /// Removes the last bank from a word/number set.
    /// By default only removes if ALL photos are still pending (not uploaded).
    /// Pass `force: true` to remove even if photos have been uploaded/archived
    /// (those photos stay archived on Instagram but are no longer tracked).
    @discardableResult
    func removeLastBank(setId: UUID, force: Bool = false) -> Bool {
        guard let setIndex = sets.firstIndex(where: { $0.id == setId }) else { return false }
        let set = sets[setIndex]
        guard set.type == .word || set.type == .number else { return false }
        guard set.banks.count > 1 else {
            print("⚠️ [BANK] Cannot remove last remaining bank")
            return false
        }

        guard let lastBank = set.banks.max(by: { $0.position < $1.position }) else { return false }
        let bankPhotos = set.photos.filter { $0.bankId == lastBank.id }

        if !force {
            let hasUploaded = bankPhotos.contains { $0.uploadStatus != .pending }
            if hasUploaded {
                print("⚠️ [BANK] Cannot remove bank \(lastBank.position) — has uploaded photos (use force to override)")
                return false
            }
        }

        let removedCount = bankPhotos.count
        sets[setIndex].banks.removeAll { $0.id == lastBank.id }
        sets[setIndex].photos.removeAll { $0.bankId == lastBank.id }
        saveSets()
        print("🗑️ [BANK] Removed bank \(lastBank.position) from set '\(set.name)' (\(removedCount) photos, force=\(force))")
        return true
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
    
    // MARK: - Per-Set Input Method

    /// Assigns an InputMethod to a specific set and persists the change.
    func setInputMethod(_ method: InputMethod, for id: UUID) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[idx].inputMethod = method
        saveSets()
    }

    func updateListItems(setId: UUID, labels: [String]) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }), sets[idx].type == .list else { return }
        let cleaned = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }

        var photosBySymbol = Dictionary(uniqueKeysWithValues: sets[idx].photos.map { ($0.symbol, $0) })
        let existingCount = sets[idx].photos.compactMap { Int($0.symbol) }.max() ?? 0
        let targetCount = cleaned.count

        if targetCount > existingCount {
            for i in (existingCount + 1)...targetCount {
                let symbol = "\(i)"
                photosBySymbol[symbol] = SetPhoto(
                    id: UUID(),
                    setId: setId,
                    symbol: symbol,
                    filename: "list_\(i).jpg",
                    imageData: nil,
                    mediaId: nil,
                    isArchived: false,
                    uploadDate: nil,
                    lastCommentId: nil,
                    uploadStatus: .pending,
                    errorMessage: nil
                )
            }
        }

        sets[idx].listItems = cleaned
        sets[idx].photos = (1...targetCount).compactMap { photosBySymbol["\($0)"] }
        sets[idx].listSeparators = sets[idx].resolvedListSeparators.filter { $0 < targetCount }
        saveSets()
        objectWillChange.send()
    }

    func renameListItem(setId: UUID, symbol: String, label: String) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }), sets[idx].type == .list else { return }
        guard let slot = Int(symbol), slot > 0 else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = sets[idx].listItems ?? sets[idx].listDisplayLabels
        while items.count < slot { items.append("Item \(items.count + 1)") }
        items[slot - 1] = trimmed
        sets[idx].listItems = items
        saveSets()
        objectWillChange.send()
    }

    /// Deletes the list item at the given slot symbol ("1", "2", …), removes its
    /// associated photo, re-numbers higher-slot photos, and adjusts separators.
    func deleteListItem(setId: UUID, symbol: String) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }),
              sets[idx].type == .list,
              let slot = Int(symbol), slot > 0 else { return }

        // 1. Remove the label from listItems
        var items = sets[idx].listItems ?? sets[idx].listDisplayLabels
        if slot - 1 < items.count { items.remove(at: slot - 1) }
        sets[idx].listItems = items.isEmpty ? nil : items

        // 2. Remove the photo for this slot
        sets[idx].photos.removeAll { $0.symbol == symbol }

        // 3. Re-number photos with a higher slot so the sequence stays contiguous
        for i in sets[idx].photos.indices {
            if let photoSlot = Int(sets[idx].photos[i].symbol), photoSlot > slot {
                sets[idx].photos[i].symbol = "\(photoSlot - 1)"
            }
        }

        // 4. Update separators: drop the separator at the deleted slot, decrement those after it
        let updatedSeparators = (sets[idx].listSeparators ?? [])
            .filter { $0 != slot }
            .map   { $0 > slot ? $0 - 1 : $0 }
        sets[idx].listSeparators = updatedSeparators.isEmpty ? nil : updatedSeparators

        saveSets()
        objectWillChange.send()
    }

    func setListLayout(setId: UUID, columns: ListSetColumns? = nil, buttonSize: ListSetButtonSize? = nil) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }), sets[idx].type == .list else { return }
        if let columns { sets[idx].listColumns = columns }
        if let buttonSize { sets[idx].listButtonSize = buttonSize }
        saveSets()
        objectWillChange.send()
    }

    func addListSeparator(setId: UUID, afterSlot slot: Int) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }), sets[idx].type == .list else { return }
        let count = sets[idx].listDisplayLabels.count
        guard slot > 0, slot < count else { return }
        var separators = Set(sets[idx].resolvedListSeparators)
        separators.insert(slot)
        sets[idx].listSeparators = Array(separators).sorted()
        saveSets()
        objectWillChange.send()
    }

    func removeListSeparator(setId: UUID, afterSlot slot: Int) {
        guard let idx = sets.firstIndex(where: { $0.id == setId }), sets[idx].type == .list else { return }
        sets[idx].listSeparators = sets[idx].resolvedListSeparators.filter { $0 != slot }
        saveSets()
        objectWillChange.send()
    }

    /// Returns the active set's resolved input method, or nil when no set is active.
    var activeInputMethod: InputMethod? {
        guard let activeId = ActiveSetSettings.shared.activeSetId else { return nil }
        return sets.first { $0.id == activeId }?.resolvedInputMethod
    }

    /// True when the currently active set uses the given input method.
    func isActiveInput(_ method: InputMethod) -> Bool {
        activeInputMethod == method
    }

    func renameSet(id: UUID, newName: String) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        sets[idx].name = trimmed
        saveSets()
    }

    func deleteSet(id: UUID) {
        // If this set is actively uploading, cancel and reset the upload manager first
        if UploadManager.shared.activeSetId == id {
            print("🗑️ [DATA] Deleting active upload set \(id) — resetting UploadManager")
            UploadManager.shared.resetAllState()
        }
        if ActiveSetSettings.shared.isActive(id) {
            ActiveSetSettings.shared.clearActive()
        }
        sets.removeAll { $0.id == id }
        saveSets()
        addLog(action: "set_deleted", details: "Deleted set \(id)")
        // Backup is manual-only: do not delete the cloud copy automatically.
    }
    
    // MARK: - Persistence
    
    private func saveSets() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: setsKey)
        }
        // Schedule a debounced, *safe* auto-backup so users don't lose set metadata by
        // forgetting to press "Back up now". The safe path never clobbers another
        // account's backup or overwrites real data with an empty local state.
        CloudBackupService.shared.scheduleDebouncedSync()
    }

    /// Forces an immediate iCloud backup. Keep for explicit user actions only.
    func forceImmediateBackup() {
        CloudBackupService.shared.syncToCloud(immediate: true)
    }

    private func loadSets() {
        if let data = UserDefaults.standard.data(forKey: setsKey),
           let decoded = try? JSONDecoder().decode([PhotoSet].self, from: data) {
            sets = migrateDecodedLegacyImagesIfNeeded(decoded)
            print("👤 [ACCOUNT] Loaded \(sets.count) sets for userId='\(currentUserId.isEmpty ? "guest" : currentUserId)'")
        } else {
            sets = []
            print("👤 [ACCOUNT] No sets found for userId='\(currentUserId.isEmpty ? "guest" : currentUserId)'")
        }
    }

    /// Defensive migration for account-scoped sets that still contain legacy inline
    /// `imageData`. Older builds could mark the global migration as complete before
    /// the logged-in user's scoped key was loaded; the next save would then encode
    /// only `imagePath` and permanently drop the inline bytes. Running this at load
    /// time protects every account key before any later saveSets() call.
    private func migrateDecodedLegacyImagesIfNeeded(_ decoded: [PhotoSet]) -> [PhotoSet] {
        var migrated = decoded
        var migratedCount = 0

        for setIndex in migrated.indices {
            let setId = migrated[setIndex].id
            for photoIndex in migrated[setIndex].photos.indices {
                var photo = migrated[setIndex].photos[photoIndex]
                guard photo.imagePath == nil, let imageData = photo.imageData else { continue }

                let path = "photos/\(setId.uuidString)/\(photo.id.uuidString).jpg"
                if let savedPath = SetPhoto.saveImageToFilesystem(data: imageData, path: path) {
                    photo.imagePath = savedPath
                    migrated[setIndex].photos[photoIndex] = photo
                    migratedCount += 1
                } else {
                    print("⚠️ [MIGRATION] Could not persist legacy image for photo \(photo.id)")
                }
            }
        }

        guard migratedCount > 0 else { return decoded }

        if let data = try? JSONEncoder().encode(migrated) {
            UserDefaults.standard.set(data, forKey: setsKey)
            print("✅ [MIGRATION] Repaired \(migratedCount) legacy photo file(s) for '\(setsKey)' before save")
            LogManager.shared.success("Repaired \(migratedCount) set thumbnails before save", category: .general)
        }

        return migrated
    }

    /// Moves sets stored under the old global key ("com.vault.sets") into the
    /// account-scoped key ("com.vault.sets.<userId>"), then removes the old key.
    /// Called on init (one-time migration) AND after a cloud restore (where
    /// CloudBackupService writes data back to the legacy key).
    /// `forceOverwrite`: when true, overwrites any existing scoped data (used on restore).
    func migrateLegacySetsIfNeeded(forceOverwrite: Bool = false) {
        guard let legacyData = UserDefaults.standard.data(forKey: legacySetsKey) else { return }
        let hasScoped = UserDefaults.standard.data(forKey: setsKey) != nil
        if !hasScoped || forceOverwrite {
            UserDefaults.standard.set(legacyData, forKey: setsKey)
            print("👤 [ACCOUNT] Migrated legacy sets → '\(setsKey)' (forceOverwrite=\(forceOverwrite))")
        } else {
            print("👤 [ACCOUNT] Scoped key already has data — skipping migration (use forceOverwrite to override)")
        }
        UserDefaults.standard.removeObject(forKey: legacySetsKey)
        print("👤 [ACCOUNT] Legacy sets key '\(legacySetsKey)' removed")
    }

    private func migrateGuestRestoreToCurrentUserIfNeeded() {
        guard !currentUserId.isEmpty else { return }
        let guestKey = "com.vault.sets.guest"
        let targetKey = setsKey
        guard targetKey != guestKey,
              UserDefaults.standard.data(forKey: targetKey) == nil,
              let guestData = UserDefaults.standard.data(forKey: guestKey) else { return }

        UserDefaults.standard.set(guestData, forKey: targetKey)
        UserDefaults.standard.removeObject(forKey: guestKey)
        print("👤 [ACCOUNT] Moved restored guest sets → '\(targetKey)' after login (\(guestData.count / 1024) KB)")
        LogManager.shared.info("Moved restored guest sets to logged-in account", category: .general)
    }

    /// Called after a cloud restore to reload sets from the newly written UserDefaults.
    /// restoreFromCloud() writes data to the legacy "com.vault.sets" key.
    /// We must run migrateLegacySetsIfNeeded() first so it gets moved to the scoped key,
    /// then loadSets() can find it.
    func reloadAfterRestore() {
        DispatchQueue.main.async {
            print("☁️ [BACKUP] reloadAfterRestore: currentUserId='\(self.currentUserId.isEmpty ? "guest" : self.currentUserId)'")

            // Check what's in UserDefaults before migration
            let scopedKey = self.setsKey
            let legacyData = UserDefaults.standard.data(forKey: self.legacySetsKey)
            let scopedData = UserDefaults.standard.data(forKey: scopedKey)
            print("☁️ [BACKUP]   legacy key '\(self.legacySetsKey)': \(legacyData != nil ? "\(legacyData!.count / 1024) KB" : "EMPTY")")
            print("☁️ [BACKUP]   scoped key '\(scopedKey)': \(scopedData != nil ? "\(scopedData!.count / 1024) KB" : "EMPTY")")

            // CRITICAL: Move restored legacy sets data → account-scoped key.
            // forceOverwrite=true so restore always wins over stale local data.
            self.migrateLegacySetsIfNeeded(forceOverwrite: true)

            // Now load from the scoped key
            self.loadSets()
            self.resetPerformanceCacheAfterRestore()

            let postScopedData = UserDefaults.standard.data(forKey: scopedKey)
            print("☁️ [BACKUP] ✅ Restore complete: \(self.sets.count) sets loaded (scoped key now \(postScopedData != nil ? "\(postScopedData!.count / 1024) KB" : "EMPTY"))")
            LogManager.shared.success("iCloud restore: \(self.sets.count) sets reloaded into DataManager", category: .general)

            // Reload IntegrationsSettings from the freshly-restored UserDefaults values
            // so the in-memory singleton reflects the recovered custom APIs.
            IntegrationsSettings.shared.reloadFromUserDefaults()

            // Reload LockscreenInputSettings (enabled flag; wallpaper image is fetched from iCloud Drive separately)
            LockscreenInputSettings.shared.reloadFromUserDefaults()

            // Reload all trick/settings singletons that are already alive in memory.
            // Without this, UserDefaults is restored but SwiftUI cards can keep showing
            // pre-restore toggles until the next app launch.
            ActiveSetSettings.shared.reloadFromUserDefaults()
            PostPredictionTestMode.shared.reloadFromUserDefaults()
            ForceReelSettings.shared.reloadFromUserDefaults()
            ForcePostSettings.shared.reloadFromUserDefaults()
            ForceNumberRevealSettings.shared.reloadFromUserDefaults()
            FollowingMagicSettings.shared.reloadFromUserDefaults()
            DateForceSettings.shared.reloadFromUserDefaults()
            AmnesiaCarouselSettings.shared.reloadFromUserDefaults()
        }
    }

    /// Forces SwiftUI views bound to `sets` to re-render. Used after iCloud Drive photo
    /// files finish downloading on restore so set thumbnails appear without a relaunch
    /// (SetPhoto.imageData reads lazily from disk, so the model itself doesn't change).
    func notifyPhotosChanged() {
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    private func resetPerformanceCacheAfterRestore() {
        let userId = currentUserId.isEmpty ? (InstagramService.shared.session.userId) : currentUserId
        guard !userId.isEmpty else {
            print("☁️ [BACKUP] Performance cache reset skipped — no current userId")
            return
        }

        let defaults = UserDefaults.standard
        let cacheIsUsable = ProfileCacheService.shared.hasUsablePerformanceCache(userId: userId)
        if cacheIsUsable {
            if let cached = ProfileCacheService.shared.loadProfile(),
               !ProfileCacheService.shared.hasCompletePerformancePreloadCache(cached, userId: userId) {
                defaults.set(false, forKey: "perf_fully_preloaded_\(userId)")
                defaults.set(false, forKey: "perf_optional_preloaded_\(userId)")
                ProfileCacheService.shared.recordPerformancePreloadExit(
                    reason: "restore_partial_cache",
                    userId: userId,
                    cachedCount: cached.cachedMediaURLs.count,
                    requiredCount: ProfileCacheService.shared.requiredPerformancePreloadPosts(for: cached),
                    context: "restore"
                )
                print("☁️ [BACKUP] Preserved partial Performance cache for userId=\(userId) — will continue preload")
                LogManager.shared.warning("Restore preserved partial Performance cache for userId=\(userId); preload required", category: .general)
            } else {
                print("☁️ [BACKUP] Preserved complete Performance profile cache for userId=\(userId)")
                LogManager.shared.info("Restore preserved complete Performance cache for userId=\(userId)", category: .general)
            }
        } else {
            let exactKeys = [
                "perf_fully_preloaded_\(userId)",
                "perf_optional_preloaded_\(userId)",
                "perf_no_more_pages_\(userId)",
                "reels_paginated_\(userId)",
                "tagged_paginated_\(userId)",
                "highlights_checked_at_\(userId)",
                "reels_checked_at_\(userId)",
                "tagged_checked_at_\(userId)"
            ]
            for key in exactKeys { defaults.removeObject(forKey: key) }

            // Only clear unusable/corrupt cache. A valid same-user cache is what lets
            // Performance paint instantly after the secret input closes.
            ProfileCacheService.shared.clearProfile()
        }
        ProfileCacheService.shared.clearRevealState(userId: userId)
        defaults.synchronize()
        print("☁️ [BACKUP] Performance restore state checked for userId=\(userId). Sets and photo files were preserved.")
        LogManager.shared.info("Restore checked Performance cache state; sets preserved", category: .general)
    }
    
    // MARK: - Migration: Move imageData from UserDefaults to Filesystem
    
    /// CRITICAL: Migrates old data structure (imageData in UserDefaults) to new structure (files on disk)
    /// This runs once on app launch to fix the 5MB+ UserDefaults issue
    private func migrateImageDataToFilesystem() {
        let migrationKey = "com.vault.migration.imagedata.v1.\(currentUserId.isEmpty ? "guest" : currentUserId)"
        
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
