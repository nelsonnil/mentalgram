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
                    
                    // Step 3: Photo Selection
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
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: { withAnimation { currentStep = 2 } }) {
                Text("Next")
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
            Text("Configuration")
                .font(.title2.bold())
                .padding(.top)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Name")
                        .font(.headline)
                    TextField("My Magic Set", text: $setName)
                        .textFieldStyle(.roundedBorder)
                }
                
                if selectedType == .word || selectedType == .number {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Banks")
                            .font(.headline)
                        
                        Stepper(value: $bankCount, in: 1...10) {
                            HStack {
                                Text("\(bankCount) banks")
                                Spacer()
                                Text("Total: \(bankCount) × photos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("How many times to repeat the photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
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
                    Text("Next")
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
    
    // MARK: - Step 3: Photo Selection
    
    private var step3PhotoSelection: some View {
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
                    
                    Text(loadedPhotos.isEmpty ? "Tap to select photos" : "\(loadedPhotos.count) photos selected")
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
            .onChange(of: selectedItems) { newItems in
                loadPhotosFromPicker(items: newItems)
            }
            
            if isLoadingPhotos {
                ProgressView("Loading photos...")
                    .padding()
            }
            
            if !loadedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(loadedPhotos.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: loadedPhotos[index].imageData) {
                                VStack {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Text(loadedPhotos[index].symbol)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 120)
            }
            
            Spacer()
            
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
                        .background(loadedPhotos.isEmpty ? Color.gray : Color.green)
                        .cornerRadius(12)
                }
                .disabled(loadedPhotos.isEmpty || isLoadingPhotos)
            }
            .padding()
        }
    }
    
    // MARK: - Load Photos from Picker
    
    private func loadPhotosFromPicker(items: [PhotosPickerItem]) {
        isLoadingPhotos = true
        loadedPhotos = []
        
        Task {
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
                    
                    await MainActor.run {
                        loadedPhotos.append((symbol: symbol, filename: filename, imageData: jpegData))
                    }
                }
            }
            
            await MainActor.run {
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
