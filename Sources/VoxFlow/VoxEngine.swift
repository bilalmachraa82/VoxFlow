import SwiftUI
import AppKit
import AVFoundation
import HotKey
import UserNotifications

/// Core engine: native capture, OpenAI/local transcription, PowerMode, History, Notifications.
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
    @Published var livePreview = ""
    @Published var fallbackNotice = ""
    @Published var lastProviderUsed = ""
    @Published var lastEstimatedCost = 0.0
    @Published var recordingSeconds = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 20)

    // MARK: - Sub-managers
    let historyStore = HistoryStore()
    let correctionStore = CorrectionMemoryStore()
    let powerMode = PowerModeManager()
    let launchManager = LaunchManager()

    // MARK: - Settings
    @AppStorage("vox.lang") var lang = "auto"
    @AppStorage("vox.model") var model = "large-v3-turbo"
    @AppStorage("vox.transcriptionProvider") var transcriptionProvider = "local"
    @AppStorage("vox.openAITranscriptionModel") var openAITranscriptionModel = "gpt-4o-transcribe"
    @AppStorage("vox.mic") var micDevice = "auto"
    @AppStorage("vox.autoPaste") var autoPaste = true
    @AppStorage("vox.sounds") var sounds = true
    @AppStorage("vox.polishProvider") var polishProvider = "none"
    @AppStorage("vox.polishModel") var polishModel = "meta-llama/llama-3.1-8b-instruct:free"
    @AppStorage("vox.openAIPolishModel") var openAIPolishModel = "gpt-5.5"
    @AppStorage("vox.realtimePreview") var realtimePreview = true
    @AppStorage("vox.holdToTalk") var holdToTalk = false
    @AppStorage("vox.customVocab") var customVocab = ""
    @AppStorage("onboardingComplete") var onboardingComplete = false

    @Published var openAITranscriptionKey: String {
        didSet { secretStore.set(openAITranscriptionKey, for: .openAITranscriptionKey) }
    }
    @Published var polishKey: String {
        didSet { secretStore.set(polishKey, for: .polishKey) }
    }

    // MARK: - Internal
    private var hotKey: HotKey?
    private let audioRecorder = NativeAudioRecorder()
    private var realtimeSession: RealtimeTranscriptionClient?
    private var recordingTimer: Timer?
    private var tempAudioURL: URL?
    private let whisperCli = "/opt/homebrew/bin/whisper-cli"
    private let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("VoxFlow/Models")
    private let secretStore: SecretStoring

    init(secretStore: SecretStoring = KeychainSecretStore()) {
        self.secretStore = secretStore
        SecretMigration.migrateLegacyUserDefaults(store: secretStore)
        self.openAITranscriptionKey = secretStore.string(for: .openAITranscriptionKey)
        self.polishKey = secretStore.string(for: .polishKey)
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
        livePreview = ""
        fallbackNotice = ""
        lastProviderUsed = ""
        lastEstimatedCost = 0
        audioLevels = Array(repeating: 0, count: 20)
        if sounds { NSSound(named: "Tink")?.play() }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-\(UUID().uuidString).wav")
        tempAudioURL = outputURL
        configureRealtimePreviewIfNeeded()

        audioRecorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.pushAudioLevel(level) }
        }
        audioRecorder.onRealtimePCM24kChunk = { [weak self] data in
            Task { @MainActor in self?.realtimeSession?.sendPCM24kAudio(data) }
        }

        do {
            try audioRecorder.start(
                outputURL: outputURL,
                inputDeviceUID: micDevice == "auto" ? nil : micDevice
            )
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingSeconds += 1 }
            }
        } catch {
            audioRecorder.stop()
            realtimeSession?.disconnect()
            realtimeSession = nil
            state = .error
            errorMsg = "Erro ao gravar: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        if sounds { NSSound(named: "Pop")?.play() }
        recordingTimer?.invalidate(); recordingTimer = nil
        audioLevels = Array(repeating: 0, count: 20)
        audioRecorder.stop()
        realtimeSession?.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.transcribe() }
    }

    private func pushAudioLevel(_ level: Float) {
        audioLevels.removeFirst()
        audioLevels.append(max(0.04, level))
    }

    private func configureRealtimePreviewIfNeeded() {
        guard transcriptionProvider == "openai",
              realtimePreview,
              !openAITranscriptionKey.isEmpty
        else {
            realtimeSession = nil
            return
        }

        let effectiveLang = TranscriptionPromptBuilder.effectiveLanguage(for: lang)
        let prompt = TranscriptionPromptBuilder.build(
            language: lang,
            customVocabulary: customVocab,
            corrections: correctionStore.recentCorrections
        )

        let session = RealtimeTranscriptionClient(
            apiKey: openAITranscriptionKey,
            language: effectiveLang,
            prompt: prompt,
            onDelta: { [weak self] delta in
                Task { @MainActor in self?.livePreview += delta }
            },
            onCompleted: { [weak self] transcript in
                Task { @MainActor in self?.livePreview = transcript }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    if self?.fallbackNotice.isEmpty == true {
                        self?.fallbackNotice = "Preview realtime indisponivel: \(message)"
                    }
                }
            }
        )
        realtimeSession = session
        session.connect()
    }

    // MARK: - Transcribe
    private func transcribe() {
        state = .transcribing
        let startTime = Date()
        realtimeSession?.disconnect()
        realtimeSession = nil

        let currentModel = model, currentLang = lang
        let currentTranscriptionProvider = transcriptionProvider
        let currentOpenAIKey = openAITranscriptionKey
        let currentOpenAIModel = openAITranscriptionModel
        let currentRealtimePreview = realtimePreview
        let currentPolishProvider = polishProvider, currentPolishKey = polishKey
        let currentOpenAIPolishModel = openAIPolishModel
        let currentCustomVocab = customVocab
        let currentCorrections = correctionStore.recentCorrections
        let modelDir = self.modelDir, whisperCli = self.whisperCli
        guard let tempAudioURL else {
            state = .error
            errorMsg = "Audio nao encontrado"
            return
        }
        let effectiveLang = TranscriptionPromptBuilder.effectiveLanguage(for: currentLang)
        let transcriptionPrompt = TranscriptionPromptBuilder.build(
            language: currentLang,
            customVocabulary: currentCustomVocab,
            corrections: currentCorrections
        )

        // Get active app for PowerMode
        let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let _ = powerMode.refreshActiveApp()
        let polishPrompt = powerMode.promptForCurrentApp()

        Task.detached {
            guard FileManager.default.fileExists(atPath: tempAudioURL.path) else {
                await MainActor.run { self.state = .error; self.errorMsg = "Audio nao encontrado" }
                return
            }

            do {
                let outcome = try await Self.transcribeAudio(
                    audioURL: tempAudioURL,
                    provider: currentTranscriptionProvider,
                    openAIKey: currentOpenAIKey,
                    openAIModel: currentOpenAIModel,
                    effectiveLang: effectiveLang,
                    prompt: transcriptionPrompt,
                    localModelName: currentModel,
                    modelDir: modelDir,
                    whisperCli: whisperCli
                )
                let text = outcome.text

                guard !text.isEmpty else {
                    await MainActor.run { self.state = .error; self.errorMsg = "Nenhuma fala detectada"; if self.sounds { NSSound(named: "Basso")?.play() } }
                    return
                }

                await MainActor.run { self.lastRaw = text }

                // Polish with PowerMode-aware prompt
                var finalText = text
                let hasPolishKey = !currentPolishKey.isEmpty || (currentPolishProvider == "openai" && !currentOpenAIKey.isEmpty)
                if currentPolishProvider != "none" && hasPolishKey {
                    await MainActor.run { self.state = .polishing }
                    if let polished = await self.polish(text: text, customPrompt: polishPrompt) {
                        finalText = polished
                    }
                }

                let duration = Int(Date().timeIntervalSince(startTime))
                let resolvedText = finalText
                let estimatedCost = Self.estimatedCost(
                    duration: duration,
                    transcriptionProvider: currentTranscriptionProvider,
                    transcriptionModel: currentOpenAIModel,
                    polishProvider: currentPolishProvider,
                    polishModel: currentOpenAIPolishModel,
                    realtimePreview: currentRealtimePreview
                )

                await MainActor.run {
                    self.lastResult = resolvedText
                    self.lastProviderUsed = outcome.providerUsed
                    self.fallbackNotice = outcome.fallbackReason ?? self.fallbackNotice
                    self.lastEstimatedCost = estimatedCost
                    self.pasteResult()
                    self.state = .done
                    if self.sounds { NSSound(named: "Glass")?.play() }

                    // Save to history
                    let entry = HistoryEntry(
                        text: resolvedText, rawText: text,
                        language: currentLang, mode: self.powerMode.currentModeName(),
                        appName: activeAppName, durationSeconds: duration
                    )
                    self.historyStore.add(entry)

                    // Notification
                    self.sendNotification(text: resolvedText)
                }

                try? FileManager.default.removeItem(at: tempAudioURL)
            } catch {
                await MainActor.run { self.state = .error; self.errorMsg = "Erro: \(error.localizedDescription)" }
            }
        }
    }

    private struct TranscriptionOutcome {
        let text: String
        let providerUsed: String
        let fallbackReason: String?
    }

    private nonisolated static func transcribeAudio(
        audioURL: URL,
        provider: String,
        openAIKey: String,
        openAIModel: String,
        effectiveLang: String,
        prompt: String,
        localModelName: String,
        modelDir: URL,
        whisperCli: String
    ) async throws -> TranscriptionOutcome {
        var fallbackReason: String?
        if provider == "openai", !openAIKey.isEmpty {
            do {
                let text = try await OpenAITranscriptionClient.transcribe(
                    apiKey: openAIKey,
                    audioURL: audioURL,
                    model: openAIModel,
                    language: effectiveLang,
                    prompt: prompt
                )
                return TranscriptionOutcome(text: text, providerUsed: "OpenAI \(openAIModel)", fallbackReason: nil)
            } catch {
                fallbackReason = "OpenAI falhou; usei fallback local. \(error.localizedDescription)"
                print("[VoxFlow] OpenAI STT falhou, fallback local: \(error.localizedDescription)")
            }
        } else if provider == "openai" {
            fallbackReason = "OpenAI sem API key; usei fallback local."
        }

        let text = try transcribeWithWhisperCli(
            tempWav: audioURL.path,
            modelName: localModelName,
            modelDir: modelDir,
            whisperCli: whisperCli,
            effectiveLang: effectiveLang,
            prompt: prompt
        )
        return TranscriptionOutcome(text: text, providerUsed: "Local \(localModelName)", fallbackReason: fallbackReason)
    }

    private nonisolated static func transcribeWithWhisperCli(
        tempWav: String,
        modelName: String,
        modelDir: URL,
        whisperCli: String,
        effectiveLang: String,
        prompt: String
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: whisperCli) else {
            throw NSError(
                domain: "VoxFlow",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "whisper-cli nao encontrado em \(whisperCli)"]
            )
        }
        let modelPath = modelDir.appendingPathComponent("ggml-\(modelName).bin").path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw NSError(
                domain: "VoxFlow",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Modelo local nao encontrado: \(modelName)"]
            )
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: whisperCli)
        proc.arguments = [
            "-m", modelPath,
            "-f", tempWav,
            "-l", effectiveLang,
            "-t", "6",
            "--no-timestamps",
            "--no-prints",
            "--prompt", prompt
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        try proc.run()
        proc.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard proc.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "VoxFlow",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message ?? "whisper-cli falhou"]
            )
        }

        return (String(data: output, encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("[") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func estimatedCost(
        duration: Int,
        transcriptionProvider: String,
        transcriptionModel: String,
        polishProvider: String,
        polishModel: String,
        realtimePreview: Bool
    ) -> Double {
        guard transcriptionProvider == "openai" else { return 0 }
        return VoxCostEstimator.estimate(
            durationSeconds: duration,
            transcriptionModel: transcriptionModel,
            polishModel: polishProvider == "openai" ? polishModel : nil,
            includesRealtimePreview: realtimePreview
        )
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

    func learnCorrection(correctedText: String) {
        let corrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { return }

        correctionStore.learn(rawText: lastRaw, correctedText: corrected)
        lastResult = corrected
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(corrected, forType: .string)
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
        return AudioDeviceManager.inputDevices().first(where: \.isDefault)?.id
            ?? AudioDeviceManager.inputDevices().first?.id
            ?? "auto"
    }

    func listMics() -> [(id: String, name: String, active: Bool)] {
        AudioDeviceManager.inputDevices().map { device in
            let active = micDevice == "auto" ? device.isDefault : device.id == micDevice
            return (id: device.id, name: device.name, active: active)
        }
    }

    func activeMicName() -> String {
        listMics().first(where: \.active)?.name ?? "Microfone"
    }

    // MARK: - Polish (PT-PT optimized prompt + selectable model)
    private func polish(text: String, customPrompt: String? = nil) async -> String? {
        let fullPrompt = PolishPromptBuilder.build(text: text, customPrompt: customPrompt)

        if polishProvider == "openai" {
            let key = polishKey.isEmpty ? openAITranscriptionKey : polishKey
            guard !key.isEmpty else { return nil }
            return try? await OpenAIPolishClient.polish(
                apiKey: key,
                model: openAIPolishModel,
                prompt: fullPrompt
            )
        }

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
