import Foundation

@MainActor
final class CorrectionMemoryStore: ObservableObject {
    @Published private(set) var corrections: [LearnedCorrection] = []

    private static let maxCorrections = 200

    private static let directoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxflow", isDirectory: true)
    }()

    private static let fileURL = directoryURL.appendingPathComponent("corrections.json")

    init() {
        corrections = Self.loadFromDisk()
    }

    func learn(rawText: String, correctedText: String) {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !corrected.isEmpty, raw != corrected else { return }

        corrections.append(LearnedCorrection(rawText: raw, correctedText: corrected))
        if corrections.count > Self.maxCorrections {
            corrections = Array(corrections.suffix(Self.maxCorrections))
        }
        saveToDisk()
    }

    var recentCorrections: [LearnedCorrection] {
        Array(corrections.suffix(40))
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(corrections)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[VoxFlow] Erro ao gravar correções: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> [LearnedCorrection] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([LearnedCorrection].self, from: data)
        } catch {
            print("[VoxFlow] Erro ao ler correções: \(error.localizedDescription)")
            return []
        }
    }
}
