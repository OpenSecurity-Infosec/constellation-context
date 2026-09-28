import ContextDomain
import ContextMath
import Foundation
import Testing

@Suite struct MathTests {
    private let engine = MathEngine()

    @Test func arithmetic() {
        let out = engine.evaluate(note: "2 + 3 * 4")
        #expect(out.first??.display == "14")
    }

    @Test func variablesReact() {
        let out = engine.evaluate(note: "price = 10\ntotal = price * 3\ntotal")
        #expect(out[1]?.display == "30")
        #expect(out[2]?.display == "30")
    }

    @Test func descriptiveText() {
        let out = engine.evaluate(note: "oats 2 + 2")
        #expect(out.first??.display == "4")
    }

    @Test func conversion() {
        let out = engine.evaluate(note: "10 km in mi")
        let value = out.first??.value ?? 0
        #expect(abs(value - 6.2137) < 0.01)
    }

    @Test func sumIgnoresComments() {
        let total = engine.aggregate("1\n2\n// 100", mode: .sum)
        #expect(total == 3)
    }

    @Test func average() {
        let avg = engine.aggregate("2\n4", mode: .avg)
        #expect(avg == 3)
    }
}

@Suite struct MathErrorTests {
    private let engine = MathEngine()
    private func rated() -> MathEngine {
        MathEngine(rates: CurrencyRates.Snapshot(
            fetchedAt: Date(), usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        ))
    }

    @Test func syntaxErrorShows() {
        #expect(engine.evaluateLines(note: "2 +") == [.error(.syntax)])
    }

    @Test func divideByZeroShows() {
        #expect(engine.evaluateLines(note: "1/0") == [.error(.divideByZero)])
        #expect(engine.evaluateLines(note: "10 % 0") == [.error(.divideByZero)])
    }

    @Test func unknownUnitShows() {
        let out = engine.evaluateLines(note: "10 blarg in blorp")
        #expect(out == [.error(.unknownUnit("blorp"))])
    }

    @Test func unknownCurrencyOfflineShows() {
        #expect(engine.evaluateLines(note: "10 USD in EUR") == [.error(.noRates)])
    }

    @Test func unknownVariableShows() {
        #expect(engine.evaluateLines(note: "frobnicate") == [.error(.unknownVariable("frobnicate"))])
    }

    @Test func proseStaysBlank() {
        #expect(engine.evaluateLines(note: "hello world") == [.blank])
        #expect(engine.evaluateLines(note: "// comment") == [.blank])
    }

    @Test func mixedNoteIsolatesFailure() {
        let out = engine.evaluateLines(note: "2 + 2\n1/0\n3 * 3")
        #expect(out[0] == .value(MathEngine.LineResult(value: 4, display: "4")))
        #expect(out[1] == .error(.divideByZero))
        #expect(out[2] == .value(MathEngine.LineResult(value: 9, display: "9")))
    }

    @Test func fixClearsError() {
        #expect(engine.evaluateLines(note: "1/") == [.error(.syntax)])
        let fixed = engine.evaluateLines(note: "1/2")
        #expect(fixed == [.value(MathEngine.LineResult(value: 0.5, display: "0.5"))])
    }

    @Test func badAssignmentShows() {
        #expect(engine.evaluateLines(note: "x = ") == [.error(.syntax)])
        #expect(engine.evaluateLines(note: "x = 1/0") == [.error(.divideByZero)])
    }

    @Test func currencyRecoversWithRates() {
        #expect(engine.evaluateLines(note: "100 USD in EUR") == [.error(.noRates)])
        let out = rated().evaluateLines(note: "100 USD in EUR")
        if case .value(let r) = out.first {
            #expect(abs(r.value - 90.909) < 0.01)
        } else {
            Issue.record("expected a value, got \(out)")
        }
    }

    @Test func legacyEvaluateStillNilOnError() {
        #expect(engine.evaluate(note: "1/0").first! == nil)
        #expect(engine.evaluate(note: "2 + 2").first??.display == "4")
    }
}
