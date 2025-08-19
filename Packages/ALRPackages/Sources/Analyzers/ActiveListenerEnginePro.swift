// ActiveListenerEnginePro.swift
//
// Phase 5 build (2025-08-19) — visible run-tag + capture boundary fixes.
//
// New in Phase 5:
// • Whole‑word capture snapping (expand capture ranges to token boundaries).
// • Capture length guard (<3 chars ⇒ fallback to non-splice variant).
// • Recall snippet normalizer: "Earlier you mentioned that yesterday, your…"
// • Clearer interrogative fallbacks ("What's one …") and lighter generic cooldown.
// • Every output is prefixed with "[ph5] " to verify correct build is running.
//
// Notes
// • Fully offline/deterministic. No ML, no network.
// • Builds on Phases 1–4: recall rewrite/gating, repetition controls, capture hygiene.

import Foundation

public final class ActiveListenerEnginePro {
    public static let shared = ActiveListenerEnginePro()
    private init() { buildRules() }

    // MARK: - Config

    private let snippetMax: Int = 120
    private let recentHistoryLimit: Int = 16
    private let variantCooldown: Int = 6                 // from Phase 2
    private let similarityRejectThreshold: Double = 0.45 // from Phase 2
    private let domainUseThreshold: Double = 0.45
    private let lastSentenceBonus: Int = 2

    // Recall gating (Phase 1)
    private let recallMinLen = 12
    private let recallMaxLen = 140
    private let recallCooldownSteps = 3
    private var stepCounter: Int = 0
    private var lastRecallStep: Int? = nil

    // Fallback family cooldown
    private let familyCooldownWindow = 4
    private var recentFamilyHistory: [String] = []

    // Additional cooldown key for generic-open prompts
    private let genericOpenFamilyKey = "fb:open"

    // MARK: - Model

    private struct Rule {
        let key: String
        let regex: NSRegularExpression
        let responses: [TemplateVariant]   // Phase 5: variants can be capture/non-capture aware
        let weight: Int
        let specificity: Int
        let sanitizeCaptures: Bool
    }

    /// Template variant that may or may not require captures.
    private struct TemplateVariant {
        let text: String                 // may include $1..$9
        let requiresCapture: Bool        // if true, needs a valid (length >=3) capture to sound natural
    }

    private var rules: [Rule] = []
    private var memory: [String] = [] // recent user snippets (trimmed)

    // Repetition control
    private var recentResponseHistory: [String] = []
    private var usedVariantIndices: [String: [Int]] = [:] // key -> recent variant indices

    // MARK: - Public API

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

        // 1) Rule-based reply
        if let reply = ruleBasedReply(for: cleaned) {
            trackMemory(cleaned)
            return withPhaseTag(reply)
        }

        // 2) Recall (gated)
        if let recall = tryRecall(currentInput: cleaned) {
            trackMemory(cleaned)
            recordFamilyUse("recall")
            return withPhaseTag(recall)
        }

        // 3) Domain fallback
        if let (d, s) = domains?.max(by: { $0.1 < $1.1 }), s >= domainUseThreshold,
           let pool = domainFallbackPools[d],
           canUseFamily("dom:\(d)")
        {
            let line = chooseVariant(from: pool, key: "dom:\(d)")
            recordFamilyUse("dom:\(d)")
            trackMemory(cleaned)
            return withPhaseTag(line)
        }

        // 4) Emotion fallback
        if let pool = fallbackByEmotion[emotion], canUseFamily("fb:\(emotion)") {
            let line = chooseVariant(from: pool, key: "fb:\(emotion)")
            recordFamilyUse("fb:\(emotion)")
            trackMemory(cleaned)
            return withPhaseTag(line)
        }

        // 5) Generic open-ended (cooled down)
        if canUseFamily(genericOpenFamilyKey) {
            let line = chooseVariant(from: genericOpenFallbacks, key: genericOpenFamilyKey)
            recordFamilyUse(genericOpenFamilyKey)
            trackMemory(cleaned)
            return withPhaseTag(line)
        }

        // Final ultra-safe neutral last resort
        let line = withPhaseTag("You can say more if you want.")
        trackMemory(cleaned)
        return line
    }

    // MARK: - Phase Tag

    private func withPhaseTag(_ text: String) -> String {
        return "[ph5] " + text
    }

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

                // Assemble candidate from variants with capture-awareness
                if let candidate = assembleCandidate(rule: rule, sentence: sentence, match: match) {
                    var score = rule.weight + rule.specificity
                    if pos == 1 { score += lastSentenceBonus }
                    if best == nil || score > best!.score {
                        best = (candidate, score)
                    }
                }
            }
            if best != nil { break }
        }
        return best?.response
    }

    // MARK: - Assemble with capture snapping + guards (Phase 5)

    private func assembleCandidate(rule: Rule, sentence: String, match: NSTextCheckingResult) -> String? {
        // Decide variant while considering capture viability
        let viableVariants = rule.responses.enumerated().filter { (idx, tv) in
            if tv.requiresCapture == false { return true }
            // requires capture: ensure we actually have a usable capture later
            for i in 1 ..< match.numberOfRanges {
                let r = match.range(at: i)
                if r.location != NSNotFound, usableCapture(in: sentence, range: r) != nil { return true }
            }
            return false
        }

        let pool = viableVariants.isEmpty ? rule.responses.enumerated() : viableVariants
        let (chosenIndex, variant) = pool.randomElement().map { ($0.offset, $0.element) } ?? (0, rule.responses[0])

        var out = variant.text

        // Substitute captures with word-boundary snapping + sanitation
        if match.numberOfRanges > 1 {
            for i in 1 ..< match.numberOfRanges {
                let placeholder = "$\(i)"
                if out.contains(placeholder) {
                    if let snapped = usableCapture(in: sentence, range: match.range(at: i)) {
                        out = spliceWithContextAwareSpacer(host: out, captureToken: placeholder, capture: snapped)
                    } else {
                        // Capture too short / unusable → strip token gracefully
                        out = out.replacingOccurrences(of: placeholder, with: "")
                    }
                }
            }
        }

        out = Punctuation.tidy(out)
        out = Punctuation.ensurePeriod(out)
        return out
    }

    /// Return a sanitized capture expanded to word boundaries, or nil if < 3 chars after cleaning.
    private func usableCapture(in sentence: String, range: NSRange) -> String? {
        guard let expanded = expandToWordBoundaries(sentence: sentence, range: range) else { return nil }
        var cleaned = CaptureSanitizer.clean(expanded)
        // Guard: reject ultra-short captures
        if cleaned.replacingOccurrences(of: " ", with: "").count < 3 { return nil }
        return cleaned
    }

    /// Expand an NSRange to nearest word boundaries in the given sentence.
    private func expandToWordBoundaries(sentence: String, range: NSRange) -> String? {
        let ns = sentence as NSString
        var start = range.location
        var len = range.length
        if start == NSNotFound { return nil }
        if start + len > ns.length { len = ns.length - start }

        // Extend left while previous char is a letter/number (inside a word)
        while start > 0 {
            let prevRange = NSRange(location: start - 1, length: 1)
            let ch = ns.substring(with: prevRange)
            if ch.range(of: #"\w"#, options: .regularExpression) != nil {
                start -= 1
                len += 1
            } else { break }
        }
        // Extend right while next char is a letter/number
        while start + len < ns.length {
            let nextRange = NSRange(location: start + len, length: 1)
            let ch = ns.substring(with: nextRange)
            if ch.range(of: #"\w"#, options: .regularExpression) != nil {
                len += 1
            } else { break }
        }

        let snapped = ns.substring(with: NSRange(location: start, length: len))
        return snapped
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

    // MARK: - Context-aware splice (Phase 3), reused in Phase 5

    private func spliceWithContextAwareSpacer(host: String, captureToken: String, capture: String) -> String {
        guard let range = host.range(of: captureToken) else {
            return host.replacingOccurrences(of: captureToken, with: capture)
        }
        let prefix = String(host[..<range.lowerBound])
        let suffix = String(host[range.upperBound...])

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

    // MARK: - Recall (with pronoun shift & snippet normalizer)

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

        var shifted = RecallFormatter.toSecondPerson(from: snippet)
        shifted = normalizeRecallLead(shifted)

        let cleaned = Punctuation.ensurePeriod( Punctuation.tidy(shifted) )
        let variants = [
            "Earlier you mentioned \(cleaned) What feels most present about that now?",
            "Earlier you mentioned \(cleaned) You can add a line or two if you want.",
            "Earlier you mentioned \(cleaned) Does anything new come up as you think about it?"
        ]

        lastRecallStep = stepCounter
        return chooseVariant(from: variants, key: "recall")
    }

    /// If snippet starts with (yesterday|today|tonight|this|that|your|my|our|the), insert "that " and lowercase first token.
    private func normalizeRecallLead(_ s: String) -> String {
        let lowers = ["yesterday","today","tonight","this","that","your","my","our","the"]
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(separator: " ").first.map(String.init) else { return s }
        let plainFirst = first.trimmingCharacters(in: CharacterSet.punctuationCharacters).lowercased()
        if lowers.contains(plainFirst) {
            // Lowercase first token and prefix with "that "
            let rest = String(trimmed.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
            let loweredFirst = first.lowercased()
            return "that " + loweredFirst + (rest.isEmpty ? "" : " " + rest)
        }
        return s
    }

    // MARK: - Rule factory (Phases 3–5)

    private func buildRules() {
        var built: [Rule] = []

        func rx(_ pattern: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: opts)
        }
        func TV(_ text: String, _ needsCap: Bool = true) -> TemplateVariant {
            TemplateVariant(text: text, requiresCapture: needsCap)
        }
        func add(_ key: String, _ pattern: String, _ responses: [TemplateVariant], _ weight: Int, _ sanitize: Bool = true) {
            let captures = max(0, pattern.filter { $0 == "(" }.count - pattern.filter { $0 == "\\" }.count)
            let spec = weight + min(3, captures)
            built.append(Rule(key: key, regex: rx(pattern), responses: responses, weight: weight, specificity: spec, sanitizeCaptures: sanitize))
        }

        // ===== Core feelings (non-greedy, with alt non-capture variants) =====
        add("feel.1", #"\bI feel like (.+?)"#, [
            TV("$1—that’s something you’ve noticed. Is there more you’d like to say?"),
            TV("That’s something you’ve noticed. Is there more you’d like to say?", false)
        ], 4)

        add("feel.2", #"\bI feel (.+?)"#, [
            TV("$1—what’s that like for you right now?"),
            TV("What’s that like for you right now?", false)
        ], 4)

        add("think.1", #"\bI think (.+?)"#, [
            TV("$1—that’s a thought worth noting."),
            TV("That’s a thought worth noting.", false)
        ], 2)

        // ===== Desire / intention =====
        add("want.1", #"\bI want to (.+?)"#, [
            TV("You want to $1. What draws you toward that?"),
            TV("What draws you toward that?", false)
        ], 3)
        add("want.2", #"\bI want (.+?)"#, [
            TV("You want $1. Is there more you’d like to say?"),
            TV("Is there more you’d like to say?", false)
        ], 3)

        // ===== Regret / counterfactuals =====
        add("regret.1", #"\bI regret (.+?)"#, [
            TV("That regret—$1. What sticks with you most?"),
            TV("That regret—what sticks with you most?", false)
        ], 5)
        add("ifonly.1", #"\bif only I had (.+?)"#, [
            TV("“If only I had $1”—there’s something there. Is there more you’d like to say?"),
            TV("There’s something there. Is there more you’d like to say?", false)
        ], 5)

        // ===== Fear / worry =====
        add("fear.1", #"\bI(?:'m| am) afraid(?: of)? (.+?)"#, [
            TV("$1 sounds scary. If it helps, put a few words to it."),
            TV("That sounds scary. If it helps, put a few words to it.", false)
        ], 5)
        add("worry.1", #"\bI (?:worry|worrying|am worried|I'm worried) (?:about|that) (.+?)"#, [
            TV("Worry about $1 can take up space. What’s one line you want to capture?"),
            TV("That worry can take up space. What’s one line you want to capture?", false)
        ], 4)

        // ===== Sadness / loss =====
        add("sad.1", #"\bI (?:miss|am missing) (.+?)"#, [
            TV("Missing $1—what do you notice in yourself as you say that?"),
            TV("Missing that—what do you notice in yourself as you say that?", false)
        ], 5)
        add("sad.2", #"\bI (?:feel )?lonely\b(?:[^.!?]*)"#, [
            TV("Feeling lonely can be heavy. What part weighs most right now?", false),
            TV("You can put a few words to that feeling here.", false),
            TV("Short phrases are enough.", false)
        ], 4, false)

        // ===== Anger / frustration =====
        add("anger.1", #"\bI (?:am|I'm) (?:angry|furious|mad) (?:at|about)? (.+?)"#, [
            TV("That really got under your skin: $1. You can say more if you want."),
            TV("That really got under your skin. You can say more if you want.", false)
        ], 4)
        add("anger.2", #"\b(?:unfair|betray(?:ed|al)|crossed a line)\b(?:[^.!?]*)"#, [
            TV("That felt unfair. What’s one detail you want to keep?", false),
            TV("If you want, name the moment that crossed a line.", false),
            TV("You can write what didn’t sit right.", false)
        ], 4, false)
        add("frustration.1", #"\b(frustrat(?:ed|ing)|annoy(?:ed|ing))\b(?:[^.!?]*)"#, [
            TV("That sounded frustrating. What part stuck with you?", false),
            TV("You can put a line to what felt most annoying about it.", false),
            TV("What was the hardest bit there?", false)
        ], 5, false)

        // ===== Disgust / aversion =====
        add("disgust.1", #"\bcan't stand (.+?)"#, [
            TV("$1 really gets to you. What makes it hit so hard?"),
            TV("That really gets to you. What makes it hit so hard?", false)
        ], 4)
        add("disgust.2", #"\b(?:gross|disgust(?:ed|ing)|nasty)\b(?:[^.!?]*)"#, [
            TV("That didn’t sit right. You can put words to it here.", false),
            TV("It’s okay to say how that felt in your body.", false),
            TV("What’s one small detail you want to remember?", false)
        ], 3, false)

        // ===== Avoidance / disclosure / minimizing =====
        add("avoid.1", #"\bI(?:'ve| have) been avoiding (.+?)"#, [
            TV("Avoiding $1 might be trying to protect something. Is there more you’d like to say?"),
            TV("That might be trying to protect something. Is there more you’d like to say?", false)
        ], 5)
        add("disclose.1", #"\bI (?:don't|do not) usually talk about (.+?)"#, [
            TV("$1 sounds important. You can say a bit more if you want."),
            TV("That sounds important. You can say a bit more if you want.", false)
        ], 5)
        add("minimize.1", #"\bI guess it (?:doesn't|does not) matter, but (.+?)"#, [
            TV("$1—you brought it up for a reason. Is there more you’d like to say about that?"),
            TV("You brought it up for a reason. Is there more you’d like to say about that?", false)
        ], 4)

        // ===== Positive / gratitude / pride =====
        add("grat.1", #"\bI(?:'m| am) grateful (?:for|that) (.+?)"#, [
            TV("That’s something you appreciate—want to keep a note of it?"),
            TV("That’s something you appreciate—want to keep a note of it?", false)
        ], 4)
        add("pride.1", #"\bI(?:'m| am) proud (?:of|that) (.+?)"#, [
            TV("That took effort—what part are you most proud of?"),
            TV("That took effort—what part are you most proud of?", false)
        ], 5)
        add("pride.2", #"\bfelt (?:proud|good) (?:about|that)\b([^.!?]*)"#, [
            TV("You can keep a note of what made you feel proud there.", false),
            TV("What do you want to remember about that?", false)
        ], 5)

        // ===== Time & change =====
        add("always.1", #"\bit always (.+?)"#, [
            TV("Always $1—has it felt that way for a long time?"),
            TV("Has it felt that way for a long time?", false)
        ], 3)
        add("sometimes.1", #"\bsometimes (.+?)"#, [
            TV("Sometimes $1—what’s that like when it happens?"),
            TV("What’s that like when it happens?", false)
        ], 2)

        // ===== Relationship figures =====
        add("rel.mother", #"\bmy mother(.*?$)"#, [
            TV("Your mother$1—how does that sit with you right now?", false),
            TV("If it helps, say a bit more about your mother$1.", false),
            TV("You can stay with that here.", false)
        ], 5)
        add("rel.father", #"\bmy father(.*?$)"#, [
            TV("Talking about your father$1—what’s present for you right now?", false),
            TV("You can put a few words to that if you want.", false),
            TV("Feel free to stay with that.", false)
        ], 5)
        add("rel.partner", #"\bmy (?:partner|spouse|husband|wife)(.*?$)"#, [
            TV("That’s part of your relationship. What stands out in this moment?", false),
            TV("You can capture one detail about your partner$1.", false),
            TV("Anything you want to remember about this?", false)
        ], 5)

        // ===== Work / study =====
        add("work.1", #"\b(?:my )?work(.*?$)"#, [
            TV("That part of work keeps showing up for you. Is there more you’d like to say?", false),
            TV("If it helps, name the bit of work that’s loudest right now.", false),
            TV("What’s one small detail about work you want to capture?", false)
        ], 3)
        add("school.1", #"\b(?:school|class|homework|study)(.*?$)"#, [
            TV("That’s part of learning for you. Anything you want to note?", false),
            TV("You can write a line about what stood out.", false),
            TV("What do you want to remember from this?", false)
        ], 3)

        // ===== Health / sleep =====
        add("health.1", #"\b(?:health|doctor|sick|ill|diagnos|symptom|medicine|hospital)(.*?$)"#, [
            TV("That’s a lot for your body to hold. Anything you want to capture about it today?", false),
            TV("You can put a few words to how that felt physically.", false),
            TV("If it helps, note one detail you want to remember.", false)
        ], 4)
        add("sleep.1", #"\b(?:sleep|insomnia|nap|rest|tired)(.*?$)"#, [
            TV("Rest has a way of coloring the day. Anything else you want to say?", false),
            TV("You can note how sleep played into today.", false),
            TV("What’s one small detail about rest you want to keep?", false)
        ], 3)

        // ===== Meta / uncertainty =====
        add("idk.1", #"\bI (?:do n't|don't|do not) know(.*?$)"#, [
            TV("It’s okay not to know$1. That’s part of it.", false),
            TV("Not knowing$1 is a valid place to be.", false),
            TV("You don’t have to have it figured out right now.", false)
        ], 4)

        // ===== Programmatic expansions =====
        let becauseTargets = ["because (.+?)", "since (.+?)", "as (.+?)"]
        for (i, pat) in becauseTargets.enumerated() {
            add("cause.\(i)", "\\b" + pat, [
                TV("$1—yeah, that adds up."),
                TV("Yeah, that adds up.", false),
                TV("That seems relevant. What’s one thing you’d add?", false),
            ], 3)
        }

        let disbeliefTargets = ["I can't believe I (.+?)", "I can’t believe I (.+?)"]
        for (i, pat) in disbeliefTargets.enumerated() {
            add("disbelief.\(i)", "\\b" + pat, [
                TV("$1—it sounds like that moment still echoes in you."),
                TV("It sounds like that moment still echoes in you.", false),
                TV("Sometimes it’s hard to hold moments like that.", false),
            ], 5)
        }

        let wishTargets = ["I wish (.+?)", "I’ve always wanted to (.+?)", "I always wanted to (.+?)"]
        for (i, pat) in wishTargets.enumerated() {
            add("wish.\(i)", "\\b" + pat, [
                TV("$1—that’s something real. Is there more you’d like to say?"),
                TV("That’s something real. Is there more you’d like to say?", false),
                TV("What does that mean to you right now?", false),
            ], 4)
        }

        let loopTargets = ["I keep (.+?)", "I kept (.+?)", "I’m trying to (.+?)"]
        for (i, pat) in loopTargets.enumerated() {
            add("loop.\(i)", "\\b" + pat, [
                TV("$1 keeps showing up. What’s one detail you want to note?"),
                TV("That keeps showing up. What’s one detail you want to note?", false),
                TV("What stands out to you about it today?", false),
            ], 3)
        }

        // ===== Mixed emotion detector =====
        add("mixed.1", #"(?:but also|at the same time)\b(?:[^.!?]*)"#, [
            TV("A few things at once—what’s standing out most?", false),
            TV("You can keep both sides here. Which part feels loudest?", false),
            TV("If it helps, write one line for each part.", false)
        ], 6, false)

        rules = built
    }

    // MARK: - Fallbacks (emotion + domain + generic open)

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
            "What’s one ‘what if’ you want to name?",
            "It’s okay if this doesn’t make total sense yet.",
            "You can write what comes up as you think of it."
        ],
        5: [ // Surprise
            "That caught your attention—want to stay with it?",
            "What’s one thing you didn’t expect?",
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
            "What’s one small detail you might want to remember?",
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

    // Generic open-ended prompts with explicit interrogatives (Phase 5)
    private let genericOpenFallbacks: [String] = [
        "What’s one thing you want to remember about this?",
        "What’s one small detail you want to remember?",
        "What feels most present right now?",
        "You can add a line if you want."
    ]

    // MARK: - Utilities

    fileprivate enum Punctuation {
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
            out = out.replacingOccurrences(of: #"^,\s*"#, with: ", ", options: .regularExpression)
            out = out.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
            out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            return out
        }
    }

    fileprivate enum RecallFormatter {
        static func toSecondPerson(from snippet: String) -> String {
            var s = stripQuotes(snippet)
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
            s = rep(s, #"\bI\b"#, "you")
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

    // MARK: - Diagnostics (unchanged API from Phase 4; optional for your rig)

    public enum Diagnostics {
        public static func evaluate(alrs: [String]) -> (grammar: Int, punctuation: Int, capitalization: Int) {
            var g = 0, p = 0, c = 0
            for s in alrs {
                g += grammarIssues(in: s)
                p += punctuationIssues(in: s)
                c += capitalizationIssues(in: s)
            }
            return (g, p, c)
        }
        private static func grammarIssues(in s: String) -> Int {
            var count = 0
            let checks: [String] = [
                #"\byou was\b"#, #"\byou is\b"#, #"\bthe the\b"#,
                #"\ba a\b"#, #"\ban an\b"#, #"\bcan can\b"#, #"\bto to\b"#
            ]
            for pat in checks { count += regexCount(s, pat) }
            return count
        }
        private static func punctuationIssues(in s: String) -> Int {
            var count = 0
            let checks: [String] = [
                #"\.\."#, #"[!?]{2,}"#, #"\s+[,.!?]"#, #"['“”‘’][^'“”‘’]*$"#
            ]
            for pat in checks { count += regexCount(s, pat) }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !t.hasSuffix(".") && !t.hasSuffix("!") && !t.hasSuffix("?") { count += 1 }
            return count
        }
        private static func capitalizationIssues(in s: String) -> Int {
            var count = 0
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                if let firstLetter = t.first(where: { $0.isLetter }),
                   firstLetter.isLowercase && !"\"'“”‘’".contains(t.first!) { count += 1 }
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
