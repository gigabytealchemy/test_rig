import CoreTypes
import Foundation

public struct ActiveListenerEngine: Sendable {
    public init() {}

    public func respond(to text: String,
                        fallbackEmotion: String?,
                        domains: [(String, Double)]? = nil) -> String
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for high-confidence domain first
        if let (domainName, score) = domains?.max(by: { $0.1 < $1.1 }), score >= 0.45 {
            if let pool = domainFallbackPools[domainName] {
                let base = pool.randomElement() ?? "That's part of your \(domainName.lowercased()) story."
                if trimmed.isEmpty {
                    return "\(base) Would you like to share more?"
                } else {
                    return base
                }
            }
        }

        // Fall back to emotion-based response
        let emotion = (fallbackEmotion?.lowercased() ?? "neutral")
        let prefix = switch emotion {
        case "joy": "It sounds like you're feeling uplifted."
        case "sadness": "It sounds like this has been heavy for you."
        case "anger": "I can hear how frustrating that was."
        default: "I'm hearing you."
        }

        if trimmed.isEmpty {
            return "\(prefix) Would you like to share a bit more?"
        } else {
            return "\(prefix) You mentioned: \"\(trimmed.prefix(140))\""
        }
    }

    // Domain-specific response pools
    private let domainFallbackPools: [String: [String]] = [
        "Work": [
            "That part of work keeps showing up for you.",
            "Your work situation sounds challenging.",
            "That's something from your professional life worth noting.",
        ],
        "Relationships": [
            "That's part of your relationship story.",
            "Relationships can bring up so much.",
            "That connection seems important to you.",
        ],
        "Family": [
            "Family can carry a lot of weight.",
            "Your family dynamics seem to be on your mind.",
            "That's part of your family story.",
        ],
        "School": [
            "School brings its own set of challenges.",
            "Your academic journey has its moments.",
            "That's part of your learning experience.",
        ],
        "Health": [
            "That's a lot for your body to hold.",
            "Health concerns can weigh heavily.",
            "Your wellbeing is important.",
        ],
        "Money": [
            "Financial matters can be stressful.",
            "That's a practical concern worth acknowledging.",
            "Money worries can take up mental space.",
        ],
        "General": [
            "That's something worth exploring.",
            "I'm here to listen to whatever you need to share.",
            "Your thoughts matter here.",
        ],
    ]
}
