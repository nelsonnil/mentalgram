import SwiftUI

/// Instagram Explore skeleton loading UI
/// Shows gray animated placeholders in grid format (4:5 aspect ratio)
struct ExploreGridSkeleton: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // 10 rows of 3 = 30 skeleton items
                ForEach(0..<10, id: \.self) { rowIndex in
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { colIndex in
                            SkeletonGridItem()
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct SkeletonGridItem: View {
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.25),
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.25)
                    ]),
                    startPoint: isAnimating ? .topLeading : .bottomTrailing,
                    endPoint: isAnimating ? .bottomTrailing : .topLeading
                )
            )
            .aspectRatio(4/5, contentMode: .fill)
            .clipped()
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating.toggle()
                }
            }
    }
}
