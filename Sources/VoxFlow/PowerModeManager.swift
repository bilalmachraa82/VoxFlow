import SwiftUI
import AppKit

// MARK: - PowerMode

/// A context-aware transcription profile that tailors the polish prompt
/// based on which application is active.
struct PowerMode: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifiers: [String]
    var promptTemplate: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifiers: [String],
        promptTemplate: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.promptTemplate = promptTemplate
        self.isEnabled = isEnabled
    }
}

// MARK: - PowerModeManager

/// Detects the frontmost application and resolves the best matching
/// `PowerMode` for transcription polishing.
@MainActor
final class PowerModeManager: ObservableObject {

    // MARK: Published State

    @Published private(set) var activeBundleID: String = ""
    @Published var customModes: [PowerMode] = []

    // MARK: Storage

    private static let customModesKey = "vox.powerModes.custom"

    // MARK: Built-in Modes

    static let emailMode = PowerMode(
        name: "Email",
        bundleIdentifiers: [
            "com.apple.mail",
            "com.google.Chrome"  // Gmail via Chrome — see URL-aware note below
        ],
        promptTemplate: """
            Reescreve esta transcricao como um email profissional em portugues. \
            Usa tom formal, adiciona saudacao ("Boa tarde,") e fecho ("Com os \
            melhores cumprimentos,"). Corrige pontuacao e capitalização. \
            Preserva termos tecnicos e nomes proprios. So o texto:\n\n{{TEXT}}
            """
    )

    static let mensagemMode = PowerMode(
        name: "Mensagem",
        bundleIdentifiers: [
            "com.tinyspeck.slackmacgap",
            "com.facebook.archon",
            "net.whatsapp.WhatsApp"
        ],
        promptTemplate: """
            Reescreve esta transcricao como uma mensagem curta e casual. \
            Mantem informal, sem saudacao nem fecho. Corrige pontuacao basica. \
            Preserva emojis e giria. So o texto:\n\n{{TEXT}}
            """
    )

    static let codigoMode = PowerMode(
        name: "Codigo",
        bundleIdentifiers: [
            "com.microsoft.VSCode",
            "dev.nicedoc.Trae",
            "com.windsurf"
        ],
        promptTemplate: """
            Limpa esta transcricao mantendo todos os termos tecnicos, nomes de \
            funcoes, variaveis e comandos exactamente como ditados. Converte \
            indicacoes como "abre parentesis" em simbolos. Usa formatacao tecnica. \
            So o texto:\n\n{{TEXT}}
            """
    )

    static let geralMode = PowerMode(
        name: "Geral",
        bundleIdentifiers: [],
        promptTemplate: """
            Corrige esta transcricao. Pontuacao, maiusculas, remove hesitacoes \
            (hum, tipo, pronto). Preserva ingles e termos tecnicos. \
            So o texto:\n\n{{TEXT}}
            """
    )

    /// All built-in modes in priority order.
    static let builtInModes: [PowerMode] = [
        emailMode,
        mensagemMode,
        codigoMode,
        geralMode
    ]

    // MARK: Init

    init() {
        customModes = Self.loadCustomModes()
    }

    // MARK: - Active App Detection

    /// Refresh the cached frontmost bundle identifier.
    func refreshActiveApp() {
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    // MARK: - Prompt Resolution

    /// Returns the prompt template for the currently active application,
    /// with `{{TEXT}}` ready to be replaced by the transcription text.
    ///
    /// Resolution order:
    /// 1. Enabled custom modes (checked first so users can override built-ins)
    /// 2. Built-in modes (email, mensagem, codigo)
    /// 3. Geral (fallback)
    func promptForCurrentApp() -> String {
        refreshActiveApp()
        let bundle = activeBundleID

        // 1. Custom modes take precedence
        if let match = customModes.first(where: {
            $0.isEnabled && $0.bundleIdentifiers.contains(bundle)
        }) {
            return match.promptTemplate
        }

        // 2. Built-in modes (skip Geral — it's the fallback)
        let specificBuiltIns = Self.builtInModes.filter { !$0.bundleIdentifiers.isEmpty }
        if let match = specificBuiltIns.first(where: {
            $0.isEnabled && $0.bundleIdentifiers.contains(bundle)
        }) {
            return match.promptTemplate
        }

        // 3. Default
        return Self.geralMode.promptTemplate
    }

    /// Convenience: returns the resolved prompt with `{{TEXT}}` replaced.
    func resolvedPrompt(for text: String) -> String {
        promptForCurrentApp().replacingOccurrences(of: "{{TEXT}}", with: text)
    }

    /// Returns the name of the mode that would apply for the current app.
    func currentModeName() -> String {
        refreshActiveApp()
        let bundle = activeBundleID

        if let match = customModes.first(where: {
            $0.isEnabled && $0.bundleIdentifiers.contains(bundle)
        }) {
            return match.name
        }

        let specificBuiltIns = Self.builtInModes.filter { !$0.bundleIdentifiers.isEmpty }
        if let match = specificBuiltIns.first(where: {
            $0.isEnabled && $0.bundleIdentifiers.contains(bundle)
        }) {
            return match.name
        }

        return Self.geralMode.name
    }

    // MARK: - Custom Mode CRUD

    func addCustomMode(_ mode: PowerMode) {
        customModes.append(mode)
        saveCustomModes()
    }

    func updateCustomMode(_ updated: PowerMode) {
        guard let index = customModes.firstIndex(where: { $0.id == updated.id }) else { return }
        customModes[index] = updated
        saveCustomModes()
    }

    func deleteCustomMode(id: UUID) {
        customModes.removeAll { $0.id == id }
        saveCustomModes()
    }

    // MARK: - Persistence (UserDefaults as JSON)

    private func saveCustomModes() {
        guard let data = try? JSONEncoder().encode(customModes) else { return }
        UserDefaults.standard.set(data, forKey: Self.customModesKey)
    }

    private static func loadCustomModes() -> [PowerMode] {
        guard let data = UserDefaults.standard.data(forKey: customModesKey),
              let modes = try? JSONDecoder().decode([PowerMode].self, from: data)
        else { return [] }
        return modes
    }
}
