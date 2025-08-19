// ActiveListenerEnginePro.swift
//
// Replacement implementing Phase 3 & 4 + Stage 3 evaluation.
// Date: 2025-08-19
//
// SUMMARY OF CHANGES
// ------------------
// PHASE 3 — Capture Hygiene
// • Switched greedy (.+)/(.*) to non-greedy (.+?)/(.*?) where templates splice $1.
// • Sanitize captured text before insertion (trim spaces/punct; normalize leading ",").
// • Context spacer: when a template ends with a host noun + $1 (e.g., "partner$1"),
//   insert either ", " (if $1 begins with comma/and/but/which/that) or a single space.
// • Output punctuation tidy: collapse repeated punctuation, remove spaces-before-commas,
//   guarantee a single sentence terminator.
//
// PHASE 4 — Emotion Coverage & Balance
// • Added broader emotion triggers: pride ("felt proud"), frustration ("frustrated/annoyed"),
//   mixed ("but also / at the same time" with opposing valence), joy variants.
// • Increased weights for these emotion rules (+1) so they beat generic domain fallbacks
//   when both match the newest sentence.
// • Neutral/Mixed fallback pools tweaked for slightly more grounded tone.
//
// Recall Polish (from Phase 1, extended here)
// • Pronoun shift now covers "I was"→"you were", "I've"→"you've", "I'd"→"you'd", "I'll"→"you'll".
//
// STAGE 3 — Evaluation Utility
// • Diagnostics.evaluate(alrs:) returns counts of grammar/punctuation/capitalization issues,
//   using simple, maintainable regex heuristics (offline, deterministic).
//
// Integration
// -----------
// let reply = ActiveListenerEnginePro.shared.respond(to: text, emotion: id, domains: domains)
// // For QA in tests:
// let issues = ActiveListenerEnginePro.Diagnostics.evaluate(alrs: collectedReplies)
// print(issues.grammar, issues.punctuation, issues.capitalization)

// ActiveListenerEnginePro.swift
//
// Phase 4 engine, with explicit "[ph4]" prefix on every output.
// Use this build to confirm your test rig is really using the new engine.

import Foundation

public final class ActiveListenerEnginePro {
    public static let shared = ActiveListenerEnginePro()
    private init() { buildRules() }

    // ... [all existing properties, rules, and helpers from the last file remain unchanged] ...

    // Wrap every final response with a prefix
    private func withPhase4Tag(_ text: String) -> String {
        return "[ph4] " + text
    }

    // MARK: - Public API
    @discardableResult
    public func respond(to input: String,
                        emotion: Int = 7,
                        domains: [(String, Double)]? = nil,
                        richEmotion: Int? = nil) -> String? {
        stepCounter &+= 1
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let reply = ruleBasedReply(for: cleaned) {
            trackMemory(cleaned)
            return withPhase4Tag(reply)
        }
        if let recall = tryRecall(currentInput: cleaned) {
            trackMemory(cleaned)
            recordFamilyUse("recall")
            return withPhase4Tag(recall)
        }
        if let (d, s) = domains?.max(by: { $0.1 < $1.1 }), s >= domainUseThreshold,
           let pool = domainFallbackPools[d], canUseFamily("dom:\(d)") {
            let line = chooseVariant(from: pool, key: "dom:\(d)")
            recordFamilyUse("dom:\(d)")
            trackMemory(cleaned)
            return withPhase4Tag(line)
        }
        if let pool = fallbackByEmotion[emotion], canUseFamily("fb:\(emotion)") {
            let line = chooseVariant(from: pool, key: "fb:\(emotion)")
            recordFamilyUse("fb:\(emotion)")
            trackMemory(cleaned)
            return withPhase4Tag(line)
        }
        let line = chooseVariant(from: fallbackByEmotion[7] ?? ["You can say more if you want."], key: "fb:7")
        recordFamilyUse("fb:7")
        trackMemory(cleaned)
        return withPhase4Tag(line)
    }


    // MARK: - Config

    private let snippetMax: Int = 120
    private let recentHistoryLimit: Int = 16
    private let variantCooldown: Int = 6                 // from Phase 2
    private let similarityRejectThreshold: Double = 0.45 // from Phase 2
    private let domainUseThreshold: Double = 0.45
    private let lastSentenceBonus: Int = 2

    // Recall gating (from Phase 1, unchanged here)
    private let recallMinLen = 12
    private let recallMaxLen = 140
    private let recallCooldownSteps = 3
    private var stepCounter: Int = 0
    private var lastRecallStep: Int? = nil

    // Fallback family cooldown (from Phase 2)
    private let familyCooldownWindow = 4
    private var recentFamilyHistory: [String] = []

    // MARK: - Model

    private struct Rule {
        let key: String
        let regex: NSRegularExpression
        let responses: [String]
        let weight: Int
        let specificity: Int
        let sanitizeCaptures: Bool // Phase 3: whether to sanitize $1..$9 before insertion
    }

    private var rules: [Rule] = []
    private var memory: [String] = [] // recent user snippets (trimmed)

    // Repetition control
    private var recentResponseHistory: [String] = []
    private var usedVariantIndices: [String: [Int]] = [:] // key -> recent variant indices

    // MARK: - Public API
/**
    /// emotion: 1=Joy,2=Sadness,3=Anger,4=Fear,5=Surprise,6=Disgust,7=Neutral,8=Mixed
    @discardableResult
    public func respond(to input: String,
                        emotion: Int = 7,
                        domains: [(String, Double)]? = nil,
                        richEmotion: Int? = nil) -> String?
    {
        stepCounter &+= 1

        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 1) Rule-based reply (newest sentence first)
        if let reply = ruleBasedReply(for: cleaned) {
            trackMemory(cleaned)
            return reply
        }

        // 2) Safer recall w/ gating and polished phrasing (Phase 1 + pronoun patches)
        if let recall = tryRecall(currentInput: cleaned) {
            trackMemory(cleaned)
            recordFamilyUse("recall")
            return recall
        }

        // 3) Domain fallback (with family cooldown)
        if let (d, s) = domains?.max(by: { $0.1 < $1.1 }), s >= domainUseThreshold,
           let pool = domainFallbackPools[d],
           canUseFamily("dom:\(d)")
        {
            let line = chooseVariant(from: pool, key: "dom:\(d)")
            recordFamilyUse("dom:\(d)")
            trackMemory(cleaned)
            return line
        }

        // 4) Emotion fallback (with family cooldown)
        if let pool = fallbackByEmotion[emotion], canUseFamily("fb:\(emotion)") {
            let line = chooseVariant(from: pool, key: "fb:\(emotion)")
            recordFamilyUse("fb:\(emotion)")
            trackMemory(cleaned)
            return line
        }

        // 5) Neutral last resort
        let line = chooseVariant(from: fallbackByEmotion[7] ?? ["You can say more if you want."], key: "fb:7")
        recordFamilyUse("fb:7")
        trackMemory(cleaned)
        return line
    }*/

    // MARK: - Core rule matching

    private func ruleBasedReply(for input: String) -> String? {
        let sentences = splitIntoSentences(input).reversed()
        var best: (response: String, score: Int)? = nil
        var pos = 0
        for sentence in sentences {
            pos += 1
            for rule in rules {
                guard let match = rule.regex.firstMatch(
                    in: sentence, options: [], range: NSRange(location: 0, length: (sentence as NSString).length)
                ) else { continue }

                var candidate = chooseVariant(from: rule.responses, key: rule.key)
                candidate = substituteCaptures(candidate, match: match, in: sentence, sanitize: rule.sanitizeCaptures)

                var score = rule.weight + rule.specificity
                if pos == 1 { score += lastSentenceBonus }

                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }
            if best != nil { break }
        }
        return best?.response
    }

    // MARK: - Sentence splitting

    private func splitIntoSentences(_ text: String) -> [String] {
        let breakers = CharacterSet(charactersIn: ".!?\n")
        var parts: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if String(ch).rangeOfCharacter(from: breakers) != nil {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current.removeAll(keepingCapacity: true)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    // MARK: - Capture substitution ($1..$9) with sanitation (Phase 3)

    private func substituteCaptures(_ template: String,
                                    match: NSTextCheckingResult,
                                    in sentence: String,
                                    sanitize: Bool) -> String
    {
        guard match.numberOfRanges > 1 else {
            return Punctuation.ensurePeriod( Punctuation.tidy(template) )
        }

        let ns = sentence as NSString
        var out = template

        for i in 1 ..< match.numberOfRanges {
            let r = match.range(at: i)
            if r.location == NSNotFound { continue }
            var cap = ns.substring(with: r)

            if sanitize {
                cap = CaptureSanitizer.clean(cap)
                out = spliceWithContextAwareSpacer(host: out, captureToken: "$\(i)", capture: cap)
            } else {
                out = out.replacingOccurrences(of: "$\(i)", with: cap)
            }
        }

        // Final punctuation tidy
        out = Punctuation.tidy(out)
        out = Punctuation.ensurePeriod(out)
        return out
    }

    /// Insert capture with awareness of host context like "...partner$1"
    private func spliceWithContextAwareSpacer(host: String, captureToken: String, capture: String) -> String {
        guard let range = host.range(of: captureToken) else {
            return host.replacingOccurrences(of: captureToken, with: capture)
        }
        // look back one token (a word)
        let prefix = String(host[..<range.lowerBound])
        let suffix = String(host[range.upperBound...])

        // Word characters right before token?
        let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9]$"#)
        let hasWordBefore = wordRegex.firstMatch(in: prefix, options: [], range: NSRange(location: max(0, prefix.count-1), length: min(1, prefix.count))) != nil

        var insertion = capture
        if hasWordBefore {
            // If capture begins with comma or common attachers, use ", " else space
            let attachers = ["", ",", "and", "but", "which", "that", "who", "whom", "because", "since"]
            let firstWord = insertion.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            if insertion.hasPrefix(",") || attachers.contains(firstWord) {
                insertion = insertion.hasPrefix(",") ? (", " + insertion.dropFirst().trimmingCharacters(in: .whitespaces)) : (", " + insertion)
            } else {
                insertion = " " + insertion
            }
        }
        var out = host.replacingOccurrences(of: captureToken, with: insertion)
        out = Punctuation.tidy(out)
        return out
    }

    // MARK: - Repetition & diversity helpers

    private func chooseVariant(from options: [String], key: String) -> String {
        guard !options.isEmpty else { return "" }
        let recentIdx = Array(usedVariantIndices[key]?.suffix(variantCooldown) ?? [])
        var candidates = Array(options.enumerated()).filter { !recentIdx.contains($0.offset) }
        if candidates.isEmpty { candidates = Array(options.enumerated()) }

        var chosen: (index: Int, value: String)? = nil
        var tries = 0
        var pool = candidates
        while tries < options.count, !pool.isEmpty {
            let pick = pool.randomElement()!
            let candidate = pick.element
            if let last = recentResponseHistory.last, tooSimilar(candidate, last) {
                pool.removeAll { $0.offset == pick.offset }
                tries += 1
                continue
            }
            chosen = (pick.offset, candidate)
            break
        }

        let index = chosen?.index ?? options.indices.randomElement()!
        let value = chosen?.value ?? options[index]

        usedVariantIndices[key, default: []].append(index)
        if usedVariantIndices[key]!.count > recentHistoryLimit { usedVariantIndices[key]!.removeFirst() }
        recentResponseHistory.append(value)
        if recentResponseHistory.count > recentHistoryLimit { recentResponseHistory.removeFirst() }
        return value
    }

    private func tooSimilar(_ a: String, _ b: String) -> Bool {
        let A = bigrams(a)
        let B = bigrams(b)
        guard !A.isEmpty, !B.isEmpty else { return false }
        let inter = A.intersection(B).count
        let uni = A.union(B).count
        return uni > 0 ? (Double(inter) / Double(uni)) >= similarityRejectThreshold : false
    }

    private func bigrams(_ s: String) -> Set<String> {
        let tokens = s.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard tokens.count >= 2 else { return [] }
        var set = Set<String>()
        for i in 0 ..< (tokens.count - 1) {
            set.insert("\(tokens[i])_\(tokens[i + 1])")
        }
        return set
    }

    private func trackMemory(_ input: String) {
        let snippet = String(input.prefix(snippetMax))
        memory.append(snippet)
        if memory.count > 50 { memory.removeFirst() }
    }

    // MARK: - Family cooldown

    private func canUseFamily(_ familyKey: String) -> Bool {
        let recent = recentFamilyHistory.suffix(familyCooldownWindow)
        return !recent.contains(familyKey)
    }

    private func recordFamilyUse(_ familyKey: String) {
        recentFamilyHistory.append(familyKey)
        if recentFamilyHistory.count > recentHistoryLimit { recentFamilyHistory.removeFirst() }
    }

    // MARK: - Recall (with pronoun shift patches)

    private func tryRecall(currentInput: String) -> String? {
        if let last = lastRecallStep, (stepCounter - last) <= recallCooldownSteps { return nil }
        guard let raw = memory.last else { return nil }

        var snippet = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        snippet = String(snippet.prefix(snippetMax))

        if snippet.count < recallMinLen || snippet.count > recallMaxLen { return nil }

        let verbRegex = try! NSRegularExpression(pattern: #"\b(am|are|is|was|were|feel|felt|want|wanted|think|thought|did|do|made|make|have|had|I've|I'd|I'll)\b"#, options: [.caseInsensitive])
        let hasVerb = verbRegex.firstMatch(in: snippet, options: [], range: NSRange(location: 0, length: (snippet as NSString).length)) != nil
        if !hasVerb { return nil }

        if tooSimilar(snippet, currentInput) { return nil }

        let shifted = RecallFormatter.toSecondPerson(from: snippet) // includes "I was→you were"
        let cleaned = Punctuation.ensurePeriod( Punctuation.tidy(shifted) )
        let variants = [
            "Earlier you mentioned \(cleaned) What feels most present about that now?",
            "Earlier you mentioned \(cleaned) You can add a line or two if you want.",
            "Earlier you mentioned \(cleaned) Does anything new come up as you think about it?"
        ]

        lastRecallStep = stepCounter
        return chooseVariant(from: variants, key: "recall")
    }

    // MARK: - Rule factory (Phase 3 & 4 updates)

    private func buildRules() {
        var built: [Rule] = []

        func rx(_ pattern: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: opts)
        }
        func add(_ key: String, _ pattern: String, _ responses: [String], _ weight: Int, _ sanitize: Bool = true) {
            // rough specificity: more captures + higher weight
            let captures = max(0, pattern.filter { $0 == "(" }.count - pattern.filter { $0 == "\\" }.count)
            let spec = weight + min(3, captures)
            built.append(Rule(key: key, regex: rx(pattern), responses: responses, weight: weight, specificity: spec, sanitizeCaptures: sanitize))
        }

        // ===== Core feelings (broad) — non-greedy where we splice $1 =====
        add("feel.1", #"\bI feel like (.+?)"#, [
            "$1—that’s something you’ve noticed. Is there more you’d like to say?",
            "You feel like $1. You can stay with that here, if it helps.",
            "There’s space for that: $1."
        ], 4)

        add("feel.2", #"\bI feel (.+?)"#, [
            "$1—what’s that like for you right now?",
            "You mentioned feeling $1. Is there anything else in you reacting to that?",
            "Naming $1 can be a start."
        ], 4)

        add("think.1", #"\bI think (.+?)"#, [
            "$1—that’s a thought worth noting.",
            "You’re thinking $1. If it helps, add a line or two.",
            "Sometimes just writing $1 can clarify things."
        ], 2)

        // ===== Desire / intention =====
        add("want.1", #"\bI want to (.+?)"#, [
            "You want to $1. What draws you toward that?",
            "There’s a pull toward $1. One step you want to remember?",
            "$1—what would that give you?"
        ], 3)
        add("want.2", #"\bI want (.+?)"#, [
            "You want $1. Is there more you’d like to say?",
            "$1—how long have you been wanting that?",
            "You can put a few words to $1 here."
        ], 3)

        // ===== Regret / counterfactuals =====
        add("regret.1", #"\bI regret (.+?)"#, [
            "That regret—$1. What sticks with you most?",
            "You’re carrying $1. You can name a detail if you want.",
            "It’s okay to have regrets. Anything else you want to say about $1?"
        ], 5)
        add("ifonly.1", #"\bif only I had (.+?)"#, [
            "“If only I had $1”—there’s something there. Is there more you’d like to say?",
            "$1—does that still weigh on you?",
            "You can sit with that thought for a bit, if it helps."
        ], 5)

        // ===== Fear / worry =====
        add("fear.1", #"\bI(?:'m| am) afraid(?: of)? (.+?)"#, [
            "$1 sounds scary. If it helps, put a few words to it.",
            "Fear around $1 is valid. You can write what comes up.",
            "You can name one ‘what if’ about $1."
        ], 5)
        add("worry.1", #"\bI (?:worry|worrying|am worried|I'm worried) (?:about|that) (.+?)"#, [
            "Worry about $1 can take up space. One line you want to capture?",
            "$1—what’s the main ‘what if’ right now?",
            "You’re safe to write about $1 here."
        ], 4)

        // ===== Sadness / loss =====
        add("sad.1", #"\bI (?:miss|am missing) (.+?)"#, [
            "Missing $1—what do you notice in yourself as you say that?",
            "$1 has a place in you. You can take your time here.",
            "If it helps, name one moment you miss about $1."
        ], 5)
        add("sad.2", #"\bI (?:feel )?lonely\b(?:[^.!?]*)"#, [
            "Feeling lonely can be heavy. What part weighs most right now?",
            "You can put a few words to that feeling here.",
            "Short phrases are enough."
        ], 4, false)

        // ===== Anger / frustration =====
        add("anger.1", #"\bI (?:am|I'm) (?:angry|furious|mad) (?:at|about)? (.+?)"#, [
            "That really got under your skin: $1. You can say more if you want.",
            "$1—what part keeps replaying?",
            "It’s okay to write it plainly."
        ], 4)
        add("anger.2", #"\b(?:unfair|betray(?:ed|al)|crossed a line)\b(?:[^.!?]*)"#, [
            "That felt unfair. One detail you want to keep?",
            "If you want, name the moment that crossed a line.",
            "You can write what didn’t sit right."
        ], 4, false)
        add("frustration.1", #"\b(frustrat(?:ed|ing)|annoy(?:ed|ing))\b(?:[^.!?]*)"#, [
            "That sounded frustrating. What part stuck with you?",
            "You can put a line to what felt most annoying about it.",
            "What was the hardest bit there?"
        ], 5, false) // +1 weight (Phase 4)

        // ===== Disgust / aversion =====
        add("disgust.1", #"\bcan't stand (.+?)"#, [
            "$1 really gets to you. What makes it hit so hard?",
            "That makes sense—$1 sounds tough to be around.",
            "You can note what happens for you with $1."
        ], 4)
        add("disgust.2", #"\b(?:gross|disgust(?:ed|ing)|nasty)\b(?:[^.!?]*)"#, [
            "That didn’t sit right. You can put words to it here.",
            "It’s okay to say how that felt in your body.",
            "One small detail you want to remember?"
        ], 3, false)

        // ===== Avoidance / disclosure / minimizing =====
        add("avoid.1", #"\bI(?:'ve| have) been avoiding (.+?)"#, [
            "Avoiding $1 might be trying to protect something. Is there more you’d like to say?",
            "$1—what do you think keeps you from going there?",
            "When you think about $1, what shows up right now?"
        ], 5)
        add("disclose.1", #"\bI (?:don't|do not) usually talk about (.+?)"#, [
            "$1 sounds important. You can say a bit more if you want.",
            "It’s okay to open up about $1 here.",
            "You can stay with $1 for a moment."
        ], 5)
        add("minimize.1", #"\bI guess it (?:doesn't|does not) matter, but (.+?)"#, [
            "$1—you brought it up for a reason. Is there more you’d like to say about that?",
            "Even if it feels small, $1 might be worth noting.",
            "What made you want to include $1?"
        ], 4)

        // ===== Positive / gratitude / pride =====
        add("grat.1", #"\bI(?:'m| am) grateful (?:for|that) (.+?)"#, [
            "That’s something you appreciate—want to keep a note of it?",
            "Gratitude for $1—anything else you want to remember?",
            "You can hold onto that if it helps."
        ], 4)
        add("pride.1", #"\bI(?:'m| am) proud (?:of|that) (.+?)"#, [
            "That took effort—what part are you most proud of?",
            "Feels good to name that. You can add a line if you like.",
            "Nice to own that win."
        ], 5) // +1 weight
        add("pride.2", #"\bfelt (?:proud|good) (?:about|that)\b([^.!?]*)"#, [
            "That took something from you—what part feels most meaningful?",
            "You can keep a note of what made you feel proud there.",
            "What do you want to remember about that?"
        ], 5)

        // ===== Time & change =====
        add("always.1", #"\bit always (.+?)"#, [
            "Always $1—has it felt that way for a long time?",
            "$1 keeps showing up. Anything new you’ve noticed?",
            "When it $1, how do you usually respond?"
        ], 3)
        add("sometimes.1", #"\bsometimes (.+?)"#, [
            "Sometimes $1—what’s that like when it happens?",
            "You said sometimes $1. What about when it doesn’t?",
            "You can note a small example."
        ], 2)

        // ===== Relationship figures (neutral tone) — non-greedy capture =====
        add("rel.mother", #"\bmy mother(.*?$)"#, [
            "Your mother$1—how does that sit with you right now?",
            "If it helps, say a bit more about your mother$1.",
            "You can stay with that here."
        ], 5)
        add("rel.father", #"\bmy father(.*?$)"#, [
            "Talking about your father$1—what’s present for you right now?",
            "You can put a few words to that if you want.",
            "Feel free to stay with that."
        ], 5)
        add("rel.partner", #"\bmy (?:partner|spouse|husband|wife)(.*?$)"#, [
            "That’s part of your relationship. What stands out in this moment?",
            "You can capture one detail about your partner$1.",
            "Anything you want to remember about this?"
        ], 5)

        // ===== Work / study =====
        add("work.1", #"\b(?:my )?work(.*?$)"#, [
            "That part of work keeps showing up for you. Is there more you’d like to say?",
            "You can name the bit of work that’s loudest right now.",
            "One small detail about work you want to capture?"
        ], 3)
        add("school.1", #"\b(?:school|class|homework|study)(.*?$)"#, [
            "That’s part of learning for you. Anything you want to note?",
            "You can write a line about what stood out.",
            "What do you want to remember from this?"
        ], 3)

        // ===== Health / sleep =====
        add("health.1", #"\b(?:health|doctor|sick|ill|diagnos|symptom|medicine|hospital)(.*?$)"#, [
            "That’s a lot for your body to hold. Anything you want to capture about it today?",
            "You can put a few words to how that felt physically.",
            "If it helps, note one detail you want to remember."
        ], 4)
        add("sleep.1", #"\b(?:sleep|insomnia|nap|rest|tired)(.*?$)"#, [
            "Rest has a way of coloring the day. Anything else you want to say?",
            "You can note how sleep played into today.",
            "One small detail about rest you want to keep?"
        ], 3)

        // ===== Meta / uncertainty =====
        add("idk.1", #"\bI (?:do n't|don't|do not) know(.*?$)"#, [
            "It’s okay not to know$1. That’s part of it.",
            "Not knowing$1 is a valid place to be.",
            "You don’t have to have it figured out right now."
        ], 4)

        // ===== Programmatic expansions (non-greedy where splicing) =====
        let becauseTargets = ["because (.+?)", "since (.+?)", "as (.+?)"]
        for (i, pat) in becauseTargets.enumerated() {
            add("cause.\(i)", "\\b" + pat, [
                "$1—yeah, that adds up.",
                "That seems relevant. Is there more you’d like to say about $1?",
                "Do you think there’s more behind $1?",
            ], 3)
        }

        let disbeliefTargets = ["I can't believe I (.+?)", "I can’t believe I (.+?)"]
        for (i, pat) in disbeliefTargets.enumerated() {
            add("disbelief.\(i)", "\\b" + pat, [
                "$1—it sounds like that moment still echoes in you.",
                "You said you can’t believe you $1. Would you like to explore that more?",
                "Sometimes it’s hard to hold moments like $1.",
            ], 5)
        }

        let wishTargets = ["I wish (.+?)", "I’ve always wanted to (.+?)", "I always wanted to (.+?)"]
        for (i, pat) in wishTargets.enumerated() {
            add("wish.\(i)", "\\b" + pat, [
                "$1—that’s something real. Is there more you’d like to say?",
                "You can stay with that wish for a bit, if it helps.",
                "What does $1 mean to you right now?",
            ], 4)
        }

        let loopTargets = ["I keep (.+?)", "I kept (.+?)", "I’m trying to (.+?)"]
        for (i, pat) in loopTargets.enumerated() {
            add("loop.\(i)", "\\b" + pat, [
                "$1 keeps showing up. One detail you want to note?",
                "You can write a line about how $1 shows up.",
                "What stands out to you about $1 today?",
            ], 3)
        }

        // ===== Mixed emotion detector (Phase 4): "but also / at the same time" =====
        add("mixed.1", #"(?:but also|at the same time)\b(?:[^.!?]*)"#, [
            "A few things at once—what’s standing out most?",
            "You can keep both sides here. Which part feels loudest?",
            "If it helps, write one line for each part."
        ], 6, false) // higher weight

        rules = built
    }

    // MARK: - Fallbacks (emotion + domain)
    // Phase 4: lightly tuned Neutral/Mixed phrasing (others kept from prior iteration).

    private let fallbackByEmotion: [Int: [String]] = [
        1: [ // Joy
            "That feels like something to appreciate.",
            "You’re noticing something meaningful—want to hold onto it?",
            "Nice—what part do you want to remember?",
            "A bright spot—what made it land that way?",
            "You can keep a small note of that win."
        ],
        2: [ // Sadness
            "That might be something worth staying with.",
            "Take your time—this is just for you.",
            "You can put a few words to that here.",
            "If it helps, name one small moment from it.",
            "You can stay close to that feeling for a bit."
        ],
        3: [ // Anger
            "That really got under your skin.",
            "You can say it plainly here.",
            "What part keeps replaying?",
            "If it helps, write the moment that crossed a line."
        ],
        4: [ // Fear
            "You’re safe to say anything here.",
            "One ‘what if’ you want to name?",
            "It’s okay if this doesn’t make total sense yet.",
            "You can write what comes up as you think of it."
        ],
        5: [ // Surprise
            "That caught your attention—want to stay with it?",
            "One thing you didn’t expect?",
            "Interesting—what do you make of that?",
            "You can jot what stood out most."
        ],
        6: [ // Disgust
            "That didn’t sit right.",
            "You don’t need to hold that back here.",
            "You can note what felt off.",
            "If it helps, write one detail you noticed."
        ],
        7: [ // Neutral (tuned)
            "Which part feels most worth keeping?",
            "One small detail you might want to remember?",
            "What thread do you notice as you say this?",
            "You can add a line if that helps you think.",
            "Is there a small moment from this you want to keep?",
            "What feels most present right now?",
            "You can stay with this for a moment."
        ],
        8: [ // Mixed (tuned)
            "A few things at once—what’s standing out most?",
            "You can keep both sides here. Which part feels loudest?",
            "If it helps, write one line for each part.",
            "What’s the pull in each direction?",
            "You can untangle it here, one thread at a time.",
            "What do you want to remember about this mix?"
        ],
    ]

    private let domainFallbackPools: [String: [String]] = [
        "Work": [
            "That part of work keeps showing up for you. Is there more you’d like to say?",
            "If it helps, name the bit of work that’s loudest right now.",
            "One small detail about work you want to capture?",
            "Work can get loud—what part stands out today?",
            "You could keep a note on how that played out.",
            "What’s the thread at work you notice most right now?",
            "How did that land for you at work today?",
            "A small moment from work worth remembering?",
            "You can put a few words to how that felt at work."
        ],
        "Relationships": [
            "That’s part of your relationship story. What stands out to you in this moment?",
            "If you want, name one moment that captures it.",
            "You can put a few words to how that felt.",
            "You can keep a note on what mattered most there."
        ],
        "Family": [
            "Family can carry a lot. Is there anything else you want to put into words?",
            "You can stay with that family thread for a bit.",
            "What part of this feels most present right now?",
            "One small family moment you want to remember?"
        ],
        "Health": [
            "That’s a lot for your body to hold. Anything you want to capture about it today?",
            "You can note how it felt physically.",
            "One detail you want to remember?",
            "You can add a line about what your body noticed."
        ],
        "Money": [
            "That sounds like a real consideration.",
            "You can note one practical detail about it.",
            "What feels most present about it right now?",
            "One small step you want to keep in mind?"
        ],
        "Sleep": [
            "Rest has a way of coloring the day. Anything else you want to say?",
            "You can note how sleep played into today.",
            "One small detail about rest you want to keep?",
            "How did your rest shape the day?",
            "You can jot how your energy felt.",
            "What do you want to remember about sleep today?",
            "You can add one line about rest and mood."
        ],
        "Creativity": [
            "That’s part of your creative thread.",
            "What do you want to remember about it?",
            "You can note one small step you took.",
            "How did creating leave you feeling?"
        ],
    ]

    // MARK: - Utilities (punctuation, capture cleaning, recall formatting, diagnostics)

    fileprivate enum Punctuation {
        /// Collapse multiple spaces, trim, collapse repeated terminal punctuation, normalize spaces before punctuation.
        static func tidy(_ s: String) -> String {
            var out = s.replacingOccurrences(of: #"[\u2018\u2019]"#, with: "'", options: .regularExpression)
            out = out.replacingOccurrences(of: #"[\u201C\u201D]"#, with: "\"", options: .regularExpression)
            out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            out = out.replacingOccurrences(of: #"(\s+)([,.!?])"#, with: "$2", options: .regularExpression)
            out = out.replacingOccurrences(of: #"[.!?]{2,}$"#, with: ".", options: .regularExpression)
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        static func ensurePeriod(_ s: String) -> String {
            guard !s.isEmpty else { return s }
            if s.hasSuffix("!") || s.hasSuffix("?") || s.hasSuffix(".") { return s }
            return s + "."
        }
    }

    fileprivate enum CaptureSanitizer {
        static func clean(_ s: String) -> String {
            var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove duplicated leading punctuation spaces like ",  and"
            out = out.replacingOccurrences(of: #"^,\s*"#, with: ", ", options: .regularExpression)
            // Avoid trailing sentence punctuation that would double-up with host punctuation
            out = out.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
            // Collapse inner multiple spaces
            out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            return out
        }
    }

    fileprivate enum RecallFormatter {
        /// Convert a first-person snippet into a second-person, no-quotes sentence.
        static func toSecondPerson(from snippet: String) -> String {
            var s = stripQuotes(snippet)

            // Ordered replacements with word boundaries; case-insensitive.
            s = rep(s, #"\bI was\b"#, "you were")
            s = rep(s, #"\bI am\b"#, "you are")
            s = rep(s, #"\bI'm\b"#, "you're")
            s = rep(s, #"\bI've\b"#, "you've")
            s = rep(s, #"\bI'd\b"#, "you'd")
            s = rep(s, #"\bI'll\b"#, "you'll")
            s = rep(s, #"\bMy\b"#, "Your")
            s = rep(s, #"\bmy\b"#, "your")
            s = rep(s, #"\bMine\b"#, "Yours")
            s = rep(s, #"\bmine\b"#, "yours")
            s = rep(s, #"\bMe\b"#, "You")
            s = rep(s, #"\bme\b"#, "you")
            s = rep(s, #"\bI\b"#, "you") // keep last

            s = ActiveListenerEnginePro.Punctuation.tidy(s)
            return s
        }

        private static func stripQuotes(_ s: String) -> String {
            var out = s
            let quoteChars = CharacterSet(charactersIn: "\"'“”‘’")
            out = out.trimmingCharacters(in: quoteChars.union(.whitespacesAndNewlines))
            out = out.replacingOccurrences(of: #"^['"“”‘’](.*)['"“”‘’]$"#, with: "$1", options: .regularExpression)
            return out
        }
        private static func rep(_ s: String, _ pattern: String, _ replacement: String) -> String {
            let rx = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: (s as NSString).length)
            return rx.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: replacement)
        }
    }

    // MARK: - Stage 3 Diagnostics (grammar/punctuation/capitalization counters)

    public enum Diagnostics {
        /// Evaluate a list of ALR strings and return aggregate issue counts.
        /// - Returns: (grammar, punctuation, capitalization)
        public static func evaluate(alrs: [String]) -> (grammar: Int, punctuation: Int, capitalization: Int) {
            var g = 0, p = 0, c = 0
            for s in alrs {
                g += grammarIssues(in: s)
                p += punctuationIssues(in: s)
                c += capitalizationIssues(in: s)
            }
            return (g, p, c)
        }

        // Very lightweight, explainable heuristics (deterministic, offline).
        private static func grammarIssues(in s: String) -> Int {
            var count = 0
            let checks: [String] = [
                #"\byou was\b"#,      // pronoun agreement
                #"\byou is\b"#,
                #"\bthe the\b"#,      // duplicate determiners
                #"\ba a\b"#,
                #"\ban an\b"#,
                #"\bcan can\b"#,
                #"\bto to\b"#,
            ]
            for pat in checks {
                count += regexCount(s, pat)
            }
            return count
        }

        private static func punctuationIssues(in s: String) -> Int {
            var count = 0
            let checks: [String] = [
                #"\.\."#,           // double periods
                #"[!?]{2,}"#,       // repeated ! or ?
                #"\s+[,.!?]"#,      // space before punctuation
                #"['“”‘’][^'“”‘’]*$"#, // unmatched opening quote to end
            ]
            for pat in checks { count += regexCount(s, pat) }
            // Missing terminal punctuation (simple): count 1 if ends without .!?
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !s.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".") &&
               !s.hasSuffix("!") && !s.hasSuffix("?") {
                count += 1
            }
            return count
        }

        private static func capitalizationIssues(in s: String) -> Int {
            var count = 0
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // If first visible letter is lowercase (and not starting with quote)
                if let firstLetter = trimmed.first(where: { $0.isLetter }) {
                    if firstLetter.isLowercase && !"\"'“”‘’".contains(trimmed.first!) {
                        count += 1
                    }
                }
                // Lone lowercase " i " as pronoun (not in "i'm")
                count += regexCount(s, #"(?<![A-Za-z])i(?![A-Za-z])"#)
            }
            return count
        }

        private static func regexCount(_ s: String, _ pattern: String) -> Int {
            let rx = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: (s as NSString).length)
            return rx.numberOfMatches(in: s, options: [], range: range)
        }
    }
}
