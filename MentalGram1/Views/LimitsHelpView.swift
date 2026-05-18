import SwiftUI

// MARK: - Limits & Safety Help View (simplified & reassuring)

struct LimitsHelpView: View {
    var onClose: (() -> Void)? = nil
    /// When true, hides the X button and shows a sticky "I understand" CTA at the bottom.
    var showContinueButton: Bool = false
    var onContinue: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                limitsTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dontWorrySection
                        budgetGaugeSection
                        apiCostTableSection
                        rehearsalSection
                        profilesRedDotSection
                        ifWarningSection
                        duringShowSection
                        bestPracticesSection
                        testingSection
                        sessionExpiredSection
                        noBanBanner
                        // Extra bottom padding so the sticky button never covers content
                        Spacer(minLength: showContinueButton ? 100 : 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }

                // Sticky "I understand" button — only shown in gate mode
                if showContinueButton {
                    continueButton
                }
            }
        }
    }

    // MARK: - Continue button (gate mode)

    private var continueButton: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))
            Button(action: { onContinue?() }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("limits.help.continue.button")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(VaultTheme.Colors.success)
                .cornerRadius(14)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(VaultTheme.Colors.background)
    }

    // MARK: - Top bar

    private var limitsTopBar: some View {
        ZStack {
            HStack {
                Spacer()
                // X button is hidden in gate mode (user must tap the CTA to continue)
                if let onClose, !showContinueButton {
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
                Text("limits.help.title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - 1. Don't worry — reassuring intro

    private var dontWorrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VaultTheme.Colors.success.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.success)
                }
                Text("limits.help.calm.title")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }

            Text("limits.help.calm.body")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            infoBox(
                icon: "checkmark.seal.fill",
                iconColor: VaultTheme.Colors.success,
                text: "limits.help.calm.infobox",
                bgColor: VaultTheme.Colors.success
            )
        }
    }

    // MARK: - 2. Budget gauge

    private var budgetGaugeSection: some View {
        limSection(icon: "gauge.with.dots.needle.33percent",
                   iconColor: Color(hex: "FF6B35"),
                   title: "limits.help.gauge.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("limits.help.gauge.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                budgetGauge

                infoBox(
                    icon: "clock.arrow.circlepath",
                    iconColor: VaultTheme.Colors.primary,
                    text: "limits.help.gauge.cache",
                    bgColor: VaultTheme.Colors.primary
                )

                infoBox(
                    icon: "lock.shield.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "limits.help.gauge.hardstop",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    private var budgetGauge: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VaultTheme.Colors.success.opacity(0.8))
                        .frame(width: geo.size.width * 0.58)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "FF9F0A").opacity(0.8))
                        .frame(width: geo.size.width * 0.26)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.8))
                }
            }
            .frame(height: 10)

            HStack {
                Text("limits.help.gauge.zone.safe")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(VaultTheme.Colors.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("limits.help.gauge.zone.low")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "FF9F0A"))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("limits.help.gauge.zone.critical")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - 3. API cost table

    private var apiCostTableSection: some View {
        limSection(icon: "tablecells",
                   iconColor: VaultTheme.Colors.primary,
                   title: "limits.help.table.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("limits.help.table.subtitle")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    tableHeaderRow
                    Divider().background(Color.white.opacity(0.08))
                    tableDataRow("limits.help.table.row.performance", first: "1",   again: "0 ✓")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.followers",   first: "1",   again: "0 ✓")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.profile.new", first: "4–5", again: "0 ✓")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.sa",          first: "2",   again: "—")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.upload",      first: "1",   again: "—")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.reveal",      first: "1",   again: "—")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.notebio",     first: "2",   again: "2")
                    Divider().background(Color.white.opacity(0.06))
                    tableDataRow("limits.help.table.row.explore",     first: "1–2", again: "0 ✓")
                }
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.09), lineWidth: 1))

                infoBox(
                    icon: "arrow.clockwise.circle.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "limits.help.sa.auto",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 8) {
            Text("limits.help.table.col.action")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("limits.help.table.col.first")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .frame(width: 44, alignment: .center)
            Text("limits.help.table.col.again")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(VaultTheme.Colors.textPrimary)
                .frame(width: 50, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
    }

    private func tableDataRow(_ actionKey: LocalizedStringKey, first: String, again: String) -> some View {
        HStack(spacing: 8) {
            Text(actionKey)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(first)
                .font(.system(size: 12))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .frame(width: 44, alignment: .center)
            Text(again)
                .font(.system(size: 12, weight: again.contains("✓") ? .semibold : .regular))
                .foregroundColor(again.contains("✓") ? VaultTheme.Colors.success : VaultTheme.Colors.textSecondary)
                .frame(width: 50, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - 3. Safe rehearsal

    private var rehearsalSection: some View {
        limSection(icon: "repeat.circle.fill",
                   iconColor: Color(hex: "A78BFA"),
                   title: "limits.help.rehearsal.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("limits.help.rehearsal.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.rehearsal.tip1")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.rehearsal.tip2")
                limBullet(icon: "xmark.circle.fill",
                          iconColor: Color(hex: "FF3B30"),
                          text: "limits.help.rehearsal.avoid1")
                limBullet(icon: "xmark.circle.fill",
                          iconColor: Color(hex: "FF3B30"),
                          text: "limits.help.rehearsal.avoid2")

                infoBox(
                    icon: "lightbulb.fill",
                    iconColor: Color(hex: "FF9F0A"),
                    text: "limits.help.rehearsal.tip",
                    bgColor: Color(hex: "FF9F0A")
                )
            }
        }
    }

    // MARK: - 5. Profiles & red dot

    private var profilesRedDotSection: some View {
        limSection(icon: "person.crop.circle.badge.exclamationmark",
                   iconColor: Color.red,
                   title: "limits.help.profiles.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("limits.help.profiles.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: Color(hex: "FF9F0A"),
                    text: "limits.help.profiles.max",
                    bgColor: Color(hex: "FF9F0A")
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("limits.help.reddot.title")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)

                    // Two mockups side by side
                    HStack(spacing: 10) {
                        followersDotMockup
                        performanceDotMockup
                    }

                    Text("limits.help.reddot.body")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("limits.help.reddot.block")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Mockup: followers list header with red dot on person.badge.plus
    private var followersDotMockup: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                Text("username")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

            Text("limits.help.reddot.location.followers")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(VaultTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mockup: performance bottom tab bar with red dot on paper plane + annotation arrow
    private var performanceDotMockup: some View {
        VStack(spacing: 4) {
            // Tab bar mockup
            HStack(spacing: 0) {
                Image(systemName: "house")
                    .font(.system(size: 17))
                    .foregroundColor(.black.opacity(0.35))
                    .frame(maxWidth: .infinity)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundColor(.black.opacity(0.35))
                    .frame(maxWidth: .infinity)
                // Paper plane with red dot — highlighted slot
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.black)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .offset(x: 5, y: -3)
                }
                .frame(maxWidth: .infinity)
                Image(systemName: "play.rectangle")
                    .font(.system(size: 17))
                    .foregroundColor(.black.opacity(0.35))
                    .frame(maxWidth: .infinity)
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

            // Arrow + label pointing to paper plane (3rd of 5 slots = 50% from left)
            HStack(spacing: 0) {
                Spacer()
                    .frame(maxWidth: .infinity) // slot 1 (house)
                Spacer()
                    .frame(maxWidth: .infinity) // slot 2 (search)
                VStack(spacing: 1) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 7))
                        .foregroundColor(Color.red)
                    Text("limits.help.reddot.location.performance")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity) // slot 3 (paper plane) ← annotation
                Spacer()
                    .frame(maxWidth: .infinity) // slot 4 (reels)
                Spacer()
                    .frame(maxWidth: .infinity) // slot 5 (avatar)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 6. If you see a warning — clear steps

    private var ifWarningSection: some View {
        limSection(icon: "exclamationmark.bubble.fill",
                   iconColor: Color(hex: "FF9F0A"),
                   title: "limits.help.warning.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("limits.help.warning.intro")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                stepRow(number: "1", text: "limits.help.warning.step1")
                stepRow(number: "2", text: "limits.help.warning.step2")
                stepRow(number: "3", text: "limits.help.warning.step3")
                stepRow(number: "4", text: "limits.help.warning.step4")

                infoBox(
                    icon: "heart.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "limits.help.warning.reassure",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    // MARK: - 3. During a show

    private var duringShowSection: some View {
        limSection(icon: "theatermasks.fill",
                   iconColor: Color(hex: "A78BFA"),
                   title: "limits.help.show.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("limits.help.show.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "wifi.slash",
                    iconColor: Color(hex: "A78BFA"),
                    text: "limits.help.show.infobox",
                    bgColor: Color(hex: "A78BFA")
                )
            }
        }
    }

    // MARK: - 4. Best practices

    private var bestPracticesSection: some View {
        limSection(icon: "sparkles",
                   iconColor: VaultTheme.Colors.primary,
                   title: "limits.help.best.title") {
            VStack(alignment: .leading, spacing: 10) {
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item1")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item2")
                limBullet(icon: "checkmark.circle.fill",
                          iconColor: VaultTheme.Colors.success,
                          text: "limits.help.best.item4")
            }
        }
    }

    // MARK: - 5. Testing & security verification

    private var testingSection: some View {
        limSection(icon: "flask.fill",
                   iconColor: Color(hex: "FF6B35"),
                   title: "limits.help.testing.title") {
            VStack(alignment: .leading, spacing: 10) {
                Text("limits.help.testing.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "checkmark.circle.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "limits.help.testing.fix",
                    bgColor: VaultTheme.Colors.success
                )
            }
        }
    }

    // MARK: - 6. Session expired / temporary restriction

    private var sessionExpiredSection: some View {
        limSection(icon: "lock.shield.fill",
                   iconColor: Color(hex: "FF6B35"),
                   title: "limits.help.session.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text("limits.help.session.body")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                caseRow(label: "limits.help.session.case1.label",
                        action: "limits.help.session.case1.action",
                        color: VaultTheme.Colors.success)
                caseRow(label: "limits.help.session.case2.label",
                        action: "limits.help.session.case2.action",
                        color: Color(hex: "FF9F0A"))
                caseRow(label: "limits.help.session.case3.label",
                        action: "limits.help.session.case3.action",
                        color: Color(hex: "A78BFA"))

                infoBox(
                    icon: "person.badge.clock.fill",
                    iconColor: Color(hex: "FF6B35"),
                    text: "limits.help.session.new_account",
                    bgColor: Color(hex: "FF6B35")
                )

                infoBox(
                    icon: "envelope.fill",
                    iconColor: VaultTheme.Colors.primary,
                    text: "limits.help.session.contact",
                    bgColor: VaultTheme.Colors.primary
                )
            }
        }
    }

    // MARK: - Final reassurance banner

    private var noBanBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VaultTheme.Colors.success.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "shield.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(VaultTheme.Colors.success)
                }
                Text("limits.help.noban.title")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(VaultTheme.Colors.success)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("limits.help.noban.body")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(VaultTheme.Colors.success.opacity(0.10))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VaultTheme.Colors.success.opacity(0.35), lineWidth: 1.5))
    }

    // MARK: - Shared helpers

    private func limSection<Content: View>(
        icon: String, iconColor: Color, title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

    private func limBullet(icon: String, iconColor: Color, text: LocalizedStringKey) -> some View {
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

    private func infoBox(icon: String, iconColor: Color, text: LocalizedStringKey, bgColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(bgColor.opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bgColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func caseRow(label: LocalizedStringKey, action: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .padding(.top, 1)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(action)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 13)
        }
    }

    private func stepRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF9F0A").opacity(0.15))
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "FF9F0A"))
            }
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}
