@testable import Analyzers
@testable import CoreTypes
import XCTest

final class AnalyzersTests: XCTestCase {
    func testRuleEmotionDetectsAnger() throws {
        let input = AnalyzerInput(fullText: "I am very angry about this.")
        let out = try RuleEmotionAnalyzer().analyze(input)
        XCTAssertEqual(out.result, "anger")
        XCTAssertEqual(out.category, .emotion)
    }

    func testPromptAnalyzerUsesFallback() throws {
        let input = AnalyzerInput(fullText: "meh", fallbackEmotion: "sadness")
        let out = try PromptAnalyzer().analyze(input)
        XCTAssertEqual(out.category, .prompt)
        XCTAssertTrue(out.result.lowercased().contains("gently") || out.metadata["emotion"] == "sadness")
    }

    func testActiveListenerResponds() throws {
        let input = AnalyzerInput(fullText: "Feeling happy about the news", fallbackEmotion: "joy")
        let out = try ActiveListeningAnalyzer().analyze(input)
        XCTAssertEqual(out.category, .alr)
        XCTAssertTrue(out.result.contains("uplifted") || out.result.contains("You mentioned"))
    }

    func testTitleAnalyzerFirstSentence() throws {
        let input = AnalyzerInput(fullText: "This is the first sentence. And here is another one.")
        let out = try TitleAnalyzer().analyze(input)
        XCTAssertEqual(out.category, .title)
        XCTAssertTrue(out.result.hasPrefix("This is the first sentence"))
        XCTAssertTrue(out.result.count <= 80)
    }

    func testDefaultRegistryContainsFourAnalyzers() {
        let reg = DefaultAlgorithmRegistry()
        XCTAssertEqual(reg.analyzers.count, 4)
    }
}
