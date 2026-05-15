import XCTest
@testable import VoxFlow

final class OpenAITranscriptionClientTests: XCTestCase {
    func testMultipartRequestContainsModelLanguagePromptAndAudio() throws {
        let audioURL = URL(fileURLWithPath: "/tmp/voxflow-test.wav")
        try Data("RIFF fake wav".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let request = try OpenAITranscriptionClient.makeRequest(
            apiKey: "test-key",
            audioURL: audioURL,
            model: "gpt-4o-transcribe",
            language: "pt",
            prompt: "Keywords: SustentaReport, feature"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(body).contains("gpt-4o-transcribe"))
        XCTAssertTrue(try XCTUnwrap(body).contains("name=\"language\""))
        XCTAssertTrue(try XCTUnwrap(body).contains("pt"))
        XCTAssertTrue(try XCTUnwrap(body).contains("SustentaReport"))
        XCTAssertTrue(try XCTUnwrap(body).contains("filename=\"voxflow-test.wav\""))
    }
}
