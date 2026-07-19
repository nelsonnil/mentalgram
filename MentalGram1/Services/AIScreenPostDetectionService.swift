import Foundation
import UIKit
import Vision

struct AIScreenPostAnalysis: Codable {
    let platform: String?
    let isInstagramPost: Bool
    let username: String
    let usernameCandidates: [String]?
    let displayName: String?
    let dateText: String?
    let relativeDate: String?
    let visibleLikeText: String?
    let visibleCommentText: String?
    let visibleShareText: String?
    let captionVisible: String?
    let imageTextVisible: String?
    let visualDescription: String?
    let mainObjects: [String]?
    let peopleVisible: [String]?
    let locationText: String?
    let postType: String?
    let confidence: Double
    let missingOrUnclear: [String]?

    var normalizedUsername: String {
        Self.normalizeUsername(username)
    }

    var normalizedUsernameCandidates: [String] {
        var seen = Set<String>()
        return ([username] + (usernameCandidates ?? []))
            .map(Self.normalizeUsername)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Primary Instagram search queries. Display names are excluded here to avoid fuzzy friend hits.
    var profileSearchQueries: [String] {
        var seen = Set<String>()
        return normalizedUsernameCandidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Controlled fallback only when username is empty and displayName looks handle-like (not a phrase).
    /// Copy with corrected engagement counter texts (used when likes are hidden and GPT shifts icons).
    func withEngagementTexts(likes: String?, comments: String?, shares: String?) -> AIScreenPostAnalysis {
        AIScreenPostAnalysis(
            platform: platform,
            isInstagramPost: isInstagramPost,
            username: username,
            usernameCandidates: usernameCandidates,
            displayName: displayName,
            dateText: dateText,
            relativeDate: relativeDate,
            visibleLikeText: likes,
            visibleCommentText: comments,
            visibleShareText: shares,
            captionVisible: captionVisible,
            imageTextVisible: imageTextVisible,
            visualDescription: visualDescription,
            mainObjects: mainObjects,
            peopleVisible: peopleVisible,
            locationText: locationText,
            postType: postType,
            confidence: confidence,
            missingOrUnclear: missingOrUnclear
        )
    }

    var displayNameSearchQuery: String? {
        guard normalizedUsername.isEmpty else { return nil }
        let cleaned = (displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.count >= 5, cleaned.count <= 30 else { return nil }
        guard !cleaned.contains(" ") else { return nil }
        guard cleaned.range(of: #"^[a-z0-9._]+$"#, options: .regularExpression) != nil else { return nil }
        return cleaned
    }

    static func normalizeUsername(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }
}

struct AIScreenOCRObservation {
    let text: String
    /// Vision normalized box: origin bottom-left, y increases upward. 1 = top of image.
    let boundingBox: CGRect
}

struct AIScreenAuthorOCRResult {
    let fullText: String
    let matchingText: String
    let authorCandidates: [String]
}

struct AIScreenPostMatch: Codable {
    let selectedIndex: Int
    let confidence: Double
    let reason: String?
}

struct AIScreenResolvedPostMatch {
    let candidate: AIScreenCandidateImage
    let confidence: Double
    let reason: String
    let isLowConfidence: Bool
}

struct AIScreenCandidateImage {
    let item: InstagramMediaItem
    let image: UIImage
}

enum AIScreenDetectionError: LocalizedError {
    case missingAPIKey
    case invalidImage
    case invalidOpenAIResponse
    case noUsername
    case noCandidates
    case noMatch

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OpenAI API key is missing."
        case .invalidImage: return "Could not prepare the image for OpenAI."
        case .invalidOpenAIResponse: return "OpenAI response could not be parsed."
        case .noUsername: return "OpenAI could not read the Instagram username."
        case .noCandidates: return "No candidate posts were available for matching."
        case .noMatch: return "OpenAI did not select a valid matching post."
        }
    }
}

final class AIScreenPostDetectionService {
    static let shared = AIScreenPostDetectionService()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private init() {}

    func analyzeScreenPhoto(_ image: UIImage, allowMissingUsername: Bool = false) async throws -> AIScreenPostAnalysis {
        let settings = IntegrationsSettings.shared
        let apiKey = settings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw AIScreenDetectionError.missingAPIKey }

        let prompt = settings.aiScreenDetectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernamePrecisionInstructions = """

        CRITICAL USERNAME INSTRUCTIONS (language-agnostic):
        - The exact Instagram AUTHOR username is the most important output.
        - Read username ONLY from the post author header: next to the avatar, and/or under the top navigation title (Posts / Publicaciones / Publications / Beitrage / etc.).
        - Cross-check if the same author handle repeats at the start of the caption.
        - NEVER use usernames from like-rows ("Liked by..." / "Les gusta a..." / equivalents), comments, suggested accounts, music/audio rows, stickers, or buttons.
        - NEVER invent usernames from count units (mil/mill/k/thousand/mille/etc.) or OCR garbage like "mll".
        - NEVER use music artist names as username.
        - NEVER use UI button labels in any language (Follow/Seguir/Watch again/Ver otra vez/etc.).
        - Preserve dots, underscores, numbers, repeated letters, and exact letter order.
        - Do not autocorrect to a more famous account. Report only what is visible in the author header.
        - Keep usernameCandidates empty unless the SAME author handle appears with a tiny OCR ambiguity (dots/underscores). Never put a second social person there.
        - If the exact author username is blurry, leave username empty rather than guessing.
        - If only a display name is visible in the author header, leave username empty and set displayName.

        MATCHING METADATA:
        - Engagement icon order (L→R bottom/side bar): heart (likes) → speech bubble (comments) → circular repost arrows (shares/reposts) → paper plane (send, usually no count).
        - If visible, read the like count exactly into visibleLikeText (examples: "1.5 mill.", "35.3 mil", "12,482", "32.4K", "4787"). These are NOT usernames.
        - CRITICAL HIDDEN LIKES: if the heart has NO digit beside it, visibleLikeText MUST be "". Do NOT put the next icon's number into likes.
          Example: heart(empty) + bubble "44" + repost "48" → visibleLikeText="", visibleCommentText="44", visibleShareText="48".
          WRONG: likes="44", comments="48", shares="".
        - "Liked by…" / "Les gusta a…" can still appear when the like COUNT is hidden — that is NOT a like number.
        - If visible, read the comment count into visibleCommentText (speech-bubble number).
        - If visible, read the reshare/repost circular-arrow count into visibleShareText. Prefer reshare/repost over paper-plane send.
        - When likes are hidden, comments + shares are CRITICAL for identifying the post.
        - Counters are CRITICAL for matching when caption is missing or the media is a Reel/video.
        - If these numbers are not visible, leave the fields empty. Do not estimate.
        - For Reels/videos, read large text overlays inside the video frame into imageTextVisible. Ignore replay/more-reels UI overlays in any language.
        - For Reels/videos, read the visible title/caption line directly below the username/profile row into captionVisible. HIGH PRIORITY for identifying the Reel.
        - Thumbnail/frame similarity is unreliable for videos; prioritize caption/overlay/counts.
        - If a post has no useful caption and only comments are visible, leave captionVisible empty; do NOT put comment authors into username.
        """
        let content = try await sendVisionRequest(
            apiKey: apiKey,
            model: settings.openAIModel,
            text: (prompt.isEmpty ? IntegrationsSettings.defaultAIScreenDetectionPrompt : prompt) + usernamePrecisionInstructions,
            images: [image],
            maxTokens: 600
        )
        let analysis = try decodeJSON(AIScreenPostAnalysis.self, from: content)
        guard allowMissingUsername || !analysis.profileSearchQueries.isEmpty else { throw AIScreenDetectionError.noUsername }
        return analysis
    }

    func recognizeLocalText(in image: UIImage) async -> String {
        let observations = await recognizeLocalObservations(in: image)
        return observations.map(\.text).joined(separator: " ")
    }

    /// Accurate OCR with bounding boxes for author extraction and caption matching.
    func recognizeLocalObservations(in image: UIImage) async -> [AIScreenOCRObservation] {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            // Broad language coverage; username handles are still Latin alphanumeric.
            request.recognitionLanguages = ["es-ES", "en-US", "fr-FR", "pt-BR", "de-DE", "it-IT"]
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: Self.cgImagePropertyOrientation(from: image.imageOrientation),
                options: [:]
            )
            do {
                try handler.perform([request])
                return (request.results ?? []).compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return AIScreenOCRObservation(text: text, boundingBox: observation.boundingBox)
                }
            } catch {
                return []
            }
        }.value
    }

    /// Author usernames from top band only; full/matching text for post matching.
    func extractAuthorOCR(from image: UIImage) async -> AIScreenAuthorOCRResult {
        let observations = await recognizeLocalObservations(in: image)
        let fullText = observations.map(\.text).joined(separator: " ")
        let matchingText = observations
            .filter { !Self.isLikelySocialNoiseLine($0.text) }
            .map(\.text)
            .joined(separator: " ")
        let authorCandidates = authorUsernameCandidates(from: observations)
        return AIScreenAuthorOCRResult(
            fullText: fullText,
            matchingText: matchingText,
            authorCandidates: authorCandidates
        )
    }

    /// Legacy bag-of-words helper. Prefer `extractAuthorOCR` / top-band candidates for usernames.
    func localUsernameCandidates(from text: String) -> [String] {
        usernameTokens(from: text, minimumLength: 5)
    }

    func authorUsernameCandidates(from observations: [AIScreenOCRObservation]) -> [String] {
        // Vision Y: 1 = top. Author header lives in roughly the top 28%.
        let topBandMinY: CGFloat = 0.72
        let topObservations = observations.filter { $0.boundingBox.maxY >= topBandMinY || $0.boundingBox.midY >= topBandMinY }
        let source = topObservations.isEmpty ? Array(observations.prefix(8)) : topObservations

        var scores: [String: Double] = [:]
        for observation in source {
            let line = observation.text
            if Self.isLikelySocialNoiseLine(line) { continue }
            let topBias = max(0, observation.boundingBox.midY - topBandMinY) * 4.0
            for token in usernameTokens(from: line, minimumLength: 4) {
                guard token.count >= 5 || Self.hasStrongShortUsernameSignal(token, in: line) else { continue }
                scores[token, default: 0] += 1.0 + topBias
            }
        }

        // Bonus for tokens repeated across top-band lines (typical author handle).
        let topText = source.map(\.text).joined(separator: " ").lowercased()
        for (token, _) in scores {
            let occurrences = topText.components(separatedBy: token).count - 1
            if occurrences >= 2 {
                scores[token, default: 0] += 1.5
            }
        }

        return scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
            .prefix(6)
            .map { $0 }
    }

    /// Ranked author queries: consensus first, then OpenAI, then repeated local top-band.
    func rankedAuthorSearchQueries(openAI: [String], localTop: [String]) -> [String] {
        let open = openAI
            .map(AIScreenPostAnalysis.normalizeUsername)
            .filter { isPlausibleAuthorUsername($0) }
        let local = localTop
            .map(AIScreenPostAnalysis.normalizeUsername)
            .filter { isPlausibleAuthorUsername($0) }

        let localSet = Set(local)
        var ranked: [String] = []
        var seen = Set<String>()

        func append(_ values: [String]) {
            for value in values where seen.insert(value).inserted {
                ranked.append(value)
            }
        }

        append(open.filter { localSet.contains($0) })
        append(open)
        append(local)
        return Array(ranked.prefix(6))
    }

    func isPlausibleAuthorUsername(_ value: String) -> Bool {
        let token = AIScreenPostAnalysis.normalizeUsername(value)
        guard token.count >= 4, token.count <= 30 else { return false }
        guard !token.allSatisfy(\.isNumber) else { return false }
        guard token.range(of: #"^[a-z0-9._]+$"#, options: .regularExpression) != nil else { return false }
        guard !Self.usernameStopwords.contains(token) else { return false }
        guard !Self.isCountUnitToken(token) else { return false }
        return true
    }

    private static func hasStrongShortUsernameSignal(_ token: String, in line: String) -> Bool {
        guard token.count == 4 else { return true }
        if token.contains(".") || token.contains("_") { return true }
        if token.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        // If OCR keeps an @ prefix in the source line, a 4-char handle is intentional.
        if line.lowercased().contains("@\(token)") { return true }
        return false
    }

    private func usernameTokens(from text: String, minimumLength: Int) -> [String] {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if Self.isLikelySocialNoiseLine(normalized) {
            return []
        }
        let pattern = #"@?[a-z0-9._]{3,30}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var seen = Set<String>()
        return regex.matches(in: normalized, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let token = String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: "@._"))
            guard isPlausibleAuthorUsername(token),
                  token.count >= minimumLength,
                  seen.insert(token).inserted else { return nil }
            return token
        }
    }

    private static let usernameStopwords: Set<String> = [
        // Product / chrome (multi-language)
        "instagram", "reels", "reel", "video", "videos", "posts", "post", "story", "stories",
        "follow", "following", "followers", "seguir", "seguidos", "seguidores", "suivre", "abonner",
        "abonnes", "abonnement", "iscritti", "segui", "seguito", "folgen", "gefolgt",
        "seguidores", "publicaciones", "publicacion", "publicacoes", "publicacao",
        "beitraege", "beitrage", "beitrag", "pubblicazioni", "pubblicazione",
        "publications", "publication", "投稿", "게시물",
        "comment", "comments", "comentario", "comentarios", "commentaires", "kommentare",
        "commenti", "comentarios", "comentarios", "댓글",
        "like", "likes", "share", "shares", "send", "save", "saved",
        "j’aime", "jaime", "curtidas", "curtir", "gefällt", "gefallt", "mi piace",
        "translation", "traduccion", "traduction", "ubersetzung", "traducao",
        "traduzione", "翻訳", "번역", "watch", "again", "more", "ver", "otra", "vez",
        "mas", "voir", "encore", "voirplus", "guardare", "ancora", "mehr", "ansehen",
        "suggested", "sugerencias", "suggestions", "vorschlag", "suggerimenti",
        "recomendado", "recomendados", "recomendadas",
        "liked", "gusta", "gustan", "les", "otros", "otras", "others", "autres", "andere",
        "altri", "altre", "outras", "outros",
        "persona", "personas", "people", "personnes", "personen",
        // Common filler words that OCR often picks as "usernames"
        "the", "and", "for", "with", "from", "this", "that", "your",
        "como", "sabes", "estas", "para", "porque", "cuando", "desde",
        "pour", "avec", "dans", "und", "oder", "mit", "von", "per", "con", "che",
        "song", "audio", "music", "musica", "musique", "musik", "original"
    ]

    private static func isCountUnitToken(_ token: String) -> Bool {
        let units: Set<String> = [
            "mil", "mill", "mll", "milo", "mill.", "k", "km", "mk",
            "thousand", "thousands", "million", "millions",
            "mille", "milhares", "milhao", "milhoes", "tausend", "mio",
            "millionen", "milioni", "mila", "万", "천", "만"
        ]
        if units.contains(token) { return true }
        // OCR noise around thousand-unit abbreviations: mll / rnil / nii
        if token.count <= 4,
           token.range(of: #"^m?l{1,3}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isLikelySocialNoiseLine(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        // Language-agnostic structural signals for like/comment social rows.
        let usernameLikePattern = #"@?[a-z0-9._]{5,30}"#
        let usernameMatches = (try? NSRegularExpression(pattern: usernameLikePattern))?
            .numberOfMatches(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)) ?? 0
        if usernameMatches >= 2, normalized.contains(" ") {
            // Multiple handles in one line usually means "liked by A and B" / comment row.
            return true
        }

        let markers = [
            // EN
            "liked by", "and others", "watch again", "watch more", "see translation", "suggested for you",
            // ES
            "les gusta a", "y mas personas", "ver mas reels", "ver otra vez", "ver traduccion", "sugerencias",
            // FR
            "aime par", "aime par", "et d autres", "voir la traduction", "regarder a nouveau",
            // PT
            "curtido por", "curtida por", "curtidas por", "e outras", "e outros", "ver traducao", "assistir novamente",
            // DE
            "gefallt", "gefallen", "und andere", "ubersetzung anzeigen", "noch einmal ansehen",
            // IT
            "piace a", "e altri", "e altre", "vedi traduzione",
            // NL / common EU variants
            "vind ik leuk", "en anderen", "vertaling bekijken",
            // Non-latin UI hints sometimes OCR'd as-is
            "翻訳を見る", "좋아요", "번역 보기"
        ]
        return markers.contains { normalized.contains($0) }
    }

    func testOpenAIConnection() async throws -> String {
        let settings = IntegrationsSettings.shared
        let apiKey = settings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw AIScreenDetectionError.missingAPIKey }

        let body: [String: Any] = [
            "model": settings.openAIModel.isEmpty ? "gpt-4o-mini" : settings.openAIModel,
            "messages": [
                ["role": "user", "content": "Reply with OK only."]
            ],
            "max_tokens": 3
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if (200...299).contains(statusCode) {
            return "OpenAI connected. Key and credits are working."
        }

        let message = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
        if statusCode == 401 {
            throw NSError(domain: "OpenAI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI API key."])
        }
        if statusCode == 429, message.lowercased().contains("quota") {
            throw NSError(domain: "OpenAI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI key is valid, but quota/credits are not available."])
        }
        throw NSError(domain: "OpenAI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func matchPost(
        screenPhoto: UIImage,
        analysis: AIScreenPostAnalysis,
        candidates: [InstagramMediaItem],
        localOCRText: String = ""
    ) async throws -> AIScreenCandidateImage {
        try await matchPostHybrid(
            screenPhoto: screenPhoto,
            analysis: analysis,
            candidates: candidates,
            localOCRText: localOCRText
        ).candidate
    }

    func matchPostHybrid(
        screenPhoto: UIImage,
        analysis: AIScreenPostAnalysis,
        candidates: [InstagramMediaItem],
        localOCRText: String = ""
    ) async throws -> AIScreenResolvedPostMatch {
        let settings = IntegrationsSettings.shared
        let apiKey = settings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw AIScreenDetectionError.missingAPIKey }

        // GPT often shifts counters left when likes are hidden (heart with no digit).
        let analysis = correctHiddenLikesCounterShift(analysis, localOCRText: localOCRText)
        logMatchAttemptHeader(analysis: analysis, candidateCount: candidates.count, localOCRText: localOCRText)

        let hydrated = await hydrateCandidates(candidates)
        guard !hydrated.isEmpty else {
            guard let fallbackItem = candidates.first else { throw AIScreenDetectionError.noCandidates }
            print("⚠️ [VISUAL MATCH] Candidates exist but images could not hydrate; using first post fallback mediaId=\(fallbackItem.mediaId)")
            LogManager.shared.warning("Visual match hydrate failed — first fallback mediaId=\(fallbackItem.mediaId)", category: .general)
            return AIScreenResolvedPostMatch(
                candidate: AIScreenCandidateImage(item: fallbackItem, image: UIImage()),
                confidence: 0,
                reason: "profile_candidates_unhydrated_fallback",
                isLowConfidence: true
            )
        }

        logCandidateStatsTable(hydrated)

        if let titlePrefixCandidate = strictTitlePrefixShortcutMatch(analysis: analysis, hydrated: hydrated, localOCRText: localOCRText) {
            logMatchDecision(reason: "strict_title_prefix_shortcut", mediaId: titlePrefixCandidate.item.mediaId, confidence: 0.96)
            return AIScreenResolvedPostMatch(
                candidate: titlePrefixCandidate,
                confidence: 0.96,
                reason: "strict_title_prefix_shortcut",
                isLowConfidence: false
            )
        }
        print("🔎 [VISUAL MATCH] Title-prefix shortcut: no unique match")

        if let strictStatsCandidate = strictStatsShortcutMatch(analysis: analysis, hydrated: hydrated) {
            logMatchDecision(reason: "strict_stats_shortcut", mediaId: strictStatsCandidate.item.mediaId, confidence: 0.9)
            return AIScreenResolvedPostMatch(
                candidate: strictStatsCandidate,
                confidence: 0.9,
                reason: "strict_stats_shortcut",
                isLowConfidence: false
            )
        }
        print("🔎 [VISUAL MATCH] Strict stats shortcut: no unique match")

        if let textCandidate = strictVisibleTextShortcutMatch(analysis: analysis, hydrated: hydrated, localOCRText: localOCRText) {
            logMatchDecision(reason: "strict_visible_text_shortcut", mediaId: textCandidate.item.mediaId, confidence: 0.86)
            return AIScreenResolvedPostMatch(
                candidate: textCandidate,
                confidence: 0.86,
                reason: "strict_visible_text_shortcut",
                isLowConfidence: false
            )
        }
        print("🔎 [VISUAL MATCH] Visible-text shortcut: no unique match")

        // Prefer GPT counters before collage/thumbnail comparison. Reels/videos often have
        // thumbnails that do not match the visible frame, so image similarity is unreliable.
        if let statsCandidate = statsFallbackMatch(analysis: analysis, hydrated: hydrated) {
            logMatchDecision(reason: "stats_fallback_before_collage", mediaId: statsCandidate.item.mediaId, confidence: 0.72)
            return AIScreenResolvedPostMatch(
                candidate: statsCandidate,
                confidence: 0.72,
                reason: "stats_fallback_before_collage",
                isLowConfidence: false
            )
        }
        print("🔎 [VISUAL MATCH] Stats fallback: no unique match")

        let postType = (analysis.postType ?? "").lowercased()
        let isVideoLike = postType.contains("reel") || postType.contains("video")
        let hasUsefulCaption = !(analysis.captionVisible ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(analysis.imageTextVisible ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // For Reels/videos without caption/overlay text, skip thumbnail collage matching.
        if isVideoLike && !hasUsefulCaption {
            let fallbackIndex = fallbackCandidateIndex(for: hydrated, preferFirst: true)
            return AIScreenResolvedPostMatch(
                candidate: hydrated[fallbackIndex],
                confidence: 0,
                reason: "video_no_caption_center_fallback",
                isLowConfidence: true
            )
        }

        let collage = makeCandidateCollage(hydrated)
        let candidateText = hydrated.enumerated().map { index, candidate in
            let item = candidate.item
            let date = item.takenAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let likes = item.likeCount.map(String.init) ?? ""
            let comments = item.commentCount.map(String.init) ?? ""
            let shares = item.shareCount.map(String.init) ?? ""
            return """
            \(index + 1). mediaId=\(item.mediaId), owner=\(item.ownerUsername ?? ""), date=\(date), likes=\(likes), comments=\(comments), shares=\(shares), caption=\((item.caption ?? "").prefix(160))
            """
        }.joined(separator: "\n")

        let text = """
        The first image is a photo of an Instagram screen. The second image is a numbered collage of candidate posts from @\(analysis.normalizedUsername).

        Screen-extracted data:
        username: \(analysis.normalizedUsername)
        dateText: \(analysis.dateText ?? "")
        visibleLikeText: \(analysis.visibleLikeText ?? "")
        visibleCommentText: \(analysis.visibleCommentText ?? "")
        visibleShareText: \(analysis.visibleShareText ?? "")
        captionVisible: \(analysis.captionVisible ?? "")
        imageTextVisible: \(analysis.imageTextVisible ?? "")
        visualDescription: \(analysis.visualDescription ?? "")
        localOCRText: \(localOCRText)
        postType: \(analysis.postType ?? "")

        Candidates:
        \(candidateText)

        Choose the candidate number that matches the on-screen post.
        PRIORITY ORDER (language-agnostic):
        1) Title/caption text under the author username
        2) Large overlay text inside the media
        3) Comment/share/like counts (likes may be missing/hidden — then use comments + shares)
        4) Only then visual similarity of still images
        CRITICAL: For Reels/videos, collage thumbnails often show a DIFFERENT frame. Do NOT rely on thumbnail/image similarity for video/reel posts. Prefer caption/overlay/counts.
        If visibleLikeText is empty because likes are hidden, match using comments and shares.
        Ignore UI chrome in any language (Follow, Posts, See translation, Watch again, etc.).
        Ignore comment authors and "Liked by ..." people. They are not the post identity.
        If there is no clear textual/statistical signal, return selectedIndex 0.
        Return ONLY valid JSON:
        {"selectedIndex":1,"confidence":0.0,"reason":""}
        """

        print("🔎 [VISUAL MATCH] Calling OpenAI collage match (videoLike=\(isVideoLike) hasCaption=\(hasUsefulCaption))")
        let content = try await sendVisionRequest(
            apiKey: apiKey,
            model: settings.openAIModel,
            text: text,
            images: [screenPhoto, collage],
            maxTokens: 300
        )
        print("🤖 [VISUAL MATCH] Collage GPT raw: \(content.prefix(400))")
        LogManager.shared.info("Visual match collage GPT raw: \(content.prefix(400))", category: .general)

        let match = try decodeJSON(AIScreenPostMatch.self, from: content)
        print("🤖 [VISUAL MATCH] Collage GPT parsed selectedIndex=\(match.selectedIndex) confidence=\(match.confidence) reason=\(match.reason ?? "")")
        let visualCandidate: AIScreenCandidateImage? = {
            guard match.selectedIndex > 0, match.selectedIndex <= hydrated.count else { return nil }
            return hydrated[match.selectedIndex - 1]
        }()

        // Accept collage result mainly when text/caption evidence exists; never trust weak video thumbnail picks.
        let minVisualConfidence = isVideoLike ? 0.9 : 0.78
        if let visualCandidate, match.confidence >= minVisualConfidence, hasUsefulCaption || !isVideoLike {
            logMatchDecision(reason: match.reason ?? "collage_text_assisted", mediaId: visualCandidate.item.mediaId, confidence: match.confidence)
            return AIScreenResolvedPostMatch(
                candidate: visualCandidate,
                confidence: match.confidence,
                reason: match.reason ?? "collage_text_assisted",
                isLowConfidence: false
            )
        }

        let fallbackIndex = fallbackCandidateIndex(for: hydrated, preferFirst: isVideoLike)
        let fallback = visualCandidate ?? hydrated[fallbackIndex]
        logMatchDecision(
            reason: match.reason ?? "low_confidence_fallback",
            mediaId: fallback.item.mediaId,
            confidence: match.confidence,
            low: true
        )
        return AIScreenResolvedPostMatch(
            candidate: fallback,
            confidence: match.confidence,
            reason: match.reason ?? "low_confidence_fallback",
            isLowConfidence: true
        )
    }

    private func logMatchAttemptHeader(
        analysis: AIScreenPostAnalysis,
        candidateCount: Int,
        localOCRText: String
    ) {
        let likes = parseCount(analysis.visibleLikeText).map(String.init) ?? "nil"
        let comments = parseCount(analysis.visibleCommentText).map(String.init) ?? "nil"
        let shares = parseCount(analysis.visibleShareText).map(String.init) ?? "nil"
        let line = """
        📋 [VISUAL MATCH] GPT screen analysis \
        username=\(analysis.normalizedUsername) \
        postType=\(analysis.postType ?? "") \
        likesText='\(analysis.visibleLikeText ?? "")'(\(likes)) \
        commentsText='\(analysis.visibleCommentText ?? "")'(\(comments)) \
        sharesText='\(analysis.visibleShareText ?? "")'(\(shares)) \
        caption='\(analysis.captionVisible ?? "")' \
        imageText='\(analysis.imageTextVisible ?? "")' \
        confidence=\(analysis.confidence) \
        candidates=\(candidateCount) \
        localOCR='\(localOCRText.prefix(180))'
        """
        print(line)
        LogManager.shared.info(line, category: .general)
    }

    private func logCandidateStatsTable(_ hydrated: [AIScreenCandidateImage]) {
        let rows = hydrated.enumerated().map { index, candidate in
            let item = candidate.item
            let likes = item.likeCount.map(String.init) ?? "-"
            let comments = item.commentCount.map(String.init) ?? "-"
            let shares = item.shareCount.map(String.init) ?? "-"
            let pinned = item.isPinned == true ? "pin" : "-"
            let caption = (item.caption ?? "").prefix(40)
            return "#\(index + 1) id=\(item.mediaId) L=\(likes) C=\(comments) S=\(shares) \(pinned) '\(caption)'"
        }.joined(separator: " | ")
        print("📋 [VISUAL MATCH] Candidate stats: \(rows)")
        LogManager.shared.info("Visual match candidate stats: \(rows)", category: .general)
    }

    private func logMatchDecision(reason: String, mediaId: String, confidence: Double, low: Bool = false) {
        let prefix = low ? "⚠️" : "✅"
        let line = "\(prefix) [VISUAL MATCH] Decision reason=\(reason) mediaId=\(mediaId) confidence=\(confidence) low=\(low)"
        print(line)
        if low {
            LogManager.shared.warning(line, category: .general)
        } else {
            LogManager.shared.success(line, category: .general)
        }
    }

    private func fallbackCandidateIndex(for hydrated: [AIScreenCandidateImage], preferFirst: Bool = false) -> Int {
        guard !hydrated.isEmpty else { return 0 }
        if preferFirst || hydrated.contains(where: { $0.item.isPinned == true }) {
            return 0
        }
        return min(max(hydrated.count / 2, 0), hydrated.count - 1)
    }

    private func strictTitlePrefixShortcutMatch(
        analysis: AIScreenPostAnalysis,
        hydrated: [AIScreenCandidateImage],
        localOCRText: String
    ) -> AIScreenCandidateImage? {
        let titleSource = !(analysis.captionVisible ?? "").isEmpty ? (analysis.captionVisible ?? "") : localOCRText
        let prefixTerms = Array(orderedMeaningfulTerms(titleSource).prefix(5))
        guard prefixTerms.count >= 3 else { return nil }
        let prefix = prefixTerms.joined(separator: " ")

        let matches = hydrated.compactMap { candidate -> AIScreenCandidateImage? in
            guard let caption = candidate.item.caption, !caption.isEmpty else { return nil }
            let candidateTerms = orderedMeaningfulTerms(caption)
            guard candidateTerms.count >= prefixTerms.count else { return nil }

            let candidatePrefix = candidateTerms.prefix(prefixTerms.count).joined(separator: " ")
            let candidateText = candidateTerms.joined(separator: " ")
            if candidatePrefix == prefix || candidateText.contains(prefix) {
                return candidate
            }
            return fuzzyPrefixMatches(prefixTerms, candidateTerms) ? candidate : nil
        }

        return matches.count == 1 ? matches[0] : nil
    }

    private func fuzzyPrefixMatches(_ visiblePrefix: [String], _ candidateTerms: [String]) -> Bool {
        guard visiblePrefix.count >= 3, candidateTerms.count >= visiblePrefix.count else { return false }
        let candidatePrefix = Array(candidateTerms.prefix(visiblePrefix.count))
        var matches = 0

        for (visible, candidate) in zip(visiblePrefix, candidatePrefix) {
            if visible == candidate {
                matches += 1
                continue
            }
            if visible.count >= 5,
               candidate.count >= 5,
               levenshteinDistance(visible, candidate) <= 1 {
                matches += 1
            }
        }

        let required = visiblePrefix.count >= 5 ? 3 : visiblePrefix.count
        return matches >= required
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }

    private func strictStatsShortcutMatch(
        analysis: AIScreenPostAnalysis,
        hydrated: [AIScreenCandidateImage]
    ) -> AIScreenCandidateImage? {
        // Prefer GPT-read counters from the spectator screen (more reliable than local OCR near icons).
        // Likes may be hidden by the account — then comments + shares are the main signal.
        let targetLikes = parseCount(analysis.visibleLikeText)
        let targetComments = parseCount(analysis.visibleCommentText)
        var targetShares = parseCount(analysis.visibleShareText)
        let likesHidden = targetLikes == nil
        // Instagram often omits reshare_count on feed items — don't require shares if no candidate has them.
        let shareCoverage = hydrated.filter { $0.item.shareCount != nil }.count
        if targetShares != nil, shareCoverage == 0 {
            print("🔎 [VISUAL MATCH] Strict stats: screen has shares=\(targetShares.map(String.init) ?? "-") but 0 candidates expose shareCount — ignoring share target")
            targetShares = nil
        }
        guard targetLikes != nil || targetComments != nil || targetShares != nil else {
            print("🔎 [VISUAL MATCH] Strict stats: GPT provided no parseable counters")
            return nil
        }
        let availableTargets = [targetLikes, targetComments, targetShares].compactMap { $0 }.count
        print("🔎 [VISUAL MATCH] Strict stats targets likes=\(targetLikes.map(String.init) ?? "hidden/-") comments=\(targetComments.map(String.init) ?? "-") shares=\(targetShares.map(String.init) ?? "-") available=\(availableTargets) likesHidden=\(likesHidden) shareCoverage=\(shareCoverage)/\(hydrated.count) (tol ±3 / 1%)")

        let scored = hydrated.compactMap { candidate -> (candidate: AIScreenCandidateImage, score: Double, evidence: Int, possible: Int, detail: String)? in
            let item = candidate.item
            var score = 0.0
            var evidence = 0
            var possible = 0
            var parts: [String] = []

            // Only score likes when GPT actually saw a like count (account may hide likes).
            if let targetLikes, let likes = item.likeCount {
                possible += 1
                let part = countMatchScore(actual: likes, target: targetLikes)
                if part > 0 {
                    evidence += 1
                    score += part
                    parts.append("L\(likes)/\(targetLikes)=\(String(format: "%.2f", part))")
                }
            }
            if let targetComments, let comments = item.commentCount {
                possible += 1
                let part = countMatchScore(actual: comments, target: targetComments)
                if part > 0 {
                    evidence += 1
                    score += part
                    parts.append("C\(comments)/\(targetComments)=\(String(format: "%.2f", part))")
                }
            }
            if let targetShares, let shares = item.shareCount {
                possible += 1
                let part = countMatchScore(actual: shares, target: targetShares)
                if part > 0 {
                    evidence += 1
                    score += part
                    parts.append("S\(shares)/\(targetShares)=\(String(format: "%.2f", part))")
                }
            }

            guard evidence > 0 else { return nil }
            return (candidate, score / Double(evidence), evidence, possible, parts.joined(separator: ","))
        }
        .sorted { $0.score > $1.score }

        if let best = scored.first {
            print("🔎 [VISUAL MATCH] Strict stats best mediaId=\(best.candidate.item.mediaId) score=\(String(format: "%.2f", best.score)) evidence=\(best.evidence)/\(best.possible) \(best.detail)")
            if let second = scored.dropFirst().first {
                print("🔎 [VISUAL MATCH] Strict stats runner-up mediaId=\(second.candidate.item.mediaId) score=\(String(format: "%.2f", second.score)) evidence=\(second.evidence)/\(second.possible)")
            }
        }

        guard let best = scored.first else { return nil }
        let runnerUpScore = scored.dropFirst().first?.score ?? 0
        // Prefer 2+ counters. If likes are hidden, comments+shares is ideal.
        // If only one counter was readable on screen — or API omits shares for this item — require a unique fit.
        let requiredEvidence = min(availableTargets >= 2 ? 2 : 1, max(best.possible, 1))
        let hasStrongEvidence = best.evidence >= requiredEvidence
            ? best.score >= (likesHidden && best.evidence >= 2 ? 0.8 : 0.85)
            : best.score >= 0.98
        guard hasStrongEvidence, best.score - runnerUpScore >= 0.12 else {
            print("🔎 [VISUAL MATCH] Strict stats rejected (need unique fit; requiredEvidence=\(requiredEvidence) got=\(best.evidence)/\(best.possible))")
            return nil
        }
        return best.candidate
    }

    private func strictVisibleTextShortcutMatch(
        analysis: AIScreenPostAnalysis,
        hydrated: [AIScreenCandidateImage],
        localOCRText: String
    ) -> AIScreenCandidateImage? {
        let captionTerms = meaningfulTerms(analysis.captionVisible ?? "")
        let overlayTerms = meaningfulTerms(analysis.imageTextVisible ?? "")
        let descriptionTerms = meaningfulTerms(analysis.visualDescription ?? "")
        let localTerms = meaningfulTerms(localOCRText)
        var visibleTerms = captionTerms
        visibleTerms.formUnion(overlayTerms)
        visibleTerms.formUnion(descriptionTerms)
        visibleTerms.formUnion(localTerms)
        guard !visibleTerms.isEmpty else { return nil }

        var scored: [(candidate: AIScreenCandidateImage, score: Double)] = []
        for candidate in hydrated {
            let item = candidate.item
            let captionText = item.caption ?? ""
            let ownerText = item.ownerUsername ?? ""
            let searchable = "\(captionText) \(ownerText)"

            let candidateTerms = meaningfulTerms(searchable)
            guard !candidateTerms.isEmpty else { continue }
            let overlap = visibleTerms.intersection(candidateTerms)
            guard !overlap.isEmpty else { continue }

            let captionOverlap = captionTerms.intersection(candidateTerms)
            let overlayOverlap = overlayTerms.intersection(candidateTerms)
            let localOverlap = localTerms.intersection(candidateTerms)
            let strongOverlap = overlap.filter { $0.count >= 5 }.count
            let baseScore = Double(overlap.count) / Double(max(visibleTerms.count, 1))
            let captionScore = Double(captionOverlap.count) * 0.28
            let overlayScore = Double(overlayOverlap.count) * 0.16
            let localScore = Double(localOverlap.count) * 0.10
            let strongScore = Double(strongOverlap) * 0.18
            let score = baseScore + captionScore + overlayScore + localScore + strongScore
            scored.append((candidate: candidate, score: score))
        }
        scored.sort { $0.score > $1.score }

        guard let best = scored.first, best.score >= 0.62 else { return nil }
        if scored.count > 1, best.score - scored[1].score < 0.22 { return nil }
        return best.candidate
    }

    private func statsFallbackMatch(
        analysis: AIScreenPostAnalysis,
        hydrated: [AIScreenCandidateImage]
    ) -> AIScreenCandidateImage? {
        let targetLikes = parseCount(analysis.visibleLikeText)
        let targetComments = parseCount(analysis.visibleCommentText)
        var targetShares = parseCount(analysis.visibleShareText)
        let likesHidden = targetLikes == nil
        let shareCoverage = hydrated.filter { $0.item.shareCount != nil }.count
        if targetShares != nil, shareCoverage == 0 {
            targetShares = nil
        }
        let availableTargets = [targetLikes, targetComments, targetShares].compactMap { $0 }.count
        guard availableTargets > 0 else { return nil }

        // When likes are hidden, comments+shares alone are enough (requiredEvidence = 2 if both exist).
        // If API omits shares, a unique comment match can still win.
        let requiredEvidence = min(2, availableTargets)

        let scored = hydrated.compactMap { candidate -> (candidate: AIScreenCandidateImage, score: Double, evidence: Int)? in
            let item = candidate.item
            var score = 0.0
            var evidence = 0
            var possible = 0

            if let targetLikes, let likes = item.likeCount {
                possible += 1
                let part = countMatchScore(actual: likes, target: targetLikes)
                if part > 0 {
                    evidence += 1
                    score += part
                }
            }
            if let targetComments, let comments = item.commentCount {
                possible += 1
                let part = countMatchScore(actual: comments, target: targetComments)
                if part > 0 {
                    evidence += 1
                    score += part
                }
            }
            if let targetShares, let shares = item.shareCount {
                possible += 1
                let part = countMatchScore(actual: shares, target: targetShares)
                if part > 0 {
                    evidence += 1
                    score += part
                }
            }

            let needed = min(requiredEvidence, max(possible, 1))
            guard evidence >= needed else { return nil }
            return (candidate, score / Double(max(evidence, 1)), evidence)
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first, best.score >= 0.7 else {
            print("🔎 [VISUAL MATCH] Stats fallback: no candidate with ≥\(requiredEvidence) counters in tolerance (likesHidden=\(likesHidden))")
            return nil
        }
        if scored.count > 1, best.score - scored[1].score < 0.1 {
            print("🔎 [VISUAL MATCH] Stats fallback: ambiguous top-2 scores \(String(format: "%.2f", best.score)) vs \(String(format: "%.2f", scored[1].score))")
            return nil
        }
        print("🔎 [VISUAL MATCH] Stats fallback best mediaId=\(best.candidate.item.mediaId) score=\(String(format: "%.2f", best.score)) evidence=\(best.evidence) likesHidden=\(likesHidden)")
        return best.candidate
    }

    /// Absolute ±3 for typical counters; for large like counts also allow ~1%.
    private func countMatchScore(actual: Int, target: Int) -> Double {
        guard target >= 0, actual >= 0 else { return 0 }
        let diff = abs(actual - target)
        let tolerance = countTolerance(for: target)
        guard diff <= tolerance else { return 0 }
        if tolerance == 0 { return 1 }
        return 1 - (Double(diff) / Double(tolerance))
    }

    private func countTolerance(for target: Int) -> Int {
        if target >= 1000 {
            return max(3, Int((Double(target) * 0.01).rounded()))
        }
        return 3
    }

    private func meaningfulTerms(_ text: String) -> Set<String> {
        Set(orderedMeaningfulTerms(text))
    }

    private func orderedMeaningfulTerms(_ text: String) -> [String] {
        let stopwords: Set<String> = [
            "instagram", "publicacion", "publicaciones", "posts", "post", "seguir", "seguidos",
            "follow", "following", "followers", "persona", "personas", "people", "video", "reel",
            "reels", "foto", "photo", "comment", "comments", "like", "likes", "share", "shares",
            "mil", "mill", "mll", "thousand", "mille", "traduccion", "translation", "traduction",
            "ver", "otra", "vez", "mas", "watch", "again", "more", "gusta", "liked", "les",
            "the", "and", "para", "con", "por", "una", "uno", "las", "los", "que", "del",
            "others", "autres", "andere"
        ]
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let pattern = #"[a-z0-9_\.]{3,}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex?.matches(in: normalized, range: nsRange) ?? []
        return matches.compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let term = String(normalized[range])
            if stopwords.contains(term) || Self.isCountUnitToken(term) { return nil }
            return term
        }
    }

    private static func cgImagePropertyOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// When likes are hidden, GPT often fills likes/comments with the bubble+repost numbers and leaves shares empty.
    /// Shift left → comments/shares when OCR/UI signals confirm hidden likes.
    private func correctHiddenLikesCounterShift(
        _ analysis: AIScreenPostAnalysis,
        localOCRText: String
    ) -> AIScreenPostAnalysis {
        let likesText = analysis.visibleLikeText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commentsText = analysis.visibleCommentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sharesText = analysis.visibleShareText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Already looks correct (likes empty, comments+shares present).
        if likesText.isEmpty, !commentsText.isEmpty, !sharesText.isEmpty {
            return analysis
        }

        // Classic mis-shift: likes+comments filled, shares empty.
        guard !likesText.isEmpty, !commentsText.isEmpty, sharesText.isEmpty,
              let shiftedComments = parseCount(likesText),
              let shiftedShares = parseCount(commentsText) else {
            return analysis
        }

        let ocr = localOCRText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let likedBySignals = [
            "les gusta", "liked by", "liked", "gusta a", "mas personas", "and others",
            "y otras", "y otros", "autres personnes", "andere personen"
        ]
        let hasLikedByRow = likedBySignals.contains { ocr.contains($0) }

        // OCR often shows the two engagement digits in order near the action bar.
        let pairPattern = #"\b\#(shiftedComments)\b[^\d]{0,12}\b\#(shiftedShares)\b"#
        let hasAdjacentPair = (try? NSRegularExpression(pattern: pairPattern))
            .map { $0.firstMatch(in: ocr, range: NSRange(ocr.startIndex..<ocr.endIndex, in: ocr)) != nil }
            ?? false

        // Prefer correcting when UI/OCR says likes are hidden, or when the pair appears as-is in OCR.
        guard hasLikedByRow || hasAdjacentPair else { return analysis }

        print("🔧 [VISUAL MATCH] Corrected hidden-likes counter shift: likes='\(likesText)' comments='\(commentsText)' shares='' → likes='' comments='\(likesText)' shares='\(commentsText)' (likedBy=\(hasLikedByRow) adjacentPair=\(hasAdjacentPair))")
        LogManager.shared.info(
            "Visual match corrected hidden-likes shift likes=\(likesText) comments=\(commentsText) → comments=\(likesText) shares=\(commentsText)",
            category: .general
        )
        return analysis.withEngagementTexts(likes: "", comments: likesText, shares: commentsText)
    }

    private func parseCount(_ text: String?) -> Int? {
        guard var raw = text?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        var multiplier = 1.0
        if raw.contains("million") || raw.contains("millones") || raw.contains("mill.")
            || raw.contains("mio") || (raw.contains("mill") && !raw.contains("mille")) {
            multiplier = 1_000_000
        } else if raw.contains("thousand") || raw.contains("tausend") || raw.contains("milhares")
                    || raw.contains("mille") || raw.contains("mil") || raw.contains("k") {
            multiplier = 1_000
        } else if raw.hasSuffix("m"), raw.rangeOfCharacter(from: .decimalDigits) != nil {
            multiplier = 1_000_000
        }

        // Normalize decimal separators after detecting units.
        raw = raw.replacingOccurrences(of: ",", with: ".")
        raw = raw
            .replacingOccurrences(of: "millones", with: "")
            .replacingOccurrences(of: "million", with: "")
            .replacingOccurrences(of: "millions", with: "")
            .replacingOccurrences(of: "thousand", with: "")
            .replacingOccurrences(of: "thousands", with: "")
            .replacingOccurrences(of: "tausend", with: "")
            .replacingOccurrences(of: "milhares", with: "")
            .replacingOccurrences(of: "mille", with: "")
            .replacingOccurrences(of: "mill.", with: "")
            .replacingOccurrences(of: "mill", with: "")
            .replacingOccurrences(of: "mil", with: "")
            .replacingOccurrences(of: "mio", with: "")
            .replacingOccurrences(of: "k", with: "")
            .replacingOccurrences(of: "m", with: "")
            .filter { $0.isNumber || $0 == "." }

        guard let value = Double(raw) else { return nil }
        return Int((value * multiplier).rounded())
    }

    private func hydrateCandidates(_ candidates: [InstagramMediaItem]) async -> [AIScreenCandidateImage] {
        var hydrated: [AIScreenCandidateImage] = []
        for item in candidates {
            guard let image = await downloadImage(item.imageURL) else { continue }
            hydrated.append(AIScreenCandidateImage(item: item, image: image))
        }
        return hydrated
    }

    private func downloadImage(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        if let cached = ProfileCacheService.shared.loadImage(forURL: urlString) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            ProfileCacheService.shared.saveImage(image, forURL: urlString)
            return image
        } catch {
            return nil
        }
    }

    private func sendVisionRequest(
        apiKey: String,
        model: String,
        text: String,
        images: [UIImage],
        maxTokens: Int
    ) async throws -> String {
        let imagePayloads = try images.map { image -> [String: Any] in
            guard let data = image.jpegData(compressionQuality: 0.78) else {
                throw AIScreenDetectionError.invalidImage
            }
            return [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
            ]
        }

        var content: [[String: Any]] = [["type": "text", "text": text]]
        content.append(contentsOf: imagePayloads)

        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-4o-mini" : model,
            "messages": [["role": "user", "content": content]],
            "response_format": ["type": "json_object"],
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "OpenAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIScreenDetectionError.invalidOpenAIResponse
        }
        return content
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIScreenDetectionError.invalidOpenAIResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIScreenDetectionError.invalidOpenAIResponse
        }
    }

    private func makeCandidateCollage(_ candidates: [AIScreenCandidateImage]) -> UIImage {
        let columns = 3
        let cellSize = CGSize(width: 320, height: 400)
        let rows = Int(ceil(Double(candidates.count) / Double(columns)))
        let size = CGSize(width: CGFloat(columns) * cellSize.width, height: CGFloat(rows) * cellSize.height)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for (index, candidate) in candidates.enumerated() {
                let col = index % columns
                let row = index / columns
                let rect = CGRect(
                    x: CGFloat(col) * cellSize.width,
                    y: CGFloat(row) * cellSize.height,
                    width: cellSize.width,
                    height: cellSize.height
                )

                drawAspectFill(candidate.image, in: rect)
                UIColor.black.withAlphaComponent(0.72).setFill()
                UIBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: 74, height: 54)).fill()

                let number = "\(index + 1)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                number.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 8), withAttributes: attrs)
            }
        }
    }

    private func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}
