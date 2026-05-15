import Foundation

enum VoxCostEstimator {
    private static let transcriptionPerMinute: [String: Double] = [
        "gpt-4o-transcribe": 0.012,
        "gpt-4o-mini-transcribe": 0.006
    ]

    private static let polishPerMinute: [String: Double] = [
        "gpt-5.5": 0.008,
        "gpt-5.4": 0.004,
        "gpt-5.4-mini": 0.0015
    ]

    private static let realtimePreviewPerMinute = 0.017

    static func estimate(
        durationSeconds: Int,
        transcriptionModel: String,
        polishModel: String?,
        includesRealtimePreview: Bool
    ) -> Double {
        guard durationSeconds > 0 else { return 0 }

        let minutes = Double(durationSeconds) / 60.0
        let stt = transcriptionPerMinute[transcriptionModel] ?? 0
        let polish = polishModel.flatMap { polishPerMinute[$0] } ?? 0
        let realtime = includesRealtimePreview ? realtimePreviewPerMinute : 0

        return minutes * (stt + polish + realtime)
    }

    static func formatUSD(_ value: Double) -> String {
        if value < 0.005 {
            return "<$0.01"
        }
        return String(format: "$%.2f", value)
    }
}
