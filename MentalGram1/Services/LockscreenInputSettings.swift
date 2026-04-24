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

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "lockscreenInputEnabled")
        self.wallpaperData = UserDefaults.standard.data(forKey: "lockscreenWallpaperData")
    }

    func saveWallpaper(_ image: UIImage) {
        wallpaperData = image.jpegData(compressionQuality: 0.85)
    }

    func clearWallpaper() {
        wallpaperData = nil
    }
}
