import CoreTypes
import Foundation

public struct ActiveListeningAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .alr
    public let name: String = "ActiveListener"
    private let engine: ActiveListenerEngine

    public init(engine: ActiveListenerEngine = .init()) {
        self.engine = engine
    }

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let reply = engine.respond(
            to: input.selectedText,
            fallbackEmotion: input.fallbackEmotion,
            domains: input.domainTuples
        )
        return AnalyzerOutput(
            category: .alr,
            name: name,
            result: reply,
            durationMS: 0,
            metadata: [:]
        )
    }
}
