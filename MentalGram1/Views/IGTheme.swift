import SwiftUI

/// Semantic color palette for the fake Instagram UI.
/// Uses UIKit adaptive colors where possible so they react to system
/// light / dark mode automatically, without needing an explicit @Environment
/// read in every sub-view. Custom overrides (button fill, glass pill) are
/// expressed as Color literals or via the colorScheme-aware helpers below.
struct IGTheme {
    let scheme: ColorScheme
    var isDark: Bool { scheme == .dark }

    // MARK: Backgrounds
    /// Main page background: #FFFFFF light · #000000 dark (pure Instagram black)
    var background:          Color { Color(UIColor.systemBackground) }
    /// Card / sheet background: #F2F2F7 light · #1C1C1E dark
    var secondaryBackground: Color { Color(UIColor.secondarySystemBackground) }

    // MARK: Text
    var primaryText:   Color { Color(UIColor.label) }
    var secondaryText: Color { Color(UIColor.secondaryLabel) }
    var tertiaryText:  Color { Color(UIColor.tertiaryLabel) }

    // MARK: Interactive
    /// Edit profile / Share profile button fill
    var buttonFill: Color { Color(UIColor.systemGray6) }
    /// External URL in bio
    var externalLink: Color { Color(UIColor.link) }

    // MARK: Structural
    var separator: Color { Color(UIColor.separator) }
    /// The gap ring between avatar and story/reveal ring — must match page background
    var storyGap: Color { Color(UIColor.systemBackground) }

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
    /// White in light mode, dark card in dark mode — visible against black page bg
    var notesBubble: Color { Color(UIColor.secondarySystemBackground) }
}
