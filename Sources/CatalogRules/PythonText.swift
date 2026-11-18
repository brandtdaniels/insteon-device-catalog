import CatalogJSON
import Foundation

/// A string compared by its code points, as Python compares strings. Swift's own `==` treats
/// canonically equivalent strings as equal, which would let `e` with a combining accent match a
/// title that holds the precomposed letter.
struct ExactText: Hashable, Sendable {
  let utf8: [UInt8]

  init(_ text: String) {
    utf8 = Array(text.utf8)
  }
}

extension Unicode.Scalar {
  /// Whether Python's `str.isspace` is true for the character, which is also what its `\s` matches
  /// and `str.strip` removes.
  var isPythonWhitespace: Bool {
    switch value {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
      true
    default:
      false
    }
  }
}

extension String {
  /// Whether `str.strip()` leaves nothing.
  var isBlankToPython: Bool {
    unicodeScalars.allSatisfy(\.isPythonWhitespace)
  }

  /// Whether the text holds an em dash (U+2014) or an en dash (U+2013).
  var hasEmOrEnDash: Bool {
    unicodeScalars.contains { $0.value == 0x2013 || $0.value == 0x2014 }
  }
}

/// The characters Python's `\s` matches, as a character class body that ICU reads the same way.
let pythonWhitespaceClass = #"\x{09}-\x{0D}\x{1C}-\x{20}\x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}"#

/// A value as Python's `repr` writes it.
func pythonRepr(_ value: JSONValue) -> String {
  switch value {
  case .null: "None"
  case .bool(let flag): flag ? "True" : "False"
  case .int(let number): String(number)
  case .double(let number): PythonFloat.format(number) ?? "\(number)"
  case .string(let text): pythonRepr(text)
  case .array(let elements): "[" + elements.map(pythonRepr).joined(separator: ", ") + "]"
  case .object(let members): "{" + members.map { "\(pythonRepr($0.key)): \(pythonRepr($0.value))" }.joined(separator: ", ") + "}"
  }
}

/// A regular expression the rules compile once, written as Python's `re` reads it. ICU runs it, with
/// `\w` and `\b` spelled out as Python means them: a letter, a number or an underscore. ICU's own
/// `\w` also takes combining marks, joiners and connector punctuation, and leaves out number
/// characters such as superscript two. Lookbehinds and every other construct pass through.
struct Pattern: Sendable {
  private let expression: NSRegularExpression

  /// A pattern that matches only a text it covers from start to end.
  static func whole(_ pattern: String) -> Pattern {
    Pattern(#"\A(?:"# + pattern + #")\z"#)
  }

  init(_ pattern: String) {
    guard let expression = try? NSRegularExpression(pattern: Self.translated(pattern)) else {
      preconditionFailure("not a regular expression: \(pattern)")
    }

    self.expression = expression
  }

  /// The characters Python's `\w` matches, without the brackets of a class.
  static let wordCharacters = #"\p{L}\p{N}_"#

  /// The pattern with `\w` and `\b` replaced by what Python means by them.
  static func translated(_ pattern: String) -> String {
    let word = "[" + wordCharacters + "]"
    var result = ""
    var insideClass = false
    var characters = pattern.makeIterator()

    while let character = characters.next() {
      switch character {
      case "\\":
        guard let escaped = characters.next() else { result.append(character); continue }

        switch (escaped, insideClass) {
        case ("w", true): result += wordCharacters
        case ("w", false): result += word
        case ("b", false): result += "(?:(?<=\(word))(?!\(word))|(?<!\(word))(?=\(word)))"
        default: result += "\\" + String(escaped)
        }
      case "[" where !insideClass:
        insideClass = true
        result.append(character)
      case "]" where insideClass:
        insideClass = false
        result.append(character)
      default:
        result.append(character)
      }
    }

    return result
  }

  /// The text of the leftmost match, as `re.search` finds it, or `nil`.
  func firstMatch(in text: String) -> String? {
    guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.range.location != NSNotFound
    else { return nil }

    // The match can end inside a grapheme cluster, such as a letter followed by a combining mark.
    // Converting the range through the UTF-16 view keeps such a match; `Range(_:in:)` can drop it.
    let units = text.utf16
    let start = units.index(units.startIndex, offsetBy: match.range.location)
    let end = units.index(start, offsetBy: match.range.length)

    return String(text[start..<end])
  }

  /// Whether the whole text matches, as `re.fullmatch` says: the pattern was made with `whole`.
  func matches(_ text: String) -> Bool {
    expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  /// The text with every match removed, as `re.sub(pattern, "", text)` leaves it.
  func removingMatches(from text: String) -> String {
    expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
  }
}
