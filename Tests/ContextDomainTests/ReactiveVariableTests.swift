import ContextDomain
import Testing

@Suite struct ReactiveVariableTests {
    @Test func plainAndUnderscoreNames() {
        for name in ["price", "_price", "price_2", "x1", "x", "_", "Price"] {
            #expect(ReactiveVariable.isValidName(name), "\(name) should be valid")
        }
    }

    @Test func unicodeNames() {
        for name in ["café", "prénom", "λ_rate", "über_price", "变量"] {
            #expect(ReactiveVariable.isValidName(name), "\(name) should be valid")
        }
    }

    @Test func triggerUnitAndCurrencyWordsAreUsableNames() {
        for name in ["sum", "avg", "average", "math", "count", "km", "mi", "usd", "EUR"] {
            #expect(ReactiveVariable.isValidName(name), "\(name) should be valid")
        }
    }

    @Test func invalidNames() {
        for name in ["1x", "9", "my price", "x-y", "x.y", "price!", "💰", "x "] {
            #expect(ReactiveVariable.problem(with: name) == .invalid, "\(name) should be invalid")
        }
        #expect(ReactiveVariable.problem(with: "") == .empty)
    }

    @Test func conversionKeywordsAreReserved() {
        for name in ["in", "In", "IN", "to", "To", "TO"] {
            #expect(ReactiveVariable.problem(with: name) == .reserved, "\(name) should be reserved")
            #expect(!ReactiveVariable.isValidName(name))
        }
        // Longer names merely containing a keyword are fine.
        #expect(ReactiveVariable.isValidName("in_eur"))
        #expect(ReactiveVariable.isValidName("total"))
        #expect(ReactiveVariable.isValidName("into"))
    }

    @Test func referencesScanWholeIdentifiersOnce() {
        #expect(ReactiveVariable.references(in: "price * (qty + price)") == ["price", "qty"])
        #expect(ReactiveVariable.references(in: "café + _x1") == ["café", "_x1"])
        #expect(ReactiveVariable.references(in: "2 + 3.5") == [])
        #expect(ReactiveVariable.references(in: "") == [])
    }
}
