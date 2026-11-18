import CatalogJSON

extension JSONValue {
  /// The member of an object with this name.
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  /// The element at a position of an array.
  subscript(position: Int) -> JSONValue? {
    guard case .array(let elements) = self, elements.indices.contains(position) else { return nil }
    return elements[position]
  }

  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  var isObject: Bool {
    if case .object = self { return true }
    return false
  }

  /// The member's text, or `nil` when the member is missing, null or not text.
  func text(_ key: String) -> String? {
    self[key]?.string
  }

  /// The member, or `nil` when it is missing or null.
  func present(_ key: String) -> JSONValue? {
    guard let value = self[key], value != .null else { return nil }
    return value
  }

  /// A copy with the member set: replaced where it is, or added at the end of the object.
  func setting(_ key: String, to value: JSONValue) -> JSONValue {
    guard case .object(var members) = self else { return self }

    if let position = members.firstIndex(where: { $0.key == key }) {
      members[position].value = value
    } else {
      members.append(JSONMember(key: key, value: value))
    }

    return .object(members)
  }

  /// Python's truth value: empty text, lists and objects, zero, `false` and `null` are false.
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

  /// Whether Python's `==` finds the two values equal: objects without regard to member order, numbers
  /// by value, and a boolean equal to the number 0 or 1.
  func pythonEquals(_ other: JSONValue) -> Bool {
    switch (self, other) {
    case (.null, .null):
      return true
    case (.string(let left), .string(let right)):
      return left.utf8.elementsEqual(right.utf8)
    case (.array(let left), .array(let right)):
      return left.count == right.count && zip(left, right).allSatisfy { $0.pythonEquals($1) }
    case (.object(let left), .object(let right)):
      return left.count == right.count && left.allSatisfy { member in
        right.first { $0.key.utf8.elementsEqual(member.key.utf8) }.map { member.value.pythonEquals($0.value) } ?? false
      }
    default:
      if let left = numeric, let right = other.numeric { return left == right }
      return false
    }
  }

  private var numeric: Double? {
    switch self {
    case .bool(let value): value ? 1 : 0
    case .int(let value): Double(value)
    case .double(let value): value
    default: nil
    }
  }
}

extension JSONValue? {
  /// Python's `==` on two values that may be absent, where absent is `None`.
  func pythonEquals(_ other: JSONValue?) -> Bool {
    (self ?? .null).pythonEquals(other ?? .null)
  }
}

extension String {
  /// Whether the two strings hold the same code points, as Python compares them; Swift's own `==`
  /// also equates canonically equivalent text.
  func isExactly(_ other: String) -> Bool {
    utf8.elementsEqual(other.utf8)
  }

  /// Whether `part` occurs in the text as Python's `in` finds it, by code points.
  func containsExactly(_ part: String) -> Bool {
    let text = Array(utf8), needle = Array(part.utf8)

    guard !needle.isEmpty else { return true }
    guard text.count >= needle.count else { return false }

    return (0...(text.count - needle.count)).contains { start in
      text[start..<(start + needle.count)].elementsEqual(needle)
    }
  }

  /// The number of code points, as Python's `len` counts them.
  var codePointCount: Int {
    unicodeScalars.count
  }
}

extension Sequence where Element == String {
  /// The strings in code point order, as Python's `sorted` gives them.
  func sortedByCodePoint() -> [String] {
    sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
  }
}
