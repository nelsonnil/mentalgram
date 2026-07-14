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

    var profileSearchQueries: [String] {
        var seen = Set<String>()
        return (normalizedUsernameCandidates + [displayName ?? ""])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func normalizeUsername(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }
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

        CRITICAL USERNAME INSTRUCTIONS:
        - The exact Instagram username/profile is the most important output. Spend extra attention on it before answering.
        - Read the profile username from the largest profile/header area when visible, and cross-check it with any repeated username in the post header or navigation bar.
        - Preserve dots, underscores, numbers, repeated letters, accents when part of displayName, and exact letter order.
        - Do not autocorrect to a more famous or more likely account. Report what is actually visible.
        - Do not return alternative guesses. Keep usernameCandidates empty unless a second username is clearly visible on screen.
        - If the exact username is blurry, leave username empty rather than guessing.
        - If only the display name is visible, leave username empty if needed and set displayName.
        - Example: "veronicaluis._", "veronicaluis_", "veronicalius._" and "veronicalius_" are all different.
        - The app will search Instagram afterwards if the exact username does not match, so one truthful exact answer or an empty username is better than invented alternatives.

        MATCHING METADATA:
        - If visible, read the like count exactly into visibleLikeText (examples: "1.5 mill.", "35.3 mil", "12,482").
        - If visible, read the comment count exactly into visibleCommentText.
        - If visible, read repost/share/send counts into visibleShareText.
        - If these numbers are not visible, leave the fields empty. Do not estimate.
        - For Reels/videos, read large text overlays inside the video frame into imageTextVisible (examples: "LA PERSONA", quotes, subtitles, title cards).
        - For Reels/videos, read the visible title/caption line directly below the username/profile row into captionVisible. This line is HIGH PRIORITY because it often identifies the exact Reel even when the thumbnail is a different frame.
        - If vertical side counters are visible, assign each number to its correct icon: heart=likes, speech bubble=comments, paper plane/share=shares. Do not move a comments/share number into likes.
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
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["es-ES", "en-US"]
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: Self.cgImagePropertyOrientation(from: image.imageOrientation),
                options: [:]
            )
            do {
                try handler.perform([request])
                return (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
            } catch {
                return ""
            }
        }.value
    }

    func localUsernameCandidates(from text: String) -> [String] {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let pattern = #"@?[a-z0-9._]{3,30}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let stopwords: Set<String> = [
            "instagram", "seguir", "seguidos", "publicaciones", "comentario",
            "comentarios", "persona", "reels", "reel", "video", "likes", "share",
            "como", "sabes", "estas", "para", "porque", "cuando", "desde"
        ]
        var seen = Set<String>()
        return regex.matches(in: normalized, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let token = String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: "@._"))
            guard token.count >= 3,
                  !token.allSatisfy(\.isNumber),
                  !stopwords.contains(token),
                  seen.insert(token).inserted else { return nil }
            return token
        }
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

        let hydrated = await hydrateCandidates(candidates)
        guard !hydrated.isEmpty else {
            guard let fallbackItem = candidates.first else { throw AIScreenDetectionError.noCandidates }
            print("⚠️ [AI SCREEN] Candidates exist but images could not hydrate; using first post fallback mediaId=\(fallbackItem.mediaId)")
            return AIScreenResolvedPostMatch(
                candidate: AIScreenCandidateImage(item: fallbackItem, image: UIImage()),
                confidence: 0,
                reason: "profile_candidates_unhydrated_fallback",
                isLowConfidence: true
            )
        }

        if let titlePrefixCandidate = strictTitlePrefixShortcutMatch(analysis: analysis, hydrated: hydrated, localOCRText: localOCRText) {
            print("⚡️ [AI SCREEN] Strict title-prefix shortcut selected mediaId=\(titlePrefixCandidate.item.mediaId)")
            return AIScreenResolvedPostMatch(
                candidate: titlePrefixCandidate,
                confidence: 0.96,
                reason: "strict_title_prefix_shortcut",
                isLowConfidence: false
            )
        }

        if let strictStatsCandidate = strictStatsShortcutMatch(analysis: analysis, hydrated: hydrated) {
            print("⚡️ [AI SCREEN] Strict stats shortcut selected mediaId=\(strictStatsCandidate.item.mediaId)")
            return AIScreenResolvedPostMatch(
                candidate: strictStatsCandidate,
                confidence: 0.9,
                reason: "strict_stats_shortcut",
                isLowConfidence: false
            )
        }

        if let textCandidate = strictVisibleTextShortcutMatch(analysis: analysis, hydrated: hydrated, localOCRText: localOCRText) {
            print("⚡️ [AI SCREEN] Strict visible-text shortcut selected mediaId=\(textCandidate.item.mediaId)")
            return AIScreenResolvedPostMatch(
                candidate: textCandidate,
                confidence: 0.86,
                reason: "strict_visible_text_shortcut",
                isLowConfidence: false
            )
        }

        let collage = makeCandidateCollage(hydrated)
        let candidateText = hydrated.enumerated().map { index, candidate in
            let item = candidate.item
            let date = item.takenAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            return """
            \(index + 1). mediaId=\(item.mediaId), owner=\(item.ownerUsername ?? ""), date=\(date), caption=\((item.caption ?? "").prefix(160))
            """
        }.joined(separator: "\n")

        let text = """
        La primera imagen es una foto tomada a una pantalla de Instagram. La segunda imagen es un collage numerado de candidatos del perfil @\(analysis.normalizedUsername).

        Datos extraidos de la pantalla:
        username: \(analysis.normalizedUsername)
        dateText: \(analysis.dateText ?? "")
        visibleLikeText: \(analysis.visibleLikeText ?? "")
        visibleCommentText: \(analysis.visibleCommentText ?? "")
        visibleShareText: \(analysis.visibleShareText ?? "")
        captionVisible: \(analysis.captionVisible ?? "")
        imageTextVisible: \(analysis.imageTextVisible ?? "")
        visualDescription: \(analysis.visualDescription ?? "")
        localOCRText: \(localOCRText)

        Candidatos:
        \(candidateText)

        Elige el numero del candidato que coincide con el post de la pantalla.
        IMPORTANTE PARA REELS/VIDEOS: la miniatura del collage puede NO ser el mismo frame visible del video. En ese caso, no dependas solo de la miniatura. La prioridad mas alta es el titulo/caption visible debajo del username o en la parte inferior del video, porque suele ser unico del Reel. Despues usa texto grande visible en el video, subtitulos, caption, username y contadores laterales extraidos arriba. Por ejemplo, si el frame visible dice "LA PERSONA" o debajo aparece un titulo como "COMO SABES SI ESTAS...", busca ese texto o una frase muy relacionada en los candidatos.
        No inventes coincidencias: si no hay señal clara visual/textual/estadistica, usa selectedIndex 0. Devuelve SOLO JSON valido:
        {"selectedIndex":1,"confidence":0.0,"reason":""}
        Si no hay coincidencia clara o la confianza es baja, usa selectedIndex 0.
        """

        let content = try await sendVisionRequest(
            apiKey: apiKey,
            model: settings.openAIModel,
            text: text,
            images: [screenPhoto, collage],
            maxTokens: 300
        )
        let match = try decodeJSON(AIScreenPostMatch.self, from: content)
        let visualCandidate: AIScreenCandidateImage? = {
            guard match.selectedIndex > 0, match.selectedIndex <= hydrated.count else { return nil }
            return hydrated[match.selectedIndex - 1]
        }()

        if let visualCandidate, match.confidence >= 0.78 {
            return AIScreenResolvedPostMatch(
                candidate: visualCandidate,
                confidence: match.confidence,
                reason: match.reason ?? "visual",
                isLowConfidence: false
            )
        }

        if let statsCandidate = statsFallbackMatch(analysis: analysis, hydrated: hydrated) {
            return AIScreenResolvedPostMatch(
                candidate: statsCandidate,
                confidence: max(match.confidence, 0.62),
                reason: "stats_fallback",
                isLowConfidence: match.confidence < 0.78
            )
        }

        return AIScreenResolvedPostMatch(
            candidate: visualCandidate ?? hydrated[0],
            confidence: match.confidence,
            reason: match.reason ?? "low_confidence_fallback",
            isLowConfidence: true
        )
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
        let targetLikes = parseCount(analysis.visibleLikeText)
        let targetComments = parseCount(analysis.visibleCommentText)
        guard targetLikes != nil || targetComments != nil else { return nil }

        let scored = hydrated.compactMap { candidate -> (candidate: AIScreenCandidateImage, score: Double, evidence: Int)? in
            let item = candidate.item
            var score = 0.0
            var evidence = 0

            if let targetLikes, let likes = item.likeCount {
                evidence += 1
                score += strictCountScore(actual: likes, target: targetLikes)
            }
            if let targetComments, let comments = item.commentCount {
                evidence += 1
                score += strictCountScore(actual: comments, target: targetComments)
            }

            guard evidence > 0 else { return nil }
            return (candidate, score / Double(evidence), evidence)
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first else { return nil }
        let runnerUpScore = scored.dropFirst().first?.score ?? 0
        let hasStrongEvidence = best.evidence >= 2 ? best.score >= 0.92 : best.score >= 0.98
        guard hasStrongEvidence, best.score - runnerUpScore >= 0.22 else { return nil }
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
        guard targetLikes != nil || targetComments != nil else { return nil }

        let scored = hydrated.compactMap { candidate -> (candidate: AIScreenCandidateImage, score: Double)? in
            let item = candidate.item
            var score = 0.0
            var evidence = 0

            if let targetLikes, let likes = item.likeCount {
                evidence += 1
                score += closenessScore(actual: likes, target: targetLikes)
            }
            if let targetComments, let comments = item.commentCount {
                evidence += 1
                score += closenessScore(actual: comments, target: targetComments)
            }

            guard evidence > 0 else { return nil }
            return (candidate, score / Double(evidence))
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first, best.score >= 0.72 else { return nil }
        if scored.count > 1, best.score - scored[1].score < 0.12 { return nil }
        return best.candidate
    }

    private func closenessScore(actual: Int, target: Int) -> Double {
        guard target > 0 else { return 0 }
        let diff = abs(Double(actual - target))
        let tolerance = max(Double(target) * 0.08, 25)
        return max(0, 1 - diff / tolerance)
    }

    private func strictCountScore(actual: Int, target: Int) -> Double {
        guard target >= 0 else { return 0 }
        let diff = abs(actual - target)
        let tolerance = max(Int((Double(max(target, 1)) * 0.015).rounded()), 2)
        guard diff <= tolerance else { return 0 }
        return 1 - (Double(diff) / Double(max(tolerance, 1)))
    }

    private func meaningfulTerms(_ text: String) -> Set<String> {
        Set(orderedMeaningfulTerms(text))
    }

    private func orderedMeaningfulTerms(_ text: String) -> [String] {
        let stopwords: Set<String> = [
            "instagram", "publicacion", "publicaciones", "seguir", "seguidos",
            "persona", "video", "reel", "foto", "comment", "comments", "like", "likes",
            "the", "and", "para", "con", "por", "una", "uno", "las", "los", "que", "del"
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
            return stopwords.contains(term) ? nil : term
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

    private func parseCount(_ text: String?) -> Int? {
        guard var raw = text?.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        var multiplier = 1.0
        if raw.contains("mill") || raw.contains("m ") || raw.hasSuffix("m") {
            multiplier = 1_000_000
        } else if raw.contains("mil") || raw.contains("k") {
            multiplier = 1_000
        }
        raw = raw
            .replacingOccurrences(of: "millones", with: "")
            .replacingOccurrences(of: "mill.", with: "")
            .replacingOccurrences(of: "mill", with: "")
            .replacingOccurrences(of: "mil", with: "")
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
