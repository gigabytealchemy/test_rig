import CoreTypes
import Foundation

public struct ALR_EnginePro: Analyzer {
    public let category: AlgorithmCategory = .alr
    public let name: String = "ALR • Engine Pro (domain-aware)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        // Get emotion ID (1-8) either from fallback or by detecting
        let emotionID = mapEmotionString(input.fallbackEmotion)
            ?? inferEmotionID(text)

        // Use DomainProAnalyzer for domain detection
        let domainClf = DomainClassifierPro()
        let domainResult = domainClf.classify(text)
        
        // Convert DomainProAnalyzer result to expected format
        let domains = domainResult.ranked.map { ($0.name, $0.score) }

        // Call the Pro engine
        let reply = ActiveListenerEnginePro.shared.respond(
            to: text,
            emotion: emotionID,
            domains: domains
        ) ?? "I'm here, listening."

        // Build metadata
        var metadata: [String: String] = [
            "emotionID": "\(emotionID)",
            "emotion": emotionStringFor(emotionID),
        ]

        if !domains.isEmpty {
            let topDomain = domains.max(by: { $0.1 < $1.1 })
            metadata["topDomain"] = topDomain.map { "\($0.0): \(String(format: "%.2f", $0.1))" }
            metadata["domains"] = domains.map { "\($0.0):\(String(format: "%.2f", $0.1))" }.joined(separator: ", ")
        }

        return AnalyzerOutput(
            category: category,
            name: name,
            result: reply,
            metadata: metadata
        )
    }

    private func mapEmotionString(_ s: String?) -> Int? {
        guard let s else { return nil }
        let key = s.lowercased()
        let map: [String: Int] = [
            "joy": 1, "happy": 1, "happiness": 1,
            "sad": 2, "sadness": 2,
            "anger": 3, "angry": 3,
            "fear": 4, "anxiety": 4, "anxious": 4,
            "surprise": 5, "surprised": 5,
            "disgust": 6, "disgusted": 6,
            "neutral": 7,
            "mixed": 8,
        ]
        return map[key]
    }

    private func inferEmotionID(_ text: String) -> Int {
        // Use EmotionProAnalyzer for emotion detection
        let clf = RuleEmotionClassifierPro()
        return clf.classify(text).id
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
