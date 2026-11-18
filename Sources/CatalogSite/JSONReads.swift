import CatalogJSON

/// Reads of a validated profile or command set. A file that passed its schema has the fields these
/// read, so a missing one reads as empty.
extension JSONValue {
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  func has(_ key: String) -> Bool {
    self[key] != nil
  }

  var members: [JSONMember] {
    guard case .object(let members) = self else { return [] }
    return members
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  /// The elements of the array at `key`, or none.
  func list(_ key: String) -> [JSONValue] {
    self[key]?.elements ?? []
  }

  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  /// The strings among the elements of an array.
  var strings: [String] {
    elements.compactMap(\.string)
  }

  var integer: Int? {
    guard case .int(let number) = self else { return nil }
    return number
  }

  /// The string at `key`, or the empty string.
  func text(_ key: String) -> String {
    self[key]?.string ?? ""
  }

  /// Whether the member is present and true under the rules Python uses for `if value:`.
  func isSet(_ key: String) -> Bool {
    self[key]?.isTruthy ?? false
  }

  /// Python's truth value: empty strings, lists and objects, zero, `false` and `null` are false.
  var isTruthy: Bool {
    switch self {
    case .null: false
    case .bool(let value): value
    case .int(let value): value != 0
    case .double(let value): value != 0
    case .string(let value): !value.isEmpty
    case .array(let value): !value.isEmpty
    case .object(let value): !value.isEmpty
    }
  }
}

/// A string compared by its code points, as Python compares strings. Swift's own `==` treats
/// canonically equivalent strings as equal.
struct ExactText: Hashable, Sendable {
  let utf8: [UInt8]

  init(_ text: String) {
    utf8 = Array(text.utf8)
  }
}

extension Sequence where Element == String {
  /// The strings in code point order, as Python's `sorted` gives them.
  func codePointSorted() -> [String] {
    sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0.value < $1.value } }
  }

  /// The strings without repeats, each at its first position, as `dict.fromkeys` keeps them.
  func uniqued() -> [String] {
    var seen = Set<ExactText>()
    return filter { seen.insert(ExactText($0)).inserted }
  }
}
