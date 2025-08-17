import Analyzers
import CoreTypes
@testable import TestRig
import XCTest

final class CoordinatorTests: XCTestCase {
    struct StubAnalyzer: Analyzer {
        let category: AlgorithmCategory
        let name: String
        let result: String
        func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
            AnalyzerOutput(category: category, name: name, result: result)
        }
    }

    struct FailingAnalyzer: Analyzer {
        let category: AlgorithmCategory = .emotion
        let name: String = "Failing"
        func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
            throw NSError(domain: "StubError", code: 1)
        }
    }

    @MainActor
    func testCoordinatorRunsStubAnalyzers() async {
        let reg = DefaultAlgorithmRegistry()
        let coord = await Coordinator(registry: reg)
        coord.text = "sample"
        // Inject stubs
        let stubs: [Analyzer] = [
            StubAnalyzer(category: .emotion, name: "Stub1", result: "joy"),
            StubAnalyzer(category: .title, name: "Stub2", result: "title"),
        ]
        let fakeReg = StubRegistry(analyzers: stubs)
        let coord2 = await Coordinator(registry: fakeReg)
        coord2.text = "sample"
        coord2.runAll()
        // Wait for completion
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(coord2.resultsByCategory[.emotion]?.first?.result, "joy")
        XCTAssertEqual(coord2.resultsByCategory[.title]?.first?.result, "title")
    }

    @MainActor
    func testCoordinatorHandlesError() async {
        let reg = StubRegistry(analyzers: [FailingAnalyzer()])
        let coord = await Coordinator(registry: reg)
        coord.text = "test"
        coord.runAll()
        // Wait for completion
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = coord.resultsByCategory[.emotion]?.first?.result ?? ""
        XCTAssertTrue(result.contains("❌"))
    }

    struct StubRegistry: AlgorithmRegistry {
        let analyzers: [Analyzer]
    }
}
