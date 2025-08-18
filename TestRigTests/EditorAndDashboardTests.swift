import Analyzers
import CoreTypes
@testable import TestRig
import XCTest

final class EditorAndDashboardTests: XCTestCase {
    func testSelectableTextEditorSelection() {
        let text = "abcdef"
        let start = text.startIndex
        let end = text.index(start, offsetBy: 3)
        let input = AnalyzerInput(fullText: text, selectedRange: start ..< end)
        XCTAssertEqual(input.selectedText, "abc")
    }

    @MainActor
    func testDashboardPlaceholderWhenNoResults() {
        let coord = Coordinator(registry: StubRegistry(analyzers: []))
        coord.text = "hello"
        XCTAssertTrue(coord.resultsByCategory.values.allSatisfy(\.isEmpty))
    }

    struct StubRegistry: AlgorithmRegistry {
        let analyzers: [Analyzer]
    }
}
