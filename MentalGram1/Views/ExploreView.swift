import SwiftUI

// MARK: - Explore View (Instagram Explore Replica)

struct ExploreView: View {
    @ObservedObject var exploreManager = ExploreManager.shared
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var secretInputSettings = SecretInputSettings.shared
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var showingUserProfile = false
    @State private var searchedProfile: InstagramProfile?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    
    // Secret Input Masking
    @State private var secretInputBuffer: String = ""  // Real typed letters (what the magician types)
    @State private var maskTextCache: String = ""  // Cached mask text from settings
    
    var body: some View {
        ZStack {
            // Main Explore view
            ZStack(alignment: .bottom) {
                // White background covering everything
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                // Search bar at top
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField("Buscar", text: $searchText)
                            .font(.system(size: 16))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isSearchFieldFocused)
                            .onChange(of: searchText) { newValue in
                                handleSearchTextChange(oldValue: searchText, newValue: newValue)
                            }
                            .onAppear {
                                updateMaskTextCache()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                secretInputBuffer = ""
                                searchResults = []
                                isSearchFieldFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(10)
                    
                    if isSearchFieldFocused || !searchText.isEmpty {
                        Button("Cancelar") {
                            searchText = ""
                            secretInputBuffer = ""
                            searchResults = []
                            isSearchFieldFocused = false
                        }
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    } else {
                        Button(action: {}) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .foregroundColor(.primary)
                                .font(.system(size: 20))
                        }
                    }
                }
                .responsiveHorizontalPadding()
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                
                // Show search results if searching
                if !searchText.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSearching {
                                HStack {
                                    ProgressView()
                                    Text("Buscando...")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            } else if searchResults.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text("No se encontraron resultados")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(searchResults) { result in
                                    SearchResultRow(result: result, onTap: {
                                        loadUserProfile(userId: result.userId)
                                    })
                                }
                            }
                        }
                    }
                    .background(Color.white)
                } else {
                    // Grid of explore content
                    if exploreManager.isLoading || exploreManager.exploreMedia.isEmpty {
                        // Show skeleton UI (like Instagram real)
                        ExploreGridSkeleton()
                            .padding(.bottom, 65)
                    } else {
                        ScrollView {
                            ExploreGridView(
                                mediaItems: exploreManager.exploreMedia,
                                cachedImages: exploreManager.cachedImages,
                                exploreManager: exploreManager
                            )
                            .padding(.bottom, 65)
                        }
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
                    selectedTab = 0 // Performance (perfil del usuario)
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
            .overlay(
                Group {
                    if isSearching {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                            
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                
                                Text("Buscando @\(searchText)...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                            .padding(32)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(16)
                        }
                    }
                }
            )
            
            // User Profile overlay (full screen on top)
            if showingUserProfile, let profile = searchedProfile {
                UserProfileView(profile: profile, onClose: {
                    withAnimation {
                        showingUserProfile = false
                    }
                })
                .transition(.move(edge: .trailing))
                .zIndex(1000)
            }
        }
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        .preferredColorScheme(.light) // CRITICAL: Explore must look exactly like Instagram (light mode)
        .onAppear {
            // Auto-load Explore feed on appear (like Instagram real)
            // If cache has old count (not multiple of 3), clear and reload
            let currentCount = exploreManager.exploreMedia.count
            if currentCount > 0 && currentCount % 3 != 0 {
                print("🗑️ [EXPLORE] Cache has \(currentCount) items (not multiple of 3), clearing...")
                exploreManager.clearCache()
            }
            
            if exploreManager.exploreMedia.isEmpty {
                exploreManager.loadExplore()
            }
        }
    }
    
    private func performSearch(query: String) {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        // ANTI-BOT: Minimum 3 characters before searching (like Instagram real)
        guard query.count >= 3 else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // ANTI-BOT: Debounce 1 second (Instagram real waits ~1s after you stop typing)
        // 300ms was too aggressive - generated 6+ API calls per search
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            guard !Task.isCancelled else { return }
            
            do {
                let results = try await InstagramService.shared.searchUsers(query: query)
                
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = results
                    isSearching = false
                }
            } catch {
                // Search errors should NEVER show popup (like Instagram real)
                guard !Task.isCancelled else { return }
                print("🔍 [SEARCH] Error (silent): \(error)")
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }
    
    private func loadUserProfile(userId: String) {
        isSearchFieldFocused = false
        
        print("🔍 [UI] Loading profile for user ID: \(userId)")
        
        Task {
            do {
                let profile = try await InstagramService.shared.getProfileInfo(userId: userId)
                
                await MainActor.run {
                    if let profile = profile {
                        print("✅ [UI] Profile loaded successfully: @\(profile.username)")
                        print("✅ [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
                        searchedProfile = profile
                        showingUserProfile = true
                        print("✅ [UI] showingUserProfile set to true")
                    } else {
                        print("❌ [UI] Profile is nil")
                    }
                }
            } catch let error as InstagramError {
                print("❌ [PROFILE] Instagram error loading profile: \(error)")
                await MainActor.run {
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ [PROFILE] Error loading profile: \(error)")
                await MainActor.run {
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }
    
    // MARK: - Secret Input Logic
    
    private func updateMaskTextCache() {
        // Get latest follower username if mode is latestFollower
        // We need to fetch it asynchronously if not cached
        if secretInputSettings.mode == .latestFollower {
            Task {
                do {
                    let follower = try await instagram.getLatestFollower()
                    await MainActor.run {
                        let username = follower?.username
                        maskTextCache = secretInputSettings.getMaskText(latestFollowerUsername: username)
                    }
                } catch {
                    // Fallback to generic "user" if fetch fails
                    await MainActor.run {
                        maskTextCache = secretInputSettings.getMaskText(latestFollowerUsername: nil)
                    }
                }
            }
        } else {
            // Custom mode - no need for async
            maskTextCache = secretInputSettings.getMaskText(latestFollowerUsername: nil)
        }
    }
    
    /// Handle text change in search field with secret input masking
    private func handleSearchTextChange(oldValue: String, newValue: String) {
        // Update mask cache on each change (in case settings changed)
        updateMaskTextCache()
        
        // Detect user's actual input
        if newValue.count > oldValue.count {
            // User typed character(s)
            let typedCharacters = String(newValue.dropFirst(oldValue.count))
            
            for char in typedCharacters {
                if char == " " {
                    // SPACE pressed → trigger auto-reveal
                    handleSpacePressed()
                    return
                } else {
                    // Regular character typed
                    secretInputBuffer.append(char)
                    
                    // Update visible text with mask
                    searchText = buildMaskedText()
                }
            }
        } else if newValue.count < oldValue.count {
            // User deleted character(s) → delete from secret buffer too
            let deletedCount = oldValue.count - newValue.count
            secretInputBuffer = String(secretInputBuffer.dropLast(deletedCount))
            
            // Update visible text with mask
            searchText = buildMaskedText()
        }
        
        // Continue with normal search (for regular search functionality)
        performSearch(query: newValue)
    }
    
    /// Build the masked text that the spectator sees
    private func buildMaskedText() -> String {
        guard !secretInputBuffer.isEmpty, !maskTextCache.isEmpty else {
            return secretInputBuffer
        }
        
        var result = ""
        for i in 0..<secretInputBuffer.count {
            let maskIndex = i % maskTextCache.count
            let char = maskTextCache[maskTextCache.index(maskTextCache.startIndex, offsetBy: maskIndex)]
            result.append(char)
        }
        return result
    }
    
    /// Handle SPACE key → Auto-reveal word from active Word Reveal set
    private func handleSpacePressed() {
        print("🎩 [SECRET] Space pressed - secret word: '\(secretInputBuffer)'")
        LogManager.shared.info("Secret input triggered: '\(secretInputBuffer)'", category: .general)
        
        // Clear the search text and buffer
        searchText = ""
        let wordToReveal = secretInputBuffer
        secretInputBuffer = ""
        
        // Find active Word Reveal set with completed photos
        guard let activeSet = findActiveWordRevealSet() else {
            print("⚠️ [SECRET] No active Word Reveal set found")
            return
        }
        
        print("🎩 [SECRET] Using set: \(activeSet.name), banks: \(activeSet.banks.count)")
        
        // Validate we have enough banks for the word length
        guard activeSet.banks.count >= wordToReveal.count else {
            print("⚠️ [SECRET] Not enough banks (\(activeSet.banks.count)) for word length (\(wordToReveal.count))")
            return
        }
        
        // Auto-reveal each letter from corresponding bank
        Task {
            await revealWord(wordToReveal, fromSet: activeSet)
        }
    }
    
    /// Find the first completed Word Reveal set
    private func findActiveWordRevealSet() -> PhotoSet? {
        return dataManager.sets.first { set in
            set.type == .word &&
            set.status == .completed &&
            !set.banks.isEmpty &&
            set.photos.allSatisfy { $0.uploadStatus == .completed && $0.mediaId != nil }
        }
    }
    
    /// Reveal word by unarchiving letters one by one (1s delay between each)
    private func revealWord(_ word: String, fromSet set: PhotoSet) async {
        let letters = Array(word.lowercased())
        let alphabet = set.selectedAlphabet ?? .latin
        
        print("🎩 [SECRET] Revealing '\(word)' using alphabet: \(alphabet.displayName)")
        
        for (index, letter) in letters.enumerated() {
            // Find the letter character in the alphabet
            guard let charIndex = alphabet.indexFor(String(letter)) else {
                print("⚠️ [SECRET] Letter '\(letter)' not found in alphabet")
                continue
            }
            
            let symbol = alphabet.characters[charIndex]
            
            // Get the photo from the corresponding bank
            guard index < set.banks.count else {
                print("⚠️ [SECRET] Bank index \(index) out of range")
                break
            }
            
            let bank = set.banks[index]
            
            // Find photo with this symbol in this bank
            guard let photo = set.photos.first(where: { $0.bankId == bank.id && $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }) else {
                print("⚠️ [SECRET] Photo not found for symbol '\(symbol)' in bank \(bank.name)")
                continue
            }
            
            print("🎩 [SECRET] Revealing letter '\(letter)' (symbol: \(symbol)) from \(bank.name)")
            
            // Reveal (unarchive) the photo
            do {
                guard let mediaId = photo.mediaId else { continue }
                
                let result = try await instagram.reveal(mediaId: mediaId)
                
                if result.success {
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: nil,
                            isArchived: false,
                            commentId: result.commentId
                        )
                    }
                    print("✅ [SECRET] Letter '\(letter)' revealed successfully")
                } else {
                    print("❌ [SECRET] Failed to reveal letter '\(letter)'")
                }
                
                // ANTI-BOT: 1 second delay between reveals
                if index < letters.count - 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ [SECRET] Error revealing letter '\(letter)': \(error)")
                // Continue with next letter even if one fails
            }
        }
        
        print("✅ [SECRET] Word reveal complete")
    }
}


// MARK: - Explore Grid View

struct ExploreGridView: View {
    let mediaItems: [InstagramMediaItem]
    let cachedImages: [String: UIImage]
    @ObservedObject var exploreManager = ExploreManager.shared
    
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
                            .onAppear {
                                // Trigger load more when this item appears
                                exploreManager.loadMoreIfNeeded(currentItem: mediaItems[index])
                            }
                        } else {
                            // Invisible placeholder to keep grid aligned
                            Color.clear
                                .aspectRatio(4/5, contentMode: .fit)
                        }
                    }
                }
            }
            
            // Loading indicator at bottom when loading more
            if exploreManager.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: UserSearchResult
    let onTap: () -> Void
    @State private var profileImage: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile picture
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(result.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if result.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if !result.fullName.isEmpty {
                        Text(result.fullName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .responsiveHorizontalPadding()
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard !result.profilePicURL.isEmpty,
              let url = URL(string: result.profilePicURL) else { return }
        
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
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
        // Fixed 4:5 container - all content fills this uniformly
        Color.clear
            .aspectRatio(4/5, contentMode: .fit)
            .overlay(
                ZStack(alignment: .topTrailing) {
                    // Content fills the entire 4:5 cell
                    if media.mediaType == .video, let videoURL = media.videoURL {
                        GridVideoPlayer(videoURL: videoURL)
                    } else if let image = cachedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                    
                    // Carousel indicator
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
            )
            .clipped()
    }
}
