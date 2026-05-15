import Foundation

struct LearnedCorrection: Codable, Equatable, Identifiable {
    let id: UUID
    let rawText: String
    let correctedText: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        rawText: String,
        correctedText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawText = rawText
        self.correctedText = correctedText
        self.createdAt = createdAt
    }
}

enum TranscriptionPromptBuilder {
    static func effectiveLanguage(for language: String) -> String {
        language == "auto" ? "pt" : language
    }

    static func build(
        language: String,
        customVocabulary: String,
        corrections: [LearnedCorrection],
        maxTerms: Int = 40
    ) -> String {
        let effectiveLanguage = effectiveLanguage(for: language)

        if effectiveLanguage == "en" {
            return "Transcription in English with clear punctuation and capitalization."
        }

        var parts = [
            "Transcrição em Português Europeu (PT-PT), com pontuação natural e acentos corretos.",
            "Pode incluir Inglês técnico; preserva termos como deploy, meeting, feedback, sprint, feature e bug."
        ]

        let terms = vocabularyTerms(
            customVocabulary: customVocabulary,
            corrections: corrections,
            maxTerms: maxTerms
        )

        if !terms.isEmpty {
            parts.append("Keywords: \(terms.joined(separator: ", ")).")
        }

        let examples = corrections
            .suffix(4)
            .map { "\($0.rawText) -> \($0.correctedText)" }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !examples.isEmpty {
            parts.append("Correções anteriores: \(examples.joined(separator: " | ")).")
        }

        return parts.joined(separator: " ")
    }

    private static func vocabularyTerms(
        customVocabulary: String,
        corrections: [LearnedCorrection],
        maxTerms: Int
    ) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []

        func appendTerm(_ rawTerm: String) {
            let term = rawTerm
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard term.count >= 3 else { return }

            let key = term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !seen.contains(key) else { return }

            seen.insert(key)
            terms.append(term)
        }

        customVocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map(String.init)
            .forEach(appendTerm)

        for correction in corrections.suffix(20) {
            let rawTokens = normalizedTokenSet(correction.rawText)
            for candidate in candidateTerms(from: correction.correctedText) {
                let normalized = normalize(candidate)
                if rawTokens.contains(normalized) && !candidate.contains(where: { $0.isUppercase }) {
                    continue
                }
                appendTerm(candidate)
                if terms.count >= maxTerms { return terms }
            }
        }

        return Array(terms.prefix(maxTerms))
    }

    private static func candidateTerms(from text: String) -> [String] {
        let words = text
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
            .map(String.init)

        var candidates: [String] = []

        for word in words {
            if word.contains(where: { $0.isUppercase }) || word.contains(where: { $0.isNumber }) {
                candidates.append(word)
            }
            if ["deploy", "feature", "meeting", "feedback", "sprint", "bug"].contains(word.lowercased()) {
                candidates.append(word)
            }
        }

        for index in words.indices.dropLast() {
            let pair = "\(words[index]) \(words[index + 1])"
            if pair.contains(where: { $0.isUppercase }) {
                candidates.append(pair)
            }
        }

        return candidates
    }

    private static func normalizedTokenSet(_ text: String) -> Set<String> {
        Set(candidateTerms(from: text).map(normalize))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
