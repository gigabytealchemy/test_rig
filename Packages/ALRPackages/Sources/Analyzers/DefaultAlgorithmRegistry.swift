import CoreTypes
import Foundation

public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer]
    public init() {
        // Empty for Step 1; we'll populate in Step 8
        analyzers = []
    }
}
