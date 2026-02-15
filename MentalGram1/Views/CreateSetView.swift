import SwiftUI
import PhotosUI

// MARK: - Slot Photo (local state before set creation)

private struct SlotPhoto: Identifiable {
    let id = UUID()
    let symbol: String
    let filename: String
    let imageData: Data
    var thumbnail: UIImage? {
        UIImage(data: imageData)
    }
}

// MARK: - Create Set View

struct CreateSetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager = DataManager.shared
    var onSetCreated: ((PhotoSet) -> Void)? = nil
    
    // Navigation
    @State private var currentStep = 1
    
    // Configuration
    @State private var setName = ""
    @State private var selectedType: SetType = .custom
    @State private var bankCount = 5
    @State private var selectedAlphabet: AlphabetType = .latin
    
    // Slot-based photo state (Number/Word Reveal)
    @State private var slotPhotos: [String: SlotPhoto] = [:]  // symbol → photo
    @State private var slotPickerItem: PhotosPickerItem? = nil
    @State private var targetSlotSymbol: String? = nil
    @State private var processingSlotSymbol: String? = nil
    
    // Bulk select (Number/Word "Select All" + Custom)
    @State private var bulkSelectedItems: [PhotosPickerItem] = []
    @State private var isLoadingBulk = false
    @State private var bulkLoadProgress: (current: Int, total: Int) = (0, 0)
    
    // Set creation
    @State private var isCreatingSet = false
    @State private var showIncompleteAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: VaultTheme.Spacing.sm) {
                    ForEach(1...2, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? VaultTheme.Colors.primary : VaultTheme.Colors.cardBorder)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(VaultTheme.Spacing.lg)
                
                TabView(selection: $currentStep) {
                    step1TypeSelection.tag(1)
                    step2Configuration.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(VaultTheme.Colors.background)
            .navigationTitle("Create Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(VaultTheme.Colors.primary)
                    .disabled(isCreatingSet || isLoadingBulk)
                }
            }
            .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        // Single slot photo picked
        .onChange(of: slotPickerItem) { newItem in
            guard let item = newItem, let symbol = targetSlotSymbol else { return }
            loadSingleSlotPhoto(item: item, symbol: symbol)
        }
        // Bulk "Select All" picked (for Number/Word)
        .onChange(of: bulkSelectedItems) { newItems in
            if selectedType == .custom {
                loadCustomPhotosAndCreate(items: newItems)
            } else {
                loadBulkPhotosIntoSlots(items: newItems)
            }
        }
        // Incomplete set warning
        .alert("Incomplete Set", isPresented: $showIncompleteAlert) {
            Button("Create Anyway") {
                finalizeSetCreation()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let filled = slotPhotos.count
            let total = currentSlotLabels.count
            let missing = currentSlotLabels.filter { slotPhotos[$0] == nil }
            let missingList = missing.prefix(10).joined(separator: ", ")
            let extra = missing.count > 10 ? " and \(missing.count - 10) more..." : ""
            Text("You have \(filled) of \(total) photos.\n\nMissing: \(missingList)\(extra)\n\nYou can add missing photos later from the set detail view.")
        }
    }
    
    // MARK: - Computed Helpers
    
    private var currentSlotLabels: [String] {
        switch selectedType {
        case .number: return (0...9).map { "\($0)" }
        case .word: return selectedAlphabet.characters
        case .custom: return []
        }
    }
    
    private var filledSlotCount: Int {
        slotPhotos.count
    }
    
    private var totalSlotCount: Int {
        currentSlotLabels.count
    }
    
    private var canCreateSet: Bool {
        !setName.trimmingCharacters(in: .whitespaces).isEmpty && filledSlotCount > 0
    }
    
    // MARK: - Step 1: Type Selection
    
    private var step1TypeSelection: some View {
        VStack(spacing: VaultTheme.Spacing.xxl) {
            Text("Choose Set Type")
                .font(.title2.bold())
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .padding(.top, VaultTheme.Spacing.lg)
            
            VaultCard {
                VStack(spacing: VaultTheme.Spacing.lg) {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Button(action: {
                            if selectedType != type {
                                selectedType = type
                                slotPhotos.removeAll()  // Clear slots on type change
                            }
                        }) {
                            HStack(spacing: VaultTheme.Spacing.lg) {
                                Image(systemName: type.icon)
                                    .font(.title2)
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                    Text(type.title)
                                        .font(.headline)
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                if selectedType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                }
                            }
                            .padding(VaultTheme.Spacing.lg)
                            .background(
                                RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                                    .fill(selectedType == type ? VaultTheme.Colors.primary.opacity(0.1) : VaultTheme.Colors.cardBorder.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                                    .stroke(selectedType == type ? VaultTheme.Colors.primary : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer()
            
            GradientButton(
                title: "Continue",
                icon: nil,
                action: { withAnimation { currentStep = 2 } }
            )
            .padding(VaultTheme.Spacing.lg)
        }
        .background(VaultTheme.Colors.background)
    }
    
    // MARK: - Step 2: Configuration + Slot Grid / Photo Picker
    
    private var step2Configuration: some View {
        ScrollView {
            VStack(spacing: VaultTheme.Spacing.xl) {
                Text("Configure & Select")
                    .font(.title2.bold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, VaultTheme.Spacing.lg)
                
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
                    // Set Name
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Set Name")
                            .font(.headline)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        TextField("Enter set name", text: $setName)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                    }
                    
                    // Alphabet Selector (only for Word Reveal)
                    if selectedType == .word {
                        alphabetSelector
                    }
                    
                    // Bank Count (for word/number)
                    if selectedType != .custom {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Number of Banks")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            Stepper(value: $bankCount, in: 1...10) {
                                Text("\(bankCount) banks")
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .tint(VaultTheme.Colors.primary)
                            
                            Text("Each image will be uploaded \(bankCount) times (once per bank). Total: \(totalSlotCount * bankCount) uploads.")
                                .font(.caption)
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, VaultTheme.Spacing.lg)
                
                Divider()
                    .background(VaultTheme.Colors.cardBorder)
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                
                // SLOT GRID (Number/Word) or PHOTO PICKER (Custom)
                if selectedType == .word || selectedType == .number {
                    slotGridSection
                } else {
                    customPhotoPickerSection
                }
                
                Spacer(minLength: VaultTheme.Spacing.xl)
                
                // Bottom buttons
                VStack(spacing: VaultTheme.Spacing.md) {
                    // CREATE SET button (Number/Word only - Custom auto-creates)
                    if selectedType != .custom {
                        ZStack {
                            GradientButton(
                                title: "Create Set",
                                icon: "checkmark.circle.fill",
                                action: handleCreateSet,
                                isEnabled: canCreateSet && !isCreatingSet,
                                style: .success
                            )
                            .disabled(!canCreateSet || isCreatingSet || isLoadingBulk)
                            if isCreatingSet {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                    }
                    
                    OutlineButton(
                        title: "Back",
                        icon: nil,
                        action: { withAnimation { currentStep = 1 } },
                        isEnabled: !isCreatingSet && !isLoadingBulk
                    )
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    .disabled(isCreatingSet || isLoadingBulk)
                }
                .padding(.bottom, VaultTheme.Spacing.lg)
            }
        }
        .background(VaultTheme.Colors.background)
    }
    
    // MARK: - Alphabet Selector
    
    private var alphabetSelector: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Alphabet")
                .font(.headline)
                .foregroundColor(VaultTheme.Colors.textPrimary)
            
            Text("Choose the alphabet for letter ordering")
                .font(.caption)
                .foregroundColor(VaultTheme.Colors.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: VaultTheme.Spacing.md) {
                ForEach(AlphabetType.allCases, id: \.self) { alphabet in
                    Button(action: {
                        if selectedAlphabet != alphabet {
                            selectedAlphabet = alphabet
                            slotPhotos.removeAll()  // Clear on alphabet change
                        }
                    }) {
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Text(alphabet.flag)
                                .font(.title3)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                Text(alphabet.displayName)
                                    .font(.caption.bold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text("\(alphabet.count) letters")
                                    .font(.caption2)
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            if selectedAlphabet == alphabet {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(VaultTheme.Colors.primary)
                                    .font(.caption)
                            }
                        }
                        .padding(VaultTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                .fill(selectedAlphabet == alphabet ? VaultTheme.Colors.primary.opacity(0.1) : VaultTheme.Colors.cardBorder.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                .stroke(selectedAlphabet == alphabet ? VaultTheme.Colors.primary : VaultTheme.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Slot Grid Section (Number / Word Reveal)
    
    private var slotGridSection: some View {
        VStack(spacing: VaultTheme.Spacing.lg) {
            // Header with progress
            HStack {
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                    Text("Photos")
                        .font(.headline)
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        // Progress circle
                        ZStack {
                            Circle()
                                .stroke(VaultTheme.Colors.cardBorder, lineWidth: 3)
                                .frame(width: 20, height: 20)
                            Circle()
                                .trim(from: 0, to: totalSlotCount > 0 ? CGFloat(filledSlotCount) / CGFloat(totalSlotCount) : 0)
                                .stroke(filledSlotCount == totalSlotCount ? VaultTheme.Colors.success : VaultTheme.Colors.primary, lineWidth: 3)
                                .frame(width: 20, height: 20)
                                .rotationEffect(.degrees(-90))
                        }
                        
                        Text("\(filledSlotCount)/\(totalSlotCount)")
                            .font(.subheadline.bold())
                            .foregroundColor(filledSlotCount == totalSlotCount ? VaultTheme.Colors.success : VaultTheme.Colors.primary)
                        
                        if filledSlotCount == totalSlotCount && totalSlotCount > 0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(VaultTheme.Colors.success)
                                .font(.caption)
                        }
                    }
                }
                
                Spacer()
                
                // SELECT ALL button
                PhotosPicker(
                    selection: $bulkSelectedItems,
                    maxSelectionCount: totalSlotCount,
                    matching: .images
                ) {
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "photo.stack")
                        Text("Select All")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    .padding(.vertical, VaultTheme.Spacing.md)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
                .disabled(isLoadingBulk)
                
                // CLEAR ALL button (if any photos loaded)
                if filledSlotCount > 0 {
                    Button(action: {
                        withAnimation { slotPhotos.removeAll() }
                    }) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(VaultTheme.Colors.error)
                            .padding(VaultTheme.Spacing.md)
                            .background(VaultTheme.Colors.error.opacity(0.1))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                    }
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            
            // Auto-detection hint
            Text(autoDetectHintText)
                .font(.caption)
                .foregroundColor(VaultTheme.Colors.info)
                .padding(VaultTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaultTheme.Colors.info.opacity(0.1))
                .cornerRadius(VaultTheme.CornerRadius.sm)
                .padding(.horizontal, VaultTheme.Spacing.lg)
            
            // Loading indicator for bulk
            if isLoadingBulk {
                HStack(spacing: VaultTheme.Spacing.md) {
                    ProgressView()
                        .tint(VaultTheme.Colors.primary)
                    Text("Optimizing photos... \(bulkLoadProgress.current)/\(bulkLoadProgress.total)")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .padding(VaultTheme.Spacing.md)
                .background(VaultTheme.Colors.primary.opacity(0.1))
                .cornerRadius(VaultTheme.CornerRadius.sm)
                .padding(.horizontal, VaultTheme.Spacing.lg)
            }
            
            // THE GRID
            let labels = currentSlotLabels
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: VaultTheme.Spacing.sm)], spacing: VaultTheme.Spacing.sm) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if let photo = slotPhotos[label] {
                        // FILLED SLOT
                        filledSlotCell(photo: photo, label: label)
                    } else if processingSlotSymbol == label {
                        // PROCESSING SLOT
                        processingSlotCell(label: label)
                    } else {
                        // EMPTY SLOT
                        emptySlotCell(label: label)
                    }
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
        }
    }
    
    // MARK: - Filled Slot Cell
    
    private func filledSlotCell(photo: SlotPhoto, label: String) -> some View {
        ZStack {
            if let thumb = photo.thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipped()
                    .cornerRadius(VaultTheme.CornerRadius.sm)
            } else {
                Rectangle()
                    .fill(VaultTheme.Colors.cardBorder)
                    .frame(width: 90, height: 90)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
            }
            
            // Symbol badge (top-left)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(VaultTheme.Colors.success))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -2, y: -2)
            
            // Delete button (top-right)
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    _ = slotPhotos.removeValue(forKey: label)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 4, y: -4)
        }
        .frame(width: 90, height: 90)
        .contentShape(Rectangle())
        // Long-press to replace
        .contextMenu {
            Button {
                targetSlotSymbol = label
                // Picker will be triggered via the overlay approach
            } label: {
                Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Button(role: .destructive) {
                withAnimation { _ = slotPhotos.removeValue(forKey: label) }
            } label: {
                Label("Remove Photo", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Processing Slot Cell
    
    private func processingSlotCell(label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                .fill(VaultTheme.Colors.primary.opacity(0.1))
                .frame(width: 90, height: 90)
            
            VStack(spacing: VaultTheme.Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(VaultTheme.Colors.primary)
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(VaultTheme.Colors.primary)
            }
        }
        .frame(width: 90, height: 90)
    }
    
    // MARK: - Empty Slot Cell
    
    private func emptySlotCell(label: String) -> some View {
        PhotosPicker(
            selection: Binding(
                get: { slotPickerItem },
                set: { newItem in
                    targetSlotSymbol = label
                    slotPickerItem = newItem
                }
            ),
            matching: .images
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .foregroundColor(VaultTheme.Colors.primary.opacity(0.3))
                    .frame(width: 90, height: 90)
                    .background(
                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                            .fill(VaultTheme.Colors.primary.opacity(0.05))
                    )
                
                VStack(spacing: VaultTheme.Spacing.xs) {
                    Text(label)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VaultTheme.Colors.primary.opacity(0.6))
                    
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(VaultTheme.Colors.primary.opacity(0.5))
                }
            }
        }
        .frame(width: 90, height: 90)
    }
    
    // MARK: - Custom Photo Picker Section
    
    private var customPhotoPickerSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            VaultCard {
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                    Text("Select Photos")
                        .font(.headline)
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    
                    PhotosPicker(
                        selection: $bulkSelectedItems,
                        maxSelectionCount: 100,
                        matching: .images
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundColor(VaultTheme.Colors.primary)
                            
                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                Text("Tap to select photos")
                                    .font(.subheadline.bold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("Select your images")
                                    .font(.caption)
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        .padding(VaultTheme.Spacing.lg)
                        .background(VaultTheme.Colors.primary.opacity(0.1))
                        .cornerRadius(VaultTheme.CornerRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                                .stroke(VaultTheme.Colors.primary, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            
            if isLoadingBulk {
                HStack(spacing: VaultTheme.Spacing.md) {
                    ProgressView()
                        .tint(VaultTheme.Colors.primary)
                    Text("Optimizing photos and creating set...")
                        .font(.subheadline)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .padding(.horizontal, VaultTheme.Spacing.lg)
            }
        }
    }
    
    // MARK: - Auto-Detect Hint Text
    
    private var autoDetectHintText: String {
        switch selectedType {
        case .number:
            return "Tip: If your files are named 0.jpg, 1.jpg, ... 9.jpg they will be auto-placed. Otherwise, tap each slot individually."
        case .word:
            let first = selectedAlphabet.characters.first ?? "A"
            let second = selectedAlphabet.characters.count > 1 ? selectedAlphabet.characters[1] : "B"
            return "Tip: Files named \(first.lowercased()).jpg, \(second.lowercased()).jpg, ... will be auto-placed. Or tap each slot."
        case .custom:
            return ""
        }
    }
    
    // MARK: - Load Single Slot Photo
    
    private func loadSingleSlotPhoto(item: PhotosPickerItem, symbol: String) {
        processingSlotSymbol = symbol
        
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    processingSlotSymbol = nil
                    slotPickerItem = nil
                    targetSlotSymbol = nil
                }
                return
            }
            
            // Compression pipeline
            let validData = InstagramService.adjustImageAspectRatio(imageData: data)
            let optimizedData = InstagramService.compressImageForUpload(imageData: validData, photoIndex: 0)
            
            let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
            
            let photo = SlotPhoto(
                symbol: symbol,
                filename: filename,
                imageData: optimizedData
            )
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) {
                    slotPhotos[symbol] = photo
                }
                processingSlotSymbol = nil
                slotPickerItem = nil
                targetSlotSymbol = nil
            }
        }
    }
    
    // MARK: - Load Bulk Photos Into Slots (Number/Word)
    
    private func loadBulkPhotosIntoSlots(items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        isLoadingBulk = true
        bulkLoadProgress = (0, items.count)
        
        Task {
            var loaded: [(filename: String, imageData: Data)] = []
            
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let validData = InstagramService.adjustImageAspectRatio(imageData: data)
                    let optimizedData = InstagramService.compressImageForUpload(imageData: validData, photoIndex: index)
                    let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
                    loaded.append((filename: filename, imageData: optimizedData))
                }
                
                await MainActor.run {
                    bulkLoadProgress = (index + 1, items.count)
                }
            }
            
            // Auto-detect and place into slots
            let labels = currentSlotLabels
            var newSlots: [String: SlotPhoto] = [:]
            var usedPhotoIndices = Set<Int>()
            
            // Pass 1: Match by filename
            for (idx, item) in loaded.enumerated() {
                let detected = detectSymbolFromFilename(item.filename)
                if let detected = detected, labels.contains(detected), newSlots[detected] == nil {
                    newSlots[detected] = SlotPhoto(
                        symbol: detected,
                        filename: item.filename,
                        imageData: item.imageData
                    )
                    usedPhotoIndices.insert(idx)
                }
            }
            
            // Pass 2: Fill remaining slots in order with unmatched photos
            var unmatchedPhotos = loaded.enumerated().filter { !usedPhotoIndices.contains($0.offset) }
            for label in labels {
                if newSlots[label] == nil, let next = unmatchedPhotos.first {
                    newSlots[label] = SlotPhoto(
                        symbol: label,
                        filename: next.element.filename,
                        imageData: next.element.imageData
                    )
                    unmatchedPhotos.removeFirst()
                }
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) {
                    slotPhotos = newSlots
                }
                isLoadingBulk = false
                bulkSelectedItems = []
            }
        }
    }
    
    // MARK: - Symbol Detection from Filename (for bulk)
    
    private func detectSymbolFromFilename(_ filename: String) -> String? {
        let name = (filename as NSString).lastPathComponent
        let baseName = name
            .replacingOccurrences(of: ".jpg", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".jpeg", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".heic", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".webp", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        
        switch selectedType {
        case .number:
            if let num = Int(baseName), num >= 0, num <= 9 {
                return "\(num)"
            }
            return nil
            
        case .word:
            let chars = selectedAlphabet.characters
            if baseName.count == 1 {
                for char in chars {
                    if char.lowercased() == baseName.lowercased() {
                        return char
                    }
                }
            }
            return nil
            
        case .custom:
            return nil
        }
    }
    
    // MARK: - Load Custom Photos & Create Set
    
    private func loadCustomPhotosAndCreate(items: [PhotosPickerItem]) {
        guard !items.isEmpty, !setName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isLoadingBulk = true
        
        Task {
            var photos: [(symbol: String, filename: String, imageData: Data)] = []
            
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let validData = InstagramService.adjustImageAspectRatio(imageData: data)
                    let optimizedData = InstagramService.compressImageForUpload(imageData: validData, photoIndex: index)
                    let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
                    let symbol = filename.replacingOccurrences(of: ".jpg", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: ".jpeg", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: ".heic", with: "", options: .caseInsensitive)
                    photos.append((symbol: symbol, filename: filename, imageData: optimizedData))
                }
            }
            
            if !photos.isEmpty {
                await MainActor.run {
                    let newSet = dataManager.createSet(
                        name: setName,
                        type: .custom,
                        bankCount: 1,
                        photos: photos
                    )
                    isLoadingBulk = false
                    onSetCreated?(newSet)
                    isPresented = false
                }
            } else {
                await MainActor.run {
                    isLoadingBulk = false
                }
            }
        }
    }
    
    // MARK: - Handle Create Set Button
    
    private func handleCreateSet() {
        let labels = currentSlotLabels
        let missing = labels.filter { slotPhotos[$0] == nil }
        
        if !missing.isEmpty {
            showIncompleteAlert = true
        } else {
            finalizeSetCreation()
        }
    }
    
    // MARK: - Finalize Set Creation
    
    private func finalizeSetCreation() {
        isCreatingSet = true
        
        let labels = currentSlotLabels
        var photos: [(symbol: String, filename: String, imageData: Data)] = []
        
        // Build photos array in slot order
        for label in labels {
            if let photo = slotPhotos[label] {
                photos.append((symbol: photo.symbol, filename: photo.filename, imageData: photo.imageData))
            }
        }
        
        guard !photos.isEmpty else {
            isCreatingSet = false
            return
        }
        
        let alphabet: AlphabetType? = selectedType == .word ? selectedAlphabet : nil
        
        let newSet = dataManager.createSet(
            name: setName,
            type: selectedType,
            bankCount: bankCount,
            photos: photos,
            selectedAlphabet: alphabet
        )
        
        isCreatingSet = false
        onSetCreated?(newSet)
        isPresented = false
    }
}
