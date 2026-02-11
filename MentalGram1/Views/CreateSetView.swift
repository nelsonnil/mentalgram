import SwiftUI
import PhotosUI

// MARK: - Create Set View

struct CreateSetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager = DataManager.shared
    
    @State private var currentStep = 1
    @State private var setName = ""
    @State private var selectedType: SetType = .custom
    @State private var bankCount = 5
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var loadedPhotos: [(symbol: String, filename: String, imageData: Data)] = []
    @State private var isLoadingPhotos = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.purple : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding()
                
                TabView(selection: $currentStep) {
                    // Step 1: Type Selection
                    step1TypeSelection
                        .tag(1)
                    
                    // Step 2: Configuration
                    step2Configuration
                        .tag(2)
                    
                    // Step 3: Photo Selection & Reorder
                    step3PhotoSelection
                        .tag(3)
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
    
    // MARK: - Step 2: Configuration
    
    private var step2Configuration: some View {
        VStack(spacing: 24) {
            Text("Configure Set")
                .font(.title2.bold())
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 20) {
                // Set Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Name")
                        .font(.headline)
                    TextField("Enter set name", text: $setName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Bank Count (for word/number types)
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
            }
            .padding()
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: { withAnimation { currentStep = 1 } }) {
                    Text("Back")
                        .font(.headline)
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
                
                Button(action: { withAnimation { currentStep = 3 } }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(setName.isEmpty ? Color.gray : Color.purple)
                        .cornerRadius(12)
                }
                .disabled(setName.isEmpty)
            }
            .padding()
        }
    }
    
    // MARK: - Step 3: Photo Selection & Reorder
    
    private var step3PhotoSelection: some View {
        VStack(spacing: 16) {
            if loadedPhotos.isEmpty {
                // Initial state: photo picker
                VStack(spacing: 20) {
                    Text("Select Photos")
                        .font(.title2.bold())
                        .padding(.top)
                    
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 100,
                        matching: .images
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48))
                                .foregroundColor(.purple)
                            
                            Text("Tap to select photos")
                                .font(.headline)
                            
                            Text(selectedType == .word ? "Select A-Z images" : selectedType == .number ? "Select 0-9 images" : "Select your images")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    if isLoadingPhotos {
                        ProgressView("Loading photos...")
                            .padding()
                    }
                    
                    Spacer()
                    
                    Button(action: { withAnimation { currentStep = 2 } }) {
                        Text("Back")
                            .font(.headline)
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding()
                }
            } else {
                // Photos loaded: show reorderable grid
                VStack(spacing: 12) {
                    HStack {
                        Text("Drag to reorder (\(loadedPhotos.count) photos)")
                            .font(.headline)
                        
                        Spacer()
                        
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 100,
                            matching: .images
                        ) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Upload order info
                    if selectedType != .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upload Order:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text("Bank 1: Photos 1-\(loadedPhotos.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            ForEach(2...bankCount, id: \.self) { bank in
                                let startIndex = (bank - 1) * loadedPhotos.count + 1
                                let endIndex = bank * loadedPhotos.count
                                Text("Bank \(bank): Photos \(startIndex)-\(endIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    // Reorderable grid
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(loadedPhotos.indices, id: \.self) { index in
                                DraggablePhotoCell(
                                    photo: loadedPhotos[index],
                                    position: index + 1,
                                    onMove: { from, to in
                                        movePhoto(from: from, to: to)
                                    },
                                    onDelete: {
                                        deletePhoto(at: index)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { withAnimation { currentStep = 2 } }) {
                            Text("Back")
                                .font(.headline)
                                .foregroundColor(.purple)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        
                        Button(action: createSet) {
                            Text("Create Set")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
        }
        .onChange(of: selectedItems) { newItems in
            loadPhotosFromPicker(items: newItems)
        }
    }
    
    // MARK: - Photo Reordering
    
    private func movePhoto(from: Int, to: Int) {
        withAnimation {
            loadedPhotos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
    
    private func deletePhoto(at index: Int) {
        withAnimation {
            loadedPhotos.remove(at: index)
            if loadedPhotos.isEmpty {
                selectedItems = []
            }
        }
    }
    
    // MARK: - Load Photos from Picker
    
    private func loadPhotosFromPicker(items: [PhotosPickerItem]) {
        isLoadingPhotos = true
        
        Task {
            var newPhotos: [(symbol: String, filename: String, imageData: Data)] = []
            
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 0.8) {
                    
                    // Extract filename (symbol) - remove extension
                    let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
                    let symbol = filename.replacingOccurrences(of: ".jpg", with: "")
                        .replacingOccurrences(of: ".jpeg", with: "")
                        .replacingOccurrences(of: ".png", with: "")
                        .replacingOccurrences(of: ".heic", with: "")
                    
                    newPhotos.append((symbol: symbol, filename: filename, imageData: jpegData))
                }
            }
            
            await MainActor.run {
                // Append new photos (don't replace if user is adding more)
                if loadedPhotos.isEmpty {
                    loadedPhotos = newPhotos
                } else {
                    loadedPhotos.append(contentsOf: newPhotos)
                }
                isLoadingPhotos = false
            }
        }
    }
    
    // MARK: - Create Set
    
    private func createSet() {
        let newSet = dataManager.createSet(
            name: setName,
            type: selectedType,
            bankCount: selectedType == .custom ? 1 : bankCount,
            photos: loadedPhotos
        )
        
        isPresented = false
    }
}

// MARK: - Draggable Photo Cell

struct DraggablePhotoCell: View {
    let photo: (symbol: String, filename: String, imageData: Data)
    let position: Int
    let onMove: (Int, Int) -> Void
    let onDelete: () -> Void
    
    @State private var isDragging = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Photo
            if let uiImage = UIImage(data: photo.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: isDragging ? Color.purple.opacity(0.3) : Color.clear, radius: 8)
            }
            
            // Position badge (BIG number)
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 32, height: 32)
                
                Text("\(position)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: -4, y: -4)
            
            // Symbol label
            Text(photo.symbol)
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(4)
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 4, y: -4)
        }
        .frame(width: 100, height: 100)
        .onDrag {
            isDragging = true
            return NSItemProvider(object: String(position - 1) as NSString)
        }
        .onDrop(of: [.text], delegate: PhotoDropDelegate(
            position: position - 1,
            onMove: onMove,
            isDragging: $isDragging
        ))
    }
}

// MARK: - Drop Delegate

struct PhotoDropDelegate: DropDelegate {
    let position: Int
    let onMove: (Int, Int) -> Void
    @Binding var isDragging: Bool
    
    func performDrop(info: DropInfo) -> Bool {
        isDragging = false
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let itemProviders = info.itemProviders(for: [.text]).first else { return }
        
        itemProviders.loadItem(forTypeIdentifier: "public.text", options: nil) { data, error in
            guard let data = data as? Data,
                  let fromString = String(data: data, encoding: .utf8),
                  let from = Int(fromString),
                  from != position else { return }
            
            DispatchQueue.main.async {
                onMove(from, position)
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        isDragging = false
    }
}
