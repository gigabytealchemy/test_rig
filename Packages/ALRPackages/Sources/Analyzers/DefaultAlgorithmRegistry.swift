import CoreTypes
import Foundation

public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer]
    public init() {
        analyzers = [
            RuleEmotionAnalyzer(),
            ActiveListeningAnalyzer(),
            TitleAnalyzer(),
            PromptAnalyzer()
        ]
    }
}
