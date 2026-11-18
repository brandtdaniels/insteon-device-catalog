import CatalogJSON
import CatalogRules
import CatalogSchema

/// Decides whether a parsed observation may be drafted from.
///
/// A rejection says which field is wrong and why, and never repeats the value: the text of a
/// rejected file may end up in a public place, and what made it fail is the thing that must not.
public enum ObservationCheck {
  /// The format a file must declare.
  public static let format = "insteon-observation/1"

  static let maximumChecks = 16
  static let maximumNote = 280
  static let maximumDetail = 200
  static let engines: Set<String> = ["i1", "i2", "i2CS"]

  private static let byte = Pattern.whole(#"0x[0-9A-F]{2}"#)
  private static let otherVersion = Pattern.whole(#"insteon-observation/\d+"#)

  /// Fields whose text is a value the format defines, so the scan leaves them alone: a key or a flag
  /// byte can look like an address.
  private static let unscanned: Set<String> = [
    "format", "device.category", "device.subcategory", "device.firmware", "device.engine", "productKey", "operatingFlags.raw", "observedOn"
  ]

  /// What each schema rule means, in words that don't repeat the value that broke it.
  private static let rules = [
    "additionalProperties": "has a field the format does not have",
    "type": "has the wrong kind of value",
    "enum": "is not one of the values the format allows",
    "const": "is not the value the format requires",
    "pattern": "is not written the way the format requires"
  ]

  /// What is wrong with a parsed observation, as plain sentences; empty when it may be drafted from.
  ///
  /// - Parameter models: The catalog's model numbers. A product name in the file may hold one, which
  ///   can look like an address and isn't.
  public static func problems(in data: JSONValue, models: Set<String> = []) -> [String] {
    let formatProblems = formatProblems(data)

    guard formatProblems.isEmpty else { return formatProblems }

    var errors = schemaProblems(data)

    if errors.isEmpty {
      errors += valueProblems(data)
    }

    return errors + privacyProblems(data, models: models)
  }

  private static func formatProblems(_ data: JSONValue) -> [String] {
    let value = data["format"]

    if value == .string(format) { return [] }

    if let text = value?.string, otherVersion.matches(text) {
      return ["unsupported format version; this tool reads \(format)"]
    }

    return ["not an \(format) file"]
  }

  private static func schemaProblems(_ data: JSONValue) -> [String] {
    guard let validator = try? ObservationSchema.validator() else {
      return ["the observation schema can't be read"]
    }

    let errors = validator.errors(in: data).enumerated().sorted { left, right in
      let order = left.element.path.utf8.lexicographicallyPrecedes(right.element.path.utf8)

      return left.element.path == right.element.path ? left.offset < right.offset : order
    }

    return errors.map { _, error in
      error.keyword == "required" ? "\(error.path): \(error.message)" : "\(error.path): \(rules[error.keyword] ?? "does not follow the format")"
    }
  }

  /// The rules the schema leaves open: how identity bytes are written, the engines, the dates and the
  /// length of free text.
  private static func valueProblems(_ data: JSONValue) -> [String] {
    var problems: [String] = []
    let device = data["device"] ?? .null

    for field in ["category", "subcategory", "firmware"] {
      if let value = device[field]?.string, !byte.matches(value) {
        problems.append("$.device.\(field): is not a byte written as 0x and two upper-case digits")
      }
    }

    if let engine = device["engine"]?.string, !engines.contains(engine) {
      problems.append("$.device.engine: is not one of i1, i2 or i2CS")
    }

    if !isCalendarDate(data["observedOn"]?.string ?? "") {
      problems.append("$.observedOn: not a calendar date")
    }

    let checks = data["checks"]?.elements ?? []

    if checks.count > maximumChecks {
      problems.append("$.checks: more than \(maximumChecks) checks")
    }

    if (data["note"]?.string ?? "").codePointCount > maximumNote {
      problems.append("$.note: longer than \(maximumNote) characters")
    }

    for (position, entry) in checks.enumerated() where (entry["detail"]?.string ?? "").codePointCount > maximumDetail {
      problems.append("$.checks[\(position)].detail: longer than \(maximumDetail) characters")
    }

    return problems
  }

  /// Whether the text is a date the calendar has, written as four digits, two and two.
  static func isCalendarDate(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)

    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          parts.allSatisfy({ $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }),
          year >= 1, (1...12).contains(month)
    else { return false }

    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    return (1...lengths[month - 1]).contains(day)
  }

  private static func privacyProblems(_ data: JSONValue, models: Set<String>) -> [String] {
    var problems: [String] = []

    for (path, text) in strings(in: data) where !unscanned.contains(path) {
      // The product name comes from the catalog, so a model number in it is not an address.
      for shape in PrivacyScan.shapes(in: text, models: path == "device.model" ? models : [], serial: path == "note") {
        problems.append("$.\(path): contains what looks like \(shape); remove it and run the observation again")
      }
    }

    return problems
  }

  /// Every string in the document with its dotted path; an array element's position is written [n].
  private static func strings(in value: JSONValue, path: String = "") -> [(String, String)] {
    switch value {
    case .string(let text):
      return [(path, text)]
    case .object(let members):
      return members.flatMap { strings(in: $0.value, path: path.isEmpty ? $0.key : "\(path).\($0.key)") }
    case .array(let elements):
      return elements.enumerated().flatMap { strings(in: $1, path: "\(path)[\($0)]") }
    default:
      return []
    }
  }
}
