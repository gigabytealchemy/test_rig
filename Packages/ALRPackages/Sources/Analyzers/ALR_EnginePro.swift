import CoreTypes
import Foundation

public struct ALR_EnginePro: Analyzer {
    public let category: AlgorithmCategory = .alr
    public let name: String = "ALR • Engine Pro (domain-aware)"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText

        // Get emotion ID (1-8) either from fallback or by detecting
        let emotionID = mapEmotionString(input.fallbackEmotion)
            ?? inferEmotionID(text)

        // Analyze domains from the text
        let domains = analyzeDomains(text)

        // Call the Pro engine
        let reply = ActiveListenerEnginePro.shared.respond(
            to: text,
            emotion: emotionID,
            domains: domains
        ) ?? "I'm here, listening."

        // Build metadata
        var metadata: [String: String] = [
            "emotionID": "\(emotionID)",
            "emotion": emotionStringFor(emotionID),
        ]

        if !domains.isEmpty {
            let topDomain = domains.max(by: { $0.1 < $1.1 })
            metadata["topDomain"] = topDomain.map { "\($0.0): \(String(format: "%.2f", $0.1))" }
            metadata["domains"] = domains.map { "\($0.0):\(String(format: "%.2f", $0.1))" }.joined(separator: ", ")
        }

        return AnalyzerOutput(
            category: category,
            name: name,
            result: reply,
            metadata: metadata
        )
    }

    private func mapEmotionString(_ s: String?) -> Int? {
        guard let s else { return nil }
        let key = s.lowercased()
        let map: [String: Int] = [
            "joy": 1, "happy": 1, "happiness": 1,
            "sad": 2, "sadness": 2,
            "anger": 3, "angry": 3,
            "fear": 4, "anxiety": 4, "anxious": 4,
            "surprise": 5, "surprised": 5,
            "disgust": 6, "disgusted": 6,
            "neutral": 7,
            "mixed": 8,
        ]
        return map[key]
    }

    private func inferEmotionID(_ text: String) -> Int {
        // Use EmotionRegexV2 for emotion detection
        EmotionRegexV2().quickID(text)
    }

    private func emotionStringFor(_ id: Int) -> String {
        switch id {
        case 1: "joy"
        case 2: "sadness"
        case 3: "anger"
        case 4: "fear"
        case 5: "surprise"
        case 6: "disgust"
        case 8: "mixed"
        default: "neutral"
        }
    }

    private func analyzeDomains(_ text: String) -> [(String, Double)] {
        let lower = text.lowercased()
        var scores: [String: Double] = [:]

        // Work domain keywords
        let workKeywords = ["work", "job", "boss", "manager", "colleague", "office", "meeting",
                            "deadline", "project", "career", "promotion", "salary", "coworker",
                            "task", "assignment", "client", "customer", "business"]
        scores["Work"] = calculateDomainScore(text: lower, keywords: workKeywords)

        // Family domain keywords
        let familyKeywords = ["family", "mother", "father", "mom", "dad", "parent", "sibling",
                              "brother", "sister", "son", "daughter", "child", "children",
                              "aunt", "uncle", "cousin", "grandparent", "grandmother", "grandfather"]
        scores["Family"] = calculateDomainScore(text: lower, keywords: familyKeywords)

        // Relationships domain keywords
        let relationshipKeywords = ["partner", "spouse", "husband", "wife", "boyfriend", "girlfriend",
                                    "friend", "relationship", "dating", "marriage", "divorce",
                                    "breakup", "love", "romantic", "intimacy"]
        scores["Relationships"] = calculateDomainScore(text: lower, keywords: relationshipKeywords)

        // Health domain keywords
        let healthKeywords = ["health", "doctor", "hospital", "sick", "illness", "symptom",
                              "medicine", "medication", "pain", "surgery", "diagnosis",
                              "therapy", "treatment", "wellness", "exercise", "fitness"]
        scores["Health"] = calculateDomainScore(text: lower, keywords: healthKeywords)

        // Money domain keywords
        let moneyKeywords = ["money", "financial", "budget", "expense", "income", "debt",
                             "loan", "mortgage", "rent", "bills", "savings", "investment",
                             "bank", "credit", "payment", "cost", "price"]
        scores["Money"] = calculateDomainScore(text: lower, keywords: moneyKeywords)

        // Sleep domain keywords
        let sleepKeywords = ["sleep", "insomnia", "tired", "exhausted", "rest", "nap",
                             "fatigue", "awake", "dream", "nightmare", "bedtime"]
        scores["Sleep"] = calculateDomainScore(text: lower, keywords: sleepKeywords)

        // Creativity domain keywords
        let creativityKeywords = ["creative", "art", "music", "writing", "painting", "drawing",
                                  "design", "imagination", "inspiration", "project", "craft",
                                  "poetry", "novel", "story", "compose"]
        scores["Creativity"] = calculateDomainScore(text: lower, keywords: creativityKeywords)

        // Filter and sort domains by score
        let validDomains = scores.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }

        return Array(validDomains.prefix(3)) // Return top 3 domains
    }

    private func calculateDomainScore(text: String, keywords: [String]) -> Double {
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return 0 }

        var matches = 0
        var weightedScore = 0.0

        for keyword in keywords {
            if text.contains(keyword) {
                matches += 1
                // Give more weight to longer, more specific keywords
                weightedScore += Double(keyword.count) / 10.0
            }
        }

        // Normalize score between 0 and 1
        let baseScore = Double(matches) / Double(keywords.count)
        let lengthBonus = min(0.3, weightedScore / Double(keywords.count))
        let finalScore = min(1.0, baseScore + lengthBonus)

        return finalScore
    }
}
