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
    private let log = Logger(subsystem: "com.yourorg.testrig", category: "rig.run")

    init(registry: AlgorithmRegistry) {
        self.registry = registry
    }

    func runAll(fallbackEmotion: String? = nil,
                timeoutPerAnalyzer: Duration = .seconds(3))
    {
        runTask?.cancel()
        isRunning = true
        lastError = nil
        let input = AnalyzerInput(fullText: text,
                                  selectedRange: selectionRange,
                                  fallbackEmotion: fallbackEmotion)

        runTask = Task {
            log.info("Run start; analyzers=\(self.registry.analyzers.count, privacy: .public)")
            defer {
                Task { @MainActor in
                    self.isRunning = false
                    self.log.info("Run end")
                }
            }

            let analyzers = registry.analyzers

            await withTaskGroup(of: (AlgorithmCategory, AnalyzerOutput)?.self) { group in
                for analyzer in analyzers {
                    group.addTask {
                        let start = ContinuousClock.now
                        do {
                            let output = try await self.runWithTimeout(timeoutPerAnalyzer) {
                                try analyzer.analyze(input)
                            }
                            let elapsed = Int(ContinuousClock.now.duration(to: start).components.seconds * 1000)
                            self.log.debug("Analyzer \(analyzer.name, privacy: .public) finished in \(elapsed) ms")
                            return (analyzer.category, AnalyzerOutput(
                                category: analyzer.category,
                                name: analyzer.name,
                                result: output.result,
                                durationMS: elapsed,
                                metadata: output.metadata
                            ))
                        } catch TimeoutError.timedOut {
                            let elapsed = Int(timeoutPerAnalyzer.components.seconds * 1000)
                            self.log.warning("Analyzer \(analyzer.name, privacy: .public) timed out after \(elapsed) ms")
                            return (analyzer.category, AnalyzerOutput(
                                category: analyzer.category,
                                name: analyzer.name,
                                result: "⏱️ Timed out",
                                durationMS: elapsed,
                                metadata: [:]
                            ))
                        } catch {
                            self.log.error("Analyzer \(analyzer.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                            return (analyzer.category, AnalyzerOutput(
                                category: analyzer.category,
                                name: analyzer.name,
                                result: "❌ \(error.localizedDescription)",
                                durationMS: 0,
                                metadata: [:]
                            ))
                        }
                    }
                }

                var grouped: [AlgorithmCategory: [AnalyzerOutput]] = [:]
                for await item in group {
                    guard let (cat, out) = item else { continue }
                    grouped[cat, default: []].append(out)
                }

                await MainActor.run {
                    self.resultsByCategory = grouped
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        isRunning = false
        log.info("Run cancelled by user")
    }
}

// MARK: - Timeout helper

enum TimeoutError: Error { case timedOut }

private extension Coordinator {
    func runWithTimeout<T>(_ duration: Duration,
                           operation: @escaping () throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError.timedOut
            }
            do {
                let value = try await group.next()!
                group.cancelAll()
                return value
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
