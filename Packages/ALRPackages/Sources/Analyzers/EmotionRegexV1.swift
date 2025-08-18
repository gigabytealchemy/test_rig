import CoreTypes
import Foundation

public struct EmotionRegexV1: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "Emotion • Rules (V1)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        let (id, label, scores) = score(text: text)
        let md = scores.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(id) – \(label)",
                              metadata: ["scores": md])
    }

    private func score(text: String) -> (Int, String, [String: Int]) {
        let t = text.lowercased()
        var s = ["Joy": 0, "Sadness": 0, "Anger": 0, "Fear": 0, "Surprise": 0, "Disgust": 0, "Neutral": 0]

        // high-precision patterns
        if t.contains("i regret") || t.contains("i miss ") { s["Sadness", default: 0] += 3 }
        if t.contains("i'm proud") || t.contains("i am proud") || t.contains("grateful") { s["Joy", default: 0] += 3 }
        if t.contains("i'm afraid") || t.contains("i am afraid") || t.contains("worried") { s["Fear", default: 0] += 3 }
        if t.contains("betray") || t.contains("furious") || t.contains("angry") { s["Anger", default: 0] += 3 }
        if t.contains("didn't expect") || t.contains("out of nowhere") || t.contains("sudden") { s["Surprise", default: 0] += 2 }
        if t.contains("gross") || t.contains("disgust") || t.contains("can't stand") { s["Disgust", default: 0] += 3 }

        // emoji cues
        if t.contains("🙂") { s["Joy", default: 0] += 2 }
        if t.contains("😢") { s["Sadness", default: 0] += 2 }
        if t.contains("😠") { s["Anger", default: 0] += 2 }
        if t.contains("😨") { s["Fear", default: 0] += 2 }
        if t.contains("😮") { s["Surprise", default: 0] += 2 }
        if t.contains("🤢") { s["Disgust", default: 0] += 2 }

        // pick winner
        if s.values.allSatisfy({ $0 == 0 }) { return (7, "Neutral 😐", s.mapValues { $0 }) }
        let best = s.max { $0.value < $1.value }!
        let id = ["Joy": 1, "Sadness": 2, "Anger": 3, "Fear": 4, "Surprise": 5, "Disgust": 6, "Neutral": 7][best.key] ?? 7
        let label = best.key + " " + ["Joy": "🙂", "Sadness": "😢", "Anger": "😠", "Fear": "😨", "Surprise": "😮", "Disgust": "🤢", "Neutral": "😐"][best.key]!
        return (id, label, s)
    }
}
