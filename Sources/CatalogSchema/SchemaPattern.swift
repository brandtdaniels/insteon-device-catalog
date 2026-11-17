import Foundation

/// A `pattern` keyword's regular expression, matched the way JSON Schema asks: anywhere in the
/// string, and with `$` meaning the very end of it.
struct SchemaPattern: Sendable {
  private let expression: NSRegularExpression

  /// `nil` when the text is not a regular expression.
  init?(_ text: String) {
    guard let expression = try? NSRegularExpression(pattern: Self.strictEnd(text)) else { return nil }
    self.expression = expression
  }

  func matches(_ string: String) -> Bool {
    expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
  }

  /// ICU lets `$` match before a final newline and ECMA 262 does not. Outside a character class,
  /// each `$` becomes `\z`, which matches only at the end.
  static func strictEnd(_ pattern: String) -> String {
    var result = ""
    var insideClass = false
    var escaped = false
    for character in pattern {
      if escaped {
        escaped = false
        result.append(character)
      } else if character == "\\" {
        escaped = true
        result.append(character)
      } else if insideClass {
        if character == "]" { insideClass = false }
        result.append(character)
      } else if character == "[" {
        insideClass = true
        result.append(character)
      } else if character == "$" {
        result.append("\\z")
      } else {
        result.append(character)
      }
    }
    return result
  }
}
