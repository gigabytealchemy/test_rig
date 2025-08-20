// ActiveListenerEngine.swift
// Phase 6.0 (2025-08-20)

import Foundation

public final class ActiveListenerEngine {
  public static let shared = ActiveListenerEngine()
  private init() {
    self.rules = buildRules()
  }

  // MARK: - Public API

  /// emotion: 1 Joy, 2 Sadness, 3 Anger, 4 Fear, 5 Surprise, 6 Disgust, 7 Neutral, 8 Mixed
  @discardableResult
  public func respond(
    to input: String,
    emotion: Int = 7,
    domains: [(String, Double)]? = nil,
    richEmotion: Int? = nil
  ) -> String? {
    stepCounter &+= 1
    let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    // 1) Rule-based
    if let reply = ruleBasedReply(for: cleaned) {
      trackMemory(cleaned)
      return tag(reply)
    }

    // 2) Recall (gated)
    if let recall = tryRecall(
      currentInput: cleaned,
      memory: &memory,
      stepCounter: stepCounter,
      lastRecallStep: &lastRecallStep,
      recallCfg: recallCfg,
      similarityRejectThreshold: similarityRejectThreshold
    ) {
      recordFamilyUse("recall")
      trackMemory(cleaned)
      return tag(recall)
    }

    // 3) Domain fallback
    if let (dom, score) = domains?.max(by: { $0.1 < $1.1 }),
       score >= domainUseThreshold,
       let pool = domainFallbackPools[dom],
       canUseFamily("dom:\(dom)")
    {
      let line = chooseVariantDeterministic(from: pool, familyKey: "dom:\(dom)")
      recordFamilyUse("dom:\(dom)")
      trackMemory(cleaned)
      return tag(line)
    }

    // 4) Emotion fallback
    if let pool = fallbackByEmotion[emotion], canUseFamily("fb:\(emotion)") {
      let line = chooseVariantDeterministic(from: pool, familyKey: "fb:\(emotion)")
      recordFamilyUse("fb:\(emotion)")
      trackMemory(cleaned)
      return tag(line)
    }

    // 5) Generic
    if canUseFamily(genericOpenFamilyKey) {
      let line = chooseVariantDeterministic(from: genericOpenFallbacks, familyKey: genericOpenFamilyKey)
      recordFamilyUse(genericOpenFamilyKey)
      trackMemory(cleaned)
      return tag(line)
    }

    trackMemory(cleaned)
    return tag("You can say more if you want.")
  }

  // MARK: - Phase tag
  private func tag(_ text: String) -> String { "[ph6.0] " + text }

  // MARK: - Config & State

  private let snippetMax: Int = 120
  private let recentHistoryLimit: Int = 16
  private let variantCooldown: Int = 6
  private let similarityRejectThreshold: Double = 0.45
  private let domainUseThreshold: Double = 0.45
  private let lastSentenceBonus: Int = 2

  // Recall config
  private let recallCfg = RecallConfig(
    recallMinLen: 12,
    recallMaxLen: 140,
    recallCooldownSteps: 3,
    snippetMax: 120
  )

  private var stepCounter: Int = 0
  private var lastRecallStep: Int? = nil

  // Family cooldowns
  private let familyCooldownWindow = 4
  private var recentFamilyHistory: [String] = []
  private let genericOpenFamilyKey = "fb:open"

  // Repetition
  private var recentResponseHistory: [String] = []
  private var usedVariantIndices: [String: [Int]] = [:]

  // Memory of recent inputs (for recall)
  private var memory: [String] = []

  // Rules & fallbacks
  private var rules: [Rule] = []
  internal let fallbackByEmotion = emotionFallbacks
  internal let domainFallbackPools = domainFallbacks
  internal let genericOpenFallbacks = genericFallbacks

  // MARK: - Rule matching (orchestration only)

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

        if let candidate = assembleCandidate(rule: rule, sentence: sentence, match: match) {
          var score = rule.weight + rule.specificity
          if pos == 1 { score += lastSentenceBonus }
          if best == nil || score > best!.score { best = (candidate, score) }
        }
      }
      if best != nil { break }
    }
    return best?.response
  }

  private func assembleCandidate(rule: Rule, sentence: String, match: NSTextCheckingResult) -> String? {
    // Variant viability
    let viable = rule.responses.enumerated().filter { (_, tv) in
      if !tv.requiresCapture { return true }
      for i in 1 ..< match.numberOfRanges {
        let r = match.range(at: i)
        if r.location != NSNotFound, usableCapture(in: sentence, range: r) != nil { return true }
      }
      return false
    }
    let pool: [(offset: Int, element: TemplateVariant)] =
      viable.isEmpty ? Array(rule.responses.enumerated()) : viable

    // Deterministic pick: first candidate not in cooldown and not too similar
    let variantIndex = firstDeterministicIndex(
      in: pool.map { $0.offset },
      familyKey: rule.key,
      optionsCount: rule.responses.count
    )
    var out = rule.responses[variantIndex].text

    // Substitute captures with snapping/sanitation
    if match.numberOfRanges > 1 {
      for i in 1 ..< match.numberOfRanges {
        let token = "$\(i)"
        guard out.contains(token) else { continue }
        if var snapped = usableCapture(in: sentence, range: match.range(at: i)) {
          if rule.key.hasPrefix("rel.") { snapped = CaptureSanitizer.trimAtVerb(snapped) }
          if CaptureSanitizer.isVague(snapped) {
            out = out.replacingOccurrences(of: token, with: "")
          } else {
            out = spliceWithContextAwareSpacer(host: out, captureToken: token, capture: snapped)
          }
        } else {
          out = out.replacingOccurrences(of: token, with: "")
        }
      }
    }

    out = out.replacingOccurrences(of: #"(?i)\byour ([A-Za-z]+) and you\b"#,
                                   with: "you and your $1",
                                   options: .regularExpression)
    out = Punctuation.tidy(out)
    out = RelationshipSanitizer.collapseInLawEcho(out)
    out = Punctuation.ensurePeriod(out)

    // record repetition history per family (deterministic cycling)
    usedVariantIndices[rule.key, default: []].append(variantIndex)
    capHistory(&usedVariantIndices[rule.key]!, to: recentHistoryLimit)
    recentResponseHistory.append(out)
    capHistory(&recentResponseHistory, to: recentHistoryLimit)

    return out
  }

  // MARK: - Helpers (orchestration)

  private func usableCapture(in sentence: String, range: NSRange) -> String? {
    guard let expanded = expandToWordBoundaries(sentence: sentence, range: range) else { return nil }
    let cleaned = CaptureSanitizer.clean(expanded)
    if cleaned.replacingOccurrences(of: " ", with: "").count < 3 { return nil }
    return cleaned
  }

  private func expandToWordBoundaries(sentence: String, range: NSRange) -> String? {
    let ns = sentence as NSString
    var start = range.location
    var len = range.length
    if start == NSNotFound { return nil }
    if start + len > ns.length { len = ns.length - start }

    while start > 0 {
      let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
      if let scalar = ch.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
        start -= 1; len += 1
      } else { break }
    }
    while start + len < ns.length {
      let ch = ns.substring(with: NSRange(location: start + len, length: 1))
      if let scalar = ch.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
        len += 1
      } else { break }
    }
    return ns.substring(with: NSRange(location: start, length: len))
  }

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

  private func spliceWithContextAwareSpacer(host: String, captureToken: String, capture: String) -> String {
    guard let range = host.range(of: captureToken) else {
      return host.replacingOccurrences(of: captureToken, with: capture)
    }
    let prefix = String(host[..<range.lowerBound])

    let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9]$"#)
    let hasWordBefore = wordRegex.firstMatch(in: prefix, options: [], range: NSRange(location: max(0, prefix.count-1), length: min(1, prefix.count))) != nil

    var insertion = capture
    if hasWordBefore {
      let attachers = ["", ",", "and", "but", "which", "that", "who", "whom", "because", "since", "so"]
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

  private func trackMemory(_ input: String) {
    let raw = input.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = safePrefix(raw, max: snippetMax)
    memory.append(safe)
    capHistory(&memory, to: 50)
  }

  private func safePrefix(_ s: String, max: Int) -> String {
    if s.count <= max { return s }
    let idx = s.index(s.startIndex, offsetBy: max)
    var out = String(s[..<idx])
    if let last = out.last,
       (last.isLetter || last.isNumber),
       idx < s.endIndex,
       (s[idx].isLetter || s[idx].isNumber)
    {
      if let cut = out.lastIndex(where: { $0.isWhitespace || ".?!,".contains($0) }) {
        out = String(out[..<cut]).trimmingCharacters(in: .whitespaces)
      }
    }
    return out
  }

  private func canUseFamily(_ familyKey: String) -> Bool {
    let recent = recentFamilyHistory.suffix(familyCooldownWindow)
    return !recent.contains(familyKey)
  }
  private func recordFamilyUse(_ familyKey: String) {
    recentFamilyHistory.append(familyKey)
    capHistory(&recentFamilyHistory, to: recentHistoryLimit)
  }

  private func capHistory<T>(_ arr: inout [T], to limit: Int) {
    while arr.count > limit { arr.removeFirst() }
  }

  private func firstDeterministicIndex(in candidateIndices: [Int], familyKey: String, optionsCount: Int) -> Int {
    let recentIdx = Array(usedVariantIndices[familyKey]?.suffix(variantCooldown) ?? [])
    let ordered = candidateIndices.sorted()
    // pick first not in cooldown and not too similar to last response
    for idx in ordered {
      if recentIdx.contains(idx) { continue }
      let candidate = (rules.first { $0.key == familyKey }?.responses[safe: idx]?.text)
        ?? "" // familyKey may be a rule key; for fallbacks we handle elsewhere
      if let last = recentResponseHistory.last, tooSimilar(candidate, last, threshold: similarityRejectThreshold) {
        continue
      }
      return idx
    }
    // fallback: first index
    return ordered.first ?? 0
  }

  private func tooSimilar(_ a: String, _ b: String, threshold: Double) -> Bool {
    let A = bigrams(a)
    let B = bigrams(b)
    guard !A.isEmpty, !B.isEmpty else { return false }
    let inter = A.intersection(B).count
    let uni = A.union(B).count
    return uni > 0 ? (Double(inter) / Double(uni)) >= threshold : false
  }

  private func bigrams(_ s: String) -> Set<String> {
    let tokens = s.lowercased().split { !$0.isLetter && !$0.isNumber }
    guard tokens.count >= 2 else { return [] }
    var set = Set<String>()
    for i in 0 ..< (tokens.count - 1) { set.insert("\(tokens[i])_\(tokens[i + 1])") }
    return set
  }

  // Deterministic variant selection for fallback/domain pools
  private func chooseVariantDeterministic(from options: [String], familyKey: String) -> String {
    guard !options.isEmpty else { return "" }
    let recentIdx = Array(usedVariantIndices[familyKey]?.suffix(variantCooldown) ?? [])
    for i in 0..<options.count {
      if recentIdx.contains(i) { continue }
      let candidate = options[i]
      if let last = recentResponseHistory.last,
         tooSimilar(candidate, last, threshold: similarityRejectThreshold) { continue }
      usedVariantIndices[familyKey, default: []].append(i)
      capHistory(&usedVariantIndices[familyKey]!, to: recentHistoryLimit)
      recentResponseHistory.append(candidate)
      capHistory(&recentResponseHistory, to: recentHistoryLimit)
      return candidate
    }
    // fallback: first
    let i = 0
    usedVariantIndices[familyKey, default: []].append(i)
    capHistory(&usedVariantIndices[familyKey]!, to: recentHistoryLimit)
    recentResponseHistory.append(options[i])
    capHistory(&recentResponseHistory, to: recentHistoryLimit)
    return options[i]
  }
}
