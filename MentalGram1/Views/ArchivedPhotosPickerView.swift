import SwiftUI

// MARK: - Archived Photo Model
struct ArchivedPhoto: Identifiable {
    let id = UUID()
    let mediaId: String
    let imageURL: String
    let timestamp: Date?
    var thumbnailImage: UIImage? = nil
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
    let onPhotoSelected: (ArchivedPhoto) -> Void

    @State private var archivedPhotos: [ArchivedPhoto] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedPhoto: ArchivedPhoto? = nil
    @State private var downloadedImages: [String: UIImage] = [:]
    @State private var isForcingRefresh = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                VaultTheme.Colors.background
                    .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text(isForcingRefresh ? "Refreshing archive..." : "Loading archived photos...")
                            .foregroundColor(.secondary)
                        if !isForcingRefresh {
                            Text("Fetching all pages — this may take a moment")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
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

                        Button(action: { loadPhotos(forceRefresh: true) }) {
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
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(archivedPhotos) { photo in
                                ArchivedPhotoCell(
                                    photo: photo,
                                    thumbnailImage: downloadedImages[photo.mediaId],
                                    isSelected: selectedPhoto?.mediaId == photo.mediaId,
                                    onTap: { selectedPhoto = photo }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Photo for \(targetSlotSymbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isLoading && errorMessage == nil {
                        Button(action: { loadPhotos(forceRefresh: true) }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select") {
                        if let selected = selectedPhoto {
                            onPhotoSelected(selected)
                            dismiss()
                        }
                    }
                    .foregroundColor(.white)
                    .disabled(selectedPhoto == nil)
                    .opacity(selectedPhoto == nil ? 0.5 : 1.0)
                }
            }
            .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            loadPhotos(forceRefresh: false)
        }
    }

    // MARK: - Load Logic

    private func loadPhotos(forceRefresh: Bool) {
        // Serve from cache if valid and not forcing refresh — zero API calls
        if !forceRefresh, ArchivedPhotosCache.shared.isValid {
            let cached = ArchivedPhotosCache.shared.photos
            archivedPhotos = cached
            isLoading = false
            // Thumbnails already downloaded in a previous open are stored in the cache objects
            for photo in cached {
                if let img = photo.thumbnailImage {
                    downloadedImages[photo.mediaId] = img
                }
            }
            print("📦 [ARCHIVE PICKER] Serving \(cached.count) photos from cache (no API call)")
            return
        }

        isLoading = true
        isForcingRefresh = forceRefresh
        errorMessage = nil

        if forceRefresh {
            ArchivedPhotosCache.shared.invalidate()
        }

        Task {
            do {
                // Full paginated fetch — may take a few seconds for large archives
                let raw = try await instagram.getAllArchivedPhotos()
                var photos = raw.map {
                    ArchivedPhoto(mediaId: $0.mediaId, imageURL: $0.imageURL, timestamp: $0.timestamp)
                }

                await MainActor.run {
                    archivedPhotos = photos
                    isLoading = false
                    isForcingRefresh = false
                }

                // Download thumbnails and store them back into cache objects
                await downloadThumbnails(into: &photos)
                ArchivedPhotosCache.shared.store(photos)

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    isForcingRefresh = false
                }
            }
        }
    }

    private func downloadThumbnails(into photos: inout [ArchivedPhoto]) async {
        for i in photos.indices {
            let photo = photos[i]
            guard !photo.imageURL.isEmpty else { continue }
            if let url = URL(string: photo.imageURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    downloadedImages[photo.mediaId] = image
                    // Keep the displayed grid updated as thumbnails arrive
                    if let idx = archivedPhotos.firstIndex(where: { $0.mediaId == photo.mediaId }) {
                        archivedPhotos[idx].thumbnailImage = image
                    }
                }
                photos[i].thumbnailImage = image  // persist in cache object
            }
        }
    }
}

// MARK: - Archived Photo Cell
struct ArchivedPhotoCell: View {
    let photo: ArchivedPhoto
    let thumbnailImage: UIImage?
    let isSelected: Bool
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
            
            // Selection overlay
            if isSelected {
                Rectangle()
                    .fill(VaultTheme.Colors.primary.opacity(0.3))
                    .frame(width: 110, height: 110)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(VaultTheme.Colors.primary)
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
            onTap()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
