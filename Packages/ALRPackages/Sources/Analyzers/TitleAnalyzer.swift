import CoreTypes
import Foundation

public struct TitleAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .title
    public let name: String = "Regex+FirstSentence"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let s = input.selectedText
        let first = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first
        let title = (first.map { String($0) } ?? s)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(title.prefix(80))
        return AnalyzerOutput(category: .title, name: name, result: clipped, durationMS: 0, metadata: [:])
    }
}
