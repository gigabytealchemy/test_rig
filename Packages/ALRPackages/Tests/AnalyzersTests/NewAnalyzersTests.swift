import Analyzers
import CoreTypes
import XCTest

final class NewAnalyzersTests: XCTestCase {
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

    // Test DomainProAnalyzer
    func testDomainProAnalyzerWorkAndExercise() throws {
        let analyzer = DomainProAnalyzer()
        let input = AnalyzerInput(
            fullText: "Ran before work this morning, then had a tough meeting with my boss.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertEqual(output.category, .domains)
        XCTAssertEqual(output.name, "Domain • Rules Pro")
        // Should detect both Exercise/Fitness and Work/Career
        XCTAssertNotNil(output.metadata["ranked"])
        XCTAssertTrue(output.metadata["ranked"]?.contains("Exercise/Fitness") ?? false)
        XCTAssertTrue(output.metadata["ranked"]?.contains("Work/Career") ?? false)
    }

    func testDomainProAnalyzerFamilyAndFood() throws {
        let analyzer = DomainProAnalyzer()
        let input = AnalyzerInput(
            fullText: "Had dinner with my sister and mom last night at a nice restaurant.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        // Should detect Family and Food/Eating
        XCTAssertTrue(output.result.contains("Family") || output.result.contains("Food"))
        XCTAssertTrue(output.metadata["ranked"]?.contains("Family") ?? false)
        XCTAssertTrue(output.metadata["ranked"]?.contains("Food/Eating") ?? false)
    }

    func testDomainProAnalyzerHealthAndSleep() throws {
        let analyzer = DomainProAnalyzer()
        let input = AnalyzerInput(
            fullText: "Couldn't sleep again. Doctor said my insomnia might be stress-related.",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        // Should detect Sleep/Rest and Health/Medical
        XCTAssertTrue(output.metadata["ranked"]?.contains("Sleep/Rest") ?? false)
        XCTAssertTrue(output.metadata["ranked"]?.contains("Health/Medical") ?? false)
    }

    func testDomainProAnalyzerWithSelection() throws {
        let fullText = "Worked all day. Later went to the gym and did a great workout."
        let selectedStart = fullText.firstIndex(of: "L")!
        let selectedEnd = fullText.endIndex
        let range = selectedStart ..< selectedEnd
        
        let input = AnalyzerInput(
            fullText: fullText,
            selectedRange: range,
            fallbackEmotion: nil
        )

        let output = try DomainProAnalyzer().analyze(input)
        // Selected text focuses on gym/workout, should prioritize Exercise/Fitness
        XCTAssertTrue(output.result.contains("Exercise") || output.result.contains("Fitness"))
    }

    func testDomainProAnalyzerEmptyText() throws {
        let analyzer = DomainProAnalyzer()
        let input = AnalyzerInput(
            fullText: "",
            selectedRange: nil,
            fallbackEmotion: nil
        )

        let output = try analyzer.analyze(input)
        XCTAssertTrue(output.result.contains("General") || output.result.contains("Other"))
    }
}
