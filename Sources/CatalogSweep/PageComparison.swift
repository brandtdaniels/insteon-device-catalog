import Foundation

/// Where two pages first differ.
public struct PageDifference: Equatable, Sendable, CustomStringConvertible {
  /// The byte offset of the first byte that differs, or the length of the shorter page when one
  /// page is a prefix of the other.
  public let offset: Int
  /// The Swift page around the offset.
  public let swiftExcerpt: String
  /// The Python page around the offset.
  public let pythonExcerpt: String

  public var description: String {
    "first difference at byte \(offset)\n    Swift:  \(swiftExcerpt)\n    Python: \(pythonExcerpt)"
  }
}

/// Compares the Swift page with the Python build's page, byte for byte.
public enum PageComparison {
  /// How many bytes of context an excerpt shows on each side of the first difference.
  static let context = 60

  /// The first difference between the pages, or `nil` when they are the same bytes.
  public static func firstDifference(swift: String, python: String) -> PageDifference? {
    firstDifference(swift: Array(swift.utf8), python: Array(python.utf8))
  }

  public static func firstDifference(swift: [UInt8], python: [UInt8]) -> PageDifference? {
    let shared = min(swift.count, python.count)
    var offset = 0

    while offset < shared, swift[offset] == python[offset] { offset += 1 }

    guard offset < shared || swift.count != python.count else { return nil }

    return PageDifference(offset: offset, swiftExcerpt: excerpt(swift, at: offset), pythonExcerpt: excerpt(python, at: offset))
  }

  /// The bytes around the offset as text, with line ends and tabs written out.
  static func excerpt(_ bytes: [UInt8], at offset: Int) -> String {
    let start = max(0, offset - context)
    let end = min(bytes.count, offset + context)
    let before = String(decoding: bytes[start..<min(offset, bytes.count)], as: UTF8.self)
    let after = String(decoding: bytes[min(offset, bytes.count)..<end], as: UTF8.self)

    return (before + "[HERE]" + after).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
  }
}
