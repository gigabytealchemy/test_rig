import Analyzers
import CoreTypes
import Foundation
import os
import SwiftUI

@MainActor
final class Coordinator: ObservableObject {
    @Published var text: String = ""
    @Published var selectionRange: Range<String.Index>?
    @Published var resultsByCategory: [AlgorithmCategory: [AnalyzerOutput]] = [:]
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    private let registry: AlgorithmRegistry
    private var runTask: Task<Void, Never>?

    init(registry: AlgorithmRegistry) {
        self.registry = registry
    }

    func runAll(fallbackEmotion: String? = nil,
                timeoutPerAnalyzer: Duration = .seconds(3)) {
        runTask?.cancel()
        isRunning = true
        lastError = nil
        let input = AnalyzerInput(fullText: text,
                                  selectedRange: selectionRange,
                                  fallbackEmotion: fallbackEmotion)

        runTask = Task {
            let analyzers = registry.analyzers

            await withTaskGroup(of: (AlgorithmCategory, AnalyzerOutput?)?.self) { group in
                for analyzer in analyzers {
                    group.addTask {
                        let start = ContinuousClock.now
                        do {
                            let output = try analyzer.analyze(input)
                            let elapsed = Int(ContinuousClock.now.duration(to: start).components.seconds * -1000)
                            return (analyzer.category,
                                    AnalyzerOutput(category: analyzer.category,
                                                   name: analyzer.name,
                                                   result: output.result,
                                                   durationMS: elapsed,
                                                   metadata: output.metadata))
                        } catch {
                            return (analyzer.category,
                                    AnalyzerOutput(category: analyzer.category,
                                                   name: analyzer.name,
                                                   result: "❌ \(error.localizedDescription)",
                                                   durationMS: 0,
                                                   metadata: [:]))
                        }
                    }
                }

                var grouped: [AlgorithmCategory: [AnalyzerOutput]] = [:]
                for await item in group {
                    guard let (cat, out) = item, let out else { continue }
                    grouped[cat, default: []].append(out)
                }
                await MainActor.run {
                    self.resultsByCategory = grouped
                }
            }

            await MainActor.run {
                self.isRunning = false
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        isRunning = false
    }
}
