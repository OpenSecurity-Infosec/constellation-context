import ContextDomain
import ContextMath
import Foundation
import Testing

@Suite struct CurrencyTests {
    private func engine() -> MathEngine {
        let snap = CurrencyRates.Snapshot(
            fetchedAt: Date(),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1, "GBP": 1.27, "BTC": 60000.0]
        )
        return MathEngine(rates: snap)
    }

    @Test func fiatConversion() {
        let out = engine().evaluate(note: "100 USD in EUR")
        let value = out.first??.value ?? 0
        #expect(abs(value - 90.909) < 0.01)
    }

    @Test func toKeywordWorks() {
        let out = engine().evaluate(note: "100 CAD to USD")
        // CAD unknown in the injected table → no result, never a crash.
        #expect(out.first??.value == nil)
    }

    @Test func cryptoConversion() {
        let out = engine().evaluate(note: "0.5 BTC in USD")
        #expect(out.first??.value == 30000)
    }

    @Test func unknownPairYieldsNil() {
        let out = engine().evaluate(note: "10 XYZ in USD")
        #expect(out.count == 1)
        #expect(out[0] == nil)
    }

    @Test func offlineEngineSkipsCurrency() {
        let out = MathEngine().evaluate(note: "10 USD in EUR")
        #expect(out.count == 1)
        #expect(out[0] == nil)
    }

    @Test func variablesStillWorkWithRates() {
        let out = engine().evaluate(note: "fee = 10\nfee USD in EUR")
        let value = out[1]?.value ?? 0
        #expect(abs(value - 9.09) < 0.01)
    }

    @Test func snapshotRateMath() {
        let snap = CurrencyRates.Snapshot(fetchedAt: Date(), usdPerUnit: ["USD": 1, "EUR": 1.1])
        #expect(abs((snap.rate(from: "USD", to: "EUR") ?? 0) - 0.909) < 0.001)
        #expect(CurrencyRates.isCurrency("btc"))
        #expect(!CurrencyRates.isCurrency("km"))
    }

    @Test func freshnessClassifies() {
        let now = Date()
        #expect(CurrencyRates.freshness(of: nil, now: now) == .unavailable)
        let fresh = CurrencyRates.Snapshot(fetchedAt: now, usdPerUnit: ["USD": 1])
        #expect(CurrencyRates.freshness(of: fresh, now: now) == .live)
        let stale = CurrencyRates.Snapshot(
            fetchedAt: now.addingTimeInterval(-7200), usdPerUnit: ["USD": 1]
        )
        #expect(CurrencyRates.freshness(of: stale, now: now) == .cachedStale)
    }

    @Test func ageLabelReads() {
        let now = Date()
        #expect(CurrencyRates.ageLabel(since: now, now: now) == "just now")
        #expect(CurrencyRates.ageLabel(since: now.addingTimeInterval(-1500), now: now) == "25m ago")
        #expect(CurrencyRates.ageLabel(since: now.addingTimeInterval(-10800), now: now) == "3h ago")
    }

    private func store(file: String) -> RateStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        return RateStore(fileURL: url)
    }

    @Test func totalOutageKeepsOldSnapshot() async {
        let s = store(file: "ctx-outage-\(UUID().uuidString).json")
        let old = CurrencyRates.Snapshot(
            fetchedAt: Date().addingTimeInterval(-7200),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        )
        s.inject(old)
        s.fetchOverride = { _ in throw URLError(.notConnectedToInternet) }
        #expect(await s.refresh() == false)
        #expect(s.current?.usdPerUnit["EUR"] == 1.1)
    }

    @Test func timeoutKeepsOldSnapshot() async {
        let s = store(file: "ctx-timeout-\(UUID().uuidString).json")
        let old = CurrencyRates.Snapshot(
            fetchedAt: Date().addingTimeInterval(-7200),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        )
        s.inject(old)
        s.fetchOverride = { _ in throw URLError(.timedOut) }
        #expect(await s.refresh() == false)
        #expect(s.current?.fetchedAt == old.fetchedAt)
    }

    @Test func badResponseKeepsOldSnapshot() async {
        let s = store(file: "ctx-bad-\(UUID().uuidString).json")
        let old = CurrencyRates.Snapshot(
            fetchedAt: Date().addingTimeInterval(-7200),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        )
        s.inject(old)
        s.fetchOverride = { _ in Data("not json at all".utf8) }
        #expect(await s.refresh() == false)
        #expect(s.current?.usdPerUnit["EUR"] == 1.1)
    }

    @Test func noCacheOutageStaysUnavailable() async {
        let s = store(file: "ctx-nocache-\(UUID().uuidString).json")
        s.fetchOverride = { _ in throw URLError(.notConnectedToInternet) }
        #expect(await s.refresh() == false)
        #expect(s.current == nil)
        #expect(CurrencyRates.freshness(of: s.current) == .unavailable)
        let out = MathEngine(rates: s.current).evaluate(note: "10 USD in EUR")
        #expect(out[0] == nil)
    }

    @Test func recoveryRefreshesSnapshot() async {
        let s = store(file: "ctx-recover-\(UUID().uuidString).json")
        let old = CurrencyRates.Snapshot(
            fetchedAt: Date().addingTimeInterval(-7200),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        )
        s.inject(old)
        s.fetchOverride = { url in
            if url.contains("frankfurter") {
                return Data("{\"rates\":{\"EUR\":0.9}}".utf8)
            }
            throw URLError(.notConnectedToInternet)
        }
        #expect(await s.refresh() == true)
        let eur = s.current?.usdPerUnit["EUR"] ?? 0
        #expect(abs(eur - (1.0 / 0.9)) < 0.001)
    }

    @Test func staleCacheStillConverts() {
        let stale = CurrencyRates.Snapshot(
            fetchedAt: Date().addingTimeInterval(-7200),
            usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        )
        let out = MathEngine(rates: stale).evaluate(note: "100 USD in EUR")
        #expect(abs((out.first??.value ?? 0) - 90.909) < 0.01)
    }
}
