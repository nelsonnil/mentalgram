import UIKit
import Combine

enum PerformanceCoverMode: String, CaseIterable, Identifiable {
    case off
    case homeScreen
    case screenOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .homeScreen: return "Fake Home Screen"
        case .screenOff: return "Fake Screen Off"
        }
    }

    var subtitle: String {
        switch self {
        case .off:
            return "Open Performance directly."
        case .homeScreen:
            return "Show your uploaded home screen screenshot first."
        case .screenOff:
            return "Show a black screen first, as if the phone were off."
        }
    }

    var icon: String {
        switch self {
        case .off: return "xmark.circle"
        case .homeScreen: return "iphone.homebutton"
        case .screenOff: return "moon.fill"
        }
    }
}

/// Manages the "Fake Home Screen" screenshot used to overlay Performance view.
/// The image is stored as JPEG in the app's Documents directory and is also
/// synced to iCloud Drive so it survives uninstall/reinstall.
final class HomeScreenIllusionService: ObservableObject {
    static let shared = HomeScreenIllusionService()

    @Published private(set) var screenshot: UIImage? = nil

    private let fileName = "fake_homescreen.jpg"
    private let fm = FileManager.default

    private var fileURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    var hasImage: Bool { screenshot != nil }

    /// Saves a new screenshot, overwriting any previous one, and syncs to iCloud Drive.
    func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        try? data.write(to: fileURL, options: .atomic)
        DispatchQueue.main.async { self.screenshot = image }
        uploadToCloud(data: data)
    }

    /// Deletes the stored screenshot locally and from iCloud Drive.
    func delete() {
        try? fm.removeItem(at: fileURL)
        DispatchQueue.main.async { self.screenshot = nil }
        deleteFromCloud()
    }

    // MARK: - iCloud Drive sync

    /// Uploads the current screenshot to the iCloud Drive container root.
    func uploadToCloud(data: Data? = nil) {
        Task.detached(priority: .background) {
            guard let base = self.fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else {
                print("🖼️ [ILLUSION] iCloud container unavailable — screenshot not backed up")
                return
            }
            let docsDir = base.appendingPathComponent("Documents", isDirectory: true)
            try? self.fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
            let dest = docsDir.appendingPathComponent(self.fileName)
            let payload = data ?? (try? Data(contentsOf: self.fileURL))
            guard let payload else { return }
            do {
                if self.fm.fileExists(atPath: dest.path) {
                    try self.fm.removeItem(at: dest)
                }
                try payload.write(to: dest, options: .atomic)
                print("🖼️ [ILLUSION] ✅ Screenshot synced to iCloud Drive (\(payload.count / 1024) KB)")
            } catch {
                print("🖼️ [ILLUSION] ❌ Could not sync screenshot: \(error.localizedDescription)")
            }
        }
    }

    /// Downloads the screenshot from iCloud Drive and saves it locally if not present.
    /// Uses the shared materializing helper so fresh-reinstall placeholders are handled.
    func downloadFromCloud(completion: @escaping (Bool) -> Void = { _ in }) {
        iCloudDriveSync.shared.restoreContainerFile(named: fileName, to: fileURL) { success in
            guard success else {
                print("🖼️ [ILLUSION] No screenshot restored from iCloud Drive")
                completion(false)
                return
            }
            print("🖼️ [ILLUSION] ✅ Screenshot restored from iCloud Drive")
            DispatchQueue.main.async {
                self.loadFromDisk()
                completion(true)
            }
        }
    }

    private func deleteFromCloud() {
        Task.detached(priority: .background) {
            guard let base = self.fm.url(forUbiquityContainerIdentifier: iCloudDriveSync.shared.containerID) else { return }
            let cloudFile = base.appendingPathComponent("Documents/\(self.fileName)")
            try? self.fm.removeItem(at: cloudFile)
            print("🖼️ [ILLUSION] Deleted screenshot from iCloud Drive")
        }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard fm.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return }
        screenshot = image
    }
}
