import CatalogJSON

/// Registries and their entries, built the way the Python tests build them.
enum Registry {
  /// A registry with these entries.
  static func with(_ documents: JSONValue...) -> JSONValue {
    .object([JSONMember(key: "documents", value: .array(documents))])
  }

  /// A registry entry: a title and a kind, and the optional fields.
  static func document(
    _ title: String = "Leak Sensor Developer Notes", _ kind: String = "developerNotes", optional: KeyValuePairs<String, JSONValue> = [:]
  ) -> JSONValue {
    .object([JSONMember(key: "title", value: .string(title)), JSONMember(key: "kind", value: .string(kind))]
      + optional.map { JSONMember(key: $0.key, value: $0.value) })
  }

  /// A list of titles as the reviewed file holds a pair.
  static func pair(_ first: String, _ second: String) -> JSONValue {
    .array([.string(first), .string(second)])
  }

  /// The kinds the registry accepts, as Python prints `sorted(DOCUMENT_KINDS)`.
  static let kindList = "['commandTables', 'developerDocumentation', 'developerNotes', 'developersGuide', 'deviceCategories', "
    + "'deviceDefinitions', 'other', 'ownersManual', 'productCatalog', 'productGuide', 'quickStart', 'supportArticle']"
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }

  public init(integerLiteral value: Int) {
    self = .int(value)
  }
}
