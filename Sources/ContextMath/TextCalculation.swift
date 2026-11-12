import Foundation

/// Local, explicit text calculations. No note mode, rate fetch or persisted state.
public enum TextCalculation {
    public static func run(name: String, text: String) -> String? {
        let engine = MathEngine()
        switch name {
        case "math":
            return engine.evaluateLines(note: text).compactMap { outcome -> String? in
                switch outcome {
                case .value(let value): return value.gutterDisplay
                case .error(let error): return error.message
                case .blank: return nil
                }
            }.joined(separator: "\n")
        case "sum", "avg":
            return engine.aggregate(text, mode: name == "sum" ? .sum : .avg).map(engine.format) ?? "—"
        default: return nil
        }
    }
}
