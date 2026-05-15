import XCTest
@testable import VoxFlow

final class RealtimeTranscriptionClientTests: XCTestCase {
    func testWebSocketRequestUsesRealtimeTranscriptionIntentAndBearerAuth() throws {
        let request = try RealtimeTranscriptionClient.makeWebSocketRequest(apiKey: "test-key")

        XCTAssertEqual(request.url?.absoluteString, "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testSessionUpdateUsesRealtimeWhisperWithManualCommitAndPtLanguage() throws {
        let data = try RealtimeTranscriptionClient.sessionUpdatePayload(
            language: "pt",
            prompt: "Keywords: SustentaReport, feature"
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let session = try XCTUnwrap(json?["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])

        XCTAssertEqual(json?["type"] as? String, "session.update")
        XCTAssertEqual(session["type"] as? String, "transcription")
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        XCTAssertEqual(transcription["language"] as? String, "pt")
        XCTAssertEqual(transcription["prompt"] as? String, "Keywords: SustentaReport, feature")
        XCTAssertEqual(format["rate"] as? Int, 24000)
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }
}
