import SwiftUI

struct TranspositionHelpView: View {
    let onClose: () -> Void
    private let accent = Color(hex: "BF5AF2")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.lg)

                    VStack(alignment: .leading, spacing: 0) {
                        guideSection(icon: "sparkles", iconColor: accent, title: "What Transposition Does") {
                            guideBody("Transposition is designed for a natural Instagram moment on the spectator's own phone. The spectator searches any public Instagram profile on their device, enters the posts or reels, scrolls, and chooses one of the first 10-12 posts. While you casually bring your phone out of your pocket and place it on the table, Vault silently captures their screen, identifies the profile and the selected post, then prepares the reveal.")
                        }

                        sectionDivider

                        guideSection(icon: "person.crop.rectangle", iconColor: .orange, title: "Performance Handling") {
                            VStack(alignment: .leading, spacing: 12) {
                                guideStep(number: "1", title: "Give the instruction", body: "Ask the spectator to use their own phone to search any public Instagram profile. Casually tell them not to spend too long and to choose one of the first 10-12 posts.")
                                guideStep(number: "2", title: "Time the capture", body: "As you speak and bring your phone out, aim it toward the spectator's screen and press the volume button. Keep your hand still until the phone vibrates.")
                                guideStep(number: "3", title: "Wait for vibration", body: "The vibration means the capture has finished. Hold steady for about 1 second after pressing volume; Vault takes a short burst of frames and automatically selects the sharpest, most readable one.")
                                guideStep(number: "4", title: "Reveal", body: "When Vault has prepared the post, use the configured reveal mode: Grid animation or Black Screen.")
                            }
                        }

                        sectionDivider

                        guideSection(icon: "text.viewfinder", iconColor: .green, title: "What Must Be Visible") {
                            VStack(alignment: .leading, spacing: 10) {
                                guideBullet("The profile username must be visible. This is the main anchor used to load the correct public profile.")
                                guideBullet("For Reels/videos, the title or caption line below the username is very important. If the first words match a candidate caption, Vault treats it as a strong signal.")
                                guideBullet("Visible text in the video frame, subtitles, like/comment/share counters and dates can all help, but the title/caption is usually more reliable than likes.")
                                guideBullet("If the screen is too bright, reflective, angled or far away, OCR may not read the text reliably.")
                            }
                        }

                        sectionDivider

                        guideSection(icon: "camera.metering.center.weighted", iconColor: .yellow, title: "Camera Distance and Zoom") {
                            VStack(alignment: .leading, spacing: 10) {
                                warningBox("This part must be practiced. Transposition is reading small text from another phone screen, not recognizing a large simple image. Distance, angle and framing matter.")
                                guideBody("Before performing, use the Camera & Zoom test view in Transposition settings. Choose the zoom that fits your device and real performance distance.")
                                guideBullet("The spectator's iPhone screen should fill most of your frame, but not be cropped too tight.")
                                guideBullet("The username, title/caption and part of the post should be visible together.")
                                guideBullet("Do not shoot from too close: it can crop the username or title. Do not shoot from too far: the text becomes too small to read.")
                                guideBullet("Practice aiming at the spectator's phone naturally. Try to keep the camera as square to their screen as possible, slightly from above toward the screen, instead of a strong side perspective.")
                                guideBullet("A steep sideways angle, glare or reflections can distort the text and reduce reliability.")
                                guideBullet("If the spectator's phone brightness is very high, ask them naturally to lower it slightly or change the angle to avoid glare.")
                                guideBullet("Enable Save selected capture when testing. Vault will save the exact frame sent to OpenAI into the gallery, so you can diagnose blur, distance, reflections or missing text.")
                            }
                        }

                        sectionDivider

                        guideSection(icon: "square.grid.3x3.fill", iconColor: accent, title: "Grid Reveal Mode") {
                            guideBody("In Grid mode, Vault prepares the selected post and then allows a reveal animation. When the post is ready, the magician sees the orange ring confirmation. Only then should you trigger the animation with volume or an open-hand gesture. The gesture can be made with either hand; once it fires, the pending reveal is consumed so repeating the gesture will not start a second animation.")
                        }

                        sectionDivider

                        guideSection(icon: "moon.fill", iconColor: .blue, title: "Black Screen Reveal Mode") {
                            VStack(alignment: .leading, spacing: 10) {
                                guideBody("Black Screen mode is used without a visible animation. The spectator believes the phone is off. Once the post is ready, you can touch the screen and swipe up; the black screen dissolves and the selected post opens large in the real Instagram app.")
                                guideBullet("Dim Black Screen lowers brightness while the camera is active, helping hide the green camera indicator. Brightness is restored before Instagram opens.")
                                guideBullet("A tiny white dot appears near the lower-right edge when the post is ready. It is a discreet private cue for the magician.")
                                guideBullet("The ready sound can be enabled or disabled in Black Screen Options.")
                            }
                        }

                        sectionDivider

                        guideSection(icon: "checkmark.seal.fill", iconColor: .green, title: "Magician Feedback") {
                            VStack(alignment: .leading, spacing: 10) {
                                guideBullet("A strong vibration after pressing volume means the capture burst is complete.")
                                guideBullet("The recognized profile may briefly appear in the following area as confirmation.")
                                guideBullet("The orange ring means the post is ready to reveal.")
                                guideBullet("If you gesture before the orange ring appears, nothing should happen because the post is not ready yet.")
                                guideBullet("In Black Screen mode, a short message-like sound can confirm that the reveal is ready if Ready Sound is enabled.")
                                guideBullet("If recognition fails, repeated error haptics tell you to press volume again and recapture.")
                            }
                        }

                        sectionDivider

                        guideSection(icon: "exclamationmark.triangle.fill", iconColor: .red, title: "Important Cautions") {
                            VStack(alignment: .leading, spacing: 10) {
                                guideBullet("The profile must be public. Private profiles cannot be loaded unless accessible to your account.")
                                guideBullet("Keep the choice within the first 10-12 posts. Transposition is optimized to avoid extra Instagram calls.")
                                guideBullet("After pressing volume, do not move your hand until the vibration confirms capture.")
                                guideBullet("Avoid glare, extreme screen brightness, shaky movement and very small text.")
                                guideBullet("If the app only has low confidence, it still prepares the best available candidate, but testing distance and zoom will improve reliability.")
                            }
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.top, VaultTheme.Spacing.lg)
        }
    }

    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.35), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 215)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 76, height: 76)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(accent)
                }
                Text("Transposition")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("AI-assisted spectator post detection")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.top, 30)
        }
    }

    private func guideSection<Content: View>(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            content()
        }
        .padding(.vertical, VaultTheme.Spacing.lg)
    }

    private var sectionDivider: some View {
        Divider().background(Color.white.opacity(0.08))
    }

    private func guideBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }

    private func guideBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.yellow)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func guideStep(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }
}
