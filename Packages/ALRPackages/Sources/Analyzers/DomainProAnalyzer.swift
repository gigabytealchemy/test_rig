// DomainClassifierPro.swift
//
// Production-lean, privacy-first rule-based domain classifier for journaling.
// - Multi-label output across a compact domain taxonomy (18 categories below)
// - Heuristics: phrase regex boosts, keyword lexicons, last-sentence priority, light stemming
// - Dialect-aware synonyms (US/UK/Aus), social-media/tech terms, money & health variants
// - Optional JSON overlay to extend/override lexicons without recompiling (DomainLexicon.json)
// - Deterministic, fast, no network
//
// Integration examples:
// let dom = DomainClassifierPro()
// let res = dom.classify("Ran before work, then dinner with my sister—feels good to be back on track.")
// print(res.primary, res.scores) // => Exercise/Fitness + Family + Work
//
// Test Rig adapter (see bottom): DomainProAnalyzer conforms to your Analyzer API
//
import CoreTypes
import Foundation

public final class DomainClassifierPro: @unchecked Sendable {
    public struct Result: Sendable {
        /// Sorted by score (desc). Scores are relative weights (not probabilities);
        /// you may normalize to [0,1] if desired.
        public let ranked: [(name: String, score: Double)]
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

    // MARK: - Tunables
    private let phraseHit: Double = 2.5       // weight per phrase regex hit
    private let keywordHit: Double = 1.0      // weight per keyword hit
    private let lastSentenceBonus: Double = 1.3
    private let minReportScore: Double = 0.5  // domains scoring below are dropped from ranked output

    // MARK: - Lexicons
    // Keywords are lowercased stems or full terms; phrases handled by regexPhrases
    private var keywords: [String: Set<String>] = [:]
    private var regexPhrases: [(domain: String, rx: NSRegularExpression)] = []

    // Extended starter set of keywords across domains
    private func seedKeywords() -> [String: [String]] {
        return [
            "Exercise/Fitness": [
                "run","ran","running","jog","jogging","gym","workout","work out","exercise","lift","lifting","weights",
                "squat","bench","deadlift","stretch","yoga","pilates","swim","swimming","bicycle","cycling","bike",
                "steps","walk","walking","hike","hiking","cardio","spin","spinning","class","coach","trainer",
                "pb","personal best","aerobics","zumba","crossfit","rowing","elliptical","treadmill","fitness",
                "training","athletic","sports","soccer","football","basketball","tennis","rugby","cricket"
            ],
            "Family": [
                "mother","mom","mum","mama","mommy","father","dad","daddy","parents","parenting","sister","brother",
                "siblings","daughter","son","kids","child","children","grandma","grandpa","grandparent","in-law",
                "inlaws","cousin","aunt","uncle","niece","nephew","family","relative","kin","folks","household",
                "stepmom","stepdad","stepsister","stepbrother"
            ],
            "Friends": [
                "friend","friends","bestie","mate","pal","buddy","bros","crew","squad","circle","gang","hang out",
                "hangout","catch up","caught up","girls night","guys night","brunch","pub","bar","party","gathering"
            ],
            "Relationships/Marriage/Partnership": [
                "partner","spouse","husband","wife","fiancé","fiance","fiancée","boyfriend","girlfriend","bf","gf",
                "relationship","marriage","wed","wedding","anniversary","argued","argue","fight","fought","counseling",
                "counselling","couples","date night","domestic","commitment","union","bond","divorce","separation"
            ],
            "Love/Romance": [
                "love","lover","crush","romance","romantic","kiss","kissing","intimate","intimacy","sex","sexual",
                "make out","made out","flirt","flirting","chemistry","spark","passion","affection","beloved","desire"
            ],
            "Food/Eating": [
                "eat","ate","eating","meal","breakfast","brunch","lunch","dinner","snack","snacked","bake","baked",
                "cook","cooked","cooking","recipe","restaurant","cafe","café","takeout","take-away","delivery",
                "diet","calorie","protein","carb","vegan","vegetarian","gluten-free","cupcake","cake","pizza","pasta",
                "burger","sandwich","supper","feast","buffet","sushi","doughnut","donut","ice cream","barbecue","bbq"
            ],
            "Sleep/Rest": [
                "sleep","slept","sleeping","nap","napped","tired","exhausted","insomnia","rest","bedtime","woke","wake",
                "awake","dream","dreamt","dreamed","nightmare","restless","siesta","slumber","doze","snooze"
            ],
            "Health/Medical": [
                "health","healthy","doctor","gp","clinic","hospital","er","a&e","urgent care","nurse","dentist","therapist",
                "therapy","counselor","physio","physical therapy","pt","meds","medicine","rx","prescription","diagnos",
                "symptom","bp","blood pressure","cholesterol","heart rate","injury","injured","surgery","sore","ache",
                "pain","migraine","cold","flu","checkup","vaccination","vaccine","illness","disease","wellness","treatment"
            ],
            "Work/Career": [
                "work","job","career","office","boss","manager","coworker","colleague","deadline","deliverable","meeting",
                "standup","stand-up","retro","review","promotion","promote","raise","pay rise","demote","hired","fired",
                "layoff","furlough","overtime","wfh","remote","commute","project","launch","ship","ticket","jira","email",
                "slack","report","kpi","okr","okrs","org chart","reorg","pull request","merge","commit","shift","schedule",
                "worked","working","assignment","task","submission","deliverable","progress",
                "client","gig","freelance","remote","online work"
            ],
            "Money/Finances": [
                "money","finance","finances","budget","budgeting","paycheck","salary","wage","wages","paid","unpaid",
                "bonus","rent","mortgage","loan","debt","credit","credit card","bank","savings","invest","investment",
                "investing","stocks","shares","bills","bill","tax","irs","hmrc","superannuation","interest","dividend",
                "pension","retirement","crypto","bitcoin","ethereum","direct deposit","late fee", "reward",
                "earnings","income","profit","cash","bills","goal"
            ],
            "School/Learning": [
                "school","class","classes","lecture","seminar","study","studying","homework","assignment","exam","quiz",
                "midterm","final","project","teacher","prof","professor","tutor","grade","gpa","research","thesis",
                "dissertation","paper","essay","campus","course","lesson","learning","curriculum","group project"
            ],
            "Spirituality/Religion": [
                "god","gods","faith","pray","prayer","church","mass","mosque","temple","synagogue","spiritual",
                "spirituality","bible","quran","koran","torah","meditate","meditation","mindful","mindfulness","retreat",
                "sunday service","hymn","worship","belief","soul","spirit"
            ],
            "Recreation/Leisure": [
                "movie","film","cinema","tv","series","show","netflix","hulu","disney+","disney plus","hbomax","max","prime",
                "board game","boardgame","puzzle","craft","knit","knitting","garden","gardening","park","beach","pool",
                "outing","festival","concert","gig","sports","stadium","match","team","league","game night","movie night"
            ],
            "Travel/Nature": [
                "travel","trip","holiday","vacation","staycation","flight","airport","airplane","plane","train","road trip",
                "roadtrip","drive","drove","bus","bike tour","camp","camping","hike","trail","forest","woods","mountain",
                "lake","river","ocean","sea","nature","outdoors","journey","itinerary","adventure","national park"
            ],
            "Creativity/Art": [
                "create","creative","creativity","write","writing","wrote","draft","poem","poetry","novel","story","paint",
                "painting","draw","drawing","sketch","design","compose","song","music","practice","rehearsal","studio",
                "art","gallery","exhibit","photography","photo","film-making","craft","handmade","writer's block","first draft"
            ],
            "Community/Society/Politics": [
                "community","neighborhood","neighbourhood","volunteer","volunteering","charity","fundraiser","election",
                "vote","voted","politics","policy","protest","march","rally","civic","council","local news","news",
                "headline","crime","safety","public","government","parliament","senate","congress","food bank"
            ],
            "Technology/Media/Internet": [
                "phone","screen","scroll","scrolled","scrolling","social","socials","social media","facebook","instagram","ig",
                "tiktok","twitter","x.com","youtube","reddit","discord","slack","email","inbox","notifications","app","apps",
                "game","gaming","console","pc","mac","iphone","android","laptop","online","offline","internet","web","digital",
                "zoom","teams","facetime","doomscroll","doomscrolling","screen time","inbox zero"
            ],
            "Self/Growth/Habits": [
                "goal","goals","habit","habits","streak","journal","journaling","therapy homework","self-care","self care",
                "routine","morning routine","evening routine","reflection","reflect","intent","intentions","affirmation",
                "vision","plan","planning","review","check-in","check in","track","tracked","on track","back on track",
                "resolution","challenge","growth","mindset","practice","personal development","self improvement"
            ]
        ]
    }

    // Phrase regex seeds
    private func seedPhrases() -> [String: [String]] {
        return [
            "Exercise/Fitness": [ #"\\b(5k|10k|marathon|half marathon)\\b"#, #"\\bpersonal best\\b"# ],
            "Family": [ #"\\b(first )?birthday\\b"#, #"\\bfamily (dinner|gathering|reunion)\\b"# ],
            "Relationships/Marriage/Partnership": [ #"\\bdate night\\b"#, #"\\bmarriage counseling|couples therapy\\b"# ],
            "Food/Eating": [ #"\\b(gluten[- ]free|dairy[- ]free|vegan|vegetarian)\\b"#, #"\\bhome[- ]cooked\\b"#, #"\bfamily dinner\b"#],
            "Work/Career": [ #"\\bperformance review\\b"#, #"\\b(rfa|rfc|okr|offsite)\\b"#, #"\\bcode review\\b"#,
                             #"\\b(work(ed)? online)\\b"#, #"\\b(an assignment.*rejected)\\b"#, #"\b(first|back) day back to work\b"#, #"\b(work(ed)? online)\b"#,
                             #"\b(an assignment.*rejected)\b"#],
            "Money/Finances": [ #"\\bcredit card\\b"#, #"\\b(loan|mortgage) approval\\b"#, #"\\bdirect deposit\\b"#,
                                #"\\b(earnings goal)\\b"#, #"\\b(pay(ing)? bills)\\b"#, #"\\b(make money)\\b"#, #"\b(earnings goal)\b"#,
                                #"\b(pay(ing)? bills)\b"#,
                                #"\b(make money)\b"#],
            "School/Learning": [ #"\\bfinal exam\\b"#, #"\\bpeer review\\b"#, #"\\bgroup project\\b"# ],
            "Spirituality/Religion": [ #"\\bsunday service\\b"#, #"\\b(quiet )?time with god\\b"# ],
            "Recreation/Leisure": [ #"\\bmovie night\\b"#, #"\\bgame night\\b"#, #"\\blive music\\b"# ],
            "Travel/Nature": [ #"\\broad (?:trip|trips)\\b"#, #"\\bnational park\\b"# ],
            "Creativity/Art": [ #"\\bwriter'?s block\\b"#, #"\\bfirst draft\\b"# ],
            "Community/Society/Politics": [ #"\\b(voted|vote|election day)\\b"#, #"\\bfood bank\\b"# ],
            "Technology/Media/Internet": [ #"\\bdoomscroll(?:ing)?\\b"#, #"\\bscreen time\\b"#, #"\\binbox zero\\b"# ],
            "Self/Growth/Habits": [ #"\\b(back|getting) on track\\b"#, #"\\bmorning routine\\b"# ]
        ]
    }


    // MARK: - Build regex from seeds
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
            // Phrase regex (heavy weight)
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
            // Recency bonus for last sentence
            if pos == 1 { for k in sliceScores.keys { sliceScores[k]! *= lastSentenceBonus } }
            // Merge
            for (k, v) in sliceScores { scores[k, default:0] += v }
        }

        // Rank and threshold
        let sortedScores = scores.sorted { $0.value > $1.value }.filter { $0.value >= minReportScore }
        // Normalize small float noise and convert to named tuple
        let ranked = sortedScores.map { (name: $0.key, score: ($0.value * 100).rounded() / 100) }
        return Result(ranked: ranked)
    }

    // MARK: - Overlays (optional)
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
        let joined = s
            .replacingOccurrences(of: "credit card", with: "credit_card")
            .replacingOccurrences(of: "out of nowhere", with: "out_of_nowhere")
            .replacingOccurrences(of: "social media", with: "social_media")
        return joined.split{ !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
    }

    private func inLex(_ token: String, _ set: Set<String>) -> Bool {
        if set.contains(token) { return true }
        let stem = lightStem(token)
        return set.contains(stem)
    }
    private func lightStem(_ t: String) -> String {
        var s = t
        for suf in ["ing","ed","ly","ies","s"] {
            if s.hasSuffix(suf) && s.count > suf.count + 2 { s.removeLast(suf.count); break }
        }
        return s
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
