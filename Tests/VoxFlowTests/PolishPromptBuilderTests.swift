import XCTest
@testable import VoxFlow

final class PolishPromptBuilderTests: XCTestCase {
    func testReplacesPowerModePlaceholderInsteadOfAppendingTextTwice() {
        let prompt = PolishPromptBuilder.build(
            text: "texto original",
            customPrompt: "Corrige isto: {{TEXT}}"
        )

        XCTAssertEqual(prompt, "Corrige isto: texto original")
    }

    func testAppendsTextWhenCustomPromptHasNoPlaceholder() {
        let prompt = PolishPromptBuilder.build(
            text: "texto original",
            customPrompt: "Corrige em PT-PT."
        )

        XCTAssertEqual(prompt, "Corrige em PT-PT.\n\ntexto original")
    }
}
