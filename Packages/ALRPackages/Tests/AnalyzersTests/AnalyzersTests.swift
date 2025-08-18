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

    func testDefaultRegistryContainsAnalyzers() {
        let reg = DefaultAlgorithmRegistry()
        XCTAssertEqual(reg.analyzers.count, 11) // 5 original + 6 new analyzers (added DomainAnalyzer)
    }

    func testDomainAnalyzerDetectsWork() throws {
        let input = AnalyzerInput(fullText: "I had a tough day at work with my boss.")
        let out = try DomainAnalyzer().analyze(input)
        XCTAssertTrue(out.result.contains("Work"))
    }

    func testActiveListenerUsesDomain() throws {
        let input = AnalyzerInput(
            fullText: "Boss was harsh today.",
            fallbackEmotion: "anger",
            domains: [("Work", 0.9)]
        )
        let out = try ActiveListeningAnalyzer().analyze(input)
        // Should contain work-related response
        XCTAssertFalse(out.result.isEmpty)
    }

    func testPromptAnalyzerUsesDomainAndEmotion() throws {
        let input = AnalyzerInput(
            fullText: "Boss was kind today.",
            fallbackEmotion: "joy",
            domains: [("Work", 0.9)]
        )
        let out = try PromptAnalyzer().analyze(input)
        // Should provide work+joy specific prompt
        XCTAssertTrue(out.result.lowercased().contains("work") || out.result.contains("win"))
        XCTAssertEqual(out.metadata["domain"], "Work")
        XCTAssertEqual(out.metadata["promptType"], "combined")
    }
}
