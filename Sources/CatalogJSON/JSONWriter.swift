/// A reason a value can't be written as JSON.
public enum JSONWriteError: Error, Equatable, Sendable {
  /// A `double` is `NaN` or infinite.
  case nonFiniteNumber
}

/// Writes JSON the way Python's `json.dumps(value, indent: 2)` does, byte for byte.
///
/// The output has no trailing newline; callers add one when they write a file.
public enum JSONWriter {
  /// How a document is laid out.
  public struct Style: Equatable, Sendable {
    /// Spaces per nesting level.
    public var indent: Int
    /// Whether each object lists its keys in code point order instead of member order.
    public var sortKeys: Bool
    /// Whether every non-ASCII character is written as a `\u` escape.
    public var asciiOnly: Bool

    public init(indent: Int = 2, sortKeys: Bool = false, asciiOnly: Bool = false) {
      self.indent = indent
      self.sortKeys = sortKeys
      self.asciiOnly = asciiOnly
    }
  }

  /// Writes `value` as text.
  ///
  /// - Throws: ``JSONWriteError/nonFiniteNumber`` when a `double` is not finite.
  public static func write(_ value: JSONValue, style: Style = Style()) throws(JSONWriteError) -> String {
    var output: [UInt8] = []
    try append(value, level: 0, style: style, to: &output)
    return String(decoding: output, as: UTF8.self)
  }

  private static func append(_ value: JSONValue, level: Int, style: Style, to output: inout [UInt8]) throws(JSONWriteError) {
    switch value {
    case .null:
      output.append(contentsOf: "null".utf8)
    case .bool(let flag):
      output.append(contentsOf: (flag ? "true" : "false").utf8)
    case .int(let number):
      output.append(contentsOf: String(number).utf8)
    case .double(let number):
      guard let text = PythonFloat.format(number) else { throw .nonFiniteNumber }
      output.append(contentsOf: text.utf8)
    case .string(let text):
      appendString(text, asciiOnly: style.asciiOnly, to: &output)
    case .array(let elements):
      guard !elements.isEmpty else {
        output.append(contentsOf: "[]".utf8)
        return
      }
      output.append(UInt8(ascii: "["))
      for (position, element) in elements.enumerated() {
        if position > 0 { output.append(UInt8(ascii: ",")) }
        appendLineBreak(level: level + 1, style: style, to: &output)
        try append(element, level: level + 1, style: style, to: &output)
      }
      appendLineBreak(level: level, style: style, to: &output)
      output.append(UInt8(ascii: "]"))
    case .object(let members):
      guard !members.isEmpty else {
        output.append(contentsOf: "{}".utf8)
        return
      }
      let ordered = style.sortKeys
        ? members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        : members
      output.append(UInt8(ascii: "{"))
      for (position, member) in ordered.enumerated() {
        if position > 0 { output.append(UInt8(ascii: ",")) }
        appendLineBreak(level: level + 1, style: style, to: &output)
        appendString(member.key, asciiOnly: style.asciiOnly, to: &output)
        output.append(contentsOf: ": ".utf8)
        try append(member.value, level: level + 1, style: style, to: &output)
      }
      appendLineBreak(level: level, style: style, to: &output)
      output.append(UInt8(ascii: "}"))
    }
  }

  private static func appendLineBreak(level: Int, style: Style, to output: inout [UInt8]) {
    output.append(UInt8(ascii: "\n"))
    output.append(contentsOf: repeatElement(UInt8(ascii: " "), count: level * style.indent))
  }

  private static func appendString(_ text: String, asciiOnly: Bool, to output: inout [UInt8]) {
    output.append(UInt8(ascii: "\""))
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22: output.append(contentsOf: #"\""#.utf8)
      case 0x5C: output.append(contentsOf: #"\\"#.utf8)
      case 0x0A: output.append(contentsOf: #"\n"#.utf8)
      case 0x0D: output.append(contentsOf: #"\r"#.utf8)
      case 0x09: output.append(contentsOf: #"\t"#.utf8)
      case 0x08: output.append(contentsOf: #"\b"#.utf8)
      case 0x0C: output.append(contentsOf: #"\f"#.utf8)
      case 0x20...0x7E:
        output.append(UInt8(scalar.value))
      case 0x00...0x1F:
        appendEscape(UInt16(scalar.value), to: &output)
      default:
        if asciiOnly {
          for unit in UTF16.encode(scalar)! { appendEscape(unit, to: &output) }
        } else {
          output.append(contentsOf: String(scalar).utf8)
        }
      }
    }
    output.append(UInt8(ascii: "\""))
  }

  private static func appendEscape(_ unit: UInt16, to output: inout [UInt8]) {
    let digits = Array("0123456789abcdef".utf8)
    output.append(contentsOf: #"\u"#.utf8)
    for shift in stride(from: 12, through: 0, by: -4) {
      output.append(digits[Int(unit >> UInt16(shift)) & 0xF])
    }
  }
}
