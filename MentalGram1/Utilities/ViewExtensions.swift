import SwiftUI

// MARK: - Responsive Design Extensions

extension View {
    /// Padding horizontal adaptativo según tamaño de pantalla
    /// iPhone SE / standard (<400pt): 12px
    /// iPhone Plus / Pro Max (>=400pt): 16px
    func responsiveHorizontalPadding() -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = screenWidth < 400 ? 12 : 16
        return self.padding(.horizontal, padding)
    }
}

// MARK: - Screen size helpers

extension UIScreen {
    /// true on compact-width phones (<400 pt, incl. iPhone 15/15 Pro at 393 pt)
    /// used to scale down fixed sizes so Performance doesn't look zoomed.
    static var isSmall: Bool { main.bounds.width < 400 }
}

/// Returns one value on iPhone SE / small screens, another on standard and large screens.
func seAdapt<T>(_ small: T, _ standard: T) -> T {
    UIScreen.isSmall ? small : standard
}
