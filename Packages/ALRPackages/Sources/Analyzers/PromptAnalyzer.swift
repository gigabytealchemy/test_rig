import CoreTypes
import Foundation

public struct PromptAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .prompt
    public let name: String = "BankedPrompts"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let emotion = (input.fallbackEmotion ?? "neutral").lowercased()

        // Check for high-confidence domain
        let topDomain = input.domainTuples?.max(by: { $0.score < $1.score })
        let domainName = (topDomain?.score ?? 0) >= 0.45 ? topDomain?.name : nil

        // Combined domain+emotion prompts
        let combinedBank: [String: String] = [
            // Work + emotions
            "Work+joy": "Celebrate a work win today - what made it possible?",
            "Work+sadness": "What's one work challenge that's weighing on you? How might you lighten it?",
            "Work+anger": "Identify the work situation that frustrated you and one way to address it.",
            "Work+neutral": "Document today's work progress - what moved forward?",

            // Relationships + emotions
            "Relationships+joy": "What moment with your partner brought you happiness today?",
            "Relationships+sadness": "What do you wish was different in your relationship right now?",
            "Relationships+anger": "What boundary do you need to communicate in your relationship?",
            "Relationships+neutral": "Describe a small interaction with your partner today.",

            // Family + emotions
            "Family+joy": "What family moment made you smile today?",
            "Family+sadness": "What family dynamic is hard to navigate right now?",
            "Family+anger": "What family pattern frustrates you? How might you respond differently?",
            "Family+neutral": "Capture a routine family moment from today.",

            // School + emotions
            "School+joy": "What academic achievement are you proud of today?",
            "School+sadness": "What's challenging about your studies right now?",
            "School+anger": "What school situation needs your assertiveness?",
            "School+neutral": "Document what you learned today, even if small.",

            // Health + emotions
            "Health+joy": "What health progress can you celebrate?",
            "Health+sadness": "What health concern needs gentle attention?",
            "Health+anger": "What health frustration needs acknowledgment?",
            "Health+neutral": "Note how your body felt at different times today.",

            // Money + emotions
            "Money+joy": "What financial decision are you proud of?",
            "Money+sadness": "What money worry needs acknowledgment?",
            "Money+anger": "What financial boundary do you need to set?",
            "Money+neutral": "Track one financial decision you made today.",
        ]

        // Single emotion prompts (fallback)
        let emotionBank: [String: String] = [
            "joy": "Write a gratitude note focusing on a highlight from today.",
            "sadness": "Gently explore what you needed today but didn't get.",
            "anger": "List the triggers and one boundary you can set next time.",
            "fear": "Name what you're afraid of and one small step toward safety.",
            "surprise": "What unexpected moment stood out today?",
            "disgust": "What didn't sit right with you today?",
            "neutral": "Pick one sentence to expand with sensory detail.",
            "mixed": "Sort through the different feelings - name each one.",
        ]

        // Select prompt based on domain+emotion or just emotion
        let prompt: String
        var metadata: [String: String] = ["emotion": emotion]

        if let domain = domainName {
            let combinedKey = "\(domain)+\(emotion)"
            metadata["domain"] = domain
            metadata["promptType"] = "combined"
            prompt = combinedBank[combinedKey]
                ?? emotionBank[emotion]
                ?? "Reflect on a small action you can take next."
        } else {
            metadata["promptType"] = "emotion"
            prompt = emotionBank[emotion]
                ?? "Reflect on a small action you can take next."
        }

        return AnalyzerOutput(
            category: .prompt,
            name: name,
            result: prompt,
            durationMS: 0,
            metadata: metadata
        )
    }
}
