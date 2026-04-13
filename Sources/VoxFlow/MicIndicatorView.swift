import SwiftUI

struct MicIndicatorView: View {
    let micName: String
    let isActive: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Image(systemName: "mic.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(micName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help("Clica para mudar microfone")
    }
}
