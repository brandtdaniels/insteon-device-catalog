import CatalogJSON

/// Reads of a validated catalog file. A file that passed its schema has the fields these read,
/// so a missing one reads as empty and the rules never trap.
extension JSONValue {
  /// The member of an object with this name.
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  /// Whether an object has a member with this name.
  func has(_ key: String) -> Bool {
    self[key] != nil
  }

  /// The elements of an array, or none for any other value.
  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  /// The members of an object in file order, or none for any other value.
  var members: [JSONMember] {
    guard case .object(let members) = self else { return [] }
    return members
  }

  /// The elements of the array at `key`, or none.
  func list(_ key: String) -> [JSONValue] {
    self[key]?.elements ?? []
  }

  /// The string value, or `nil` for any other value.
  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  /// The string at `key`, or `nil`.
  func text(_ key: String) -> String? {
    self[key]?.string
  }

  /// The integer value, or `nil` for any other value.
  var integer: Int? {
    guard case .int(let number) = self else { return nil }
    return number
  }

  /// The integer at `key`, or `nil`.
  func number(_ key: String) -> Int? {
    self[key]?.integer
  }

  /// Whether the member is present and true under the rules Python uses for `if value:`.
  func isSet(_ key: String) -> Bool {
    self[key]?.isTruthy ?? false
  }

  /// Whether the value is less than `other` as Python's `<` reads two numbers or two strings: by
  /// value, or by code point. Values of other kinds are not ordered.
  func isLess(than other: JSONValue) -> Bool {
    switch (self, other) {
    case (.string(let left), .string(let right)): codePointPrecedes(left, right)
    default: if let left = numericValue, let right = other.numericValue { left < right } else { false }
    }
  }

  private var numericValue: Double? {
    switch self {
    case .int(let value): Double(value)
    case .double(let value): value
    default: nil
    }
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

  /// The value as Python's `str` writes it into a message: a string as it is, a number in
  /// decimal, a boolean as `True` or `False`.
  var messageText: String {
    switch self {
    case .string(let value): value
    case .null: "None"
    case .bool(let value): value ? "True" : "False"
    case .int(let value): String(value)
    case .double(let value): PythonFloat.format(value) ?? "\(value)"
    case .array, .object: canonical
    }
  }

  /// A string that is equal for two values exactly when the values are equal, to collect values
  /// in sets and compare them as keys.
  var canonical: String {
    switch self {
    case .null: "n"
    case .bool(let value): value ? "t" : "f"
    case .int(let value): "i\(value)"
    case .double(let value): "d\(value)"
    case .string(let value): "s\(value.utf8.count):\(value)"
    case .array(let values): "[" + values.map(\.canonical).joined(separator: ",") + "]"
    case .object(let members): "{" + members.map { "\($0.key.utf8.count):\($0.key)=\($0.value.canonical)" }.joined(separator: ",") + "}"
    }
  }
}

/// The integer a hexadecimal string such as `0x2E` holds, as Python's `int(text, 16)` reads it.
func hexValue(_ text: String) -> Int {
  var digits = Substring(text)
  if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
    digits = digits.dropFirst(2)
  }
  return Int(digits, radix: 16) ?? 0
}

/// Whether the strings are in the same order Python's `<` gives them: by code point.
func codePointPrecedes(_ left: String, _ right: String) -> Bool {
  left.unicodeScalars.lexicographicallyPrecedes(right.unicodeScalars) { $0.value < $1.value }
}

extension Sequence where Element == String {
  /// The strings in code point order, as Python's `sorted` gives them.
  func codePointSorted() -> [String] {
    sorted(by: codePointPrecedes)
  }
}

/// A string as Python's `repr` writes it: in single quotes unless it holds one and no double quote.
func pythonRepr(_ text: String) -> String {
  let quote: Unicode.Scalar = text.contains("'") && !text.contains("\"") ? "\"" : "'"
  var result = String(Character(quote))

  for scalar in text.unicodeScalars {
    switch scalar {
    case quote, "\\":
      result += "\\" + String(Character(scalar))
    case "\n":
      result += "\\n"
    case "\r":
      result += "\\r"
    case "\t":
      result += "\\t"
    default:
      result += isPrintable(scalar) ? String(Character(scalar)) : escaped(scalar)
    }
  }

  return result + String(Character(quote))
}

private func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
  if scalar == " " { return true }

  switch scalar.properties.generalCategory {
  case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator:
    return false
  default:
    return true
  }
}

private func escaped(_ scalar: Unicode.Scalar) -> String {
  let digits = String(scalar.value, radix: 16)
  let width = scalar.value <= 0xFF ? 2 : scalar.value <= 0xFFFF ? 4 : 8
  let prefix = width == 2 ? "\\x" : width == 4 ? "\\u" : "\\U"

  return prefix + String(repeating: "0", count: width - digits.count) + digits
}
