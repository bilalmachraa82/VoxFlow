import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var searchText = ""
    @State private var expandedID: UUID?
    @State private var showClearConfirmation = false

    private var filteredEntries: [HistoryEntry] {
        if searchText.isEmpty {
            return store.entries
        }
        return store.search(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }

            Divider()
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Pesquisar transcricoes...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            if searchText.isEmpty {
                Text("Sem transcricoes ainda.\nPrima \u{2325}+Espaco para comecar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Nenhum resultado para \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                entryRow(entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        }
                    }
            }
            .onDelete(perform: deleteEntries)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: HistoryEntry) -> some View {
        let isExpanded = expandedID == entry.id
        return VStack(alignment: .leading, spacing: 6) {
            // Header: timestamp + app badge + duration
            HStack(spacing: 8) {
                Text(relativeTimestamp(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                appBadge(entry.appName)

                Spacer()

                Text(formattedDuration(entry.durationSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Preview or full text
            if isExpanded {
                expandedContent(entry)
            } else {
                Text(entry.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private func expandedContent(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if entry.rawText != entry.text {
                DisclosureGroup("Texto original") {
                    Text(entry.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - App Badge

    private func appBadge(_ name: String) -> some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.12))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                exportMarkdown()
            } label: {
                Label("Exportar Markdown", systemImage: "arrow.down.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.entries.isEmpty)

            Spacer()

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Limpar tudo", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.entries.isEmpty)
            .alert("Limpar historico?", isPresented: $showClearConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Limpar tudo", role: .destructive) {
                    withAnimation {
                        store.clearAll()
                    }
                }
            } message: {
                Text("Todas as transcricoes serao apagadas permanentemente.")
            }
        }
    }

    // MARK: - Actions

    private func deleteEntries(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredEntries[$0].id }
        withAnimation {
            for id in idsToDelete {
                store.deleteEntry(id: id)
            }
        }
    }

    private func exportMarkdown() {
        let md = store.exportMarkdown()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "voxflow-historico.md"
        panel.title = "Exportar Historico"
        panel.prompt = "Guardar"

        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Formatting

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_PT")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }
}
