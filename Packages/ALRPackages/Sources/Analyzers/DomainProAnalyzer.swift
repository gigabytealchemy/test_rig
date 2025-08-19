// DomainProAnalyzer.swift
//
// Production‑lean, privacy‑first rule‑based domain classifier for journaling.
// Deterministic, fast, no network. No ML.
//
// -----------------------------------------------------------------------------
// This iteration — TWO SAFE, HIGH‑CONFIDENCE OVERRIDES
// -----------------------------------------------------------------------------
// What changed (and why)
// 1) HARD OVERRIDE: “work out / workout / working out / worked out” → Exercise/Fitness
//    • If this pattern appears anywhere, Exercise/Fitness is forced to win for that clause.
//    • Additionally, Work/Career is zeroed for that clause to prevent bleed from “work”.
//    • Rationale: in journaling, “work out” is unambiguous exercise; “work” is generic.
// 2) STRONG FAMILY BIAS ON KIN TERMS
//    • Presence of any kin term (kid(s), mom, dad, daughter, son, parents, etc.) applies
//      a strong Family boost so Family wins even if Food/Love/School tokens appear.
//    • Exception: spouse‑only mentions (wife/husband/partner) with NO other kin do NOT
//      trigger this bias (so pure couple entries can remain Relationships).
//
// Kept intentionally minimal to avoid over‑fitting. No logging; adapter unchanged.
//
// Tunables touched
// • workoutForceWeight: +∞ effect via zeroing Work and a large Exercise add
// • kinFamilyBoost: strong add so Family wins “almost regardless” (except spouse‑only)
//
// Next ideas (only if needed)
// • If Family still leaks to Food, we can very slightly raise kinFamilyBoost.
// • If an edge case appears where “work out” fires incorrectly, we can scope by tokenization.
// -----------------------------------------------------------------------------

import CoreTypes
import Foundation

public final class DomainClassifierPro: @unchecked Sendable {
    public struct Result: Sendable {
        public let ranked: [(name: String, score: Double)] // sorted desc
        public var primary: String { ranked.first?.name ?? "General / Other" }
        public var scores: [String: Double] { Dictionary(uniqueKeysWithValues: ranked) }
    }

    public init() { buildRegex(); loadExternalLexicon() }

    // MARK: - Taxonomy (18)
    public static let Domains: [String] = [
        "Exercise/Fitness",
        "Family",
        "Friends",
        "Relationships/Marriage/Partnership",
        "Love/Romance",
        "Food/Eating",
        "Sleep/Rest",
        "Health/Medical",
        "Work/Career",
        "Money/Finances",
        "School/Learning",
        "Spirituality/Religion",
        "Recreation/Leisure",
        "Travel/Nature",
        "Creativity/Art",
        "Community/Society/Politics",
        "Technology/Media/Internet",
        "Self/Growth/Habits"
    ]

    // MARK: - Tunables (deterministic)
    private let phraseHit: Double = 2.5       // weight per phrase regex hit
    private let keywordHit: Double = 1.0      // weight per keyword hit
    private let lastSentenceBonus: Double = 1.15
    private let minReportScore: Double = 0.5  // below this, domains drop from ranked output

    // Context windows
    private let familyKinWindow: Int = 8

    // --- New override strengths ---
    private let kinFamilyBoost: Double = 3.0         // strong Family bias when any kin present (except spouse‑only)
    private let workoutForceAdd: Double = 3.0        // extra add to Exercise when “work out” is found
    private let workoutZeroOutWork: Bool = true      // zero Work when “work out” is found in a clause

    // Regex strings
    private let workoutRegex = #"(?<!home)\bwork[ -]?out(s|ed|ing)?\b"#  // “work out / workout / worked/working out”

    // MARK: - Lexicons
    private var keywords: [String: Set<String>] = [:]
    private var regexPhrases: [(domain: String, rx: NSRegularExpression)] = []

    private func seedKeywords() -> [String: [String]] {
        return [
            "Exercise/Fitness": [
                "run","ran","running","jog","jogging","gym","workout","work out","exercise","lift","lifting","weights",
                "squat","bench","deadlift","stretch","stretched","stretching","yoga","pilates","swim","swimming",
                "bicycle","cycling","bike","steps","walk","walking","hike","hiking","cardio","spin","spinning","class",
                "coach","trainer","pb","personal best","aerobics","zumba","crossfit","rowing","elliptical","treadmill",
                "fitness","training","athletic","sports","soccer","football","basketball","tennis","rugby","cricket",
                "reps","rep","set","sets","trail","trailrun"
            ],
            "Family": [
                "mother","mom","mum","mama","mommy","father","dad","daddy","parents","parenting","sister","brother",
                "siblings","daughter","son","kids","kid","child","children","grandma","grandpa","grandparent",
                "in-law","inlaws","cousin","aunt","uncle","niece","nephew","family","relative","kin","folks","household",
                "stepmom","stepdad","stepsister","stepbrother","home","house"
            ],
            "Friends": [
                "friend","friends","bestie","mate","pal","buddy","bros","crew","squad","circle","gang","hang out",
                "hangout","catch up","caught up","girls night","guys night","brunch","pub","bar","party","gathering"
            ],
            "Relationships/Marriage/Partnership": [
                "partner","spouse","husband","wife","fiancé","fiance","fiancée","boyfriend","girlfriend","bf","gf",
                "relationship","marriage","wed","wedding","anniversary","argued","argue","fight","fought","counseling",
                "counselling","couples","date night","domestic","commitment","union","bond","divorce","separation",
                "jealous","intimacy","romance"
            ],
            "Love/Romance": [
                "love","lover","crush","romance","romantic","kiss","kissing","intimate","intimacy","sex","sexual",
                "make out","made out","flirt","flirting","chemistry","spark","passion","affection","beloved","desire","bae","boo","cute"
            ],
            "Food/Eating": [
                "eat","ate","eating","meal","breakfast","brunch","lunch","dinner","snack","snacked",
                "bake","baked","cook","cooked","cooking","recipe","restaurant","cafe","café","takeout","take-away","delivery",
                "diet","calorie","protein","carb","vegan","vegetarian","gluten-free","cupcake","cake","pizza","pasta",
                "burger","sandwich","supper","feast","buffet","sushi","doughnut","donut","ice cream","barbecue","bbq",
                "leftovers","latte","espresso","coffee","tea","boba","milk tea","menu","ordered","order","reservation",
                "chef","barista","dessert","cookies","homemade","soup","bread","chicken","pasta"
            ],
            "Sleep/Rest": [
                "sleep","slept","sleeping","nap","napped","tired","exhausted","insomnia","rest","bedtime","woke","wake",
                "awake","dream","dreamt","dreamed","nightmare","restless","siesta","slumber","doze","snooze","drowsy","fatigue"
            ],
            "Health/Medical": [
                "health","healthy","doctor","gp","clinic","hospital","er","a&e","urgent care","nurse","dentist","therapist",
                "therapy","counselor","physio","physical therapy","pt","meds","medicine","rx","prescription","diagnos",
                "symptom","bp","blood pressure","cholesterol","heart rate","injury","injured","surgery","sore","ache",
                "pain","migraine","headache","cold","flu","fever","cough","checkup","vaccination","vaccine","illness","disease",
                "wellness","treatment","nausea","nauseous","vomit","vomiting","refill","appointment","check-up"
            ],
            "Work/Career": [
                "work","worked","working","job","career","office","boss","manager","coworker","colleague",
                "deadline","deliverable","meeting","standup","stand-up","retro","review","promotion","promote","raise","pay rise",
                "demote","hired","fired","layoff","furlough","overtime","wfh","remote","commute","project","launch","ship",
                "ticket","jira","email","slack","report","kpi","okr","okrs","org chart","reorg","pull request","merge","commit",
                "shift","schedule","assignment","task","submission","progress","client","gig","freelance","online work",
                "timesheet","clock in","clock out","clock-in","clock-out","onboarding","offboarding","stakeholder",
                "performance","payroll","interview","recruiter","bonus","deploy","prod","bug","repo","zoom","meet","call"
            ],
            "Money/Finances": [
                "money","finance","finances","budget","budgeting","paycheck","salary","wage","wages","paid","unpaid",
                "bonus","rent","mortgage","loan","debt","credit","credit card","bank","savings","invest","investment",
                "investing","stocks","shares","bills","bill","tax","irs","hmrc","superannuation","interest","dividend",
                "pension","retirement","crypto","bitcoin","ethereum","direct deposit","late fee","refund","insurance","premium",
                "fee","fees","income","profit","cash"
            ],
            "School/Learning": [
                "school","class","classes","lecture","seminar","study","studying","homework","assignment","assignments",
                "exam","quiz","midterm","final","project","teacher","prof","professor","tutor","grade","gpa","research",
                "thesis","dissertation","paper","essay","campus","course","lesson","learning","curriculum","group project"
            ],
            "Spirituality/Religion": [
                "god","gods","faith","pray","prayer","church","mass","mosque","temple","synagogue","spiritual",
                "spirituality","bible","quran","koran","torah","meditate","meditation","mindful","mindfulness","retreat",
                "sunday service","hymn","worship","belief","soul","spirit"
            ],
            "Recreation/Leisure": [
                "movie","film","cinema","tv","series","show","netflix","hulu","disney+","disney plus","hbomax","max","prime",
                "board game","boardgame","puzzle","craft","knit","knitting","garden","gardening","park","beach","pool",
                "outing","festival","concert","gig","sports","stadium","match","team","league","game night","movie night",
                "party","bar","club","karaoke","picnic","camping","camp","play","played","playing","hike","hiking"
            ],
            "Travel/Nature": [
                "travel","trip","holiday","vacation","staycation","flight","airport","airplane","plane","train","road trip",
                "roadtrip","drive","drove","bus","bike tour","camp","camping","hike","trail","forest","woods","mountain",
                "lake","river","ocean","sea","nature","outdoors","journey","itinerary","adventure","national park",
                "uber","lyft","taxi","hotel","airbnb","check-in","checkin","reservation","tour","tourist","scenic"
            ],
            "Creativity/Art": [
                "create","creative","creativity","write","writing","wrote","draft","poem","poetry","novel","story","paint",
                "painting","draw","drawing","sketch","design","compose","song","music","practice","rehearsal","studio",
                "art","gallery","exhibit","photography","photo","film-making","craft","handmade","writer's block","first draft"
            ],
            "Community/Society/Politics": [
                "community","neighborhood","neighbourhood","volunteer","volunteering","charity","fundraiser","election",
                "vote","voted","politics","policy","protest","march","rally","civic","council","local news","news",
                "headline","crime","safety","public","government","parliament","senate","congress","food bank","petition","town hall"
            ],
            "Technology/Media/Internet": [
                "phone","screen","scroll","scrolled","scrolling","social","socials","social media","facebook","instagram","ig",
                "tiktok","twitter","x.com","youtube","reddit","discord","slack","email","inbox","notifications","app","apps",
                "game","gaming","console","pc","mac","iphone","android","laptop","online","offline","internet","web","digital",
                "zoom","teams","facetime","doomscroll","doomscrolling","screen time","inbox zero","stream","streaming","binge","binged","podcast","newsfeed"
            ],
            "Self/Growth/Habits": [
                "goal","goals","habit","habits","streak","journal","journaling","therapy homework","self-care","self care",
                "routine","morning routine","evening routine","reflection","reflect","intent","intentions","affirmation",
                "vision","plan","planning","review","check-in","check in","track","tracked","on track","back on track",
                "resolution","challenge","growth","mindset","practice","personal development","self improvement","discipline",
                "focus","focused","todo","to-do","checklist","time block","time-block","pomodoro"
            ]
        ]
    }

    // Phrase regex seeds (kept minimal; the “work out” hard override is handled separately too)
    private func seedPhrases() -> [String: [String]] {
        return [
            "Exercise/Fitness": [
                workoutRegex, // treat as strong signal; hard override applied separately
                #"\b(gym|ran|running|jog(ging)?|yoga|pilates|lift(ing)?|reps?|sets?)\b"#,
                #"\b(5k|10k|marathon|half marathon)\b"#,
                #"\bpersonal best\b"#
            ],
            "Family": [
                #"\b(first )?birthday\b"#,
                #"\bfamily (gathering|reunion)\b"#
            ],
            "Relationships/Marriage/Partnership": [
                #"\bdate night\b"#,
                #"\bmarriage counseling|couples therapy\b"#,
                #"\banniversar(?:y|ies)(?: dinner)?\b"#
            ],
            "Food/Eating": [
                #"\b(gluten[- ]free|dairy[- ]free|vegan|vegetarian)\b"#,
                #"\bhome[- ]cooked\b"#
            ]
            // Other domains keep their default minimal seeds above (not repeated here for brevity)
        ]
    }

    private func buildRegex() {
        let seed = seedKeywords()
        for (dom, list) in seed { keywords[dom] = Set(list.map { $0.lowercased() }) }
        let phr = seedPhrases()
        for (dom, pats) in phr {
            for p in pats { regexPhrases.append((dom, try! NSRegularExpression(pattern: p, options: [.caseInsensitive]))) }
        }
    }

    // MARK: - Classify
    public func classify(_ text: String) -> Result {
        let normalized = normalize(text)
        if normalized.isEmpty { return Result(ranked: []) }

        // Split into sentences (newest first)
        let sentences = splitIntoSentences(normalized).reversed()

        var scores: [String: Double] = [:]
        var pos = 0
        for sentence in sentences { pos += 1
            var sliceScores: [String: Double] = [:]

            // Phrase regex (adds weight)
            for (dom, rx) in regexPhrases {
                if rx.firstMatch(in: sentence, options: [], range: NSRange(location: 0, length: (sentence as NSString).length)) != nil {
                    sliceScores[dom, default:0] += phraseHit
                }
            }

            // Keyword hits (light stemming)
            let toks = tokenize(sentence)
            for dom in DomainClassifierPro.Domains {
                guard let set = keywords[dom] else { continue }
                var c = 0
                for t in toks { if inLex(t, set) { c += 1 } }
                if c > 0 { sliceScores[dom, default:0] += Double(c) * keywordHit }
            }

            // --- HARD OVERRIDES (per your request) ---
            applyWorkoutHardOverride(raw: sentence, scores: &sliceScores)
            applyKinStrongFamilyBias(tokens: toks, scores: &sliceScores)

            // Recency bonus for last sentence (summary often at the end)
            if pos == 1 { for k in sliceScores.keys { sliceScores[k]! *= lastSentenceBonus } }

            // Merge to total
            for (k, v) in sliceScores { scores[k, default:0] += v }
        }

        // Rank and threshold
        let sortedScores = scores.sorted { $0.value > $1.value }.filter { $0.value >= minReportScore }
        let ranked = sortedScores.map { (name: $0.key, score: ($0.value * 100).rounded() / 100) }
        return Result(ranked: ranked)
    }

    // MARK: - Overrides

    // 1) “work out / workout / working/ed out” ⇒ Force Exercise; optionally zero Work.
    private func applyWorkoutHardOverride(raw: String, scores: inout [String: Double]) {
        if regexMatch(workoutRegex, in: raw) {
            // Strongly bias Exercise
            scores["Exercise/Fitness", default: 0] += phraseHit + workoutForceAdd
            if workoutZeroOutWork {
                scores["Work/Career"] = 0 // ensure Work cannot dominate this clause
            }
        }
    }

    // 2) Any kin term present ⇒ strong Family bias (except spouse‑only case)
    private func applyKinStrongFamilyBias(tokens toks: [String], scores: inout [String: Double]) {
        let fam = "Family"
        let spouse: Set<String> = ["wife","husband","spouse","partner","fiance","fiancé","fiancee","fiancée","bf","gf","boyfriend","girlfriend"]
        let kin: Set<String> = ["kid","kids","baby","child","children","daughter","son","mom","dad","mother","father",
                                "parents","parenting","family","inlaws","in-law","cousin","cousins","sibling","siblings",
                                "aunt","uncle","grandma","grandpa","grandparent","grandparents","niece","nephew"]

        let hasSpouse = anyIn(toks, spouse)
        let hasKin = anyIn(toks, kin)

        // Spouse‑only (no other kin) → do NOT force Family
        if hasSpouse && !hasKin { return }

        // If any kin present, apply strong Family boost
        if hasKin {
            scores[fam, default: 0] += kinFamilyBoost
        }
    }

    // MARK: - Overlays (optional JSON pack)
    private struct DomainLexiconPack: Decodable { let domains: [String: [String]]?; let phrases: [String: [String]]? }
    private func loadExternalLexicon(filename: String = "DomainLexicon", ext: String = "json") {
        #if canImport(Foundation)
        if let url = Bundle.main.url(forResource: filename, withExtension: ext),
           let data = try? Data(contentsOf: url),
           let pack = try? JSONDecoder().decode(DomainLexiconPack.self, from: data) {
            if let doms = pack.domains {
                for (dom, words) in doms { keywords[dom, default: []].formUnion(words.map { $0.lowercased() }) }
            }
            if let phr = pack.phrases {
                for (dom, pats) in phr { for p in pats { regexPhrases.append((dom, try! NSRegularExpression(pattern: p, options: [.caseInsensitive]))) } }
            }
        }
        #endif
    }

    // MARK: - Utils
    private func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

    private func tokenize(_ s: String) -> [String] {
        // Collapse common multiword tokens to single tokens so lexicons/regex align better.
        let joined = s
            .replacingOccurrences(of: "credit card", with: "credit_card")
            .replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
            .replacingOccurrences(of: "social media", with: "social_media")
            .replacingOccurrences(of: "date night", with: "date-night")
            .replacingOccurrences(of: "made up", with: "made_up")
            .replacingOccurrences(of: "time block", with: "time_block")
            .replacingOccurrences(of: "game night", with: "game_night")
            .replacingOccurrences(of: "movie night", with: "movie_night")
            .replacingOccurrences(of: "road trip", with: "roadtrip")
            .replacingOccurrences(of: "board game", with: "boardgame")
            .replacingOccurrences(of: "work out", with: "workout") // help disambiguate “work out”
        return joined.split{ !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }.map(String.init)
    }

    private func inLex(_ token: String, _ set: Set<String>) -> Bool {
        if set.contains(token) { return true }
        let stem = lightStem(token)
        return set.contains(stem) || set.contains(stem.replacingOccurrences(of: "_", with: " "))
    }

    private func lightStem(_ t: String) -> String {
        var s = t
        for suf in ["ing","ed","ly","ies","s"] {
            if s.hasSuffix(suf) && s.count > suf.count + 2 { s.removeLast(suf.count); break }
        }
        return s
    }

    // Helpers
    private func anyIn(_ toks: [String], _ set: Set<String>) -> Bool {
        for t in toks { let ls = lightStem(t); if set.contains(ls) || set.contains(t) { return true } }
        return false
    }
    private func indexSet(_ toks: [String], in set: Set<String>) -> [Int] {
        var idxs: [Int] = []
        for (i, t) in toks.enumerated() {
            let ls = lightStem(t)
            if set.contains(ls) || set.contains(t) { idxs.append(i) }
        }
        return idxs
    }
    private func anyWithin(_ a: [Int], _ b: [Int], dist: Int) -> Bool {
        for i in a { for j in b { if abs(i - j) <= dist { return true } } }
        return false
    }
    private func regexMatch(_ pattern: String, in text: String) -> Bool {
        return (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}

// MARK: - Test Rig Adapter (Analyzer)
public struct DomainProAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .domains
    public let name: String = "Domain • Rules Pro"
    private let clf = DomainClassifierPro()
    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let text = (input.selectedRange != nil) ? String(input.fullText[input.selectedRange!]) : input.fullText
        let res = clf.classify(text)
        let ranked = res.ranked.map { "\($0.name)=\(String(format: "%.2f", $0.score))" }.joined(separator: " • ")
        return AnalyzerOutput(category: category,
                              name: name,
                              result: res.primary,
                              metadata: ["ranked": ranked])
    }
}
