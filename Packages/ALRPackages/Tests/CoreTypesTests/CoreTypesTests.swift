@testable import CoreTypes
import XCTest

final class CoreTypesTests: XCTestCase {
    func testSelectedTextFallsBackToFullText() {
        let input = AnalyzerInput(fullText: "hello world")
        XCTAssertEqual(input.selectedText, "hello world")
    }

    func testSelectedTextRespectsRange() {
        let text = "abcdef"
        let start = text.startIndex
        let end = text.index(start, offsetBy: 3) // "abc"
        let input = AnalyzerInput(fullText: text,
                                  selectedRange: start ..< end)
        XCTAssertEqual(input.selectedText, "abc")
    }

    func testAnalyzerOutputInitialization() {
        let output = AnalyzerOutput(category: .emotion,
                                    name: "Stub",
                                    result: "joy",
                                    durationMS: 12,
                                    metadata: ["k": "v"])
        XCTAssertEqual(output.category, .emotion)
        XCTAssertEqual(output.name, "Stub")
        XCTAssertEqual(output.result, "joy")
        XCTAssertEqual(output.durationMS, 12)
        XCTAssertEqual(output.metadata["k"], "v")
    }
}
