import SwiftUI

// MARK: - Archived Photo Model
struct ArchivedPhoto: Identifiable {
    let id = UUID()
    let mediaId: String
    let imageURL: String
    let timestamp: Date?
    var thumbnailImage: UIImage? = nil
    var isVideo: Bool = false
    var videoURL: String? = nil
    var videoAspectRatio: CGFloat? = nil
}

// MARK: - Archived Photos Cache
/// In-memory cache shared across all ArchivedPhotosPickerView instances.
/// Prevents redundant API calls when the user opens the picker for multiple slots.
/// TTL = 15 minutes — after that the next open triggers a fresh full fetch.
final class ArchivedPhotosCache {
    static let shared = ArchivedPhotosCache()
    private init() {}

    private(set) var photos: [ArchivedPhoto] = []
    private var fetchedAt: Date? = nil
    private let ttl: TimeInterval = 15 * 60  // 15 minutes

    var isValid: Bool {
        guard let t = fetchedAt else { return false }
        return Date().timeIntervalSince(t) < ttl
    }

    func store(_ photos: [ArchivedPhoto]) {
        self.photos = photos
        self.fetchedAt = Date()
    }

    func invalidate() {
        photos = []
        fetchedAt = nil
    }
}

// MARK: - Archived Photos Picker View
struct ArchivedPhotosPickerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var instagram = InstagramService.shared

    let targetSlotSymbol: String
    var multiSelectMode: Bool = false
    var maxSelection: Int = 1
    var destinationLabels: [String] = []
    var excludedMediaIds: Set<String> = []
    let onPhotoSelected: (ArchivedPhoto) -> Void
    var onPhotosSelected: (([ArchivedPhoto]) -> Void)? = nil

    // Accumulated photos across all loaded pages
    @State private var archivedPhotos: [ArchivedPhoto] = []
    @State private var downloadedImages: [String: UIImage] = [:]
    @State private var selectedPhoto: ArchivedPhoto? = nil
    @State private var selectedMediaIds: [String] = []

    // Pagination state
    @State private var nextCursor: String? = nil
    @State private var hasMore = true
    @State private var seenMediaIds: Set<String> = []

    // Loading states
    @State private var isLoadingFirst = true   // first page — show full-screen spinner
    @State private var isLoadingMore = false   // subsequent pages — show bottom spinner
    @State private var errorMessage: String? = nil
    @State private var loadMoreError: String? = nil
    @State private var rateLimited = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                VaultTheme.Colors.background.ignoresSafeArea()

                if isLoadingFirst {
                    VStack(spacing: 16) {
                        ProgressView().tint(.white)
                        Text("Loading archived photos…")
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Could not load archived photos")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button(action: { resetAndLoad() }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(VaultTheme.Colors.primary)
                                .cornerRadius(VaultTheme.CornerRadius.md)
                        }
                    }
                    .padding()
                } else if archivedPhotos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No archived photos found")
                            .font(.headline)
                        Text("Upload and archive photos first to use this feature")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        if multiSelectMode {
                            VStack(spacing: 4) {
                                Text("\(selectedMediaIds.count)/\(maxSelection) selected")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("archive_picker.bulk_help")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                if hasMore {
                                    Text("archive_picker.load_more_hint")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(archivedPhotos) { photo in
                                let isExcluded = excludedMediaIds.contains(photo.mediaId)
                                ArchivedPhotoCell(
                                    photo: photo,
                                    thumbnailImage: downloadedImages[photo.mediaId],
                                    isSelected: multiSelectMode
                                        ? selectedMediaIds.contains(photo.mediaId)
                                        : selectedPhoto?.mediaId == photo.mediaId,
                                    isDisabled: isExcluded,
                                    selectionLabel: selectionLabel(for: photo.mediaId),
                                    onTap: {
                                        if multiSelectMode {
                                            toggleMultiSelection(photo)
                                        } else if !isExcluded {
                                            selectedPhoto = photo
                                        }
                                    }
                                )
                            }
                        }
                        .padding()

                        // ── Bottom pagination area ──────────────────────────────
                        if isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 20)
                        } else if rateLimited {
                            VStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Too many API requests — wait a moment before loading more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Try Again") { loadNextPage() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                        } else if let err = loadMoreError {
                            VStack(spacing: 6) {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") { loadNextPage() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                        } else if hasMore {
                            Button(action: { loadNextPage() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load more (\(archivedPhotos.count) loaded)")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(VaultTheme.Colors.primary)
                                .padding(.vertical, 14)
                            }
                        } else {
                            Text("All \(archivedPhotos.count) photos loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationTitle(multiSelectMode ? "Select Archived Photos" : "Select Photo for \(targetSlotSymbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isLoadingFirst && errorMessage == nil {
                        Button(action: { resetAndLoad() }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(multiSelectMode ? "Import" : "Select") {
                        if multiSelectMode {
                            let selected = selectedMediaIds.compactMap { mediaId in
                                archivedPhotos.first(where: { $0.mediaId == mediaId })
                            }
                            onPhotosSelected?(selected)
                            dismiss()
                        } else if let selected = selectedPhoto {
                            onPhotoSelected(selected)
                            dismiss()
                        }
                    }
                    .foregroundColor(.white)
                    .disabled(multiSelectMode ? selectedMediaIds.isEmpty : selectedPhoto == nil)
                    .opacity((multiSelectMode ? selectedMediaIds.isEmpty : selectedPhoto == nil) ? 0.5 : 1.0)
                }
            }
            .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { loadFirstPage() }
    }

    private func toggleMultiSelection(_ photo: ArchivedPhoto) {
        guard !excludedMediaIds.contains(photo.mediaId) else { return }
        if let existingIndex = selectedMediaIds.firstIndex(of: photo.mediaId) {
            selectedMediaIds.remove(at: existingIndex)
        } else if selectedMediaIds.count < maxSelection {
            selectedMediaIds.append(photo.mediaId)
        }
    }

    private func selectionLabel(for mediaId: String) -> String? {
        guard let index = selectedMediaIds.firstIndex(of: mediaId) else { return nil }
        if destinationLabels.indices.contains(index) {
            return destinationLabels[index]
        }
        return "\(index + 1)"
    }

    // MARK: - Load Logic

    private func resetAndLoad() {
        archivedPhotos = []
        downloadedImages = [:]
        nextCursor = nil
        hasMore = true
        seenMediaIds = []
        errorMessage = nil
        loadMoreError = nil
        rateLimited = false
        ArchivedPhotosCache.shared.invalidate()
        loadFirstPage()
    }

    private func loadFirstPage() {
        // Serve from in-memory cache for instant reopens (no API call)
        if ArchivedPhotosCache.shared.isValid {
            let cached = ArchivedPhotosCache.shared.photos
            archivedPhotos = cached
            for photo in cached { if let img = photo.thumbnailImage { downloadedImages[photo.mediaId] = img } }
            hasMore = false   // cache is the full result
            isLoadingFirst = false
            print("📦 [ARCHIVE PICKER] \(cached.count) photos from cache")
            return
        }

        isLoadingFirst = true
        errorMessage = nil

        Task {
            do {
                var ids = seenMediaIds
                let result = try await instagram.fetchArchivedPhotosPage(
                    cursor: nil, seenMediaIds: &ids, applyDelay: false)
                seenMediaIds = ids
                let newPhotos = result.photos.map {
                    ArchivedPhoto(mediaId: $0.mediaId, imageURL: $0.imageURL, timestamp: $0.timestamp,
                                  isVideo: $0.isVideo, videoURL: $0.videoURL,
                                  videoAspectRatio: $0.videoAspectRatio)
                }
                await MainActor.run {
                    archivedPhotos = newPhotos
                    nextCursor = result.nextCursor
                    hasMore = result.hasMore
                    rateLimited = result.rateLimited
                    isLoadingFirst = false
                }
                await downloadThumbnails(for: newPhotos, startingAt: 0)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingFirst = false
                }
            }
        }
    }

    private func loadNextPage() {
        guard hasMore, !isLoadingMore, !isLoadingFirst else { return }
        isLoadingMore = true
        loadMoreError = nil
        rateLimited = false

        Task {
            do {
                var ids = seenMediaIds
                let result = try await instagram.fetchArchivedPhotosPage(
                    cursor: nextCursor, seenMediaIds: &ids, applyDelay: true)
                seenMediaIds = ids
                let newPhotos = result.photos.map {
                    ArchivedPhoto(mediaId: $0.mediaId, imageURL: $0.imageURL, timestamp: $0.timestamp,
                                  isVideo: $0.isVideo, videoURL: $0.videoURL,
                                  videoAspectRatio: $0.videoAspectRatio)
                }
                let startIndex = archivedPhotos.count
                await MainActor.run {
                    archivedPhotos.append(contentsOf: newPhotos)
                    nextCursor = result.nextCursor
                    hasMore = result.hasMore
                    rateLimited = result.rateLimited
                    isLoadingMore = false
                    if result.blocked {
                        loadMoreError = "Upload in progress — try again once it finishes"
                    }
                }
                await downloadThumbnails(for: newPhotos, startingAt: startIndex)

                // When all pages are loaded, store in cache
                if !result.hasMore && !result.rateLimited && !result.blocked {
                    ArchivedPhotosCache.shared.store(archivedPhotos)
                }
            } catch {
                await MainActor.run {
                    loadMoreError = error.localizedDescription
                    isLoadingMore = false
                }
            }
        }
    }

    private func downloadThumbnails(for photos: [ArchivedPhoto], startingAt offset: Int) async {
        for (i, photo) in photos.enumerated() {
            guard !photo.imageURL.isEmpty else { continue }
            if let url = URL(string: photo.imageURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                let globalIndex = offset + i
                await MainActor.run {
                    downloadedImages[photo.mediaId] = image
                    if globalIndex < archivedPhotos.count {
                        archivedPhotos[globalIndex].thumbnailImage = image
                    }
                }
            }
        }
    }
}

// MARK: - Archived Photo Cell
struct ArchivedPhotoCell: View {
    let photo: ArchivedPhoto
    let thumbnailImage: UIImage?
    let isSelected: Bool
    var isDisabled: Bool = false
    var selectionLabel: String? = nil
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 110, height: 110)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
            
            if isDisabled {
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 110, height: 110)

                Text("Used")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(6)
            }

            // Selection overlay
            if isSelected {
                Rectangle()
                    .fill(VaultTheme.Colors.primary.opacity(0.3))
                    .frame(width: 110, height: 110)

                if let selectionLabel {
                    Text(selectionLabel)
                        .font(.system(size: selectionLabel.count > 2 ? 13 : 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(Capsule().fill(VaultTheme.Colors.primary))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(VaultTheme.Colors.primary)
                }
            }

            // Video badge (top-left) — indicates this is a video, not a photo
            if photo.isVideo {
                VStack {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(4)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(width: 110, height: 110)
                .padding(5)
            }

            // Date overlay
            if let timestamp = photo.timestamp {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDate(timestamp))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                }
                .frame(width: 110, height: 110)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? VaultTheme.Colors.primary : Color.clear, lineWidth: 3)
        )
        .onTapGesture {
            if !isDisabled {
                onTap()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
