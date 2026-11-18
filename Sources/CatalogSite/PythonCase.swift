/// Case changes as Python's `str.lower` and `str.capitalize` make them.
enum PythonCase {
  /// The text in lower case, with a capital sigma at the end of a word written as a final sigma.
  static func lowercased(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    var result = ""

    for (index, scalar) in scalars.enumerated() {
      if scalar.value == 0x3A3 {
        result.unicodeScalars.append(isFinalSigma(at: index, in: scalars) ? "\u{3C2}" : "\u{3C3}")
      } else {
        result += scalar.properties.lowercaseMapping
      }
    }

    return result
  }

  /// The first character in title case and the rest in lower case.
  static func capitalized(_ text: String) -> String {
    guard let first = text.unicodeScalars.first else { return "" }
    return first.properties.titlecaseMapping + lowercased(String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())))
  }

  /// A capital sigma is final when a cased letter comes before it and none comes after it, with
  /// case-ignorable characters skipped on both sides.
  private static func isFinalSigma(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
    var before = index - 1
    while before >= 0, scalars[before].properties.isCaseIgnorable { before -= 1 }
    guard before >= 0, scalars[before].properties.isCased else { return false }

    var after = index + 1
    while after < scalars.count, scalars[after].properties.isCaseIgnorable { after += 1 }
    return after == scalars.count || !scalars[after].properties.isCased
  }
}
