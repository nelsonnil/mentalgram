import SwiftUI
import PhotosUI

// MARK: - Create Set View

struct CreateSetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager = DataManager.shared
    var onSetCreated: ((PhotoSet) -> Void)? = nil  // Callback when set is created
    
    @State private var currentStep = 1
    @State private var setName = ""
    @State private var selectedType: SetType = .custom
    @State private var bankCount = 5
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator (2 steps now)
                HStack(spacing: 8) {
                    ForEach(1...2, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.purple : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding()
                
                TabView(selection: $currentStep) {
                    step1TypeSelection.tag(1)
                    step2ConfigurationWithPicker.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Create Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: selectedItems) { newItems in
            loadPhotosFromPicker(items: newItems)
        }
    }
    
    // MARK: - Step 1: Type Selection
    
    private var step1TypeSelection: some View {
        VStack(spacing: 24) {
            Text("Choose Set Type")
                .font(.title2.bold())
                .padding(.top)
            
            VStack(spacing: 16) {
                ForEach(SetType.allCases, id: \.self) { type in
                    Button(action: { selectedType = type }) {
                        HStack(spacing: 16) {
                            Image(systemName: type.icon)
                                .font(.title2)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.title)
                                    .font(.headline)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.purple)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedType == type ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedType == type ? Color.purple : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Spacer()
            
            Button(action: { withAnimation { currentStep = 2 } }) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding()
        }
    }
    
    // MARK: - Step 2: Configuration + Photo Picker (Combined)
    
    private var step2ConfigurationWithPicker: some View {
        VStack(spacing: 24) {
            Text("Configure & Select")
                .font(.title2.bold())
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Name")
                        .font(.headline)
                    TextField("Enter set name", text: $setName)
                        .textFieldStyle(.roundedBorder)
                }
                
                if selectedType != .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Banks")
                            .font(.headline)
                        
                        Stepper(value: $bankCount, in: 1...10) {
                            Text("\(bankCount) banks")
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Each image will be uploaded \(bankCount) times (once per bank)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Photo Picker (integrated)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Photos")
                        .font(.headline)
                    
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 100,
                        matching: .images
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tap to select photos")
                                    .font(.subheadline.bold())
                                Text(photoPickerPrompt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple, lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
            
            if isLoadingPhotos {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Creating set and loading photos...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            Spacer()
            
            Button(action: { withAnimation { currentStep = 1 } }) {
                Text("Back")
                    .font(.headline)
                    .foregroundColor(.purple)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding()
            .disabled(isLoadingPhotos)
        }
    }
    
    private var photoPickerPrompt: String {
        switch selectedType {
        case .word: return "Select A-Z images"
        case .number: return "Select 0-9 images"
        case .custom: return "Select your images"
        }
    }
    
    // MARK: - Load Photos from Picker & Auto-Create Set
    
    private func loadPhotosFromPicker(items: [PhotosPickerItem]) {
        guard !items.isEmpty, !setName.isEmpty else { return }
        
        isLoadingPhotos = true
        
        Task {
            var loadedPhotos: [(symbol: String, filename: String, imageData: Data)] = []
            
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 0.8) {
                    
                    let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
                    let symbol = filename.replacingOccurrences(of: ".jpg", with: "")
                        .replacingOccurrences(of: ".jpeg", with: "")
                        .replacingOccurrences(of: ".png", with: "")
                        .replacingOccurrences(of: ".heic", with: "")
                    
                    loadedPhotos.append((symbol: symbol, filename: filename, imageData: jpegData))
                }
            }
            
            // AUTO-CREATE SET when photos are loaded
            if !loadedPhotos.isEmpty {
                let newSet = dataManager.createSet(
                    name: setName,
                    type: selectedType,
                    bankCount: selectedType == .custom ? 1 : bankCount,
                    photos: loadedPhotos
                )
                
                await MainActor.run {
                    isLoadingPhotos = false
                    // Notify parent and close
                    onSetCreated?(newSet)
                    isPresented = false
                }
            } else {
                await MainActor.run {
                    isLoadingPhotos = false
                }
            }
        }
    }
}
