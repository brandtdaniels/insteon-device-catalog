/// How the sweep sets the Swift rules' output against the Python build's.
public enum Comparison {
  /// What the sweep compares of one run: the rule messages in order, and the schema errors by file
  /// and path only, because the two validators word their messages differently.
  public struct Outcome: Equatable, Sendable {
    public var ruleMessages: [String]
    public var schemaErrors: [String]
    /// The schema error lines as printed, to show a person; they don't take part in the comparison.
    public var schemaLines: [String] = []

    public static func == (left: Outcome, right: Outcome) -> Bool {
      left.ruleMessages == right.ruleMessages && left.schemaErrors == right.schemaErrors
    }
  }

  /// Whether the Swift run and the Python run agree: the same rule messages in the same order, and
  /// schema errors that match as `schemaErrorsMatch` says.
  public static func agree(swift: Outcome, python: Outcome) -> Bool {
    swift.ruleMessages == python.ruleMessages && schemaErrorsMatch(swift: swift.schemaErrors, python: python.schemaErrors)
  }

  /// Whether every Python schema error has a Swift error at its place or below it in the same
  /// file, and every Swift error is at or below a Python error. The Swift validator reports the
  /// errors of the `oneOf` branch a document names, where the Python validator reports the
  /// `oneOf` itself, so a Swift path may run deeper than Python's.
  public static func schemaErrorsMatch(swift: [String], python: [String]) -> Bool {
    swift.allSatisfy { error in python.contains { isAtOrBelow(error, $0) } }
      && python.allSatisfy { error in swift.contains { isAtOrBelow($0, error) } }
  }

  /// Whether `error`, as `file: $.path`, is the same place as `ancestor` or inside it.
  static func isAtOrBelow(_ error: String, _ ancestor: String) -> Bool {
    guard error.hasPrefix(ancestor) else { return false }
    guard let next = error.dropFirst(ancestor.count).first else { return true }
    return next == "." || next == "["
  }

  /// Splits problem lines into rule messages and schema errors. Lines from checks the Swift rules
  /// don't cover (registry, terms, sources and dashes) are left out.
  public static func outcome(of lines: [String]) -> Outcome {
    var outcome = Outcome(ruleMessages: [], schemaErrors: [])

    for line in lines where !isOutsideTheRules(line) {
      if let key = schemaKey(of: line) {
        outcome.schemaErrors.append(key)
        outcome.schemaLines.append(line)
      } else {
        outcome.ruleMessages.append(line)
      }
    }

    outcome.schemaErrors.sort(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    return outcome
  }

  /// The lines of `lines` that `other` lacks, counting repeats.
  public static func lines(_ lines: [String], notIn other: [String]) -> [String] {
    var remaining = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)

    return lines.filter { line in
      guard let count = remaining[line], count > 0 else { return true }
      remaining[line] = count - 1
      return false
    }
  }

  /// `file.json: $.path` for a schema error line, which reads `file.json: $.path: message`.
  public static func schemaKey(of line: String) -> String? {
    guard let marker = line.range(of: ": $") else { return nil }
    let file = line[..<marker.lowerBound]
    let rest = line[line.index(before: marker.upperBound)...]
    let path = rest.range(of: ": ").map { rest[..<$0.lowerBound] } ?? rest

    return "\(file): \(path)"
  }

  /// Lines that belong to the registry, term, source, near-duplicate title and dash checks.
  static func isOutsideTheRules(_ line: String) -> Bool {
    line.contains("; use ")
      || (line.contains(": source '") || line.contains(": source \"")) && line.contains("is not in documents/registry.json")
      || line.contains("has an em or en dash")
  }
}
