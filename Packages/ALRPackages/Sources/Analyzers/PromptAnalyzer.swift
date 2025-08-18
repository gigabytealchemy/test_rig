import CoreTypes
import Foundation

public struct PromptAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .prompt
    public let name: String = "BankedPrompts"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let emotion = (input.fallbackEmotion ?? "neutral").lowercased()
        let bank: [String: String] = [
            "joy": "Write a gratitude note focusing on a highlight from today.",
            "sadness": "Gently explore what you needed today but didn't get.",
            "anger": "List the triggers and one boundary you can set next time.",
            "neutral": "Pick one sentence to expand with sensory detail.",
        ]
        let prompt = bank[emotion, default: "Reflect on a small action you can take next."]
        return AnalyzerOutput(
            category: .prompt,
            name: name,
            result: prompt,
            durationMS: 0,
            metadata: ["emotion": emotion]
        )
    }
}
