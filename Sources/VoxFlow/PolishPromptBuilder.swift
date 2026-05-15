import Foundation

enum PolishPromptBuilder {
    static func build(text: String, customPrompt: String?) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let customPrompt, !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return """
            Es um assistente de correcção de texto em Português Europeu (PT-PT).

            REGRAS OBRIGATÓRIAS:
            1. Corrige pontuação e maiúsculas segundo normas PT-PT
            2. Remove palavras de preenchimento: hum, uh, tipo, pronto, então, basicamente, ok, ya
            3. Preserva TODOS os termos em inglês sem traduzir
            4. Usa ortografia PT-PT
            5. Mantém o sentido exacto; não adicionar nem inventar
            6. Devolve APENAS o texto corrigido

            Texto para corrigir:
            \(trimmedText)
            """
        }

        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.contains("{{TEXT}}") {
            return prompt.replacingOccurrences(of: "{{TEXT}}", with: trimmedText)
        }

        return "\(prompt)\n\n\(trimmedText)"
    }
}
