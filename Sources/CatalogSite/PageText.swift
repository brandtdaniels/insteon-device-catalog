import CatalogJSON

/// The small pieces of wording and number formatting the page's text is made of.
enum PageText {
  /// A count with its noun, such as `1 minute` or `5 minutes`.
  static func countNoun(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
  }

  /// The number a hexadecimal byte such as `0x2E` holds.
  static func number(ofHex text: String) -> Int {
    var digits = Substring(text)
    if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits = digits.dropFirst(2) }
    return Int(digits, radix: 16) ?? 0
  }

  /// The first letter in capitals and the rest in lower case.
  static func capitalized(_ text: String) -> String {
    PythonCase.capitalized(text)
  }

  /// How the page shows an identity's engine, and the sentence that says which firmware runs it.
  static func engineNote(_ entry: JSONValue) -> (label: String, tooltip: String) {
    let engine = entry.text("engine")
    let label = PageTables.engineLabels[engine] ?? engine

    guard let selection = entry["firmware"] else { return (label, "Every firmware version runs \(label).") }

    if let only = selection["only"] {
      return ("\(label) on some firmware", "Firmware \(only.strings.joined(separator: ", ")) runs \(label).")
    }

    return (
      "\(label) on most firmware",
      "Every firmware version except \((selection["except"] ?? .null).strings.joined(separator: ", ")) runs \(label)."
    )
  }
}
