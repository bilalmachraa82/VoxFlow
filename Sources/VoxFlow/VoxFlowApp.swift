import SwiftUI

@main
struct VoxFlowApp: App {
    @StateObject private var engine = VoxEngine()

    var body: some Scene {
        WindowGroup("VoxFlow") {
            MainMenuView()
                .environmentObject(engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MainMenuView()
                .environmentObject(engine)
        } label: {
            Label {
                Text("VoxFlow")
            } icon: {
                Image(systemName: engine.state == .recording ? "mic.fill" : "waveform")
            }
        }
        .menuBarExtraStyle(.window)

        Window("VoxFlow — Definicoes", id: "settings") {
            SettingsScreen()
                .environmentObject(engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("VoxFlow — Bem-vindo", id: "onboarding") {
            OnboardingView()
                .environmentObject(engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
