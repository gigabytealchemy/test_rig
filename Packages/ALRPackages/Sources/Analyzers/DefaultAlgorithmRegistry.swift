import CoreTypes
import Foundation

public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer]
    public init() {
        analyzers = [
            // Emotion analyzers
            RuleEmotionAnalyzer(),
            EmotionProAnalyzer(),
            
            // Domain analyzers
            DomainAnalyzer(),
            DomainProAnalyzer(),
            
            // ALR analyzers
            ActiveListeningAnalyzer(),
            ALR_EngineWrap(),
            ALR_EngineWithPatternHint(),
            ALR_EnginePro(),
            
            // Other analyzers
            TitleAnalyzer(),
            PromptAnalyzer(),
        ]
    }
}
