import XCTest
@testable import VoxFlow

final class OpenAIPolishClientTests: XCTestCase {
    func testResponsesRequestUsesGpt55AndPlainTextFormat() throws {
        let request = try OpenAIPolishClient.makeRequest(
            apiKey: "test-key",
            model: "gpt-5.5",
            prompt: "Corrige este texto."
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertTrue(body.contains("\"model\":\"gpt-5.5\""))
        XCTAssertTrue(body.contains("\"input\":\"Corrige este texto.\""))
        XCTAssertTrue(body.contains("\"verbosity\":\"low\""))
    }

    func testExtractsOutputTextFromResponsesPayload() throws {
        let json = """
        {
          "output": [
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": "Texto corrigido." }
              ]
            }
          ]
        }
        """

        let text = try OpenAIPolishClient.extractText(from: Data(json.utf8))

        XCTAssertEqual(text, "Texto corrigido.")
    }

    func testRaisesOutputTokenLimitForLongPrompts() {
        let shortLimit = OpenAIPolishClient.maxOutputTokens(for: "Texto curto.")
        let longLimit = OpenAIPolishClient.maxOutputTokens(for: String(repeating: "palavra ", count: 3_000))

        XCTAssertEqual(shortLimit, 500)
        XCTAssertGreaterThan(longLimit, shortLimit)
        XCTAssertLessThanOrEqual(longLimit, 4_000)
    }
}
