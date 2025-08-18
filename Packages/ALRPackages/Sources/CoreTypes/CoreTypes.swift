import Foundation

public enum AlgorithmCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case emotion, alr, title, prompt, domains
}

public struct DomainScore: Codable, Sendable {
    public let name: String
    public let score: Double

    public init(name: String, score: Double) {
        self.name = name
        self.score = score
    }
}

public struct AnalyzerInput: Sendable, Codable {
    public let fullText: String
    public let selectedRangeStart: Int?
    public let selectedRangeEnd: Int?
    public let fallbackEmotion: String?
    public let domains: [DomainScore]?

    public init(fullText: String,
                selectedRange: Range<String.Index>? = nil,
                fallbackEmotion: String? = nil,
                domains: [(name: String, score: Double)]? = nil)
    {
        self.fullText = fullText
        if let range = selectedRange {
            let startOffset = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
            let endOffset = fullText.distance(from: fullText.startIndex, to: range.upperBound)
            selectedRangeStart = startOffset
            selectedRangeEnd = endOffset
        } else {
            selectedRangeStart = nil
            selectedRangeEnd = nil
        }
        self.fallbackEmotion = fallbackEmotion
        self.domains = domains?.map { DomainScore(name: $0.name, score: $0.score) }
    }

    public var selectedRange: Range<String.Index>? {
        guard let start = selectedRangeStart, let end = selectedRangeEnd else { return nil }
        let startIndex = fullText.index(fullText.startIndex, offsetBy: start)
        let endIndex = fullText.index(fullText.startIndex, offsetBy: end)
        return startIndex ..< endIndex
    }

    public var selectedText: String {
        guard let r = selectedRange else { return fullText }
        return String(fullText[r])
    }

    public var domainTuples: [(name: String, score: Double)]? {
        domains?.map { ($0.name, $0.score) }
    }
}

public struct AnalyzerOutput: Sendable, Codable, Identifiable {
    public let id: UUID
    public let category: AlgorithmCategory
    public let name: String
    public let result: String
    public let durationMS: Int
    public let metadata: [String: String]

    public init(category: AlgorithmCategory,
                name: String,
                result: String,
                durationMS: Int = 0,
                metadata: [String: String] = [:])
    {
        id = UUID()
        self.category = category
        self.name = name
        self.result = result
        self.durationMS = durationMS
        self.metadata = metadata
    }
}
