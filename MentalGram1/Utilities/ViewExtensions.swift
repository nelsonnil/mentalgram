import SwiftUI

// MARK: - Responsive Design Extensions

extension View {
    /// Padding horizontal adaptativo según tamaño de pantalla
    /// iPhone Pro (<400pt): 12px
    /// iPhone Pro Max (>=400pt): 16px
    func responsiveHorizontalPadding() -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = screenWidth < 400 ? 12 : 16
        return self.padding(.horizontal, padding)
    }
}
