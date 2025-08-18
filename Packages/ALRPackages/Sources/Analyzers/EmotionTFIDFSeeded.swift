import CoreTypes
import Foundation

public struct EmotionTFIDFSeeded: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "Emotion • TF-IDF Seeded (no model)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        let tf = termFreq(text)
        let scores = emotionSeeds.mapValues { cosine(tf, $0) }
        let best = scores.max { $0.value < $1.value }!
        let id = idFor(best.key)
        let label = labelFor(id)
        let md = scores.map { "\($0.key): \(String(format: "%.2f", $0.value))" }.sorted().joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(id) – \(label)",
                              metadata: ["similarity": md])
    }

    // Tiny seed bags (expand freely)
    private let emotionSeeds: [String: [String: Double]] = [
        "Joy": ["proud": 1, "grateful": 1, "relief": 1, "glad": 1, "win": 1, "appreciate": 1],
        "Sadness": ["regret": 1, "miss": 1, "lonely": 1, "loss": 1, "grief": 1, "tired": 1],
        "Anger": ["angry": 1, "furious": 1, "annoyed": 1, "unfair": 1, "betray": 1],
        "Fear": ["afraid": 1, "worry": 1, "anxious": 1, "scared": 1, "overwhelm": 1],
        "Surprise": ["unexpected": 1, "sudden": 1, "shock": 1, "didn't": 1, "out_of_nowhere": 1],
        "Disgust": ["gross": 1, "disgust": 1, "repulsed": 1, "can't_stand": 1],
        "Neutral": ["note": 1, "observe": 1, "log": 1, "track": 1],
    ]

    private func termFreq(_ text: String) -> [String: Double] {
        let toks = tokenize(text)
        var tf = [String: Double]()
        for w in toks {
            tf[w, default: 0] += 1
        }
        let n = max(1, toks.count)
        for k in tf.keys {
            tf[k]! /= Double(n)
        }
        return tf
    }

    private func tokenize(_ t: String) -> [String] {
        let base = t.lowercased()
            .replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
            .replacingOccurrences(of: "can't stand", with: "can't_stand")
        return base.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
    }

    private func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let keys = Set(a.keys).union(b.keys)
        var dot = 0.0, na = 0.0, nb = 0.0
        for k in keys {
            let av = a[k] ?? 0, bv = b[k] ?? 0
            dot += av * bv
            na += av * av
            nb += bv * bv
        }
        return (na == 0 || nb == 0) ? 0 : dot / (sqrt(na) * sqrt(nb))
    }

    private func idFor(_ key: String) -> Int {
        ["Joy": 1, "Sadness": 2, "Anger": 3, "Fear": 4, "Surprise": 5, "Disgust": 6, "Neutral": 7][key] ?? 7
    }

    private func labelFor(_ id: Int) -> String {
        switch id {
        case 1: "Joy 🙂"
        case 2: "Sadness 😢"
        case 3: "Anger 😠"
        case 4: "Fear 😨"
        case 5: "Surprise 😮"
        case 6: "Disgust 🤢"
        default: "Neutral 😐"
        }
    }
}
