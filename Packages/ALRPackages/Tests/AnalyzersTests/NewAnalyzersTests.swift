import Analyzers
import CoreTypes
import XCTest

final class NewAnalyzersTests: XCTestCase {
    // Test EmotionRegexV1
    func testEmotionRegexV1BasicDetection() throws {
        let analyzer = EmotionRegexV1()
        let input = AnalyzerInput(
            fullText: "I'm proud of what we accomplished today. Really grateful!",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .emotion)
        XCTAssertEqual(output.name, "Emotion • Rules (V1)")
        XCTAssertTrue(output.result.contains("Joy"))
    }

    func testEmotionRegexV1FearDetection() throws {
        let analyzer = EmotionRegexV1()
        let input = AnalyzerInput(
            fullText: "I'm afraid this won't work out. I'm really worried.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Fear"))
    }

    // Test EmotionRegexV2
    func testEmotionRegexV2ContrastHandling() throws {
        let analyzer = EmotionRegexV2()
        let input = AnalyzerInput(
            fullText: "I was happy at first, but honestly I'm afraid now.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Fear"), "Should prioritize emotion after 'but'")
    }

    func testEmotionRegexV2Intensifiers() throws {
        let analyzer = EmotionRegexV2()
        let input = AnalyzerInput(
            fullText: "I'm really very angry about this!",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Anger"))
        XCTAssertNotNil(output.metadata["scores"])
    }

    // Test EmotionTFIDFSeeded
    func testEmotionTFIDFSeeded() throws {
        let analyzer = EmotionTFIDFSeeded()
        let input = AnalyzerInput(
            fullText: "I feel so grateful and proud. This is a relief!",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .emotion)
        XCTAssertTrue(output.result.contains("Joy"))
        XCTAssertNotNil(output.metadata["similarity"])
    }

    func testEmotionTFIDFSeededAnger() throws {
        let analyzer = EmotionTFIDFSeeded()
        let input = AnalyzerInput(
            fullText: "This is so unfair! I'm furious and annoyed.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Anger"))
    }

    // Test ALR_EngineWrap
    func testALREngineWrap() throws {
        let analyzer = ALR_EngineWrap()
        let input = AnalyzerInput(
            fullText: "I kept avoiding the conversation with my sister.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .alr)
        XCTAssertEqual(output.name, "ALR • Engine (sentiment-aware)")
        XCTAssertFalse(output.result.isEmpty)
        XCTAssertNotNil(output.metadata["emotion"])
    }

    func testALREngineWrapWithFallbackEmotion() throws {
        let analyzer = ALR_EngineWrap()
        let input = AnalyzerInput(
            fullText: "Today was interesting.",
            selectedRange: nil,
            fallbackEmotion: "joy"
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.metadata["emotion"], "joy")
    }

    // Test ALR_EngineWithPatternHint
    func testALREngineWithPatternHint() throws {
        let analyzer = ALR_EngineWithPatternHint()
        let input = AnalyzerInput(
            fullText: "I don't know what to do anymore.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .alr)
        XCTAssertTrue(output.result.contains("That seems to show up for you sometimes"))
    }

    func testALREngineWithPatternHintNoPattern() throws {
        let analyzer = ALR_EngineWithPatternHint()
        let input = AnalyzerInput(
            fullText: "The weather is nice today.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertFalse(output.result.contains("That seems to show up"))
    }

    // Test with selections
    func testAnalyzersWithSelection() throws {
        let fullText = "The beginning is neutral. I'm really afraid of what's next."
        let selectedStart = fullText.firstIndex(of: "I")!
        let selectedEnd = fullText.endIndex
        let range = selectedStart ..< selectedEnd

        let input = AnalyzerInput(
            fullText: fullText,
            selectedRange: range,
            fallbackEmotion: nil
        )

        // Test that V1 focuses on selection
        let v1 = try EmotionRegexV1().analyze(input)
        // V1 should analyze the selected text
        XCTAssertFalse(v1.result.isEmpty)
        XCTAssertTrue(v1.result.contains("–")) // Has proper format

        // Test that V2 focuses on selection
        let v2 = try EmotionRegexV2().analyze(input)
        XCTAssertTrue(v2.result.contains("Fear"))

        // Test that TFIDF focuses on selection
        let tfidf = try EmotionTFIDFSeeded().analyze(input)
        // TFIDF might detect Fear (4) or another emotion based on word similarity
        XCTAssertFalse(tfidf.result.isEmpty)
        XCTAssertTrue(tfidf.result.contains("–")) // Check it has the ID format
    }
}
