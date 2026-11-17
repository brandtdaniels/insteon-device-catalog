import CatalogJSON

extension JSONValue {
  /// Whether JSON Schema counts the two values as the same: numbers by value (1 and 1.0 are one
  /// number), objects without regard to member order.
  func isSchemaEqual(to other: JSONValue) -> Bool {
    switch (self, other) {
    case (.null, .null):
      return true
    case (.bool(let a), .bool(let b)):
      return a == b
    case (.string(let a), .string(let b)):
      return a == b
    case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.isSchemaEqual(to: $1) }
    case (.object(let a), .object(let b)):
      guard a.count == b.count else { return false }
      return a.allSatisfy { member in
        b.first { $0.key == member.key }.map { member.value.isSchemaEqual(to: $0.value) } ?? false
      }
    default:
      if let a = number, let b = other.number {
        return a == b
      }
      return false
    }
  }

  /// The value of an integer or a floating-point number.
  var number: Double? {
    switch self {
    case .int(let value): Double(value)
    case .double(let value): value
    default: nil
    }
  }

  /// The member of an object with this name.
  func member(_ key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  /// The value as one line for an error message: strings in single quotes, lists in brackets,
  /// objects in braces.
  var summary: String {
    switch self {
    case .null:
      "null"
    case .bool(let value):
      value ? "true" : "false"
    case .int(let value):
      String(value)
    case .double(let value):
      PythonFloat.format(value) ?? "\(value)"
    case .string(let value):
      "'" + value.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\\n") + "'"
    case .array(let elements):
      "[" + elements.map(\.summary).joined(separator: ", ") + "]"
    case .object(let members):
      "{" + members.map { "'\($0.key)': \($0.value.summary)" }.joined(separator: ", ") + "}"
    }
  }
}
