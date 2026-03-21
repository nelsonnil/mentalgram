import SwiftUI

// MARK: - Date Force Help View

struct DateForceHelpView: View {
    let onClose: () -> Void
    @State private var selectedMode: DateForceMode = .auto

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    heroHeader
                        .padding(.bottom, VaultTheme.Spacing.xl)

                    // Mode selector (sticky-ish, just below hero)
                    modeSelectorBar
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.xl)

                    Group {
                        HelpSection(icon: "theatermasks.fill", iconColor: Color(hex: "C084FC"), title: "Presentation & Script") {
                            presentationSection
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

                        HelpSection(icon: "mic.fill", iconColor: VaultTheme.Colors.warning, title: "During the Show") {
                            duringShow
                        }

                        divider

                        HelpSection(icon: "lightbulb.fill", iconColor: Color(hex: "F472B6"), title: "Tips") {
                            tipsSection
                        }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)

                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }

            // Top bar
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
            .background(VaultTheme.Colors.background.shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4))
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
            Text("The people a room chooses to follow — and the people who follow them — add up to exactly where we are in time.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VaultTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - Mode Selector

    private var modeSelectorBar: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Select mode to view its guide")
                .font(VaultTheme.Typography.captionSmall())
                .foregroundColor(VaultTheme.Colors.textTertiary)
            HStack(spacing: 8) {
                ForEach(DateForceMode.allCases, id: \.rawValue) { mode in
                    let isSelected = selectedMode == mode
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode } }) {
                        HStack(spacing: 4) {
                            Text(mode == .auto ? "🤖" : "🎩")
                                .font(.system(size: 12))
                            Text(mode == .auto ? "Auto" : "Dual")
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                        .cornerRadius(20)
                    }
                }
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(VaultTheme.Colors.cardBorder)
            .frame(height: 1)
            .padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - Presentation & Script

    private var presentationSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {

            // Opening hook
            ShowStep(
                label: "THE HOOK  —  OPENING MONOLOGUE",
                labelColor: Color(hex: "C084FC"),
                steps: [
                    ShowStepItem(
                        action: "Start before touching the phone. Stand still. Let the room settle.",
                        dialogue: "\"I want to talk about something we all do every single day — but never think about. Following people.\""
                    ),
                    ShowStepItem(
                        action: "Pause. Let that land.",
                        dialogue: "\"Not following in the street. Following on Instagram. That small decision — tapping that button — means something. It means you chose that person. You said: this person matters to me. Their life is worth a piece of mine.\""
                    ),
                    ShowStepItem(
                        action: "Build slowly. Look at the audience.",
                        dialogue: "\"And the people who follow YOU — they made the same choice about you. They looked at your life and said: yes. I want this. That's not nothing. That is a quiet kind of trust.\""
                    ),
                    ShowStepItem(
                        action: "Let a beat of silence breathe.",
                        dialogue: "\"What I've come to believe — and what I want to show you tonight — is that those choices carry weight. Real, measurable weight. And when you add them all up across a room full of people... they tell us something extraordinary.\""
                    )
                ]
            )

            // The ask (Auto mode: follow the magician)
            if selectedMode == .auto {
                ShowStep(
                    label: "THE INVITATION  —  AUTO MODE",
                    labelColor: VaultTheme.Colors.primary,
                    steps: [
                        ShowStepItem(
                            action: "Take out your phone. Hold it visible but don't open anything yet.",
                            dialogue: "\"I'm going to need your help. Everyone take out your phone and open Instagram.\""
                        ),
                        ShowStepItem(
                            action: "Wait while they do it. Don't rush.",
                            dialogue: "\"Now search for me.\" [say your username clearly] \"And follow me. Right now, in this room. You're going to be part of this.\""
                        ),
                        ShowStepItem(
                            action: "Once most have followed, casually tap the 'Followed by' area in Performance — the app begins capturing silently in the background. The audience has no idea.",
                            dialogue: "\"Good. Don't close Instagram — you'll need it in a moment. Keep it open on your own profile.\""
                        ),
                        ShowStepItem(
                            action: "The loading takes 8–20 seconds depending on how many spectators. Use every second of it for the presentation below. You are building drama while the app works invisibly.",
                            dialogue: nil
                        )
                    ]
                )
            }

            // The justification of followers vs following
            ShowStep(
                label: "THE JUSTIFICATION  —  TWO KINDS OF CONNECTION",
                labelColor: Color.blue,
                steps: [
                    ShowStepItem(
                        action: "Split the room visually. Point left, then right.",
                        dialogue: "\"I want to separate you into two groups for a moment. Those on my left — and those on my right.\""
                    ),
                    ShowStepItem(
                        action: "Address the left group (date group — their followers).",
                        dialogue: "\"The people on my left represent one side of the equation: the people who chose you. Your followers. The ones who looked at your life and decided it was worth watching. That number is a measure of your reach — your presence in the world.\""
                    ),
                    ShowStepItem(
                        action: "Address the right group (time group — their following).",
                        dialogue: "\"And those on my right — you represent the other side. The people you chose. Who you follow. The people you let into your daily life without them even knowing. That number is a measure of your curiosity. Your hunger. What you care about.\""
                    ),
                    ShowStepItem(
                        action: "Bring the two ideas together.",
                        dialogue: "\"Two different directions of the same connection. Who comes to you. And who you go to. And I believe — I genuinely believe — that together, in this room, at this exact moment... those two numbers know something we don't.\""
                    )
                ]
            )

            // The number collection
            ShowStep(
                label: "COLLECTING THE NUMBERS  —  THE RITUAL",
                labelColor: VaultTheme.Colors.warning,
                steps: [
                    ShowStepItem(
                        action: "Address the left group first. Everyone has Instagram open already.",
                        dialogue: "\"Everyone on my left — look at your profile. Not who you follow. The other number. How many people follow YOU. Say it out loud.\""
                    ),
                    ShowStepItem(
                        action: "Write each number on a notepad or board as they say it. Make it theatrical — take your time.",
                        dialogue: "\"[Name]: 1,240. [Name]: 873. And you? 512. Perfect.\""
                    ),
                    ShowStepItem(
                        action: "Add them publicly with a slow, deliberate voice.",
                        dialogue: "\"1,240 plus 873 plus 512. Together... 2,625. That is the combined reach of your group. The sum of everyone who chose you. Remember that number.\""
                    ),
                    ShowStepItem(
                        action: "Now address the right group. Same energy.",
                        dialogue: "\"And the other side. Everyone on my right — different question. How many people do YOU follow? The people you chose.\""
                    ),
                    ShowStepItem(
                        action: "Collect and write their following counts.",
                        dialogue: "\"[Name]: 347. [Name]: 512. And you? 190. Good.\""
                    ),
                    ShowStepItem(
                        action: "Add them.",
                        dialogue: "\"347 plus 512 plus 190. Together... 1,049. The collective reach of your curiosity. Hold that number too.\""
                    )
                ]
            )

            // The Explore justification
            ShowStep(
                label: "THE STRANGER  —  JUSTIFYING EXPLORE",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    ShowStepItem(
                        action: "Build the reason why you use a stranger. This is the moment that makes the effect feel inevitable rather than engineered.",
                        dialogue: "\"Now here's the thing. If I chose the profile — you'd wonder. If you chose someone you know — it wouldn't be fair. What we need is someone completely outside this room. Someone the algorithm found for us. A stranger that none of us invited.\""
                    ),
                    ShowStepItem(
                        action: "Hand the phone to someone who has not participated at all — ideally someone who didn't follow you and didn't give a number.",
                        dialogue: "\"You haven't been part of this yet. I want you to open Instagram Explore — that's the search tab, with the magnifying glass. You'll see posts from people you've never met, chosen by the algorithm. Scroll for as long as you want. When one catches your eye — stop. Don't think. Just stop.\""
                    ),
                    ShowStepItem(
                        action: "Let them scroll freely. Say nothing. Let the silence do the work.",
                        dialogue: nil
                    ),
                    ShowStepItem(
                        action: "When they tap a post, take back the phone naturally and show the screen to the room.",
                        dialogue: "\"A complete stranger. Someone none of us know. The algorithm found them. And look — they have followers. And they follow people. Just like all of us.\""
                    )
                ]
            )

            // The revelation setup
            ShowStep(
                label: "THE REVELATION  —  BUILDING TO THE MOMENT",
                labelColor: VaultTheme.Colors.error,
                steps: [
                    ShowStepItem(
                        action: "Slow everything down. Look between the screen and the audience.",
                        dialogue: "\"Remember the first number? The sum of everyone who follows your group — 2,625. Now look at this stranger. They have... [read the forced followers number]. 5,227 followers.\""
                    ),
                    ShowStepItem(
                        action: "Do the subtraction slowly, out loud.",
                        dialogue: "\"5,227... minus 2,625... that gives us... 2,602. Four digits. 26 — 02. The 26th of February. Someone check their phone. What is today's date?\""
                    ),
                    ShowStepItem(action: "Pause. Don't smile. Let them react first.", dialogue: nil),
                    ShowStepItem(
                        action: "Then the time.",
                        dialogue: "\"And the second number — 1,049. The people your group follows. This stranger follows... [read the forced following number]. 2,349 people. 2,349 minus 1,049... 1,300. Thirteen hundred. 13:00. Someone tell me the time right now.\""
                    ),
                    ShowStepItem(
                        action: "Let the room erupt. Then close slowly.",
                        dialogue: "\"The people who chose you. The people you chose. A stranger found by a machine. And together — without planning, without preparation, without any of you knowing what the others would say — you just told us exactly when and where we are. That's not technology. That's not math. That's something much older than both.\""
                    )
                ]
            )
        }
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            switch selectedMode {
            case .auto:
                BodyText("The app silently fetches your latest followers via the Instagram API. It reads two numbers from each person's profile:")
                MetricRow(icon: "person.2.fill", color: .blue, label: "Followers count", description: "How many people follow that spectator → used for the **date** group")
                MetricRow(icon: "person.crop.circle.badge.plus", color: .orange, label: "Following count", description: "How many people that spectator follows → used for the **time** group")
                BodyText("The first half of captured spectators form the date group. The second half form the time group. Each Explore post then shows forced numbers: **followers = today's date + sum(date group's follower counts)**, **following = current time + sum(time group's following counts)**.")

            case .dual:
                BodyText("The magician manually visits each spectator's profile in Explore. When the profile is closed, it registers automatically. The app reads the same two numbers:")
                MetricRow(icon: "person.2.fill", color: .blue, label: "Followers count", description: "How many people follow that spectator → date group")
                MetricRow(icon: "person.crop.circle.badge.plus", color: .orange, label: "Following count", description: "How many people that spectator follows → time group")
                BodyText("Register an even number of spectators. The app splits them in half: first half → 📅 date, second half → 🕐 time. Both Auto and Dual use the **same math** — the only difference is *who does the work*.")
                InfoBox(text: "Auto and Dual produce identical results. Auto is faster and more discreet. Dual gives the magician more control over which profiles are used.")
            }
        }
    }

    // MARK: - Before the Show

    private var beforeShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            switch selectedMode {
            case .auto:
                NumberedStep(number: 1, text: "Enable **Date Force** in Settings.")
                NumberedStep(number: 2, text: "Select **Auto** mode.")
                NumberedStep(number: 3, text: "Choose how many spectators to capture: **2, 4, 6 or 8**. The app will split them equally between date and time groups.")
                NumberedStep(number: 4, text: "Set a **date format** (DD/MM or MM/DD) and a **time offset** if needed.")
                NumberedStep(number: 5, text: "During the show, ask the audience to **follow you on Instagram**. Once they do, enter Performance and tap the 'Followed by' area to start the capture.")

            case .dual:
                NumberedStep(number: 1, text: "Enable **Date Force** in Settings.")
                NumberedStep(number: 2, text: "Select **Dual** mode.")
                NumberedStep(number: 3, text: "Choose your **date format** and optional **time offset**.")
                NumberedStep(number: 4, text: "In Performance, go to Explore and **open each spectator's profile**. Close it to register them. Register an **even total** of spectators.")
                NumberedStep(number: 5, text: "Tap the profile picture while on a profile to **cancel** that registration if you made a mistake.")
            }
        }
    }

    // MARK: - During the Show

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            switch selectedMode {

            case .auto:
                ShowStep(
                    label: "SETUP",
                    labelColor: VaultTheme.Colors.primary,
                    steps: [
                        ShowStepItem(
                            action: "Ask the audience to follow you on Instagram right now.",
                            dialogue: "\"Before we start — open Instagram and follow me. Ten seconds, that's all. You'll be part of something.\""
                        ),
                        ShowStepItem(
                            action: "Wait a moment. Enter Performance and tap the 'Followed by' area once.",
                            dialogue: nil
                        ),
                        ShowStepItem(
                            action: "The app silently fetches the latest followers. Names appear one by one as they load — ~1 to 2 seconds per person. With 4 spectators expect roughly 8–12 seconds total. Use this time to build anticipation.",
                            dialogue: nil
                        ),
                        ShowStepItem(
                            action: "The last name of the date group shows a subtle dash after it. Only you know what it marks. Tap again to toggle between date group and time group names.",
                            dialogue: nil
                        )
                    ]
                )

                ShowStep(
                    label: "DATE GROUP  —  AUTO",
                    labelColor: Color.blue,
                    steps: [
                        ShowStepItem(
                            action: "Address the first half of captured names. Ask each person to open Instagram, go to their profile, and read how many followers they have.",
                            dialogue: "\"María, Carlos — you two. Open Instagram. How many people follow you? Read it out loud.\""
                        ),
                        ShowStepItem(
                            action: "Guide the audience through the addition.",
                            dialogue: "\"1,240 plus 873. Together, the people who follow you: 2,113. Write that down.\""
                        )
                    ]
                )

                ShowStep(
                    label: "TIME GROUP  —  AUTO",
                    labelColor: Color.orange,
                    steps: [
                        ShowStepItem(
                            action: "Address the second half. Ask how many people they follow.",
                            dialogue: "\"Pedro, Ana — same thing. But this time: how many people do YOU follow?\""
                        ),
                        ShowStepItem(
                            action: "Sum their following counts.",
                            dialogue: "\"347 plus 512. The people you follow together: 859.\""
                        )
                    ]
                )

            case .dual:
                ShowStep(
                    label: "REGISTERING SPECTATORS  —  DUAL",
                    labelColor: VaultTheme.Colors.primary,
                    steps: [
                        ShowStepItem(
                            action: "In Explore, search for the first spectator and open their profile. Close it — they are registered automatically.",
                            dialogue: nil
                        ),
                        ShowStepItem(
                            action: "Repeat for all spectators. Register an even number total.",
                            dialogue: nil
                        ),
                        ShowStepItem(
                            action: "If you open the wrong profile, tap the profile picture to cancel it before closing.",
                            dialogue: nil
                        )
                    ]
                )

                ShowStep(
                    label: "DATE GROUP  —  DUAL",
                    labelColor: Color.blue,
                    steps: [
                        ShowStepItem(
                            action: "Address the first half of spectators. Ask each to open their own profile and read how many followers they have.",
                            dialogue: "\"María, Carlos — open your Instagram profile. How many people follow you? Read it aloud.\""
                        ),
                        ShowStepItem(
                            action: "Add the numbers publicly.",
                            dialogue: "\"1,240 plus 873. The people who follow you together: 2,113. Hold that number.\""
                        )
                    ]
                )

                ShowStep(
                    label: "TIME GROUP  —  DUAL",
                    labelColor: Color.orange,
                    steps: [
                        ShowStepItem(
                            action: "Address the second half. Ask how many people they follow.",
                            dialogue: "\"Pedro, Ana — different question. How many people do YOU follow on Instagram?\""
                        ),
                        ShowStepItem(
                            action: "Sum their following counts.",
                            dialogue: "\"347 plus 512. Together: 859.\""
                        )
                    ]
                )
            }

            // Shared: free choice + revelation
            ShowStep(
                label: "THE FREE CHOICE",
                labelColor: VaultTheme.Colors.warning,
                steps: [
                    ShowStepItem(
                        action: "Hand the phone to someone who has not participated. Explore is open.",
                        dialogue: "\"This is Instagram Explore — people from all over the world you have never met. Scroll through. When one catches your eye, tap it. Completely your choice.\""
                    ),
                    ShowStepItem(
                        action: "They tap freely. The forced numbers appear below the username.",
                        dialogue: "\"Look at this person. A complete stranger. They have 5,126 followers — and they follow 2,322 people.\""
                    )
                ]
            )

            ShowStep(
                label: "THE REVELATION",
                labelColor: VaultTheme.Colors.success,
                steps: [
                    ShowStepItem(
                        action: "Reveal the date using the followers number.",
                        dialogue: "\"The people who follow your group combined: 2,113. This stranger has 5,126 followers. 5,126 minus 2,113... 3,013. Four digits: 28 — 02. The 28th of February. What is today's date?\""
                    ),
                    ShowStepItem(action: "Pause. Let it land.", dialogue: nil),
                    ShowStepItem(
                        action: "Reveal the time using the following number.",
                        dialogue: "\"And the people your second group follows together: 859. This stranger follows 2,322 people. 2,322 minus 859... 1,463. Someone check the time right now.\""
                    ),
                    ShowStepItem(
                        action: "Close on the idea.",
                        dialogue: "\"The people who follow you. The people you follow. Two different choices, made privately over years. And together they told us exactly when and where we are. That's not a trick. That's connection.\""
                    )
                ]
            )
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            switch selectedMode {
            case .auto:
                TipRow(icon: "clock.fill", color: VaultTheme.Colors.warning,
                       text: "**Loading time.** Each follower takes ~1–2 seconds to load. 4 spectators ≈ 6–10 s. 8 spectators ≈ 12–20 s. Use this time to build anticipation with the audience.")

                TipRow(icon: "minus", color: VaultTheme.Colors.textTertiary,
                       text: "**Group marker.** During loading, the last person of the date group shows a dash after their name. Only you see its meaning.")

                TipRow(icon: "arrow.left.arrow.right", color: VaultTheme.Colors.primary,
                       text: "**Toggle display.** Once loaded, tap the 'Followed by' area again to switch between showing date group names and time group names.")

                TipRow(icon: "arrow.counterclockwise", color: VaultTheme.Colors.secondary,
                       text: "**Auto reset.** Spectators are cleared automatically after the Explore post is closed, so the effect is ready to repeat.")

            case .dual:
                TipRow(icon: "xmark.circle.fill", color: VaultTheme.Colors.error,
                       text: "**Wrong profile?** Tap the profile picture while you are on their profile to cancel. They will not be registered when you close it.")

                TipRow(icon: "number.circle.fill", color: VaultTheme.Colors.primary,
                       text: "**Register an even number.** The split is always half/half. If you register an odd number, the date group gets one less than the time group.")

                TipRow(icon: "arrow.counterclockwise", color: VaultTheme.Colors.secondary,
                       text: "**Auto reset.** Spectators clear automatically after the Explore post is closed.")
            }

            TipRow(icon: "clock.badge.exclamationmark.fill", color: VaultTheme.Colors.warning,
                   text: "**Time offset.** If the reveal happens a few minutes after you start, set the offset to +2 or +3 min so the time on stage matches the real clock.")

            TipRow(icon: "person.fill.questionmark", color: VaultTheme.Colors.textSecondary,
                   text: "**Private profiles.** Both follower and following counts are still visible publicly. No issues.")

            TipRow(icon: "checkmark.shield.fill", color: VaultTheme.Colors.success,
                   text: "**The audience can verify.** Each spectator can open Instagram on their own phone and confirm their follower/following counts match what you read aloud.")
        }
    }
}

// MARK: - Reusable Components

private struct HelpSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let content: Content

    init(icon: String, iconColor: Color, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
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

private struct MetricRow: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(description)
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VaultTheme.Spacing.sm)
        .background(color.opacity(0.06))
        .cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

private struct BodyText: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(VaultTheme.Typography.body())
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
    let text: LocalizedStringKey
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
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
            .stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1))
    }
}

private struct ShowStepItem {
    let action: LocalizedStringKey
    let dialogue: LocalizedStringKey?
}

private struct ShowStep: View {
    let label: LocalizedStringKey
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
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
            .stroke(labelColor.opacity(0.2), lineWidth: 1))
    }
}

private struct DialogueBox: View {
    let text: LocalizedStringKey
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .cornerRadius(1)
            Text(text)
                .font(.system(size: 13, weight: .regular))
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
