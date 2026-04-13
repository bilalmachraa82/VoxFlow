import SwiftUI
import AppKit
import HotKey
import UserNotifications

/// Core engine — whisper-cli backend, PowerMode, History, Notifications.
@MainActor
final class VoxEngine: ObservableObject {

    enum State: String {
        case idle, recording, transcribing, polishing, done, error
    }

    // MARK: - Published State
    @Published var state: State = .idle
    @Published var lastResult = ""
    @Published var lastRaw = ""
    @Published var errorMsg = ""
    @Published var recordingSeconds = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 20)

    // MARK: - Sub-managers
    let historyStore = HistoryStore()
    let powerMode = PowerModeManager()
    let launchManager = LaunchManager()

    // MARK: - Settings
    @AppStorage("vox.lang") var lang = "auto"
    @AppStorage("vox.model") var model = "small"
    @AppStorage("vox.mic") var micDevice = "auto"
    @AppStorage("vox.autoPaste") var autoPaste = true
    @AppStorage("vox.sounds") var sounds = true
    @AppStorage("vox.polishProvider") var polishProvider = "none"
    @AppStorage("vox.polishKey") var polishKey = ""
    @AppStorage("vox.polishModel") var polishModel = "meta-llama/llama-3.1-8b-instruct:free"
    @AppStorage("vox.holdToTalk") var holdToTalk = false
    @AppStorage("vox.customVocab") var customVocab = ""
    @AppStorage("onboardingComplete") var onboardingComplete = false

    // MARK: - Internal
    private var hotKey: HotKey?
    private var ffmpegProcess: Process?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private let tempWav = "/tmp/voxflow-rec.wav"
    private let whisperCli = "/opt/homebrew/Cellar/whisper-cpp/1.8.3/bin/whisper-cli"
    private let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("VoxFlow/Models")

    init() {
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        setupHotkey()
        requestNotificationPermission()
    }

    // MARK: - Hotkey
    func setupHotkey() {
        hotKey = HotKey(key: .space, modifiers: [.option])

        if holdToTalk {
            hotKey?.keyDownHandler = { [weak self] in
                Task { @MainActor in self?.startRecording() }
            }
            hotKey?.keyUpHandler = { [weak self] in
                Task { @MainActor in self?.stopRecording() }
            }
        } else {
            hotKey?.keyDownHandler = { [weak self] in
                Task { @MainActor in self?.toggle() }
            }
        }
    }

    // MARK: - Toggle
    func toggle() {
        switch state {
        case .idle, .done, .error: startRecording()
        case .recording: stopRecording()
        default: break
        }
    }

    // MARK: - Record
    func startRecording() {
        guard state != .recording else { return }
        state = .recording
        recordingSeconds = 0
        errorMsg = ""
        audioLevels = Array(repeating: 0, count: 20)
        if sounds { NSSound(named: "Tink")?.play() }

        let mic = detectMic()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "avfoundation", "-i", ":\(mic)", "-t", "120",
                          "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le", "-y", tempWav]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            ffmpegProcess = proc
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingSeconds += 1 }
            }
            // Simulate waveform levels
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.audioLevels = (0..<20).map { _ in Float.random(in: 0.05...0.85) }
                }
            }
        } catch {
            state = .error
            errorMsg = "Erro ao gravar: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        if sounds { NSSound(named: "Pop")?.play() }
        recordingTimer?.invalidate(); recordingTimer = nil
        levelTimer?.invalidate(); levelTimer = nil
        audioLevels = Array(repeating: 0, count: 20)
        ffmpegProcess?.terminate(); ffmpegProcess = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.transcribe() }
    }

    // MARK: - Transcribe
    private func transcribe() {
        state = .transcribing
        let startTime = Date()

        let currentModel = model, currentLang = lang
        let currentPolishProvider = polishProvider, currentPolishKey = polishKey
        let currentCustomVocab = customVocab
        let modelDir = self.modelDir, whisperCli = self.whisperCli, tempWav = self.tempWav

        // Get active app for PowerMode
        let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let _ = powerMode.refreshActiveApp()
        let polishPrompt = powerMode.promptForCurrentApp()

        Task.detached {
            let modelPath = modelDir.appendingPathComponent("ggml-\(currentModel).bin").path
            guard FileManager.default.fileExists(atPath: modelPath) else {
                await MainActor.run { self.state = .error; self.errorMsg = "Modelo nao encontrado" }
                return
            }
            guard FileManager.default.fileExists(atPath: tempWav) else {
                await MainActor.run { self.state = .error; self.errorMsg = "Audio nao encontrado" }
                return
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: whisperCli)

            // Language strategy:
            // - "auto" is bad for mixed PT+EN (picks one and ignores the other)
            // - "pt" forces Portuguese but Whisper still transcribes English words correctly
            //   when the initial prompt tells it to expect code-switching
            // - This is the best approach for bilingual PT-PT + EN users
            let effectiveLang = (currentLang == "auto") ? "pt" : currentLang

            var args = ["-m", modelPath, "-f", tempWav, "-l", effectiveLang, "-t", "6", "--no-timestamps", "--no-prints"]

            // Initial prompt: critical for mixed-language accuracy
            var promptParts: [String] = []
            if effectiveLang == "pt" {
                promptParts = [
                    "Transcrição em Português Europeu com termos em Inglês.",
                    "O utilizador alterna entre Português e Inglês naturalmente.",
                    "Preserva palavras em Inglês: deploy, meeting, feedback, sprint, feature, bug.",
                    "Pontuação correcta com acentos: ã, õ, ç, é, ê, á, ó, ú."
                ]
            } else if effectiveLang == "en" {
                promptParts = [
                    "Transcription in English with proper punctuation and capitalization."
                ]
            }
            if !currentCustomVocab.isEmpty {
                promptParts.append("Vocabulário: \(currentCustomVocab)")
            }
            if !promptParts.isEmpty {
                args += ["--prompt", promptParts.joined(separator: " ")]
            }
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                var text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                text = text.components(separatedBy: "\n").filter { !$0.hasPrefix("[") }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    await MainActor.run { self.state = .error; self.errorMsg = "Nenhuma fala detectada"; if self.sounds { NSSound(named: "Basso")?.play() } }
                    return
                }

                await MainActor.run { self.lastRaw = text }

                // Polish with PowerMode-aware prompt
                var finalText = text
                if currentPolishProvider != "none" && !currentPolishKey.isEmpty {
                    await MainActor.run { self.state = .polishing }
                    if let polished = await self.polish(text: text, customPrompt: polishPrompt) {
                        finalText = polished
                    }
                }

                let duration = Int(Date().timeIntervalSince(startTime))

                await MainActor.run {
                    self.lastResult = finalText
                    self.pasteResult()
                    self.state = .done
                    if self.sounds { NSSound(named: "Glass")?.play() }

                    // Save to history
                    let entry = HistoryEntry(
                        text: finalText, rawText: text,
                        language: currentLang, mode: self.powerMode.currentModeName(),
                        appName: activeAppName, durationSeconds: duration
                    )
                    self.historyStore.add(entry)

                    // Notification
                    self.sendNotification(text: finalText)
                }

                try? FileManager.default.removeItem(atPath: tempWav)
            } catch {
                await MainActor.run { self.state = .error; self.errorMsg = "Erro: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - Paste
    private func pasteResult() {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(lastResult, forType: .string)

        if autoPaste {
            let src = CGEventSource(stateID: .combinedSessionState)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                down.flags = .maskCommand; up.flags = .maskCommand
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let saved = saved { pb.clearContents(); pb.setString(saved, forType: .string) }
            }
        }
    }

    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(text: String) {
        // Only if app is not frontmost
        guard NSApp.isActive == false else { return }
        let content = UNMutableNotificationContent()
        content.title = "VoxFlow"
        content.subtitle = "Transcricao concluida"
        content.body = String(text.prefix(120))
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Mic Detection
    func detectMic() -> String {
        if micDevice != "auto" { return micDevice }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
        let pipe = Pipe()
        proc.standardError = pipe; proc.standardOutput = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var inAudio = false; var builtIn: String?; var firstReal: String?
        let virtual = ["ZoomAudio", "Microsoft Teams", "Loopback", "BlackHole"]
        for line in output.components(separatedBy: "\n") {
            if line.contains("audio devices") { inAudio = true; continue }
            guard inAudio, let match = line.range(of: #"\[(\d+)\]"#, options: .regularExpression) else { continue }
            let idx = String(line[match]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            if virtual.contains(where: { line.contains($0) }) { continue }
            if firstReal == nil { firstReal = idx }
            if line.contains("Microfone") || line.contains("MacBook") || line.contains("Built-in") { builtIn = idx }
            if line.lowercased().contains("yeti") || line.lowercased().contains("blue") || line.contains("USB") { return idx }
        }
        return builtIn ?? firstReal ?? "0"
    }

    func listMics() -> [(id: String, name: String, active: Bool)] {
        let currentMic = detectMic()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
        let pipe = Pipe()
        proc.standardError = pipe; proc.standardOutput = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var results: [(id: String, name: String, active: Bool)] = []
        var inAudio = false
        let virtual = ["ZoomAudio", "Microsoft Teams", "Loopback", "BlackHole"]
        for line in output.components(separatedBy: "\n") {
            if line.contains("audio devices") { inAudio = true; continue }
            guard inAudio, let match = line.range(of: #"\[(\d+)\]"#, options: .regularExpression) else { continue }
            let idx = String(line[match]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            if virtual.contains(where: { line.contains($0) }) { continue }
            let name = line.components(separatedBy: "] ").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
            results.append((id: idx, name: name, active: idx == currentMic))
        }
        return results
    }

    // MARK: - Polish (PT-PT optimized prompt + selectable model)
    private func polish(text: String, customPrompt: String? = nil) async -> String? {
        // PT-PT specific prompt — critical for quality
        let basePrompt = customPrompt ?? """
        Es um assistente de correcção de texto em Português Europeu (PT-PT, não brasileiro).

        REGRAS OBRIGATÓRIAS:
        1. Corrige pontuação e maiúsculas segundo normas PT-PT
        2. Remove palavras de preenchimento: hum, uh, tipo, pronto, então, basicamente, ok, ya
        3. Preserva TODOS os termos em inglês sem traduzir (ex: "deploy", "meeting", "feedback")
        4. Usa ortografia PT-PT (facto, não fato; equipa, não time; telemóvel, não celular)
        5. Mantém o sentido exacto — NÃO adicionar, inventar, ou reformular frases
        6. Devolve APENAS o texto corrigido, sem explicações nem comentários

        Texto para corrigir:
        """

        let fullPrompt = "\(basePrompt)\n\(text)"
        let (url, body) = polishRequest(prompt: fullPrompt)
        guard let url = url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if polishProvider != "google" { request.setValue("Bearer \(polishKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15 // don't wait forever

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if polishProvider == "google" {
            if let c = json["candidates"] as? [[String: Any]], let p = c.first?["content"] as? [String: Any],
               let parts = p["parts"] as? [[String: Any]], let t = parts.first?["text"] as? String { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            if let c = json["choices"] as? [[String: Any]], let m = c.first?["message"] as? [String: Any],
               let t = m["content"] as? String { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    private func polishRequest(prompt: String) -> (URL?, [String: Any]) {
        switch polishProvider {
        case "openrouter": return (URL(string: "https://openrouter.ai/api/v1/chat/completions"), ["model": polishModel, "messages": [["role": "user", "content": prompt]], "max_tokens": 500, "temperature": 0.1])
        case "groq": return (URL(string: "https://api.groq.com/openai/v1/chat/completions"), ["model": "llama-3.1-8b-instant", "messages": [["role": "user", "content": prompt]], "max_tokens": 500, "temperature": 0.1])
        case "google": return (URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(polishKey)"), ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["temperature": 0.1, "maxOutputTokens": 500]])
        default: return (nil, [:])
        }
    }
}
