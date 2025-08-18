import CoreTypes
import Foundation

public struct ALR_EngineWithPatternHint: Analyzer {
    public let category: AlgorithmCategory = .alr
    public let name: String = "ALR • Engine + Pattern Hint"
    private let engine = ActiveListenerEngine()

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        let clf = RuleEmotionClassifierPro()
        let emotionResult = clf.classify(text)
        let emotionID = emotionResult.id
        let emotionString = emotionStringFor(emotionID)
        let main = engine.respond(to: text, fallbackEmotion: emotionString)

        // naive pattern "repetition" detector on the last paragraph
        let lastPara = text.split(separator: "\n").last.map(String.init) ?? text
        let hint = repetitionHint(lastPara)

        let result = hint.map { "\($0)\n\(main)" } ?? main
        return AnalyzerOutput(category: category,
                              name: name,
                              result: result,
                              metadata: ["emotionID": "\(emotionID)", "emotion": emotionString])
    }

    private func repetitionHint(_ s: String) -> String? {
        // If the last paragraph repeats a strong phrase like "I don't know" or "I'm tired"
        let cues = ["i don't know", "i dont know", "i'm tired", "i am tired", "i keep", "again", "still"]
        let lower = s.lowercased()
        guard cues.contains(where: { lower.contains($0) }) else { return nil }
        // Solo, non-directive hint
        return "That seems to show up for you sometimes. Is there more you'd like to say about it?"
    }

    private func emotionStringFor(_ id: Int) -> String {
        switch id {
        case 1: "joy"
        case 2: "sadness"
        case 3: "anger"
        case 4: "fear"
        case 5: "surprise"
        case 6: "disgust"
        case 8: "mixed"
        default: "neutral"
        }
    }
}
