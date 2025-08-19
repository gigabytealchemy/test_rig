// DomainProAnalyzer.swift
//
// Production-lean rule-based domain classifier (18 domains) for journaling text.
// Deterministic, fast, private (no network). Multi-cue scoring.
//
// Domains / IDs:
//  1 Exercise/Fitness, 2 Family, 3 Friends, 4 Relationships/Marriage/Partnership,
//  5 Love/Romance, 6 Food/Eating, 7 Sleep/Rest, 8 Health/Medical,
//  9 Work/Career, 10 Money/Finances, 11 School/Learning, 12 Spirituality/Religion,
//  13 Recreation/Leisure, 14 Travel/Nature, 15 Creativity/Art,
//  16 Community/Society/Politics, 17 Technology/Media/Internet, 18 Self/Growth/Habits
//
// Design:
// - Large keyword lexicons + phrase regex boosts (dialects/variants included).
// - Last sentence bonus (journals often summarize at the end).
// - Returns top-1 domain with scores; choose threshold externally if you want "Mixed".
//
// Integration in Test Rig (Analyzer):
//   let out = DomainProAnalyzer().analyze(input)
//   -> AnalyzerOutput.result = "9 – Work/Career"
//

import Foundation

public final class DomainClassifierPro {

    public struct Result: Sendable {
        public let id: Int
        public let label: String
        public let scores: [Int: Double]
    }

    // Tunables
    private let phraseHit: Double = 2.5
    private let keywordHit: Double = 1.0
    private let lastSentenceBonus: Double = 1.5
    private let minReportScore: Double = 0.5

    public init() {}

    // Labels
    private let labels: [Int: String] = [
        1:"Exercise/Fitness", 2:"Family", 3:"Friends", 4:"Relationships/Marriage/Partnership",
        5:"Love/Romance", 6:"Food/Eating", 7:"Sleep/Rest", 8:"Health/Medical",
        9:"Work/Career", 10:"Money/Finances", 11:"School/Learning", 12:"Spirituality/Religion",
        13:"Recreation/Leisure", 14:"Travel/Nature", 15:"Creativity/Art",
        16:"Community/Society/Politics", 17:"Technology/Media/Internet", 18:"Self/Growth/Habits"
    ]

    // Keyword seeds (extended; lowercased)
    private lazy var keywords: [Int: Set<String>] = {
        seedKeywords().mapValues { Set($0) }
    }()

    // Phrase regex seeds
    private lazy var phraseRegex: [Int: [NSRegularExpression]] = {
        seedPhrases().mapValues { arr in arr.map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) } }
    }()

    public func classify(_ text: String) -> Result {
        let t = text.lowercased()
        let parts = splitSentences(text)
        var scores: [Int: Double] = [:]

        // Base keywords
        for (id, lex) in keywords {
            for w in lex {
                if t.contains(w) {
                    scores[id, default:0] += keywordHit
                }
            }
        }

        // Phrase boosts
        for (id, regs) in phraseRegex {
            for r in regs {
                if r.firstMatch(in: t, options: [], range: NSRange(location: 0, length: t.utf16.count)) != nil {
                    scores[id, default:0] += phraseHit
                }
            }
        }

        // Last sentence emphasis
        if let last = parts.last?.lowercased() {
            for (id, reg) in phraseRegex {
                for r in reg {
                    if r.firstMatch(in: last, options: [], range: NSRange(location: 0, length: last.utf16.count)) != nil {
                        scores[id, default:0] += (lastSentenceBonus - 1.0) * phraseHit
                    }
                }
            }
            for (id, lex) in keywords {
                for w in lex where last.contains(w) {
                    scores[id, default:0] += (lastSentenceBonus - 1.0) * keywordHit
                }
            }
        }

        // Pick winner
        let sorted = scores.sorted { $0.value > $1.value }
        guard let top = sorted.first, top.value >= minReportScore else {
            // fall back to the strongest anyway to avoid "General" dumping; label will still reflect top domain
            let fallback = sorted.first ?? (9, 0.0) // Work default if nothing found
            return Result(id: fallback.0, label: labels[fallback.0] ?? "Unknown", scores: scores)
        }
        return Result(id: top.0, label: labels[top.0] ?? "Unknown", scores: scores)
    }

    // MARK: Seeds

    // Extended starter keywords
    private func seedKeywords() -> [Int: [String]] {
        return [
            1: [ // Exercise/Fitness
                "run","ran","running","jog","jogging","gym","workout","work out","exercise","lift","lifting","weights",
                "squat","bench","deadlift","stretch","yoga","pilates","swim","swimming","bicycle","cycling","bike",
                "steps","walk","walking","hike","hiking","cardio","spin","spinning","class","coach","trainer",
                "pb","personal best","aerobics","zumba","crossfit","rowing","elliptical","treadmill","fitness",
                "training","athletic","sports","soccer","football","basketball","tennis","rugby","cricket","hiit",
                "peloton","strava","vo2max","workout video"
            ],
            2: [ // Family
                "mother","mom","mum","mama","mommy","father","dad","daddy","parents","parenting","sister","brother",
                "siblings","daughter","son","kids","child","children","grandma","grandpa","grandparent","in-law",
                "inlaws","cousin","aunt","uncle","niece","nephew","family","relative","kin","folks","household",
                "stepmom","stepdad","stepsister","stepbrother"
            ],
            3: [ // Friends
                "friend","friends","bestie","mate","pal","buddy","bros","crew","squad","circle","gang","hang out",
                "hangout","catch up","caught up","girls night","guys night","brunch","pub","bar","party","gathering"
            ],
            4: [ // Relationships/Marriage/Partnership
                "partner","spouse","husband","wife","fiancé","fiance","fiancée","boyfriend","girlfriend","bf","gf",
                "relationship","marriage","wed","wedding","anniversary","argued","argue","fight","fought","counseling",
                "counselling","couples","date night","domestic","commitment","union","bond","divorce","separation"
            ],
            5: [ // Love/Romance
                "love","lover","crush","romance","romantic","kiss","kissing","intimate","intimacy","sex","sexual",
                "make out","made out","flirt","flirting","chemistry","spark","passion","affection","beloved","desire"
            ],
            6: [ // Food/Eating
                "eat","ate","eating","meal","breakfast","brunch","lunch","dinner","snack","snacked","bake","baked",
                "cook","cooked","cooking","recipe","restaurant","cafe","café","takeout","take-away","delivery",
                "diet","calorie","protein","carb","vegan","vegetarian","gluten-free","cupcake","cake","pizza","pasta",
                "burger","sandwich","supper","feast","buffet","sushi","doughnut","donut","ice cream","barbecue","bbq",
                "family dinner"
            ],
            7: [ // Sleep/Rest
                "sleep","slept","sleeping","nap","napped","tired","exhausted","insomnia","rest","bedtime","woke","wake",
                "awake","dream","dreamt","dreamed","nightmare","restless","siesta","slumber","doze","snooze"
            ],
            8: [ // Health/Medical
                "health","healthy","doctor","gp","clinic","hospital","er","a&e","urgent care","nurse","dentist","therapist",
                "therapy","counselor","physio","physical therapy","pt","meds","medicine","rx","prescription","diagnos",
                "symptom","bp","blood pressure","cholesterol","heart rate","injury","injured","surgery","sore","ache",
                "pain","migraine","cold","flu","checkup","vaccination","vaccine","illness","disease","wellness",
                "treatment","well-being","wellbeing","self-care","self care"
            ],
            9: [ // Work/Career
                "work","worked","working","job","career","office","boss","manager","coworker","colleague","deadline",
                "deliverable","project","assignment","task","submission","progress","review","client","gig","freelance",
                "remote","online work","shift","schedule","launch","ship","ticket","jira","email","slack","report",
                "kpi","okr","okrs","org chart","reorg","pull request","merge","commit","meeting","standup","retro"
            ],
            10: [ // Money/Finances
                "money","finance","finances","budget","budgeting","paycheck","salary","wage","wages","paid","unpaid",
                "bonus","rent","mortgage","loan","debt","credit","credit card","bank","savings","invest","investment",
                "investing","stocks","shares","bills","bill","tax","irs","hmrc","superannuation","interest","dividend",
                "pension","retirement","crypto","bitcoin","ethereum","direct deposit","late fee","earnings","income",
                "profit","cash","goal","make money","pay bills","earnings goal"
            ],
            11: [ // School/Learning
                "school","class","classes","lecture","seminar","study","studying","homework","assignment","exam","quiz",
                "midterm","final","project","teacher","prof","professor","tutor","grade","gpa","research","thesis",
                "dissertation","paper","essay","campus","course","lesson","learning","curriculum","group project"
            ],
            12: [ // Spirituality/Religion
                "god","gods","faith","pray","prayer","church","mass","mosque","temple","synagogue","spiritual",
                "spirituality","bible","quran","koran","torah","meditate","meditation","mindful","mindfulness","retreat",
                "sunday service","hymn","worship","belief","soul","spirit","quiet time with god"
            ],
            13: [ // Recreation/Leisure
                "movie","film","cinema","tv","series","show","netflix","hulu","disney+","disney plus","hbomax","max","prime",
                "board game","boardgame","puzzle","craft","knit","knitting","garden","gardening","park","beach","pool",
                "outing","festival","concert","gig","sports","stadium","match","team","league","game night","movie night",
                "live music"
            ],
            14: [ // Travel/Nature
                "travel","trip","holiday","vacation","staycation","flight","airport","airplane","plane","train","road trip",
                "roadtrip","drive","drove","bus","bike tour","camp","camping","hike","trail","forest","woods","mountain",
                "lake","river","ocean","sea","nature","outdoors","journey","itinerary","adventure","national park"
            ],
            15: [ // Creativity/Art
                "create","creative","creativity","write","writing","wrote","draft","poem","poetry","novel","story","paint",
                "painting","draw","drawing","sketch","design","compose","song","music","practice","rehearsal","studio",
                "art","gallery","exhibit","photography","photo","film-making","craft","handmade","writer's block","first draft"
            ],
            16: [ // Community/Society/Politics
                "community","neighborhood","neighbourhood","volunteer","volunteering","charity","fundraiser","election",
                "vote","voted","politics","policy","protest","march","rally","civic","council","local news","news",
                "headline","crime","safety","public","government","parliament","senate","congress","food bank"
            ],
            17: [ // Technology/Media/Internet
                "phone","screen","scroll","scrolled","scrolling","social","socials","social media","facebook","instagram","ig",
                "tiktok","twitter","x.com","youtube","reddit","discord","slack","email","inbox","notifications","app","apps",
                "game","gaming","console","pc","mac","iphone","android","laptop","online","offline","internet","web","digital",
                "zoom","teams","facetime","doomscroll","doomscrolling","screen time","inbox zero"
            ],
            18: [ // Self/Growth/Habits
                "goal","goals","habit","habits","streak","journal","journaling","therapy homework","self-care","self care",
                "routine","morning routine","evening routine","reflection","reflect","intent","intentions","affirmation",
                "vision","plan","planning","review","check-in","check in","track","tracked","on track","back on track",
                "resolution","challenge","growth","mindset","practice","personal development","self improvement"
            ]
        ]
    }

    private func seedPhrases() -> [Int: [String]] {
        return [
            1: [ #"\\b(5k|10k|marathon|half marathon)\\b"#, #"\\bpersonal best\\b"# ],
            2: [ #"\\b(first )?birthday\\b"#, #"\\bfamily (dinner|gathering|reunion)\\b"# ],
            4: [ #"\\bdate night\\b"#, #"\\bmarriage counseling|couples therapy\\b"# ],
            6: [ #"\\b(gluten[- ]free|dairy[- ]free|vegan|vegetarian)\\b"#, #"\\bhome[- ]cooked\\b"# ],
            9: [ #"\\b(first|back) day back to work\\b"#, #"\\b(work(ed)? online)\\b"#, #"\\b(an assignment.*rejected)\\b"#, #"\\bcode review\\b"# ],
            10:[ #"\\b(earnings goal)\\b"#, #"\\b(pay(ing)? bills)\\b"#, #"\\b(make money)\\b"#, #"\\bdirect deposit\\b"# ],
            11:[ #"\\bfinal exam\\b"#, #"\\bpeer review\\b"#, #"\\bgroup project\\b"# ],
            12:[ #"\\bsunday service\\b"#, #"\\b(quiet )?time with god\\b"# ],
            13:[ #"\\bmovie night\\b"#, #"\\bgame night\\b"#, #"\\blive music\\b"# ],
            14:[ #"\\broad (?:trip|trips)\\b"#, #"\\bnational park\\b"# ],
            15:[ #"\\bwriter'?s block\\b"#, #"\\bfirst draft\\b"# ],
            16:[ #"\\b(voted|vote|election day)\\b"#, #"\\bfood bank\\b"# ],
            17:[ #"\\bdoomscroll(?:ing)?\\b"#, #"\\bscreen time\\b"#, #"\\binbox zero\\b"# ],
            18:[ #"\\b(back|getting) on track\\b"#, #"\\bmorning routine\\b"# ]
        ]
    }

    // MARK: Utils

    private func splitSentences(_ text: String) -> [String] {
        let rough = text.replacingOccurrences(of: "\n", with: " . ")
        let parts = rough.split(whereSeparator: { ".!?".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }
        return parts.filter { !$0.isEmpty }
    }

    private func labelFor(_ id: Int) -> String { labels[id] ?? "Unknown" }
}

// MARK: - Test Rig Adapter

public struct DomainProAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .domain
    public let name: String = "Domain • Rules Pro"
    private let clf = DomainClassifierPro()
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
