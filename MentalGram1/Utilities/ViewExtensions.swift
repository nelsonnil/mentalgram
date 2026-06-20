import SwiftUI

// MARK: - Responsive Design Extensions

extension View {
    /// Padding horizontal adaptativo según tamaño de pantalla
    /// iPhone SE / 15 / 15 Pro (isSmall): 12px
    /// iPhone Plus / Pro Max (!isSmall): 16px
    func responsiveHorizontalPadding() -> some View {
        let padding: CGFloat = UIScreen.isSmall ? 12 : 16
        return self.padding(.horizontal, padding)
    }
}

// MARK: - Screen size helpers

extension UIScreen {
    /// true on compact-width phones (SE, 15 standard, 15 Pro) — false on Plus/Pro Max.
    /// Prefer the physical model for Plus/Pro Max devices because Display Zoom can
    /// report a compact render size even on a large phone.
    static var isSmall: Bool {
        if isPlusOrProMaxDevice { return false }
        return main.nativeBounds.width < 1200
    }

    private static var isPlusOrProMaxDevice: Bool {
        let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        let identifier = simulatorModel ?? DeviceInfo.shared.modelIdentifier

        switch identifier {
        case
            "iPhone17,4", "iPhone17,2", // iPhone 16 Plus / Pro Max
            "iPhone15,5", "iPhone16,2", // iPhone 15 Plus / Pro Max
            "iPhone14,8", "iPhone15,3", // iPhone 14 Plus / Pro Max
            "iPhone14,3",               // iPhone 13 Pro Max
            "iPhone13,4",               // iPhone 12 Pro Max
            "iPhone12,5",               // iPhone 11 Pro Max
            "iPhone11,4", "iPhone11,6": // iPhone XS Max
            return true
        default:
            return false
        }
    }
}

/// Returns one value on iPhone SE / small screens, another on standard and large screens.
func seAdapt<T>(_ small: T, _ standard: T) -> T {
    UIScreen.isSmall ? small : standard
}
