import SwiftUI

// MARK: - FAQ Help View

struct FAQHelpView: View {
    var onClose: (() -> Void)? = nil

    private let accentColor = Color(hex: "64D2FF")

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                faqTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        faqItem(
                            icon: "hourglass",
                            iconColor: accentColor,
                            question: "faq.q.slow_load.question",
                            answer: "faq.q.slow_load.answer",
                            tip: "faq.q.slow_load.tip"
                        )
                        faqItem(
                            icon: "arrow.clockwise",
                            iconColor: Color(hex: "30D158"),
                            question: "faq.q.refresh.question",
                            answer: "faq.q.refresh.answer",
                            tip: nil
                        )
                        faqItem(
                            icon: "camera.fill",
                            iconColor: Color(hex: "FF9F0A"),
                            question: "faq.q.new_photo.question",
                            answer: "faq.q.new_photo.answer",
                            tip: nil
                        )
                        faqItem(
                            icon: "film.stack",
                            iconColor: Color(hex: "BF5AF2"),
                            question: "faq.q.reels_slow.question",
                            answer: "faq.q.reels_slow.answer",
                            tip: nil
                        )
                        faqItem(
                            icon: "wifi.slash",
                            iconColor: Color(hex: "FF453A"),
                            question: "faq.q.no_data.question",
                            answer: "faq.q.no_data.answer",
                            tip: nil
                        )
                        faqItem(
                            icon: "lock.shield.fill",
                            iconColor: Color(hex: "FF9F0A"),
                            question: "faq.q.bot.question",
                            answer: "faq.q.bot.answer",
                            tip: nil
                        )
                        faqItem(
                            icon: "iphone",
                            iconColor: accentColor,
                            question: "faq.q.not_instagram.question",
                            answer: "faq.q.not_instagram.answer",
                            tip: nil
                        )

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Top bar

    private var faqTopBar: some View {
        ZStack {
            HStack {
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .padding(.trailing, 20)
                }
            }
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                Text("faq.help.title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - FAQ item

    private func faqItem(
        icon: String,
        iconColor: Color,
        question: LocalizedStringKey,
        answer: LocalizedStringKey,
        tip: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(question)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(answer)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let tip {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "FFD60A"))
                        .frame(width: 18)
                        .padding(.top, 1)
                    Text(tip)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(hex: "FFD60A").opacity(0.07))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "FFD60A").opacity(0.25), lineWidth: 1)
                )
            }

            Divider()
                .background(Color.white.opacity(0.06))
        }
    }
}
