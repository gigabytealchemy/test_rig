import CoreTypes
import Foundation

public struct RuleEmotionAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "RuleEmotion (stub)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let t = input.selectedText.lowercased()
        let emotion = if t.contains("angry") { "anger" } else if t.contains("sad") { "sadness" } else if t.contains("happy") { "joy" } else { "neutral" }

        return AnalyzerOutput(
            category: .emotion,
            name: name,
            result: emotion,
            durationMS: 0,
            metadata: [:]
        )
    }
}
