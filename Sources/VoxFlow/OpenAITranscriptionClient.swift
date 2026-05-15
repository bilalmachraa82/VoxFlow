import Foundation

enum OpenAITranscriptionClient {
    enum ClientError: LocalizedError {
        case missingURL
        case invalidResponse
        case apiError(String)
        case missingText

        var errorDescription: String? {
            switch self {
            case .missingURL:
                return "URL OpenAI invalido"
            case .invalidResponse:
                return "Resposta OpenAI invalida"
            case .apiError(let message):
                return message
            case .missingText:
                return "A OpenAI nao devolveu texto"
            }
        }
    }

    static func transcribe(
        apiKey: String,
        audioURL: URL,
        model: String,
        language: String,
        prompt: String
    ) async throws -> String {
        let request = try makeRequest(
            apiKey: apiKey,
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = apiErrorMessage(from: data) ?? "OpenAI STT falhou (\(http.statusCode))"
            throw ClientError.apiError(message)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else {
            throw ClientError.missingText
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.missingText }
        return trimmed
    }

    static func makeRequest(
        apiKey: String,
        audioURL: URL,
        model: String,
        language: String,
        prompt: String
    ) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw ClientError.missingURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try multipartBody(
            boundary: boundary,
            audioURL: audioURL,
            fields: [
                "model": model,
                "response_format": "json",
                "language": language,
                "prompt": prompt
            ]
        )
        return request
    }

    private static func multipartBody(
        boundary: String,
        audioURL: URL,
        fields: [String: String]
    ) throws -> Data {
        var body = Data()

        for (name, value) in fields {
            append("--\(boundary)\r\n", to: &body)
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
            append("\(value)\r\n", to: &body)
        }

        let audioData = try Data(contentsOf: audioURL)
        append("--\(boundary)\r\n", to: &body)
        append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n",
            to: &body
        )
        append("Content-Type: audio/wav\r\n\r\n", to: &body)
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n", to: &body)

        return body
    }

    private static func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }
}
