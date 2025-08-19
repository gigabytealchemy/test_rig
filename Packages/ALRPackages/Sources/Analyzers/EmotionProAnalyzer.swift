// EmotionProAnalyzer.swift
//
// Rule-based emotion classifier for journaling (offline, deterministic).
// Outputs 8-way: 1 Joy, 2 Sadness, 3 Anger, 4 Fear, 5 Surprise, 6 Disgust, 7 Neutral, 8 Mixed.
//
// This iteration:
// - Adds special handling for "mad" slang (e.g., "mad tired/fun/good") → intensifier for Joy/Neutral, not Anger
// - Keeps boundary-safe Anger regexes for true cases ("mad at/about", "so mad", "made me mad")
// - Widens mixedMargin (0.28 → 0.40) so Joy+negative blends become Mixed more often
// - Retains earlier fixes (neutral gating ≥2 anchors, contrast weighting 1.30, made→mad stemming guard)
//
// Why: shrink Joy→Anger hard flips; prefer Mixed/Neutral over a wrong single label.

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
    private let clauseAfterContrastWeight: Double = 1.30
    private let negationWindow: Int = 3
    private let intensifierMul: Double = 1.6
    private let dampenerMul: Double = 0.7
    private let exclaimAmpPerBang: Double = 0.12
    private let capsBoost: Double = 0.15
    private let mixedMargin: Double = 0.40   // widened for safer Mixed
    private let neutralMinHits: Int = 2

    // MARK: - Lexicons (cleaned; lowercase; light stemming used)
    private var joy: Set<String> = [
      "proud","grateful","gratitude","relief","relieved","glad","joy","happy","happiness",
      "excited","content","appreciate","overjoyed","thrilled","delighted","stoked","buzzing",
      "chuffed","ecstatic","elated","satisfied","satisfaction","celebrate","celebrat","fun",
      "promotion","graduation","anniversary","birthday","celebrated","milestone"
    ]

    private var sadness: Set<String> = [
      "sad","sadness","regret","miss","missing","lonely","alone","loss","losing","grief",
      "heartbroken","downcast","blue","low","drained","exhausted","tired","bored","boring","boredom",
      "monotony","monotonous","tedious","tedium","homesick","homesickness","nostalgic","nostalgia",
      "disappointed","gutted","bereft","shattered","knackered"
    ]

    private var anger: Set<String> = [
      "angry","anger","furious","mad","irritated","annoyed","peeved","pissed","miffed","rage",
      "seething","fuming","livid","resent","resentful","unfair","injustice","betray",
      "frustrat","frustrated","frustrating","frustration"
    ]

    private var fear: Set<String> = [
      "afraid","scared","fear","anxious","anxiety","worried","worry","nervous","jittery",
      "overwhelm","overwhelmed","panic","panicked","terrified","petrified","dread","uneasy",
      "apprehensive","concern","concerned","worrying"
    ]

    private var surprise: Set<String> = [
      "surprised","shocked","shock","sudden","unexpected","didn't","expect","did","not","expect",
      "whoa","wow","gobsmacked","flabbergasted","stunned"
    ]

    private var disgust: Set<String> = [
      "disgust","disgusted","gross","nasty","repulsed","revolting","yuck","eww","icky","vile",
      "minging","manky","rank","foul","nauseous","sickening","sickened","appalled"
    ]

    private var neutral: Set<String> = [
      "note","noticed","observing","log","track","journal","record","write",
      "today","this","morning","evening","update","check-in","check","routine","uneventful",
      "same","as","usual","nothing","special","chores","fyi"
    ]

    // MARK: - Regex patterns (boundary-safe)
    private lazy var patterns: [(NSRegularExpression, (inout [Int: Double], inout Int) -> Void)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        return [
            // --- Joy (life events / clear positives) ---
            (rx(#"\b(?:first )?birthday\b"#), { s, _ in s[1, default:0] += 3 }),
            (rx(#"\banniversar(?:y|ies)\b"#), { s, _ in s[1, default:0] += 2.2 }),
            (rx(#"\bpromotion\b"#), { s, _ in s[1, default:0] += 2.0 }),
            (rx(#"\bgraduation\b"#), { s, _ in s[1, default:0] += 2.0 }),
            (rx(#"\bcelebrat(?:e|ed|ing|ion)\b"#), { s, _ in s[1, default:0] += 1.8 }),
            (rx(#"\bso happy\b"#), { s, _ in s[1, default:0] += 2.0 }),
            (rx(#"\bproud of\b"#), { s, _ in s[1, default:0] += 1.5 }),

            // --- Sadness (nostalgia/miss mild) ---
            (rx(#"\bnostalg(?:ic|ia)\b"#), { s, _ in s[2, default:0] += 0.8 }),
            (rx(#"\bhomesick(ness)?\b"#), { s, _ in s[2, default:0] += 1.0 }),
            (rx(#"\b(i )?miss(ing)?( (you|them|home|the old))?\b"#), { s, _ in s[2, default:0] += 1.0 }),
            (rx(#"\blet down\b"#), { s, _ in s[2, default:0] += 2.0 }),

            // --- Anger (true “mad” uses + complaints) ---
            (rx(#"\bmad (?:at|about)\b"#), { s, _ in s[3, default:0] += 2.2 }),
            (rx(#"\bso mad\b"#), { s, _ in s[3, default:0] += 2.3 }),
            (rx(#"\bmade me mad\b"#), { s, _ in s[3, default:0] += 2.4 }),
            (rx(#"\bpissed off\b"#), { s, _ in s[3, default:0] += 2.3 }),
            (rx(#"\bwound up\b"#), { s, _ in s[3, default:0] += 2.0 }),
            (rx(#"\bcrossed a line\b"#), { s, _ in s[3, default:0] += 2.4 }),
            (rx(#"(shitshow|utterly dismal|rotten|garbage|rip-?off|slave wages|pain in the (?:ass|butt)|cutting my hours)"#),
             { s, _ in s[3, default:0] += 2.0 }),
            (rx(#"\ball (this|that) (bs|bullshit)\b"#), { s, _ in s[3, default:0] += 2.0 }),

            // --- "ugh" (very mild; no more flipping Joy) ---
            (rx(#"(^|\b)ugh(?:[ ,.!?]| (?:that|this|so|such|it'?s))"#),
             { s, _ in s[3, default:0] += 0.3; s[6, default:0] += 0.2 }),

            // --- Fear (medical/uncertainty) ---
            (rx(#"\b(hospital|doctor|clinic|e\.?r\.?|emergency|mri|x-?ray|ct|ultra\s?sound|lab(?:work|s)?|bloodwork)\b.{0,40}\b(wait|test|result|worry|concern)\b"#),
             { s, _ in s[4, default:0] += 2.4 }),
            (rx(#"\b(biopsy|scan|test results?|waiting (for|on) results|results (are|came) (back|in))\b"#),
             { s, _ in s[4, default:0] += 1.8 }),

            // --- Surprise ---
            (rx(#"\b(didn'?t expect|out of nowhere|sudden(?:ly)?)\b"#), { s, _ in s[5, default:0] += 2.0 }),

            // --- Disgust ---
            (rx(#"\b(disgust(?:ed|ing)?|gross|can't stand|cannot stand)\b"#), { s, _ in s[6, default:0] += 2.4 }),

            // --- Joy slang: "mad <adj>" as intensifier (not Anger) ---
            (rx(#"\bmad (?:good|fun|love|respect|skills?|tired)\b"#),
             { s, _ in s[1, default:0] += 1.0; s[3, default:0] -= 1.0 }),

            // --- Neutral anchor (counts toward gating) ---
            (rx(#"\bjust an update\b"#), { s, nh in s[7, default:0] += 1.5; nh += 1 }),
        ]
    }()

    private let intensifiers: Set<String> = [
        "very","really","so","extremely","totally","incredibly","soooo","super","mega","proper","dead","well",
        "absolutely","completely","thoroughly","utterly","highly","exceedingly","overly","excessively","intensely"
    ]
    private let dampeners: Set<String> = [
        "a","bit","kind","of","kinda","slightly","somewhat","a","little","sort","of","ish","low-key","lowkey",
        "not","really","not","that","not","too","not","very","not","much"
    ]
    private let negators: Set<String> = [
        "not","never","no","hardly","barely","scarcely","isn't","isnt","aren't","arent","don't","dont","didn't","didnt",
        "cannot","can't","cant","ain't","ain’t","won't","wont"
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

        // Normalize & prioritize clause after contrast markers
        let normalized = normalize(text)
        let (priorityClause, otherClauses) = prioritizeAfterContrast(normalized)

        // Score clauses
        var scores: [Int: Double] = [:] // 1..7
        var neutralHitsTotal = 0
        scoreClause(priorityClause, into: &scores, weight: clauseAfterContrastWeight, neutralHits: &neutralHitsTotal)
        for clause in otherClauses {
            scoreClause(clause, into: &scores, weight: 1.0, neutralHits: &neutralHitsTotal)
        }

        // Emoji & punctuation amplifiers
        amplifyFromEmojiAndPunct(in: normalized, scores: &scores)

        // Fallback neutral if no signal
        if scores.values.allSatisfy({ $0 == 0 }) { scores[7] = 1 }

        // Neutral gating
        if (scores[7] ?? 0) > 0, neutralHitsTotal < neutralMinHits { scores[7] = 0 }

        // Mixed decision: Joy vs Negative if close; otherwise top-1
        let sorted = scores.sorted { $0.value > $1.value }
        let top = sorted.first!
        let second = sorted.dropFirst().first ?? (7, 0.0)

        let joyScore = scores[1] ?? 0
        let negMax  = max(scores[2] ?? 0, scores[3] ?? 0, scores[4] ?? 0)
        let mixedOpposing = (joyScore > 0.8 && negMax > 0.8) &&
                            ((abs(joyScore - negMax) / max(1.0, max(joyScore, negMax))) < 0.55)

        let isMixed = mixedOpposing || (second.1 > 0 && (top.1 - second.1) / max(1.0, top.1) < mixedMargin)
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

    private var intensifiersOverlay: Set<String> = []
    private var dampenersOverlay: Set<String> = []
    private var negatorsOverlay: Set<String> = []

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

    // prefer overlay words if present
    private func isIntensifier(_ t: String) -> Bool { intensifiers.contains(t) || intensifiersOverlay.contains(t) }
    private func isDampener(_ t: String)   -> Bool { dampeners.contains(t) || dampenersOverlay.contains(t) }
    private func isNegator(_ t: String)     -> Bool { negators.contains(t) || negatorsOverlay.contains(t) }

    // MARK: - Clause scoring
    private func scoreClause(_ clause: String, into scores: inout [Int: Double], weight: Double, neutralHits: inout Int) {
        guard !clause.isEmpty else { return }

        // Pattern boosts
        var local = scores
        let ns = clause as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        for (rx, bump) in patterns {
            if rx.firstMatch(in: clause, options: [], range: fullRange) != nil {
                bump(&local, &neutralHits)
            }
        }

        // Tokenize & windowed negation/intensity
        let tokens = tokenize(clause)
        let n = tokens.count
        for i in 0..<n {
            let t = tokens[i]
            var hits: [Int] = []
            if inLex(t, joy)      { hits.append(1) }
            if inLex(t, sadness)  { hits.append(2) }
            if inLex(t, anger)    { hits.append(3) }
            if inLex(t, fear)     { hits.append(4) }
            if inLex(t, surprise) { hits.append(5) }
            if inLex(t, disgust)  { hits.append(6) }
            if inLex(t, neutral)  { hits.append(7); neutralHits += 1 }
            guard !hits.isEmpty else { continue }

            var mul = 1.0
            var inverted = false
            let lo = max(0, i - negationWindow), hi = min(n - 1, i + negationWindow)
            for j in lo...hi {
                let ctx = tokens[j]
                if isIntensifier(ctx) { mul *= intensifierMul }
                if isDampener(ctx)    { mul *= dampenerMul }
                if isNegator(ctx)     { inverted = true }
                if isAllCaps(ctx)     { mul *= (1.0 + capsBoost) }
            }

            for h in hits {
                let v = (inverted ? -1.0 : 1.0) * mul
                local[h, default: 0] += v
                if inverted, h == 1 { local[2, default:0] += abs(v) * 0.8 } // "not happy" → lean Sadness
            }
        }

        // Merge with weight
        for (k, v) in local { scores[k, default:0] += v * weight }
    }

    // MARK: - Emoji & punctuation
    private func amplifyFromEmojiAndPunct(in text: String, scores: inout [Int: Double]) {
        for ch in text {
            if let id = emojiMap[ch] { scores[id, default:0] += 1.0 }
        }
        let bangs = text.filter { $0 == "!" }.count
        if bangs > 0 {
            // Target Joy first, then Surprise, then current top
            let hasJoy = (scores[1] ?? 0) > 0
            let hasSurprise = (scores[5] ?? 0) > 0
            let target = hasJoy ? 1 : (hasSurprise ? 5 : (scores.sorted { $0.value > $1.value }.first?.key ?? 5))
            scores[target, default:0] += Double(bangs) * exclaimAmpPerBang * max(1.0, scores[target] ?? 1.0)
        }
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
        let low = s.lowercased()
        let collapsed = low.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed
    }

    private func prioritizeAfterContrast(_ text: String) -> (String, [String]) {
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
        // Join multi-word idioms we look for in lexicons/regex
        let joined = s.replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
        return joined.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
    }

    private func inLex(_ token: String, _ set: Set<String>) -> Bool {
        if set.contains(token) { return true }
        let stem = lightStem(token)
        if set.contains(stem) { return true }
        return false
    }

    // Avoid stemming "made" → "mad" (false Anger on "made me dinner")
    private func lightStem(_ t: String) -> String {
        if t == "made" { return "made" }
        var s = t
        for suf in ["ing","ed","ly","ies","s"] {
            if s.hasSuffix(suf) && s.count > suf.count + 2 { s.removeLast(suf.count); break }
        }
        return s
    }

    private func isAllCaps(_ t: String) -> Bool {
        let letters = t.filter { $0.isLetter }
        return !letters.isEmpty && letters.allSatisfy { $0.isUppercase } && t.count > 2
    }
}

// MARK: - Test Rig Adapter (unchanged)
public struct EmotionProAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .emotion
    public let name: String = "Emotion • Rules Pro"
    private let clf = RuleEmotionClassifierPro()
    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil)
            ? String(input.fullText[input.selectedRange!])
            : input.fullText
        let res = clf.classify(text)
        let scoreStr = res.scores
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\(String(format: "%.2f", $0.value))" }
            .joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(res.id) – \(res.label)",
                              metadata: ["scores": scoreStr])
    }
}
