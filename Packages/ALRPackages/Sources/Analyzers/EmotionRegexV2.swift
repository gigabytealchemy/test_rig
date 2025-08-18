import CoreTypes
import Foundation

public struct EmotionRegexV2: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "Emotion • Rules+Heuristics (V2)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText
        let t = text.lowercased()

        // clause after "but/however/though" has priority
        let prioritized = prioritizeAfterContrast(t)

        var s = [1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0, 6: 0.0, 7: 0.0] // 1..7

        func bump(_ id: Int, _ v: Double) { s[id, default: 0] += v }

        // base cues (reuse V1 ideas)
        if prioritized.contains("i regret") || prioritized.contains("miss ") { bump(2, 3) }
        if prioritized.contains("i'm proud") || prioritized.contains("grateful") { bump(1, 3) }
        if prioritized.contains("afraid") || prioritized.contains("worried") || prioritized.contains("anxious") { bump(4, 3) }
        if prioritized.contains("angry") || prioritized.contains("furious") || prioritized.contains("betray") { bump(3, 3) }
        if prioritized.contains("didn't expect") || prioritized.contains("out of nowhere") || prioritized.contains("sudden") { bump(5, 2) }
        if prioritized.contains("gross") || prioritized.contains("disgust") || prioritized.contains("can't stand") { bump(6, 3) }

        // negation flips for common pairs
        if prioritized.contains("not happy") { bump(2, 2) }
        if prioritized.contains("not sad") { bump(1, 1) }
        if prioritized.contains("not afraid") || prioritized.contains("not anxious") { bump(1, 1) }

        // intensifiers / dampeners
        let intens = ["very", "so", "really", "extremely", "soooo", "!"]
        let damp = ["a bit", "kind of", "slightly", "somewhat"]
        let mult: Double = intens.first(where: { prioritized.contains($0) }) != nil ? 1.5 :
            damp.first(where: { prioritized.contains($0) }) != nil ? 0.7 : 1.0
        for k in s.keys {
            s[k]! *= mult
        }

        // fallback
        if s.values.allSatisfy({ $0 == 0 }) { s[7] = 1 }

        let sorted = s.sorted { $0.value > $1.value }
        let top = sorted[0]
        let second = sorted.count > 1 ? sorted[1] : (7, 0)
        let mixed = (second.1 > 0 && (top.1 - second.1) / max(1.0, top.1) < 0.2)
        let id = mixed ? 8 : top.0
        let label = labelFor(id)
        let md = sorted
            .map { "\(labelFor($0.0)): \(String(format: "%.1f", $0.1))" }
            .joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(id) – \(label)",
                              metadata: ["scores": md])
    }

    private func prioritizeAfterContrast(_ t: String) -> String {
        let splitters = [" but ", " however ", " though "]
        for s in splitters {
            if let r = t.range(of: s) { return String(t[r.upperBound...]) }
        }
        return t
    }

    private func labelFor(_ id: Int) -> String {
        switch id {
        case 1: "Joy 🙂"
        case 2: "Sadness 😢"
        case 3: "Anger 😠"
        case 4: "Fear 😨"
        case 5: "Surprise 😮"
        case 6: "Disgust 🤢"
        case 8: "Mixed 😵‍💫"
        default: "Neutral 😐"
        }
    }

    // Helper for other analyzers to reuse emotion detection
    func quickID(_ text: String) -> Int {
        let out = try? analyze(.init(fullText: text, selectedRange: nil, fallbackEmotion: nil))
        let prefix = out?.result.prefix(1) ?? "7"
        return Int(String(prefix)) ?? 7
    }
}
