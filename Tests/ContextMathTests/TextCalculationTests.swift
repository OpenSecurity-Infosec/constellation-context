import ContextMath
import Testing

@Suite struct TextCalculationTests {
    @Test func explicitCalculationsPreserveInputsAndHandleErrors() {
        let input = "price = 10\nprice * 2\n1 / 0"
        let result = TextCalculation.run(name: "math", text: input)
        #expect(result == "price = 10\n20\n÷ by 0")
        #expect(TextCalculation.run(name: "sum", text: "2\n4") == "6")
        #expect(TextCalculation.run(name: "avg", text: "2\n4") == "3")
        #expect(TextCalculation.run(name: "paste", text: input) == nil)
        #expect(TextCalculation.run(name: "math", text: "10 USD in EUR") == "no rates — offline?")
    }
}
