import SwiftUI

// MARK: - HistoryEntry

/// A single transcription record with metadata for search and export.
struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let rawText: String
    let language: String
    let mode: String
    let appName: String
    let timestamp: Date
    let durationSeconds: Int

    init(
        id: UUID = UUID(),
        text: String,
        rawText: String,
        language: String = "auto",
        mode: String = "Geral",
        appName: String = "",
        timestamp: Date = Date(),
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.language = language
        self.mode = mode
        self.appName = appName
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
    }
}

// MARK: - HistoryStore

/// Searchable, disk-persisted transcription history.
///
/// Entries are stored as JSON at `~/.voxflow/history.json` and capped
/// at 500 records (oldest trimmed first).
@MainActor
final class HistoryStore: ObservableObject {

    // MARK: Published State

    @Published var entries: [HistoryEntry] = []

    // MARK: Constants

    static let maxEntries = 500

    private static let directoryURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".voxflow", isDirectory: true)
    }()

    private static let fileURL: URL = {
        directoryURL.appendingPathComponent("history.json")
    }()

    // MARK: Init

    init() {
        entries = Self.loadFromDisk()
    }

    // MARK: - Public API

    /// Append a new entry, trim to max, and persist.
    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        trimIfNeeded()
        saveToDisk()
    }

    /// All entries (most recent first — already sorted by insertion order).
    var allEntries: [HistoryEntry] { entries }

    /// Case-insensitive search across `text`, `rawText`, `appName`, and `mode`.
    func search(query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        let lowered = trimmed.lowercased()
        return entries.filter { entry in
            entry.text.lowercased().contains(lowered)
                || entry.rawText.lowercased().contains(lowered)
                || entry.appName.lowercased().contains(lowered)
                || entry.mode.lowercased().contains(lowered)
        }
    }

    /// Delete a single entry by id.
    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Delete all entries.
    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    /// Export the full history as a Markdown document.
    func exportMarkdown() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "pt_PT")

        var lines: [String] = ["# VoxFlow — Historico de Transcricoes", ""]

        for entry in entries {
            let date = dateFormatter.string(from: entry.timestamp)
            let duration = formatDuration(entry.durationSeconds)

            lines.append("## \(date)")
            lines.append("")
            lines.append("- **Modo:** \(entry.mode)")
            lines.append("- **App:** \(entry.appName.isEmpty ? "—" : entry.appName)")
            lines.append("- **Lingua:** \(entry.language)")
            lines.append("- **Duracao:** \(duration)")
            lines.append("")
            lines.append("### Texto Final")
            lines.append("")
            lines.append(entry.text)
            lines.append("")

            if entry.rawText != entry.text {
                lines.append("### Texto Original")
                lines.append("")
                lines.append(entry.rawText)
                lines.append("")
            }

            lines.append("---")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[VoxFlow] Erro ao gravar historico: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
            return decoded
        } catch {
            print("[VoxFlow] Erro ao ler historico: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers

    private func trimIfNeeded() {
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}
