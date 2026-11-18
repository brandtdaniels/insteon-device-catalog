import Foundation

/// What a run of the ingestion tool left behind, as named parts: its exit status, what it printed,
/// the files it wrote.
///
/// A golden file holds the parts one after another. Each part is a header line, `=== name length`,
/// then exactly `length` bytes and a newline, so no content can be mistaken for a header.
public struct IngestGolden: Equatable, Sendable {
  public struct Part: Equatable, Sendable {
    public let name: String
    public let bytes: [UInt8]

    public init(name: String, bytes: [UInt8]) {
      self.name = name
      self.bytes = bytes
    }

    public var text: String {
      String(decoding: bytes, as: UTF8.self)
    }
  }

  public var parts: [Part]

  public init(parts: [Part] = []) {
    self.parts = parts
  }

  public mutating func add(_ name: String, _ text: String) {
    parts.append(Part(name: name, bytes: Array(text.utf8)))
  }

  /// The text of the part with this name.
  public subscript(name: String) -> String? {
    parts.first { $0.name == name }?.text
  }

  public func serialized() -> [UInt8] {
    var output: [UInt8] = []

    for part in parts {
      output += Array("=== \(part.name) \(part.bytes.count)\n".utf8)
      output += part.bytes
      output.append(0x0A)
    }

    return output
  }

  /// The parts in the bytes, or `nil` when they are not in the golden layout.
  public static func parse(_ bytes: [UInt8]) -> IngestGolden? {
    var parts: [Part] = []
    var index = 0

    while index < bytes.count {
      guard let end = bytes[index...].firstIndex(of: 0x0A) else { return nil }
      let header = String(decoding: bytes[index..<end], as: UTF8.self).split(separator: " ", omittingEmptySubsequences: false)

      guard header.count >= 3, header[0] == "===", let length = Int(header[header.count - 1]) else { return nil }
      let start = end + 1
      guard start + length < bytes.count, bytes[start + length] == 0x0A else { return nil }

      parts.append(Part(name: header[1..<(header.count - 1)].joined(separator: " "), bytes: Array(bytes[start..<(start + length)])))
      index = start + length + 1
    }

    return IngestGolden(parts: parts)
  }
}
