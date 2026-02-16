import SwiftUI

// MARK: - Archived Photo Model
struct ArchivedPhoto: Identifiable {
    let id = UUID()
    let mediaId: String
    let imageURL: String
    let timestamp: Date?
    var thumbnailImage: UIImage? = nil
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
    @State private var downloadedImages: [String: UIImage] = [:] // mediaId -> UIImage
    
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
                        Text("Loading archived photos...")
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
                        
                        Button(action: loadArchivedPhotos) {
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
                                    onTap: {
                                        selectedPhoto = photo
                                    }
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
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
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
            loadArchivedPhotos()
        }
    }
    
    private func loadArchivedPhotos() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let photos = try await instagram.testGetArchivedPhotos()
                
                await MainActor.run {
                    archivedPhotos = photos.map { photo in
                        ArchivedPhoto(
                            mediaId: photo.mediaId,
                            imageURL: photo.imageURL,
                            timestamp: photo.timestamp
                        )
                    }
                    isLoading = false
                }
                
                // Download thumbnails in background
                await downloadThumbnails()
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func downloadThumbnails() async {
        for photo in archivedPhotos {
            guard !photo.imageURL.isEmpty else { continue }
            
            do {
                if let url = URL(string: photo.imageURL),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        downloadedImages[photo.mediaId] = image
                    }
                }
            } catch {
                print("Failed to download thumbnail for \(photo.mediaId): \(error)")
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
