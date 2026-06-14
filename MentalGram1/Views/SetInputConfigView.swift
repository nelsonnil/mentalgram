import SwiftUI

// MARK: - Per-Set Input Picker
//
// Shown inside each set card (SetRowView). Lets the magician pick the single
// input method for that set, restricted to the methods allowed for its type.
// Methods that need extra setup show a "Configure" button that opens a sheet
// editing the (globally shared) configuration for that input.

struct SetInputPicker: View {
    let set: PhotoSet

    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @State private var configMethod: InputMethod? = nil

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

    private var configureTitle: String {
        if selected == .api, let detail = selectionDetail {
            return "Configure API: \(detail)"
        }
        return "Configure \(selected.title)"
    }

    private var accent: Color {
        switch set.type {
        case .word:   return Color(hex: "7C3AED")
        case .number: return Color(hex: "FF9500")
        case .custom: return Color(hex: "F97316")
        case .card:   return Color(hex: "16A34A")
        case .list:   return Color(hex: "64D2FF")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textTertiary)
                Text("set.input.label")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if let detail = selectionDetail {
                    Text(detail)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.15))
                        .cornerRadius(5)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(allowed) { method in
                    chip(for: method)
                }
            }

            // Configure button — full-width, shown when selected method has settings
            if selected.needsConfig {
                Button { configMethod = selected } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(configureTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.12))
                    .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $configMethod) { method in
            SetInputConfigSheet(method: method, setType: set.type, accent: accent)
        }
    }

    @ViewBuilder
    private func chip(for method: InputMethod) -> some View {
        let isSelected = selected == method
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                dataManager.setInputMethod(method, for: set.id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: method.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(method.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? accent : Color(hex: "#2C2C2E"))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Input Config Sheet
//
// Edits the globally-shared configuration for the chosen input. Only one
// configuration exists per input type (shared across all sets that use it).

struct SetInputConfigSheet: View {
    let method: InputMethod
    let setType: SetType
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

// MARK: - Cover Typing config (mask mode + username)

private struct CoverTypingConfig: View {
    @ObservedObject private var secret = SecretInputSettings.shared

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
                TextField("Custom username", text: $secret.customUsername)
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(VaultTheme.Spacing.md)
                    .background(Color(hex: "#2C2C2E"))
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
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
