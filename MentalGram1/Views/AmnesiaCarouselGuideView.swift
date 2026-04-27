import SwiftUI

struct AmnesiaCarouselGuideView: View {
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

                        guideSection(icon: "rectangle.on.rectangle.slash.fill", iconColor: accent,
                                     title: String(localized: "guide.amnesia.what.title")) {
                            guideBody(String(localized: "guide.amnesia.what.body"))
                        }

                        sectionDivider

                        guideSection(icon: "bolt.fill", iconColor: .yellow,
                                     title: String(localized: "guide.amnesia.trigger.title")) {
                            guideBody(String(localized: "guide.amnesia.trigger.body"))
                        }

                        sectionDivider

                        guideSection(icon: "eyes", iconColor: accent,
                                     title: String(localized: "guide.amnesia.hidden.title")) {
                            guideBody(String(localized: "guide.amnesia.hidden.body"))
                        }

                        sectionDivider

                        guideSection(icon: "theatermasks.fill", iconColor: .orange,
                                     title: String(localized: "guide.amnesia.options.title")) {
                            VStack(alignment: .leading, spacing: 12) {
                                guideStep(number: "A",
                                          title: String(localized: "guide.amnesia.optionA.title"),
                                          body:  String(localized: "guide.amnesia.optionA.body"))
                                guideStep(number: "B",
                                          title: String(localized: "guide.amnesia.optionB.title"),
                                          body:  String(localized: "guide.amnesia.optionB.body"))
                            }
                        }

                        sectionDivider

                        guideSection(icon: "checkmark.seal.fill", iconColor: .green,
                                     title: String(localized: "guide.amnesia.date.title")) {
                            guideBody(String(localized: "guide.amnesia.date.body"))
                        }

                        sectionDivider

                        guideSection(icon: "doc.text.fill", iconColor: accent,
                                     title: String(localized: "guide.amnesia.script.title")) {
                            VStack(alignment: .leading, spacing: 16) {
                                scriptBlock(phase: String(localized: "guide.amnesia.script.opening.phase"),
                                            text:  String(localized: "guide.amnesia.script.opening.text"))
                                scriptBlock(phase: String(localized: "guide.amnesia.script.close.phase"),
                                            text:  String(localized: "guide.amnesia.script.close.text"))
                                scriptBlock(phase: String(localized: "guide.amnesia.script.optionA.phase"),
                                            text:  String(localized: "guide.amnesia.script.optionA.text"))
                                scriptBlock(phase: String(localized: "guide.amnesia.script.optionB.phase"),
                                            text:  String(localized: "guide.amnesia.script.optionB.text"))
                                scriptBlock(phase: String(localized: "guide.amnesia.script.climax.phase"),
                                            text:  String(localized: "guide.amnesia.script.climax.text"))
                            }
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // Top bar
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

    // MARK: - Hero header

    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.35), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "rectangle.on.rectangle.slash.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(accent)
                }
                Text("Amnesia Carousel")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text(String(localized: "guide.amnesia.hero_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.top, 30)
        }
    }

    // MARK: - Helpers

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

    private func scriptBlock(phase: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phase)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent.opacity(0.8))
                .tracking(1)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
        }
    }
}
