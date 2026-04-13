import SwiftUI

struct StatsView: View {
    let entries: [HistoryEntry]

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    private var timeSaved: String {
        let seconds = totalWords * 3 / 2 // ~1.5s saved per word vs typing
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
    private var avgSpeed: String {
        guard !entries.isEmpty else { return "—" }
        let avg = Double(entries.reduce(0) { $0 + $1.durationSeconds }) / Double(entries.count)
        return String(format: "%.1fs", avg)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: [.init(), .init()], spacing: 10) {
                    card("Transcricoes", "\(entries.count)", "mic.fill", .purple)
                    card("Palavras", "\(totalWords)", "text.word.spacing", .blue)
                    card("Tempo poupado", timeSaved, "clock.arrow.circlepath", .green)
                    card("Vel. media", avgSpeed, "bolt.fill", .orange)
                }

                // 7-day chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ultimos 7 dias").font(.subheadline).fontWeight(.semibold)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(0..<7, id: \.self) { offset in
                            let date = Calendar.current.date(byAdding: .day, value: -(6 - offset), to: Date())!
                            let count = entries.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }.count
                            let maxC = max(entries.count / 7 + 1, 1)
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                                    .frame(height: max(4, CGFloat(count) / CGFloat(maxC) * 60))
                                Text(dayLabel(date, offset: 6 - offset)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 90)
                }
                .padding(14)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
    }

    private func card(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3).fontWeight(.bold)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func dayLabel(_ date: Date, offset: Int) -> String {
        if offset == 0 { return "Hoje" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }
}
