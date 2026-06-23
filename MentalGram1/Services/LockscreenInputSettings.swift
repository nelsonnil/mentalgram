import Foundation
import Combine
import UIKit

class LockscreenInputSettings: ObservableObject {
    static let shared = LockscreenInputSettings()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "lockscreenInputEnabled") }
    }

    /// JPEG data for the wallpaper image, persisted in UserDefaults.
    @Published var wallpaperData: Data? {
        didSet { UserDefaults.standard.set(wallpaperData, forKey: "lockscreenWallpaperData") }
    }

    /// Decoded wallpaper (not persisted — rebuilt on demand).
    var wallpaperImage: UIImage? {
        guard let data = wallpaperData else { return nil }
        return UIImage(data: data)
    }

    /// Feature is only active when enabled AND a wallpaper has been chosen.
    var isReady: Bool { isEnabled && wallpaperData != nil }

    /// True as soon as a wallpaper exists, regardless of the legacy `isEnabled`
    /// flag. Used by the per-set input system where the lockscreen is enabled by
    /// selecting it as a set's input, not by a global toggle.
    var hasWallpaper: Bool { wallpaperData != nil }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "lockscreenInputEnabled")
        self.wallpaperData = UserDefaults.standard.data(forKey: "lockscreenWallpaperData")
    }

    func saveWallpaper(_ image: UIImage) {
        wallpaperData = image.jpegData(compressionQuality: 0.85)
        uploadWallpaperToCloud()
    }

    func clearWallpaper() {
        wallpaperData = nil
        deleteWallpaperFromCloud()
    }

    // MARK: - iCloud Drive sync

    /// Uploads the wallpaper JPEG to iCloud Drive so it survives a reinstall.
    func uploadWallpaperToCloud() {
        guard let data = wallpaperData else { return }
        Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let base = fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else {
                print("🔒 [LOCKSCREEN] iCloud container unavailable — wallpaper not backed up")
                return
            }
            let docsDir = base.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
            let dest = docsDir.appendingPathComponent("lockscreen_wallpaper.jpg")
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try data.write(to: dest, options: .atomic)
                print("🔒 [LOCKSCREEN] ✅ Wallpaper synced to iCloud Drive (\(data.count / 1024) KB)")
            } catch {
                print("🔒 [LOCKSCREEN] ❌ Could not sync wallpaper: \(error.localizedDescription)")
            }
        }
    }

    /// Downloads wallpaper from iCloud Drive and restores it into UserDefaults + memory.
    /// Uses the shared materializing helper so fresh-reinstall placeholders are handled.
    func downloadWallpaperFromCloud(completion: @escaping (Bool) -> Void = { _ in }) {
        let tmpURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lockscreen_wallpaper_restore.jpg")
        iCloudDriveSync.shared.restoreContainerFile(named: "lockscreen_wallpaper.jpg", to: tmpURL) { success in
            guard success, let data = try? Data(contentsOf: tmpURL) else {
                print("🔒 [LOCKSCREEN] No wallpaper restored from iCloud Drive")
                completion(false)
                return
            }
            try? FileManager.default.removeItem(at: tmpURL)
            DispatchQueue.main.async {
                self.wallpaperData = data   // triggers didSet → saves to UserDefaults
                print("🔒 [LOCKSCREEN] ✅ Wallpaper restored from iCloud Drive (\(data.count / 1024) KB)")
                completion(true)
            }
        }
    }

    private func deleteWallpaperFromCloud() {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let base = fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else { return }
            let cloudFile = base.appendingPathComponent("Documents/lockscreen_wallpaper.jpg")
            try? fm.removeItem(at: cloudFile)
            print("🔒 [LOCKSCREEN] Deleted wallpaper from iCloud Drive")
        }
    }

    // MARK: - Restore reload

    /// Re-reads the enabled flag from UserDefaults after an iCloud restore.
    func reloadFromUserDefaults() {
        isEnabled = UserDefaults.standard.bool(forKey: "lockscreenInputEnabled")
        wallpaperData = UserDefaults.standard.data(forKey: "lockscreenWallpaperData")
        print("🔒 [LOCKSCREEN] Reloaded settings from UserDefaults after restore")
    }
}
