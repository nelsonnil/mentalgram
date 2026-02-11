import SwiftUI

/// Instagram-style skeleton loading UI
/// Layout MUST match InstagramProfileView exactly (pic LEFT, stats RIGHT)
struct InstagramProfileSkeleton: View {
    var onPlusPress: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Header Bar (matches InstagramHeaderView)
                HStack {
                    // Plus button (back to Sets)
                    if let onPlusPress = onPlusPress {
                        Button(action: onPlusPress) {
                            Image(systemName: "plus.app")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                    } else {
                        SkeletonBox(width: 24, height: 24)
                    }
                    
                    Spacer()
                    
                    // Username placeholder
                    HStack(spacing: 4) {
                        SkeletonBox(width: 100, height: 16)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.3))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        SkeletonBox(width: 22, height: 22)
                        SkeletonBox(width: 22, height: 22)
                    }
                }
                .responsiveHorizontalPadding()
                .frame(height: 44)
                
                // MARK: - Profile Info Section
                VStack(spacing: 16) {
                    // Profile Picture (LEFT) + Stats (RIGHT) - SAME ROW
                    HStack(alignment: .center, spacing: 0) {
                        // Profile Picture on LEFT
                        SkeletonCircle(size: 86)
                            .padding(.leading, UIScreen.main.bounds.width * 0.04)
                        
                        Spacer(minLength: 8)
                        
                        // Stats on RIGHT (Posts, Followers, Following)
                        HStack(spacing: 0) {
                            SkeletonStatView()
                            SkeletonStatView()
                            SkeletonStatView()
                        }
                        .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                    }
                    
                    // Name + Bio placeholders
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBox(width: 120, height: 14)
                        SkeletonBox(width: UIScreen.main.bounds.width - 48, height: 14)
                        SkeletonBox(width: UIScreen.main.bounds.width - 100, height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
                    // Followed by placeholder
                    HStack(spacing: 4) {
                        HStack(spacing: -8) {
                            SkeletonCircle(size: 20)
                            SkeletonCircle(size: 20)
                            SkeletonCircle(size: 20)
                        }
                        SkeletonBox(width: 180, height: 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
                    // Edit Profile + Share Profile buttons
                    HStack(spacing: 8) {
                        SkeletonBox(width: 0, height: 32)
                            .frame(maxWidth: .infinity)
                            .cornerRadius(8)
                        SkeletonBox(width: 0, height: 32)
                            .frame(maxWidth: .infinity)
                            .cornerRadius(8)
                        SkeletonBox(width: 32, height: 32)
                            .cornerRadius(8)
                    }
                    .responsiveHorizontalPadding()
                    
                    // Story Highlights
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<5, id: \.self) { _ in
                                VStack(spacing: 4) {
                                    SkeletonCircle(size: 64)
                                    SkeletonBox(width: 40, height: 10)
                                }
                            }
                        }
                        .responsiveHorizontalPadding()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.vertical, 12)
                
                // MARK: - Tab Bar
                HStack(spacing: 0) {
                    ForEach(["square.grid.3x3", "play.rectangle", "person.crop.square"], id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundColor(icon == "square.grid.3x3" ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(
                                Rectangle()
                                    .fill(icon == "square.grid.3x3" ? Color.primary : Color.clear)
                                    .frame(height: 1),
                                alignment: .bottom
                            )
                    }
                }
                .frame(height: 44)
                
                Divider()
                
                // MARK: - Photos Grid (4:5 aspect ratio)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1)
                    ],
                    spacing: 1
                ) {
                    ForEach(0..<12, id: \.self) { _ in
                        SkeletonBox(width: 0, height: 0)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4/5, contentMode: .fill)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Skeleton Stat View (matches StatView layout)

struct SkeletonStatView: View {
    var body: some View {
        VStack(spacing: 2) {
            SkeletonBox(width: 35, height: 16)
            SkeletonBox(width: 55, height: 13)
        }
        .frame(width: 100)
    }
}

// MARK: - Skeleton Components

struct SkeletonBox: View {
    let width: CGFloat
    let height: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(isAnimating ? 0.15 : 0.25),
                        Color.gray.opacity(isAnimating ? 0.25 : 0.15)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width > 0 ? width : nil, height: height > 0 ? height : nil)
            .cornerRadius(4)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonCircle: View {
    let size: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(isAnimating ? 0.15 : 0.25),
                        Color.gray.opacity(isAnimating ? 0.25 : 0.15)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview

struct InstagramProfileSkeleton_Previews: PreviewProvider {
    static var previews: some View {
        InstagramProfileSkeleton()
    }
}
