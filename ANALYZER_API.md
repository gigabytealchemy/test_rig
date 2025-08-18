# Analyzer API Documentation

## Overview

The TestRig analyzer system provides a flexible, concurrent framework for text analysis algorithms. Analyzers are independent, composable units that process text input and produce categorized results.

## Core Concepts

### 1. Algorithm Categories

Analyzers are grouped into five primary categories:

```swift
public enum AlgorithmCategory: String, Codable, Sendable, CaseIterable {
    case emotion
    case alr  // Active Listening Response
    case title
    case prompt
    case domains
}
```

### 2. Data Flow

```
Text Input → AnalyzerInput → Analyzer → AnalyzerOutput → UI Display
```

## Core Types

### AnalyzerInput

The input structure passed to all analyzers:

```swift
public struct AnalyzerInput: Sendable, Codable {
    public let fullText: String                      // Complete text content
    public let selectedRange: Range<String.Index>?   // Optional text selection
    public let fallbackEmotion: String?              // Optional emotion context
    public let domains: [DomainScore]?               // Optional domain classifications
}
```

**Key Properties:**
- `fullText`: The complete text to analyze
- `selectedRange`: Optional user-selected text range for focused analysis
- `fallbackEmotion`: Optional emotion context for emotion-dependent analyzers
- `domains`: Optional array of domain classifications with confidence scores
- `selectedText`: Computed property returning the selected text substring
- `domainTuples`: Computed property converting domains to tuples for easier access

### DomainScore

Domain classification with confidence score:

```swift
public struct DomainScore: Codable, Sendable {
    public let name: String    // Domain name (e.g., "Work", "Family")
    public let score: Double   // Confidence score (0.0 to 1.0)
}
```

### AnalyzerOutput

The result structure returned by analyzers:

```swift
public struct AnalyzerOutput: Sendable, Codable {
    public let category: AlgorithmCategory  // Category for grouping
    public let name: String                 // Analyzer display name
    public let result: String               // Primary result text
    public var durationMS: Int = 0         // Execution time (set by Coordinator)
    public var metadata: [String: String] = [:]  // Additional key-value data
}
```

**Key Properties:**
- `result`: Main output text (supports markdown formatting)
- `metadata`: Optional dictionary for supplementary data
- `durationMS`: Automatically populated by the Coordinator

## Analyzer Protocol

### Basic Definition

```swift
public protocol Analyzer: Sendable {
    var category: AlgorithmCategory { get }
    var name: String { get }
    func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput
}
```

### Protocol Requirements

1. **category**: The algorithm category for UI grouping
2. **name**: Display name shown in the results dashboard
3. **analyze(_:)**: Core analysis function that processes input

### Implementation Guidelines

- **Thread Safety**: Analyzers must be `Sendable` for concurrent execution
- **Error Handling**: Throw errors for invalid input or processing failures
- **Timeouts**: Default 3-second timeout per analyzer (configurable)
- **Stateless**: Analyzers should be stateless; use input/output for all data

## Current Analyzers

The TestRig currently includes 11 analyzers:

### Emotion Analyzers
1. **RuleEmotionAnalyzer** - Rule-based emotion detection
2. **EmotionRegexV1** - Simple keyword/pattern scoring
3. **EmotionRegexV2** - Enhanced with negation and intensifiers
4. **EmotionTFIDFSeeded** - TF-IDF based emotion detection

### Active Listening Response Analyzers
5. **ActiveListeningAnalyzer** - Domain-aware active listening
6. **ALR_EngineWrap** - Sentiment-aware engine wrapper
7. **ALR_EngineWithPatternHint** - Pattern-based hints
8. **ALR_EnginePro** - Production-level with 120+ rules

### Other Analyzers
9. **TitleAnalyzer** - Extract title from text
10. **PromptAnalyzer** - Domain+emotion aware prompts
11. **DomainAnalyzer** - Detect text domains

## Creating a New Analyzer

### Step 1: Create the Analyzer File

Create a new file in `Packages/ALRPackages/Sources/Analyzers/`:

```swift
// YourAnalyzer.swift
import CoreTypes
import Foundation

public struct YourAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .emotion // Choose appropriate category
    public let name: String = "Your Analyzer"
    
    public init() {}
    
    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        // Your analysis logic here
        let result = processText(input.fullText)
        
        return AnalyzerOutput(
            category: category,
            name: name,
            result: result,
            metadata: ["key": "value"] // Optional metadata
        )
    }
    
    private func processText(_ text: String) -> String {
        // Implementation details
        return "Analysis result"
    }
}
```

### Step 2: Register with DefaultAlgorithmRegistry

Add your analyzer to `Packages/ALRPackages/Sources/Analyzers/DefaultAlgorithmRegistry.swift`:

```swift
public struct DefaultAlgorithmRegistry: AlgorithmRegistry {
    public let analyzers: [Analyzer] = [
        // Emotion analyzers
        RuleEmotionAnalyzer(),
        EmotionRegexV1(),
        EmotionRegexV2(),
        EmotionTFIDFSeeded(),
        
        // Active Listening Response analyzers
        ActiveListeningAnalyzer(),
        ALR_EngineWrap(),
        ALR_EngineWithPatternHint(),
        ALR_EnginePro(),
        
        // Other analyzers
        TitleAnalyzer(),
        PromptAnalyzer(),
        DomainAnalyzer(),
        
        YourAnalyzer() // Add your analyzer here
    ]
    
    public init() {}
}
```

### Step 3: Add Tests

Create tests in `Packages/ALRPackages/Tests/AnalyzersTests/`:

```swift
func testYourAnalyzer() throws {
    let analyzer = YourAnalyzer()
    let input = AnalyzerInput(
        fullText: "Test text",
        selectedRange: nil,
        fallbackEmotion: nil,
        domains: nil
    )
    
    let output = try analyzer.analyze(input)
    XCTAssertEqual(output.category, .emotion)
    XCTAssertEqual(output.name, "Your Analyzer")
    XCTAssertFalse(output.result.isEmpty)
}
```

## Example Analyzers

### 1. Simple Pattern Analyzer

```swift
public struct KeywordAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .prompt
    public let name: String = "Keywords"
    
    public init() {}
    
    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let keywords = extractKeywords(from: input.fullText)
        let result = keywords.joined(separator: ", ")
        
        return AnalyzerOutput(
            category: category,
            name: name,
            result: result,
            metadata: ["count": "\(keywords.count)"]
        )
    }
    
    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return Array(Set(words.filter { $0.count > 5 })).prefix(10).sorted()
    }
}
```

### 2. Selection-Aware Analyzer

```swift
public struct SelectionAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .activeListening
    public let name: String = "Selection Focus"
    
    public init() {}
    
    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let textToAnalyze: String
        
        if let range = input.selectedRange {
            textToAnalyze = String(input.fullText[range])
        } else {
            textToAnalyze = input.fullText
        }
        
        let wordCount = textToAnalyze.split(separator: " ").count
        let result = "Analyzing \(wordCount) words"
        
        return AnalyzerOutput(
            category: category,
            name: name,
            result: result,
            metadata: [
                "hasSelection": "\(input.selectedRange != nil)",
                "wordCount": "\(wordCount)"
            ]
        )
    }
}
```

### 3. Domain-Aware Analyzer

```swift
public struct DomainAwareAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .prompt
    public let name: String = "Domain Aware"
    
    public init() {}
    
    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        // Check for high-confidence domain
        let topDomain = input.domainTuples?.max(by: { $0.score < $1.score })
        let domainName = (topDomain?.score ?? 0) >= 0.45 ? topDomain?.name : nil
        
        let emotion = input.fallbackEmotion ?? "neutral"
        
        var result: String
        var metadata: [String: String] = ["emotion": emotion]
        
        if let domain = domainName {
            result = "Analyzing \(domain) content with \(emotion) tone"
            metadata["domain"] = domain
            metadata["confidence"] = String(format: "%.2f", topDomain?.score ?? 0)
        } else {
            result = "General analysis with \(emotion) tone"
        }
        
        return AnalyzerOutput(
            category: category,
            name: name,
            result: result,
            metadata: metadata
        )
    }
}
```

### 4. Async/Throwing Analyzer

```swift
public struct ValidationAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .prompt
    public let name: String = "Validator"
    
    public init() {}
    
    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        // Validation that can throw
        guard !input.fullText.isEmpty else {
            throw AnalyzerError.emptyInput
        }
        
        guard input.fullText.count >= 10 else {
            throw AnalyzerError.textTooShort(minimum: 10)
        }
        
        let result = "✓ Valid input: \(input.fullText.count) characters"
        
        return AnalyzerOutput(
            category: category,
            name: name,
            result: result
        )
    }
}

enum AnalyzerError: LocalizedError {
    case emptyInput
    case textTooShort(minimum: Int)
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Input text cannot be empty"
        case .textTooShort(let min):
            return "Text must be at least \(min) characters"
        }
    }
}
```

## Advanced Features

### Using Metadata

Metadata provides additional context without cluttering the main result:

```swift
return AnalyzerOutput(
    category: category,
    name: name,
    result: "Main result text",
    metadata: [
        "confidence": "0.95",
        "method": "statistical",
        "version": "1.0",
        "debug": "Additional details for developers"
    ]
)
```

### Result Formatting

Results support markdown formatting:

```swift
let result = """
**Bold text** for emphasis
*Italic text* for subtlety
`code` for technical terms

- Bullet points
- For lists

> Blockquotes for important notes
"""
```

### Error Handling

The Coordinator automatically handles errors:
- Errors are prefixed with "❌" in the UI
- Timeouts show "⏱️ Timed out"
- Error messages are extracted from `localizedDescription`

### Performance Considerations

1. **Timeout**: Default 3-second timeout per analyzer
2. **Concurrency**: All analyzers run concurrently via TaskGroup
3. **Cancellation**: Users can cancel all running analyzers
4. **Memory**: Keep analyzer state minimal; use input/output for data

## Testing Guidelines

### Unit Test Template

```swift
final class YourAnalyzerTests: XCTestCase {
    func testBasicAnalysis() throws {
        let analyzer = YourAnalyzer()
        let input = AnalyzerInput(
            fullText: "Sample text for testing",
            selectedRange: nil,
            fallbackEmotion: nil
        )
        
        let output = try analyzer.analyze(input)
        
        XCTAssertEqual(output.category, .expectedCategory)
        XCTAssertEqual(output.name, "Expected Name")
        XCTAssertTrue(output.result.contains("expected"))
    }
    
    func testWithSelection() throws {
        let text = "The quick brown fox jumps"
        let analyzer = YourAnalyzer()
        
        // Create selection range for "quick brown"
        let start = text.firstIndex(of: "q")!
        let end = text.firstIndex(of: "f")!
        let range = start..<end
        
        let input = AnalyzerInput(
            fullText: text,
            selectedRange: range,
            fallbackEmotion: nil,
            domains: [("General", 0.5)]
        )
        
        let output = try analyzer.analyze(input)
        // Assert on selection-specific behavior
    }
    
    func testErrorConditions() {
        let analyzer = YourAnalyzer()
        let input = AnalyzerInput(
            fullText: "", // Invalid input
            selectedRange: nil,
            fallbackEmotion: nil,
            domains: nil
        )
        
        XCTAssertThrows(try analyzer.analyze(input))
    }
}
```

## Integration Workflow

1. **Development**: Create analyzer in `Analyzers/` directory
2. **Registration**: Add to `DefaultAlgorithmRegistry`
3. **Testing**: Write comprehensive unit tests
4. **Build**: Run `xcodebuild` to ensure compilation
5. **Lint**: Run `swiftlint` and `swiftformat`
6. **Coverage**: Ensure tests maintain coverage threshold
7. **UI Testing**: Launch app and verify analyzer appears in correct category

## Debugging Tips

1. **Logging**: The Coordinator logs analyzer execution times
2. **Metadata**: Use metadata dictionary for debug information
3. **Error Messages**: Provide clear, actionable error descriptions
4. **Test Isolation**: Test analyzers independently before integration

## Best Practices

1. **Single Responsibility**: Each analyzer should focus on one analysis type
2. **Predictable Output**: Consistent result format for similar inputs
3. **Graceful Degradation**: Handle edge cases without crashing
4. **Performance**: Keep analysis under 1 second for typical input
5. **Documentation**: Comment complex algorithms and edge cases
6. **Naming**: Use descriptive names that explain the analysis purpose

## FAQ

**Q: Can analyzers maintain state between runs?**
A: No, analyzers should be stateless. Use input/output for all data transfer.

**Q: How do I add a new category?**
A: Add a new case to `AlgorithmCategory` enum in `CoreTypes.swift`. The UI will automatically create a new section.

**Q: How do domains work?**
A: The DomainAnalyzer detects domains (Work, Family, Relationships, Health, Money, School) and passes them to other analyzers via the `domains` field in AnalyzerInput. Domain-aware analyzers can adjust their responses based on the detected domain.

**Q: Can analyzers call other analyzers?**
A: Not directly. Each analyzer should be independent. Share common logic via utility functions.

**Q: What's the maximum execution time?**
A: Default timeout is 3 seconds, configurable via `runAll(timeoutPerAnalyzer:)`.

**Q: Can I use external libraries?**
A: No external runtime dependencies are allowed. Use only Swift standard library and Foundation.

**Q: How do I disable an analyzer temporarily?**
A: Comment it out in `DefaultAlgorithmRegistry.analyzers` array.

## Support

For questions or issues:
- Check existing analyzers in `Packages/ALRPackages/Sources/Analyzers/`
- Review test examples in `Packages/ALRPackages/Tests/AnalyzersTests/`
- Ensure your analyzer conforms to `Analyzer` protocol and is `Sendable`