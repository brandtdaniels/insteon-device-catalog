import Foundation

/// Why the version rule fails.
public enum VersionProblem: Error, Equatable, Sendable, CustomStringConvertible {
  /// A `VERSION` text, trimmed, isn't MAJOR.MINOR.
  case malformed(String)
  /// `VERSION` is lower than the base's.
  case wentDown
  /// A schema changed and `VERSION` isn't higher than the base's.
  case schemaChangedWithoutBump
  /// git can't compare the schemas with the base.
  case cannotCompare(base: String)
  /// A file can't be read from disk.
  case unreadable(file: String)

  public var description: String {
    switch self {
    case .malformed(let text):
      "VERSION must be MAJOR.MINOR, not \(Self.quoted(text))"
    case .wentDown:
      "VERSION went down."
    case .schemaChangedWithoutBump:
      "The schemas changed, so VERSION needs a higher MAJOR.MINOR."
    case .cannotCompare(let base):
      "git couldn't compare schema with \(base)"
    case .unreadable(let file):
      "\(file) can't be read"
    }
  }

  /// The text in single quotes, or double quotes when it holds only single quotes, with
  /// backslash escapes for the quote, the backslash and control characters.
  private static func quoted(_ text: String) -> String {
    let quote: Character = text.contains("'") && !text.contains("\"") ? "\"" : "'"
    var result = String(quote)
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case _ where Character(scalar) == quote: result += "\\\(quote)"
      case _ where scalar.value < 0x20 || scalar.value == 0x7F:
        result += "\\x" + (scalar.value < 0x10 ? "0" : "") + String(scalar.value, radix: 16)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + String(quote)
  }
}

/// A catalog version: MAJOR and MINOR, compared as numbers of any size.
struct MajorMinor: Comparable, Sendable {
  private let major: String
  private let minor: String

  /// Reads `MAJOR.MINOR` from a text with optional surrounding whitespace.
  init(_ text: String) throws(VersionProblem) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else {
      throw .malformed(trimmed)
    }
    major = Self.withoutLeadingZeros(parts[0])
    minor = Self.withoutLeadingZeros(parts[1])
  }

  static func < (lhs: MajorMinor, rhs: MajorMinor) -> Bool {
    if lhs.major != rhs.major { return Self.isSmaller(lhs.major, rhs.major) }
    return Self.isSmaller(lhs.minor, rhs.minor)
  }

  private static func withoutLeadingZeros(_ digits: Substring) -> String {
    let stripped = digits.drop { $0 == "0" }
    return stripped.isEmpty ? "0" : String(stripped)
  }

  /// Orders digit strings without leading zeros as numbers: fewer digits is smaller, then by digits.
  private static func isSmaller(_ lhs: String, _ rhs: String) -> Bool {
    lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs
  }
}

/// The rule that a change to the schemas raises the catalog's version.
///
/// A schema change needs a higher MAJOR.MINOR in `VERSION` than the base has, and `VERSION`
/// never goes down. A base without `VERSION` has nothing to raise.
public struct VersionCheck: Sendable {
  private let git: any GitReading

  public init(git: any GitReading) {
    self.git = git
  }

  /// Checks the `VERSION` file in a repository against the base revision.
  public func verify(base: String, root: URL) throws(VersionProblem) {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("VERSION")) else {
      throw .unreadable(file: "VERSION")
    }
    try verify(base: base, current: String(decoding: data, as: UTF8.self))
  }

  /// Checks the text of the current `VERSION` against the base revision and `HEAD`.
  public func verify(base: String, current: String) throws(VersionProblem) {
    let new = try MajorMinor(current)
    let old = try git.contents(of: "VERSION", at: base).map { text throws(VersionProblem) in try MajorMinor(text) }

    if let old, new < old { throw .wentDown }

    // A base without VERSION predates versioning, so adding it counts as raising it.
    if try schemaChanged(since: base), let old, new <= old { throw .schemaChangedWithoutBump }
  }

  private func schemaChanged(since base: String) throws(VersionProblem) -> Bool {
    let paths: [String]
    do {
      paths = try git.changedPaths(from: base, to: "HEAD")
    } catch {
      throw .cannotCompare(base: base)
    }
    return paths.contains { $0 == "schema" || $0.hasPrefix("schema/") }
  }
}
