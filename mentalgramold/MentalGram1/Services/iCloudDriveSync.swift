import Foundation

// MARK: - iCloudDriveSync
// Syncs set photo files (Documents/photos/) to the iCloud container so they
// survive an uninstall/reinstall. Files placed inside the ubiquity container
// are automatically uploaded by iOS — no manual API calls needed.

class iCloudDriveSync {
    static let shared = iCloudDriveSync()

    private let containerID = "iCloud.com.nelsonnil.vault"
    private let fm = FileManager.default

    private var localPhotosRoot: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
    }

    // Resolves the iCloud container URL on a background thread (can block).
    private func iCloudPhotosRoot() -> URL? {
        guard let base = fm.url(forUbiquityContainerIdentifier: containerID) else {
            print("☁️ [DRIVE] iCloud container unavailable")
            return nil
        }
        let dir = base.appendingPathComponent("Documents/photos", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Upload

    /// Uploads ALL files from Documents/photos/ to iCloud.
    /// Call after saving a set or completing an upload batch.
    func syncAllPhotosToCloud() {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot() else { return }
            let localRoot = self.localPhotosRoot

            guard let setFolders = try? self.fm.contentsOfDirectory(
                at: localRoot, includingPropertiesForKeys: nil
            ) else {
                print("☁️ [DRIVE] No local photo folders to sync")
                return
            }

            var uploaded = 0
            for setFolder in setFolders where setFolder.hasDirectoryPath {
                let cloudSetFolder = cloudRoot.appendingPathComponent(setFolder.lastPathComponent, isDirectory: true)
                try? self.fm.createDirectory(at: cloudSetFolder, withIntermediateDirectories: true)

                guard let photoFiles = try? self.fm.contentsOfDirectory(
                    at: setFolder, includingPropertiesForKeys: nil
                ) else { continue }

                for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                    let dest = cloudSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                    // Only copy if destination doesn't exist or source is newer
                    if !self.fm.fileExists(atPath: dest.path) {
                        do {
                            try self.fm.copyItem(at: photoFile, to: dest)
                            uploaded += 1
                        } catch {
                            print("☁️ [DRIVE] Failed to copy \(photoFile.lastPathComponent): \(error)")
                        }
                    }
                }
            }
            print("☁️ [DRIVE] ✅ Synced \(uploaded) new photo files to iCloud Drive")
        }
    }

    /// Uploads photos for a single set (faster, use after creating/updating one set).
    func syncSetPhotos(setId: UUID) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot() else { return }
            let setFolderName = setId.uuidString
            let localSetFolder = self.localPhotosRoot.appendingPathComponent(setFolderName, isDirectory: true)

            guard self.fm.fileExists(atPath: localSetFolder.path),
                  let photoFiles = try? self.fm.contentsOfDirectory(
                      at: localSetFolder, includingPropertiesForKeys: nil
                  ) else { return }

            let cloudSetFolder = cloudRoot.appendingPathComponent(setFolderName, isDirectory: true)
            try? self.fm.createDirectory(at: cloudSetFolder, withIntermediateDirectories: true)

            var uploaded = 0
            for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                let dest = cloudSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                if !self.fm.fileExists(atPath: dest.path) {
                    try? self.fm.copyItem(at: photoFile, to: dest)
                    uploaded += 1
                }
            }
            print("☁️ [DRIVE] Set \(setFolderName.prefix(8))… → \(uploaded) files uploaded")
        }
    }

    // MARK: - Download (restore after reinstall)

    /// Downloads ALL photo files from iCloud to local Documents/photos/.
    /// Call once after restoring settings from CloudBackupService.
    func downloadAllPhotosFromCloud(completion: @escaping (Int) -> Void = { _ in }) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot() else {
                completion(0)
                return
            }
            let localRoot = self.localPhotosRoot
            try? self.fm.createDirectory(at: localRoot, withIntermediateDirectories: true)

            guard let setFolders = try? self.fm.contentsOfDirectory(
                at: cloudRoot, includingPropertiesForKeys: nil
            ) else {
                print("☁️ [DRIVE] No cloud photo folders found")
                completion(0)
                return
            }

            var downloaded = 0
            for setFolder in setFolders where setFolder.hasDirectoryPath {
                let localSetFolder = localRoot.appendingPathComponent(setFolder.lastPathComponent, isDirectory: true)
                try? self.fm.createDirectory(at: localSetFolder, withIntermediateDirectories: true)

                guard let photoFiles = try? self.fm.contentsOfDirectory(
                    at: setFolder, includingPropertiesForKeys: nil
                ) else { continue }

                for photoFile in photoFiles where photoFile.pathExtension == "jpg" {
                    // Trigger download if the file is just an iCloud placeholder
                    try? self.fm.startDownloadingUbiquitousItem(at: photoFile)

                    let dest = localSetFolder.appendingPathComponent(photoFile.lastPathComponent)
                    if !self.fm.fileExists(atPath: dest.path) {
                        do {
                            try self.fm.copyItem(at: photoFile, to: dest)
                            downloaded += 1
                        } catch {
                            // File might still be downloading from iCloud — retry later
                            print("☁️ [DRIVE] File not ready yet: \(photoFile.lastPathComponent)")
                        }
                    }
                }
            }
            print("☁️ [DRIVE] ✅ Downloaded \(downloaded) photo files from iCloud Drive")
            completion(downloaded)
        }
    }

    /// Removes the iCloud copy of a deleted set so it doesn't accumulate.
    func deleteSetFromCloud(setId: UUID) {
        Task.detached(priority: .background) {
            guard let cloudRoot = self.iCloudPhotosRoot() else { return }
            let cloudSetFolder = cloudRoot.appendingPathComponent(setId.uuidString, isDirectory: true)
            try? self.fm.removeItem(at: cloudSetFolder)
            print("☁️ [DRIVE] Deleted set \(setId.uuidString.prefix(8))… from iCloud Drive")
        }
    }
}
