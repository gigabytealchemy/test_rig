import CoreTypes
import Foundation

public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer]
    public init() {
        analyzers = [
            // Original analyzers
            RuleEmotionAnalyzer(),
            DomainAnalyzer(),
            ActiveListeningAnalyzer(),
            TitleAnalyzer(),
            PromptAnalyzer(),

            // Emotion analyzer
            EmotionProAnalyzer(),

            // New ALR analyzers
            ALR_EngineWrap(),
            ALR_EngineWithPatternHint(),
            ALR_EnginePro(),
        ]
    }
}
