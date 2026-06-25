import SwiftUI

/// Lets the magician search any Instagram profile, browse their reels,
/// and select one to be "forced" at a specific position in the Explore grid.
struct ForceReelPickerView: View {
    let slotIndex: Int

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ForceReelSettings.shared
    @ObservedObject private var instagram = InstagramService.shared
    @ObservedObject private var uploadManager = UploadManager.shared

    @State private var usernameInput: String = ""
    @State private var reels: [InstagramMediaItem] = []
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMorePages = false
    @State private var nextMaxId: String? = nil
    @State private var errorMessage: String?
    @State private var searchedUsername: String = ""
    @State private var searchedUserId: String = ""
    @State private var lastSearchTime: Date = .distantPast
    @State private var lastPageLoadTime: Date = .distantPast
    @State private var showingRelogin = false

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    private let pageSize = 18
    private let minPageGap: TimeInterval = 3.5
    private var isUploadBusy: Bool {
        uploadManager.activeTask != nil || uploadManager.isUploading || uploadManager.isActive || uploadManager.isSyncArchiveActive
    }
    private let uploadBusyMessage = "Upload in progress. Wait until the upload pauses or finishes before loading Instagram reels."

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    TextField(String(localized: "force_reel.picker.placeholder"), text: $usernameInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(10)
                        .onSubmit { searchReels() }

                    Button(action: searchReels) {
                        if isLoading {
                            ProgressView()
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(isLoading || usernameInput.trimmingCharacters(in: .whitespaces).isEmpty || instagram.isLocked || isUploadBusy)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isUploadBusy {
                    uploadBusyBanner
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                Divider()

                if reels.isEmpty && !isLoading {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        if searchedUsername.isEmpty {
                            Text("force_reel.picker.empty_state")
                                .foregroundColor(.secondary)
                        } else {
                            Text(String(format: String(localized: "force_reel.picker.no_reels"), searchedUsername))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    Spacer()
                    ProgressView(String(localized: "force_reel.picker.loading"))
                    Spacer()
                } else {
                    // Reels grid
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: String(localized: "force_reel.picker.header"), searchedUsername, reels.count) + (hasMorePages ? "+" : ""))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if isLoadingMore {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                            LazyVGrid(columns: columns, spacing: 1) {
                                ForEach(reels) { reel in
                                    ReelPickerCell(
                                        reel: reel,
                                        image: cachedImages[reel.imageURL],
                                        isSelected: settings.slots.contains(where: { $0.mediaId == reel.mediaId }),
                                        onTap: { select(reel) }
                                    )
                                    .onAppear { loadMoreIfNeeded(currentReel: reel) }
                                }
                            }

                            if hasMorePages {
                                Button(action: loadMoreReels) {
                                    if isLoadingMore {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    } else {
                                        Text("Load more reels")
                                            .font(.system(size: 14, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    }
                                }
                                .disabled(isLoadingMore || isUploadBusy)
                                .buttonStyle(.bordered)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(format: String(localized: "force_reel.picker.nav_title"), slotIndex + 1))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "action.cancel")) { dismiss() }
                }
                if settings.slots.contains(where: { $0.id == slotIndex && $0.hasReel }) {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "force_reel.picker.clear"), role: .destructive) {
                            settings.clearSlot(slotIndex)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            // Direct re-login sheet (no disguise — this is a private settings area)
            .sheet(isPresented: $showingRelogin) {
                ReloginSheet(isPresented: $showingRelogin)
            }
        }
    }

    private var uploadBusyBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 1)
            Text(uploadBusyMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private func searchReels() {
        let username = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !username.isEmpty else { return }
        guard !isUploadBusy else {
            errorMessage = uploadBusyMessage
            return
        }

        // ANTI-BOT: Enforce minimum 8 s cooldown between searches
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSearchTime)
        if elapsed < 8 {
            let remaining = Int(8 - elapsed) + 1
            errorMessage = "Please wait \(remaining)s before searching again"
            return
        }

        // ANTI-BOT: Block if Instagram lockdown is active
        guard !instagram.isLocked else {
            errorMessage = "Service temporarily unavailable. Try again later."
            return
        }

        // Session expired — prompt re-login directly (no disguise in private settings)
        if instagram.isSessionExpired {
            showingRelogin = true
            return
        }

        lastSearchTime = now
        errorMessage = nil
        isLoading = true
        reels = []
        cachedImages = [:]
        nextMaxId = nil
        hasMorePages = false
        searchedUsername = username
        searchedUserId = ""

        Task {
            do {
                // ANTI-BOT: Wait for network stability before any API call
                try await instagram.waitForNetworkStability()

                // Resolve username → userId
                let results: [UserSearchResult]
                do {
                    results = try await instagram.searchUsers(query: username)
                } catch {
                    print("❌ [FORCE] searchUsers failed: \(error)")
                    await MainActor.run {
                        isLoading = false
                        if instagram.isSessionExpired {
                            showingRelogin = true
                        } else {
                            errorMessage = "Search failed: \(error.localizedDescription)"
                        }
                    }
                    return
                }

                guard let match = results.first(where: { $0.username.lowercased() == username })
                        ?? results.first else {
                    await MainActor.run {
                        errorMessage = "Profile '@\(username)' not found"
                        isLoading = false
                    }
                    return
                }

                let userId = match.userId
                await MainActor.run { searchedUserId = userId }
                print("🎭 [FORCE] Found @\(username) → userId: \(userId)")

                // ANTI-BOT: Random pause between search and reel fetch (1.0–2.5 s)
                let pause = UInt64.random(in: 1_000_000_000...2_500_000_000)
                try await Task.sleep(nanoseconds: pause)
                guard await MainActor.run(body: { !isUploadBusy }) else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = uploadBusyMessage
                    }
                    return
                }

                let (fetchedReels, nextId) = try await instagram.getUserReelsPage(userId: userId, amount: pageSize)
                let uniqueFetched = uniqueReels(fetchedReels)
                await MainActor.run {
                    reels = uniqueFetched
                    nextMaxId = nextId
                    hasMorePages = nextId != nil
                    lastPageLoadTime = Date()
                    isLoading = false
                    print("🎭 [FORCE] Loaded \(uniqueFetched.count) reels for @\(username)")
                }

                // Download thumbnails (CDN, not Instagram API — low risk, no delay needed)
                await downloadThumbnails(for: uniqueFetched)
            } catch {
                await MainActor.run {
                    isLoading = false
                    if instagram.isSessionExpired {
                        showingRelogin = true
                    } else {
                        errorMessage = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func loadMoreReels() {
        guard let maxId = nextMaxId, !searchedUserId.isEmpty else { return }
        guard !isLoadingMore else { return }
        guard !isUploadBusy else {
            errorMessage = uploadBusyMessage
            return
        }
        guard !instagram.isLocked else {
            errorMessage = "Service temporarily unavailable. Try again later."
            return
        }
        if instagram.isSessionExpired {
            showingRelogin = true
            return
        }
        let elapsed = Date().timeIntervalSince(lastPageLoadTime)
        let waitBeforeRequest = max(0, minPageGap - elapsed)
        isLoadingMore = true

        Task {
            do {
                if waitBeforeRequest > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitBeforeRequest * 1_000_000_000))
                }
                let pause = UInt64.random(in: 1_200_000_000...2_400_000_000)
                try await Task.sleep(nanoseconds: pause)
                guard await MainActor.run(body: { !isUploadBusy }) else {
                    await MainActor.run {
                        isLoadingMore = false
                        errorMessage = uploadBusyMessage
                    }
                    return
                }
                await MainActor.run { lastPageLoadTime = Date() }

                let (fetched, nextId) = try await instagram.getUserReelsPage(userId: searchedUserId, amount: pageSize, maxId: maxId)
                let existingKeys = await MainActor.run {
                    Set(reels.map { $0.mediaId.isEmpty ? $0.imageURL : $0.mediaId })
                }
                let fresh = uniqueReels(fetched.filter {
                    !existingKeys.contains($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId)
                })

                await MainActor.run {
                    reels.append(contentsOf: fresh)
                    nextMaxId = nextId
                    hasMorePages = nextId != nil && nextId != maxId
                    isLoadingMore = false
                }
                await downloadThumbnails(for: fresh)
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                    if instagram.isSessionExpired {
                        showingRelogin = true
                    }
                }
                print("⚠️ [FORCE REEL] Pagination error: \(error)")
            }
        }
    }

    private func loadMoreIfNeeded(currentReel: InstagramMediaItem) {
        guard hasMorePages, !isLoadingMore else { return }
        let currentKey = currentReel.mediaId.isEmpty ? currentReel.imageURL : currentReel.mediaId
        guard let index = reels.firstIndex(where: {
            ($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId) == currentKey
        }) else { return }
        let threshold = max(1, Int(Double(reels.count) * 0.82))
        if index >= threshold {
            loadMoreReels()
        }
    }

    private func select(_ reel: InstagramMediaItem) {
        settings.selectReel(
            slotIndex: slotIndex,
            thumbnailURL: reel.imageURL,
            videoURL: reel.videoURL ?? "",
            mediaId: reel.mediaId,
            username: searchedUsername,
            likeCount: reel.likeCount,
            commentCount: reel.commentCount,
            caption: reel.caption
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }

    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func downloadThumbnails(for items: [InstagramMediaItem]) async {
        for item in items {
            guard cachedImages[item.imageURL] == nil else { continue }
            if let img = await downloadImage(from: item.imageURL) {
                await MainActor.run { cachedImages[item.imageURL] = img }
            }
        }
    }

    private func uniqueReels(_ items: [InstagramMediaItem]) -> [InstagramMediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.mediaId.isEmpty ? item.imageURL : item.mediaId
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Single reel cell in picker

private struct ReelPickerCell: View {
    let reel: InstagramMediaItem
    let image: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(4/5, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .aspectRatio(4/5, contentMode: .fill)
                    .overlay(ProgressView())
            }

            // Play icon
            Image(systemName: "play.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .shadow(radius: 2)
                .padding(6)

            // Selection overlay
            if isSelected {
                Color.blue.opacity(0.35)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
