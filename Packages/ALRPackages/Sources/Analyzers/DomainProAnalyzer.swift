// EmotionProAnalyzer.swift
//
// Production-lean rule-based 8-way emotion classifier for journaling text.
// Deterministic, fast, private (no network).
//
// Output IDs / labels:
//  1 Joy 🙂     2 Sadness 😢   3 Anger 😠   4 Fear 😨
/* 5 Surprise 😮 6 Disgust 🤢   7 Neutral 😐 8 Mixed 😵‍💫 */
//
// Design:
// - Long, dialect-friendly lexicons (US/UK/Aus slang included).
// - Regex boosts for high-precision cues (frustration, concern, nostalgia, life events).
// - Negation window, intensifier/dampener multipliers.
// - Emoji + punctuation amplifiers; "!" prefers Joy then Surprise.
// - Contrast handling: clause after "but/however/though" gets a mild bonus.
// - Light stemming (ing/ed/ly/s/ies) for robust matching.
// - Mixed decision when opposing valences are both present.
//
// Integration in Test Rig (Analyzer):
//   let out = EmotionProAnalyzer().analyze(input)
//   -> AnalyzerOutput.result = "1 – Joy 🙂"
//
// Notes:
// - We purposely KEEP neutral token scoring so low-affect entries don't get forced
//   into a wrong emotional bucket.
// - Mixed logic is relaxed enough to avoid hard wrongs while still picking a winner
//   when one emotion is clearly dominant.
//

import Foundation

// MARK: - Classifier

public final class RuleEmotionClassifierPro {

    public struct Result: Sendable {
        public let id: Int
        public let label: String
        public let scores: [Int: Double]   // 1..8
    }

    // MARK: Tunables
    private let clauseAfterContrastWeight: Double = 1.20
    private let lastSentenceBonus: Double = 1.10
    private let negationWindow: Int = 3
    private let intensifierMul: Double = 1.6
    private let dampenerMul: Double = 0.7
    private let exclaimAmpPerBang: Double = 0.12
    private let capsBoost: Double = 0.15
    private let mixedMargin: Double = 0.30  // relaxed from super-strict so Mixed triggers appropriately

    public init() {}

    // MARK: Lexicons (all lowercase; light stemming applied on tokens)
    private let joy: Set<String> = [
        "joy","joyful","happy","happiness","glad","grateful","gratitude","thankful","relief","relieved",
        "content","contented","excited","thrilled","delighted","ecstatic","elated","overjoyed","euphoric",
        "proud","accomplished","satisfied","satisfaction","appreciate","appreciated","appreciation",
        "stoked","buzzing","chuffed","made up","over the moon","thriving","celebrate","celebrat","fun",
        "playful","cheerful","light","uplifted","win","won","victory","progress went well","good news",
        "awesome","great","fantastic","amazing","brilliant","sweet","lovely","yay","woohoo","🥳","😊","😄","😁"
    ]

    private let sadness: Set<String> = [
        "sad","sadness","down","blue","low","depressed","depressing","heartbroken","grief","grieving","loss","losing",
        "regret","regretted","regretting","miss","missing","lonely","alone","isolated","homesick","homesickness",
        "disappointed","let down","bereft","gutted","shattered","knackered","tired","exhausted","drained",
        "bored","boring","boredom","monotony","monotonous","tedious","tedium","nostalgic","nostalgia","tearful","crying","😭"
    ]

    private let anger: Set<String> = [
        "anger","angry","mad","furious","irate","livid","enraged","seething","fuming","raging","pissed","pissed off",
        "annoyed","irritated","peeved","miffed","wound up","cross","resent","resentful","spite","snapped",
        "unfair","injustice","betray","betrayed","let me down",
        "frustrat","frustrated","frustrating","frustration","🤬","😡"
    ]

    private let fear: Set<String> = [
        "afraid","scared","fear","fearful","terrified","petrified","panicked","panic","uneasy","apprehensive",
        "worried","worry","worrying","concern","concerned","nervous","on edge","jittery","tense","tight",
        "stressed","stress","anxious","anxiety","overwhelm","overwhelmed","dread","alarm","😨","😰","😱"
    ]

    private let surprise: Set<String> = [
        "surprised","surprise","shocked","shock","stunned","stunning","sudden","suddenly","unexpected",
        "didn't expect","did not expect","out of nowhere","whoa","wow","gobsmacked","flabbergasted","🤯","😮"
    ]

    private let disgust: Set<String> = [
        "disgust","disgusted","disgusting","gross","grossed out","nasty","vile","rank","foul","revolting","repulsed",
        "icky","yuck","eww","manky","minging","can't stand","cannot stand","nauseous","sickening","🤢","🤮"
    ]

    // Keep neutral active (helps avoid hard wrongs)
    private let neutral: Set<String> = [
        "note","noted","observe","observing","log","logged","record","recording","write","writing",
        "today","yesterday","this morning","this evening","update","check-in","check in","journal","journaling","document"
    ]

    // Modifiers
    private let intensifiers: Set<String> = [
        "very","so","really","extremely","super","mega","proper","dead","well","soooo","incredibly","truly"
    ]
    private let dampeners: Set<String> = [
        "a bit","a little","kind of","kinda","sort of","sorta","slightly","somewhat","lowkey","low-key","ish"
    ]
    private let negators: Set<String> = [
        "not","never","no","hardly","barely","isn't","isnt","aren't","arent","wasn't","wasnt","can't","cant","won't","wont","don't","dont","ain't","aint"
    ]

    // MARK: Regex boosts
    private lazy var patterns: [(NSRegularExpression, (inout [Int: Double]) -> Void)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        return [
            // Life-event joy
            (rx(#"\b(?:first )?birthday\b"#), { $0[1, default:0] += 3.0 }),
            (rx(#"\banniversar(?:y|ies)\b"#), { $0[1, default:0] += 2.5 }),
            (rx(#"\bmilestone\b"#), { $0[1, default:0] += 1.6 }),
            (rx(#"\bhad a blast\b"#), { $0[1, default:0] += 3.0 }),
            (rx(#"\bso happy\b"#), { $0[1, default:0] += 2.0 }),

            // Sadness
            (rx(#"\bi regret\b"#), { $0[2, default:0] += 3.0 }),
            (rx(#"\bnostalg(?:ic|ia)\b"#), { $0[2, default:0] += 1.8 }),

            // Anger
            (rx(#"(?<!not )\bfrustrat(?:ed|ing|ion)?\b"#), { $0[3, default:0] += 3.0 }),
            (rx(#"\b(unfair|injustice)\b"#), { $0[3, default:0] += 2.0 }),

            // Fear
            (rx(#"\bconcern(?:ed|ing)?\b"#), { $0[4, default:0] += 2.0 }),
            (rx(#"\boverwhelm(?:ed|ing)?\b"#), { $0[4, default:0] += 2.0 }),

            // Surprise
            (rx(#"\b(didn'?t expect|out of nowhere|sudden(?:ly)?)\b"#), { $0[5, default:0] += 2.5 }),

            // Disgust
            (rx(#"\b(disgust(?:ed|ing)?|gross|can't stand|cannot stand)\b"#), { $0[6, default:0] += 3.0 }),

            // Slang: "mad good/fun/..." is positive — damp anger if any
            (rx(#"\bmad (?:good|fun|love|respect|skills?)\b"#), { scores in
                scores[1, default:0] += 1.2
                scores[3, default:0] -= 1.0
            })
        ]
    }()

    // MARK: Public API
    public func classify(_ text: String) -> Result {
        // Split to sentences, newest-first and give the last sentence a small bonus
        let sentences = splitSentences(text).reversed()
        var total: [Int: Double] = [:]

        var idx = 0
        for s in sentences {
            let weight = idx == 0 ? lastSentenceBonus : 1.0
            var scores = scoreClause(s)
            for (k, v) in scores { total[k, default:0] += v * weight }
            idx += 1
        }

        // Contrast: prefer clause after "but/however/though"
        if let contrasted = clauseAfterContrast(text.lowercased()) {
            let boost = scoreClause(contrasted)
            for (k, v) in boost { total[k, default:0] += v * (clauseAfterContrastWeight - 1.0) }
        }

        // Decide winner or Mixed
        let sorted = total.sorted { $0.value > $1.value }
        guard let top = sorted.first else {
            return Result(id: 7, label: labelFor(7), scores: [7:1.0])
        }
        let second = sorted.dropFirst().first ?? (7, 0.0)

        let joyScore = total[1] ?? 0
        let negMax  = max(total[2] ?? 0, total[3] ?? 0, total[4] ?? 0)
        let mixedOpposing = (joyScore > 0.8 && negMax > 0.8) &&
                            ((abs(joyScore - negMax) / max(1.0, max(joyScore, negMax))) < 0.55)

        let isMixed = mixedOpposing || (second.1 > 0 && (top.1 - second.1) / max(1.0, top.1) < mixedMargin)
        let id = isMixed ? 8 : top.0
        return Result(id: id, label: labelFor(id), scores: total)
    }

    // MARK: Internals

    private func scoreClause(_ clause: String) -> [Int: Double] {
        var scores: [Int: Double] = [:]
        let tokens = tokenize(clause)
        let lowered = clause.lowercased()

        // 1) Regex boosts (once per clause)
        var local = scores
        for (rx, bump) in patterns {
            if rx.firstMatch(in: lowered, options: [], range: NSRange(location: 0, length: lowered.utf16.count)) != nil {
                bump(&local)
            }
        }

        // 2) Token-level hits with negation/intensity/dampening
        let n = tokens.count
        for i in 0..<n {
            let t = tokens[i]
            let base: [Int] = bucketHits(for: t)
            if base.isEmpty { continue }

            // Negation window
            var mult = 1.0
            let start = max(0, i - negationWindow)
            if (start..<i).contains(where: { negators.contains(tokens[$0]) }) {
                mult *= -1.0    // flip sentiment
            }

            // Intensifiers / dampeners in a small forward window
            let fwdEnd = min(n, i + 3)
            if (i..<fwdEnd).contains(where: { intensifiers.contains(tokens[$0]) }) { mult *= intensifierMul }
            if (i..<fwdEnd).contains(where: { dampeners.contains(tokens[$0])   }) { mult *= dampenerMul }

            for b in base {
                local[b, default: 0] += mult
            }
        }

        // 3) Emoji and punctuation amplifiers
        amplifyFromEmojiAndPunct(clause, into: &local)

        return local
    }

    private func bucketHits(for token: String) -> [Int] {
        var hits: [Int] = []
        if inLex(token, joy)      { hits.append(1) }
        if inLex(token, sadness)  { hits.append(2) }
        if inLex(token, anger)    { hits.append(3) }
        if inLex(token, fear)     { hits.append(4) }
        if inLex(token, surprise) { hits.append(5) }
        if inLex(token, disgust)  { hits.append(6) }
        if inLex(token, neutral)  { hits.append(7) } // keep neutral active
        return hits
    }

    private func amplifyFromEmojiAndPunct(_ text: String, into scores: inout [Int: Double]) {
        // Exclamation marks
        let bangs = text.filter { $0 == "!" }.count
        if bangs > 0 {
            let hasJoy = (scores[1] ?? 0) > 0
            let hasSurprise = (scores[5] ?? 0) > 0
            let target = hasJoy ? 1 : (hasSurprise ? 5 : (scores.sorted { $0.value > $1.value }.first?.key ?? 5))
            scores[target, default:0] += Double(bangs) * exclaimAmpPerBang * max(1.0, scores[target] ?? 1.0)
        }
        // ALL CAPS word boost (avoid URLs)
        if text.split(separator: " ").contains(where: { $0.count > 2 && $0 == $0.uppercased() && !$0.contains("HTTP") }) {
            let k = scores.sorted { $0.value > $1.value }.first?.key
            if let k { scores[k, default:0] += capsBoost }
        }
    }

    private func clauseAfterContrast(_ t: String) -> String? {
        for split in [" but ", " however ", " though "] {
            if let r = t.range(of: split) { return String(t[r.upperBound...]) }
        }
        return nil
    }

    private func splitSentences(_ text: String) -> [String] {
        // Simple splitter that respects newlines
        let rough = text.replacingOccurrences(of: "\n", with: " . ")
        let parts = rough.split(whereSeparator: { ".?!".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }
        return parts.filter { !$0.isEmpty }
    }

    private func tokenize(_ s: String) -> [String] {
        let lower = s.lowercased()
            .replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
            .replacingOccurrences(of: "made up", with: "made_up")
            .replacingOccurrences(of: "over the moon", with: "over_the_moon")
        let raw = lower.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
        return raw.map(lightStem)
    }

    private func lightStem(_ w: String) -> String {
        var s = w
        if s.hasSuffix("ies"), s.count > 3 { s = String(s.dropLast(3)) + "y" }
        for suf in ["ing","ed","ly","s"] where s.count > suf.count + 2 && s.hasSuffix(suf) {
            s = String(s.dropLast(suf.count))
            break
        }
        return s
    }

    private func inLex(_ token: String, _ set: Set<String>) -> Bool {
        if set.contains(token) { return true }
        // also allow phrasey tokens we collapsed e.g. "over_the_moon"
        if set.contains(token.replacingOccurrences(of: "_", with: " ")) { return true }
        return false
    }

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
}

// MARK: - Test Rig Adapter

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
        // "id – Label"
        return AnalyzerOutput(category: category,
                              name: name,
                              result: "\(res.id) – \(res.label)",
                              metadata: ["scores": res.scores
                                .sorted{ $0.key < $1.key }
                                .map{ "\($0.key):\(String(format: "%.2f", $0.value))" }
                                .joined(separator: " • ")])
    }
}
