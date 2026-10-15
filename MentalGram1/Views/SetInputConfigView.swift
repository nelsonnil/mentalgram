import SwiftUI

// MARK: - Per-Set Input Picker
//
// Shown inside each set card (SetRowView). Lets the magician pick the single
// input method for that set, restricted to the methods allowed for its type.
// Configuration opens from the card's Configure button.

struct SetInputPicker: View {
    let set: PhotoSet

    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var integrations = IntegrationsSettings.shared

    private var allowed: [InputMethod] { InputMethod.allowed(for: set.type) }

    /// Always read the freshest copy from DataManager so the highlight updates.
    private var selected: InputMethod {
        (dataManager.sets.first { $0.id == set.id } ?? set).resolvedInputMethod
    }

    /// Short label shown next to the chips so the magician can tell which
    /// concrete source is configured without opening the config sheet.
    /// Currently shows the selected API source (e.g. "Inject" or a renamed API).
    private var selectionDetail: String? {
        switch selected {
        case .api:
            return integrations.ppApiSource == .none ? nil : integrations.ppApiSource.displayName
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let detail = selectionDetail {
                HStack {
                    Spacer(minLength: 8)
                    Text(detail)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selected.chipColor)
                        .lineLimit(1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allowed) { method in
                        inputTile(for: method)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func inputTile(for method: InputMethod) -> some View {
        let isSelected = selected == method
        let color = method.chipColor
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                dataManager.setInputMethod(method, for: set.id)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: method.icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(method.chipTitle)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(isSelected ? .white : color.opacity(0.95))
            .frame(width: 76, height: 76)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [color, color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        color.opacity(0.14)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.white.opacity(0.22) : color.opacity(0.35), lineWidth: isSelected ? 1.5 : 1)
            )
            .cornerRadius(14)
            .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(method.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Input Config Sheet
//
// Edits the globally-shared configuration for the chosen input. Only one
// configuration exists per input type (shared across all sets that use it).

struct SetInputConfigSheet: View {
    let method: InputMethod
    let set: PhotoSet
    let accent: Color

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
                    header
                    switch method {
                    case .coverTyping: CoverTypingConfig()
                    case .api:         ApiInputConfig(accent: accent)
                    case .ocr:         OCRInputConfig(accent: accent)
                    case .lockscreen:  LockscreenConfig(accent: accent)
                    case .digitGrid:   DigitGridConfig()
                    case .clockInput:  ClockInputConfig()
                    case .cardClock:   CardClockConfig()
                    case .numpadCard:  NumpadCardConfig()
                    case .listInput:   ListInputConfig()
                    case .fakeNotes:   FakeNotesInputConfig()
                    case .urlScheme:   SetURLSchemeConfigContent(set: set, accent: accent)
                    }
                }
                .padding(VaultTheme.Spacing.lg)
            }
            .background(VaultTheme.Colors.background.ignoresSafeArea())
            .navigationTitle(method.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.done")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: method.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(accent)
                .cornerRadius(12)
            VStack(alignment: .leading, spacing: 2) {
                Text(method.title)
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text(method.shortDescription)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
        }
    }
}

// MARK: - URL Scheme config (per set)

struct SetURLSchemeConfigContent: View {
    let set: PhotoSet
    let accent: Color
    @State private var copied = false

    private var urlScheme: String {
        guard let mode = set.type.revealURLTemplate else { return "" }
        let setParam = "&set=\(set.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? set.name)"
        switch set.type {
        case .word:           return "vault://reveal?\(mode)=<word>\(setParam)"
        case .number:         return "vault://reveal?\(mode)=1\(setParam)"
        case .custom, .list:  return "vault://reveal?\(mode)=<1-100>\(setParam)"
        case .card:           return "vault://reveal?\(mode)=3D\(setParam)"
        }
    }

    private var helperText: String {
        switch set.type {
        case .word:
            return "Replace <word> with the word to reveal. Example: vault://reveal?word=MAGIC&set=\(set.name)"
        case .number:
            return "Put the number after word=. Example: vault://reveal?word=7&set=\(set.name)"
        case .custom, .list:
            return "Put the slot number after slot=. Example: vault://reveal?slot=15&set=\(set.name)"
        case .card:
            return "Use value + suit after card=. Example: vault://reveal?card=3D&set=\(set.name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(urlScheme)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)

            Text(helperText)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = urlScheme
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                    Text(copied ? "Copied" : "Copy URL")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(copied ? VaultTheme.Colors.success : accent)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ListInputConfig: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("List Input opens a private full-screen list when Performance starts. Tap one item to close the list and reveal its linked media on the fake Instagram profile.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NumpadCardConfig: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Label("set.input.numpadcard.help", systemImage: "rectangle.grid.3x2.fill")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("set.input.numpadcard.noconfig", systemImage: "checkmark.seal")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.success)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FakeNotesInputConfig: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("Notes Input opens a fake iOS Notes interface when Performance starts. The spectator types their selection and confirms by placing the phone face-down. The typed word is used to reveal the matching image.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Cover Typing config (mask mode + username)

private struct CoverTypingConfig: View {
    @ObservedObject private var secret = SecretInputSettings.shared
    @State private var isCachingResults = false
    @State private var cachedCount: Int = 0

    private var preview: String {
        let word = "car"
        let mask = secret.mode == .customUsername ? secret.customUsername.lowercased() : "user"
        guard !mask.isEmpty else { return "user" }
        var result = ""
        for i in 0..<word.count {
            let idx = mask.index(mask.startIndex, offsetBy: i % mask.count)
            result.append(mask[idx])
        }
        return result
    }

    private func triggerPrefetch() {
        let username = secret.customUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return }
        isCachingResults = true
        Task {
            let count = await VisitedProfileCacheService.shared.prefetchAndCacheMaskResults(username: username)
            await MainActor.run {
                cachedCount = count
                isCachingResults = false
            }
        }
    }

    private func refreshCachedCount() {
        let username = secret.customUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedCount = VisitedProfileCacheService.shared.maskSearchResultsCount(forUsername: username)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("set.input.covertyping.help")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            Text("set.input.covertyping.maskmode")
                .font(VaultTheme.Typography.bodyBold())
                .foregroundColor(VaultTheme.Colors.textPrimary)

            ForEach(MaskInputMode.allCases, id: \.self) { mode in
                let selected = secret.mode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { secret.mode = mode }
                } label: {
                    HStack(spacing: VaultTheme.Spacing.md) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected ? VaultTheme.Colors.primary : VaultTheme.Colors.textSecondary)
                        Text(mode.displayName)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if secret.mode == .customUsername {
                HStack(spacing: 8) {
                    TextField("Custom username", text: $secret.customUsername)
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                        .padding(VaultTheme.Spacing.md)
                        .background(Color(hex: "#2C2C2E"))
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { triggerPrefetch() }
                        .onChange(of: secret.customUsername) { _ in refreshCachedCount() }

                    Button(action: { triggerPrefetch() }) {
                        Group {
                            if isCachingResults {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(cachedCount > 0 ? VaultTheme.Colors.primary : .gray)
                            }
                        }
                    }
                    .disabled(isCachingResults || secret.customUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Estado del caché
                if isCachingResults {
                    Label("Guardando perfiles…", systemImage: "ellipsis.circle")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                } else if cachedCount > 0 {
                    Label("\(cachedCount) perfiles guardados", systemImage: "checkmark.circle.fill")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(.green)
                } else if !secret.customUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Sin caché — pulsa ↺ para guardar", systemImage: "exclamationmark.circle")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(.orange)
                }
            }

            HStack(spacing: 4) {
                Text("Preview:")
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(VaultTheme.Colors.textTertiary)
                Text("\"car\" → \"\(preview)\"")
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(VaultTheme.Colors.primary)
            }
        }
        .onAppear { refreshCachedCount() }
    }
}

// MARK: - API config (source picker)

private struct ApiInputConfig: View {
    let accent: Color
    @ObservedObject private var integrations = IntegrationsSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("set.input.api.help")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            Text("set.input.api.source")
                .font(VaultTheme.Typography.bodyBold())
                .foregroundColor(VaultTheme.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ApiSource.allCases.filter { $0 != .none && !$0.isInterfaceInput }, id: \.rawValue) { src in
                    let isActive = integrations.ppApiSource == src
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            integrations.ppApiSource = isActive ? .none : src
                        }
                    } label: {
                        Text(src.displayName.replacingOccurrences(of: "Custom API ", with: "API "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isActive ? .white : VaultTheme.Colors.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(isActive ? accent : Color(hex: "#2C2C2E"))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Label("set.input.api.endpoint_hint", systemImage: "info.circle")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textTertiary)
        }
    }
}

// MARK: - OCR config (camera + language)

private struct OCRInputConfig: View {
    let accent: Color
    @AppStorage("ocr_language") private var ocrLanguage: String = "es-ES"
    @AppStorage("ocr_camera")   private var ocrCamera:   Int    = 0

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("set.input.ocr.help")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            Text("set.input.ocr.camera")
                .font(VaultTheme.Typography.captionSmall())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: 6) {
                ForEach([0, 1], id: \.self) { val in
                    let sel = ocrCamera == val
                    Button { ocrCamera = val } label: {
                        HStack(spacing: 5) {
                            Image(systemName: val == 0 ? "camera.fill" : "camera.rotate.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(val == 0 ? "Rear" as LocalizedStringKey : "Front")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(sel ? .white : VaultTheme.Colors.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(sel ? accent : Color(hex: "#2C2C2E"))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("set.input.ocr.language")
                .font(VaultTheme.Typography.captionSmall())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .textCase(.uppercase)
            Menu {
                ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                    Button { ocrLanguage = lang.code } label: {
                        if ocrLanguage == lang.code {
                            Label(lang.display, systemImage: "checkmark")
                        } else {
                            Text(lang.display)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "globe").font(.system(size: 12))
                    Text(OCRConfiguration.displayName(for: ocrLanguage))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                }
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(hex: "#2C2C2E"))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Lockscreen config (wallpaper)

private struct LockscreenConfig: View {
    let accent: Color
    @ObservedObject private var settings = LockscreenInputSettings.shared
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text("set.input.lockscreen.help")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            if let img = settings.wallpaperImage {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Button { showingPicker = true } label: {
                            Label(String(localized: "action.change"), systemImage: "photo.on.rectangle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(accent)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        Button {
                            settings.clearWallpaper()
                            settings.isEnabled = false
                        } label: {
                            Label(String(localized: "action.remove"), systemImage: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(VaultTheme.Colors.error)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            } else {
                Button { showingPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 16))
                        Text("settings.lockscreen.choose_wallpaper")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accent)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingPicker) {
            HomeScreenImagePicker { image in
                settings.saveWallpaper(image)
                // Per-set selection drives on/off; enable the wallpaper-ready flag
                // so isReady passes once an image exists.
                settings.isEnabled = true
            }
        }
    }
}

// MARK: - Digit Grid (no config)

private struct DigitGridConfig: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Label("set.input.digitgrid.help", systemImage: "hand.draw")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            Label("set.input.digitgrid.noconfig", systemImage: "checkmark.seal")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Clock Input (no config)

private struct ClockInputConfig: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Label("set.input.clockinput.help", systemImage: "hand.draw.fill")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            Label("set.input.clockinput.noconfig", systemImage: "checkmark.seal")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Card Clock (no config)

private struct CardClockConfig: View {
    private let accent = Color(hex: "16A34A")   // card-set green

    private let valueTable: [(String, String)] = [
        ("A",  "↑→"), ("2",  "→↑"), ("3",  "→→"), ("4",  "→↓"),
        ("5",  "↓→"), ("6",  "↓↓"), ("7",  "↓←"), ("8",  "←↓"),
        ("9",  "←←"), ("10", "←↑"), ("J",  "↑←"), ("Q",  "↑↑"),
        ("K",  "↑↓"),
    ]
    private let suitTable: [(String, String)] = [
        ("♠", "↑"), ("♥", "→"), ("♣", "↓"), ("♦", "←"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {

            Label("set.input.cardclock.help", systemImage: "clock.fill")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            // Value table
            VStack(alignment: .leading, spacing: 6) {
                Text("set.input.cardclock.values")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                          spacing: 6) {
                    ForEach(valueTable, id: \.0) { face, swipes in
                        HStack(spacing: 3) {
                            Text(face)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accent)
                            Text(swipes)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(10)
            .background(VaultTheme.Colors.backgroundSecondary)
            .cornerRadius(VaultTheme.CornerRadius.sm)

            // Suit table
            VStack(alignment: .leading, spacing: 6) {
                Text("set.input.cardclock.suits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                HStack(spacing: 16) {
                    ForEach(suitTable, id: \.0) { suit, swipes in
                        HStack(spacing: 3) {
                            Text(suit)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(["♥","♦"].contains(suit) ? .red : VaultTheme.Colors.textPrimary)
                            Text(swipes)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(10)
            .background(VaultTheme.Colors.backgroundSecondary)
            .cornerRadius(VaultTheme.CornerRadius.sm)

            Label("set.input.cardclock.longpress", systemImage: "hand.tap.fill")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            Label("set.input.cardclock.noconfig", systemImage: "checkmark.seal")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textTertiary)
        }
    }
}
