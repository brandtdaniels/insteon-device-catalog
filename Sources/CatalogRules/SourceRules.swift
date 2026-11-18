import CatalogJSON

/// The titles of the registered documents, compared by code point.
public struct RegisteredTitles: Sendable {
  private let titles: Set<ExactText>

  public init(_ titles: some Sequence<String>) {
    self.titles = Set(titles.map(ExactText.init))
  }

  /// Whether a document is registered under exactly this title.
  public func contains(_ title: String) -> Bool {
    titles.contains(ExactText(title))
  }
}

/// The citation rule: a source is a registered title.
public enum SourceRules {
  /// The strings in any `sources` list of a profile or command set that are not registered titles,
  /// in file order.
  ///
  /// - Parameters:
  ///   - label: What starts each line, such as `2852.json`.
  ///   - key: The key of `value` in its parent. Strings in a list take the key of the list.
  public static func problems(label: String, in value: JSONValue, titles: RegisteredTitles, key: String? = nil) -> [String] {
    switch value {
    case .object(let members):
      return members.flatMap { problems(label: label, in: $0.value, titles: titles, key: $0.key) }
    case .array(let elements):
      return elements.flatMap { problems(label: label, in: $0, titles: titles, key: key) }
    case .string(let title) where key == "sources" && !titles.contains(title):
      return ["\(label): source \(pythonRepr(title)) is not in documents/registry.json; register the document or cite its exact title"]
    default:
      return []
    }
  }
}
