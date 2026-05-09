import Foundation
import Combine

// MARK: - iCloudDriveSync
// Syncs set photo files (Documents/photos/) to the iCloud container so they
// survive an uninstall/reinstall. Files placed inside the ubiquity container
// are automatically uploaded by iOS — no manual API calls needed.

enum DriveError: Error, LocalizedError {
    case containerUnavailable
    case iCloudFull
    case writeFailed(String)

    var isICloudFull: Bool {
        if case .iCloudFull = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .containerUnavailable: return "iCloud Drive is not available on this device."
        case .iCloudFull: return "iCloud storage is full. Free up space to enable photo backup."
        case .writeFailed(let msg): return "Could not save to iCloud Drive: \(msg)"
        }
    }
}

class iCloudDriveSync: ObservableObject {
    static let shared = iCloudDriveSync()

    /// Nil when everything is OK. Non-nil when the last sync had an error.
    @Published private(set) var lastError: DriveError?
    /// Number of photo files currently confirmed in iCloud (counted on last sync).
    @Published private(set) var cloudFileCount: Int = 0

    let containerID = "iCloud.com.nelsonnil.vault"
    private let fm = FileManager.default

    // MARK: - Local root

    var localPhotosRoot: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
    }

    // MARK: - Full diagnostics (call from BackupCard "Drive Diag" button)
    // IMPORTANT: must be called on a background thread (not main thread).

    func runDiagnostics() {
        func log(_ msg: String) {
            print("☁️ [DIAG] \(msg)")
            LogManager.shared.info("☁️ [DIAG] \(msg)", category: .general)
        }

        log("=== iCloud Drive Diagnostics START ===")
        log("containerID: \(containerID)")

        // 1. iCloud identity token
        if let token = fm.ubiquityIdentityToken {
            log("✅ iCloud signed in — token present (\(token))")
        } else {
            log("❌ iCloud identity token = NIL")
            log("   FIX: Settings → [Name] → iCloud → iCloud Drive must be ON")
            log("   Also check: Settings → [Name] → iCloud → Apps Using iCloud → Vault = ON")
        }

        // 2. Container resolution
        if let base = fm.url(forUbiquityContainerIdentifier: containerID) {
            log("✅ Container path: \(base.path)")

            let docs    = base.appendingPathComponent("Documents")
            let photosN = base.appendingPathComponent("Documents/Photos")
            let photosL = base.appendingPathComponent("Documents/photos")
            log("   Documents/ exists: \(fm.fileExists(atPath: docs.path))")
            log("   Documents/Photos  exists: \(fm.fileExists(atPath: photosN.path))")
            log("   Documents/photos  exists: \(fm.fileExists(atPath: photosL.path))")

            // 3. Create Photos dir and write test file
            do {
                try fm.createDirectory(at: photosN, withIntermediateDirectories: true)
                log("✅ createDirectory(Photos) OK")
            } catch {
                log("❌ createDirectory failed: \(error.localizedDescription) code=\((error as NSError).code)")
            }

            let testFile = photosN.appendingPathComponent("diag_\(Int(Date().timeIntervalSince1970)).txt")
            do {
                try "vault_diag".write(to: testFile, atomically: true, encoding: .utf8)
                log("✅ Test file written: \(testFile.lastPathComponent)")

                // Check ubiquitous state of the test file
                let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
                                                  .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]
                if let rv = try? testFile.resourceValues(forKeys: keys) {
                    log("   isUbiquitousItem: \(rv.isUbiquitousItem ?? false)")
                    log("   isUploaded:       \(rv.ubiquitousItemIsUploaded ?? false)")
                    log("   isUploading:      \(rv.ubiquitousItemIsUploading ?? false)")
                    if let uploadErr = rv.ubiquitousItemUploadingError {
                        log("❌ Upload error: \(uploadErr.localizedDescription)")
                    }
                } else {
                    log("   ⚠️ Could not read ubiquitous attributes")
                }
                // Clean up test file
                try? fm.removeItem(at: testFile)
            } catch {
                log("❌ Test file write failed: \(error.localizedDescription) code=\((error as NSError).code)")
                if (error as NSError).code == NSFileWriteOutOfSpaceError {
                    log("   → iCloud storage is FULL")
                }
            }

            // 4. Count set folders in Photos dir
            let allPhotosRoots = [photosN, photosL]
            for root in allPhotosRoots {
                guard fm.fileExists(atPath: root.path),
                      let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
                let setFolders = folders.filter { $0.hasDirectoryPath }
                var totalJpgs = 0
                for sf in setFolders {
                    if let files = try? fm.contentsOfDirectory(at: sf, includingPropertiesForKeys: nil) {
                        totalJpgs += files.filter { $0.pathExtension == "jpg" }.count
                    }
                }
                log("   \(root.lastPathComponent)/ → \(setFolders.count) set folders, \(totalJpgs) JPGs")
            }

        } else {
            log("❌ url(forUbiquityContainerIdentifier:) returned NIL for '\(containerID)'")
            log("   Possible causes:")
            log("   1. iCloud Drive is OFF in Settings → [Name] → iCloud")
            log("   2. Container '\(containerID)' not registered in Apple Developer portal")
            log("   3. Provisioning profile does not include iCloud entitlement")
        }

        // 5. Local photos root
        let localExists = fm.fileExists(atPath: localPhotosRoot.path)
        log("Local photos root exists: \(localExists) — \(localPhotosRoot.path)")
        if localExists, let folders = try? fm.contentsOfDirectory(at: localPhotosRoot, includingPropertiesForKeys: nil) {
            log("Local set folders: \(folders.filter { $0.hasDirectoryPath }.count)")
        }

        log("cloudFileCount (last sync): \(cloudFileCount)")
        log("lastError: \(lastError?.localizedDescription ?? "none")")
        log("=== iCloud Drive Diagnostics END ===")
        log("📍 To find the folder: Files app → Browse → iCloud Drive → Vault → Photos")
        log("   If 'Vault' not listed: Settings → [Name] → iCloud → Show All → enable Vault")
    }

    // MARK: - iCloud root resolution (with retry)

    /// MUST be called from a background thread — url(forUbiquityContainerIdentifier:) blocks.
    /// Retries up to `maxAttempts` times with `delaySecs` between each attempt.
    func iCloudPhotosRoot(maxAttempts: Int = 5, delaySecs: Double = 2.0) -> URL? {
        for attempt in 1...maxAttempts {
            if let base = fm.url(forUbiquityContainerIdentifier: containerID) {
                let dir = base.appendingPathComponent("Documents/Photos", isDirectory: true)
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    print("☁️ [DRIVE] iCloud root resolved on attempt \(attempt)")
                    print("☁️ [DRIVE]   container path: \(base.path)")
                    print("☁️ [DRIVE]   Photos folder:  \(dir.path)")
                    return dir
                } catch let error as NSError {
                    if error.code == NSFileWriteOutOfSpaceError || error.domain == NSCocoaErrorDomain && error.code == 640 {
                        print("☁️ [DRIVE] ❌ iCloud FULL — cannot create Photos folder")
                        DispatchQueue.main.async { self.lastError = .iCloudFull }
                    } else {
                        print("☁️ [DRIVE] Could not create iCloud dir (attempt \(attempt)): \(error)")
                    }
                    return nil
                }
            }
            if attempt < maxAttempts {
                print("☁️ [DRIVE] Container unavailable — retrying in \(delaySecs)s (attempt \(attempt)/\(maxAttempts))")
                Thread.sleep(forTimeInterval: delaySecs)
            }
        }
        print("☁️ [DRIVE] ❌ iCloud container unavailable after \(maxAttempts) attempts. Is iCloud Drive enabled?")
        DispatchQueue.main.async { self.lastError = .containerUnavailable }
        return nil
    }

    // MARK: - Ensure folder exists (called at launch)

    /// Creates the Vault/Photos folder in iCloud Drive, places a marker file, and
    /// migrates any files from the legacy "photos" folder into "Photos" to eliminate duplicates.
    func ensureCloudFolderExists() {
        Task.detached(priority: .background) {
            guard let base = self.fm.url(forUbiquityContainerIdentifier: self.containerID) else {
                print("☁️ [DRIVE] ensureCloudFolderExists: container unavailable")
                DispatchQueue.main.async { self.lastError = .containerUnavailable }
                return
            }

            let newRoot    = base.appendingPathComponent("Documents/Photos", isDirectory: true)
            let legacyRoot = base.appendingPathComponent("Documents/photos", isDirectory: true)

            // Create the canonical Photos folder
            try? self.fm.createDirectory(at: newRoot, withIntermediateDirectories: true)

            // Marker file so folder is visible in Files even with no photos
            let marker = newRoot.appendingPathComponent(".vault_folder", isDirectory: false)
            if !self.fm.fileExists(atPath: marker.path) {
                do {
                    try "Vault photo backup.".write(to: marker, atomically: true, encoding: .utf8)
                    print("☁️ [DRIVE] Marker file created")
                } catch let error as NSError {
                    if error.code == NSFileWriteOutOfSpaceError {
                        print("☁️ [DRIVE] ❌ iCloud FULL — marker file not written")
                        DispatchQueue.main.async { self.lastError = .iCloudFull }
                        return
                    }
                }
            }

            // Migrate legacy "photos" folder → "Photos": move any set folders not already in Photos
            if self.fm.fileExists(atPath: legacyRoot.path),
               let legacyFolders = try? self.fm.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil) {
                var moved = 0
                for folder in legacyFolders where folder.hasDirectoryPath {
                    let dest = newRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                    if !self.fm.fileExists(atPath: dest.path) {
                        try? self.fm.moveItem(at: folder, to: dest)
                        moved += 1
                    }
                }
                // Remove legacy root only when empty
                let remaining = (try? self.fm.contentsOfDirectory(atPath: legacyRoot.path))?.count ?? 0
                if remaining == 0 {
                    try? self.fm.removeItem(at: legacyRoot)
                    print("☁️ [DRIVE] Legacy 'photos' folder removed (moved \(moved) sets → 'Photos')")
                } else {
                    print("☁️ [DRIVE] Legacy 'photos' folder still has \(remaining) items — not removed yet")
                }
            }

            DispatchQueue.main.async { self.lastError = nil }
        }
    }

    // MARK: - Upload

    /// Uploads ALL files from Documents/photos/ to iCloud.
    /// Returns via closure: (uploaded: Int, skipped: Int, error: DriveError?).
    func syncAllPhotosToCloud(completion: ((Int, Int, DriveError?) -> Void)? = nil) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot() else {
                completion?(0, 0, self.lastError ?? .containerUnavailable)
                return
            }
            let localRoot = self.localPhotosRoot

            // Ensure local root exists
            try? self.fm.createDirectory(at: localRoot, withIntermediateDirectories: true)

            // Write marker so folder appears in Files even if no photos yet
            let marker = cloudRoot.appendingPathComponent(".vault_folder", isDirectory: false)
            if !self.fm.fileExists(atPath: marker.path) {
                try? "Vault photo backup folder.".write(to: marker, atomically: true, encoding: .utf8)
            }

            guard let setFolders = try? self.fm.contentsOfDirectory(
                at: localRoot, includingPropertiesForKeys: nil
            ) else {
                print("☁️ [DRIVE] No local photo folders found — cloud folder created and ready")
                completion?(0, 0, nil)
                return
            }

            var uploaded = 0
            var skipped  = 0
            var hitFull  = false

            for setFolder in setFolders where setFolder.hasDirectoryPath {
                let cloudSetFolder = cloudRoot.appendingPathComponent(
                    setFolder.lastPathComponent, isDirectory: true)
                try? self.fm.createDirectory(at: cloudSetFolder, withIntermediateDirectories: true)

                guard let photoFiles = try? self.fm.contentsOfDirectory(
                    at: setFolder, includingPropertiesForKeys: nil
                ) else { continue }

                for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                    let dest = cloudSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                    if self.fm.fileExists(atPath: dest.path) {
                        skipped += 1
                        continue
                    }
                    do {
                        try self.fm.copyItem(at: photoFile, to: dest)
                        uploaded += 1
                    } catch let error as NSError {
                        if error.code == NSFileWriteOutOfSpaceError {
                            print("☁️ [DRIVE] ❌ iCloud FULL while uploading \(photoFile.lastPathComponent)")
                            hitFull = true
                            break
                        } else {
                            print("☁️ [DRIVE] Failed to copy \(photoFile.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
                if hitFull { break }
            }

            // Count total files now in the cloud for the status indicator
            let cloudCount = self.countCloudFiles(at: cloudRoot)

            let driveError: DriveError? = hitFull ? .iCloudFull : nil
            DispatchQueue.main.async {
                self.lastError = driveError
                self.cloudFileCount = cloudCount
            }

            let statusEmoji = hitFull ? "⚠️" : "✅"
            print("☁️ [DRIVE] \(statusEmoji) Sync complete — \(uploaded) uploaded, \(skipped) already in cloud, \(cloudCount) total in cloud")
            if hitFull {
                LogManager.shared.warning("iCloud storage is full — \(uploaded) photos uploaded before space ran out", category: .general)
            }
            completion?(uploaded, skipped, driveError)
        }
    }

    /// Uploads photos for a single set (faster, use after creating/updating one set).
    func syncSetPhotos(setId: UUID) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot(maxAttempts: 3, delaySecs: 1.0) else { return }
            let setFolderName = setId.uuidString
            let localSetFolder = self.localPhotosRoot.appendingPathComponent(
                setFolderName, isDirectory: true)

            guard self.fm.fileExists(atPath: localSetFolder.path),
                  let photoFiles = try? self.fm.contentsOfDirectory(
                      at: localSetFolder, includingPropertiesForKeys: nil
                  ) else { return }

            let cloudSetFolder = cloudRoot.appendingPathComponent(setFolderName, isDirectory: true)
            try? self.fm.createDirectory(at: cloudSetFolder, withIntermediateDirectories: true)

            var uploaded = 0
            for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                let dest = cloudSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                if self.fm.fileExists(atPath: dest.path) { continue }
                do {
                    try self.fm.copyItem(at: photoFile, to: dest)
                    uploaded += 1
                } catch let error as NSError {
                    if error.code == NSFileWriteOutOfSpaceError {
                        print("☁️ [DRIVE] ❌ iCloud FULL — set \(setFolderName.prefix(8)) sync stopped")
                        DispatchQueue.main.async { self.lastError = .iCloudFull }
                        return
                    }
                    print("☁️ [DRIVE] Failed to copy \(photoFile.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { self.lastError = nil }
            print("☁️ [DRIVE] Set \(setFolderName.prefix(8))… → \(uploaded) files uploaded")
        }
    }

    // MARK: - Download (restore after reinstall)

    /// Downloads ALL photo files from iCloud to local Documents/photos/.
    /// Checks both the current "Documents/Photos" folder and the legacy "Documents/photos"
    /// folder for backward compatibility with existing user backups.
    func downloadAllPhotosFromCloud(completion: @escaping (Int) -> Void = { _ in }) {
        Task.detached(priority: .background) {
            let localRoot = self.localPhotosRoot
            try? self.fm.createDirectory(at: localRoot, withIntermediateDirectories: true)

            // Try both possible cloud root paths: new "Photos" and legacy "photos"
            var cloudRoots: [URL] = []
            if let base = self.fm.url(forUbiquityContainerIdentifier: self.containerID) {
                let newPath    = base.appendingPathComponent("Documents/Photos", isDirectory: true)
                let legacyPath = base.appendingPathComponent("Documents/photos", isDirectory: true)
                if self.fm.fileExists(atPath: newPath.path)    { cloudRoots.append(newPath) }
                if self.fm.fileExists(atPath: legacyPath.path) { cloudRoots.append(legacyPath) }
                print("☁️ [DRIVE] Download: checking \(cloudRoots.count) cloud root(s)")
            } else {
                print("☁️ [DRIVE] iCloud container unavailable — cannot download")
                DispatchQueue.main.async { self.lastError = .containerUnavailable }
                completion(0)
                return
            }

            guard !cloudRoots.isEmpty else {
                print("☁️ [DRIVE] No cloud photo folders found (neither Photos nor photos)")
                completion(0)
                return
            }

            var downloaded = 0
            for cloudRoot in cloudRoots {
                guard let setFolders = try? self.fm.contentsOfDirectory(
                    at: cloudRoot, includingPropertiesForKeys: nil
                ) else { continue }

                for setFolder in setFolders where setFolder.hasDirectoryPath {
                    let localSetFolder = localRoot.appendingPathComponent(
                        setFolder.lastPathComponent, isDirectory: true)
                    try? self.fm.createDirectory(at: localSetFolder, withIntermediateDirectories: true)

                    guard let photoFiles = try? self.fm.contentsOfDirectory(
                        at: setFolder, includingPropertiesForKeys: nil
                    ) else { continue }

                    for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                        try? self.fm.startDownloadingUbiquitousItem(at: photoFile)
                        let dest = localSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                        if !self.fm.fileExists(atPath: dest.path) {
                            do {
                                try self.fm.copyItem(at: photoFile, to: dest)
                                downloaded += 1
                            } catch {
                                print("☁️ [DRIVE] File not ready yet: \(photoFile.lastPathComponent)")
                            }
                        }
                    }
                }
            }
            print("☁️ [DRIVE] ✅ Downloaded \(downloaded) photo files from iCloud Drive")
            completion(downloaded)
        }
    }

    /// Removes the iCloud copy of a deleted set.
    func deleteSetFromCloud(setId: UUID) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot(maxAttempts: 2, delaySecs: 1.0) else { return }
            let cloudSetFolder = cloudRoot.appendingPathComponent(setId.uuidString, isDirectory: true)
            try? self.fm.removeItem(at: cloudSetFolder)
            print("☁️ [DRIVE] Deleted set \(setId.uuidString.prefix(8))… from iCloud Drive")
        }
    }

    // MARK: - Helpers

    private func countCloudFiles(at root: URL) -> Int {
        guard let setFolders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for folder in setFolders where folder.hasDirectoryPath {
            if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                count += files.filter { $0.pathExtension == "jpg" }.count
            }
        }
        return count
    }
}
