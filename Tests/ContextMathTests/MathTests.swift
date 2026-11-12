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

    @Test func thousandsFoldOnce() {
        #expect(engine.lineNumbers("1,000") == [1000])
        #expect(engine.lineNumbers("1,000,000") == [1000000])
        #expect(engine.aggregate("1,000\n2,000", mode: .sum) == 3000)
    }

    @Test func isoDatesIgnored() {
        #expect(engine.lineNumbers("due 2024-01-15") == [])
        #expect(engine.aggregate("2024-01-15\n5", mode: .sum) == 5)
    }

    @Test func contributionsMapLines() {
        #expect(engine.contributions(text: "2 + 3\nno numbers\n// 9\n4") == [[2, 3], [], [], [4]])
    }

    @Test func aggregateMatchesContributions() {
        let text = "oats 2\n1,000\n// skip 9\ndue 2024-01-15\n3.5"
        let flat = engine.contributions(text: text).flatMap { $0 }
        #expect(engine.aggregate(text, mode: .sum) == flat.reduce(0, +))
        #expect(engine.aggregate(text, mode: .avg) == flat.reduce(0, +) / Double(flat.count))
    }

    @Test func mixedContentLiveUpdate() {
        #expect(engine.aggregate("milk 2\neggs 3", mode: .sum) == 5)
        #expect(engine.aggregate("milk 2\neggs 30", mode: .sum) == 32)
        #expect(engine.aggregate("nothing here", mode: .sum) == nil)
        #expect(engine.aggregate("nothing here", mode: .avg) == nil)
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

@Suite struct ReactiveVariableMathTests {
    private let engine = MathEngine()
    private func rated() -> MathEngine {
        MathEngine(rates: CurrencyRates.Snapshot(
            fetchedAt: Date(), usdPerUnit: ["USD": 1.0, "EUR": 1.1]
        ))
    }

    private func displays(_ note: String) -> [String?] {
        engine.evaluate(note: note).map { $0?.display }
    }

    // MARK: Order, redefinition, recalculation

    @Test func recalculatesDownNotUp() {
        let out = displays("x = 2\ny = x * 3\nx = 10\nz = x * 3\ny\nz")
        #expect(out == ["2", "6", "10", "30", "6", "30"])
    }

    @Test func redefinitionShadowsForLinesBelow() {
        #expect(displays("price = 10\nprice\nprice = 4\nprice") == ["10", "10", "4", "4"])
    }

    @Test func editingUpstreamRecalculatesDependents() {
        #expect(engine.evaluate(note: "price = 10\ntotal = price * 3")[1]?.display == "30")
        #expect(engine.evaluate(note: "price = 20\ntotal = price * 3")[1]?.display == "60")
        // No state leaks between evaluations.
        #expect(engine.evaluateLines(note: "total") == [.error(.unknownVariable("total"))])
    }

    @Test func commentsAndBlanksDoNotBreakTheChain() {
        let out = engine.evaluateLines(note: "x = 2\n// note\n\nx + 1")
        #expect(out[1] == .blank)
        #expect(out[2] == .blank)
        #expect(out[3] == .value(MathEngine.LineResult(value: 3, display: "3")))
    }

    @Test func variableOnlyExpressionsEvaluate() {
        #expect(displays("a = 2\nb = 3\na * b") == ["2", "3", "6"])
        #expect(displays("a = 2\nb = 3\n(a + b) * a") == ["2", "3", "10"])
    }

    @Test func whitespaceVariantsAssign() {
        #expect(displays("x=5\ny =x+1\n  z   =   y * 2  \nz") == ["5", "6", "12", "12"])
    }

    @Test func selfIncrementUsesPreviousValue() {
        #expect(displays("count = 1\ncount = count + 1\ncount") == ["1", "2", "2"])
    }

    // MARK: Gutter display

    @Test func assignmentGutterNamesTheVariable() {
        let out = engine.evaluateLines(note: "price = 10\nprice * 2")
        #expect(out[0] == .value(MathEngine.LineResult(value: 10, display: "10", assignedName: "price")))
        if case .value(let r) = out[0] { #expect(r.gutterDisplay == "price = 10") }
        if case .value(let r) = out[1] { #expect(r.gutterDisplay == "20") }
    }

    @Test func errorMessagesReadInTheGutter() {
        #expect(MathEngine.LineError.unknownVariable("tax").message == "unknown tax")
        #expect(MathEngine.LineError.forwardReference("tax").message == "tax defined below")
        #expect(MathEngine.LineError.cycle("a").message == "cycle: a")
        #expect(MathEngine.LineError.invalidVariableName("1x").message == "bad name 1x")
        #expect(MathEngine.LineError.reservedVariableName("in").message == "reserved in")
    }

    // MARK: Forward references, undefined names, failed assignments

    @Test func forwardReferenceInAssignmentAndBareName() {
        let out = engine.evaluateLines(note: "total = price * 3\nprice = 10\nprice")
        #expect(out[0] == .error(.forwardReference("price")))
        #expect(out[2] == .value(MathEngine.LineResult(value: 10, display: "10")))
        #expect(engine.evaluateLines(note: "price\nprice = 10").first == .error(.forwardReference("price")))
    }

    @Test func undefinedVariableInExpressionIsNotRescuedBySuffix() {
        #expect(engine.evaluateLines(note: "tax * 2") == [.error(.unknownVariable("tax"))])
        #expect(engine.evaluateLines(note: "2 + tax") == [.error(.unknownVariable("tax"))])
        #expect(engine.evaluateLines(note: "(tax)") == [.error(.unknownVariable("tax"))])
        #expect(engine.evaluateLines(note: "x = nope + 1") == [.error(.unknownVariable("nope"))])
        // Descriptive labels are still prose, not variables.
        #expect(engine.evaluate(note: "oats 2 + 2").first??.display == "4")
    }

    @Test func failedAssignmentClearsInsteadOfKeepingStaleValue() {
        let out = engine.evaluateLines(note: "x = 5\nx = 1/0\nx")
        #expect(out[1] == .error(.divideByZero))
        #expect(out[2] == .error(.unknownVariable("x")))
        let out2 = engine.evaluateLines(note: "x = nope\nx")
        #expect(out2[0] == .error(.unknownVariable("nope")))
        #expect(out2[1] == .error(.unknownVariable("x")))
    }

    // MARK: Cycles

    @Test func selfReferenceWithoutPriorValueIsACycle() {
        let out = engine.evaluateLines(note: "x = x + 1\nx")
        #expect(out == [.error(.cycle("x")), .error(.cycle("x"))])
    }

    @Test func mutualAndThreeWayCycles() {
        let out = engine.evaluateLines(note: "a = b + 1\nb = a + 1\na")
        #expect(out == [.error(.cycle("a")), .error(.cycle("b")), .error(.cycle("a"))])
        let three = engine.evaluateLines(note: "a = b\nb = c\nc = a")
        #expect(three == [.error(.cycle("a")), .error(.cycle("b")), .error(.cycle("c"))])
    }

    @Test func forwardChainIsNotACycle() {
        let out = engine.evaluateLines(note: "a = b + 1\nb = 2\nb")
        #expect(out[0] == .error(.forwardReference("b")))
        #expect(out[2] == .value(MathEngine.LineResult(value: 2, display: "2")))
    }

    @Test func cycleCanBeBrokenByLaterRedefinition() {
        let out = engine.evaluateLines(note: "a = b\nb = a\na = 5\na")
        #expect(out[0] == .error(.cycle("a")))
        #expect(out[1] == .error(.cycle("b")))
        #expect(out[3] == .value(MathEngine.LineResult(value: 5, display: "5")))
        #expect(displays("b = 1\na = b\nb = a\nb") == ["1", "1", "1", "1"])
    }

    @Test func reusedNamesDownTheNoteAreNotACycle() {
        #expect(displays("x = 1\ny = x + 1\nx = y + 1\nx") == ["1", "2", "3", "3"])
    }

    @Test func longChainRecalculatesWithoutRecursionBlowup() {
        var lines = ["a0 = 1"]
        for i in 1...500 { lines.append("a\(i) = a\(i - 1) + 1") }
        lines.append("a500")
        let out = engine.evaluate(note: lines.joined(separator: "\n"))
        #expect(out.last??.display == "501")
    }

    // MARK: Assignment and name syntax

    @Test func assignmentSyntaxErrors() {
        #expect(engine.evaluateLines(note: "a = b = 5") == [.error(.syntax)])
        #expect(engine.evaluateLines(note: "a == 5") == [.error(.syntax)])
        #expect(engine.evaluateLines(note: "a <= 5") == [.error(.syntax)])
        #expect(engine.evaluateLines(note: "2 + 3 = 5") == [.error(.syntax)])
        #expect(engine.evaluateLines(note: "= 5") == [.error(.invalidVariableName(""))])
    }

    @Test func invalidAndReservedNames() {
        #expect(engine.evaluateLines(note: "1x = 5") == [.error(.invalidVariableName("1x"))])
        #expect(engine.evaluateLines(note: "my price = 5") == [.error(.invalidVariableName("my price"))])
        #expect(engine.evaluateLines(note: "x-y = 5") == [.error(.invalidVariableName("x-y"))])
        #expect(engine.evaluateLines(note: "in = 5") == [.error(.reservedVariableName("in"))])
        #expect(engine.evaluateLines(note: "To = 5") == [.error(.reservedVariableName("To"))])
    }

    @Test func unicodeUnderscoreAndCaseSensitiveNames() {
        #expect(displays("café = 3\nλ_rate = café * 2\nλ_rate") == ["3", "6", "6"])
        #expect(displays("_total = 5\n_total + 1") == ["5", "6"])
        #expect(displays("price = 1\nPrice = 2\nprice + Price") == ["1", "2", "3"])
        #expect(engine.evaluateLines(note: "Price = 10\nprice")[1] == .error(.unknownVariable("price")))
    }

    @Test func keywordUnitAndCurrencyNamesWork() {
        #expect(displays("sum = 2 + 3\navg = sum / 5\navg") == ["5", "1", "1"])
        #expect(displays("km = 5\nkm * 2") == ["5", "10"])
        #expect(displays("usd = 7\nusd * 2") == ["7", "14"])
        // Conversion syntax still wins on conversion-shaped lines.
        let conv = engine.evaluate(note: "km = 5\n10 km in mi")
        #expect(abs((conv[1]?.value ?? 0) - 6.2137) < 0.01)
    }

    // MARK: Units and currency

    @Test func assignmentFromUnitConversion() {
        let out = engine.evaluate(note: "dist = 10 km in mi\ndist * 2")
        #expect(abs((out[0]?.value ?? 0) - 6.2137) < 0.01)
        #expect(abs((out[1]?.value ?? 0) - 12.4274) < 0.01)
        #expect(out[0]?.assignedName == "dist")
    }

    @Test func variableAsConversionAmount() {
        let out = engine.evaluate(note: "d = 10\n(d * 2) km in mi")
        #expect(abs((out[1]?.value ?? 0) - 12.4274) < 0.01)
        #expect(engine.evaluateLines(note: "nope km in mi") == [.error(.unknownVariable("nope"))])
        #expect(engine.evaluateLines(note: "nope * 2 km in mi") == [.error(.unknownVariable("nope"))])
        #expect(engine.evaluateLines(note: "d km in mi\nd = 10").first == .error(.forwardReference("d")))
    }

    @Test func badConversionAssignmentDefinesNothing() {
        let out = engine.evaluateLines(note: "dist = 10 km in blorp\ndist")
        #expect(out[0] == .error(.unknownUnit("blorp")))
        #expect(out[1] == .error(.unknownVariable("dist")))
    }

    @Test func assignmentFromCurrencyConversion() {
        let out = rated().evaluate(note: "price = 100\nin_eur = price USD in EUR\nin_eur * 2")
        #expect(abs((out[1]?.value ?? 0) - 90.909) < 0.01)
        #expect(abs((out[2]?.value ?? 0) - 181.818) < 0.01)
        let offline = engine.evaluateLines(note: "fee = 100 USD in EUR\nfee")
        #expect(offline[0] == .error(.noRates))
        #expect(offline[1] == .error(.unknownVariable("fee")))
    }

    // MARK: sum / avg interaction

    @Test func sumCountsVariableUsesNotDefinitions() {
        #expect(engine.contributions(text: "price = 10\nprice\n20") == [[], [10], [20]])
        #expect(engine.aggregate("price = 10\nprice\n20", mode: .sum) == 30)
        #expect(engine.contributions(text: "price = 10\nprice * 3\noats 2") == [[], [30], [2]])
    }

    @Test func avgIsNotDilutedByAssignments() {
        #expect(engine.aggregate("x = 100\n2\n4", mode: .avg) == 3)
        #expect(engine.contributions(text: "x = 2\nx\nx = 5\nx") == [[], [2], [], [5]])
        #expect(engine.aggregate("x = 2\nx\nx = 5\nx", mode: .avg) == 3.5)
    }

    @Test func sumKeepsLiteralCountingAndHonorsConversions() {
        #expect(engine.contributions(text: "price = 10\n2 apples 3 pears") == [[], [2, 3]])
        let conv = engine.contributions(text: "d = 10 km in mi\nd")
        #expect(conv[0] == [])
        #expect(abs((conv[1].first ?? 0) - 6.2137) < 0.01)
        #expect(engine.aggregate("sum = 5\nsum", mode: .sum) == 5)
        #expect(engine.contributions(text: "x = 1/0\nx\n3") == [[], [], [3]])
    }
}

@Suite struct MathPerfTests {
    private func bigNote(lines: Int) -> String {
        var out: [String] = []
        out.reserveCapacity(lines)
        for i in 0..<lines {
            switch i % 6 {
            case 0: out.append("v\(i) = \(i) * 1.5")
            case 1: out.append("oats \(i) + \(i)")
            case 2: out.append("\(i) km in mi")
            case 3: out.append("just some prose words here")
            case 4: out.append("\(i)/0")
            default: out.append("total = v0 + \(i)")
            }
        }
        return out.joined(separator: "\n")
    }

    @Test func twoThousandLinesStaysResponsive() {
        let engine = MathEngine()
        let note = bigNote(lines: 2000)
        let start = Date()
        let out = engine.evaluateLines(note: note)
        let elapsed = Date().timeIntervalSince(start)
        #expect(out.count == 2000)
        print("PERF full 2000-line eval: \(elapsed)s")
        #expect(elapsed < 1.0)
    }

    @Test func tenThousandLinesStaysBounded() {
        let engine = MathEngine()
        let note = bigNote(lines: 10_000)
        let start = Date()
        let out = engine.evaluateLines(note: note)
        let elapsed = Date().timeIntervalSince(start)
        #expect(out.count == 10_000)
        print("PERF full 10000-line eval: \(elapsed)s")
        #expect(elapsed < 5.0)
    }

    @Test func largeNoteKeepsErrorsAndValues() {
        let engine = MathEngine()
        let out = engine.evaluateLines(note: bigNote(lines: 12))
        // Spot-check the 6-line cycle: assign, suffix, conversion, prose, div0, assign.
        #expect(out[3] == .blank)
        #expect(out[4] == .error(.divideByZero))
        if case .value = out[0] {} else { Issue.record("expected value at line 0, got \(out[0])") }
    }
}

@Suite struct MathInlineCommentTests {
    @Test func commentsDoNotCreateDependenciesOrAssignments() {
        let result = MathEngine().evaluate(note: "price = 10 // total = price * 9\ntotal = price * 3 // total + missing\ntotal // = 999\n// ignored = total")
        #expect(result.map { $0?.value } == [10, 30, 30, nil])
    }

    @Test func commentsPreserveConversionsDivisionAndErrors() {
        let engine = MathEngine()
        let result = engine.evaluate(note: "12 / 3 // portions\n2 km in m // distance\n5+2//tight")
        #expect(result.map { $0?.value } == [4, 2000, 7])
        #expect(engine.evaluateLines(note: "x = 4\nx = 1 / 0 // invalid\nx") [1] == .error(.divideByZero))
        #expect(engine.evaluateLines(note: "x = 4\nx = 1 / 0 // invalid\nx") [2] == .error(.unknownVariable("x")))
    }
}
