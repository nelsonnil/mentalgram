import SwiftUI

/// Lets the magician search any Instagram profile, browse their reels,
/// and select one to be "forced" at a specific position in the Explore grid.
struct ForceReelPickerView: View {
    let slotIndex: Int

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ForceReelSettings.shared
    @ObservedObject private var instagram = InstagramService.shared

    @State private var usernameInput: String = ""
    @State private var reels: [InstagramMediaItem] = []
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchedUsername: String = ""
    @State private var lastSearchTime: Date = .distantPast
    @State private var showingRelogin = false

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

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
                    .disabled(isLoading || usernameInput.trimmingCharacters(in: .whitespaces).isEmpty || instagram.isLocked)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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
                            Text(String(format: String(localized: "force_reel.picker.header"), searchedUsername, reels.count))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
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
                                }
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

    // MARK: - Search

    private func searchReels() {
        let username = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !username.isEmpty else { return }

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
        searchedUsername = username

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
                print("🎭 [FORCE] Found @\(username) → userId: \(userId)")

                // ANTI-BOT: Random pause between search and reel fetch (1.0–2.5 s)
                let pause = UInt64.random(in: 1_000_000_000...2_500_000_000)
                try await Task.sleep(nanoseconds: pause)

                // Fetch reels — keep amount at 18 (same as rest of app)
                let fetchedReels = try await instagram.getUserReels(userId: userId, amount: 18)
                await MainActor.run {
                    reels = fetchedReels
                    isLoading = false
                    print("🎭 [FORCE] Loaded \(fetchedReels.count) reels for @\(username)")
                }

                // Download thumbnails (CDN, not Instagram API — low risk, no delay needed)
                for reel in fetchedReels {
                    if let img = await downloadImage(from: reel.imageURL) {
                        await MainActor.run { cachedImages[reel.imageURL] = img }
                    }
                }
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
}

// MARK: - Single reel cell in picker

private struct ReelPickerCell: View {
    let reel: InstagramMediaItem
    let image: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        }
        .buttonStyle(.plain)
    }
}
