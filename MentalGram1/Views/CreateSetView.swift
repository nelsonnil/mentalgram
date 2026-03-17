import SwiftUI
import PhotosUI

// MARK: - Create Set View
// Simple 1-step form: name + type + alphabet (word only) + bank count → creates empty set.
// Photos are loaded afterwards in SetDetailView by tapping each slot or using Select All.

struct CreateSetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager = DataManager.shared
    var onSetCreated: ((PhotoSet) -> Void)? = nil

    @State private var setName = ""
    @State private var selectedType: SetType = .word
    @State private var bankCount = 1
    @State private var selectedAlphabet: AlphabetType = .latin
    @State private var isCreating = false

    private var canCreate: Bool {
        !setName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: VaultTheme.Spacing.xl) {
                    // Set Name
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Set Name")
                            .font(.headline)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        TextField("Enter set name", text: $setName)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                    }

                    // Type
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

                    // Alphabet (word only)
                    if selectedType == .word {
                        HStack {
                            Text("Alphabet")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(AlphabetType.allCases, id: \.self) { alphabet in
                                    Button(action: { selectedAlphabet = alphabet }) {
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
                    }

                    // Bank count (word/number only)
                    if selectedType != .custom {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Number of Banks")
                                .font(.headline)
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Stepper(value: $bankCount, in: 1...20) {
                                Text("\(bankCount) bank\(bankCount == 1 ? "" : "s")")
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .tint(VaultTheme.Colors.primary)
                            Text("You can add or remove banks later from the set view.")
                                .font(.caption)
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }

                    Spacer(minLength: VaultTheme.Spacing.xl)

                    // Create button + hint
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
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    private func createSet() {
        guard canCreate else { return }
        isCreating = true
        let alphabet: AlphabetType? = selectedType == .word ? selectedAlphabet : nil
        let count = selectedType == .custom ? 1 : bankCount
        let newSet = dataManager.createSet(
            name: setName.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            bankCount: count,
            photos: [],
            selectedAlphabet: alphabet
        )
        isCreating = false
        onSetCreated?(newSet)
        isPresented = false
    }
}
