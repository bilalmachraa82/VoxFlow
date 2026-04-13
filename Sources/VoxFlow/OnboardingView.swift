import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @EnvironmentObject var engine: VoxEngine

    @State private var currentStep = 0
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var isDownloadingModel = false
    @State private var downloadProgress: Double = 0
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var permissionTimer: Timer?

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: microphoneStep
                case 2: accessibilityStep
                case 3: modelStep
                case 4: testStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .frame(width: 480, height: 520)
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.purple : (index < currentStep ? Color.purple.opacity(0.4) : Color.gray.opacity(0.3)))
                    .frame(width: index == currentStep ? 10 : 8, height: index == currentStep ? 10 : 8)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.purple)

            Text("VoxFlow")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Transcricao de voz local")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Label("100% gratis", systemImage: "gift.fill")
                    .foregroundStyle(.green)
                Label("100% privado", systemImage: "lock.shield.fill")
                    .foregroundStyle(.blue)
            }
            .font(.subheadline)
            .padding(.top, 8)

            Spacer()

            Button {
                withAnimation { currentStep = 1 }
            } label: {
                Text("Comecar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
        }
    }

    // MARK: - Step 2: Microphone Permission

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

            Text("Acesso ao microfone")
                .font(.title2)
                .fontWeight(.semibold)

            Text("O VoxFlow precisa de acesso ao microfone para capturar a tua voz e transcrever localmente. O audio nunca sai do teu Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()

            if micPermissionGranted {
                Label("Permissao concedida", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button {
                    requestMicrophonePermission()
                } label: {
                    Label("Permitir microfone", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
            }
        }
        .onAppear {
            checkMicPermission()
            startMicPolling()
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Step 3: Accessibility Permission

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "accessibility")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

            Text("Acesso de acessibilidade")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Para colar texto automaticamente no cursor, o VoxFlow precisa de permissao de acessibilidade. Isto permite simular Cmd+V apos a transcricao.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()

            if accessibilityGranted {
                Label("Permissao concedida", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button {
                    requestAccessibilityPermission()
                } label: {
                    Label("Abrir Preferencias", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)

                Text("Activa o VoxFlow na lista que aparece")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            startAccessibilityPolling()
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Step 4: Model

    private var modelStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

            Text("Modelo de transcricao")
                .font(.title2)
                .fontWeight(.semibold)

            Text("O modelo '\(engine.model)' sera usado para transcrever. E um bom equilibrio entre velocidade e qualidade.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            let modelPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VoxFlow/Models/ggml-\(engine.model).bin")

            if FileManager.default.fileExists(atPath: modelPath.path) {
                Label("Modelo pronto", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else if isDownloadingModel {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .tint(.purple)
                        .frame(maxWidth: 280)
                    Text("A descarregar... \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Modelo nao encontrado — usa 'vox --setup' no terminal", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Spacer()

            Button {
                withAnimation { currentStep = 4 }
            } label: {
                Text("Continuar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
        }
    }

    // MARK: - Step 5: Test

    private var testStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if testResult.isEmpty {
                Text("Faz o teu primeiro teste!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Prima o botao e fala.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    startTest()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isTesting ? Color.red.opacity(0.15) : Color.purple.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: isTesting ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(isTesting ? .red : .purple)
                    }
                }
                .buttonStyle(.plain)

                if isTesting {
                    Text("A gravar... prima novamente para parar")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Funciona!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(testResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 340)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            if !testResult.isEmpty {
                Button {
                    onboardingComplete = true
                } label: {
                    Text("Concluido!")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
            }

            // Skip option for users who want to complete later
            if testResult.isEmpty && !isTesting {
                Button("Saltar teste") {
                    onboardingComplete = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
    }

    // MARK: - Permission Helpers

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                micPermissionGranted = granted
                if granted {
                    permissionTimer?.invalidate()
                    permissionTimer = nil
                    withAnimation { currentStep = 2 }
                }
            }
        }
    }

    private func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micPermissionGranted = status == .authorized
    }

    private func startMicPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .authorized {
                    micPermissionGranted = true
                    permissionTimer?.invalidate()
                    permissionTimer = nil
                    withAnimation { currentStep = 2 }
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func startAccessibilityPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if AXIsProcessTrusted() {
                    accessibilityGranted = true
                    permissionTimer?.invalidate()
                    permissionTimer = nil
                    withAnimation { currentStep = 3 }
                }
            }
        }
    }

    // MARK: - Test Helpers

    private func startTest() {
        if isTesting {
            engine.toggle()
            isTesting = false
            // Observe engine state to capture result
            observeTestResult()
        } else {
            isTesting = true
            testResult = ""
            engine.toggle()
        }
    }

    private func observeTestResult() {
        // Poll engine state to capture transcription result
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            Task { @MainActor in
                switch engine.state {
                case .done:
                    timer.invalidate()
                    testResult = engine.lastResult
                case .error:
                    timer.invalidate()
                    testResult = "Erro: \(engine.errorMsg)"
                case .idle:
                    // If engine returned to idle without result, keep waiting briefly
                    break
                default:
                    break
                }
            }
        }
    }
}
