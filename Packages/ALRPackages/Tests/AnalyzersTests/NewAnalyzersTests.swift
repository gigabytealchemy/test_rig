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

    // Test ALR_EnginePro
    func testALREnginePro() throws {
        let analyzer = ALR_EnginePro()
        let input = AnalyzerInput(
            fullText: "I've been stressed about work deadlines and my manager keeps adding more projects.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .alr)
        XCTAssertEqual(output.name, "ALR • Engine Pro (domain-aware)")
        XCTAssertFalse(output.result.isEmpty)
        XCTAssertNotNil(output.metadata["emotionID"])
        XCTAssertNotNil(output.metadata["topDomain"])
        // Should detect Work domain
        XCTAssertTrue(output.metadata["topDomain"]?.contains("Work") ?? false)
    }

    func testALREngineProWithFamilyDomain() throws {
        let analyzer = ALR_EnginePro()
        let input = AnalyzerInput(
            fullText: "My mother called yesterday. We talked about my sister's wedding plans.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        // Should detect Family domain
        XCTAssertTrue(output.metadata["domains"]?.contains("Family") ?? false)
    }

    // Test EmotionProAnalyzer
    func testEmotionProAnalyzerJoyDetection() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "I'm so grateful and proud of what we achieved today!",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .emotion)
        XCTAssertEqual(output.name, "Emotion • Rules Pro")
        XCTAssertTrue(output.result.contains("Joy"))
        XCTAssertTrue(output.result.contains("🙂"))
        XCTAssertNotNil(output.metadata["scores"])
    }

    func testEmotionProAnalyzerFearDetection() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "I'm worried about what might happen. I'm really anxious.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Fear"))
        XCTAssertTrue(output.result.contains("😨"))
    }

    func testEmotionProAnalyzerContrastHandling() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "I was happy initially, but I'm really angry about how it ended.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        // Should prioritize emotion after "but"
        XCTAssertTrue(output.result.contains("Anger") || output.result.contains("😠"))
    }

    func testEmotionProAnalyzerMixedEmotions() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "I feel both grateful and anxious about this opportunity.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        // Should detect mixed emotions when close scores
        XCTAssertTrue(output.result.contains("Mixed") || output.result.contains("😵‍💫") ||
                     output.result.contains("Joy") || output.result.contains("Fear"))
    }

    func testEmotionProAnalyzerWithSelection() throws {
        let fullText = "The meeting went well. But I regret not calling back immediately."
        let selectedStart = fullText.firstIndex(of: "I")!
        let selectedEnd = fullText.endIndex
        let range = selectedStart ..< selectedEnd

        let input = AnalyzerInput(
            fullText: fullText,
            selectedRange: range,
            fallbackEmotion: nil
        )

        let output = try EmotionProAnalyzer().analyze(input)
        // Should analyze selected text which has regret
        XCTAssertTrue(output.result.contains("Sadness") || output.result.contains("😢") ||
                     output.result.contains("2"))
    }

    func testEmotionProAnalyzerNeutralText() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "Today I made a note about the meeting schedule.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Neutral") || output.result.contains("😐"))
    }

    func testEmotionProAnalyzerEmptyText() throws {
        let analyzer = EmotionProAnalyzer()
        let input = AnalyzerInput(
            fullText: "",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("Neutral") || output.result.contains("😐"))
    }
}
