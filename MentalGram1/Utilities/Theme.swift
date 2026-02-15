import SwiftUI

// MARK: - Vault Theme System

struct VaultTheme {
    
    // MARK: - Colors
    
    struct Colors {
        // Backgrounds
        static let background = Color(hex: "0A0A0A")
        static let backgroundSecondary = Color(hex: "1A1A1A")
        static let cardBackground = Color(hex: "1F1F1F")
        static let cardBorder = Color(hex: "2D2D2D")
        
        // Primary Accent (Purple - Magic theme)
        static let primary = Color(hex: "A855F7")
        static let primaryDark = Color(hex: "7C3AED")
        
        // Secondary Accent (Cyan - Tech theme)
        static let secondary = Color(hex: "06B6D4")
        static let secondaryDark = Color(hex: "0284C7")
        
        // Status Colors
        static let success = Color(hex: "10B981")
        static let warning = Color(hex: "F59E0B")
        static let error = Color(hex: "EF4444")
        static let info = Color(hex: "3B82F6")
        
        // Text Colors
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "A1A1AA")
        static let textTertiary = Color(hex: "71717A")
        static let textDisabled = Color(hex: "52525B")
        
        // Gradients
        static let gradientPrimary = LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let gradientSuccess = LinearGradient(
            colors: [success, Color(hex: "06D6A0")],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        static let gradientWarning = LinearGradient(
            colors: [warning, Color(hex: "FBBF24")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Typography
    
    struct Typography {
        // Display
        static func displayLarge() -> Font { .system(size: 32, weight: .bold, design: .rounded) }
        static func display() -> Font { .system(size: 28, weight: .bold, design: .rounded) }
        
        // Title
        static func titleLarge() -> Font { .system(size: 24, weight: .bold, design: .default) }
        static func title() -> Font { .system(size: 20, weight: .semibold, design: .default) }
        static func titleSmall() -> Font { .system(size: 17, weight: .semibold, design: .default) }
        
        // Body
        static func body() -> Font { .system(size: 15, weight: .regular, design: .default) }
        static func bodyBold() -> Font { .system(size: 15, weight: .semibold, design: .default) }
        
        // Caption
        static func caption() -> Font { .system(size: 13, weight: .regular, design: .default) }
        static func captionBold() -> Font { .system(size: 13, weight: .semibold, design: .default) }
        static func captionSmall() -> Font { .system(size: 11, weight: .regular, design: .default) }
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        static let small = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.2), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.3), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(8))
        
        // Glow effects
        static let glowPurple = (color: Colors.primary.opacity(0.3), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(0))
        static let glowCyan = (color: Colors.secondary.opacity(0.3), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(0))
    }
}

// MARK: - Color Extension (Hex support)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions for Theme

extension View {
    func cardStyle() -> some View {
        self
            .background(VaultTheme.Colors.cardBackground)
            .cornerRadius(VaultTheme.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
                    .stroke(VaultTheme.Colors.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: VaultTheme.Shadows.medium.color,
                radius: VaultTheme.Shadows.medium.radius,
                x: VaultTheme.Shadows.medium.x,
                y: VaultTheme.Shadows.medium.y
            )
    }
    
    func glowEffect(color: Color, radius: CGFloat = 20) -> some View {
        self
            .shadow(color: color.opacity(0.3), radius: radius, x: 0, y: 0)
    }
}
