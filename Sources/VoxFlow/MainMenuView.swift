import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var engine: VoxEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, minHeight: 220).padding(16)
            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear {
            if !engine.onboardingComplete {
                openWindow(id: "onboarding")
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: "waveform").foregroundStyle(.purple)
            Text("VoxFlow").font(.headline)
            Spacer()
            statusPill
        }
        .padding(16)
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle().fill(stateColor).frame(width: 6, height: 6)
            Text(stateLabel).font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.ultraThinMaterial).clipShape(Capsule())
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        switch engine.state {
        case .idle:      idleView
        case .recording: recordingView
        case .transcribing, .polishing: loadingView
        case .done:      resultView
        case .error:     errorView
        }
    }

    private var idleView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "mic.circle").font(.system(size: 44)).foregroundStyle(.purple.opacity(0.5))
            Text("Prima ⌥+Espaco para ditar").font(.subheadline).foregroundStyle(.secondary)

            Button { engine.toggle() } label: {
                Label("Comecar a gravar", systemImage: "mic.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)

            if !engine.lastResult.isEmpty {
                Divider().padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ultima:").font(.caption).foregroundStyle(.tertiary)
                    Text(engine.lastResult).font(.callout).lineLimit(3).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
    }

    private var recordingView: some View {
        VStack(spacing: 12) {
            Spacer()

            // Waveform (simple bars from engine levels)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<engine.audioLevels.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .bottom, endPoint: .top))
                        .frame(width: 8, height: max(4, CGFloat(engine.audioLevels[i]) * 55))
                        .animation(.spring(response: 0.15), value: engine.audioLevels[i])
                }
            }
            .frame(height: 60)
            .padding(.horizontal)

            Text("\(engine.recordingSeconds)s").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.red)

            Button { engine.toggle() } label: {
                Label("Parar", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)

            MicIndicatorView(
                micName: engine.listMics().first(where: \.active)?.name ?? "Microfone",
                isActive: true
            )

            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text(engine.state == .transcribing ? "A transcrever..." : "A polir texto...")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Resultado").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(engine.lastResult, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
            }
            ScrollView {
                Text(engine.lastResult).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if engine.autoPaste {
                Label("Colado no cursor", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Button { engine.state = .idle } label: {
                Label("Nova gravacao", systemImage: "mic.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.purple)
        }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.yellow)
            Text(engine.errorMsg).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Tentar novamente") { engine.state = .idle }.buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Image(systemName: "gear") }
            .buttonStyle(.borderless)

            Spacer()
            Text("⌥+Espaco").font(.caption2).foregroundStyle(.tertiary)
            Spacer()

            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var stateColor: Color {
        switch engine.state {
        case .idle, .done: return .green
        case .recording: return .red
        case .transcribing, .polishing: return .orange
        case .error: return .yellow
        }
    }
    private var stateLabel: String {
        switch engine.state {
        case .idle: return "Pronto"
        case .recording: return "A gravar"
        case .transcribing: return "A transcrever"
        case .polishing: return "A polir"
        case .done: return "Concluido"
        case .error: return "Erro"
        }
    }
}
