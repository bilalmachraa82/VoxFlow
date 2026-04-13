import SwiftUI
import AVFoundation

// MARK: - WaveformGenerator

@MainActor
final class WaveformGenerator: ObservableObject {
    @Published var levels: [Float]

    private var audioEngine: AVAudioEngine?
    private var displayTimer: Timer?
    private let barCount: Int
    private var rawLevel: Float = 0

    init(barCount: Int = 18) {
        self.barCount = barCount
        self.levels = Array(repeating: 0, count: barCount)
    }

    func start() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }

            // Calculate RMS
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = data[i]
                sum += sample * sample
            }
            let rms = sqrtf(sum / Float(frameLength))

            // Normalize to 0-1 range (typical mic RMS is 0-0.5)
            let normalized = min(rms * 3.0, 1.0)
            Task { @MainActor in
                self.rawLevel = normalized
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            return
        }

        // Update levels at ~15fps for smooth animation
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevels()
            }
        }
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Animate levels back to zero
        withAnimation(.easeOut(duration: 0.4)) {
            levels = Array(repeating: 0, count: barCount)
        }
    }

    private func updateLevels() {
        let base = rawLevel

        // Shift existing levels left and add new level with variation
        var newLevels = Array(levels.dropFirst())
        let variation = Float.random(in: -0.15...0.15)
        let newLevel = max(0, min(1, base + variation))
        newLevels.append(newLevel)

        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            levels = newLevels
        }
    }
}

// MARK: - WaveformView

struct WaveformView: View {
    @ObservedObject var generator: WaveformGenerator

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let cornerRadius: CGFloat = 1.5
    private let maxHeight: CGFloat = 50

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(generator.levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(barGradient(for: index))
                    .frame(width: barWidth, height: barHeight(for: level))
            }
        }
        .frame(height: maxHeight)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minHeight: CGFloat = 4
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }

    private func barGradient(for index: Int) -> LinearGradient {
        let position = CGFloat(index) / CGFloat(max(generator.levels.count - 1, 1))
        let startColor = Color.purple.opacity(0.6 + position * 0.4)
        let endColor = Color.purple.opacity(0.3 + position * 0.3)
        return LinearGradient(
            colors: [startColor, endColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var generator = WaveformGenerator(barCount: 18)

        var body: some View {
            VStack(spacing: 16) {
                WaveformView(generator: generator)
                    .frame(width: 200, height: 60)

                HStack {
                    Button("Start") { generator.start() }
                    Button("Stop") { generator.stop() }
                }
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
