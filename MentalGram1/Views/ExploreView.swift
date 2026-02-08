import SwiftUI

// MARK: - Explore View (Instagram Explore Replica)

struct ExploreView: View {
    @ObservedObject var exploreManager = ExploreManager.shared
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Search bar at top
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        Text("Buscar")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(10)
                    
                    Button(action: {}) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundColor(.primary)
                            .font(.system(size: 20))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                
                // Grid of explore content
                if exploreManager.isLoading && exploreManager.exploreMedia.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Cargando explore...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if exploreManager.exploreMedia.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No hay contenido")
                            .font(.headline)
                        
                        Button("Cargar Explore") {
                            exploreManager.loadExplore()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        ExploreGridView(
                            mediaItems: exploreManager.exploreMedia,
                            cachedImages: exploreManager.cachedImages
                        )
                        .padding(.bottom, 65)
                    }
                }
            }
            
            // Instagram bottom bar
            InstagramBottomBar(
                profileImageURL: nil,
                cachedImage: nil,
                isHome: false,
                isSearch: true,
                onHomePress: {
                    showingExplore = false
                    selectedTab = 1 // Sets
                },
                onSearchPress: {
                    // Already on search
                },
                onReelsPress: {
                    // Reels (disabled)
                },
                onMessagesPress: {
                    // Messages (disabled)
                },
                onProfilePress: {
                    showingExplore = false
                    selectedTab = 0 // Performance
                }
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
    }
}

// MARK: - Explore Grid View

struct ExploreGridView: View {
    let mediaItems: [InstagramMediaItem]
    let cachedImages: [String: UIImage]
    
    var body: some View {
        LazyVStack(spacing: 2) {
            // Create rows of 3 items
            ForEach(0..<((mediaItems.count + 2) / 3), id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { colIndex in
                        let index = rowIndex * 3 + colIndex
                        if index < mediaItems.count {
                            ExploreMediaCell(
                                media: mediaItems[index],
                                cachedImage: cachedImages[mediaItems[index].imageURL]
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Explore Media Cell

struct ExploreMediaCell: View {
    let media: InstagramMediaItem
    let cachedImage: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width / 3 - 1.33, height: UIScreen.main.bounds.width / 3 - 1.33)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: UIScreen.main.bounds.width / 3 - 1.33, height: UIScreen.main.bounds.width / 3 - 1.33)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Video indicator (play icon)
            if media.mediaType == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .padding(6)
            }
            
            // Carousel indicator (multiple icon)
            if media.mediaType == .carousel {
                Image(systemName: "square.on.square")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .padding(6)
            }
        }
    }
}
