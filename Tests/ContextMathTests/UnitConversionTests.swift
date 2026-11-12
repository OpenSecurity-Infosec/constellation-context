import ContextMath
import Foundation
import Testing

@Suite struct UnitConversionTests {
    private let engine = MathEngine()

    private func value(_ note: String, line: Int = 0) -> Double? {
        engine.evaluate(note: note)[line]?.value
    }

    private func expectApprox(_ note: String, _ expected: Double, line: Int = 0, tol: Double = 0.001) {
        let got = value(note, line: line)
        #expect(got != nil)
        if let got { #expect(abs(got - expected) < tol) }
    }

    // MARK: New dimensions

    @Test func volumeConversions() {
        expectApprox("1 gal in l", 3.785411784)
        expectApprox("250 ml in l", 0.25)
        expectApprox("1 l in ml", 1000)
        expectApprox("2 tbsp in ml", 29.5735)
        expectApprox("1 cup in ml", 236.5882365)
        expectApprox("1 litre in millilitres", 1000)
    }

    @Test func areaConversions() {
        expectApprox("1 acre in m2", 4046.8564224)
        expectApprox("100 sq ft in m2", 9.290304)
        expectApprox("1 ha in acres", 2.4710538)
        expectApprox("10 square meters in square feet", 107.639104)
        expectApprox("1 km2 in ha", 100)
    }

    @Test func speedConversions() {
        expectApprox("100 km/h in mph", 62.137119)
        expectApprox("10 m/s in km/h", 36)
        expectApprox("60 mph in km/h", 96.56064)
        expectApprox("100 kilometres per hour in miles per hour", 62.137119)
        expectApprox("10 km / h in mph", 6.2137119)
        expectApprox("10 knots in km/h", 18.52)
    }

    @Test func timeConversions() {
        expectApprox("90 min in h", 1.5)
        expectApprox("2 wk in days", 14)
        expectApprox("1 yr in days", 365.25)
        expectApprox("3600 seconds in hours", 1)
        expectApprox("500 ms in s", 0.5)
    }

    @Test func dataSizeConversions() {
        expectApprox("1 GB in MB", 1000)
        expectApprox("1 GiB in MiB", 1024)
        expectApprox("8 Mb in MB", 1)
        expectApprox("1 byte in bits", 8)
        expectApprox("1500 B in KB", 1.5)
        expectApprox("2 megabytes in kilobytes", 2000)
    }

    @Test func lengthAndMassAdditions() {
        expectApprox("1 nmi in km", 1.852)
        expectApprox("1 yd in ft", 3)
        expectApprox("1 tonne in kg", 1000)
        expectApprox("1 stone in lb", 14)
        expectApprox("16 ounces in pounds", 1)
        expectApprox("1 ton in kg", 907.18474)
    }

    // MARK: Temperature offsets, all pairs

    @Test func temperatureOffsetsAllPairs() {
        expectApprox("32 f in c", 0)
        expectApprox("212 f in c", 100)
        expectApprox("-40 c in f", -40)
        expectApprox("0 c in k", 273.15)
        expectApprox("300 k in f", 80.33)
        expectApprox("98.6 f in k", 310.15)
        expectApprox("25 c in c", 25)
        expectApprox("100 °C in °F", 212)
        expectApprox("100 degrees celsius in fahrenheit", 212)
    }

    // MARK: Abbreviated, plural, case, glued and phrasing forms

    @Test func abbreviatedPluralCaseForms() {
        expectApprox("10 Kilometres IN Miles", 6.2137119)
        expectApprox("10 KM to mi", 6.2137119)
        expectApprox("5 kilograms in pounds", 11.023113)
        expectApprox("3 feet in inches", 36)
        expectApprox("10km in mi", 6.2137119)
        expectApprox("2 L in mL", 2000)
        expectApprox("5 lbs in kg", 2.26796185)
    }

    @Test func inchUnitIsNotTheKeyword() {
        expectApprox("9 in in cm", 22.86)
        expectApprox("12 in to ft", 1)
        expectApprox("10 km in mi.", 6.2137119)
    }

    @Test func thousandsAndScientificAmounts() {
        expectApprox("1,000 m in km", 1)
        expectApprox("1e3 m in km", 1)
        #expect(engine.evaluate(note: "1,000 + 1").first??.display == "1001")
        #expect(engine.evaluate(note: "1e3 + 1").first??.display == "1001")
    }

    // MARK: Compound quantities

    @Test func compoundQuantitiesSumComponents() {
        expectApprox("5 ft 6 in in cm", 167.64)
        expectApprox("1 h 30 min in min", 90)
        expectApprox("2 kg 500 g in kg", 2.5)
        expectApprox("height 5 ft 6 in in cm", 167.64)
        expectApprox("5ft 6in in cm", 167.64)
    }

    // MARK: Variables and descriptive text

    @Test func descriptiveTextAroundConversion() {
        expectApprox("run: 10 km in mi", 6.2137119)
        expectApprox("oats 10 km in mi", 6.2137119)
        expectApprox("distance 10 km to miles", 6.2137119)
        expectApprox("10 km in mi for the run", 6.2137119)
    }

    @Test func variablesInNewDimensions() {
        expectApprox("v = 100\nv km/h in mph", 62.137119, line: 1)
        expectApprox("t = 90 min in h\nt * 2", 3, line: 1)
        expectApprox("size = 2 GB in MB\nsize", 2000, line: 1)
        expectApprox("h = 5\nh ft 6 in in cm", 167.64, line: 1)
    }

    @Test func unknownAmountVariableIsNotRescued() {
        #expect(engine.evaluateLines(note: "nope * 2 km in mi") == [.error(.unknownVariable("nope"))])
        #expect(engine.evaluateLines(note: "nope km/h in mph") == [.error(.unknownVariable("nope"))])
    }

    // MARK: Errors in the gutter

    @Test func incompatibleUnitsSaySo() {
        for note in ["10 kg in mi", "10 km in kg", "10 l in kg", "10 km in USD"] {
            let out = engine.evaluateLines(note: note)
            if case .error(let e) = out.first {
                #expect(e.message.hasPrefix("can't convert"))
            } else {
                Issue.record("expected an error for \(note), got \(out)")
            }
        }
        if case .error(let e) = engine.evaluateLines(note: "10 kg in mi").first {
            #expect(e.message == "can't convert kg to mi")
        }
    }

    @Test func unknownUnitNamesTheUnknownSide() {
        #expect(engine.evaluateLines(note: "10 blarg in km") == [.error(.unknownUnit("blarg"))])
        #expect(engine.evaluateLines(note: "10 km in blorp") == [.error(.unknownUnit("blorp"))])
        #expect(engine.evaluateLines(note: "10 blarg in blorp") == [.error(.unknownUnit("blorp"))])
        #expect(engine.evaluateLines(note: "10 km in") == [.error(.syntax)])
    }

    @Test func failedIncompatibleAssignmentDefinesNothing() {
        let out = engine.evaluateLines(note: "x = 10 kg in mi\nx")
        if case .error(let e) = out[0] {
            #expect(e.message == "can't convert kg to mi")
        } else {
            Issue.record("expected an error, got \(out[0])")
        }
        #expect(out[1] == .error(.unknownVariable("x")))
    }

    @Test func proseWithInOrToStaysBlank() {
        #expect(engine.evaluateLines(note: "walk to the shop") == [.blank])
        #expect(engine.evaluateLines(note: "go in peace") == [.blank])
    }

    @Test func sameCurrencyNeedsNoRates() {
        expectApprox("10 USD in USD", 10)
    }

    // MARK: Number formatting

    @Test func formattingKeepsTinyAndHugeValuesHonest() {
        #expect(engine.format(0) == "0")
        #expect(engine.format(-0.0) == "0")
        #expect(engine.format(2.5) == "2.5")
        #expect(engine.format(2.0 / 3.0) == "0.666667")
        #expect(engine.format(0.000001) == "0.000001")
        #expect(engine.format(1.5e-7) == "1.5e-07")
        #expect(engine.format(-1e-7) == "-1e-07")
        #expect(engine.format(1e20) == "1e+20")
        #expect(engine.format(1_000_000) == "1000000")
    }

    @Test func tinyConversionResultIsNotZeroInGutter() {
        #expect(engine.evaluate(note: "1 mm in km").first??.display == "0.000001")
        #expect(engine.evaluate(note: "1 mm in mi").first??.display == "6.21371e-07")
    }

    @Test func gluedSymbolsAndSuperscripts() {
        expectApprox("5'6\" in cm", 167.64)
        expectApprox("-40°C in °F", -40)
        expectApprox("10 m² in ft²", 107.639104)
        expectApprox("10 km in km", 10)
    }

    @Test func compoundAssignmentAndComponentErrors() {
        expectApprox("h = 5 ft 6 in in cm\nh", 167.64, line: 1)
        #expect(engine.evaluateLines(note: "5 ft 3 kg in cm") == [.error(.incompatibleUnits("kg", "cm"))])
        #expect(engine.evaluateLines(note: "nope ft 6 in in cm") == [.error(.unknownVariable("nope"))])
        #expect(engine.evaluateLines(note: "h ft 6 in in cm\nh = 5").first == .error(.forwardReference("h")))
        #expect(engine.evaluateLines(note: "1/0 km in mi") == [.error(.divideByZero)])
    }

    @Test func exponentVariableMathStillWorks() {
        let out = engine.evaluate(note: "x = 1e3\nx + 1")
        #expect(out[1]?.display == "1001")
    }

    @Test func incompatibleErrorCaseMatchesMessage() {
        #expect(engine.evaluateLines(note: "10 kg in mi") == [.error(.incompatibleUnits("kg", "mi"))])
        #expect(MathEngine.LineError.incompatibleUnits("kg", "mi").message == "can't convert kg to mi")
    }
}

@Suite struct UnitConversionTableTests {
    @Test func lookupAcceptsAliasPluralCaseForms() {
        #expect(UnitConversion.unit(for: "Kilometres")?.symbol == "km")
        #expect(UnitConversion.unit(for: "square feet")?.symbol == "ft2")
        #expect(UnitConversion.unit(for: "°F")?.symbol == "f")
        #expect(UnitConversion.unit(for: "miles per hour")?.symbol == "mph")
        #expect(UnitConversion.unit(for: "blorp") == nil)
        #expect(!UnitConversion.isUnit("blorp"))
    }

    @Test func dataCasingDistinguishesBitsFromBytes() {
        #expect(UnitConversion.unit(for: "MB")?.factorToBase == 1_000_000)
        #expect(UnitConversion.unit(for: "Mb")?.factorToBase == 125_000)
        #expect(UnitConversion.unit(for: "B")?.factorToBase == 1)
        #expect(UnitConversion.unit(for: "b")?.factorToBase == 0.125)
    }

    @Test func convertIsNilAcrossDimensions() {
        #expect(UnitConversion.convert(amount: 1, from: "kg", to: "mi") == nil)
        #expect(UnitConversion.convert(amount: 1, from: "kg", to: "blorp") == nil)
        #expect(UnitConversion.convert(amount: 100, from: "celsius", to: "fahrenheit") == 212)
    }
}
