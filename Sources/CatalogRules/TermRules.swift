import CatalogJSON

/// The forms CONVENTIONS.md rules out of the catalog's prose.
public enum TermRules {
  private struct RuledOut: Sendable {
    let pattern: Pattern
    let replacement: String

    init(_ pattern: String, _ replacement: String) {
      self.pattern = Pattern(pattern)
      self.replacement = replacement
    }
  }

  /// The ruled-out forms in the order a string is checked, each with what to write instead.
  private static let ruledOut: [RuledOut] = [
    RuledOut(#"\bINSTEON\b"#, "Insteon"),
    RuledOut(#"(?<![.\w])[iI]2cs\b|\bI2CS\b"#, "i2CS"),
    RuledOut(#"\b[Aa]cknowledgement"#, "acknowledgment"),
    RuledOut(#"\b[Pp]ower line"#, "powerline"),
    RuledOut(#"\bon level\b"#, "on-level"),
    RuledOut(#"\b(2242|2245) Hub\b"#, "Hub 2242, Hub 2245"),
    RuledOut(#"\bAll-Link|\ball-link"#, "ALL-Link"),
    RuledOut(#"(?<!ALL-)\b[Ll]ink database"#, "ALL-Link database"),
    RuledOut(#"\bclean-up"#, "cleanup"),
    RuledOut(#"\b[Ss]et button\b"#, "SET button"),
    RuledOut(
      #"(?<!Insteon )(?<!Modem )(?<!Hub )\b[Dd]eveloper'?s? [Gg]uides?\b|\b[Tt]he guide\b"#,
      "the document's title, such as Leak Sensor Developer Notes or Insteon Developer's Guide"
    )
  ]

  /// The keys whose strings are prose.
  private static let proseKeys: Set<String> = ["description", "note", "notes", "sources", "label", "section", "text", "expect"]

  private static let codeSpan = Pattern("`[^`]*`")

  /// The ruled-out terms in the prose strings of a profile or command set, one line for each
  /// pattern that matches a string, in the order the strings and patterns come. A string is prose
  /// when its key is `description`, `note`, `notes`, `sources`, `label`, `section`, `text` or
  /// `expect`, or is `name` and holds a space; text between backticks is left out.
  ///
  /// - Parameters:
  ///   - label: What starts each line, such as `2852.json`.
  ///   - key: The key of `value` in its parent. Strings in a list take the key of the list.
  public static func problems(label: String, in value: JSONValue, key: String? = nil) -> [String] {
    switch value {
    case .object(let members):
      return members.flatMap { problems(label: label, in: $0.value, key: $0.key) }
    case .array(let elements):
      return elements.flatMap { problems(label: label, in: $0, key: key) }
    case .string(let text):
      guard let key, proseKeys.contains(key) || (key == "name" && text.unicodeScalars.contains(" ")) else { return [] }
      let prose = codeSpan.removingMatches(from: text)

      return ruledOut.compactMap { term in
        term.pattern.firstMatch(in: prose).map { "\(label): \(pythonRepr($0)) in \(key); use \(term.replacement)" }
      }
    default:
      return []
    }
  }
}
