import Foundation

/// Physical-unit conversions for `math` notes: length, mass, temperature,
/// volume, area, speed, time, and data size. Every unit maps to a base
/// unit per dimension (metre, kilogram, litre, square metre, metre per
/// second, second, byte); temperature converts through Celsius so the
/// Fahrenheit/Kelvin offsets apply in both directions. Fluid measures
/// (gallon, cup, pint, quart, tablespoon, teaspoon, fluid ounce) are the
/// US customary ones unless spelled "imperial"; `ton` is the US short
/// ton and `tonne` the metric one; a `yr` is a Julian year (365.25 days).
/// Lookup is case-insensitive and accepts abbreviations, plurals, and
/// spelled-out forms, with one deliberate exception: data-size casing
/// wins when it is unambiguous (`MB` megabyte vs `Mb` megabit, `B` byte
/// vs `b` bit); all-lowercase `mb`/`kb` read as bytes, as usually typed.
public enum UnitConversion {
    public enum Dimension: String, Equatable, Sendable {
        case length, mass, temperature, volume, area, speed, time, data
    }

    public struct Unit: Equatable, Sendable {
        /// Short canonical symbol as typed back in error messages.
        public var symbol: String
        public var dimension: Dimension
        /// Multiply a value in this unit by this to get the base unit.
        /// Unused for temperature, which needs an offset, not just a scale.
        public var factorToBase: Double

        public init(symbol: String, dimension: Dimension, factorToBase: Double) {
            self.symbol = symbol
            self.dimension = dimension
            self.factorToBase = factorToBase
        }
    }

    /// Resolves a typed unit phrase (`km`, `Kilometres`, `square feet`,
    /// `°F`, `miles per hour`) to a unit, or nil when unknown.
    public static func unit(for raw: String) -> Unit? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        guard !trimmed.isEmpty else { return nil }
        if let exact = exactCaseUnits[trimmed] { return exact }
        let key = normalize(trimmed)
        if let unit = unitsByAlias[key] { return unit }
        // Singularize the last word: metres -> metre, inches -> inch.
        for candidate in singularForms(of: key) {
            if let unit = unitsByAlias[candidate] { return unit }
        }
        // Spaceless spellings: sqft, kmh, floz spelled "fl oz" both land.
        let spaceless = key.replacingOccurrences(of: " ", with: "")
        if let unit = unitsByAlias[spaceless] { return unit }
        for candidate in singularForms(of: spaceless) {
            if let unit = unitsByAlias[candidate] { return unit }
        }
        return nil
    }

    public static func isUnit(_ raw: String) -> Bool { unit(for: raw) != nil }

    /// Converts between resolved units. Nil when dimensions differ.
    public static func convert(amount: Double, from: Unit, to: Unit) -> Double? {
        guard from.dimension == to.dimension else { return nil }
        if from.dimension == .temperature {
            return fromCelsius(toCelsius(amount, from: from.symbol), to: to.symbol)
        }
        return amount * from.factorToBase / to.factorToBase
    }

    /// Converts between typed unit phrases. Nil when either side is
    /// unknown or the dimensions differ.
    public static func convert(amount: Double, from: String, to: String) -> Double? {
        guard let f = unit(for: from), let t = unit(for: to) else { return nil }
        return convert(amount: amount, from: f, to: t)
    }

    private static func toCelsius(_ amount: Double, from symbol: String) -> Double {
        switch symbol {
        case "f": return (amount - 32) * 5 / 9
        case "k": return amount - 273.15
        default: return amount
        }
    }

    private static func fromCelsius(_ celsius: Double, to symbol: String) -> Double {
        switch symbol {
        case "f": return celsius * 9 / 5 + 32
        case "k": return celsius + 273.15
        default: return celsius
        }
    }

    /// Lowercases, folds superscript and micro spellings, makes hyphens
    /// spaces, drops spaces around `/`, collapses runs of spaces, and
    /// strips a leading `degrees`/`degree`/`°` so `degrees celsius`,
    /// `°C`, and `celsius` are one key. `°c`/`°f` keep their letter.
    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "²", with: "2")
        s = s.replacingOccurrences(of: "³", with: "3")
        s = s.replacingOccurrences(of: "µ", with: "u")
        s = s.replacingOccurrences(of: "μ", with: "u")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: "°", with: "")
        for prefix in ["degrees ", "degree "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.replacingOccurrences(of: " / ", with: "/")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func singularForms(of key: String) -> [String] {
        var forms: [String] = []
        if key.hasSuffix("es") { forms.append(String(key.dropLast(2))) }
        if key.hasSuffix("s") { forms.append(String(key.dropLast())) }
        return forms
    }

    // MARK: - Tables

    private typealias Entry = (symbol: String, dimension: Dimension, factor: Double, aliases: [String])

    private static let entries: [Entry] = {
        var e: [Entry] = []
        func add(_ symbol: String, _ dimension: Dimension, _ factor: Double, _ aliases: [String] = []) {
            e.append((symbol, dimension, factor, aliases))
        }
        // Length, base metre.
        add("mm", .length, 0.001, ["millimeter", "millimetre"])
        add("cm", .length, 0.01, ["centimeter", "centimetre"])
        add("m", .length, 1, ["meter", "metre"])
        add("km", .length, 1000, ["kilometer", "kilometre"])
        add("um", .length, 1e-6, ["micrometer", "micrometre", "micron"])
        add("in", .length, 0.0254, ["inch", "\""])
        add("ft", .length, 0.3048, ["foot", "feet", "'"])
        add("yd", .length, 0.9144, ["yard"])
        add("mi", .length, 1609.344, ["mile"])
        add("nmi", .length, 1852, ["nautical mile"])
        // Mass, base kilogram.
        add("mg", .mass, 1e-6, ["milligram"])
        add("g", .mass, 0.001, ["gram", "gramme"])
        add("kg", .mass, 1, ["kilogram"])
        add("oz", .mass, 0.028349523125, ["ounce"])
        add("lb", .mass, 0.45359237, ["lbs", "pound"])
        add("st", .mass, 6.35029318, ["stone"])
        add("ton", .mass, 907.18474, ["short ton", "us ton"])
        add("tonne", .mass, 1000, ["metric ton", "t"])
        // Temperature, base Celsius (factor unused, offsets apply).
        add("c", .temperature, 1, ["celsius", "centigrade"])
        add("f", .temperature, 1, ["fahrenheit"])
        add("k", .temperature, 1, ["kelvin"])
        // Volume, base litre. US customary fluid measures.
        add("ml", .volume, 0.001, ["milliliter", "millilitre", "cc"])
        add("cl", .volume, 0.01, ["centiliter", "centilitre"])
        add("l", .volume, 1, ["liter", "litre"])
        add("m3", .volume, 1000, ["cubic meter", "cubic metre"])
        add("tsp", .volume, 0.00492892159, ["teaspoon"])
        add("tbsp", .volume, 0.0147867648, ["tablespoon"])
        add("floz", .volume, 0.0295735296, ["fluid ounce", "fl oz", "us fluid ounce"])
        add("cup", .volume, 0.2365882365, ["us cup"])
        add("pt", .volume, 0.473176473, ["pint", "us pint"])
        add("qt", .volume, 0.946352946, ["quart", "us quart"])
        add("gal", .volume, 3.785411784, ["gallon", "us gallon"])
        add("impgal", .volume, 4.54609, ["imperial gallon", "uk gallon"])
        // Area, base square metre.
        add("mm2", .area, 1e-6, ["square millimeter", "square millimetre", "sq mm"])
        add("cm2", .area, 1e-4, ["square centimeter", "square centimetre", "sq cm"])
        add("m2", .area, 1, ["square meter", "square metre", "sq m", "sqm"])
        add("km2", .area, 1e6, ["square kilometer", "square kilometre", "sq km"])
        add("ha", .area, 10_000, ["hectare"])
        add("in2", .area, 0.00064516, ["square inch", "sq in", "sqin"])
        add("ft2", .area, 0.09290304, ["square foot", "square feet", "sq ft", "sqft"])
        add("yd2", .area, 0.83612736, ["square yard", "sq yd", "sqyd"])
        add("acre", .area, 4046.8564224)
        add("mi2", .area, 2_589_988.110336, ["square mile", "sq mi", "sqmi"])
        // Speed, base metre per second.
        add("m/s", .speed, 1, ["meter per second", "metre per second", "meters per second", "metres per second"])
        add("km/h", .speed, 1000.0 / 3600, ["kmh", "kph", "kilometer per hour", "kilometre per hour", "kilometers per hour", "kilometres per hour"])
        add("mph", .speed, 0.44704, ["mi/h", "mile per hour", "miles per hour"])
        add("ft/s", .speed, 0.3048, ["foot per second", "feet per second", "fps"])
        add("kn", .speed, 1852.0 / 3600, ["knot", "kt"])
        // Time, base second. A year is the Julian year, 365.25 days.
        add("ms", .time, 0.001, ["millisecond"])
        add("s", .time, 1, ["sec", "second"])
        add("min", .time, 60, ["minute"])
        add("h", .time, 3600, ["hr", "hour"])
        add("d", .time, 86_400, ["day"])
        add("wk", .time, 604_800, ["week"])
        add("yr", .time, 31_557_600, ["year", "y"])
        // Data, base byte. Decimal SI, binary IEC, and bits at 1/8 byte.
        add("bit", .data, 0.125)
        add("b", .data, 0.125)
        add("kbit", .data, 125, ["kilobit"])
        add("mbit", .data, 125_000, ["megabit"])
        add("gbit", .data, 125_000_000, ["gigabit"])
        add("tbit", .data, 125_000_000_000, ["terabit"])
        add("byte", .data, 1)
        add("kb", .data, 1_000, ["kilobyte"])
        add("mb", .data, 1_000_000, ["megabyte"])
        add("gb", .data, 1_000_000_000, ["gigabyte"])
        add("tb", .data, 1_000_000_000_000, ["terabyte"])
        add("pb", .data, 1_000_000_000_000_000, ["petabyte"])
        add("kib", .data, 1_024, ["kibibyte"])
        add("mib", .data, 1_048_576, ["mebibyte"])
        add("gib", .data, 1_073_741_824, ["gibibyte"])
        add("tib", .data, 1_099_511_627_776, ["tebibyte"])
        add("pib", .data, 1_125_899_906_842_624, ["pebibyte"])
        return e
    }()

    private static let unitsByAlias: [String: Unit] = {
        var map: [String: Unit] = [:]
        for entry in entries {
            let unit = Unit(symbol: entry.symbol, dimension: entry.dimension, factorToBase: entry.factor)
            map[entry.symbol] = unit
            for alias in entry.aliases { map[alias] = unit }
        }
        return map
    }()

    /// Case-sensitive data spellings checked before lowercasing, so
    /// `Mb` stays megabit while `MB` and `mb` are megabytes.
    private static let exactCaseUnits: [String: Unit] = {
        func unit(_ symbol: String) -> Unit { unitsByAlias[symbol]! }
        return [
            "B": unit("byte"),
            "kB": unit("kb"), "KB": unit("kb"),
            "MB": unit("mb"), "GB": unit("gb"), "TB": unit("tb"), "PB": unit("pb"),
            "KiB": unit("kib"), "MiB": unit("mib"), "GiB": unit("gib"),
            "TiB": unit("tib"), "PiB": unit("pib"),
            "Kb": unit("kbit"), "Kbit": unit("kbit"),
            "Mb": unit("mbit"), "Mbit": unit("mbit"),
            "Gb": unit("gbit"), "Gbit": unit("gbit"),
            "Tb": unit("tbit"), "Tbit": unit("tbit"),
        ]
    }()
}
