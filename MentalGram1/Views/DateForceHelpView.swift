import SwiftUI

// MARK: - Date Force Help View

struct DateForceHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Hero Header ───────────────────────────────────────
                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.xxl)

                    // ── Sections ──────────────────────────────────────────
                    Group {
                        HelpSection(icon: "eye.fill", iconColor: VaultTheme.Colors.primary, title: "What the Audience Sees") {
                            whatAudienceSees
                        }

                        divider

                        HelpSection(icon: "gearshape.2.fill", iconColor: VaultTheme.Colors.secondary, title: "How It Works") {
                            howItWorks
                        }

                        divider

                        HelpSection(icon: "list.number", iconColor: VaultTheme.Colors.success, title: "Before the Show") {
                            beforeShow
                        }

                        divider

                        modeSection

                        divider

                        HelpSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the Show") {
                            duringShow
                        }

                        divider

                        HelpSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "Tips & Edge Cases") {
                            tipsSection
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // ── Top bar ───────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date Force")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Performance Guide")
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
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(
                VaultTheme.Colors.background
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(VaultTheme.Colors.primary.opacity(0.15))
                    .frame(width: 80, height: 80)
                Text("🔮")
                    .font(.system(size: 40))
            }

            Text("Social Experiment")
                .font(VaultTheme.Typography.title())
                .foregroundColor(VaultTheme.Colors.textPrimary)

            Text("An improvised experiment around a simple truth: the people we choose to follow are the ones who matter to us. And that choice, multiplied across a room, reveals exactly where we are in time.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(VaultTheme.Colors.cardBorder)
            .frame(height: 1)
            .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - Section Content

    private var whatAudienceSees: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            BodyText("The performer frames it as a spontaneous experiment: the people we follow on Instagram are not random — they are a reflection of who we are. And the number of people each of us follows carries real weight.")
            BodyText("Several audience members reveal how many people they follow. Those numbers are combined. A volunteer freely picks any post from Explore — a complete stranger. That creator's follower data, when calculated against the audience's following counts, decodes into today's date and the exact time of the moment. Not a trick. A consequence of real connections.")
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            BulletPoint(text: "The app reads each spectator's real **following count** — the people they choose to follow, not their followers.")
            BulletPoint(text: "Those counts are added together. The sum is the audience's collective social reach.")
            BulletPoint(text: "Any post opened in Explore secretly shows **forced numbers**: followers = today's date + the sum, following = current time + the sum.")
            BulletPoint(text: "The audience subtracts their own sum and arrives at the date and time. The spectators' real following counts can be verified on their own phones at any moment.")

            InfoBox(text: "Following counts ≥ 1,000 are automatically reduced to their last 3 digits (e.g. 1,247 → 247). Announce this naturally during the show — \"to keep it human\" — and the audience can verify it directly on the spectator's profile.")
        }
    }

    private var beforeShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            NumberedStep(number: 1, text: "Enable **Date Force** in Settings.")
            NumberedStep(number: 2, text: "Choose your **date format**: DD/MM (European) or MM/DD (American).")
            NumberedStep(number: 3, text: "Choose your **mode**: Simple, Dual, or Auto (see Mode Guide below).")
            NumberedStep(number: 4, text: "Set a **time offset** (1–5 min) to account for the time spent before the reveal.")
            NumberedStep(number: 5, text: "**Auto mode only:** set the max number of followers to capture (2–6). The app does the rest when you enter Performance.")
            NumberedStep(number: 6, text: "That's it. No props, no envelopes, no pre-show setup. The only thing that matters is the present moment — and the app captures it in real time.")
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundColor(VaultTheme.Colors.primary)
                    .font(.system(size: 18))
                Text("Mode Guide")
                    .font(VaultTheme.Typography.titleSmall())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }

            // Simple mode
            ModeCard(
                badge: "SIMPLE",
                badgeColor: VaultTheme.Colors.secondary,
                subtitle: "Best for short shows or small groups",
                rows: [
                    ("person.2.fill", "Register any number of spectators (2–5 recommended). All go to the date group."),
                    ("calendar", "Explore followers − spectator sum = date."),
                    ("clock.fill", "Explore following shows the time directly — no subtraction needed. Great as a kicker reveal."),
                ]
            )

            // Dual mode
            ModeCard(
                badge: "DUAL",
                badgeColor: VaultTheme.Colors.primary,
                subtitle: "Maximum drama — two independent calculations",
                rows: [
                    ("person.2.fill", "First N spectators (set in Settings) → date group. Remaining spectators → time group."),
                    ("calendar", "Explore followers − date group sum = date."),
                    ("clock.fill", "Explore following − time group sum = time."),
                    ("star.fill", "Two separate reveals from two separate groups. The audience is completely lost.")
                ]
            )

            // Auto mode
            ModeCard(
                badge: "AUTO",
                badgeColor: Color(hex: "F472B6"),
                subtitle: "Hands-free — followers are captured automatically",
                rows: [
                    ("waveform", "Ask the audience to follow you. In Performance, tap the 'Followed by' area once to capture the latest N followers automatically."),
                    ("arrow.down.circle.fill", "Names appear one by one as they load. The last of the date group shows a subtle dash — only you will notice."),
                    ("calendar", "First half (rounded up) → date group. Second half → time group. Groups split automatically."),
                    ("arrow.left.arrow.right", "Once loaded, tap again to toggle between date group and time group names."),
                    ("checkmark.circle.fill", "Go to Explore and open any post. The forced numbers are already calculated and ready to reveal.")
                ]
            )
        }
        .padding(.horizontal, VaultTheme.Spacing.lg)
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {

            // Opening
            ShowStep(
                label: "OPENING",
                labelColor: VaultTheme.Colors.textSecondary,
                steps: [
                    ShowStepItem(
                        action: "Frame it as a spontaneous experiment, not a trick.",
                        dialogue: "\"I want to try something. On Instagram, the people you follow — not your followers, the people YOU choose to follow — those are the ones that actually matter to you. They are your world. And I think that choice, when you add it all up across a room full of people, becomes something more than just a number.\""
                    )
                ]
            )

            // ── SIMPLE / DUAL ──────────────────────────────────────────────

            // Date group (Simple & Dual)
            ShowStep(
                label: "DATE GROUP  —  SIMPLE & DUAL",
                labelColor: VaultTheme.Colors.secondary,
                steps: [
                    ShowStepItem(action: "Ask for a volunteer. Search their Instagram in Explore, open their profile, then close it — it registers automatically.", dialogue: nil),
                    ShowStepItem(
                        action: "Read their following count aloud.",
                        dialogue: "\"María — how many people do you follow? 347. Those are 347 people you decided were worth your attention. That means something.\""
                    ),
                    ShowStepItem(
                        action: "If they follow 1,000 or more, use the last 3 digits.",
                        dialogue: "\"Pedro, you follow 1,247 people — that's a lot of connections. To keep this human, we'll work with the last three digits: 247.\""
                    ),
                    ShowStepItem(action: "Repeat with the remaining spectators in this group. Write each number visibly. Sum them.", dialogue: nil),
                    ShowStepItem(
                        action: "Announce the total with weight.",
                        dialogue: "\"347 plus 512. Together, the people you follow add up to 859. That is your collective reach. Remember it.\""
                    )
                ]
            )

            // Time group (Dual only)
            ShowStep(
                label: "TIME GROUP  —  DUAL ONLY",
                labelColor: VaultTheme.Colors.primary,
                steps: [
                    ShowStepItem(action: "Ask for new volunteers — different from the first group.", dialogue: nil),
                    ShowStepItem(
                        action: "Repeat the same process. Sum their numbers.",
                        dialogue: "\"183 plus 291. The people you follow together: 474.\""
                    )
                ]
            )

            // ── AUTO ───────────────────────────────────────────────────────

            ShowStep(
                label: "AUTO MODE  —  SETUP",
                labelColor: Color(hex: "F472B6"),
                steps: [
                    ShowStepItem(
                        action: "Ask the audience to follow you on Instagram right now.",
                        dialogue: "\"Before we start — if you want to be part of this, open Instagram and follow me. It will take ten seconds.\""
                    ),
                    ShowStepItem(action: "Wait a moment. Then enter Performance and tap the 'Followed by' area once. The app silently fetches the latest followers and their following counts one by one.", dialogue: nil),
                    ShowStepItem(
                        action: "Names appear on screen as they load. The last name of the date group has a subtle dash — only you see it. Once fully loaded, tap to switch between groups if needed.",
                        dialogue: nil
                    )
                ]
            )

            ShowStep(
                label: "AUTO MODE  —  DURING THE SHOW",
                labelColor: Color(hex: "F472B6"),
                steps: [
                    ShowStepItem(
                        action: "Address the date group by name. Ask each person to open their own Instagram and read how many people they follow.",
                        dialogue: "\"María, Carlos, Luisa — you three. Open Instagram, go to your profile. How many people do you follow? Read it out loud.\""
                    ),
                    ShowStepItem(
                        action: "Guide the audience through the addition publicly.",
                        dialogue: "\"347 plus 512 plus 190 — together: 1,049. Write that down.\""
                    ),
                    ShowStepItem(
                        action: "Repeat with the time group.",
                        dialogue: "\"Pedro, Ana, Jorge — same thing. Your numbers: 283 plus 410 plus 97 — together: 790.\""
                    ),
                    ShowStepItem(action: "Go to Explore and hand the phone to someone who has not participated. The numbers are already calculated and waiting.", dialogue: nil)
                ]
            )

            // ── SHARED ─────────────────────────────────────────────────────

            // Explore
            ShowStep(
                label: "THE FREE CHOICE",
                labelColor: VaultTheme.Colors.warning,
                steps: [
                    ShowStepItem(action: "Invite someone who has not participated at all.", dialogue: nil),
                    ShowStepItem(
                        action: "Hand them your phone with Explore open.",
                        dialogue: "\"This is Instagram Explore — posts from people all over the world that you have never met. Scroll through. No rush. When one catches your attention, tap it. Completely your choice.\""
                    ),
                    ShowStepItem(
                        action: "They tap freely. The forced numbers appear below the username.",
                        dialogue: "\"Look at this person. A complete stranger. They have 3,886 followers — and they follow 2,322 people.\""
                    )
                ]
            )

            // The reveal
            ShowStep(
                label: "THE REVELATION",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    ShowStepItem(
                        action: "Reveal the date. Slow down. Let every step land.",
                        dialogue: "\"The people you follow, combined, give us 859. This stranger has 3,886 followers. 3,886 minus 859... 3,027. Four digits. 28 — 02. The 28th of February. What is today's date?\""
                    ),
                    ShowStepItem(action: "Pause. Let it fully land before moving on.", dialogue: nil),
                    ShowStepItem(
                        action: "Reveal the time — subtraction in Dual/Auto, direct reading in Simple.",
                        dialogue: "\"And the people your second group follows together: 474. This stranger follows 2,322. 2,322 minus 474... 1,848. Can someone check the time right now?\""
                    ),
                    ShowStepItem(
                        action: "Close on the idea, not the numbers.",
                        dialogue: "\"This wasn't a trick. The people you follow — the choices you made, privately, over years — just told us exactly when and where we are. That's not magic. That's connection.\""
                    )
                ]
            )
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            TipRow(icon: "xmark.circle.fill", color: VaultTheme.Colors.error,
                   text: "**Wrong profile? (Simple/Dual)** Tap the profile picture while on their profile to cancel. That profile will not be registered when you close it.")

            TipRow(icon: "arrow.counterclockwise", color: VaultTheme.Colors.secondary,
                   text: "**Auto reset.** Spectators are cleared automatically after the Explore post is closed, so the effect is ready to repeat immediately.")

            TipRow(icon: "clock.badge.exclamationmark.fill", color: VaultTheme.Colors.warning,
                   text: "**Time offset.** If the reveal happens 3 minutes after you open Explore, set the offset to +3 min so the time on stage matches the clock.")

            TipRow(icon: "waveform", color: Color(hex: "F472B6"),
                   text: "**Auto mode loading time.** Each follower takes ~1–2 seconds to load. With 6 followers expect ~10 seconds total — use this time to build anticipation with the audience.")

            TipRow(icon: "minus", color: VaultTheme.Colors.textTertiary,
                   text: "**Auto mode group marker.** During loading, the last person of the date group shows a dash after their name. Only you know what it means. The audience sees plain text.")

            TipRow(icon: "person.fill.questionmark", color: VaultTheme.Colors.textSecondary,
                   text: "**Private profiles.** The following count is still visible. No issues.")

            TipRow(icon: "number.circle.fill", color: VaultTheme.Colors.primary,
                   text: "**Low following count (under 10).** Works mathematically but adds little drama. Prefer spectators who follow at least 50 people.")

            TipRow(icon: "checkmark.shield.fill", color: VaultTheme.Colors.success,
                   text: "**The audience can verify.** Spectators can check their own following count on their phones and see it matches what you read. This makes the effect unassailable.")
        }
    }
}

// MARK: - Reusable Components

private struct HelpSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: Content

    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 18))
                Text(title)
                    .font(VaultTheme.Typography.titleSmall())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content
        }
    }
}

private struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(VaultTheme.Typography.body())
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BulletPoint: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Circle()
                .fill(VaultTheme.Colors.primary)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(LocalizedStringKey(text))
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(VaultTheme.Colors.primary)
                .frame(width: 22, height: 22)
                .background(VaultTheme.Colors.primary.opacity(0.15))
                .clipShape(Circle())
            Text(LocalizedStringKey(text))
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoBox: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(VaultTheme.Colors.info)
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.info.opacity(0.08))
        .cornerRadius(VaultTheme.CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                .stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ModeCard: View {
    let badge: String
    let badgeColor: Color
    let subtitle: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15))
                    .cornerRadius(VaultTheme.CornerRadius.pill)
                Text(subtitle)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: rows[i].0)
                        .font(.system(size: 12))
                        .foregroundColor(badgeColor)
                        .frame(width: 18)
                        .padding(.top, 2)
                    Text(rows[i].1)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .stroke(badgeColor.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ShowStepItem {
    let action: String
    let dialogue: String?
}

private struct ShowStep: View {
    let label: String
    let labelColor: Color
    let steps: [ShowStepItem]

    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(labelColor)
                .tracking(1.5)

            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                ForEach(steps.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                            Circle()
                                .fill(labelColor.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 8)
                            Text(steps[i].action)
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let dialogue = steps[i].dialogue {
                            DialogueBox(text: dialogue, color: labelColor)
                        }
                    }
                }
            }
        }
        .padding(VaultTheme.Spacing.md)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .stroke(labelColor.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct DialogueBox: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .cornerRadius(1)
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .italic()
                .foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, VaultTheme.Spacing.md)
    }
}

private struct TipRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 22)
                .padding(.top, 1)
            Text(LocalizedStringKey(text))
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
