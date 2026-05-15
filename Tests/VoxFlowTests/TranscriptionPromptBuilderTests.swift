import XCTest
@testable import VoxFlow

final class TranscriptionPromptBuilderTests: XCTestCase {
    func testBuildsPortuguesePromptWithCustomVocabularyAndLearnedCorrections() {
        let corrections = [
            LearnedCorrection(rawText: "vou abrir o sustenta report", correctedText: "Vou abrir o SustentaReport."),
            LearnedCorrection(rawText: "fiz deploy da feitura", correctedText: "Fiz deploy da feature.")
        ]

        let prompt = TranscriptionPromptBuilder.build(
            language: "auto",
            customVocabulary: "Bilal, IFIC, Daniela Alves",
            corrections: corrections
        )

        XCTAssertTrue(prompt.contains("Português Europeu"))
        XCTAssertTrue(prompt.contains("Bilal"))
        XCTAssertTrue(prompt.contains("SustentaReport"))
        XCTAssertTrue(prompt.contains("feature"))
        XCTAssertFalse(prompt.contains("Brasileiro"))
    }

    func testEffectiveLanguageDefaultsAutoToPortugueseForPtptDictation() {
        XCTAssertEqual(TranscriptionPromptBuilder.effectiveLanguage(for: "auto"), "pt")
        XCTAssertEqual(TranscriptionPromptBuilder.effectiveLanguage(for: "en"), "en")
    }
}
