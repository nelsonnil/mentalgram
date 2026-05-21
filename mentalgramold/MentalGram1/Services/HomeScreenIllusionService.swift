import UIKit
import Combine

/// Manages the "Fake Home Screen" screenshot used to overlay Performance view.
/// The image is stored as JPEG in the app's Documents directory so it survives
/// app updates and is excluded from iCloud backup.
final class HomeScreenIllusionService: ObservableObject {
    static let shared = HomeScreenIllusionService()

    @Published private(set) var screenshot: UIImage? = nil

    private let fileName = "fake_homescreen.jpg"
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    var hasImage: Bool { screenshot != nil }

    /// Saves a new screenshot, overwriting any previous one.
    func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        try? data.write(to: fileURL, options: .atomic)
        DispatchQueue.main.async { self.screenshot = image }
    }

    /// Deletes the stored screenshot.
    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
        DispatchQueue.main.async { self.screenshot = nil }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return }
        screenshot = image
    }
}
