import Foundation

enum OpenAIPolishClient {
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
                return "A OpenAI nao devolveu texto corrigido"
            }
        }
    }

    static func polish(apiKey: String, model: String, prompt: String) async throws -> String {
        let request = try makeRequest(apiKey: apiKey, model: model, prompt: prompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = apiErrorMessage(from: data) ?? "OpenAI polish falhou (\(http.statusCode))"
            throw ClientError.apiError(message)
        }

        return try extractText(from: data)
    }

    static func makeRequest(apiKey: String, model: String, prompt: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw ClientError.missingURL
        }

        let body: [String: Any] = [
            "model": model,
            "input": prompt,
            "max_output_tokens": maxOutputTokens(for: prompt),
            "store": false,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": ["type": "text"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func maxOutputTokens(for prompt: String) -> Int {
        let estimatedInputTokens = max(1, prompt.count / 4)
        return min(max(500, estimatedInputTokens + 200), 4_000)
    }

    static func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }

        if let outputText = json["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let output = json["output"] as? [[String: Any]] else {
            throw ClientError.missingText
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }

        throw ClientError.missingText
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
