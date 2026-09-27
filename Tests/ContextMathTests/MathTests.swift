import ContextDomain
import ContextMath
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
