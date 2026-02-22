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
    @State private var isUpdatingMask: Bool = false  // Flag to ignore programmatic searchText changes
    
    // Reveal task (runs silently in background)
    @State private var revealTask: Task<Void, Never>?
    // Debounce duplicate space triggers (keyboard can fire onChange multiple times)
    @State private var lastSpaceTriggerTime: Date = .distantPast
    
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
                                guard !isUpdatingMask else { return }
                                handleSearchTextChange(newValue: newValue)
                            }
                            .onAppear {
                                updateMaskTextCache()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                isUpdatingMask = true
                                searchText = ""
                                secretInputBuffer = ""
                                isUpdatingMask = false
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
                            isUpdatingMask = true
                            searchText = ""
                            secretInputBuffer = ""
                            isUpdatingMask = false
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
                                mediaItems: exploreManager.exploreMediaWithForce(),
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
            
            // Reveal runs silently in background — no visual indicator (spectator must not see anything)
            // Magician gets haptic feedback: medium pulse on space, success/error on completion
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
    /// Uses secretInputBuffer.count as the "expected" length to detect typed vs deleted chars
    private func handleSearchTextChange(newValue: String) {
        // Update mask cache on each change (in case settings changed)
        updateMaskTextCache()
        
        let expectedLength = secretInputBuffer.count
        
        if newValue.count > expectedLength {
            // User typed new character(s) — extract only the newly typed ones
            let newChars = String(newValue.suffix(newValue.count - expectedLength))
            
            var hasSpace = false
            for char in newChars {
                if char == " " {
                    // SPACE pressed → trigger auto-reveal (but DON'T clear the text)
                    hasSpace = true
                } else {
                    secretInputBuffer.append(char)
                }
            }
            
            // Replace visible text with mask characters (strip the space)
            let masked = buildMaskedText()
            isUpdatingMask = true
            searchText = masked
            isUpdatingMask = false
            
            // Trigger reveal AFTER updating the text (space = "transmit" the word)
            if hasSpace {
                handleSpacePressed()
            }
            
        } else if newValue.count < expectedLength {
            // User deleted character(s)
            let deletedCount = expectedLength - newValue.count
            secretInputBuffer = String(secretInputBuffer.dropLast(deletedCount))
            
            // Replace visible text with mask characters
            let masked = buildMaskedText()
            isUpdatingMask = true
            searchText = masked
            isUpdatingMask = false
        }
        // If newValue.count == expectedLength, it's either our own mask update or no real change — ignore
        
        // Trigger search with the masked text (what the spectator sees)
        performSearch(query: searchText)
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
    
    /// Handle SPACE key → Transmit the secret word (trigger reveal in background)
    /// The search field keeps showing the mask text so the magician can tap into the profile
    private func handleSpacePressed() {
        // Debounce: keyboard/onChange can fire this twice in the same millisecond.
        // Require at least 1.5 s between consecutive space triggers.
        let now = Date()
        guard now.timeIntervalSince(lastSpaceTriggerTime) > 1.5 else {
            print("⚠️ [SECRET] Space debounced (called \(String(format: "%.2f", now.timeIntervalSince(lastSpaceTriggerTime)))s after previous)")
            return
        }
        lastSpaceTriggerTime = now

        let word = secretInputBuffer
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] SPACE PRESSED - transmitting secret word: '\(word)' (\(word.count) letters)")
        print("🎩 [SECRET] Search field keeps showing: '\(searchText)' (mask text stays)")
        LogManager.shared.info("Secret input SPACE triggered: '\(word)'", category: .general)
        
        guard !word.isEmpty else {
            print("⚠️ [SECRET] Empty word, ignoring space")
            return
        }
        
        // NOTE: Do NOT clear searchText or secretInputBuffer!
        // The masked text stays visible so the magician can tap to enter the follower's profile.
        // The spectator sees a normal username search.
        
        // Haptic feedback to confirm transmission (subtle, only magician feels it)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Diagnostics: show all sets and their state
        print("🎩 [SECRET] Total sets in DataManager: \(dataManager.sets.count)")
        for (i, set) in dataManager.sets.enumerated() {
            let archivedWithMedia = set.photos.filter { $0.mediaId != nil && $0.isArchived }.count
            let withMedia = set.photos.filter { $0.mediaId != nil }.count
            let archived = set.photos.filter { $0.isArchived }.count
            print("🎩 [SECRET]   Set[\(i)]: '\(set.name)' type=\(set.type.rawValue) status=\(set.status.rawValue) banks=\(set.banks.count) photos=\(set.photos.count) withMediaId=\(withMedia) archived=\(archived) archivedWithMedia=\(archivedWithMedia)")
        }
        
        // Find active Word Reveal set with completed photos
        guard let activeSet = findActiveWordRevealSet() else {
            print("❌ [SECRET] NO ACTIVE WORD REVEAL SET FOUND!")
            print("❌ [SECRET] Requirements: type=word, status=completed, banks>0, has photos with mediaId+isArchived")
            LogManager.shared.error("No active Word Reveal set found for '\(word)'", category: .general)
            
            // Haptic error feedback for magician (no visual, spectator won't notice)
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)
            return
        }
        
        print("🎩 [SECRET] Using set: '\(activeSet.name)', banks: \(activeSet.banks.count)")
        
        // Validate we have enough banks for the word length
        guard activeSet.banks.count >= word.count else {
            print("⚠️ [SECRET] Not enough banks (\(activeSet.banks.count)) for word '\(word)' (\(word.count) letters)")
            LogManager.shared.error("Not enough banks (\(activeSet.banks.count)) for word '\(word)' (\(word.count) letters)", category: .general)
            return
        }
        
        // Cancel any previous reveal task
        revealTask?.cancel()
        
        // Auto-reveal each letter in background (completely silent, no UI changes)
        revealTask = Task {
            await revealWord(word, fromSet: activeSet)
        }
    }
    
    /// Find the first completed Word Reveal set that has archived photos ready to reveal
    private func findActiveWordRevealSet() -> PhotoSet? {
        // Try strict match first: completed word set with archived photos
        if let strict = dataManager.sets.first(where: { set in
            set.type == .word &&
            set.status == .completed &&
            !set.banks.isEmpty &&
            set.photos.contains(where: { $0.mediaId != nil && $0.isArchived })
        }) {
            return strict
        }
        
        // Fallback: any word set with archived photos (even if status is not .completed)
        if let fallback = dataManager.sets.first(where: { set in
            set.type == .word &&
            !set.banks.isEmpty &&
            set.photos.contains(where: { $0.mediaId != nil && $0.isArchived })
        }) {
            print("⚠️ [SECRET] Using fallback set (status: \(fallback.status.rawValue), not 'completed')")
            return fallback
        }
        
        return nil
    }
    
    /// Reveal word by unarchiving letters one by one (1s delay between each)
    private func revealWord(_ word: String, fromSet set: PhotoSet) async {
        let letters = Array(word.lowercased())
        let alphabet = set.selectedAlphabet ?? .latin
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] REVEALING '\(word)' (\(letters.count) letters)")
        print("🎩 [SECRET] Set: '\(set.name)', Alphabet: \(alphabet.displayName)")
        print("🎩 [SECRET] Banks (sorted): \(sortedBanks.map { "pos\($0.position)=\($0.name)" })")
        
        var successCount = 0
        var failCount = 0
        
        for (index, letter) in letters.enumerated() {
            // Check if task was cancelled
            if Task.isCancelled {
                print("⚠️ [SECRET] Reveal task cancelled at letter \(index)")
                break
            }
            
            // Find the letter character in the alphabet
            guard let charIndex = alphabet.indexFor(String(letter)) else {
                print("❌ [SECRET] Letter '\(letter)' NOT FOUND in alphabet \(alphabet.displayName)")
                failCount += 1
                continue
            }
            
            let symbol = alphabet.characters[charIndex]
            
            // Get the bank by position (1-based), not array index
            let bankPosition = index + 1
            guard let bank = sortedBanks.first(where: { $0.position == bankPosition }) ?? (index < sortedBanks.count ? sortedBanks[index] : nil) else {
                print("❌ [SECRET] No bank for position \(bankPosition)")
                failCount += 1
                break
            }
            
            // Find photo with this symbol in this bank
            let photosInBank = set.photos.filter { $0.bankId == bank.id }

            // Check if the photo was already unarchived in a previous reveal (count as success, no API call needed)
            if let alreadyRevealed = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
                print("ℹ️ [SECRET] [\(index + 1)/\(letters.count)] '\(letter)' already unarchived locally (mediaId: \(alreadyRevealed.mediaId ?? "?")) — skipping API call")
                successCount += 1
                continue
            }

            guard let photo = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }) else {
                print("❌ [SECRET] Photo NOT FOUND for symbol '\(symbol)' in bank '\(bank.name)' (pos \(bank.position))")
                print("❌ [SECRET] Bank has \(photosInBank.count) photos:")
                for p in photosInBank.prefix(5) {
                    print("   - symbol='\(p.symbol)' mediaId=\(p.mediaId ?? "nil") archived=\(p.isArchived) status=\(p.uploadStatus.rawValue)")
                }
                failCount += 1
                continue
            }
            
            guard let mediaId = photo.mediaId else {
                print("❌ [SECRET] Photo has nil mediaId (should not happen)")
                failCount += 1
                continue
            }
            
            print("🎩 [SECRET] [\(index + 1)/\(letters.count)] Revealing '\(letter)' → symbol '\(symbol)' from bank '\(bank.name)' mediaId=\(mediaId)")
            
            // Reveal (unarchive) the photo
            do {
                let result = try await instagram.reveal(mediaId: mediaId)
                
                if result.success {
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            isArchived: false,
                            commentId: result.commentId
                        )
                    }
                    successCount += 1
                    print("✅ [SECRET] [\(index + 1)/\(letters.count)] Letter '\(letter)' REVEALED OK")
                    LogManager.shared.success("Revealed '\(letter)' (mediaId: \(mediaId))", category: .general)
                } else {
                    failCount += 1
                    print("❌ [SECRET] [\(index + 1)/\(letters.count)] Reveal returned FALSE for '\(letter)'")
                    LogManager.shared.error("Reveal failed for '\(letter)' (mediaId: \(mediaId))", category: .general)
                }
                
                // ANTI-BOT: Random delay between reveals (800ms–2200ms) to avoid machine-like patterns
                if index < letters.count - 1 {
                    let betweenDelay = UInt64.random(in: 800_000_000...2_200_000_000)
                    try? await Task.sleep(nanoseconds: betweenDelay)
                }
            } catch {
                failCount += 1
                print("❌ [SECRET] [\(index + 1)/\(letters.count)] ERROR revealing '\(letter)': \(error)")
                LogManager.shared.error("Reveal error for '\(letter)': \(error)", category: .general)
            }
        }
        
        print("🎩 [SECRET] ═══════════════════════════════════════")
        print("🎩 [SECRET] REVEAL COMPLETE: \(successCount) ok, \(failCount) failed, total \(letters.count)")
        LogManager.shared.info("Word reveal '\(word)': \(successCount) ok, \(failCount) failed", category: .general)
        
        // Haptic feedback to magician when reveal finishes (spectator can't see anything)
        await MainActor.run {
            if failCount == 0 {
                // Success: double light tap
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    generator.impactOccurred()
                }
            } else {
                // Some failures: error vibration
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }
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
