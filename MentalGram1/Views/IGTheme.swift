import SwiftUI

// MARK: - Adaptive UIColor constants for Instagram-accurate dark mode
// Instagram uses pure black (#000000) as page background in dark mode (OLED),
// not iOS systemBackground (#1C1C1E). Button pills are #262626, surfaces #121212.
extension UIColor {
    /// Page background: pure black in dark mode, white in light mode
    static let igPageBackground = UIColor { t in
        t.userInterfaceStyle == .dark ? .black : .white
    }
    /// Secondary surface: #121212 dark · secondarySystemBackground light
    static let igSecondaryBackground = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1)
            : .secondarySystemBackground
    }
    /// Action button fill (Following/Message/Edit pills): #262626 dark · systemGray6 light
    static let igButtonFill = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.149, blue: 0.149, alpha: 1)
            : .systemGray6
    }
}

/// Semantic color palette for the fake Instagram UI.
/// Uses UIKit adaptive colors where possible so they react to system
/// light / dark mode automatically, without needing an explicit @Environment
/// read in every sub-view. Custom overrides (button fill, glass pill) are
/// expressed as Color literals or via the colorScheme-aware helpers below.
struct IGTheme {
    let scheme: ColorScheme
    var isDark: Bool { scheme == .dark }

    // MARK: Backgrounds
    /// Instagram uses pure #000000 in dark mode (OLED black), not iOS systemBackground (#1C1C1E)
    var background:          Color { Color(UIColor.igPageBackground) }
    /// Secondary surface: #F2F2F7 light · #121212 dark
    var secondaryBackground: Color { Color(UIColor.igSecondaryBackground) }

    // MARK: Text
    var primaryText:   Color { Color(UIColor.label) }
    var secondaryText: Color { Color(UIColor.secondaryLabel) }
    var tertiaryText:  Color { Color(UIColor.tertiaryLabel) }

    // MARK: Interactive
    /// "Following / Message / Email" pill button fill — #262626 dark · systemGray6 light
    var buttonFill: Color { Color(UIColor.igButtonFill) }
    /// External URL in bio
    var externalLink: Color { Color(UIColor.link) }

    // MARK: Structural
    var separator: Color { Color(UIColor.separator) }
    /// Gap ring between avatar and story ring — must match page background exactly
    var storyGap: Color { Color(UIColor.igPageBackground) }

    // MARK: Bottom bar glass pill (iOS 16-25 fallback)
    var glassTint:   Color { isDark ? Color.clear : Color.white.opacity(0.62) }
    var glassStroke: Color { isDark ? Color.white.opacity(0.15) : Color.white.opacity(0.90) }
    var glassEffect: AnyShapeStyle {
        isDark
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(.ultraThinMaterial)
    }

    // MARK: Tab bar
    /// Pill highlight behind the active tab icon
    var tabActiveIndicator: Color { Color(UIColor.label).opacity(0.11) }

    // MARK: Notes bubble
    /// Elevated surface visible against pure black — #1C1C1E dark · white light
    var notesBubble: Color { isDark ? Color(hex: "1C1C1E")              : Color.white }
}
