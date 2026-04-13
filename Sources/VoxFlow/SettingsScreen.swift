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
                    Label("Nao descarregado — usa 'vox --status' no terminal", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section("Performance M4") {
                LabeledContent("Benchmark JFK (11s)", value: "~1.1s")
                LabeledContent("Target", value: "<3s para 10s audio")
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
            Section("Servico de Polish (gratis)") {
                Picker("Provider:", selection: $engine.polishProvider) {
                    Text("Desactivado").tag("none")
                    Text("Groq — RECOMENDADO (300+ tok/s, 14k req/dia gratis)").tag("groq")
                    Text("Google AI Studio (500 req/dia gratis)").tag("google")
                    Text("OpenRouter (50 req/dia gratis, 1000 com $10)").tag("openrouter")
                }
                if engine.polishProvider != "none" {
                    SecureField("API Key:", text: $engine.polishKey).textFieldStyle(.roundedBorder)
                    Link("Obter key gratis →", destination: URL(string: polishURL)!).font(.caption)
                }
            }

            if engine.polishProvider == "openrouter" {
                Section("Modelo OpenRouter (todos gratis)") {
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
                    Label("Whisper transcreve o audio localmente", systemImage: "1.circle.fill").font(.caption)
                    Label("O vocabulario ajuda Whisper a reconhecer nomes", systemImage: "2.circle.fill").font(.caption)
                    Label("O LLM corrige pontuacao e ortografia PT-PT", systemImage: "3.circle.fill").font(.caption)
                    Label("O texto e colado automaticamente no cursor", systemImage: "4.circle.fill").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var polishURL: String {
        switch engine.polishProvider {
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
            Text("Transcricao de voz local para PT-PT\n100% gratis • 100% privado • 0 MB idle\nwhisper.cpp + Metal • macOS 14+")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
    }
}
