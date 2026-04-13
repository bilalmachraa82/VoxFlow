import SwiftUI
import ServiceManagement

/// Manages launch-at-login registration via `SMAppService` (macOS 13+).
///
/// The `isEnabled` property reflects the live system status — it is not
/// cached, so it always returns the truth from the OS.
@MainActor
final class LaunchManager: ObservableObject {

    // MARK: Published State

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            // Keep the system in sync when SwiftUI toggles this binding.
            if isEnabled {
                register()
            } else {
                unregister()
            }
        }
    }

    // MARK: Init

    init() {
        // Read the current system status so the toggle starts in the right position.
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Public API

    /// Toggle launch-at-login on or off.
    func toggle() {
        if isEnabled {
            unregister()
        } else {
            register()
        }
    }

    // MARK: - Private

    private func register() {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
        } catch {
            print("[VoxFlow] Erro ao registar arranque automatico: \(error.localizedDescription)")
            isEnabled = false
        }
    }

    private func unregister() {
        do {
            try SMAppService.mainApp.unregister()
            isEnabled = false
        } catch {
            print("[VoxFlow] Erro ao remover arranque automatico: \(error.localizedDescription)")
            // Re-read the real status in case unregister failed.
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
