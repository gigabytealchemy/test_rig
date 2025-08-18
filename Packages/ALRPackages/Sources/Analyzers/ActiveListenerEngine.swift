import CoreTypes
import Foundation

public struct ActiveListenerEngine {
    public init() {}

    public func respond(to text: String, fallbackEmotion: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
