import SwiftUI

// MARK: - Shared helpers

private struct IPHSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content()
        }
    }
}

private struct IPHBullet: View {
    let icon: String
    let iconColor: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Acrostic live example: generates output in the device language and
// highlights the first letter of each word in pink.
private struct AcrosticExampleBullet: View {
    private let accentColor = Color(hex: "F472B6")

    private var exampleWord: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "es": return "VASO"
        case "fr": return "REVE"
        case "de": return "LICHT"
        case "it": return "MARE"
        case "pt": return "ALMA"
        case "nl": return "LICHT"
        case "pl": return "NURT"
        case "ru": return "ДУША"
        case "hi": return "JAL"
        case "th": return "FAH"
        case "vi": return "SONG"
        default:   return "STAR"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.badge.star")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(accentColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                let pairs = AcrosticEngine.preview(word: exampleWord)

                // Intro line
                (Text("Example — word received: ")
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                + Text(exampleWord)
                    .foregroundColor(accentColor)
                    .bold())
                .font(VaultTheme.Typography.body())

                // Poem lines with highlighted first letter
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pairs.indices, id: \.self) { i in
                        let word = pairs[i].word
                        let first = String(word.prefix(1))
                        let rest  = String(word.dropFirst())
                        (Text(first)
                            .foregroundColor(accentColor)
                            .bold()
                        + Text(rest)
                            .foregroundColor(VaultTheme.Colors.textSecondary))
                        .font(VaultTheme.Typography.body())
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(VaultTheme.Colors.textSecondary.opacity(0.07))
                .cornerRadius(8)

                Text("The first letter of each line spells out the spectator's word — a powerful revelation that fills the entire bio.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct IPHMethodPill: View {
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(20)
    }
}

private struct IPHOCRBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "A78BFA"))
                Text("What is OCR?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            Text("OCR (Optical Character Recognition) is a technology that reads text from an image or live camera. The app uses the camera to recognise a word a spectator wrote or chose, without any manual input from the magician.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "A78BFA"))
                Text("Point camera → text is detected → prediction triggers automatically")
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color(hex: "A78BFA").opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "A78BFA").opacity(0.25), lineWidth: 1)
        )
    }
}

private struct IPHRealVsFakeBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text("Fake app vs. real Instagram")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }

            Text("The app's fake profile shows the prediction **instantly** — but this is only a local preview. It is not yet live on real Instagram.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            IPHOrangeRingConfirmationDemo()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "FF9F0A"))
                    .padding(.top, 1)
                Text("When the update is confirmed on **real Instagram**, the app gives two strong vibrations and the profile picture shows a blinking orange ring. For Notes and Biography, this is the confirmation that the text is live on Instagram — not just visible in the fake profile.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "30D158"))
                    .padding(.top, 1)
                Text("**After the vibration**, open the real Instagram profile yourself first — this loads the content in the feed. If the spectator looks before you do, they may need to scroll down to see it.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(hex: "FF9F0A").opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "FF9F0A").opacity(0.3), lineWidth: 1)
        )
    }
}

private struct IPHOrangeRingConfirmationDemo: View {
    @State private var blink = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.99, green: 0.78, blue: 0.12),
                                Color(red: 0.99, green: 0.42, blue: 0.13),
                                Color(red: 0.90, green: 0.14, blue: 0.49),
                                Color(red: 0.99, green: 0.78, blue: 0.12)
                            ],
                            center: .center
                        ),
                        lineWidth: blink ? 4 : 2
                    )
                    .frame(width: blink ? 48 : 42, height: blink ? 48 : 42)
                    .opacity(blink ? 1.0 : 0.45)
                Circle()
                    .fill(VaultTheme.Colors.backgroundSecondary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    )
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Real Instagram confirmed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text("Double vibration + orange ring = safe to show the spectator.")
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(hex: "FF9F0A").opacity(0.10))
        .cornerRadius(10)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }
}

private var iphDivider: some View {
    Rectangle()
        .fill(Color(hex: "#2C2C2E"))
        .frame(height: 1)
        .padding(.vertical, 4)
}

private func iphTopBar(title: LocalizedStringKey, subtitle: LocalizedStringKey, onClose: @escaping () -> Void) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(VaultTheme.Typography.titleSmall())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text(subtitle)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
        }
        Spacer()
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(VaultTheme.Colors.backgroundSecondary)
                .clipShape(Circle())
        }
    }
    .padding(.horizontal, VaultTheme.Spacing.lg)
}

// MARK: - Profile Picture Help View

struct ProfilePictureHelpView: View {
    let onClose: () -> Void
    private let accent = Color(hex: "0A84FF")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    Group {
                        IPHSection(icon: "wand.and.stars", iconColor: accent, title: "What it does") {
                            whatItDoes
                        }
                        iphDivider
                        IPHSection(icon: "square.and.arrow.up", iconColor: VaultTheme.Colors.success, title: "Input methods") {
                            inputMethods
                        }
                        iphDivider
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the Show") {
                            duringShow
                        }
                        iphDivider
                        IPHSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "Tips") {
                            tips
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            iphTopBar(title: "Profile Picture", subtitle: "Feature Guide", onClose: onClose)
                .padding(.top, VaultTheme.Spacing.md)
                .background(VaultTheme.Colors.background.opacity(0.95))
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(accent)
            }
            Text("Profile Picture Prediction")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Change your Instagram profile photo automatically to match the spectator's prediction.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VaultTheme.Spacing.lg)
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "The app uploads a chosen photo as your Instagram profile picture at the exact moment of the reveal.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "The spectator sees your profile photo change live — the image matches what they predicted.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "Can be triggered automatically when entering Performance, or manually.")
        }
    }

    private var inputMethods: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IPHMethodPill(label: "URL Scheme", color: accent)
                IPHMethodPill(label: "Last gallery photo", color: VaultTheme.Colors.success)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("URL Scheme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Use vault://profilepic from any shortcut or automation tool (e.g. Apple Shortcuts) to trigger an upload when Performance opens.")
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Ideal for pre-show automation: build a Shortcut that runs the URL and the photo changes before you even walk on stage.")
            }

            iphDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("Last gallery photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "photo.on.rectangle", iconColor: VaultTheme.Colors.success,
                          text: "Enable \"Auto on Performance open\" to automatically upload the most recent photo in your camera roll every time you enter Performance.")
                IPHBullet(icon: "photo.on.rectangle", iconColor: VaultTheme.Colors.success,
                          text: "Take the prediction photo before the show, then open Performance — it uploads instantly without any extra steps.")
            }
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPHBullet(icon: "1.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Prepare the prediction photo in your camera roll before the performance.")
            IPHBullet(icon: "2.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Enable \"Auto on Performance open\" or have a URL Scheme shortcut ready.")
            IPHBullet(icon: "3.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Open the Performance tab — the photo uploads automatically and appears in the fake profile instantly.")
            IPHBullet(icon: "4.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Wait for the double vibration and the orange ring around your profile picture. That means the new image is live on real Instagram, then open your own Instagram profile before showing the spectator.")
            IPHRealVsFakeBox()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use a 1:1 square photo for best results on the circular Instagram profile picture crop.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "A 30-second cooldown prevents accidental re-uploads during the same performance.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Combine with a URL Scheme from Apple Shortcuts for a completely hands-free reveal.")
        }
    }
}

// MARK: - Note Help View

struct NoteHelpView: View {
    let onClose: () -> Void
    private let accent = Color(hex: "30D158")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    Group {
                        IPHSection(icon: "wand.and.stars", iconColor: accent, title: "What it does") {
                            whatItDoes
                        }
                        iphDivider
                        IPHSection(icon: "square.and.arrow.up", iconColor: Color(hex: "0A84FF"), title: "Input methods") {
                            inputMethods
                        }
                        iphDivider
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the Show") {
                            duringShow
                        }
                        iphDivider
                        IPHSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "Tips") {
                            tips
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            iphTopBar(title: "Note", subtitle: "Feature Guide", onClose: onClose)
                .padding(.top, VaultTheme.Spacing.md)
                .background(VaultTheme.Colors.background.opacity(0.95))
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 38))
                    .foregroundColor(accent)
            }
            Text("Note Prediction")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Post a note on your Instagram profile that matches what the spectator predicted — visible above your profile picture for 24 hours.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VaultTheme.Spacing.lg)
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "The app posts a note on your Instagram account that matches what the spectator said or wrote.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "The note appears above your profile picture in the Instagram Stories bar — only your followers can see it.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "Notes disappear automatically after 24 hours, leaving no permanent trace.")
        }
    }

    private var inputMethods: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Pills row — all available input methods
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                IPHMethodPill(label: "API", color: Color(hex: "0A84FF"))
                IPHMethodPill(label: "URL Scheme", color: accent)
                IPHMethodPill(label: "OCR", color: Color(hex: "A78BFA"))
                IPHMethodPill(label: "Number Lockscreen", color: Color(hex: "FF453A"))
                IPHMethodPill(label: "Card Lockscreen", color: Color(hex: "FF453A"))
                IPHMethodPill(label: "Number Clock", color: Color(hex: "FF9F0A"))
                IPHMethodPill(label: "Card Clock", color: Color(hex: "30D158"))
                IPHMethodPill(label: "Numpad Card", color: Color(hex: "30D158"))
            }

            // API
            VStack(alignment: .leading, spacing: 10) {
                Text("API")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "network", iconColor: Color(hex: "0A84FF"),
                          text: "Open Performance first, then ask the spectator to make their selection in Inject or your custom API. The app polls every 2 s and posts the note automatically when a new value arrives — double vibration plus the orange ring confirms it is live on real Instagram.")
            }

            iphDivider

            // URL Scheme
            VStack(alignment: .leading, spacing: 10) {
                Text("URL Scheme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Trigger the note from any automation app using vault://note?text1=<your text>. Use multiple placeholders for more complex predictions: vault://note?text1=silla&text2=rojo")
            }

            iphDivider

            // OCR
            VStack(alignment: .leading, spacing: 10) {
                Text("OCR — Camera Recognition")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "camera.viewfinder", iconColor: Color(hex: "A78BFA"),
                          text: "Point the camera at a word the spectator wrote or a card they are holding — the app reads the text automatically and sends it as your note, no typing required.")
                IPHOCRBox()
            }

            iphDivider

            // Number Lockscreen
            VStack(alignment: .leading, spacing: 10) {
                Text("Number Lockscreen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "lock.fill", iconColor: Color(hex: "FF453A"),
                          text: "Assign {text1}, {text2}, or {text3} to Number Lockscreen. When you open Performance, the fake lockscreen appears for hidden digit entry. The number you type is substituted into the note template and sent automatically. If a number/custom set is also active, the same number unarchives its slot.")
            }

            iphDivider

            // Card Lockscreen
            VStack(alignment: .leading, spacing: 10) {
                Text("Card Lockscreen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "lock.rectangle.stack.fill", iconColor: Color(hex: "FF453A"),
                          text: "Same fake lockscreen, but the digits you type are a card code (0 + value + suit). The card name in the device language (e.g. \"3 of hearts\") fills the template. If a card set is active, the same card is unarchived.")
            }

            iphDivider

            // Number Clock
            VStack(alignment: .leading, spacing: 10) {
                Text("Number Clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "hand.draw.fill", iconColor: Color(hex: "FF9F0A"),
                          text: "Assign {text1}, {text2}, or {text3} to the Number Clock source. When Performance opens, a black screen appears. Swipe pairs to enter any number of digits (1, 2, 3 or more), then stop swiping for 3 seconds to confirm. The number fills the template and the note is sent. The black screen stays visible until you tap anywhere to show the fake profile.")
            }

            iphDivider

            // Card Clock
            VStack(alignment: .leading, spacing: 10) {
                Text("Card Clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "clock.fill", iconColor: Color(hex: "30D158"),
                          text: "Assign {text1}, {text2}, or {text3} to Card Clock. A black screen appears in Performance (the screen looks off). 2 swipes for value (A=↑→ … 9=←← 10=←↑ J=↑← Q=↑↑ K=↑↓) + 1 swipe for suit (↑=♠ →=♥ ↓=♣ ←=♦). Stop swiping for 3 seconds to confirm. The card name in the device language (e.g. \"3 of hearts\") fills the template. If a card set is active, the same card is unarchived. The black screen stays visible until you tap anywhere to show the fake profile.")
            }

            iphDivider

            // Numpad Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Numpad Card")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "rectangle.grid.3x2.fill", iconColor: Color(hex: "30D158"),
                          text: "Assign {text1}, {text2}, or {text3} to Numpad Card. Performance starts on a completely black screen; tap anywhere to reveal the card pad, select A-10/J/Q/K and the suit, and it closes automatically. The localized card name fills the note template. If a Playing Cards set also uses Numpad Card, the same selection reveals that card.")
            }

            iphDivider

            // Compatibility
            VStack(alignment: .leading, spacing: 10) {
                Text("Compatibility")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                          text: "The SAME interface type can be shared across Set, Biography, and Notes — one capture fills them all at once (e.g. Numpad Card in Bio + Notes + a Playing Cards set).")
                IPHBullet(icon: "exclamationmark.triangle.fill", iconColor: VaultTheme.Colors.warning,
                          text: "DIFFERENT interface types cannot coexist (only one capture happens per performance): OCR, Number Clock, Card Clock, Numpad Card, Number Lockscreen and Card Lockscreen are mutually exclusive. Settings warns you and offers to deactivate the conflicting ones.")
            }
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPHBullet(icon: "1.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Ask the spectator to think of or write a short word (max 60 characters).")
            IPHBullet(icon: "2.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Capture it via OCR, enter it via API/URL Scheme, or use Lockscreen / Number Clock / Card Clock / Numpad Card for covert digit or card entry.")
            IPHBullet(icon: "3.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Open Performance — the note posts automatically (API / URL Scheme / interface input) or tap \"Send Note\". It appears in the fake profile instantly.")
            IPHBullet(icon: "4.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Wait for the double vibration and the orange ring around your profile picture. That means the note is live on real Instagram, then open your own profile before the spectator looks.")
            IPHRealVsFakeBox()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Notes are limited to 60 characters — keep predictions concise (a single word or short phrase works best).")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "A cooldown prevents double-sending. If the button is disabled, wait a few seconds and try again.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use the URL Scheme method with Apple Shortcuts so the note posts the moment you open the app — zero visible interaction.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use the Text Template field to wrap the value in a sentence — e.g. \"My prediction is: {text1}\". Works with any source: API, OCR, Lockscreen, Number Clock, Card Clock, or Numpad Card.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Need two values in one note? Use {text1} and {text2} in your template. They can come from different APIs, or both from the same interface capture (same captured value fills all interface-assigned slots).")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Only one interface type (OCR, Lockscreen, Number Clock, Card Clock, or Numpad Card) can be active per performance. If your Set already uses Numpad Card, Biography and Notes can also use Numpad Card but not a different interface type.")
        }
    }
}

// MARK: - Biography Help View

struct BiographyHelpView: View {
    let onClose: () -> Void
    private let accent = Color(hex: "FF9F0A")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    Group {
                        IPHSection(icon: "wand.and.stars", iconColor: accent, title: "What it does") {
                            whatItDoes
                        }
                        iphDivider
                        IPHSection(icon: "square.and.arrow.up", iconColor: Color(hex: "0A84FF"), title: "Input methods") {
                            inputMethods
                        }
                        iphDivider
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the Show") {
                            duringShow
                        }
                        iphDivider
                        IPHSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "Tips") {
                            tips
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            iphTopBar(title: "Biography", subtitle: "Feature Guide", onClose: onClose)
                .padding(.top, VaultTheme.Spacing.md)
                .background(VaultTheme.Colors.background.opacity(0.95))
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 36))
                    .foregroundColor(accent)
            }
            Text("Biography Prediction")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Update your Instagram biography to reveal a prediction — the text appears permanently on your profile page until you change it.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VaultTheme.Spacing.lg)
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "The app updates the bio section of your real Instagram profile with a text that matches the spectator's prediction.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "Visible to anyone who visits your profile — no followers required, ideal for in-person reveals.")
            IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                      text: "Supports up to 150 characters, so you can include the full prediction and a signature line.")
        }
    }

    private var inputMethods: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Pills row
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                IPHMethodPill(label: "API", color: Color(hex: "0A84FF"))
                IPHMethodPill(label: "URL Scheme", color: accent)
                IPHMethodPill(label: "OCR", color: Color(hex: "A78BFA"))
                IPHMethodPill(label: "Number Lockscreen", color: Color(hex: "FF453A"))
                IPHMethodPill(label: "Card Lockscreen", color: Color(hex: "FF453A"))
                IPHMethodPill(label: "Number Clock", color: Color(hex: "FF9F0A"))
                IPHMethodPill(label: "Card Clock", color: Color(hex: "30D158"))
                IPHMethodPill(label: "Numpad Card", color: Color(hex: "30D158"))
                IPHMethodPill(label: "Templates", color: Color(hex: "64D2FF"))
                IPHMethodPill(label: "Acrostic Mode", color: Color(hex: "F472B6"))
            }

            // API
            VStack(alignment: .leading, spacing: 10) {
                Text("API")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "network", iconColor: Color(hex: "0A84FF"),
                          text: "Open Performance first, then ask the spectator to make their selection in Inject or your custom API. The app polls every 2 s and updates the bio automatically when a new value arrives — double vibration plus the orange ring confirms it is live on real Instagram.")
                IPHBullet(icon: "network", iconColor: Color(hex: "0A84FF"),
                          text: "Use the Text Template field with {text1}, {text2}, {text3} to combine values from different APIs into one bio — e.g. \"I knew you'd pick {text1} and the color {text2}\".")
            }

            iphDivider

            // URL Scheme
            VStack(alignment: .leading, spacing: 10) {
                Text("URL Scheme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Trigger the biography update using vault://bio?text1=<your text>. Use multiple values for complex predictions: vault://bio?text1=silla&text2=rojo")
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Works from any app — Tasker, NFC tags, Apple Shortcuts, Focus Mode automations — even while Performance is already open.")
            }

            iphDivider

            // OCR
            VStack(alignment: .leading, spacing: 10) {
                Text("OCR — Camera Recognition")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "camera.viewfinder", iconColor: Color(hex: "A78BFA"),
                          text: "Covertly scan text the spectator has written — the word or phrase is captured without any manual typing and is used to update your biography instantly.")
                IPHOCRBox()
            }

            iphDivider

            // Number Lockscreen
            VStack(alignment: .leading, spacing: 10) {
                Text("Number Lockscreen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "lock.fill", iconColor: Color(hex: "FF453A"),
                          text: "Assign {text1}, {text2}, or {text3} to Number Lockscreen. When you open Performance, the fake lockscreen appears. Type the number covertly — it is substituted into the bio template and sent automatically. If a number/custom set is also active, the same number unarchives its slot.")
            }

            iphDivider

            // Card Lockscreen
            VStack(alignment: .leading, spacing: 10) {
                Text("Card Lockscreen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "lock.rectangle.stack.fill", iconColor: Color(hex: "FF453A"),
                          text: "Same fake lockscreen, but the digits are a card code (0 + value + suit). The card name in the device language (e.g. \"3 of hearts\") fills the bio template. If a card set is active, the same card is unarchived.")
            }

            iphDivider

            // Number Clock
            VStack(alignment: .leading, spacing: 10) {
                Text("Number Clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "hand.draw.fill", iconColor: Color(hex: "FF9F0A"),
                          text: "Assign {text1}, {text2}, or {text3} to Number Clock. A black screen appears when Performance opens. Swipe pairs to enter any number of digits (1, 2, 3 or more), then stop swiping for 3 seconds to confirm. The number fills the bio template and the bio is updated. The black screen stays visible until you tap anywhere to show the fake profile.")
            }

            iphDivider

            // Card Clock
            VStack(alignment: .leading, spacing: 10) {
                Text("Card Clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "clock.fill", iconColor: Color(hex: "30D158"),
                          text: "Assign {text1}, {text2}, or {text3} to Card Clock. A black screen appears in Performance (the screen looks off). 2 swipes for value (A=↑→ … 9=←← 10=←↑ J=↑← Q=↑↑ K=↑↓) + 1 swipe for suit (↑=♠ →=♥ ↓=♣ ←=♦). Stop swiping for 3 seconds to confirm. The card name in the device language (e.g. \"3 of hearts\") fills the bio template. If a card set is active, the same card is unarchived. The black screen stays visible until you tap anywhere to show the fake profile.")
            }

            iphDivider

            // Numpad Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Numpad Card")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "rectangle.grid.3x2.fill", iconColor: Color(hex: "30D158"),
                          text: "Assign {text1}, {text2}, or {text3} to Numpad Card. Performance opens on a black screen. Tap anywhere to show the card pad, choose value and suit, and the view disappears to reveal the fake Instagram profile. The card name in the selected language fills the bio template. If a Playing Cards set also uses Numpad Card, the same card is unarchived.")
            }

            iphDivider

            // Compatibility
            VStack(alignment: .leading, spacing: 10) {
                Text("Compatibility")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "checkmark.circle.fill", iconColor: VaultTheme.Colors.success,
                          text: "The SAME interface type can be shared across Set, Biography, and Notes — one capture fills them all at once. For example, one Numpad Card selection can update Bio, post a Note, and reveal the active Playing Cards set.")
                IPHBullet(icon: "exclamationmark.triangle.fill", iconColor: VaultTheme.Colors.warning,
                          text: "DIFFERENT interface types cannot coexist: OCR, Number Clock, Card Clock, Numpad Card, Number Lockscreen and Card Lockscreen are mutually exclusive. Settings warns you and offers to deactivate the conflicting ones.")
            }

            iphDivider

            // Templates
            VStack(alignment: .leading, spacing: 10) {
                Text("Bio Templates (T1 – T4)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "square.grid.2x2.fill", iconColor: Color(hex: "64D2FF"),
                          text: "Above the biography text field there are four template slots — T1, T2, T3, T4. Tap a slot to switch to that template and edit it freely.")
                IPHBullet(icon: "square.grid.2x2.fill", iconColor: Color(hex: "64D2FF"),
                          text: "The active template is the one used when you tap \"Update Biography\", during Performance auto-updates, and when triggered via URL Scheme — up to 4 completely different bio texts ready without retyping.")
                IPHBullet(icon: "square.grid.2x2.fill", iconColor: Color(hex: "64D2FF"),
                          text: "Use {text1}, {text2}, {text3} anywhere in the template. At send time, each placeholder is replaced by its configured source — API, OCR, Lockscreen, Number Clock, Card Clock, or Numpad Card.")
            }

            iphDivider

            // Acrostic Mode
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Acrostic Mode")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "F472B6"))
                        .cornerRadius(4)
                }

                IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                          text: "When enabled, a single word received via API or OCR is automatically converted into an acrostic poem. Each letter of the word becomes its own line, starting with a common word beginning with that letter.")
                // Live example in device language
                AcrosticExampleBullet()
                IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                          text: "Repeated letters cycle through 3 different words automatically — so \"BANANA\" never repeats the same word for B, A, or N.")
                IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                          text: "Works in the device language — Spanish, English, French, German, Italian, Portuguese, Dutch, Polish, Russian, Japanese, Korean, Chinese, Hindi, Thai, Vietnamese and more.")
                IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                          text: "Activate the toggle labeled \"Acrostic Mode\" in the Biography card. The conversion is automatic — the spectator never sees a single word, only a meaningful poetic bio.")
                IPHBullet(icon: "exclamationmark.triangle.fill", iconColor: VaultTheme.Colors.warning,
                          text: "Only works with single words (no spaces). Multi-word inputs are sent as-is, unchanged.")
            }
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPHBullet(icon: "1.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Have the spectator write or choose a word / phrase beforehand (up to 150 characters).")
            IPHBullet(icon: "2.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Capture it via OCR, load via API, type it manually, use Lockscreen / Number Clock / Card Clock / Numpad Card for covert digit or card entry, or select the matching template slot (T1–T4) in one tap.")
            IPHBullet(icon: "3.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Open Performance (or trigger the URL Scheme) — the biography updates in the fake profile instantly. If using Lockscreen, Number Clock, Card Clock, or Numpad Card, the interface appears first for covert input before showing the fake Instagram profile.")
            IPHBullet(icon: "4.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Wait for the double vibration and the orange ring around your profile picture. That means the bio is live on real Instagram, then visit your own Instagram profile before showing the spectator.")
            IPHRealVsFakeBox()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Save your regular bio in template T1 and your reveal bio in T2 — switch between them in one tap during any show.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "The biography works for any text — not just single words. You can reveal a sentence, a date, or a full phrase.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Press Return inside the bio field to add line breaks — the formatting is preserved when sent to Instagram.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use {text1} in the template with Number Clock to show the spectator's thought-of number — e.g. \"You thought of the number {text1}\".")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use {text1} with Card Clock or Numpad Card for card reveals — e.g. \"Your card was {text1}\" fills automatically with the selected card.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Only one interface type (OCR, Lockscreen, Number Clock, Card Clock, or Numpad Card) can run per performance — shared across Set, Bio, and Notes. Configure all slots to use the same type.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Combine with the Profile Picture method: update both the photo and the bio to make an even stronger double reveal.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Use {text1}, {text2}, {text3} placeholders in your template and assign each to a different API source for multi-value predictions.")
            IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                      text: "Try Acrostic Mode with OCR: the spectator writes any word on a piece of paper, you scan it, and your Instagram bio transforms into a poem where each line begins with the letters of their word. A reveal unlike anything else.")
            IPHBullet(icon: "text.badge.star", iconColor: Color(hex: "F472B6"),
                      text: "Acrostic Mode + API: integrate with your booking or Inject link — the spectator chooses a word on their device, it arrives silently, and the bio is rewritten as an acrostic poem before they even look at your phone.")
        }
    }
}
