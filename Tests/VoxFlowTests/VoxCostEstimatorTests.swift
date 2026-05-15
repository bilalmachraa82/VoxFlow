import XCTest
@testable import VoxFlow

final class VoxCostEstimatorTests: XCTestCase {
    func testQualitySetupEstimatesAboutTwoCentsPerMinute() {
        let estimate = VoxCostEstimator.estimate(
            durationSeconds: 60,
            transcriptionModel: "gpt-4o-transcribe",
            polishModel: "gpt-5.5",
            includesRealtimePreview: false
        )

        XCTAssertEqual(estimate, 0.02, accuracy: 0.01)
    }

    func testMiniTranscribeAndNoPolishIsCheaperThanQualitySetup() {
        let quality = VoxCostEstimator.estimate(
            durationSeconds: 60,
            transcriptionModel: "gpt-4o-transcribe",
            polishModel: "gpt-5.5",
            includesRealtimePreview: false
        )
        let economy = VoxCostEstimator.estimate(
            durationSeconds: 60,
            transcriptionModel: "gpt-4o-mini-transcribe",
            polishModel: nil,
            includesRealtimePreview: false
        )

        XCTAssertLessThan(economy, quality)
    }

    func testRealtimePreviewAddsStreamingCost() {
        let finalOnly = VoxCostEstimator.estimate(
            durationSeconds: 60,
            transcriptionModel: "gpt-4o-transcribe",
            polishModel: "gpt-5.5",
            includesRealtimePreview: false
        )
        let withPreview = VoxCostEstimator.estimate(
            durationSeconds: 60,
            transcriptionModel: "gpt-4o-transcribe",
            polishModel: "gpt-5.5",
            includesRealtimePreview: true
        )

        XCTAssertGreaterThan(withPreview, finalOnly)
    }
}
