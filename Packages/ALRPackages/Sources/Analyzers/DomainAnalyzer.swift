import CoreTypes
import Foundation

public struct DomainAnalyzer: Analyzer {
    public let category: AlgorithmCategory = .domains
    public let name: String = "RuleDomain"

    public init() {}

    public func analyze(_ input: AnalyzerInput) throws -> AnalyzerOutput {
        let t = input.selectedText.lowercased()
        var results: [(String, Double)] = []

        // Work domain
        if t.contains("boss") || t.contains("office") || t.contains("work") ||
            t.contains("meeting") || t.contains("deadline") || t.contains("project") ||
            t.contains("colleague") || t.contains("manager") || t.contains("job")
        {
            results.append(("Work", 0.9))
        }

        // Relationships domain
        if t.contains("wife") || t.contains("husband") || t.contains("partner") ||
            t.contains("boyfriend") || t.contains("girlfriend") || t.contains("spouse") ||
            t.contains("dating") || t.contains("relationship")
        {
            results.append(("Relationships", 0.85))
        }

        // Family domain
        if t.contains("mother") || t.contains("father") || t.contains("mom") ||
            t.contains("dad") || t.contains("parent") || t.contains("sibling") ||
            t.contains("brother") || t.contains("sister") || t.contains("family")
        {
            results.append(("Family", 0.85))
        }

        // School domain
        if t.contains("school") || t.contains("class") || t.contains("study") ||
            t.contains("homework") || t.contains("exam") || t.contains("teacher") ||
            t.contains("professor") || t.contains("university") || t.contains("college")
        {
            results.append(("School", 0.8))
        }

        // Health domain
        if t.contains("doctor") || t.contains("hospital") || t.contains("sick") ||
            t.contains("health") || t.contains("medicine") || t.contains("pain") ||
            t.contains("therapy") || t.contains("symptom")
        {
            results.append(("Health", 0.75))
        }

        // Money domain
        if t.contains("money") || t.contains("budget") || t.contains("expense") ||
            t.contains("debt") || t.contains("loan") || t.contains("mortgage") ||
            t.contains("rent") || t.contains("financial") || t.contains("salary")
        {
            results.append(("Money", 0.75))
        }

        // Default neutral if no specific domain detected
        if results.isEmpty {
            results.append(("General", 0.5))
        }

        // Sort by score and format output
        let top = results.sorted { $0.1 > $1.1 }
        let desc = top.map { "\($0.0): \(String(format: "%.2f", $0.1))" }.joined(separator: ", ")

        // Store top domain in metadata for other analyzers to use
        var metadata: [String: String] = [:]
        if let topDomain = top.first {
            metadata["topDomain"] = topDomain.0
            metadata["topScore"] = String(format: "%.2f", topDomain.1)
        }

        return AnalyzerOutput(
            category: .domains,
            name: name,
            result: desc,
            durationMS: 0,
            metadata: metadata
        )
    }
}
