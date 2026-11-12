/// Decorative editor paper; stored independently from the color theme.
public enum PaperType: String, Codable, CaseIterable, Sendable {
    case plain, ruled, grid, dotted

    public var displayName: String { rawValue.capitalized }
}
