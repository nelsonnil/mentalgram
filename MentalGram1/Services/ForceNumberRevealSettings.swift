import Foundation
import Combine

/// Enables the "Force Number Reveal" feature.
/// When active: swiping on the grid builds a digit buffer, and tapping the Posts tab icon
/// unarchives the photo whose symbol matches each digit in the corresponding bank.
class ForceNumberRevealSettings: ObservableObject {
    static let shared = ForceNumberRevealSettings()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceNumberRevealEnabled") }
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "forceNumberRevealEnabled")
    }
}
