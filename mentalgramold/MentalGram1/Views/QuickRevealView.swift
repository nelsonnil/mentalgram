import SwiftUI

// MARK: - Quick Reveal View

struct QuickRevealView: View {
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var instagram = InstagramService.shared
    
    @State private var selectedSetId: UUID?
    @State private var revealValue = ""
    @State private var isRevealing = false
    @State private var resultMessage = ""
    @State private var showingResult = false
    
    var completedSets: [PhotoSet] {
        dataManager.sets.filter { $0.status == .completed }
    }
    
    var selectedSet: PhotoSet? {
        guard let id = selectedSetId else { return nil }
        return completedSets.first(where: { $0.id == id })
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.purple)
                    
                    Text("Quick Reveal")
                        .font(.title.bold())
                    
                    Text("Instantly unarchive and reveal photos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)
                
                if completedSets.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No completed sets")
                            .font(.headline)
                        
                        Text("Upload a set first to use Quick Reveal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Set Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select Set")
                                .font(.headline)
                            
                            Menu {
                                ForEach(completedSets) { set in
                                    Button(action: { selectedSetId = set.id }) {
                                        Label(set.name, systemImage: set.type.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    if let set = selectedSet {
                                        Image(systemName: set.type.icon)
                                        Text(set.name)
                                    } else {
                                        Text("Choose a set...")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Value Input
                        if let set = selectedSet {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Value to Reveal")
                                    .font(.headline)
                                
                                TextField(placeholderForSet(set), text: $revealValue)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                
                                Text(hintForSet(set))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Reveal Button
                        if selectedSet != nil && !revealValue.isEmpty {
                            Button(action: performReveal) {
                                if isRevealing {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Label("Reveal Magic", systemImage: "sparkles")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isRevealing ? Color.gray : Color.purple)
                            .cornerRadius(12)
                            .disabled(isRevealing)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Quick Reveal")
        .alert("Reveal Result", isPresented: $showingResult) {
            Button("OK") { resultMessage = "" }
        } message: {
            Text(resultMessage)
        }
    }
    
    // MARK: - Helpers
    
    private func placeholderForSet(_ set: PhotoSet) -> String {
        switch set.type {
        case .word: return "COCHE"
        case .number: return "393"
        case .custom: return "7_corazones"
        }
    }
    
    private func hintForSet(_ set: PhotoSet) -> String {
        switch set.type {
        case .word: return "Enter a word (one letter per bank)"
        case .number: return "Enter a number (one digit per bank)"
        case .custom: return "Enter the exact filename (without extension)"
        }
    }
    
    // MARK: - Perform Reveal
    
    private func performReveal() {
        guard let set = selectedSet else { return }
        
        isRevealing = true
        
        Task {
            do {
                let value = revealValue.uppercased()
                
                if set.type == .word || set.type == .number {
                    // Multi-bank reveal
                    let characters = Array(value)
                    var revealed: [String] = []
                    
                    for (index, char) in characters.enumerated() {
                        let bankPosition = index + 1
                        
                        guard bankPosition <= set.banks.count else {
                            await MainActor.run {
                                resultMessage = "⚠️ Not enough banks for \"\(value)\"\n\nThis set has \(set.banks.count) banks."
                                showingResult = true
                                isRevealing = false
                            }
                            return
                        }
                        
                        let bank = set.banks.first(where: { $0.position == bankPosition })!
                        let photo = set.photos.first(where: { $0.bankId == bank.id && $0.symbol == String(char) })
                        
                        guard let photo = photo, let mediaId = photo.mediaId else {
                            await MainActor.run {
                                resultMessage = "❌ Photo \"\(char)\" not found in Bank \(bankPosition)"
                                showingResult = true
                                isRevealing = false
                            }
                            return
                        }
                        
                        let result = try await instagram.reveal(mediaId: mediaId)
                        
                        if result.success {
                            revealed.append(String(char))
                            dataManager.updatePhoto(photoId: photo.id, mediaId: nil, isArchived: false, commentId: result.commentId)
                        }
                        
                        // Delay between reveals
                        if index < characters.count - 1 {
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                    }
                    
                    await MainActor.run {
                        resultMessage = "✨ Successfully revealed: \(revealed.joined())\n\nCheck Instagram!"
                        showingResult = true
                        isRevealing = false
                        revealValue = ""
                    }
                    
                } else {
                    // Custom: single photo
                    guard let photo = set.photos.first(where: { $0.symbol.lowercased() == value.lowercased() || $0.filename.lowercased().contains(value.lowercased()) }),
                          let mediaId = photo.mediaId else {
                        await MainActor.run {
                            resultMessage = "❌ Photo \"\(value)\" not found in set"
                            showingResult = true
                            isRevealing = false
                        }
                        return
                    }
                    
                    let result = try await instagram.reveal(mediaId: mediaId)
                    
                    if result.success {
                        await MainActor.run {
                            dataManager.updatePhoto(photoId: photo.id, mediaId: nil, isArchived: false, commentId: result.commentId)
                            resultMessage = "✨ Successfully revealed: \(photo.symbol)\n\nComment posted for: \(result.follower ?? "latest follower")"
                            showingResult = true
                            isRevealing = false
                            revealValue = ""
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    resultMessage = "❌ Error: \(error.localizedDescription)"
                    showingResult = true
                    isRevealing = false
                }
            }
        }
    }
}
