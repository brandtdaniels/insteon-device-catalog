/// A strict JSON parser.
///
/// It accepts RFC 8259 and nothing more: no comments, trailing commas, `NaN` or `Infinity`.
/// It rejects duplicate keys within an object, invalid UTF-8, integers beyond `Int`, and nesting
/// beyond a limit. Objects keep the order of their members.
public enum JSONParser {
  /// The deepest nesting of arrays and objects a document may have unless the caller says otherwise.
  public static let defaultMaximumDepth = 512

  /// Parses UTF-8 text.
  public static func parse(_ text: String, maximumDepth: Int = defaultMaximumDepth) throws(JSONParseError) -> JSONValue {
    try parse(Array(text.utf8), maximumDepth: maximumDepth)
  }

  /// Parses UTF-8 bytes.
  ///
  /// - Throws: ``JSONParseError`` naming the line and column of the first problem.
  public static func parse(_ bytes: [UInt8], maximumDepth: Int = defaultMaximumDepth) throws(JSONParseError) -> JSONValue {
    var reader = Reader(bytes: bytes, maximumDepth: maximumDepth)
    try reader.validateUTF8()
    reader.skipWhitespace()
    let value = try reader.readValue(depth: 0)
    reader.skipWhitespace()
    if let byte = reader.peek {
      throw reader.failure("unexpected \(reader.describe(byte)) after the value")
    }
    return value
  }
}

private struct Reader {
  let bytes: [UInt8]
  let maximumDepth: Int
  var index = 0

  init(bytes: [UInt8], maximumDepth: Int) {
    self.bytes = bytes
    self.maximumDepth = maximumDepth
  }

  var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

  // MARK: Errors

  func failure(_ message: String, at offset: Int? = nil) -> JSONParseError {
    let offset = min(offset ?? index, bytes.count)
    var line = 1
    var lineStart = 0
    for position in 0..<offset where bytes[position] == 0x0A {
      line += 1
      lineStart = position + 1
    }
    let column = 1 + bytes[lineStart..<offset].filter { $0 & 0xC0 != 0x80 }.count
    return JSONParseError(message: message, line: line, column: column)
  }

  /// Names the character that starts at `byte` for a message.
  func describe(_ byte: UInt8) -> String {
    let scalar = Unicode.Scalar(byte)
    return byte < 0x20 || byte >= 0x7F ? "byte 0x" + hex(byte) : "\"\(Character(scalar))\""
  }

  private func hex(_ byte: UInt8) -> String {
    let digits = Array("0123456789ABCDEF")
    return String([digits[Int(byte >> 4)], digits[Int(byte & 0xF)]])
  }

  // MARK: UTF-8

  func validateUTF8() throws(JSONParseError) {
    var iterator = bytes.makeIterator()
    var parser = Unicode.UTF8.ForwardParser()
    var offset = 0
    while true {
      switch parser.parseScalar(from: &iterator) {
      case .valid(let scalar): offset += scalar.count
      case .emptyInput: return
      case .error: throw failure("invalid UTF-8", at: offset)
      }
    }
  }

  // MARK: Values

  mutating func skipWhitespace() {
    while let byte = peek, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
      index += 1
    }
  }

  mutating func readValue(depth: Int) throws(JSONParseError) -> JSONValue {
    guard let byte = peek else { throw failure("unexpected end of input") }
    switch byte {
    case UInt8(ascii: "{"): return try readObject(depth: depth + 1)
    case UInt8(ascii: "["): return try readArray(depth: depth + 1)
    case UInt8(ascii: "\""): return .string(try readString())
    case UInt8(ascii: "t"): return try readLiteral("true", as: .bool(true))
    case UInt8(ascii: "f"): return try readLiteral("false", as: .bool(false))
    case UInt8(ascii: "n"): return try readLiteral("null", as: .null)
    case UInt8(ascii: "N"): return try readNonNumber("NaN")
    case UInt8(ascii: "I"): return try readNonNumber("Infinity")
    case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try readNumber()
    default: throw failure("unexpected \(describe(byte))")
    }
  }

  mutating func readLiteral(_ word: String, as value: JSONValue) throws(JSONParseError) -> JSONValue {
    let expected = Array(word.utf8)
    guard bytes[index...].starts(with: expected) else {
      throw failure("unexpected \(describe(bytes[index]))")
    }
    index += expected.count
    return value
  }

  func readNonNumber(_ word: String) throws(JSONParseError) -> JSONValue {
    if bytes[index...].starts(with: Array(word.utf8)) {
      throw failure("\(word) is not JSON")
    }
    throw failure("unexpected \(describe(bytes[index]))")
  }

  mutating func enter(_ depth: Int) throws(JSONParseError) {
    if depth > maximumDepth {
      throw failure("nesting deeper than \(maximumDepth)")
    }
  }

  mutating func readArray(depth: Int) throws(JSONParseError) -> JSONValue {
    try enter(depth)
    index += 1
    var elements: [JSONValue] = []
    skipWhitespace()
    if peek == UInt8(ascii: "]") {
      index += 1
      return .array(elements)
    }
    while true {
      skipWhitespace()
      elements.append(try readValue(depth: depth))
      skipWhitespace()
      guard let byte = peek else { throw failure("unexpected end of input") }
      index += 1
      if byte == UInt8(ascii: "]") { return .array(elements) }
      if byte != UInt8(ascii: ",") {
        throw failure("expected \",\" or \"]\", found \(describe(byte))", at: index - 1)
      }
      skipWhitespace()
      if peek == UInt8(ascii: "]") { throw failure("unexpected \"]\"") }
    }
  }

  mutating func readObject(depth: Int) throws(JSONParseError) -> JSONValue {
    try enter(depth)
    index += 1
    var members: [JSONMember] = []
    var seen = Set<[UInt8]>()
    skipWhitespace()
    if peek == UInt8(ascii: "}") {
      index += 1
      return .object(members)
    }
    while true {
      skipWhitespace()
      guard let first = peek else { throw failure("unexpected end of input") }
      guard first == UInt8(ascii: "\"") else { throw failure("expected a string key") }
      let keyOffset = index
      let key = try readString()
      // Keys compare by their scalars; String equality would also equate canonically equivalent keys.
      guard seen.insert(Array(key.utf8)).inserted else {
        throw failure("duplicate key \"\(key)\"", at: keyOffset)
      }
      skipWhitespace()
      guard peek == UInt8(ascii: ":") else {
        if peek == nil { throw failure("unexpected end of input") }
        throw failure("expected \":\"")
      }
      index += 1
      skipWhitespace()
      members.append(JSONMember(key: key, value: try readValue(depth: depth)))
      skipWhitespace()
      guard let byte = peek else { throw failure("unexpected end of input") }
      index += 1
      if byte == UInt8(ascii: "}") { return .object(members) }
      if byte != UInt8(ascii: ",") {
        throw failure("expected \",\" or \"}\", found \(describe(byte))", at: index - 1)
      }
    }
  }

  // MARK: Numbers

  mutating func readNumber() throws(JSONParseError) -> JSONValue {
    let start = index
    if peek == UInt8(ascii: "-") {
      index += 1
      if bytes[index...].starts(with: Array("Infinity".utf8)) { throw failure("Infinity is not JSON", at: start) }
    }
    guard let first = peek, isDigit(first) else { throw failure("digit expected") }
    index += 1
    if first == UInt8(ascii: "0"), let next = peek, isDigit(next) { throw failure("leading zero") }
    if first != UInt8(ascii: "0") { skipDigits() }
    var isInteger = true
    if peek == UInt8(ascii: ".") {
      isInteger = false
      index += 1
      try requireDigits()
    }
    if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
      isInteger = false
      index += 1
      if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
      try requireDigits()
    }
    let lexeme = String(decoding: bytes[start..<index], as: UTF8.self)
    if isInteger {
      guard let value = Int(lexeme) else { throw failure("integer out of range", at: start) }
      return .int(value)
    }
    guard let value = Double(lexeme), value.isFinite else { throw failure("number out of range", at: start) }
    return .double(value)
  }

  func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

  mutating func skipDigits() {
    while let byte = peek, isDigit(byte) { index += 1 }
  }

  mutating func requireDigits() throws(JSONParseError) {
    guard let byte = peek, isDigit(byte) else { throw failure("digit expected") }
    skipDigits()
  }

  // MARK: Strings

  mutating func readString() throws(JSONParseError) -> String {
    index += 1
    var buffer: [UInt8] = []
    while true {
      guard let byte = peek else { throw failure("unterminated string") }
      switch byte {
      case UInt8(ascii: "\""):
        index += 1
        return String(decoding: buffer, as: UTF8.self)
      case UInt8(ascii: "\\"):
        try readEscape(into: &buffer)
      case 0..<0x20:
        throw failure("control character in string")
      default:
        buffer.append(byte)
        index += 1
      }
    }
  }

  mutating func readEscape(into buffer: inout [UInt8]) throws(JSONParseError) {
    let backslash = index
    index += 1
    guard let byte = peek else { throw failure("unterminated string") }
    let simple: UInt8?
    switch byte {
    case UInt8(ascii: "\""): simple = 0x22
    case UInt8(ascii: "\\"): simple = 0x5C
    case UInt8(ascii: "/"): simple = 0x2F
    case UInt8(ascii: "b"): simple = 0x08
    case UInt8(ascii: "f"): simple = 0x0C
    case UInt8(ascii: "n"): simple = 0x0A
    case UInt8(ascii: "r"): simple = 0x0D
    case UInt8(ascii: "t"): simple = 0x09
    case UInt8(ascii: "u"): simple = nil
    default: throw failure("invalid escape")
    }
    if let simple {
      buffer.append(simple)
      index += 1
      return
    }
    let unit = try readUnicodeEscapeUnit()
    var scalarValue = UInt32(unit)
    if (0xD800...0xDBFF).contains(unit) {
      guard bytes[index...].starts(with: Array("\\u".utf8)) else {
        throw failure("unpaired surrogate", at: backslash)
      }
      index += 1
      let low = try readUnicodeEscapeUnit()
      guard (0xDC00...0xDFFF).contains(low) else { throw failure("unpaired surrogate", at: backslash) }
      scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
    } else if (0xDC00...0xDFFF).contains(unit) {
      throw failure("unpaired surrogate", at: backslash)
    }
    buffer.append(contentsOf: Array(String(Unicode.Scalar(scalarValue)!).utf8))
  }

  /// Reads `u` and four hexadecimal digits, with `index` on the `u`.
  mutating func readUnicodeEscapeUnit() throws(JSONParseError) -> UInt16 {
    let marker = index
    index += 1
    var unit: UInt16 = 0
    for _ in 0..<4 {
      guard let byte = peek, let digit = hexValue(byte) else {
        throw failure("invalid unicode escape", at: marker)
      }
      unit = unit << 4 | UInt16(digit)
      index += 1
    }
    return unit
  }

  func hexValue(_ byte: UInt8) -> Int? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"): Int(byte - UInt8(ascii: "a")) + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): Int(byte - UInt8(ascii: "A")) + 10
    default: nil
    }
  }
}
