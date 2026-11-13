import Foundation
import ContextVault

@main struct ContextBench {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: context-bench <vault-path>")
            exit(2)
        }
        do {
            let connector = ObsidianConnector(id: "bench", displayName: "Benchmark", root: URL(fileURLWithPath: CommandLine.arguments[1]))
            let clock = ContinuousClock()
            func milliseconds(_ duration: Duration) -> Double {
                Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            }
            var start = clock.now
            let notes = try await connector.list()
            let cold = milliseconds(start.duration(to: clock.now))
            guard !notes.isEmpty else { print("FAIL: empty vault"); exit(2) }
            start = clock.now
            _ = try await connector.list()
            let warm = milliseconds(start.duration(to: clock.now))
            // Same connector.search entry point used by Library; include reconciliation.
            let queries = ["project", "context", "meeting", "daily", "notes", "the", "计划", "café", "[[", "zzbenchmarkmissingzz"]
            var samples: [Double] = []
            var hits = 0
            for _ in 0..<10 {
                for query in queries {
                    start = clock.now
                    hits += try await connector.search(query).count
                    samples.append(milliseconds(start.duration(to: clock.now)))
                }
            }
            samples.sort()
            let p50 = samples[Int(ceil(Double(samples.count) * 0.50)) - 1]
            let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
            print(String(format: "notes=%d cold_index_ms=%.2f warm_index_ms=%.2f search_p50_ms=%.2f search_p95_ms=%.2f samples=%d hits=%d budget_ms=100 %@", notes.count, cold, warm, p50, p95, samples.count, hits, p95 <= 100 ? "PASS" : "FAIL"))
            if p95 > 100 { exit(1) }
        } catch {
            // Connector errors may contain private paths or note names.
            print("FAIL: vault could not be indexed or searched")
            exit(2)
        }
    }
}
