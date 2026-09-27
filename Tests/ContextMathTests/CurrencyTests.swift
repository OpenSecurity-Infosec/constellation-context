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
}
