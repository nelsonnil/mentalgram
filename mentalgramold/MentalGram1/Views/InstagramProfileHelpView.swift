import SwiftUI

// MARK: - Shared helpers

private struct IPHSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
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
    let text: String

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

private struct IPHMethodPill: View {
    let label: String
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

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "FF9F0A"))
                    .padding(.top, 1)
                Text("The app **vibrates** when the upload or unarchive is confirmed on real Instagram. Wait for that signal before proceeding.")
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

private var iphDivider: some View {
    Rectangle()
        .fill(Color(hex: "#2C2C2E"))
        .frame(height: 1)
        .padding(.vertical, 4)
}

private func iphTopBar(title: String, subtitle: String, onClose: @escaping () -> Void) -> some View {
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
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the show") {
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
                      text: "Wait for the vibration confirming the upload on real Instagram, then open your own Instagram profile before showing the spectator.")
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
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the show") {
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
            HStack(spacing: 6) {
                IPHMethodPill(label: "API", color: Color(hex: "0A84FF"))
                IPHMethodPill(label: "URL Scheme", color: accent)
                IPHMethodPill(label: "OCR", color: Color(hex: "A78BFA"))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("API")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "network", iconColor: Color(hex: "0A84FF"),
                          text: "The app calls the Instagram API directly to post the note. Set up an API source in \"Auto Input\" to pull the text from an external service (e.g. a personal webhook or Make/Zapier automation).")
            }

            iphDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("URL Scheme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Trigger the note from any automation app using vault://note?text=<your text>. Combine with Apple Shortcuts to send the note automatically when Performance opens.")
            }

            iphDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("OCR — Camera Recognition")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "camera.viewfinder", iconColor: Color(hex: "A78BFA"),
                          text: "Point the camera at a word the spectator wrote or a card they are holding — the app reads the text automatically and sends it as your note, no typing required.")
                IPHOCRBox()
            }
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPHBullet(icon: "1.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Ask the spectator to think of or write a short word (max 60 characters).")
            IPHBullet(icon: "2.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Use OCR to read it covertly, or enter it manually before the performance.")
            IPHBullet(icon: "3.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Open Performance — the note posts automatically (with API or URL Scheme) or tap \"Send Note\". It appears in the fake profile instantly.")
            IPHBullet(icon: "4.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Wait for the vibration confirming the note is live on real Instagram, then open your own profile before the spectator looks.")
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
                        IPHSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the show") {
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
            HStack(spacing: 6) {
                IPHMethodPill(label: "API", color: Color(hex: "0A84FF"))
                IPHMethodPill(label: "URL Scheme", color: accent)
                IPHMethodPill(label: "OCR", color: Color(hex: "A78BFA"))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("API")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "network", iconColor: Color(hex: "0A84FF"),
                          text: "The app calls the Instagram Graph API to update your bio. Configure an API source in \"Auto Input\" to receive the prediction text from an external system before the show.")
            }

            iphDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("URL Scheme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "link", iconColor: accent,
                          text: "Trigger the biography update using vault://bio?text=<your text>. Create an Apple Shortcut that sends this URL when Performance opens for a hands-free reveal.")
                IPHBullet(icon: "link", iconColor: accent,
                          text: "You can also use URL schemes from other apps (Tasker, NFC tags, Focus Mode automations) to update the bio at the right moment.")
            }

            iphDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("OCR — Camera Recognition")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                IPHBullet(icon: "camera.viewfinder", iconColor: Color(hex: "A78BFA"),
                          text: "Covertly scan text the spectator has written — the word or phrase is captured without any manual typing and is used to update your biography instantly.")
                IPHOCRBox()
            }
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPHBullet(icon: "1.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Have the spectator write or choose a word / phrase beforehand (up to 150 characters).")
            IPHBullet(icon: "2.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Capture it via OCR, load it via API, or type it manually before the performance.")
            IPHBullet(icon: "3.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Open Performance (or trigger the URL Scheme) — the biography updates in the fake profile instantly.")
            IPHBullet(icon: "4.circle.fill", iconColor: VaultTheme.Colors.warning,
                      text: "Wait for the vibration confirming the bio is live on real Instagram, then visit your own Instagram profile before showing the spectator.")
            IPHRealVsFakeBox()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Pre-write a \"normal\" bio and update it back after the show to avoid leaving the prediction bio permanently.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "The biography works for any text — not just single words. You can reveal a sentence, a date, or a full phrase.")
            IPHBullet(icon: "lightbulb", iconColor: Color(hex: "F472B6"),
                      text: "Combine with the Profile Picture method: update both the photo and the bio to make an even stronger double reveal.")
        }
    }
}
