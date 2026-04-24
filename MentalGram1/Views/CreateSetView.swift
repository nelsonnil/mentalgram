import SwiftUI
import PhotosUI

// MARK: - Create Set View

struct CreateSetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager = DataManager.shared
    var onSetCreated: ((PhotoSet) -> Void)? = nil

    @State private var setName = ""
    @State private var selectedType: SetType = .word
    @State private var bankCount = 1
    @State private var selectedAlphabet: AlphabetType = .latin
    @State private var selectedTemplate: LetterTemplate? = nil       // nil = upload own (word)
    @State private var selectedNumberTemplate: NumberTemplate? = nil  // nil = upload own (number)
    @State private var isCreating = false
    @State private var availableTemplates: [LetterTemplate] = []
    @State private var availableNumberTemplates: [NumberTemplate] = []

    private var canCreate: Bool {
        !setName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: VaultTheme.Spacing.xl) {

                    // ── Set Name ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Set Name")
                            .font(.headline)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        TextField("Enter set name", text: $setName)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                    }

                    // ── Type ─────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Type")
                            .font(.headline)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        VStack(spacing: VaultTheme.Spacing.sm) {
                            ForEach(SetType.allCases, id: \.self) { type in
                                Button(action: { selectedType = type }) {
                                    HStack(spacing: VaultTheme.Spacing.md) {
                                        Image(systemName: type.icon)
                                            .font(.title3)
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                            .frame(width: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(type.title)
                                                .font(.subheadline.bold())
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
                                    .padding(VaultTheme.Spacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                            .fill(selectedType == type
                                                  ? VaultTheme.Colors.primary.opacity(0.1)
                                                  : VaultTheme.Colors.cardBorder.opacity(0.4))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                            .stroke(selectedType == type
                                                    ? VaultTheme.Colors.primary
                                                    : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // ── Alphabet (word only) ──────────────────────────────────
                    if selectedType == .word {
                        HStack {
                            Text("Alphabet")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(AlphabetType.allCases, id: \.self) { alphabet in
                                    Button(action: {
                                        selectedAlphabet = alphabet
                                        refreshTemplates(for: alphabet)
                                    }) {
                                        Label(
                                            "\(alphabet.flag) \(alphabet.displayName) (\(alphabet.count) letters)",
                                            systemImage: selectedAlphabet == alphabet ? "checkmark" : ""
                                        )
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedAlphabet.flag)
                                    Text(selectedAlphabet.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(VaultTheme.Colors.cardBorder.opacity(0.5))
                                .cornerRadius(VaultTheme.CornerRadius.sm)
                            }
                        }

                        // ── Template picker (word) ────────────────────────────
                        TemplatePicker(
                            templates: availableTemplates,
                            selectedTemplate: $selectedTemplate
                        )
                    }

                    // ── Number template picker ────────────────────────────────
                    if selectedType == .number {
                        NumberTemplatePicker(
                            templates: availableNumberTemplates,
                            selectedTemplate: $selectedNumberTemplate
                        )
                    }

                    // ── Bank / slot count ─────────────────────────────────────
                    if selectedType == .card {
                        // Card sets are always 52 slots — no configuration needed
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Image(systemName: "suit.spade.fill")
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                            Text("52 fixed slots (A–K × ♠♥♣♦)")
                                .font(.caption)
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        .padding(VaultTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VaultTheme.Colors.cardBorder.opacity(0.3))
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                    } else if selectedType == .custom {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Number of image slots")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Stepper(value: $bankCount, in: 1...100) {
                                Text(bankCount == 1
                                    ? String(localized: "1 slot")
                                    : String(format: String(localized: "%lld slots"), bankCount))
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .tint(VaultTheme.Colors.primary)
                            Text("Each slot holds one image (up to 100). Select with 1–3 grid swipes.")
                                .font(.caption)
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Number of Banks")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Stepper(value: $bankCount, in: 1...20) {
                                Text(bankCount == 1
                                    ? String(localized: "1 bank")
                                    : String(format: String(localized: "%lld banks"), bankCount))
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .tint(VaultTheme.Colors.primary)
                            Text("You can add or remove banks later from the set view.")
                                .font(.caption)
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }

                    Spacer(minLength: VaultTheme.Spacing.xl)

                    // ── Create button ─────────────────────────────────────────
                    VStack(spacing: 6) {
                        ZStack {
                            GradientButton(
                                title: "Create Set",
                                icon: "checkmark.circle.fill",
                                action: createSet,
                                isEnabled: canCreate && !isCreating,
                                style: .success
                            )
                            .disabled(!canCreate || isCreating)
                            if isCreating { ProgressView().tint(.white) }
                        }
                        if setName.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle").font(.caption2)
                                Text("Enter a set name to continue").font(.caption2)
                            }
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }
                }
                .padding(VaultTheme.Spacing.lg)
            }
            .background(VaultTheme.Colors.background)
            .navigationTitle("Create Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(VaultTheme.Colors.primary)
                        .disabled(isCreating)
                }
            }
            .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
            refreshTemplates(for: selectedAlphabet)
            availableNumberTemplates = TemplateManager.shared.numberTemplates()
        }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func refreshTemplates(for alphabet: AlphabetType) {
        availableTemplates = TemplateManager.shared.templates(for: alphabet)
        // Reset selection if current template doesn't belong to the new alphabet
        if let sel = selectedTemplate, sel.alphabet != alphabet {
            selectedTemplate = nil
        }
    }

    private func createSet() {
        guard canCreate else { return }
        isCreating = true

        let alphabet: AlphabetType? = selectedType == .word ? selectedAlphabet : nil
        let count = bankCount

        // Load template photos if one was chosen, otherwise create empty slots
        var templatePhotos: [(symbol: String, filename: String, imageData: Data)] = []
        if selectedType == .word, let template = selectedTemplate {
            templatePhotos = TemplateManager.shared.photos(for: template)
        } else if selectedType == .number, let template = selectedNumberTemplate {
            templatePhotos = TemplateManager.shared.photos(for: template)
        }

        let newSet = dataManager.createSet(
            name: setName.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            bankCount: count,
            photos: templatePhotos,
            selectedAlphabet: alphabet
        )
        isCreating = false
        onSetCreated?(newSet)
        isPresented = false
    }
}

// MARK: - Template Picker

private struct TemplatePicker: View {
    let templates: [LetterTemplate]
    @Binding var selectedTemplate: LetterTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Image Template")
                .font(.headline)
                .foregroundColor(VaultTheme.Colors.textPrimary)

            if templates.isEmpty {
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                    Text("No templates available. You'll upload your own images.")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .padding(VaultTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaultTheme.Colors.cardBackground)
                .cornerRadius(VaultTheme.CornerRadius.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaultTheme.Spacing.md) {

                        // "Upload my own" card
                        TemplateCard(
                            title: String(localized: "Upload my own"),
                            icon: "photo.badge.plus",
                            previewImages: [],
                            isSelected: selectedTemplate == nil,
                            isCustom: true
                        ) {
                            selectedTemplate = nil
                        }

                        // One card per template
                        ForEach(templates) { template in
                            TemplateCardFromDisk(
                                template: template,
                                isSelected: selectedTemplate == template
                            ) {
                                selectedTemplate = template
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Template Card (from disk images)

private struct TemplateCardFromDisk: View {
    let template: LetterTemplate
    let isSelected: Bool
    let onTap: () -> Void

    @State private var previewImages: [UIImage] = []

    var body: some View {
        TemplateCard(
            title: template.name,
            icon: nil,
            previewImages: previewImages,
            isSelected: isSelected,
            isCustom: false,
            onTap: onTap
        )
        .onAppear {
            previewImages = TemplateManager.shared.previewImages(for: template, count: 4)
        }
    }
}

// MARK: - Template Card (generic)

private struct TemplateCard: View {
    let title: String
    let icon: String?
    let previewImages: [UIImage]
    let isSelected: Bool
    let isCustom: Bool
    let onTap: () -> Void

    private let cardSize: CGFloat = 110

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Preview area
                ZStack {
                    RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                        .fill(VaultTheme.Colors.backgroundSecondary)
                        .frame(width: cardSize, height: cardSize)

                    if isCustom {
                        VStack(spacing: 4) {
                            Image(systemName: icon ?? "photo.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            Text("Your photos")
                                .font(.system(size: 9))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    } else if previewImages.isEmpty {
                        ProgressView()
                            .tint(VaultTheme.Colors.textTertiary)
                    } else {
                        // 2×2 grid of letter previews
                        let cols = min(previewImages.count, 2)
                        let rows = previewImages.count > 2 ? 2 : 1
                        let cellSize = (cardSize - 4) / 2

                        VStack(spacing: 2) {
                            ForEach(0..<rows, id: \.self) { row in
                                HStack(spacing: 2) {
                                    ForEach(0..<cols, id: \.self) { col in
                                        let idx = row * cols + col
                                        if idx < previewImages.count {
                                            Image(uiImage: previewImages[idx])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: cellSize, height: cellSize)
                                                .clipped()
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: cardSize, height: cardSize)
                        .clipShape(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm))
                    }

                    // Selection ring
                    if isSelected {
                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                            .stroke(VaultTheme.Colors.primary, lineWidth: 2.5)
                            .frame(width: cardSize, height: cardSize)
                    }
                }

                // Template name
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: cardSize)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Number Template Picker

private struct NumberTemplatePicker: View {
    let templates: [NumberTemplate]
    @Binding var selectedTemplate: NumberTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Image Template")
                .font(.headline)
                .foregroundColor(VaultTheme.Colors.textPrimary)

            if templates.isEmpty {
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                    Text("No templates available. You'll upload your own images.")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .padding(VaultTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaultTheme.Colors.cardBackground)
                .cornerRadius(VaultTheme.CornerRadius.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaultTheme.Spacing.md) {

                        // "Upload my own" card
                        TemplateCard(
                            title: String(localized: "Upload my own"),
                            icon: "photo.badge.plus",
                            previewImages: [],
                            isSelected: selectedTemplate == nil,
                            isCustom: true
                        ) {
                            selectedTemplate = nil
                        }

                        // One card per number template
                        ForEach(templates) { template in
                            NumberTemplateCardFromDisk(
                                template: template,
                                isSelected: selectedTemplate == template
                            ) {
                                selectedTemplate = template
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Number Template Card (from disk images)

private struct NumberTemplateCardFromDisk: View {
    let template: NumberTemplate
    let isSelected: Bool
    let onTap: () -> Void

    @State private var previewImages: [UIImage] = []

    var body: some View {
        TemplateCard(
            title: template.name,
            icon: nil,
            previewImages: previewImages,
            isSelected: isSelected,
            isCustom: false,
            onTap: onTap
        )
        .onAppear {
            previewImages = TemplateManager.shared.previewImages(for: template, count: 4)
        }
    }
}
