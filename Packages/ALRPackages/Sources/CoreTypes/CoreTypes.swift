import Foundation

public enum AlgorithmCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case emotion, alr, title, prompt
}

public struct AnalyzerInput: Sendable, Codable {
    public let fullText: String
    public let selectedRangeStart: Int?
    public let selectedRangeEnd: Int?
    public let fallbackEmotion: String?

    public init(fullText: String,
                selectedRange: Range<String.Index>? = nil,
                fallbackEmotion: String? = nil) {
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
                metadata: [String: String] = [:]) {
        id = UUID()
        self.category = category
        self.name = name
        self.result = result
        self.durationMS = durationMS
        self.metadata = metadata
    }
}
