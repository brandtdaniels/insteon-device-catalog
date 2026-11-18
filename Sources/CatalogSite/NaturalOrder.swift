/// Natural order: runs of digits compare as numbers and every other run compares in lower case by
/// code point, the way the page sorts models.
enum NaturalOrder {
  /// One part of a key: text, or a number kept as its digits without leading zeros.
  private enum Run: Comparable {
    case text([UInt32])
    case number(digits: [UInt8])

    static func < (left: Run, right: Run) -> Bool {
      switch (left, right) {
      case (.text(let a), .text(let b)): a.lexicographicallyPrecedes(b)
      case (.number(let a), .number(let b)): a.count != b.count ? a.count < b.count : a.lexicographicallyPrecedes(b)
      case (.text, .number): true
      case (.number, .text): false
      }
    }
  }

  /// The elements ordered by the key, with elements of equal keys in their original order.
  static func sorted<Element>(_ elements: [Element], key: (Element) -> String) -> [Element] {
    let keys = elements.map { runs(of: key($0)) }

    return elements.indices.sorted { left, right in
      let (a, b) = (keys[left], keys[right])
      if a.lexicographicallyPrecedes(b) { return true }
      if b.lexicographicallyPrecedes(a) { return false }
      return left < right
    }.map { elements[$0] }
  }

  /// The text split into alternating runs of non-digits and digits, starting with a non-digit run
  /// that may be empty, and ending with one.
  private static func runs(of text: String) -> [Run] {
    var runs: [Run] = []
    var words = ""
    var digits: [UInt8] = []

    func flushDigits() {
      guard !digits.isEmpty else { return }
      runs.append(.text(Array(PythonCase.lowercased(words).unicodeScalars.map(\.value))))
      words = ""
      runs.append(.number(digits: Array(digits.drop(while: { $0 == 0 }))))
      digits = []
    }

    for scalar in text.unicodeScalars {
      if scalar.properties.generalCategory == .decimalNumber, let value = scalar.properties.numericValue {
        digits.append(UInt8(value))
      } else {
        flushDigits()
        words.unicodeScalars.append(scalar)
      }
    }

    flushDigits()
    runs.append(.text(Array(PythonCase.lowercased(words).unicodeScalars.map(\.value))))
    return runs
  }
}
