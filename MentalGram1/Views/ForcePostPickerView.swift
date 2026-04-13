import SwiftUI

/// Lets the magician search any Instagram profile, browse ALL their posts
/// (with automatic pagination), and select one to force during the trick.
/// Pass `editingUserId` when changing an existing entry (pre-fills username).
struct ForcePostPickerView: View {
    var editingUserId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ForcePostSettings.shared
    @ObservedObject private var instagram = InstagramService.shared

    @State private var usernameInput: String = ""
    @State private var posts: [InstagramMediaItem] = []
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isSearching = false          // initial search in progress
    @State private var isLoadingMore = false        // pagination in progress
    @State private var hasMorePages = false
    @State private var nextMaxId: String? = nil
    @State private var errorMessage: String?
    @State private var searchedUsername: String = ""
    @State private var searchedUserId: String = ""
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
                searchBar
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                Divider()
                contentArea
            }
            .navigationTitle(editingUserId != nil ? "Change Post" : "Add Force Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if let uid = editingUserId, settings.entry(forUserId: uid) != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Remove", role: .destructive) {
                            settings.clearEntry(userId: uid)
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                // Pre-fill username when editing an existing entry
                if let uid = editingUserId,
                   let entry = settings.entry(forUserId: uid) {
                    usernameInput = entry.username
                }
            }
            .sheet(isPresented: $showingRelogin) {
                ReloginSheet(isPresented: $showingRelogin)
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Instagram username", text: $usernameInput)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(10)
                .onSubmit { searchPosts() }

            Button(action: searchPosts) {
                if isSearching {
                    ProgressView().frame(width: 44, height: 44)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .disabled(isSearching || usernameInput.trimmingCharacters(in: .whitespaces).isEmpty || instagram.isLocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if posts.isEmpty && !isSearching {
            emptyState
        } else if posts.isEmpty && isSearching {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Header with post count
                    HStack {
                        Text("@\(searchedUsername) · \(posts.count)\(hasMorePages ? "+" : "") posts")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        if isLoadingMore {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(posts) { post in
                            PostPickerCell(
                                post: post,
                                image: cachedImages[post.imageURL],
                                isSelected: isPostSelected(post),
                                onTap: { select(post) }
                            )
                        }
                    }

                    // Load more button
                    if hasMorePages {
                        Button(action: loadMorePosts) {
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text("Load more posts")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .disabled(isLoadingMore)
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(searchedUsername.isEmpty
                 ? "Search a username to see their posts"
                 : "No posts found for @\(searchedUsername)")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search

    private func searchPosts() {
        let username = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !username.isEmpty else { return }

        let now = Date()
        if now.timeIntervalSince(lastSearchTime) < 8 {
            let remaining = Int(8 - now.timeIntervalSince(lastSearchTime)) + 1
            errorMessage = "Wait \(remaining)s before searching again"
            return
        }
        guard !instagram.isLocked else {
            errorMessage = "Service temporarily unavailable. Try again later."
            return
        }

        // Session expired — prompt re-login directly
        if instagram.isSessionExpired {
            showingRelogin = true
            return
        }

        lastSearchTime = now
        errorMessage = nil
        isSearching = true
        posts = []
        cachedImages = [:]
        nextMaxId = nil
        hasMorePages = false
        searchedUsername = username

        Task {
            do {
                try await instagram.waitForNetworkStability()

                guard let results = try? await instagram.searchUsers(query: username),
                      let match = results.first(where: { $0.username.lowercased() == username })
                                  ?? results.first else {
                    await MainActor.run {
                        errorMessage = "Profile '@\(username)' not found"
                        isSearching = false
                    }
                    return
                }

                let userId = match.userId
                await MainActor.run { searchedUserId = userId }

                let pause = UInt64.random(in: 1_000_000_000...2_000_000_000)
                try await Task.sleep(nanoseconds: pause)

                let (fetched, nextId) = try await instagram.getUserMediaItems(userId: userId, amount: 18)
                await MainActor.run {
                    posts = fetched
                    nextMaxId = nextId
                    hasMorePages = nextId != nil
                    isSearching = false
                }

                await downloadThumbnails(for: fetched)

            } catch {
                let msg = "\(error)"
                let isPrivate = msg.lowercased().contains("not authorized") || msg.lowercased().contains("not found")
                await MainActor.run {
                    isSearching = false
                    if instagram.isSessionExpired {
                        showingRelogin = true
                    } else {
                        errorMessage = isPrivate
                            ? "@\(username) is a private account. You need to follow them first."
                            : "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Load more pages

    private func loadMorePosts() {
        guard let maxId = nextMaxId, !searchedUserId.isEmpty else { return }
        isLoadingMore = true

        Task {
            do {
                let pause = UInt64.random(in: 800_000_000...1_500_000_000)
                try await Task.sleep(nanoseconds: pause)

                let (fetched, nextId) = try await instagram.getUserMediaItems(
                    userId: searchedUserId, amount: 18, maxId: maxId
                )
                await MainActor.run {
                    posts.append(contentsOf: fetched)
                    nextMaxId = nextId
                    hasMorePages = nextId != nil
                    isLoadingMore = false
                }
                await downloadThumbnails(for: fetched)

            } catch {
                await MainActor.run { isLoadingMore = false }
                print("⚠️ [FORCE POST] Pagination error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func isPostSelected(_ post: InstagramMediaItem) -> Bool {
        // When editing an existing entry, match against that entry's mediaId.
        // When adding new, match against any existing entry for the searched user.
        if let uid = editingUserId {
            return settings.entry(forUserId: uid)?.mediaId == post.mediaId
        }
        return settings.entry(forUserId: searchedUserId)?.mediaId == post.mediaId
    }

    private func select(_ post: InstagramMediaItem) {
        settings.selectPost(item: post, username: searchedUsername, userId: searchedUserId)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }

    private func downloadThumbnails(for items: [InstagramMediaItem]) async {
        for item in items {
            guard cachedImages[item.imageURL] == nil else { continue }
            if let img = await downloadImage(from: item.imageURL) {
                await MainActor.run { cachedImages[item.imageURL] = img }
            }
        }
    }

    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Post cell

private struct PostPickerCell: View {
    let post: InstagramMediaItem
    let image: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay(ProgressView().scaleEffect(0.7))
                }

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
