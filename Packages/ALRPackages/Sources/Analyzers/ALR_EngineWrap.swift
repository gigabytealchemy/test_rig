import CoreTypes
import Foundation

public struct ALR_EngineWrap: Analyzer {
    public let category: AlgorithmCategory = .alr
    public let name: String = "ALR • Engine (sentiment-aware)"
    private let engine = ActiveListenerEngine()

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        let emotionString = input.fallbackEmotion
            ?? inferEmotionString(text)

        let reply = engine.respond(to: text, fallbackEmotion: emotionString)
        return AnalyzerOutput(category: category,
                              name: name,
                              result: reply,
                              metadata: ["emotion": emotionString])
    }

    private func inferEmotionString(_ text: String) -> String {
        // Use the V2 analyzer's emotion detection
        let emotionID = EmotionRegexV2().quickID(text)
        return emotionStringFor(emotionID)
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
