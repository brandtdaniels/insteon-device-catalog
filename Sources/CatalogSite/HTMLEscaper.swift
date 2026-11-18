/// Escapes text for HTML the way Python's `html.escape(text, quote=True)` does.
enum HTMLEscaper {
  /// The text with `&`, `<`, `>`, `"` and `'` replaced by character references. Every other
  /// character, including each non-ASCII one, stays as it is.
  static func escape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)

    for scalar in text.unicodeScalars {
      switch scalar {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "'": result += "&#x27;"
      default: result.unicodeScalars.append(scalar)
      }
    }

    return result
  }
}
