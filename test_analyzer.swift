import Analyzers
import CoreTypes

let fullText = "The beginning is neutral. I'm really afraid of what's next."
let selectedStart = fullText.firstIndex(of: "I")!
let selectedEnd = fullText.endIndex
let range = selectedStart ..< selectedEnd

let input = AnalyzerInput(
    fullText: fullText,
    selectedRange: range,
    fallbackEmotion: nil
)

print("Full text: \(fullText)")
print("Selected text: \(String(fullText[range]))")

let v1 = try EmotionRegexV1().analyze(input)
print("V1 result: \(v1.result)")

let v2 = try EmotionRegexV2().analyze(input)
print("V2 result: \(v2.result)")
