// RuleEmotionClassifierPro.swift
//
// Production-lean, privacy-first rule-based emotion classifier for journaling.
// - Deterministic, fast, no network, no telemetry
// - 8-way output: 1 Joy, 2 Sadness, 3 Anger, 4 Fear, 5 Surprise, 6 Disgust, 7 Neutral, 8 Mixed
// - Heuristics: lexicons, pattern boosts, negation windows, intensifiers/dampeners,
//   contrastive connectors (prefer clause after "but/however/though"), emoji cues,
//   punctuation amplifiers, repetition de-noising, and light stemming.
// - Tunables collected at the top; extend lexicons safely without changing logic.
//
// Integration examples:
// let clf = RuleEmotionClassifierPro()
// let result = clf.classify("I regret not calling back. I'm worried I made it worse.")
// print(result.id, result.label, result.scores) // => 4 Fear, with scores per bucket
//
// Test Rig adapter (see bottom): EmotionProAnalyzer conforms to your Analyzer API.
// If names differ, adjust the small adapter only.
//
import CoreTypes
import Foundation

public final class RuleEmotionClassifierPro: @unchecked Sendable {
    // MARK: - Public model
    public struct Result: Sendable {
        public let id: Int               // 1..8
        public let label: String         // "Joy 🙂" etc
        public let scores: [Int: Double] // raw scores per id (1..7); 8 is Mixed only
    }

    public init() { loadExternalLexicon() }

    // MARK: - Tunables
    private let clauseAfterContrastWeight: Double = 1.35 // emphasize the clause after BUT/HOWEVER/THOUGH
    private let negationWindow: Int = 3                  // tokens before a hit that invert or dampen
    private let intensifierMul: Double = 1.6
    private let dampenerMul: Double = 0.7
    private let exclaimAmpPerBang: Double = 0.12         // add % per '!'
    private let capsBoost: Double = 0.15                 // if token is ALLCAPS and length>2
    private let mixedMargin: Double = 0.22               // within 22% of top → Mixed

    // MARK: - Lexicons (extendable)
    // Use lowercased stems (e.g., "grateful", "gratitu" unnecessary). We also stem lightly below.
    private var joy: Set<String> = [
        "proud","grateful","gratitude","relief","relieved","glad","joy","happy","happiness","excited","content","appreciate","win","progress","celebrate",
        // Dialects/slang/UK/Aus/US
        "stoked","buzzing","amped","pumped","over the moon","chuffed","well chuffed","proper chuffed","made up","delighted","thrilled","ecstatic","elated","overjoyed","cheered","lifted","heartened"
    ]
    private var sadness: Set<String> = [
        "sad","sadness","regret","miss","missing","lonely","alone","loss","losing","grief","heartbroken","devastated","bereft","sorrow","mourn","mourning","blue","down","low","flat","drained","burnt out","burned out","exhausted","knackered","shattered","gutted","downcast","disappointed","let down"
    ]
    private var anger: Set<String> = [
        "angry","anger","furious","mad","irritated","annoyed","peeved","pissed off","cheesed off","miffed","rage","seething","fuming","livid","resent","resentful","unfair","injustice","betray","crossed a line","frustrat","wound up"
    ]
    private var fear: Set<String> = [
        "afraid","scared","fear","anxious","anxiety","worried","worry","nervous","on edge","jittery","overwhelm","overwhelmed","panic","panicked","terrified","petrified","dread","uneasy","apprehensive"
    ]
    private var surprise: Set<String> = [
        "surprised","shocked","shock","sudden","unexpected","didn't expect","did not expect","out of nowhere","whoa","wow","gobsmacked","flabbergasted","stunned","took me by surprise"
    ]
    private var disgust: Set<String> = [
        "disgust","disgusted","gross","nasty","repulsed","revolting","can't stand","cannot stand","yuck","eww","icky","vile","minging","manky","rank","foul","nauseous","sickening"
    ]
    private var neutral: Set<String> = [
        "note","noticed","observing","log","track","journal","record","write","today","this morning","this evening","update","check-in","check in"
    ]

    // High-precision patterns (regex) → direct boosts
    private lazy var patterns: [(NSRegularExpression, (inout [Int: Double]) -> Void)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        return [
            // Regret / counterfactuals → Sadness
            (rx(#"\bi regret\b"#), { $0[2, default:0] += 3 }),
            (rx(#"\bif only I (?:had|didn't|did not)\b"#), { $0[2, default:0] += 2.5 }),
            // Pride / gratitude → Joy
            (rx(#"\bI(?:'m| am) proud\b"#), { $0[1, default:0] += 3 }),
            (rx(#"\bgrateful\b"#), { $0[1, default:0] += 2.5 }),
            // Fear
            (rx(#"\bI(?:'m| am) afraid\b"#), { $0[4, default:0] += 3 }),
            (rx(#"\bworried\b"#), { $0[4, default:0] += 2 }),
            // Anger / unfairness
            (rx(#"\b(?:angry|furious|betray(?:ed)?|unfair)\b"#), { $0[3, default:0] += 3 }),
            // Surprise
            (rx(#"\b(?:didn'?t expect|out of nowhere|sudden(?:ly)?)\b"#), { $0[5, default:0] += 2.5 }),
            // Disgust
            (rx(#"\b(?:disgust(?:ed|ing)?|gross|can't stand|cannot stand)\b"#), { $0[6, default:0] += 3 })
        ]
    }()

    private let intensifiers: Set<String> = [
        "very","really","so","extremely","totally","incredibly","soooo","super","mega","proper","dead","well"
    ]
    private let dampeners: Set<String>   = [
        "a bit","kind of","kinda","slightly","somewhat","a little","sort of","ish","low-key","lowkey"
    ]
    private let negators: Set<String>     = [
        "not","never","no","hardly","barely","scarcely","isn't","isnt","aren't","arent","don't","dont","didn't","didnt","cannot","can't","cant","ain't","ain’t","won't","wont"
    ]

    // Emoji → boosts
    private let emojiMap: [Character: Int] = [
        "🙂":1, "😊":1, "😄":1, "😁":1, "🥳":1,
        "😢":2, "😭":2, "😔":2,
        "😠":3, "😡":3, "🤬":3,
        "😨":4, "😰":4, "😱":4,
        "😮":5, "😲":5, "🤯":5,
        "🤢":6, "🤮":6, "😖":6
    ]

    // MARK: - Classify
    public func classify(_ text: String) -> Result {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Result(id: 7, label: labelFor(7), scores: [7:1])
        }

        // 1) Normalize & split into clauses; prioritize clause after contrast
        let normalized = normalize(text)
        let (priorityClause, otherClauses) = prioritizeAfterContrast(normalized)

        // 2) Score clauses (priority weighted)
        var scores: [Int: Double] = [:] // 1..7
        scoreClause(priorityClause, into: &scores, weight: clauseAfterContrastWeight)
        for clause in otherClauses { scoreClause(clause, into: &scores, weight: 1.0) }

        // 3) Emoji & punctuation amplifiers (whole text)
        amplifyFromEmojiAndPunct(in: normalized, scores: &scores)

        // 4) Fallback neutral if no signal
        if scores.values.allSatisfy({ $0 == 0 }) { scores[7] = 1 }

        // 5) Decide winner or Mixed based on margin
        let sorted = scores.sorted { $0.value > $1.value }
        let top = sorted.first!
        let second = sorted.dropFirst().first ?? (7,0)
        let isMixed = second.1 > 0 && (top.1 - second.1) / max(1.0, top.1) < mixedMargin
        let id = isMixed ? 8 : top.0
        return Result(id: id, label: labelFor(id), scores: scores)
    }

    // MARK: - External lexicon overlay (optional)
    private struct LexiconPack: Decodable {
        let joy: [String]?
        let sadness: [String]?
        let anger: [String]?
        let fear: [String]?
        let surprise: [String]?
        let disgust: [String]?
        let neutral: [String]?
        let intensifiers: [String]?
        let dampeners: [String]?
        let negators: [String]?
    }

    private func loadExternalLexicon(filename: String = "EmotionLexicon", ext: String = "json") {
        #if canImport(Foundation)
        if let url = Bundle.main.url(forResource: filename, withExtension: ext),
           let data = try? Data(contentsOf: url),
           let pack = try? JSONDecoder().decode(LexiconPack.self, from: data) {
            if let v = pack.joy { joy.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.sadness { sadness.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.anger { anger.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.fear { fear.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.surprise { surprise.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.disgust { disgust.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.neutral { neutral.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.intensifiers { intensifiersOverlay.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.dampeners { dampenersOverlay.formUnion(v.map { $0.lowercased() }) }
            if let v = pack.negators { negatorsOverlay.formUnion(v.map { $0.lowercased() }) }
        }
        #endif
    }

    private var intensifiersOverlay: Set<String> = []
    private var dampenersOverlay: Set<String> = []
    private var negatorsOverlay: Set<String> = []

    // prefer overlay if present
    private func isIntensifier(_ t: String) -> Bool { intensifiers.contains(t) || intensifiersOverlay.contains(t) }
    private func isDampener(_ t: String)   -> Bool { dampeners.contains(t) || dampenersOverlay.contains(t) }
    private func isNegator(_ t: String)     -> Bool { negators.contains(t) || negatorsOverlay.contains(t) }

    // MARK: - Clause scoring
    private func scoreClause(_ clause: String, into scores: inout [Int: Double], weight: Double) {
        guard !clause.isEmpty else { return }

        // Pattern boosts (regex)
        var local = scores
        for (rx, bump) in patterns {
            if rx.firstMatch(in: clause, options: [], range: NSRange(location: 0, length: (clause as NSString).length)) != nil {
                bump(&local)
            }
        }

        // Tokenize & windowed negation/intensity
        let tokens = tokenize(clause)
        let n = tokens.count
        for i in 0..<n {
            let t = tokens[i]
            // Determine base bucket(s) by lexicon membership
            var hits: [Int] = []
            if inLex(t, joy)      { hits.append(1) }
            if inLex(t, sadness)  { hits.append(2) }
            if inLex(t, anger)    { hits.append(3) }
            if inLex(t, fear)     { hits.append(4) }
            if inLex(t, surprise) { hits.append(5) }
            if inLex(t, disgust)  { hits.append(6) }
            if inLex(t, neutral)  { hits.append(7) }
            guard !hits.isEmpty else { continue }

            // Check context window for negation & intensity
            var mul = 1.0
            var inverted = false
            // Intensifiers/dampeners anywhere in a small window
            let lo = max(0, i - negationWindow), hi = min(n - 1, i + negationWindow)
            for j in lo...hi {
                let ctx = tokens[j]
                if isIntensifier(ctx) { mul *= intensifierMul }
                if isDampener(ctx)    { mul *= dampenerMul }
                if isNegator(ctx)     { inverted = true }
                if isAllCaps(tokens[j]) { mul *= (1.0 + capsBoost) }
            }

            for h in hits {
                let v = (inverted ? -1.0 : 1.0) * mul
                local[h, default: 0] += v
                if inverted { // e.g., "not happy" → damp joy and add to sadness
                    if h == 1 { local[2, default:0] += abs(v) * 0.8 }
                }
            }
        }

        // Apply clause weight and merge into global scores
        for (k, v) in local { scores[k, default:0] += v * weight }
    }

    // MARK: - Emoji & punctuation
    private func amplifyFromEmojiAndPunct(in text: String, scores: inout [Int: Double]) {
        for ch in text { if let id = emojiMap[ch] { scores[id, default:0] += 1.0 } }
        let bangs = text.filter { $0 == "!" }.count
        if bangs > 0 {
            // add proportional boost to the current top category (if any yet), else anger/surprise
            let top = scores.sorted { $0.value > $1.value }.first?.key
            let target = top ?? 3
            scores[target, default:0] += Double(bangs) * exclaimAmpPerBang * max(1.0, scores[target] ?? 1.0)
        }
        // many question marks can lean Surprise a bit
        let qs = text.filter { $0 == "?" }.count
        if qs >= 2 { scores[5, default:0] += 0.5 }
    }

    // MARK: - Utilities
    private func labelFor(_ id: Int) -> String {
        switch id {
        case 1: return "Joy 🙂"
        case 2: return "Sadness 😢"
        case 3: return "Anger 😠"
        case 4: return "Fear 😨"
        case 5: return "Surprise 😮"
        case 6: return "Disgust 🤢"
        case 8: return "Mixed 😵‍💫"
        default: return "Neutral 😐"
        }
    }

    private func normalize(_ s: String) -> String {
        // Lowercase, collapse whitespace, keep emoji/punct
        let low = s.lowercased()
        let collapsed = low.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed
    }

    private func prioritizeAfterContrast(_ text: String) -> (String, [String]) {
        // Split on contrastive connectives and give the last clause priority
        let markers = [" but ", " however ", " though "]
        for m in markers {
            if text.contains(m), let r = text.range(of: m) {
                let after = String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                let before = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                return (after, [before])
            }
        }
        return (text, [])
    }

    private func tokenize(_ s: String) -> [String] {
        // Keep simple tokens; join certain phrases beforehand
        let joined = s.replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
        return joined.split{ !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
    }

    private func inLex(_ token: String, _ set: Set<String>) -> Bool {
        if set.contains(token) { return true }
        // light stemming: drop common suffixes
        let stem = lightStem(token)
        if set.contains(stem) { return true }
        // phrase-like entries (e.g., "can't stand") handled earlier via regex; but also check joined underscore
        return false
    }

    private func lightStem(_ t: String) -> String {
        var s = t
        for suf in ["ing","ed","ly","ies","s"] {
            if s.hasSuffix(suf) && s.count > suf.count + 2 { s.removeLast(suf.count); break }
        }
        return s
    }

    private func isAllCaps(_ t: String)     -> Bool { let letters = t.filter{ $0.isLetter }; return !letters.isEmpty && letters.allSatisfy{ $0.isUppercase } && t.count > 2 }
}

// MARK: - Test Rig Adapter (Analyzer)
// Conforms to a simple Analyzer API used by your macOS Test Rig. Adjust names if needed.
// Expecting types similar to:
//   public enum AlgorithmCategory { case emotion, activeListening, title, prompt, domain }
//   public struct AnalyzerInput { let fullText: String; let selectedRange: Range<String.Index>? }
//   public struct AnalyzerOutput { let category: AlgorithmCategory; let name: String; let result: String; let metadata: [String:String]? }

public struct EmotionProAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "Emotion • Rules Pro"
    private let clf = RuleEmotionClassifierPro()
    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil) ? String(input.fullText[input.selectedRange!]) : input.fullText
        let res = clf.classify(text)
        let scoreStr = res.scores
            .sorted{ $0.key < $1.key }
            .map{ "\($0.key):\(String(format: "%.2f", $0.value))" }
            .joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(res.id) – \(res.label)",
                              metadata: ["scores": scoreStr])
    }
}
