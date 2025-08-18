import Analyzers
import CoreTypes
@testable import TestRig
import XCTest

final class CoordinatorRobustnessTests: XCTestCase {
    struct FastAnalyzer: Analyzer {
        let category: AlgorithmCategory
        let name: String
        let result: String

        func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
            AnalyzerOutput(category: category, name: name, result: result)
        }
    }

    struct ErrorAnalyzer: Analyzer {
        let category: AlgorithmCategory = .title
        let name: String = "Erroring"
        func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
            throw NSError(domain: "Test", code: 42,
                          userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
    }

    struct StubRegistry: AlgorithmRegistry {
        let analyzers: [Analyzer]
    }

    @MainActor
    func testErrorSurfacesInResult() async {
        let reg = StubRegistry(analyzers: [ErrorAnalyzer()])
        let coord = Coordinator(registry: reg)
        coord.text = "hello"
        coord.runAll(timeoutPerAnalyzer: .seconds(2))

        // Wait briefly for the error to be processed
        try? await Task.sleep(for: .milliseconds(100))

        let result = coord.resultsByCategory[.title]?.first?.result ?? ""
        XCTAssertTrue(result.hasPrefix("❌"), "Expected ❌ prefix on error")
        XCTAssertTrue(result.contains("boom"), "Expected error message in result")
    }

    @MainActor
    func testGroupingMultipleAnalyzers() async {
        let reg = StubRegistry(analyzers: [
            FastAnalyzer(category: .emotion, name: "Fast1", result: "emotion-result"),
            FastAnalyzer(category: .title, name: "Fast2", result: "title-result"),
            FastAnalyzer(category: .emotion, name: "Fast3", result: "emotion-result-2"),
            ErrorAnalyzer(),
        ])
        let coord = Coordinator(registry: reg)
        coord.text = "hello"
        coord.runAll(timeoutPerAnalyzer: .seconds(1))

        // Wait for analyzers to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Verify grouping works correctly
        XCTAssertNotNil(coord.resultsByCategory[.emotion], "Expected emotion category results")
        XCTAssertNotNil(coord.resultsByCategory[.title], "Expected title category results")

        // Verify multiple results per category
        let emotionResults = coord.resultsByCategory[.emotion] ?? []
        XCTAssertEqual(emotionResults.count, 2, "Expected 2 emotion analyzers")

        let titleResults = coord.resultsByCategory[.title] ?? []
        XCTAssertEqual(titleResults.count, 2, "Expected 2 title analyzers (1 success, 1 error)")

        // Verify error analyzer shows error
        let hasError = titleResults.contains { $0.result.hasPrefix("❌") }
        XCTAssertTrue(hasError, "Expected at least one error result in title category")
    }

    @MainActor
    func testLoggingOccurs() async {
        // This test verifies that logging methods are called (no assertions, just coverage)
        let reg = StubRegistry(analyzers: [
            FastAnalyzer(category: .emotion, name: "Logger", result: "log-test"),
        ])
        let coord = Coordinator(registry: reg)
        coord.text = "test"

        // Run and cancel to test both log paths
        coord.runAll()
        try? await Task.sleep(for: .milliseconds(50))
        coord.cancel()

        // No assertions needed - just verifying code paths for coverage
    }
}
