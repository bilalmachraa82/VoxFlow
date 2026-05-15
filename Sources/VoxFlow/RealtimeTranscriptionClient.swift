import Foundation

final class RealtimeTranscriptionClient {
    typealias TextCallback = @Sendable (String) -> Void

    private let apiKey: String
    private let language: String
    private let prompt: String
    private let onDelta: TextCallback
    private let onCompleted: TextCallback
    private let onError: TextCallback
    private let session: URLSession
    private var webSocket: URLSessionWebSocketTask?

    init(
        apiKey: String,
        language: String,
        prompt: String,
        session: URLSession = .shared,
        onDelta: @escaping TextCallback,
        onCompleted: @escaping TextCallback,
        onError: @escaping TextCallback
    ) {
        self.apiKey = apiKey
        self.language = language
        self.prompt = prompt
        self.session = session
        self.onDelta = onDelta
        self.onCompleted = onCompleted
        self.onError = onError
    }

    func connect() {
        do {
            let request = try Self.makeWebSocketRequest(apiKey: apiKey)
            let task = session.webSocketTask(with: request)
            webSocket = task
            task.resume()
            receiveLoop()
            send(data: try Self.sessionUpdatePayload(language: language, prompt: prompt))
        } catch {
            onError(error.localizedDescription)
        }
    }

    func sendPCM24kAudio(_ data: Data) {
        guard !data.isEmpty else { return }
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        send(json: payload)
    }

    func commit() {
        send(json: ["type": "input_audio_buffer.commit"])
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }

    static func makeWebSocketRequest(apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func sessionUpdatePayload(language: String, prompt: String) throws -> Data {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "language": language,
                            "prompt": prompt
                        ],
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        send(data: data)
    }

    private func send(data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(string)) { [weak self] error in
            if let error {
                self?.onError(error.localizedDescription)
            }
        }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                handle(message)
                receiveLoop()
            case .failure(let error):
                onError(error.localizedDescription)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            data = nil
        }

        guard let data,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else {
            return
        }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            if let delta = event["delta"] as? String {
                onDelta(delta)
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String {
                onCompleted(transcript)
            }
        case "error":
            let error = event["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Erro realtime desconhecido"
            onError(message)
        default:
            break
        }
    }
}
