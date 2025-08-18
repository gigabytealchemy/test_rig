import CoreTypes
import Foundation

public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer]
    public init() {
        analyzers = [
            // Original analyzers
            RuleEmotionAnalyzer(),
            ActiveListeningAnalyzer(),
            TitleAnalyzer(),
            PromptAnalyzer(),

            // New emotion analyzers
            EmotionRegexV1(),
            EmotionRegexV2(),
            EmotionTFIDFSeeded(),

            // New ALR analyzers
            ALR_EngineWrap(),
            ALR_EngineWithPatternHint(),
            ALR_EnginePro(),
        ]
    }
}
