import SwiftUI

/// Renders an Instagram icon from the asset catalog.
/// Falls back to an SF Symbol if the asset hasn't been replaced yet.
struct IGIcon: View {
    let asset: String
    let fallback: String
    var size: CGFloat = 24
    var color: Color = .black

    var body: some View {
        if UIImage(named: asset) != nil {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundColor(color)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size))
                .foregroundColor(color)
        }
    }
}
