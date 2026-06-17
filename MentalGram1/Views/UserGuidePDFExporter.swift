import SwiftUI
import UIKit
import Combine

// MARK: - PDF Exporter

@MainActor
final class UserGuidePDFExporter: ObservableObject {
    @Published var isExporting = false

    private let pageWidth: CGFloat  = 595.28
    private let pageHeight: CGFloat = 841.89
    private let renderScale: CGFloat = 2.0

    func export() async -> URL? {
        isExporting = true
        defer { isExporting = false }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultUserGuide.pdf")

        let pages = UserGuidePDFPages.make()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        for index in pages.indices {
            let pageView = UserGuidePDFPageView(
                page: pages[index],
                pageNumber: index + 1,
                pageCount: pages.count
            )
            .frame(width: pageWidth, height: pageHeight)
            .background(Color.white)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: pageView)
            renderer.scale = renderScale
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: pageHeight)

            renderer.render { _, draw in
                pdfContext.beginPDFPage(nil)

                pdfContext.saveGState()
                pdfContext.setFillColor(UIColor.white.cgColor)
                pdfContext.fill(mediaBox)
                pdfContext.clip(to: mediaBox)
                draw(pdfContext)
                pdfContext.restoreGState()

                pdfContext.endPDFPage()
            }
        }

        pdfContext.closePDF()

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - Professional paginated PDF

private struct UserGuidePDFPageData {
    let chapter: String
    let title: String
    let subtitle: String?
    let color: Color
    let blocks: [UserGuidePDFBlock]
}

private enum UserGuidePDFBlock {
    case paragraph(String)
    case heading(String)
    case bullets([String])
    case callout(String)
    case table(headers: [String], rows: [[String]])
    case frames(PDFVisual, String)
}

private enum UserGuidePDFPages {
    static func make() -> [UserGuidePDFPageData] {
        let blue = Color(hex: "0A84FF")
        let purple = Color(hex: "BF5AF2")
        let orange = Color(hex: "FF9F0A")
        let green = Color(hex: "16A34A")
        let indigo = Color(hex: "6366F1")
        let slate = Color(hex: "94A3B8")

        func L(_ key: String, _ fallback: String) -> String {
            let localized = String(localized: String.LocalizationValue(key))
            return localized == key ? fallback : localized
        }

        return [
            UserGuidePDFPageData(
                chapter: "VAULT",
                title: L("guide.pdf.cover.subtitle", "User Guide"),
                subtitle: DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none),
                color: green,
                blocks: [
                    .paragraph("A complete performance reference for Vault: real Instagram automation, hidden input methods, profile reveals, forces, predictions and camouflage tools."),
                    .heading("Included sections"),
                    .bullets([
                        "Getting Started and Performance",
                        "Limits & Safety",
                        "Input Methods with visual frame sequences",
                        "Post Prediction and set types",
                        "Profile Picture, Note and Biography",
                        "Force Post, Force Reel, Counter Glitch and Date Force",
                        "Performance Cover, Lockscreen Input and Amnesia Carousel"
                    ]),
                    .callout("This PDF is generated in the current device language when translations exist in the app."),
                    .heading("⚠ Before you start"),
                    .callout("This PDF is a condensed quick-reference guide. For full step-by-step instructions with interactive demos and animations, use the User Guide inside the app or watch the tutorial video. The in-app guide is always the most complete and up-to-date source.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: L("guide.section.getting_started", "GETTING STARTED"),
                title: L("guide.introduction.title", "What is Vault?"),
                subtitle: "Hybrid app · Real account · Real results",
                color: blue,
                blocks: [
                    .paragraph("Vault connects directly to your real Instagram account — no separate profile, no special audience and no visible setup required. Everything you perform happens on the same account your spectators already follow."),
                    .heading("How it works"),
                    .bullets([
                        "Upload, archive and unarchive photos at the exact moment you choose.",
                        "Change your profile photo, note or biography in real time.",
                        "Read followers/following counts and metadata for forces.",
                        "Show a convincing Instagram interface while Vault works invisibly."
                    ]),
                    .heading("Three pillars"),
                    .table(headers: ["Pillar", "Use"], rows: [
                        ["Forces", "Force Post · Force Reel · Date Force · Counter Glitch"],
                        ["Predictions", "Post Prediction · Playing Cards · List Set · Custom Set"],
                        ["Profile reveals", "Profile Picture · Note · Biography"]
                    ]),
                    .callout("The spectator verifies the result on real Instagram, not inside a magic app.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "GETTING STARTED",
                title: "Performance",
                subtitle: "The Instagram emulator",
                color: blue,
                blocks: [
                    .paragraph(L("perf.help.overview.body1", "Performance is a built-in Instagram emulator. It looks and feels like the real Instagram app, but it runs inside Vault and is directly connected to your Instagram account through the official API.")),
                    .callout(L("perf.help.overview.infobox", "Everything the spectator sees is real Instagram content from your actual account — posts, followers, reels — pulled live from the API. It is not a simulation; it is your real profile.")),
                    .heading("Navigation"),
                    .bullets([
                        "Tap the + button in the top-left header to return to Settings.",
                        "Use Posts, Reels and Tagged tabs like the real Instagram profile.",
                        "Tap the Search icon to open Explore and search any real profile.",
                        "Pull to refresh when you need fresh Instagram data."
                    ]),
                    .heading("Real Instagram data"),
                    .bullets([
                        "Photos and videos are loaded live.",
                        "Follower/following counts are real and can be manipulated for effects.",
                        "Biography, note and profile picture updates appear on the real account."
                    ]),
                    .frames(.forceReel, "Explore can become the reveal moment when Force Reel is active.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Settings Overview",
                subtitle: "Where the main tools live before performance",
                color: orange,
                blocks: [
                    .paragraph("Use Settings before the show. Prepare profile reveals, sets, forces, integrations and camouflage here; Performance is where the spectator sees Instagram."),
                    .frames(.settingsOverview, "Frames: Settings dashboard → profile tools → tricks → camouflage and community."),
                    .callout("The + button inside Performance returns to Settings if you need to adjust something before the effect.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "GETTING STARTED",
                title: L("limits.help.title", "Limits & Safety"),
                subtitle: "API budget, cache and recovery",
                color: blue,
                blocks: [
                    .paragraph(L("limits.help.calm.body", "Instagram occasionally shows a brief warning asking you to confirm it's you. This is normal for apps connected to the platform and has nothing to do with a ban.")),
                    .heading("55-action hourly budget"),
                    .table(headers: ["Feature", "First time", "Repeat"], rows: [
                        ["Open Performance", "3–5", "0–5"],
                        ["Followers list", "1", "0"],
                        ["New follower profile", "3–4", "0 cached"],
                        ["Profile picture", "1", "1"],
                        ["Sync & Archive", "2/photo", "—"],
                        ["Upload", "1/photo", "—"],
                        ["Reveal", "1/photo", "—"],
                        ["Note or Bio", "1", "1"],
                        ["Explore/Search", "1–2", "0 cached"]
                    ]),
                    .callout("Safe: >20 actions · Low: 8–20 · Critical: <8. At 55 actions Vault stops silently until the rolling window renews.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "GETTING STARTED",
                title: "Limits & Safety — Live Handling",
                subtitle: nil,
                color: blue,
                blocks: [
                    .heading("Safe rehearsal"),
                    .bullets([
                        "Open the same follower profile once; it is cached for days.",
                        "Spread Sync & Archive and uploads across different hours.",
                        "Do not open many new profiles in a row during testing.",
                        "Do not restart the app repeatedly while testing."
                    ]),
                    .heading("If Instagram shows a warning"),
                    .bullets([
                        "Open the official Instagram app and tap Dismiss.",
                        "Complete email/SMS verification if requested.",
                        "Log out in Vault, wait about a minute and log in again."
                    ]),
                    .heading("During a live show"),
                    .paragraph("Vault hides technical errors behind a generic No Internet screen. Use it as cover: Instagram is glitching for a second."),
                    .callout("Your account will not be banned. Instagram may only ask to confirm your identity.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: L("input.guide.section.label", "INPUT METHODS"),
                title: L("input.guide.title", "Input Methods"),
                subtitle: L("input.guide.subtitle", "Every way Vault captures what the spectator chose — without them noticing"),
                color: purple,
                blocks: [
                    .paragraph(L("input.guide.intro.body", "An input method is the secret interface used to send a word, number, card, photo action, note, biography, profile picture change or automation command into Vault.")),
                    .table(headers: ["Set", "Methods"], rows: [
                        ["Words", L("input.guide.compat.word.methods", "Cover Typing · Camera (OCR) · API")],
                        ["Numbers", L("input.guide.compat.number.methods", "Digit Grid · Number Clock · Number Lockscreen · Camera (OCR) · API")],
                        ["Cards", L("input.guide.compat.card.methods", "Card Clock · Numpad Card · Card Lockscreen · Camera (OCR) · API")]
                    ]),
                    .heading(L("input.guide.covertyping.title", "Cover Typing")),
                    .paragraph(L("input.guide.covertyping.body", "You secretly type the spectator's chosen word into the Explore search bar. A different decoy word is shown on screen.")),
                    .heading(L("input.guide.ocr.title", "Camera (OCR)")),
                    .paragraph(L("input.guide.ocr.body", "The rear camera silently reads text in the frame and sends the result automatically."))
                ]
            ),

            UserGuidePDFPageData(
                chapter: "INPUT METHODS",
                title: L("input.guide.digitgrid.title", "Digit Grid"),
                subtitle: L("input.guide.digitgrid.compat", "Number · Custom sets"),
                color: purple,
                blocks: [
                    .paragraph(L("input.guide.digitgrid.body", "The fake Instagram grid acts as a hidden keypad. The visible cells map to 1-9, and the last row acts as 0.")),
                    .callout(L("input.guide.digitgrid.activate", "While the fake Instagram profile is visible, swipe horizontally across the grid rows to encode each digit. The following count updates with each swipe. Long press to confirm.")),
                    .frames(.digitGrid, "Frame sequence: normal grid → hidden digit selection → following counter preview."),
                    .heading("Confirmation by feature"),
                    .bullets([
                        "Post Prediction: long press or Posts icon confirms.",
                        "Force Reel: opening Explore locks the pending number.",
                        "Counter Glitch: Followers/Following or Explore captures the counter offset."
                    ])
                ]
            ),

            UserGuidePDFPageData(
                chapter: "INPUT METHODS",
                title: L("input.guide.clock.title", "Number Clock"),
                subtitle: "Black screen numeric input",
                color: slate,
                blocks: [
                    .paragraph(L("input.guide.clock.body", "A completely black fullscreen screen — as if the phone is off. Swipe gestures encode digits 0–9 using pairs of directional swipes.")),
                    .table(headers: ["Digit", "Swipes", "Digit", "Swipes"], rows: [
                        ["0", "↑↑", "5", "↓→"],
                        ["1", "↑→", "6", "↓↓"],
                        ["2", "→↑", "7", "↓←"],
                        ["3", "→→", "8", "←↓"],
                        ["4", "→↓", "9", "←←"]
                    ]),
                    .frames(.blackClock, "Frames: black screen → swipe pair → hidden value → wait 3 seconds to confirm."),
                    .callout(L("input.guide.clock.activate", "Stop swiping for 3 seconds to confirm and fire the reveal. Tap anywhere after confirmation to dismiss the black screen."))
                ]
            ),

            UserGuidePDFPageData(
                chapter: "INPUT METHODS",
                title: L("input.guide.cardclock.title", "Card Clock"),
                subtitle: "3 swipes total",
                color: green,
                blocks: [
                    .paragraph(L("input.guide.cardclock.body", "Exactly 3 swipes are required: the first 2 encode the card value and the 3rd is a single swipe for the suit.")),
                    .table(headers: ["Value", "Swipes", "Value", "Swipes"], rows: [
                        ["A", "↑→", "8", "←↓"],
                        ["2", "→↑", "9", "←←"],
                        ["3", "→→", "10", "↑←"],
                        ["4", "→↓", "J", "←↑"],
                        ["5", "↓→", "Q", "↑↑"],
                        ["6", "↓↓", "K", "↑↓"],
                        ["7", "↓←", "", ""]
                    ]),
                    .table(headers: ["Suit", "Swipe", "Suit", "Swipe"], rows: [
                        ["♠", "↑", "♥", "→"],
                        ["♣", "↓", "♦", "←"]
                    ]),
                    .frames(.cardClock, "Frames: black screen → value pair → suit swipe → completed card.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "INPUT METHODS",
                title: "Lockscreen, Numpad Card, API and URL",
                subtitle: nil,
                color: indigo,
                blocks: [
                    .heading(L("input.guide.lockscreen.title", "Number Lockscreen")),
                    .paragraph(L("input.guide.lockscreen.body", "Vault shows a fake iPhone lock screen with a standard PIN keypad. You type the secret number first; spectator taps are ignored.")),
                    .frames(.lockscreen, "Frames: empty lockscreen → secret digits → spectator taps → Performance opens."),
                    .heading(L("input.guide.numpadcard.title", "Numpad Card")),
                    .paragraph(L("input.guide.numpadcard.body", "A black fullscreen input for playing cards. Tap anywhere to reveal a private card pad, choose value and suit, then it closes automatically.")),
                    .heading(L("input.guide.urlscheme.title", "URL Scheme")),
                    .paragraph("vault://reveal?word=MAGIC · vault://reveal?slot=15 · vault://reveal?card=J♠ · vault://bio?text=Now · vault://note?text1=hello · vault://profilepic")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "POST PREDICTION",
                title: L("postpred.help.hero.title", "The Image Prediction"),
                subtitle: L("postpred.help.hero.body", "A selected image appears on your Instagram profile — in its exact original position, with its original date."),
                color: purple,
                blocks: [
                    .paragraph(L("postpred.help.howitworks.archive_reason", "Instagram does not let you upload a new photo and backdate it. Vault uploads prediction images in advance and archives them immediately.")),
                    .heading("How it works"),
                    .bullets([
                        L("postpred.help.howitworks.step1", "Prepare your Set — upload photos in advance and let the app archive them automatically."),
                        L("postpred.help.howitworks.step2", "The spectator freely picks a word, number, image, or card."),
                        L("postpred.help.howitworks.step3", "Trigger the reveal. The matching photo reappears on real Instagram.")
                    ]),
                    .callout(L("postpred.help.howitworks.info", "The spectator sees a real post on a real Instagram profile."))
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Set Card & Input Selector",
                subtitle: "How the active set is prepared",
                color: purple,
                blocks: [
                    .paragraph("Each prediction set has its own card. Upload/archive media, mark the set active and choose the input method directly from that set card."),
                    .frames(.setCardConfig, "Frames: set card → active/uploaded state → input picker → configure button."),
                    .callout("This visual is important: the input method belongs to the set card, not to a separate global toggle.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "POST PREDICTION",
                title: L("postpred.help.section.settypes", "Set Types"),
                subtitle: nil,
                color: purple,
                blocks: [
                    .table(headers: ["Type", "Use"], rows: [
                        ["Word Reveal", L("postpred.help.settype.word.desc", "26 slots (A–Z) × N banks.")],
                        ["Number Reveal", L("postpred.help.settype.number.desc", "10 slots (0–9) × N banks.")],
                        ["Custom Set", L("postpred.help.settype.custom.desc", "1–100 custom images, 1 bank.")],
                        ["Playing Cards", L("postpred.help.settype.card.desc", "52 slots (A–K × suits), 1 bank.")],
                        ["List Set", "Private named choices from a visible list, importable from TXT/CSV."]
                    ]),
                    .heading("Banks"),
                    .paragraph(L("postpred.help.metric.banks.desc", "Each bank = one position in the word or number. Bank 1 → first letter/digit, Bank 2 → second, and so on.")),
                    .heading("Video slots"),
                    .paragraph("Playing Cards and Custom sets support videos. Upload via real Instagram, map the video to a slot, then reveal in Performance.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "POST PREDICTION",
                title: "Before and During the Show",
                subtitle: nil,
                color: purple,
                blocks: [
                    .heading(L("postpred.help.section.before", "Before the Show")),
                    .bullets([
                        L("postpred.help.before.1", "Create a Set in the Sets section."),
                        L("postpred.help.before.2", "Upload the images and wait for them to be automatically archived."),
                        L("postpred.help.before.3", "Do not use the app, change networks or interrupt upload."),
                        L("postpred.help.before.4", "Mark the set active and select its input method.")
                    ]),
                    .heading(L("postpred.help.section.during", "During the Show")),
                    .bullets([
                        L("postpred.help.during.invite.action", "Ask the spectator to freely think of a word, number or letter."),
                        L("postpred.help.during.input.action", "Capture the input silently."),
                        L("postpred.help.during.reveal.action", "The app unarchives the matching photo."),
                        L("postpred.help.during.timing.action", "When the app vibrates, the reveal is live on real Instagram.")
                    ]),
                    .callout(L("postpred.help.tip.fakeapp", "Fake profile = instant preview, real Instagram = after vibration."))
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Post Prediction Setup",
                subtitle: "Upload, archive, activate, reveal",
                color: purple,
                blocks: [
                    .paragraph("The strongest image prediction requires preparation: media is uploaded, archived, then later unarchived at the exact reveal moment."),
                    .frames(.postPredictionSetup, "Frames: create set → upload/archive → active set → orange ring when live on Instagram."),
                    .callout("In the fake profile the preview can appear instantly. Real Instagram is safe to show only after vibration/orange ring confirmation.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "INSTAGRAM PROFILE",
                title: "Profile Picture · Note · Biography",
                subtitle: "Real profile reveals",
                color: orange,
                blocks: [
                    .heading("Profile Picture"),
                    .paragraph("Change your Instagram profile photo automatically to match the spectator's prediction. Use vault://profilepic or the most recent gallery photo on Performance open."),
                    .heading("Note"),
                    .paragraph("Post a note above your profile picture for 24 hours. Supports API, URL Scheme, OCR, Lockscreen, Clock and Numpad Card inputs."),
                    .heading("Biography"),
                    .paragraph("Update your Instagram bio permanently until changed. Supports templates T1–T4 and placeholders {text1}, {text2}, {text3}. Enable Acrostic Mode to transform a received word into a poem (e.g. VASO → Viento / Árbol / Sol / Origen)."),
                    .frames(.profileConfirm, "Frames: fake app preview → upload/update → double vibration → orange ring confirmation."),
                    .callout("Wait for double vibration + orange ring before showing the spectator real Instagram.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Profile Picture Settings",
                subtitle: "Prediction photo before Performance",
                color: orange,
                blocks: [
                    .paragraph("Profile Picture can be triggered by URL Scheme or by uploading the latest gallery photo when Performance opens."),
                    .frames(.profileSettings, "Frames: profile picture card → latest photo source → auto on Performance open → orange ring confirmation."),
                    .callout("Use a square 1:1 image so Instagram's circular crop looks clean.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Note Configuration",
                subtitle: "Template + input source",
                color: Color(hex: "30D158"),
                blocks: [
                    .paragraph("Notes use a text template. Values captured by OCR, API, URL Scheme, Lockscreen, Clock or Numpad Card fill placeholders such as {text1}."),
                    .frames(.noteConfig, "Frames: note template → input source → Send Note / automatic update → confirmation."),
                    .callout("Keep notes short: Instagram Notes are limited to 60 characters.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "VISUAL SETUP",
                title: "Biography Configuration",
                subtitle: "T1–T4 templates, placeholders and Acrostic Mode",
                color: orange,
                blocks: [
                    .paragraph("Biography uses templates and placeholders just like Notes, but it stays on the Instagram profile until changed. It supports four independent slots (T1–T4) and a built-in Acrostic Mode."),
                    .frames(.biographyConfig, "Frames: template tabs → placeholder text → input source → Acrostic Mode toggle → Update Biography."),
                    .heading("Acrostic Mode"),
                    .paragraph("Enable the 'Acrostic Mode' toggle in the Biography card. When a single word or code arrives via API, OCR or URL Scheme, it is automatically converted before being sent to Instagram."),
                    .bullets([
                        "Each letter of the word → one line, starting with that letter.",
                        "Each digit → one 6-digit line starting with that digit.",
                        "Example: VASO → Viento / Árbol / Sol / Origen.",
                        "Mixed example: 3c → 356754 / Car. Number example: 123456 → 143553 / 265474 / 3xxxxx / 4xxxxx / 5xxxxx / 6xxxxx.",
                        "Repeated letters cycle through 3 different words (BANANA never repeats the same word).",
                        "Works in the device language — 17 languages supported.",
                        "Multi-word inputs are sent as-is (no transformation)."
                    ]),
                    .callout("Use T1 as your normal bio and T2/T3/T4 for prediction or reset versions. Acrostic Mode works per-send regardless of which slot is active.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "TRICKS",
                title: "Force Post",
                subtitle: "Force a scroll to stop on a specific post",
                color: purple,
                blocks: [
                    .paragraph("Before the show choose a post in Settings. During performance the spectator scrolls freely, but the app decelerates on your selected image."),
                    .heading("Setup"),
                    .bullets(["Enable Force Post.", "Search a profile.", "Select the forced post.", "Repeat for multiple profiles if needed."]),
                    .heading("During the show"),
                    .bullets(["Hand the phone to the spectator.", "They scroll freely.", "The force happens during deceleration.", "Reveal your prediction after the post stops."]),
                    .callout("One spectator scroll triggers one force. After that, scrolling continues normally.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "TRICKS",
                title: "Force Reel",
                subtitle: "Force a specific reel in Explore",
                color: indigo,
                blocks: [
                    .paragraph("Pick a reel and assign a position number. The spectator names a number; you secretly enter it with Digit Grid, then open Explore."),
                    .frames(.forceReel, "Frames: grid map → hidden dial → Explore grid counts to the forced reel."),
                    .heading("Tips"),
                    .bullets(["Prepare the reel beforehand.", "Use the Following counter as your private preview.", "Open Explore only after the number is correct."])
                ]
            ),

            UserGuidePDFPageData(
                chapter: "TRICKS",
                title: "Counter Glitch",
                subtitle: "Inflate and reveal a counter",
                color: purple,
                blocks: [
                    .paragraph("The spectator names a number. You register it secretly, open their profile, and the counter appears inflated. Press volume to glitch back to the real number."),
                    .frames(.counterGlitch, "Frames: register digits → inflated counter → volume glitch → spectator checks their real phone."),
                    .heading("Transfer Mode"),
                    .paragraph("First pulse deflates your counter; second pulse inflates the spectator's counter by the same amount."),
                    .heading("Large counters"),
                    .paragraph("Counter Glitch uses the exact number entered. During the glitch, Vault temporarily shows the full counter value so small changes remain visible even when Instagram would normally abbreviate the count.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "TRICKS",
                title: "Date Force",
                subtitle: "Followers/following reveal today's date and time",
                color: Color(hex: "60A5FA"),
                blocks: [
                    .paragraph("Select spectators from the followers list. Their followers/following counts encode date and time through two secret groups."),
                    .frames(.dateForce, "Frames: select followers → form date/time groups → Explore profile → reveal today's date."),
                    .heading("Know your audience"),
                    .bullets(["Large audience: ask public profiles to follow you.", "Small/all-private: accept requests first, then select participants.", "Tap avatar/story ring to select; tap again to deselect."]),
                    .callout("Choose DD/MM or MM/DD and optionally apply a minute offset.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "CAMOUFLAGE",
                title: "Performance Cover · Lockscreen Input",
                subtitle: "Make opening Vault look natural",
                color: green,
                blocks: [
                    .heading("Performance Cover"),
                    .paragraph("Choose what appears before Performance is revealed: Fake Home Screen shows your uploaded iPhone home screen screenshot; Fake Screen Off shows a pure black screen as if the phone were off. Tap anywhere to reveal the fake profile."),
                    .heading("Lockscreen Input"),
                    .paragraph("Use a fake iOS passcode screen before Performance. Enter your secret number first, tap outside to lock it, then spectator taps are ignored."),
                    .frames(.lockscreen, "Frames: wallpaper/passcode → secret input → spectator taps → Performance opens."),
                    .callout("Performance Cover + Lockscreen creates a natural sequence before the reveal while OCR/API/Bio/Note can keep working underneath.")
                ]
            ),

            UserGuidePDFPageData(
                chapter: "TRICKS",
                title: L("guide.amnesia.row.title", "Amnesia Carousel"),
                subtitle: L("guide.amnesia.hero_subtitle", "Hypnotic memory effect · Instagram verified"),
                color: Color(hex: "A78BFA"),
                blocks: [
                    .paragraph(L("guide.amnesia.what.body", "Vault prepares a visible 4-image carousel and a hidden 5-image carousel. Closing the carousel in Vault swaps them on real Instagram.")),
                    .frames(.amnesiaCarousel, "Frames: spectator sees 4 images → Vault swaps carousel → Instagram refresh reveals 5 images."),
                    .heading("Two ways to activate"),
                    .bullets(["Hand passes: theatrical close and app-switcher reset.", "Discreet scrolling: take the phone, small scroll, leave it on the table."]),
                    .heading("Date verification"),
                    .paragraph(L("guide.amnesia.date.body", "Ask the spectator to notice the upload date. At the end the fifth image has the same date, because both carousels were uploaded at the same time."))
                ]
            ),

        ]
    }
}

private struct UserGuidePDFPageView: View {
    let page: UserGuidePDFPageData
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.chapter)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(page.color)
                        .tracking(1.0)
                    Text(page.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(Color(hex: "111111"))
                    if let subtitle = page.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "555555"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Text("Vault")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "777777"))
            }

            Rectangle()
                .fill(page.color.opacity(0.35))
                .frame(height: 1)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(page.blocks.indices, id: \.self) { index in
                    UserGuidePDFBlockView(block: page.blocks[index], color: page.color)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Vault · User Guide")
                Spacer()
                Text("\(pageNumber) / \(pageCount)")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color(hex: "888888"))
        }
        .padding(.top, 34)
        .padding(.bottom, 28)
        .padding(.horizontal, 34)
        .background(Color.white)
    }
}

private struct UserGuidePDFBlockView: View {
    let block: UserGuidePDFBlock
    let color: Color

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "303030"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .padding(.top, 3)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•")
                            .foregroundColor(color)
                            .font(.system(size: 11.5, weight: .bold))
                        Text(item)
                            .font(.system(size: 11.3))
                            .foregroundColor(Color(hex: "303030"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .callout(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)
                Text(text)
                    .font(.system(size: 11.3, weight: .medium))
                    .foregroundColor(Color(hex: "222222"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(color.opacity(0.08))
            .cornerRadius(8)
        case .table(let headers, let rows):
            PDFSimpleTable(headers: headers, rows: rows, color: color)
        case .frames(let visual, let caption):
            VStack(alignment: .leading, spacing: 6) {
                PDFVisualPanel(visual: visual, color: color)
                Text(caption)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
            }
        }
    }
}

private struct PDFSimpleTable: View {
    let headers: [String]
    let rows: [[String]]
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            row(headers, isHeader: true)
            ForEach(rows.indices, id: \.self) { index in
                row(rows[index], isHeader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private func row(_ values: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(.system(size: isHeader ? 9.5 : 9.2, weight: isHeader ? .bold : .regular))
                    .foregroundColor(isHeader ? color : Color(hex: "333333"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(isHeader ? color.opacity(0.08) : Color.white)
            }
        }
    }
}

// MARK: - Print Document

private struct UserGuidePrintDocument: View {

    private let blue    = Color(hex: "0A84FF")
    private let green   = Color(hex: "16A34A")
    private let orange  = Color(hex: "FF9F0A")
    private let purple  = Color(hex: "BF5AF2")
    private let indigo  = Color(hex: "6366F1")
    private let teal    = Color(hex: "30D158")
    private let slate   = Color(hex: "94A3B8")
    private let red     = Color(hex: "FF453A")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverSection

            // ── GETTING STARTED ───────────────────────────────────────────────
            chapterHeader(String(localized: "guide.section.getting_started", defaultValue: "GETTING STARTED"), color: blue)

            PDFSectionFull(
                title: String(localized: "guide.introduction.title", defaultValue: "Introduction — What is Vault?"),
                color: blue,
                items: [
                    .body("Vault is a secret Instagram automation tool for magicians. It connects directly to your real Instagram account — no separate profile, no special audience, no visible setup required. Everything you perform happens on the same account your spectators already follow — and what they see is Instagram, not the app."),
                    .body("Vault gives you control over three areas: Forces (guide the spectator toward a number, date or post you already know), Predictions (pre-upload a photo that matches the spectator's choice, archive it, and unarchive it at the climax), and Profile Reveals (change your photo, note or biography in real time to match what the spectator is thinking)."),
                    .highlight("When the spectator opens Instagram on their own phone they see the real result — not a screenshot, not a simulation. The prediction was there from the start, archived and invisible until you decided to reveal it.")
                ]
            )

            PDFSectionFull(
                title: String(localized: "perf.help.overview.title", defaultValue: "Performance"),
                color: blue,
                items: [
                    .body("Performance is a built-in Instagram emulator. It looks and feels like the real Instagram app, but it runs inside Vault and is directly connected to your Instagram account through the official API. Everything the spectator sees is real Instagram content from your actual account — posts, followers, reels — pulled live from the API. It is not a simulation; it is your real profile."),
                    .label("The + Button — Access Settings"),
                    .body("To access Settings from Performance, tap the + button located in the top-left corner of the header bar — the same bar that shows your username. This is the only way to get back to Settings while in Performance mode. Configure all your tricks before the show."),
                    .label("The Profile View"),
                    .body("Tap the followers count to open the full followers list. In Date Force mode, tap the avatar circle to select spectators — a blue number badge shows the selection order. Switch between Posts, Reels and Tagged tabs to browse the profile. Pull down on the profile to reload it from Instagram."),
                    .label("Bottom Navigation Bar & Explore"),
                    .body("The bottom navigation bar mimics Instagram's interface. Only the magnifying glass (Search) is functional and opens Explore. Explore shows a real Instagram feed with random reels and a search bar to find any profile by username. In Force Reel mode, the target reel appears at the position you dialled in secretly."),
                    .label("Real Instagram Data"),
                    .body("Photos and videos are loaded live from your real Instagram account. Follower and following counts are real — and can be secretly manipulated for effects. Any profile you search loads its real posts, reels and biography from the API. Biography updates and photo uploads made from Settings appear on the real Instagram profile.")
                ]
            )

            PDFSectionFull(
                title: String(localized: "limits.help.title", defaultValue: "Limits & Safety"),
                color: blue,
                items: [
                    .body("Instagram occasionally shows a brief warning asking you to confirm it's you. This is completely normal for any app connected to the platform and has nothing to do with a ban. Vault is designed with the same anti-bot safeguards real apps use."),
                    .label("Your 55-action hourly budget"),
                    .body("Instagram limits each connected app to roughly 55 actions per hour. The budget works as a rolling 60-minute window. FREE (0 cost): scrolling your grid, volume button animation, typing secret numbers, viewing already-opened profiles (cached), browsing Settings or Guide. LOW cost: opening app (1), loading followers list (1), revealing a letter/photo (1 each), Counter Glitch new profile (4), searching a profile (2). HIGH cost: Sync & Archive — 2 calls per photo, uploading photos — 1 call per photo."),
                    .label("Actions consumed per feature"),
                    .body("Open Performance: 3–5 first time, 0–5 repeat.\nFollowers list: 1 first time, 0 repeat.\nNew follower profile: 3–4 first time, 0 repeat if cached.\nProfile picture change: 1.\nSync & Archive: 2 per photo.\nUpload: 1 per photo.\nAuto-upload full cycle: 3 per photo.\nReveal: 1 per letter/photo.\nNote or bio change: 1.\nExplore / Search: 1–2 first time, 0 repeat if cached."),
                    .label("Safe / Low / Critical budget zones"),
                    .body("Safe: more than 20 actions available. Low: 8–20 actions available. Critical: fewer than 8 actions available. At 55 actions Vault performs a hard stop: nothing is sent, nothing is triggered, and the app waits silently until the rolling 60-minute budget renews."),
                    .label("Cache, Sync & Archive and batches"),
                    .body("Quick repeat visits can cost 0 because Vault reuses cache. Opening Performance usually costs 3 actions for profile + posts, or up to 5 if Reels/Tagged cache must be rebuilt. After a full performance with reveals and profile visits, the app can add a short waiting period before Sync & Archive — this is normal and protects the session. Per-photo costs multiply: Sync & Archive on 4 photos = 8 actions total."),
                    .label("Visiting profiles — the expensive action"),
                    .body("Opening a new follower profile usually costs 3–4 actions. Recommended: open at most 2 new profiles per session during rehearsal. When fewer than 8 actions remain, a small red dot appears near risky profile-entry points (Followers list / Performance tab). If you try to open a new profile in critical budget, the app blocks the action and warns with a strong vibration."),
                    .label("Safe rehearsal — the golden rules"),
                    .body("• Open the same follower's profile once → it's cached for days. Rehearse Counter Glitch as many times as you want with the same person at zero cost.\n• Spread Sync & Archive and photo uploads across different hours — don't stack them all before a show.\n• Don't open 3–4 different follower profiles in a row during rehearsal.\n• Don't restart the app repeatedly while testing."),
                    .label("If you see an 'Unusual activity' warning"),
                    .body("1. Open the official Instagram app and tap 'Dismiss' on the warning.\n2. If it asks for verification, complete it with your email or SMS code.\n3. In Vault, log out from Settings, wait about a minute, and log in again.\n4. You're ready to continue — your account is safe. Your account keeps working perfectly. This only pauses Vault for a few minutes."),
                    .label("During a live performance"),
                    .body("If a warning appears while the spectator is watching the screen, Vault hides all technical details and shows a generic 'No Internet Connection' screen. Perfect cover: 'Instagram is glitching for a sec — no big deal.'"),
                    .label("If the app shows a No Internet screen"),
                    .body("Only a Dismiss button appears: open Instagram, tap Dismiss on the warning, then return to Vault. A specific end date is shown: wait until that date, then log in again. A phone or email code is requested: complete verification in the Instagram app first, then return to Vault. New accounts with little activity history are more likely to see checks. If bot detection keeps happening, contact the developer and share your logs."),
                    .label("Best practices"),
                    .body("• Don't repeat the same effect several times in a row.\n• Prepare sets (Sync & Archive) the night before.\n• If you perform often, use a dedicated Instagram account.\n• Vault automatically handles wait times, cache and cooldowns."),
                    .highlight("Your account will never be banned. Instagram occasionally asks to confirm your identity — that is all it is.")
                ]
            )

            // ── INPUT METHODS ─────────────────────────────────────────────────
            chapterHeader(String(localized: "input.guide.section.label", defaultValue: "INPUT METHODS"), color: purple)

            PDFSectionFull(
                title: "What is an input method?",
                color: purple,
                items: [
                    .body("An input method is the secret interface used to send a word, number, card, photo action, note, biography, profile picture change or automation command into Vault. Some methods are chosen per prediction set, while others belong to Notes, Bio, Profile Picture, Force Reel, Counter Glitch or URL automations."),
                    .label("Compatibility"),
                    .body("Words → Cover Typing · Camera (OCR) · API\nNumbers / Custom → Digit Grid · Number Clock · Number Lockscreen · Camera (OCR) · API\nCards → Card Clock · Numpad Card · Card Lockscreen · Camera (OCR) · API")
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.covertyping.title", defaultValue: "Cover Typing") + "  ·  " + String(localized: "input.guide.covertyping.compat", defaultValue: "Word sets"),
                color: purple,
                items: [
                    .body(String(localized: "input.guide.covertyping.body", defaultValue: "You secretly type the spectator's chosen word into the Explore search bar. A different decoy word is shown on screen — the app reads only what you type, not what is displayed. The spectator sees a normal Instagram search with no suspicious activity.")),
                    .highlight(String(localized: "input.guide.covertyping.activate", defaultValue: "Tap the search bar in Explore and type the secret word. Press Space once to confirm — the space disappears from the field and a subtle vibration lets you know the word was captured and the reveal triggered. The bar keeps showing a decoy word so the spectator sees nothing unusual."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.ocr.title", defaultValue: "Camera (OCR)") + "  ·  " + String(localized: "input.guide.ocr.compat", defaultValue: "Word · Number · Custom sets"),
                color: purple,
                items: [
                    .body(String(localized: "input.guide.ocr.body", defaultValue: "The rear camera silently reads text in the frame — playing cards, written words, arithmetic results, dates — and sends the result to whatever is currently using OCR: a prediction, Notes, Bio, or any configured placeholder. Nothing appears on screen while it scans, and the camera shutter never fires.")),
                    .highlight(String(localized: "input.guide.ocr.activate", defaultValue: "Press the physical volume ↑ button once to start scanning. The camera reads automatically and stops on its own after detecting a valid result. No visual feedback is shown to the spectator.")),
                    .note(String(localized: "input.guide.ocr.tip", defaultValue: "OCR works once per performance session (to avoid repeated camera bursts). If you need to re-scan, leave and re-enter Performance."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.digitgrid.title", defaultValue: "Digit Grid") + "  ·  " + String(localized: "input.guide.digitgrid.compat", defaultValue: "Number · Custom sets"),
                color: purple,
                items: [
                    .body(String(localized: "input.guide.digitgrid.body", defaultValue: "The fake Instagram grid acts as a hidden keypad. The visible cells map to 1-9, and the last row acts as 0. Moving naturally between Posts, Reels and Tagged lets you build the value while the following/follower count becomes a private progress indicator.")),
                    .highlight(String(localized: "input.guide.digitgrid.activate", defaultValue: "While the fake Instagram profile is visible, swipe horizontally across the grid rows to encode each digit. The following count updates with each swipe to confirm what was entered. Long press to confirm.")),
                    .label("Confirmation by feature"),
                    .body("Post Prediction: tap hidden cell positions to build the number, then confirm with the Posts icon or a long press.\nForce Reel: use the grid map to enter the position, then open Search/Explore to lock the pending reel position.\nCounter Glitch: use the same grid map to enter the offset; Followers/Following or Explore captures it for the counter."),
                    .note(String(localized: "input.guide.digitgrid.tip", defaultValue: "The grid gestures are completely invisible to the spectator — they see a normal Instagram profile the whole time.")),
                    .visual(.digitGrid)
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.clock.title", defaultValue: "Number Clock") + "  ·  " + String(localized: "input.guide.clock.compat", defaultValue: "Number · Custom sets"),
                color: slate,
                items: [
                    .body(String(localized: "input.guide.clock.body", defaultValue: "A completely black fullscreen screen — as if the phone is off. Swipe gestures encode digits 0–9 using pairs of directional swipes: each digit requires exactly two swipes in sequence (e.g. ↑↑ = 0, ↑→ = 1, →→ = 3). The captured number can reveal a prediction or fill Notes/Bio placeholders when those are configured for Number Clock.")),
                    .body("DIGIT ENCODING (each digit = 2 swipes):  0=↑↑  1=↑→  2=→↑  3=→→  4=→↓  5=↓→  6=↓↓  7=↓←  8=←↓  9=←←"),
                    .body("EXAMPLES:  5 = ↓→  |  37 = →→ + ↓←  |  369 = →→ + ↓↓ + ←←"),
                    .body("HAPTIC FEEDBACK: Light tap = each swipe registered · Medium pulse = digit completed · Double strong vibration = number committed after 3 s of no swipes · Error buzz = invalid pair"),
                    .highlight(String(localized: "input.guide.clock.activate", defaultValue: "The black screen opens automatically when the active set uses Number Clock. Swipe pairs to build your number digit by digit — each completed pair gives a short vibration. Stop swiping for 3 seconds to confirm and fire the reveal. Tap anywhere after confirmation to dismiss the black screen.")),
                    .visual(.blackClock)
                ]
            )

            cardClockSection

            PDFSectionFull(
                title: String(localized: "input.guide.numpadcard.title", defaultValue: "Numpad Card") + "  ·  " + String(localized: "input.guide.numpadcard.compat", defaultValue: "Card sets · Notes · Bio"),
                color: green,
                items: [
                    .body(String(localized: "input.guide.numpadcard.body", defaultValue: "A black fullscreen input for playing cards. When Performance opens, the screen is completely black. Tap anywhere to reveal a private card pad, choose A-10/J/Q/K and one suit, then the pad closes automatically and the fake Instagram profile appears. The captured card can reveal a Playing Cards set or fill Notes/Bio with the localized card name.")),
                    .highlight(String(localized: "input.guide.numpadcard.activate", defaultValue: "Open Performance, tap the black screen once, select the card value, then select the suit. As soon as value + suit are selected, Vault confirms with haptic feedback and dismisses the view.")),
                    .note(String(localized: "input.guide.numpadcard.tip", defaultValue: "Use this when you want a faster, more visual card input than Card Clock, but still want the first screen to look completely black.")),
                    .visual(.cardClock)
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.lockscreen.title", defaultValue: "Number Lockscreen") + "  ·  " + String(localized: "input.guide.lockscreen.compat", defaultValue: "Number · Custom sets"),
                color: indigo,
                items: [
                    .body(String(localized: "input.guide.lockscreen.body", defaultValue: "Vault shows a fake iPhone lock screen with a standard PIN keypad. You type the secret number (up to 4 digits) first — then the spectator can type anything they like on the visible keypad. Only your secret sequence is captured; the spectator's taps have no effect. The predict fires when 4 digits are entered.")),
                    .highlight(String(localized: "input.guide.lockscreen.activate", defaultValue: "Open the lock screen from the Performance tab. Enter your secret digits on the keypad — they appear as filled dots. Tap outside the keypad to mark the end of your secret input. The spectator can then type freely without changing your captured number.")),
                    .note(String(localized: "input.guide.lockscreen.tip", defaultValue: "Add a real wallpaper screenshot to make it indistinguishable from a genuine iOS lock screen. Setup is covered in the Lockscreen guide under Camouflage.")),
                    .visual(.lockscreen)
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.lockscreencard.title", defaultValue: "Card Lockscreen") + "  ·  " + String(localized: "input.guide.lockscreencard.compat", defaultValue: "Card sets"),
                color: green,
                items: [
                    .body(String(localized: "input.guide.lockscreencard.body", defaultValue: "The same fake lock screen as Number Lockscreen, but the digits are decoded into a playing card: value + suit. Values are A=1, 2-9 as themselves, 10=10, J=11, Q=12, K=13. Suits are 1=♠, 2=♥, 3=♣, 4=♦. The card can reveal a prediction or fill Notes/Bio with the localized card name.")),
                    .body("Code format: [value][suit]. Use 0 prefix for 3-digit code if needed.\nA♠ = 11  ·  7♥ = 72  ·  9♦ = 94  ·  10♠ = 101  ·  J♥ = 112  ·  Q♣ = 123  ·  K♦ = 134\nExample: to reveal Q♥ enter 122."),
                    .highlight(String(localized: "input.guide.lockscreencard.activate", defaultValue: "Enter the 4-digit code that corresponds to your card (the full table is in the set config). Tap outside to lock in your input. The spectator can type any digits after — only your secret sequence matters.")),
                    .visual(.lockscreen)
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.api.title", defaultValue: "API / Webhook") + "  ·  " + String(localized: "input.guide.api.compat", defaultValue: "Word · Number · Custom sets"),
                color: Color(hex: "FFD60A"),
                items: [
                    .body(String(localized: "input.guide.api.body", defaultValue: "A third-party service — such as 11z Inject or any JSON endpoint you control — sends the secret to Vault over the internet. Vault polls it every few seconds and applies the result automatically. Ideal for remote performances or zero-handling situations.")),
                    .highlight(String(localized: "input.guide.api.activate", defaultValue: "Configure the API URL in Settings → Integrations. Once set, Vault polls it continuously. When new data arrives it is applied to the active set without any action from you."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.urlscheme.title", defaultValue: "URL Scheme") + "  ·  " + String(localized: "input.guide.urlscheme.compat", defaultValue: "All set types · Note · Bio · Profile Picture"),
                color: Color(hex: "FB923C"),
                items: [
                    .body(String(localized: "input.guide.urlscheme.body", defaultValue: "iOS Shortcuts or any app can send commands to Vault instantly using the vault:// URL scheme — reveal a specific slot, update your note or biography, or swap your profile picture, all without touching the app.")),
                    .body("Examples:\n  vault://reveal?word=MAGIC\n  vault://reveal?slot=15\n  vault://reveal?card=J♠\n  vault://bio?text=Now\n  vault://note?text1=hello\n  vault://profilepic"),
                    .highlight(String(localized: "input.guide.urlscheme.activate", defaultValue: "Use vault://note, vault://bio, vault://reveal or vault://profilepic from any iOS Shortcut or automation. Vault opens instantly and applies the action. The tab switches to Performance automatically.")),
                    .note(String(localized: "input.guide.urlscheme.tip", defaultValue: "Combine with the Shortcuts app to create invisible triggers: NFC tags, voice commands, widgets, or even AirDrop from a second device."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "input.guide.force.title", defaultValue: "Input → On-Screen Animation"),
                color: purple,
                items: [
                    .body(String(localized: "input.guide.force.body", defaultValue: "Digit Grid, Clock Input and Card Clock do more than reveal a set — the captured number also powers two optional on-screen animations that make the reveal visible and dramatic for the spectator.")),
                    .label(String(localized: "input.guide.force.post.title", defaultValue: "Force Post")),
                    .body(String(localized: "input.guide.force.post.body", defaultValue: "The spectator scrolls freely through the post grid. The feed secretly decelerates on the photo whose position matches the number you entered — they believe the choice was entirely random.")),
                    .label(String(localized: "input.guide.force.reel.title", defaultValue: "Force Reel")),
                    .body(String(localized: "input.guide.force.reel.body", defaultValue: "When the spectator opens Explore, the reel you pre-selected appears at the exact position matching the digit you captured — indistinguishable from a genuine Explore feed.")),
                    .visual(.forceReel)
                ]
            )

            // ── POST PREDICTION ───────────────────────────────────────────────
            chapterHeader("POST PREDICTION", color: purple)

            PDFSectionFull(
                title: String(localized: "postpred.help.hero.title", defaultValue: "Post Prediction — The Image Prediction"),
                color: purple,
                items: [
                    .body(String(localized: "postpred.help.hero.body", defaultValue: "A selected image appears on your Instagram profile — in its exact original position, with its original date — chosen in real time by the spectator.")),
                    .body(String(localized: "postpred.help.howitworks.archive_reason", defaultValue: "Instagram does not let you upload a new photo and backdate it. Vault solves this by uploading the prediction images in advance and archiving them immediately. Because Instagram keeps each post's original upload date and grid position, an unarchived prediction later looks like an old post that was already there. The upload and archive are automatic and immediate, so spectators never see the preparation photos on your live profile.")),
                    .label("How It Works"),
                    .body("Step 1: " + String(localized: "postpred.help.howitworks.step1", defaultValue: "Prepare your Set — upload photos in advance and let the app archive them automatically. They become invisible on Instagram until you choose to reveal them.")),
                    .body("Step 2: " + String(localized: "postpred.help.howitworks.step2", defaultValue: "The spectator freely picks a word, number, image, or card. You capture their choice silently using one of the input methods.")),
                    .body("Step 3: " + String(localized: "postpred.help.howitworks.step3", defaultValue: "Trigger the reveal. The matching photo reappears on real Instagram in its original position, with its original date — as if it had always been there.")),
                    .label("Sets and Banks"),
                    .body(String(localized: "postpred.help.metric.sets.desc", defaultValue: "Sets are collections of photos (letters A–Z or digits 0–9) uploaded and archived in advance, ready to be revealed.") + "\n" + String(localized: "postpred.help.metric.banks.desc", defaultValue: "Each bank = one position in the word or number. Bank 1 → first letter/digit, Bank 2 → second, and so on. The number of banks defines the maximum length of what you can reveal.")),
                    .highlight(String(localized: "postpred.help.howitworks.info", defaultValue: "The spectator sees a real post on a real Instagram profile. There is no app involved — just Instagram."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "postpred.help.section.settypes", defaultValue: "Set Types"),
                color: purple,
                items: [
                    .body(String(localized: "postpred.help.settypes.intro", defaultValue: "Choose the type that matches your effect:")),
                    .label("Word Reveal"),
                    .body(String(localized: "postpred.help.settype.word.desc", defaultValue: "26 slots (A–Z) × N banks. Each bank reveals one letter. Bank 1 = 1st letter, Bank 2 = 2nd letter.") + " Compatible with: Cover Typing · OCR · API · URL Scheme"),
                    .label("Number Reveal"),
                    .body(String(localized: "postpred.help.settype.number.desc", defaultValue: "10 slots (0–9) × N banks. Each bank reveals one digit. Bank 1 = 1st digit, Bank 2 = 2nd digit.") + " Compatible with: Digit Grid · Clock · Lockscreen · OCR · API · URL Scheme"),
                    .label("Custom Set"),
                    .body(String(localized: "postpred.help.settype.custom.desc", defaultValue: "1–100 custom images, 1 bank. Swipe 1–3 digits to select the slot number (1–100). Perfect for match results, tarot draws, or any visual choice.")),
                    .label("Playing Cards"),
                    .body(String(localized: "postpred.help.settype.card.desc", defaultValue: "52 slots (A–K × ♠♥♣♦), 1 bank. Swipe 2 or 3 digits to select any card. Suits: 1=♠ 2=♥ 3=♣ 4=♦. Example: 4→2 = 4♥ · 1→1→1 = J♠.") + " Compatible with: Card Clock · Card Lockscreen · URL Scheme"),
                    .label("List Set"),
                    .body("Create a private list of named choices (e.g. horoscope signs, celebrity names, card names). Each list item is linked to a specific uploaded photo. The spectator picks from a visible on-screen list. Can be imported from TXT/CSV files. Compatible with: List Input · URL Scheme"),
                    .label("List Set: private selection screen"),
                    .body("Use List Set when the prediction is chosen from a visible list rather than a number/card/word. Steps: 1) Create the list. 2) Rename or import TXT/CSV. 3) Choose the layout. 4) Add media and upload. 5) Perform from the private fullscreen interface. 6) Wait for confirmation before showing real Instagram. Compatibility: List Input uses its own private fullscreen interface and does not share the same capture screen with Clock, Lockscreen, OCR or Numpad Card."),
                    .label("Using videos as slots"),
                    .body("Playing Cards and Custom sets support videos. Upload the video through real Instagram first, map the video to a slot inside Vault, then reveal it from Performance. Horizontal videos appear letterboxed, so vertical/reel-friendly media looks cleaner.")
                ]
            )

            PDFSectionFull(
                title: String(localized: "postpred.help.section.inputs", defaultValue: "Input Methods"),
                color: purple,
                items: [
                    .body(String(localized: "postpred.help.inputs.intro", defaultValue: "Each input method is compatible with specific set types. Choose the one that best fits your performance.")),
                    .label("Word sets"),
                    .body("Cover Typing: type the real secret word while the spectator sees a cover word. OCR: point the camera at written/printed text. API/URL: trigger remotely from a service or Shortcut."),
                    .label("Number / Custom sets"),
                    .body("Digit Grid: enter digits invisibly on the fake Instagram grid. Number Clock: black screen, each digit is two directional swipes, then wait 3 seconds. Number Lockscreen: fake iOS passcode keypad; your secret number is captured before the spectator taps."),
                    .label("Playing Cards"),
                    .body("Card Clock: 3 swipes total — 2 for value and 1 for suit. Numpad Card: black screen, tap to show a private card pad. Card Lockscreen: numeric card code. URL Scheme can also reveal a specific card symbol."),
                    .label("Confirmation rules"),
                    .body("Digit Grid confirms with long press or the feature-specific action. Clock, Card Clock and Numpad Card confirm automatically after completing the input. OCR confirms automatically after detection. API/URL confirms when new valid data arrives. List Input confirms when the private list item is tapped."),
                    .highlight("When the app vibrates, the reveal is live on real Instagram. Direct the spectator to open Instagram only after that confirmation.")
                ]
            )

            PDFSectionFull(
                title: String(localized: "postpred.help.section.before", defaultValue: "Before the Show"),
                color: purple,
                items: [
                    .body("1. " + String(localized: "postpred.help.before.1", defaultValue: "Create a Set in the Sets section. Choose Word Reveal, Number Reveal, Custom Set, or Playing Cards. Select an image template or upload your own photos.")),
                    .body("2. " + String(localized: "postpred.help.before.2", defaultValue: "Upload the images and wait for them to be automatically archived. This can take several hours — leave the app running overnight if needed.")),
                    .body("3. " + String(localized: "postpred.help.before.3", defaultValue: "During upload, do not use the app, change networks, or interrupt the process. The screen stays awake automatically. A notification will prompt you to return between uploads.")),
                    .body("4. " + String(localized: "postpred.help.before.4", defaultValue: "In My Sets, tap the set you uploaded, mark it as active, and select its input method directly from the set card.")),
                    .body("5. " + String(localized: "postpred.help.before.5", defaultValue: "Each set has its own input method selector on its card. No separate toggle needed — just pick the method that fits your performance."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "postpred.help.section.during", defaultValue: "During the Show"),
                color: purple,
                items: [
                    .label(String(localized: "postpred.help.during.step.invite", defaultValue: "THE FREE CHOICE")),
                    .body(String(localized: "postpred.help.during.invite.action", defaultValue: "Ask the spectator to freely think of a word, number, or letter. Do not suggest anything.")),
                    .body("Script: " + String(localized: "postpred.help.during.invite.dialogue", defaultValue: "\"Think of any word — or any number. Something personal, something only you know. Don't say it yet.\"")),
                    .label(String(localized: "postpred.help.during.step.input", defaultValue: "CAPTURING THE CHOICE")),
                    .body(String(localized: "postpred.help.during.input.action", defaultValue: "Capture the input silently using Grid Input, OCR, or URL Scheme, while the spectator speaks their choice aloud.")),
                    .body("Script: " + String(localized: "postpred.help.during.input.dialogue", defaultValue: "\"Say it out loud now — loud enough for everyone to hear.\"")),
                    .label(String(localized: "postpred.help.during.step.reveal", defaultValue: "THE REVEAL")),
                    .body(String(localized: "postpred.help.during.reveal.action", defaultValue: "The app unarchives the matching photo. In the app, the result appears within 2–3 seconds. On real Instagram, each photo is unarchived individually with a short pause — total time depends on the length of the word.")),
                    .body(String(localized: "postpred.help.during.timing.action", defaultValue: "When the app vibrates, the reveal is live on real Instagram. Direct the spectator to open Instagram.")),
                    .body("Script: " + String(localized: "postpred.help.during.timing.dialogue", defaultValue: "\"Open Instagram. Go to my profile. Scroll down — it was there all along.\""))
                ]
            )

            PDFSectionFull(
                title: String(localized: "postpred.help.section.tips", defaultValue: "Tips"),
                color: purple,
                items: [
                    .note(String(localized: "postpred.help.tip.timing", defaultValue: "Reveal speed. One letter or digit: ~2–3 seconds. Five letters (e.g. 'MAGIC'): ~12–15 seconds. Each additional letter adds ~2–3 seconds.")),
                    .note(String(localized: "postpred.help.tip.vibration", defaultValue: "Vibration = ready. The haptic feedback is the signal that the photo is live on real Instagram. Once it vibrates, direct the spectator to scroll their profile.")),
                    .note(String(localized: "postpred.help.tip.ring", defaultValue: "Orange ring = confirmed. After a successful reveal, an orange gradient ring appears around your profile photo — exactly like an Instagram Story ring. It confirms the photo is live on real Instagram.")),
                    .note(String(localized: "postpred.help.tip.position", defaultValue: "Original position. The photo reappears exactly where it was in the grid, with its original date — it may require scrolling to find it.")),
                    .note(String(localized: "postpred.help.tip.upload", defaultValue: "During upload. Do not use the app, change Wi-Fi networks, or let the screen lock. A notification prompts you to return between each upload.")),
                    .note(String(localized: "postpred.help.tip.banks", defaultValue: "Number of Banks. Each bank = one letter or digit position. Plan your sets around the longest word or number you want to reveal.")),
                    .note(String(localized: "postpred.help.tip.fakeapp", defaultValue: "Fake profile = instant preview, real Instagram = after vibration. The prediction appears in the app's fake profile the moment it is triggered — but it is not yet live on real Instagram. Wait for the haptic vibration before proceeding.")),
                    .note(String(localized: "postpred.help.tip.openprofile", defaultValue: "Open your real Instagram profile first. After the vibration confirms the upload, open your own Instagram profile before inviting the spectator to look. This loads the content in the feed."))
                ]
            )

            // ── INSTAGRAM PROFILE ─────────────────────────────────────────────
            chapterHeader("INSTAGRAM PROFILE", color: orange)

            PDFSectionFull(
                title: "Note Prediction",
                color: teal,
                items: [
                    .body("Post a note on your Instagram profile that matches what the spectator predicted — visible above your profile picture in the Instagram Stories bar for 24 hours."),
                    .body("The app posts a note on your Instagram account that matches what the spectator said or wrote. Notes disappear automatically after 24 hours, leaving no permanent trace."),
                    .label("Input methods: API · URL Scheme · OCR · Number/Card Lockscreen · Number/Card Clock · Numpad Card"),
                    .body("API: Open Performance first, then ask the spectator to make their selection in Inject or your custom API. Vault polls every 2 s and posts the note automatically when a new value arrives. URL Scheme: vault://note?text1=<text> — use multiple placeholders: vault://note?text1=silla&text2=rojo. OCR: Point the camera at a word the spectator wrote — the app reads it and sends it as your note. Lockscreen: Assign {text1} to lockscreen; the number/card fills the template on confirm. If a matching set is active, the same input can also unarchive its slot. Number/Card Clock: A black screen appears in Performance; swipe to enter then stop 3 s to auto-confirm. Numpad Card: Tap the black screen once, select card value + suit."),
                    .label("What is OCR?"),
                    .body("OCR (Optical Character Recognition) reads text from an image or live camera. In Vault, point the camera at a word, number or card and the prediction triggers automatically without manual input."),
                    .label("Compatibility"),
                    .body("The SAME interface type can be shared across Set, Biography and Notes — one capture fills them all at once (for example Numpad Card in Bio + Notes + a Playing Cards set). DIFFERENT interface types cannot coexist in a single performance: OCR, Number Clock, Card Clock, Numpad Card, Number Lockscreen and Card Lockscreen are mutually exclusive. Settings warns you and offers to deactivate conflicts."),
                    .highlight("Fake app vs. real Instagram: The note appears in the fake profile instantly — but is NOT yet live on real Instagram. Wait for the double vibration + orange ring around your profile picture BEFORE showing the spectator."),
                    .label("During the Show"),
                    .body("1. Ask the spectator to think of or write a short word (max 60 characters).\n2. Capture it via OCR / enter via API or URL Scheme / use interface input.\n3. Open Performance — the note posts automatically (or tap Send Note if using the manual flow).\n4. Wait for double vibration + orange ring, then open your own real Instagram profile first."),
                    .visual(.profileConfirm),
                    .label("Tips"),
                    .body("• Notes are limited to 60 characters — keep predictions concise.\n• A cooldown prevents double-sending. If the button is disabled, wait a few seconds.\n• Use the Text Template field: e.g. 'My prediction is: {text1}'.\n• Need two values? Use {text1} and {text2} in your template.\n• Only one interface type (OCR, Lockscreen, Number Clock, Card Clock, or Numpad Card) can be active per performance.")
                ]
            )

            PDFSectionFull(
                title: "Biography Prediction",
                color: orange,
                items: [
                    .body("Update your Instagram biography to reveal a prediction — the text appears permanently on your profile page until you change it. Visible to anyone who visits your profile — no followers required. Supports up to 150 characters."),
                    .label("Input methods: API · URL Scheme · OCR · Number/Card Lockscreen · Number/Card Clock · Numpad Card · Templates · Acrostic Mode"),
                    .body("Same input system as Note (see above). Additionally supports Bio Templates (T1–T4): pre-configured text blocks you can switch between. T1 can be your normal bio, T2 the prediction bio, T3 a follow-up line and T4 a reset/alternate version. Templates can include {text1}, {text2} and {text3}, and can include line breaks."),
                    .body("vault://bio?text=<text> — trigger the bio update from any Shortcut or automation. Combine T1/T2 switch with URL Scheme for completely hands-free bio swaps."),
                    .label("Acrostic Mode"),
                    .body("Enable the 'Acrostic Mode' toggle in the Biography card. When a single word or code arrives via API, OCR or URL Scheme, it is automatically converted before being sent to Instagram. Each letter becomes a line starting with a word in the device language; each digit becomes a 6-digit line starting with that digit.\n\nExample — word received: VASO\nBio sent to Instagram:\n  Viento\n  Árbol\n  Sol\n  Origen\n\nMixed example — code received: 3c\nBio sent to Instagram:\n  356754\n  Car\n\nNumber example — code received: 123456\nBio sent to Instagram:\n  143553\n  265474\n  3xxxxx\n  4xxxxx\n  5xxxxx\n  6xxxxx\n\nRepeated letters cycle through 3 different words so the same word never appears twice (e.g. BANANA uses Barco / Árbol / Norte / Avión / Nube / Azul). Works in 17 languages — the word bank is built into the app and adapts to the device language automatically."),
                    .highlight("Acrostic Mode only transforms single words (no spaces). Multi-word inputs are sent unchanged."),
                    .highlight("Fake app vs. real Instagram: Same as Note — wait for double vibration + orange ring before showing the spectator."),
                    .label("During the Show"),
                    .body("1. Set up your bio template before the show (T1 = normal bio, T2 = prediction text).\n2. If using Acrostic Mode, enable the toggle in the Biography card and set the input source to API or OCR.\n3. Capture the spectator's word using your chosen input method.\n4. Open Performance — the word is converted to the acrostic poem and the bio updates automatically.\n5. Wait for double vibration + orange ring, then open your own profile first."),
                    .visual(.profileConfirm),
                    .label("Tips"),
                    .body("• Combine with Profile Picture for a double reveal (bio + photo change at the same moment).\n• Use {text1}{text2}{text3} placeholders for complex multi-part predictions.\n• Acrostic Mode + OCR: spectator writes any word, you scan it, bio becomes a poem — powerful and visual.\n• Acrostic Mode + API: spectator selects a word in your Inject or booking link — arrives silently, bio rewritten as a poem.\n• Number Clock can fill any number of digits; Card Clock/Numpad Card fill the localized card name.\n• Bio is permanent until changed — ideal for in-person reveals where the spectator visits your profile on their own phone.")
                ]
            )

            PDFSectionFull(
                title: "Profile Picture Prediction",
                color: blue,
                items: [
                    .body("Change your Instagram profile photo automatically to match the spectator's prediction. The app uploads a chosen photo as your Instagram profile picture at the exact moment of the reveal. The spectator sees your profile photo change live — the image matches what they predicted."),
                    .label("Input methods: URL Scheme (vault://profilepic) · Last gallery photo (Auto on Performance open)"),
                    .body("URL Scheme: Use vault://profilepic from any Shortcut or automation to trigger an upload when Performance opens. Ideal for pre-show automation: run the Shortcut before walking on stage.\nLast gallery photo: Enable 'Auto on Performance open' to automatically upload the most recent photo in your camera roll every time you enter Performance. Take the prediction photo before the show, then open Performance — it uploads instantly."),
                    .highlight("Fake app vs. real Instagram: Wait for double vibration + orange ring around your profile picture. That means the new image is live on real Instagram — then open your own Instagram profile before showing the spectator."),
                    .label("During the Show"),
                    .body("1. Prepare the prediction photo in your camera roll before the performance.\n2. Enable 'Auto on Performance open' or have a URL Scheme shortcut ready.\n3. Open Performance — photo uploads automatically.\n4. Wait for double vibration + orange ring, then open your own Instagram profile."),
                    .visual(.profileConfirm),
                    .label("Tips"),
                    .body("• Use a 1:1 square photo for best results on the circular Instagram profile picture crop.\n• A 30-second cooldown prevents accidental re-uploads during the same performance.\n• Combine with a URL Scheme from Apple Shortcuts for a completely hands-free reveal.")
                ]
            )

            // ── TRICKS ────────────────────────────────────────────────────────
            chapterHeader("TRICKS", color: purple)

            PDFSectionFull(
                title: "Force Post",
                color: purple,
                items: [
                    .body("Before the show you choose a post in Settings. During the performance the spectator scrolls freely — but the app always stops on your pre-chosen image."),
                    .label("Setup"),
                    .body("1. Before the show, open Settings and enable Force Post.\n2. Tap 'Select Post' or 'Add Another Profile' to search for any Instagram account.\n3. Search the username and tap the post you want to force.\n4. Repeat to add multiple profiles (each can have one forced post).\n5. Once configured, close Settings."),
                    .label("During the Show"),
                    .body("GO TO PERFORMANCE: Hand the phone to the spectator. 'Open any profile — scroll through their posts freely.'\nTHE FORCE: The spectator scrolls freely — the feed secretly decelerates on the photo whose position matches the one you set. They believe the choice was entirely random.\nTHE REVEAL: Show the envelope, card, or prediction that matches. 'Look at that post — I wrote this before we met.'"),
                    .label("Tips"),
                    .body("• Prepare in advance — Settings are not touched during performance.\n• Works on multiple profiles — assign different forced posts to different accounts for variety.\n• A single spectator scroll triggers only one force — the app won't intercept a second time.\n• Works offline — the forced post position is remembered even without internet.\n• Only works on public profiles.")
                ]
            )

            PDFSectionFull(
                title: "Force Reel",
                color: indigo,
                items: [
                    .body("In Settings you pick a reel and assign it a position number. The spectator names any number — the magician secretly enters that number with the Digit Grid (see Input Methods), then opens Explore. The forced reel appears at exactly that position."),
                    .label("Setup"),
                    .body("1. Before the show, open Settings and enable Force Reel.\n2. Tap 'Select Reel', search for any account and pick the reel you want to force.\n3. Note the position number assigned — this is the number the spectator must 'freely' name.\n4. Once configured, close Settings."),
                    .label("During the Show"),
                    .body("OPEN A PROFILE: In Performance, navigate to any Instagram profile and open their post grid. 'Open any profile — a friend, a celebrity, anyone.'\nSPECTATOR NAMES A NUMBER: Ask the spectator to call out any number. While their attention is on the screen, use the hidden Digit Grid input to enter it.\nMAGICIAN DIALS IN SECRET: Moving through Posts, Reels and Tagged looks like normal browsing — the app is building the number in the background. The Following counter previews the accumulated number.\nOPEN EXPLORE: Navigate to Explore. 'Count to position #13 in Explore. That reel — right where your number landed — is what I prepared for you.'"),
                    .visual(.forceReel),
                    .label("Tips"),
                    .body("• Prepare beforehand — Settings are not touched during performance.\n• A 3-digit number like 134 feels completely impossible to predict.\n• Open Explore only after the number is visible in the hidden counter preview — that tap locks the pending position.")
                ]
            )

            PDFSectionFull(
                title: "Counter Glitch",
                color: purple,
                items: [
                    .body("The spectator names a number from 1 to 100. The magician secretly registers it using the Digit Grid on their own profile. Then opens a participant's Instagram profile — the counter appears inflated. Pressing the volume button triggers a glitch: a countdown reveals the 'stolen' number."),
                    .label("Setup"),
                    .body("1. Enable Counter Glitch in Settings.\n2. Choose Followers or Following counter to manipulate.\n3. Optionally enable Transfer Mode (the number moves from your counter to the spectator's).\n4. Set a Delay (0–10 seconds) before the glitch countdown.\n5. Enter the offset with Digit Grid, then open Followers/Following or Explore to capture the pending buffer."),
                    .label("Performance Script"),
                    .body("THE PROPOSAL: 'Think of a number from 1 to 100.' While talking, use the Digit Grid on your profile to secretly register the digits.\nLA JUSTIFICACIÓN: Explain that Instagram keeps hidden records of interactions and that the counter can show more than the spectator expects.\nEL MOMENTO: Press the volume button while on the spectator's profile. The counter glitches and begins the countdown.\nLA REVELACIÓN: 'Check your phone. That number — you'll see it's the same one you were thinking of.' The spectator verifies the real number on their own device.\nTRANSFER LINE: In Transfer Mode, present it as the number leaving your profile and arriving on theirs."),
                    .label("Large counters"),
                    .body("Counter Glitch uses the exact number entered, from 1 to 100. During the glitch, Vault temporarily shows the full counter value so small changes do not disappear inside Instagram-style K/M rounding."),
                    .label("Transfer Mode"),
                    .body("Phase 1 (Deflation): On the magician's profile, press volume and the counter deflates from inflated to normal, as if the number 'left'.\nPhase 2 (Inflation): Navigate to the spectator's profile and press volume again; their counter inflates by the same number — confirming the transfer."),
                    .visual(.counterGlitch),
                    .label("Tips"),
                    .body("• Register the digits before opening the spectator's profile — the Digit Grid works on your own profile.\n• Use a Delay to build tension before the glitch fires.\n• Don't show the screen to the spectator before the glitch fires — they'll see the inflated counter.\n• Works on public profiles at any size; on 1K+ counters, the temporary full-number display keeps small changes visible.")
                ]
            )

            PDFSectionFull(
                title: "Date Force",
                color: Color(hex: "60A5FA"),
                items: [
                    .body("You select spectators from the audience who have followed you. Their followers and following counts encode today's date and time. The result appears on any Explore reel profile — the spectator subtracts their own numbers and gets today's date."),
                    .label("How It Works"),
                    .body("Two secret groups of spectators are selected (date group + time group). The app calculates how much to inflate each follower/following count so the sum encodes the date and time. The inflation is camouflaged within the natural variation of any Instagram counter."),
                    .label("Setup"),
                    .body("1. Enable Date Force in Settings and choose DD/MM or MM/DD format.\n2. Optionally apply a minute offset if you want the time reveal to land a few minutes ahead.\n3. In the Followers list, tap the avatar/story ring to select participants (number badges show order).\n4. First half = date group, second half = time group.\n5. Navigate back, close and wait 2–3 seconds while the app prepares the counters.\n6. Open Explore to complete the setup."),
                    .label("Performance Script"),
                    .body("EL GANCHO: 'Did you know that Instagram tracks exactly who you follow and when? Every connection is recorded.'\nLA INVITACIÓN: Ask selected spectators to follow you on Instagram while the app captures the new followers in the background.\nLA JUSTIFICACIÓN: Split the selected people into left/right or first/second groups so the sums feel like a ritual rather than a calculation.\nEL RITUAL DE LOS NÚMEROS: Have them add the follower/following numbers from the selected profiles. One group encodes the date, the other encodes the time.\nEL DESCONOCIDO: Move to Explore and open a random reel/profile so the reveal feels independent from your account.\nLA REVELACIÓN: The spectator subtracts or combines the numbers and obtains today's date and time."),
                    .label("Know Your Audience"),
                    .body("Large audience (4+ people): Ask who has a public profile and instruct them to follow you. With 10+ people, there will always be at least 4 with public profiles.\nSmall audience or all-private: Ask them to follow you from their real Instagram, accept the requests, then switch from Instagram to Vault and select participants from the followers list."),
                    .visual(.dateForce),
                    .label("Tips"),
                    .body("• Tap the photo/avatar/story ring, not the row — tapping the row opens the profile.\n• Tap again to deselect if you made a mistake.\n• Use an even number of spectators (date group and time group must be equal size).\n• Private accounts are automatically marked with 'Follow too' badge — you can still use them.")
                ]
            )

            // ── ADVANCED FEATURES ─────────────────────────────────────────────
            chapterHeader("ADVANCED FEATURES", color: slate)

            PDFSectionFull(
                title: String(localized: "guide.fakehome.title", defaultValue: "Performance Cover"),
                color: slate,
                items: [
                    .body(String(localized: "guide.fakehome.help.what.body", defaultValue: "Performance Cover shows a full-screen cover before your fake Instagram profile appears. Choose Fake Home Screen to show a real home screen screenshot, or Fake Screen Off to show a black screen as if the phone were off.")),
                    .label("Fake Screen Off"),
                    .body(String(localized: "guide.fakehome.help.screenoff.body", defaultValue: "Fake Screen Off uses the same flow as Fake Home Screen, but the cover is pure black. It can stay visible while OCR, Inject/API, biography, notes, or other background inputs keep working underneath. Tap anywhere to reveal Performance.")),
                    .label("How to use it"),
                    .body(String(localized: "guide.fakehome.help.how.body", defaultValue: "1. In Settings, open Performance Cover and choose Off, Fake Home Screen, or Fake Screen Off.\n2. For Fake Home Screen, upload a real iPhone home screen screenshot with the Instagram icon visible.\n3. For Fake Screen Off, no image is needed — the app shows a pure black screen.\n4. Open Performance. Tap anywhere on the cover to reveal your profile.")),
                    .body(String(localized: "guide.fakehome.help.why.body", defaultValue: "It creates a natural pause before the reveal. Fake Home Screen looks like you are opening Instagram normally; Fake Screen Off looks like the phone was off until you tap it."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "guide.lockscreen.title", defaultValue: "Lockscreen Input"),
                color: indigo,
                items: [
                    .body(String(localized: "guide.lockscreen.help.what.body", defaultValue: "When you open Performance, the app shows a fake iOS-style passcode screen before revealing your profile. To anyone watching it looks like you are simply unlocking your phone.")),
                    .label("How to enter your secret number"),
                    .body("1. Tap the digits of your secret number on the numpad — they register silently.\n2. Tap anywhere outside the numpad to lock those digits in place.\n3. Fill the remaining dots by tapping any digits — they are ignored.\n4. Once all 4 dots are filled the lockscreen dismisses and Performance opens."),
                    .label(String(localized: "guide.lockscreen.help.wallpaper.title", defaultValue: "Wallpaper")),
                    .body(String(localized: "guide.lockscreen.help.wallpaper.body", defaultValue: "Upload the same wallpaper you use on your real lock screen so the fake one looks identical. Then select Lockscreen as the input method on your set card in My Sets.")),
                    .label(String(localized: "guide.lockscreen.help.cards.title", defaultValue: "Playing Card codes")),
                    .body("Suits:  1 = ♠   2 = ♥   3 = ♣   4 = ♦\nCards A–9 → [value][suit]:  A♠ = 11  ·  7♥ = 72  ·  9♦ = 94\nCards 10, J, Q, K → [tens][units][suit]:  10♠ = 101  ·  J♥ = 112  ·  Q♣ = 123  ·  K♦ = 134\nExample: to reveal Q♥ enter 122."),
                    .label("Same secret number — many tricks"),
                    .body("The number entered on the fake lockscreen can unarchive a numeric photo, reveal a playing card, show a custom image, activate Counter Glitch or force a reel in Explore. It is the same secret number used by Grid Input and the other numeric tricks."),
                    .body(String(localized: "guide.lockscreen.help.why.body", defaultValue: "It disguises the act of entering a secret number as a normal phone unlock. Combined with Performance Cover, the full sequence can look like: unlock phone → home screen or black screen → open Instagram — completely natural to any observer."))
                ]
            )

            PDFSectionFull(
                title: String(localized: "guide.amnesia.row.title", defaultValue: "Amnesia Carousel"),
                color: Color(hex: "A78BFA"),
                items: [
                    .body(String(localized: "guide.amnesia.what.body", defaultValue: "A hypnotic amnesia effect verified on real Instagram. Vault prepares two carousels: a visible 4-image carousel and a hidden 5-image carousel. The spectator opens your profile on their own phone, enters the visible carousel and memorizes the 4 images. When you close that carousel in Vault, Instagram swaps the posts: the 4-image carousel is archived and the 5-image carousel is unarchived.")),
                    .label(String(localized: "guide.amnesia.trigger.title", defaultValue: "The trigger — correct order")),
                    .body("1. Ask the spectator to open Instagram, enter your profile and tap the carousel.\n2. While they are inside the carousel, have them look at the 4 images and notice the date.\n3. Close the carousel in Vault — Vault adds the extra image on real Instagram.\n4. IMPORTANT: do not leave Vault or close the app. Wait for the archive/unarchive process to finish.\n5. When the spectator finishes memorizing, ask them to fully close Instagram. Or take their phone, make a natural small scroll, and leave it on the table.\n❌ Do not close the carousel in Vault before the spectator has entered and seen the initial 4 images."),
                    .label(String(localized: "guide.amnesia.hidden.title", defaultValue: "Hidden image")),
                    .body(String(localized: "guide.amnesia.hidden.body", defaultValue: "The 5th image (marked with an orange border in the app) is the one that appears at the end. In the ESP template it is usually the star: the spectator remembers circle, cross, waves and square, but not the star.")),
                    .label("Two ways to activate"),
                    .body("A — Hand passes (more theatrical): close the carousel in Vault and say 'I'll close mine too' as part of the ritual. Ask them to close Instagram completely.\nB — Discreet scrolling (more invisible): take their phone for a second, make a natural small scroll while talking and leave it on the table. This justifies the refresh without looking technical."),
                    .label("Performance Script"),
                    .body("OPENING: 'Take your phone. Open Instagram, enter my profile and tap this carousel. Memorize each symbol and also notice the upload date.'\nCLOSING INSTAGRAM: Once the spectator is inside the carousel, close the carousel in Vault. Wait for the process to finish. 'Now close Instagram completely from the app switcher.'\nCLIMAX: 'You named circle, cross, waves and square... but you didn't name the star. Are you sure the star wasn't there?' [Spectator opens Instagram — sees 5 images.] 'It did not appear now. Instagram says it was already there. The post did not change: your memory did.'"),
                    .visual(.amnesiaCarousel),
                    .label(String(localized: "guide.amnesia.date.title", defaultValue: "Date verification — the final blow")),
                    .body(String(localized: "guide.amnesia.date.body", defaultValue: "At the beginning, ask the spectator to notice the upload date of the post. At the end, when they see 5 images, ask: 'Is it the same date you saw before?' It always is — because both carousels were uploaded at the same time. Instagram cannot modify dates. This detail turns the verification into irrefutable proof."))
                ]
            )

            // ── FAQ ───────────────────────────────────────────────────────────
            chapterHeader(String(localized: "faq.help.title", defaultValue: "FREQUENTLY ASKED QUESTIONS"), color: green)

            PDFSectionFull(
                title: "FAQ",
                color: green,
                items: [
                    .label(String(localized: "faq.q.slow_load.question", defaultValue: "Why does my profile take a few seconds to load?")),
                    .body(String(localized: "faq.q.slow_load.answer", defaultValue: "When you open Performance, the app connects to Instagram to fetch your latest data — posts, followers, profile picture and more. This takes 2–5 seconds depending on your internet connection and how busy Instagram's servers are. Nothing is wrong: it is exactly the same delay a real Instagram app would have on a slow connection.") + " " + String(localized: "faq.q.slow_load.tip", defaultValue: "Tip: if the audience notices the loading, say 'let me open Instagram' while it loads — they will assume it is normal network latency.")),
                    .label(String(localized: "faq.q.refresh.question", defaultValue: "Does the profile refresh every time I open Performance?")),
                    .body(String(localized: "faq.q.refresh.answer", defaultValue: "Yes, once per session. The app fetches fresh data from Instagram and caches it so the content stays accurate. If you open Performance again within the same 90-second window, the cached version appears instantly — no new request is made.")),
                    .label(String(localized: "faq.q.new_photo.question", defaultValue: "I uploaded a new photo to Instagram. When will it appear?")),
                    .body(String(localized: "faq.q.new_photo.answer", defaultValue: "Your new photo will appear the next time you open Performance — typically within 90 seconds of posting it on Instagram. The app always fetches the latest posts on entry, so you do not need to do anything manually.")),
                    .label(String(localized: "faq.q.reels_slow.question", defaultValue: "Reels and Tagged content seem slow to appear. Is that normal?")),
                    .body(String(localized: "faq.q.reels_slow.answer", defaultValue: "Reels and Tagged photos load automatically in the background a few seconds after your posts appear, so they are ready before you swipe to those tabs. Once loaded they are saved and appear instantly on future sessions — no internet needed.")),
                    .label(String(localized: "faq.q.no_data.question", defaultValue: "What happens if I have no internet connection when I open Performance?")),
                    .body("The app displays the last cached profile data. When the internet connection is restored, it silently refreshes in the background. The spectator sees your profile without interruption."),
                    .label("Can using Vault get my Instagram account suspended?"),
                    .body("Vault is designed with Instagram's rate limits in mind and uses the same anti-bot safeguards real apps use. The risk is minimal when used as intended. Avoid testing repeatedly in short periods — most detections happen during rehearsal, not live performances."),
                    .label("The audience asks why the app looks like Instagram"),
                    .body("Say exactly what they already believe: you are checking Instagram. Performance is a faithful replica connected to real Instagram data, so the natural handling is to treat it like the real app. Keep your script focused on Instagram, not on Vault.")
                ]
            )

            footerView
            Color.clear.frame(height: 20)
        }
        .background(Color.white)
    }

    // MARK: - Card Clock section

    private var cardClockSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PDFSectionFull(
                title: String(localized: "input.guide.cardclock.title", defaultValue: "Card Clock") + "  ·  " + String(localized: "input.guide.cardclock.compat", defaultValue: "Card sets"),
                color: green,
                items: [
                    .body(String(localized: "input.guide.cardclock.body", defaultValue: "A completely black screen — same look as Number Clock, but captures a playing card instead of a number. Exactly 3 swipes are required: the first 2 encode the card value using a clock-face layout, the 3rd is a single swipe for the suit.")),
                    .highlight(String(localized: "input.guide.cardclock.activate", defaultValue: "Swipe 1 + 2 for the value, swipe 3 for the suit (single directional swipe). Each completed value pair gives a distinct vibration; the 3rd swipe triggers a strong vibration for the completed card. Stop swiping for 3 seconds to confirm automatically.")),
                    .visual(.cardClock)
                ]
            )
            cardClockTable
        }
    }

    private var cardClockTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            PDFSectionLabel(
                String(localized: "postpred.help.input.cardclock.guide.values", defaultValue: "VALUE ENCODING  (clock face)"),
                color: green
            )
            HStack(spacing: 6) {
                ForEach([("A","↑→"),("2","→↑"),("3","→→"),("4","→↓"),("5","↓→"),("6","↓↓"),("7","↓←")], id: \.0) { face, sw in
                    PDFPill(label: face, value: sw, color: green)
                }
            }
            HStack(spacing: 6) {
                ForEach([("8","←↓"),("9","←←"),("10","↑←"),("J","←↑"),("Q","↑↑"),("K","↑↓")], id: \.0) { face, sw in
                    PDFPill(label: face, value: sw, color: green)
                }
            }
            PDFSectionLabel(
                String(localized: "postpred.help.input.cardclock.guide.suits", defaultValue: "SUIT ENCODING  (single swipe)"),
                color: green
            )
            HStack(spacing: 10) {
                ForEach([("♠","↑"),("♥","→"),("♣","↓"),("♦","←")], id: \.0) { suit, sw in
                    PDFPill(label: suit, value: sw,
                            color: ["♥","♦"].contains(suit) ? .red : green)
                }
            }
            PDFSectionLabel("EXAMPLES", color: green)
            VStack(alignment: .leading, spacing: 4) {
                Text("J♠  =  ←↑  ↑     (Jack: ←↑ · Spades: ↑)")
                Text("3♥  =  →→  →     (3: →→ · Hearts: →)")
                Text("A♦  =  ↑→  ←     (Ace: ↑→ · Diamonds: ←)")
                Text("Q♣  =  ↑↑  ↓     (Queen: ↑↑ · Clubs: ↓)")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color(hex: "222"))
        }
        .padding(14)
        .background(green.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(green.opacity(0.25), lineWidth: 1))
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Chapter header

    private func chapterHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .tracking(1.2)
                .padding(.leading, 12)
                .padding(.vertical, 10)
            Spacer()
        }
        .background(color.opacity(0.07))
        .padding(.top, 18)
    }

    // MARK: - Cover

    private var coverSection: some View {
        ZStack(alignment: .leading) {
            Color(hex: "111214")
            HStack(spacing: 0) {
                Rectangle()
                    .fill(green)
                    .frame(width: 5)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Vault")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                Text(String(localized: "guide.pdf.cover.subtitle", defaultValue: "User Guide"))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color(white: 0.75))
                Text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.5))
            }
            .padding(.leading, 28)
            .padding(.vertical, 36)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("Vault · vault-app.com · \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.6))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - PDF sub-components

private enum PDFItem {
    case body(String)
    case label(String)
    case highlight(String)
    case note(String)
    case visual(PDFVisual)
}

private enum PDFVisual {
    case settingsOverview
    case setCardConfig
    case postPredictionSetup
    case profileSettings
    case noteConfig
    case biographyConfig
    case digitGrid
    case blackClock
    case cardClock
    case lockscreen
    case forceReel
    case counterGlitch
    case dateForce
    case amnesiaCarousel
    case profileConfirm
}

private struct PDFSectionFull: View {
    let title: String
    let color: Color
    let items: [PDFItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "111"))
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items.indices, id: \.self) { idx in
                    switch items[idx] {
                    case .body(let text):
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "333"))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    case .label(let text):
                        Text(text)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(color)
                            .padding(.top, 4)
                    case .highlight(let text):
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(color.opacity(0.7))
                                .frame(width: 3)
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "222"))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(color.opacity(0.07))
                        .cornerRadius(6)
                    case .note(let text):
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(color)
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "444"))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                        }
                    case .visual(let visual):
                        PDFVisualPanel(visual: visual, color: color)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(color.opacity(0.5))
                .frame(width: 2)
                .padding(.vertical, 10),
            alignment: .leading
        )
    }
}

private struct PDFVisualPanel: View {
    let visual: PDFVisual
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
                .tracking(0.5)

            switch visual {
            case .settingsOverview:
                settingsOverviewVisual
            case .setCardConfig:
                setCardConfigVisual
            case .postPredictionSetup:
                postPredictionSetupVisual
            case .profileSettings:
                profileSettingsVisual
            case .noteConfig:
                noteConfigVisual
            case .biographyConfig:
                biographyConfigVisual
            case .digitGrid:
                digitGridVisual
            case .blackClock:
                blackClockVisual
            case .cardClock:
                cardClockVisual
            case .lockscreen:
                lockscreenVisual
            case .forceReel:
                forceReelVisual
            case .counterGlitch:
                counterGlitchVisual
            case .dateForce:
                dateForceVisual
            case .amnesiaCarousel:
                amnesiaVisual
            case .profileConfirm:
                profileConfirmVisual
            }
        }
        .padding(12)
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private var title: String {
        switch visual {
        case .settingsOverview: return "VISUAL — Settings dashboard"
        case .setCardConfig: return "VISUAL — Set card configuration"
        case .postPredictionSetup: return "VISUAL — Post Prediction workflow"
        case .profileSettings: return "VISUAL — Profile Picture settings"
        case .noteConfig: return "VISUAL — Note template setup"
        case .biographyConfig: return "VISUAL — Biography template setup"
        case .digitGrid: return "VISUAL — Digit Grid hidden keypad"
        case .blackClock: return "VISUAL — Black screen clock input"
        case .cardClock: return "VISUAL — Card Clock flow"
        case .lockscreen: return "VISUAL — Fake lockscreen input"
        case .forceReel: return "VISUAL — Force Reel animation"
        case .counterGlitch: return "VISUAL — Counter Glitch countdown"
        case .dateForce: return "VISUAL — Date Force selection"
        case .amnesiaCarousel: return "VISUAL — Amnesia Carousel swap"
        case .profileConfirm: return "VISUAL — Real Instagram confirmation"
        }
    }

    private var settingsOverviewVisual: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PDFSettingsCard(icon: "person.crop.circle.fill", title: "Profile Picture", subtitle: "Prediction photo", color: Color(hex: "FF9F0A"))
                PDFSettingsCard(icon: "bubble.left.fill", title: "Note", subtitle: "{text1} template", color: Color(hex: "30D158"))
                PDFSettingsCard(icon: "text.alignleft", title: "Biography", subtitle: "T1–T4", color: Color(hex: "FF9F0A"))
            }
            HStack(spacing: 8) {
                PDFSettingsCard(icon: "photo.on.rectangle", title: "Post Prediction", subtitle: "Sets + archive", color: color)
                PDFSettingsCard(icon: "square.grid.2x2", title: "Force Reel", subtitle: "Select target", color: color)
                PDFSettingsCard(icon: "lock.fill", title: "Camouflage", subtitle: "Home + lock", color: Color(hex: "16A34A"))
            }
            HStack {
                Text("+")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(color))
                Text("Performance header: tap + to return to Settings")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "333"))
                Spacer()
            }
            .padding(8)
            .background(Color.white)
            .cornerRadius(8)
        }
    }

    private var setCardConfigVisual: some View {
        HStack(spacing: 10) {
            PDFPhoneFrame(title: "My Sets") {
                VStack(alignment: .leading, spacing: 8) {
                    PDFMiniSetCard(title: "Cards Set", status: "Uploaded · Active", method: "Card Clock", color: color)
                    PDFMiniSetCard(title: "Word Reveal", status: "Archived", method: "Cover Typing", color: Color(hex: "0A84FF"))
                }
            }
            PDFArrow()
            VStack(alignment: .leading, spacing: 8) {
                PDFPickerRow(label: "Input Method", value: "Card Clock", color: color)
                PDFPickerRow(label: "Configure", value: "Encoding table", color: color)
                PDFPickerRow(label: "Active", value: "ON", color: Color(hex: "16A34A"))
                Text("The input is selected on the set card.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "444"))
            }
        }
    }

    private var postPredictionSetupVisual: some View {
        HStack(spacing: 8) {
            PDFStageBox(number: "1", title: "Create Set", text: "Choose type", color: color)
            PDFArrow()
            PDFStageBox(number: "2", title: "Upload", text: "Media goes live", color: color)
            PDFArrow()
            PDFStageBox(number: "3", title: "Archive", text: "Hidden from profile", color: color)
            PDFArrow()
            PDFStageBox(number: "4", title: "Reveal", text: "Unarchive + ring", color: color)
        }
    }

    private var profileSettingsVisual: some View {
        HStack(spacing: 10) {
            PDFPhoneFrame(title: "Profile Picture") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color.opacity(0.18))
                            .frame(width: 52, height: 52)
                            .overlay(Image(systemName: "person.crop.circle.fill").foregroundColor(color))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source")
                                .font(.system(size: 9, weight: .bold))
                            Text("Last gallery photo")
                                .font(.system(size: 9))
                        }
                    }
                    PDFToggleRow(title: "Auto on Performance open", isOn: true, color: color)
                    PDFButtonLabel("Upload Profile Picture", color: color)
                }
            }
            PDFArrow()
            profileConfirmVisual
        }
    }

    private var noteConfigVisual: some View {
        PDFPhoneFrame(title: "Note") {
            VStack(alignment: .leading, spacing: 8) {
                PDFTextFieldMock(title: "Template", text: "My prediction is {text1}", color: color)
                PDFPickerRow(label: "Input", value: "OCR / Clock / URL", color: color)
                PDFPickerRow(label: "Cooldown", value: "Ready", color: Color(hex: "16A34A"))
                PDFButtonLabel("Send Note", color: color)
            }
        }
    }

    private var biographyConfigVisual: some View {
        PDFPhoneFrame(title: "Biography") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(["T1", "T2", "T3", "T4"], id: \.self) { tab in
                        Text(tab)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(tab == "T2" ? .white : color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(tab == "T2" ? color : color.opacity(0.10))
                            .cornerRadius(6)
                    }
                }
                PDFTextFieldMock(title: "Bio template", text: "{text1}", color: color)
                PDFPickerRow(label: "Input", value: "OCR / API", color: color)

                // Acrostic Mode toggle row
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.star")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "F472B6"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Acrostic Mode")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                        Text("VASO → Viento / Árbol / Sol / Origen")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Capsule()
                        .fill(Color(hex: "F472B6"))
                        .frame(width: 26, height: 14)
                        .overlay(
                            Circle().fill(.white).frame(width: 10, height: 10)
                                .offset(x: 5), alignment: .trailing
                        )
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(hex: "1C1C1E"))
                .cornerRadius(7)

                PDFButtonLabel("Update Biography", color: color)
            }
        }
    }

    private var digitGridVisual: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(["Posts", "Reels", "Tagged"], id: \.self) { tab in
                    Text(tab)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(tab == "Posts" ? .white : Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.black)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0], id: \.self) { digit in
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                            .fill(color.opacity(0.35))
                            .frame(height: 34)
                        Text("\(digit)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(digit == 0 ? Color.orange : color))
                            .padding(4)
                    }
                }
            }
            HStack {
                Text("Following")
                Text("307")
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Spacer()
                Text("hidden value building")
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: "16A34A"))
            }
            .font(.system(size: 10))
            .foregroundColor(Color(hex: "444"))
        }
    }

    private var blackClockVisual: some View {
        HStack(spacing: 12) {
            phoneShell {
                VStack(spacing: 14) {
                    Text("screen looks off")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    Text("→→  ↓←")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                    Text("37")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                PDFTinyRow("1", "Each digit = 2 swipes")
                PDFTinyRow("2", "Short vibration after each pair")
                PDFTinyRow("3", "Wait 3 seconds to confirm")
                PDFTinyRow("4", "Tap anywhere to dismiss")
            }
        }
    }

    private var cardClockVisual: some View {
        HStack(spacing: 12) {
            phoneShell {
                VStack(spacing: 10) {
                    Text("Q♣")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("↑↑  ↓")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                    Text("2 swipes value + 1 suit")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                PDFTinyRow("A", "Value: Q = ↑↑")
                PDFTinyRow("B", "Suit: Clubs = ↓")
                PDFTinyRow("C", "Total = 3 swipes")
                PDFTinyRow("D", "Wait 3 seconds")
            }
        }
    }

    private var lockscreenVisual: some View {
        HStack(spacing: 12) {
            phoneShell {
                VStack(spacing: 9) {
                    HStack(spacing: 8) {
                        ForEach(0..<4) { _ in Circle().fill(Color.white).frame(width: 8, height: 8) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 3), spacing: 8) {
                        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { digit in
                            Text("\(digit)")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                PDFTinyRow("1", "Enter secret digits first")
                PDFTinyRow("2", "Tap outside to lock them")
                PDFTinyRow("3", "Spectator taps are ignored")
                PDFTinyRow("4", "Looks like normal unlock")
            }
        }
    }

    private var forceReelVisual: some View {
        HStack(spacing: 8) {
            PDFStageBox(number: "1", title: "Grid", text: "Hidden digit map", color: color)
            PDFArrow()
            PDFStageBox(number: "2", title: "Dial", text: "Following = 13", color: color)
            PDFArrow()
            PDFStageBox(number: "3", title: "Explore", text: "#13 forced reel", color: color)
        }
    }

    private var counterGlitchVisual: some View {
        HStack(spacing: 8) {
            PDFStageBox(number: "1", title: "Your Profile", text: "register 37", color: color)
            PDFArrow()
            PDFStageBox(number: "2", title: "Spectator", text: "inflated +37", color: color)
            PDFArrow()
            PDFStageBox(number: "3", title: "Glitch", text: "volume → countdown", color: color)
            PDFArrow()
            PDFStageBox(number: "4", title: "Conviction", text: "real phone confirms", color: color)
        }
    }

    private var dateForceVisual: some View {
        HStack(spacing: 8) {
            PDFStageBox(number: "1", title: "Selection", text: "followers picked", color: color)
            PDFArrow()
            PDFStageBox(number: "2", title: "Sum", text: "date + time groups", color: color)
            PDFArrow()
            PDFStageBox(number: "3", title: "Explore", text: "stranger profile", color: color)
            PDFArrow()
            PDFStageBox(number: "4", title: "Reveal", text: "today's date", color: color)
        }
    }

    private var amnesiaVisual: some View {
        HStack(spacing: 10) {
            VStack(spacing: 5) {
                Text("Before")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                HStack(spacing: 4) {
                    ForEach(["○", "✚", "〰", "□"], id: \.self) { symbol in
                        Text(symbol).font(.system(size: 15)).frame(width: 24, height: 24).background(Color.white).cornerRadius(4)
                    }
                }
            }
            PDFArrow()
            VStack(spacing: 5) {
                Text("After refresh")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                HStack(spacing: 4) {
                    ForEach(["○", "✚", "〰", "□", "★"], id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 15))
                            .foregroundColor(symbol == "★" ? .orange : Color(hex: "111"))
                            .frame(width: 24, height: 24)
                            .background(Color.white)
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            Text("same date\nthe memory changed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "444"))
        }
    }

    private var profileConfirmVisual: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [Color.yellow, Color.orange, Color.pink, Color.yellow],
                            center: .center
                        ),
                        lineWidth: 5
                    )
                    .frame(width: 54, height: 54)
                Circle()
                    .fill(Color(hex: "F2F2F2"))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.fill")
                    .foregroundColor(Color(hex: "555"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Real Instagram confirmed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                Text("Double vibration + orange ring = safe to show the spectator.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "444"))
            }
        }
    }

    private func phoneShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .frame(width: 94, height: 158)
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 82, height: 144)
            content()
                .frame(width: 76, height: 132)
        }
    }
}

private struct PDFSettingsCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.13))
                .cornerRadius(7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "111"))
                Text(subtitle)
                    .font(.system(size: 8.5))
                    .foregroundColor(Color(hex: "666"))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .background(Color.white)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct PDFPhoneFrame<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Circle().fill(Color.white.opacity(0.35)).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black)

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(hex: "F7F7F8"))
        }
        .frame(width: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
    }
}

private struct PDFMiniSetCard: View {
    let title: String
    let status: String
    let method: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "photo.fill").font(.system(size: 12)).foregroundColor(color))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                    Text(status)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color(hex: "666"))
                }
                Spacer()
            }
            HStack {
                Text(method)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(5)
                Spacer()
                Text("Configure")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color)
                    .cornerRadius(5)
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.16), lineWidth: 1))
    }
}

private struct PDFPickerRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(Color(hex: "666"))
                Text(value)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "111"))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color)
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct PDFToggleRow: View {
    let title: String
    let isOn: Bool
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(hex: "222"))
            Spacer()
            Capsule()
                .fill(isOn ? color : Color(hex: "CCCCCC"))
                .frame(width: 32, height: 18)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: isOn ? 7 : -7)
                )
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
    }
}

private struct PDFTextFieldMock: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "222"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white)
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct PDFButtonLabel: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color)
            .cornerRadius(8)
    }
}

private struct PDFTinyRow: View {
    let marker: String
    let text: String

    init(_ marker: String, _ text: String) {
        self.marker = marker
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(hex: "111")))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "333"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PDFStageBox: View {
    let number: String
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(color))
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "111"))
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "555"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }
}

private struct PDFArrow: View {
    var body: some View {
        Text("→")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Color(hex: "777"))
    }
}

private struct PDFSectionLabel: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .tracking(0.6)
    }
}

private struct PDFPill: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "111"))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(color.opacity(0.08))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.2), lineWidth: 0.6))
    }
}

// MARK: - ShareSheet wrapper

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss?() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
