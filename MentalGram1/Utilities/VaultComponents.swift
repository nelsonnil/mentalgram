import SwiftUI

// MARK: - Vault UI Components

// MARK: - Modern Card

struct VaultCard<Content: View>: View {
    let content: Content
    var glowColor: Color? = nil
    
    init(glowColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.glowColor = glowColor
    }
    
    var body: some View {
        content
            .padding(VaultTheme.Spacing.lg)
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
            .modifier(GlowModifier(color: glowColor))
    }
}

struct GlowModifier: ViewModifier {
    let color: Color?
    
    func body(content: Content) -> some View {
        if let color = color {
            content.shadow(color: color.opacity(0.3), radius: 20, x: 0, y: 0)
        } else {
            content
        }
    }
}

// MARK: - Gradient Button

struct GradientButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var isEnabled: Bool = true
    var style: ButtonStyleType = .primary
    
    enum ButtonStyleType {
        case primary
        case secondary
        case success
        case destructive
    }
    
    var gradient: LinearGradient {
        switch style {
        case .primary:
            return VaultTheme.Colors.gradientPrimary
        case .secondary:
            return LinearGradient(colors: [VaultTheme.Colors.secondary], startPoint: .leading, endPoint: .trailing)
        case .success:
            return VaultTheme.Colors.gradientSuccess
        case .destructive:
            return LinearGradient(colors: [VaultTheme.Colors.error], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(VaultTheme.Typography.bodyBold())
                }
                Text(title)
                    .font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(gradient)
            .cornerRadius(VaultTheme.CornerRadius.md)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Outline Button

struct OutlineButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var color: Color = VaultTheme.Colors.primary
    var isEnabled: Bool = true
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(VaultTheme.Typography.bodyBold())
                }
                Text(title)
                    .font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(Color.clear)
            .cornerRadius(VaultTheme.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                    .stroke(color, lineWidth: 2)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let style: BadgeStyle
    
    enum BadgeStyle {
        case success
        case warning
        case error
        case info
        case pending
        case active
        
        var color: Color {
            switch self {
            case .success: return VaultTheme.Colors.success
            case .warning: return VaultTheme.Colors.warning
            case .error: return VaultTheme.Colors.error
            case .info: return VaultTheme.Colors.info
            case .pending: return VaultTheme.Colors.textSecondary
            case .active: return VaultTheme.Colors.primary
            }
        }
        
        var icon: String? {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "clock.fill"
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            case .pending: return "clock"
            case .active: return "bolt.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = style.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text.uppercased())
                .font(VaultTheme.Typography.captionSmall())
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, VaultTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(style.color)
        .cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

// MARK: - Icon Badge (for type indicators)

struct IconBadge: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 48
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: size, height: size)
            .cornerRadius(VaultTheme.CornerRadius.md)
            
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Stat Card (for dashboard stats)

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = VaultTheme.Colors.primary
    
    var body: some View {
        VStack(spacing: VaultTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(VaultTheme.Typography.titleLarge())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            
            Text(title)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .stroke(VaultTheme.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double // 0.0 to 1.0
    var height: CGFloat = 8
    var gradient: LinearGradient = VaultTheme.Colors.gradientPrimary
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(VaultTheme.Colors.cardBorder)
                    .frame(height: height)
                
                // Foreground
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(gradient)
                    .frame(width: geometry.size.width * CGFloat(min(progress, 1.0)), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: VaultTheme.Spacing.xl) {
            // Icon with gradient
            ZStack {
                Circle()
                    .fill(VaultTheme.Colors.cardBackground)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(VaultTheme.Colors.cardBorder, lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(VaultTheme.Colors.gradientPrimary)
            }
            
            VStack(spacing: VaultTheme.Spacing.sm) {
                Text(title)
                    .font(VaultTheme.Typography.titleLarge())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                
                Text(message)
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let actionTitle = actionTitle, let action = action {
                GradientButton(
                    title: actionTitle,
                    icon: "plus.circle.fill",
                    action: action
                )
                .frame(maxWidth: 280)
            }
        }
        .padding(VaultTheme.Spacing.xxxl)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(VaultTheme.Typography.titleSmall())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            
            Spacer()
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.primary)
                }
            }
        }
        .padding(.horizontal, VaultTheme.Spacing.lg)
        .padding(.vertical, VaultTheme.Spacing.sm)
    }
}
