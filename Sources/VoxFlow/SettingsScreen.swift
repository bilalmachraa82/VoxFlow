import SwiftUI
import ServiceManagement

struct SettingsScreen: View {
    @EnvironmentObject var engine: VoxEngine
    @State private var mics: [(id: String, name: String, active: Bool)] = []

    var body: some View {
        TabView {
            generalTab.tabItem { Label("Geral", systemImage: "gear") }
            micTab.tabItem { Label("Microfone", systemImage: "mic") }
            modelTab.tabItem { Label("Modelo", systemImage: "cpu") }
            powerModeTab.tabItem { Label("Modos", systemImage: "app.dashed") }
            polishTab.tabItem { Label("Polish", systemImage: "sparkles") }
            historyTab.tabItem { Label("Historico", systemImage: "clock") }
            statsTab.tabItem { Label("Stats", systemImage: "chart.bar") }
            aboutTab.tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .onAppear { mics = engine.listMics() }
    }

    // MARK: - Geral
    private var generalTab: some View {
        Form {
            Section("Lingua") {
                Picker("Lingua:", selection: $engine.lang) {
                    Text("Auto-detectar").tag("auto")
                    Text("Portugues (PT-PT)").tag("pt")
                    Text("English").tag("en")
                    Text("Espanol").tag("es")
                    Text("Francais").tag("fr")
                    Text("Deutsch").tag("de")
                }
            }
            Section("Comportamento") {
                Toggle("Colar automaticamente no cursor", isOn: $engine.autoPaste)
                Toggle("Sons de feedback", isOn: $engine.sounds)
                Toggle("Hold-to-talk (segura ⌥+Space = grava)", isOn: $engine.holdToTalk)
                    .onChange(of: engine.holdToTalk) { engine.setupHotkey() }
                Toggle("Iniciar com o macOS", isOn: Binding(
                    get: { engine.launchManager.isEnabled },
                    set: { _ in engine.launchManager.toggle() }
                ))
            }
            Section("Atalho") {
                HStack {
                    Text("Ditar / Parar")
                    Spacer()
                    Text("⌥ + Espaco").padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Section("Permissoes") {
                HStack {
                    Text("Acessibilidade")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Label("Activo", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Activar") {
                            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Microfone
    private var micTab: some View {
        Form {
            Section("Dispositivo activo") {
                Picker("Microfone:", selection: $engine.micDevice) {
                    Text("Auto-detectar (recomendado)").tag("auto")
                    ForEach(mics, id: \.id) { mic in Text(mic.name).tag(mic.id) }
                }
                Button("Actualizar") { mics = engine.listMics() }
            }
            Section("Detectados") {
                if mics.isEmpty {
                    Text("Nenhum microfone detectado").foregroundStyle(.secondary)
                } else {
                    ForEach(mics, id: \.id) { mic in
                        HStack {
                            Image(systemName: mic.active ? "mic.fill" : "mic").foregroundStyle(mic.active ? .green : .secondary)
                            Text(mic.name)
                            Spacer()
                            if mic.active { Text("Activo").font(.caption).foregroundStyle(.green) }
                        }
                    }
                }
            }
            Section { Text("Dispositivos virtuais (Zoom, Teams) sao filtrados. USB mics (Yeti) aparecem quando ligados.").font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    // MARK: - Modelo
    private var modelTab: some View {
        Form {
            Section("Motor de transcricao") {
                Picker("Provider:", selection: $engine.transcriptionProvider) {
                    Text("Local — privado/offline").tag("local")
                    Text("OpenAI — melhor qualidade PT-PT").tag("openai")
                }

                if engine.transcriptionProvider == "openai" {
                    SecureField("OpenAI API Key:", text: $engine.openAITranscriptionKey)
                        .textFieldStyle(.roundedBorder)

                    Picker("Modelo OpenAI:", selection: $engine.openAITranscriptionModel) {
                        Text("gpt-4o-transcribe — qualidade maxima").tag("gpt-4o-transcribe")
                        Text("gpt-4o-mini-transcribe — mais barato").tag("gpt-4o-mini-transcribe")
                    }

                    Toggle("Preview live com gpt-realtime-whisper", isOn: $engine.realtimePreview)

                    Text("Se a chamada OpenAI falhar, o VoxFlow tenta o modelo local selecionado abaixo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Modelo Whisper") {
                Picker("Modelo:", selection: $engine.model) {
                    Text("base — 74 MB, rapido mas fraco").tag("base")
                    Text("small — 465 MB, basico").tag("small")
                    Text("medium — 1.5 GB, bom").tag("medium")
                    Text("large-v3-turbo — 1.6 GB, RECOMENDADO PT-PT").tag("large-v3-turbo")
                    Text("large-v3 — 3.1 GB, maximo (lento)").tag("large-v3")
                }
                let mp = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("VoxFlow/Models/ggml-\(engine.model).bin")
                if FileManager.default.fileExists(atPath: mp.path) {
                    Label("Pronto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Nao encontrado em ~/Library/Application Support/VoxFlow/Models", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section("Custo estimado") {
                let estimate = VoxCostEstimator.estimate(
                    durationSeconds: 60,
                    transcriptionModel: engine.openAITranscriptionModel,
                    polishModel: engine.polishProvider == "openai" ? engine.openAIPolishModel : nil,
                    includesRealtimePreview: engine.transcriptionProvider == "openai" && engine.realtimePreview
                )
                LabeledContent("Por minuto", value: VoxCostEstimator.formatUSD(estimate))
                Text("Estimativa conservadora para ditado curto; confirma sempre na dashboard da OpenAI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Aprendizagem") {
                LabeledContent("Correccoes guardadas", value: "\(engine.correctionStore.corrections.count)")
                Text("As correccoes que guardas no resultado alimentam o glossario das proximas transcricoes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Power Mode
    private var powerModeTab: some View {
        Form {
            Section("Modos por aplicacao") {
                Text("O VoxFlow adapta o tom da transcricao automaticamente consoante a app activa.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Modos activos") {
                ForEach(PowerModeManager.builtInModes + engine.powerMode.customModes) { mode in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mode.name).fontWeight(.medium)
                            Spacer()
                            Text(mode.isEnabled ? "Activo" : "Desactivo")
                                .font(.caption).foregroundStyle(mode.isEnabled ? .green : .secondary)
                        }
                        Text(mode.bundleIdentifiers.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Polish
    private var polishTab: some View {
        Form {
            Section("Servico de Polish") {
                Picker("Provider:", selection: $engine.polishProvider) {
                    Text("Desactivado").tag("none")
                    Text("OpenAI — gpt-5.5, melhor PT-PT").tag("openai")
                    Text("Groq — rapido, qualidade variavel").tag("groq")
                    Text("Google AI Studio").tag("google")
                    Text("OpenRouter").tag("openrouter")
                }
                if engine.polishProvider != "none" {
                    SecureField("API Key:", text: $engine.polishKey).textFieldStyle(.roundedBorder)
                    Link("Gerir API key", destination: URL(string: polishURL)!).font(.caption)
                    if engine.polishProvider == "openai" {
                        Text("Pode ficar vazio para reutilizar a key OpenAI da transcricao.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if engine.polishProvider == "openai" {
                Section("Modelo OpenAI") {
                    Picker("Modelo:", selection: $engine.openAIPolishModel) {
                        Text("gpt-5.5 — melhor qualidade").tag("gpt-5.5")
                        Text("gpt-5.4 — alternativa").tag("gpt-5.4")
                        Text("gpt-5.4-mini — economico").tag("gpt-5.4-mini")
                    }
                }
            }

            if engine.polishProvider == "openrouter" {
                Section("Modelo OpenRouter") {
                    Picker("Modelo:", selection: $engine.polishModel) {
                        Text("Llama 3.1 8B — rapido, bom PT").tag("meta-llama/llama-3.1-8b-instruct:free")
                        Text("Gemma 4 27B — excelente PT").tag("google/gemma-4-27b-it:free")
                        Text("Nemotron 3 Super 120B — maximo qualidade").tag("nvidia/nemotron-3-super-120b-instruct:free")
                        Text("Qwen3 Next 80B — forte multilingual").tag("qwen/qwen3-next-80b-a3b-instruct:free")
                    }
                }
            }

            Section("Vocabulario personalizado") {
                TextField("Nomes, termos tecnicos, marcas...", text: $engine.customVocab, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                Text("Exemplo: Patricia Pilar, SustentaReport, Daniela Alves, deploy, sprint, IFIC")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Como funciona") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("O motor escolhido transcreve o audio", systemImage: "1.circle.fill").font(.caption)
                    Label("O vocabulario e as correccoes guiam nomes e termos", systemImage: "2.circle.fill").font(.caption)
                    Label("O polish corrige pontuacao e ortografia PT-PT", systemImage: "3.circle.fill").font(.caption)
                    Label("O texto e colado automaticamente no cursor", systemImage: "4.circle.fill").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var polishURL: String {
        switch engine.polishProvider {
        case "openai": return "https://platform.openai.com/api-keys"
        case "groq": return "https://console.groq.com"
        case "google": return "https://aistudio.google.com"
        default: return "https://openrouter.ai/keys"
        }
    }

    // MARK: - History
    private var historyTab: some View {
        HistoryView(store: engine.historyStore)
    }

    // MARK: - Stats
    private var statsTab: some View {
        StatsView(entries: engine.historyStore.entries)
    }

    // MARK: - About
    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "waveform.circle.fill").font(.system(size: 48)).foregroundStyle(.purple)
            Text("VoxFlow").font(.title2).fontWeight(.bold)
            Text("v3.0").foregroundStyle(.secondary)
            Text("Transcricao PT-PT para macOS\nOpenAI para maxima qualidade • local para fallback/offline\nmacOS 14+")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
    }
}
