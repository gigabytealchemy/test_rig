import CoreTypes
import Foundation

public protocol Analyzer: Sendable {
    var category: AlgorithmCategory { get }
    var name: String { get }
    func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput
}

public protocol AlgorithmRegistry {
    var analyzers: [Analyzer] { get }
}
