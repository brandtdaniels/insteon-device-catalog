import CatalogJSON
import Testing

struct JSONParserTests {
  @Test func parsesEveryValueKind() throws {
    let value = try JSONParser.parse(#"{"n": null, "t": true, "f": false, "i": 3, "d": 3.5, "s": "x", "a": [1], "o": {}}"#)
    #expect(value == .object([
      JSONMember(key: "n", value: .null),
      JSONMember(key: "t", value: .bool(true)),
      JSONMember(key: "f", value: .bool(false)),
      JSONMember(key: "i", value: .int(3)),
      JSONMember(key: "d", value: .double(3.5)),
      JSONMember(key: "s", value: .string("x")),
      JSONMember(key: "a", value: .array([.int(1)])),
      JSONMember(key: "o", value: .object([]))
    ]))
  }

  @Test func keepsObjectMemberOrder() throws {
    let value = try JSONParser.parse(#"{"b": 1, "a": 2, "c": 3}"#)
    guard case .object(let members) = value else {
      Issue.record("not an object")
      return
    }
    #expect(members.map(\.key) == ["b", "a", "c"])
  }

  @Test(arguments: [
    ("0", JSONValue.int(0)),
    ("-0", .int(0)),
    ("25105", .int(25105)),
    ("-7", .int(-7)),
    ("0.067", .double(0.067)),
    ("755.2", .double(755.2)),
    ("1e-07", .double(1e-07)),
    ("1E5", .double(100000.0)),
    ("-0.0", .double(-0.0)),
    ("100.0", .double(100.0))
  ])
  func parsesNumbers(text: String, expected: JSONValue) throws {
    #expect(try JSONParser.parse(text) == expected)
  }

  @Test(arguments: [
    (#""a\"b\\c\/d\b\f\n\r\t""#, "a\"b\\c/d\u{8}\u{C}\n\r\t"),
    (#""\u00e9""#, "\u{E9}"),
    (#""\ud83d\ude00""#, "\u{1F600}"),
    (#""\u0000""#, "\u{0}"),
    ("\"\u{2026} \u{3A9}\"", "\u{2026} \u{3A9}")
  ])
  func parsesStrings(text: String, expected: String) throws {
    #expect(try JSONParser.parse(text) == .string(expected))
  }

  @Test func allowsSurroundingWhitespace() throws {
    #expect(try JSONParser.parse(" \n\t\r[ ]\n") == .array([]))
  }

  @Test func acceptsNestingUpToTheLimit() throws {
    let text = String(repeating: "[", count: 64) + String(repeating: "]", count: 64)
    _ = try JSONParser.parse(text, maximumDepth: 64)
  }

  struct Rejection: CustomTestStringConvertible, Sendable {
    let name: String
    let text: String
    let line: Int
    let column: Int
    let message: String
    var testDescription: String { name }
  }

  @Test(arguments: [
    Rejection(name: "duplicate key", text: #"{"a": 1, "a": 2}"#, line: 1, column: 10, message: "duplicate key \"a\""),
    Rejection(name: "duplicate key on a later line", text: "{\n  \"a\": 1,\n  \"a\": 2\n}", line: 3, column: 3, message: "duplicate key \"a\""),
    Rejection(name: "NaN", text: "[NaN]", line: 1, column: 2, message: "NaN is not JSON"),
    Rejection(name: "Infinity", text: "[Infinity]", line: 1, column: 2, message: "Infinity is not JSON"),
    Rejection(name: "negative Infinity", text: "[-Infinity]", line: 1, column: 2, message: "Infinity is not JSON"),
    Rejection(name: "overflowing float", text: "[1e999]", line: 1, column: 2, message: "number out of range"),
    Rejection(name: "overflowing integer", text: "[99999999999999999999]", line: 1, column: 2, message: "integer out of range"),
    Rejection(name: "trailing comma in array", text: "[1, 2,]", line: 1, column: 7, message: "unexpected \"]\""),
    Rejection(name: "trailing comma in object", text: #"{"a": 1,}"#, line: 1, column: 9, message: "expected a string key"),
    Rejection(name: "leading zero", text: "[01]", line: 1, column: 3, message: "leading zero"),
    Rejection(name: "bare decimal point", text: "[1.]", line: 1, column: 4, message: "digit expected"),
    Rejection(name: "plus sign", text: "[+1]", line: 1, column: 2, message: "unexpected \"+\""),
    Rejection(name: "single quotes", text: "{'a': 1}", line: 1, column: 2, message: "expected a string key"),
    Rejection(name: "comment", text: "[1] // x", line: 1, column: 5, message: "unexpected \"/\" after the value"),
    Rejection(name: "unterminated string", text: "[\"abc", line: 1, column: 6, message: "unterminated string"),
    Rejection(name: "raw control character in string", text: "[\"a\tb\"]", line: 1, column: 4, message: "control character in string"),
    Rejection(name: "unknown escape", text: #"["\x"]"#, line: 1, column: 4, message: "invalid escape"),
    Rejection(name: "short unicode escape", text: #"["\u12"]"#, line: 1, column: 4, message: "invalid unicode escape"),
    Rejection(name: "lone high surrogate", text: #"["\ud83d"]"#, line: 1, column: 3, message: "unpaired surrogate"),
    Rejection(name: "lone low surrogate", text: #"["\ude00"]"#, line: 1, column: 3, message: "unpaired surrogate"),
    Rejection(name: "empty input", text: "", line: 1, column: 1, message: "unexpected end of input"),
    Rejection(name: "unclosed array", text: "[1", line: 1, column: 3, message: "unexpected end of input"),
    Rejection(name: "missing colon", text: #"{"a" 1}"#, line: 1, column: 6, message: "expected \":\""),
    Rejection(name: "second document", text: "[] []", line: 1, column: 4, message: "unexpected \"[\" after the value"),
    Rejection(name: "unknown literal", text: "[nul]", line: 1, column: 2, message: "unexpected \"n\""),
    Rejection(name: "nesting beyond the limit", text: String(repeating: "[", count: 5) + String(repeating: "]", count: 5), line: 1, column: 4, message: "nesting deeper than 3")
  ])
  func rejects(_ rejection: Rejection) {
    let error = #expect(throws: JSONParseError.self) {
      _ = try JSONParser.parse(rejection.text, maximumDepth: 3)
    }
    #expect(error?.line == rejection.line)
    #expect(error?.column == rejection.column)
    #expect(error?.message == rejection.message)
  }

  @Test func rejectsInvalidUTF8AtTheOffendingByte() {
    let bytes: [UInt8] = Array(#"["ab"#.utf8) + [0xFF] + Array(#"cd"]"#.utf8)
    let error = #expect(throws: JSONParseError.self) {
      _ = try JSONParser.parse(bytes)
    }
    #expect(error?.message == "invalid UTF-8")
    #expect(error?.line == 1)
    #expect(error?.column == 5)
  }

  @Test func rejectsATruncatedUTF8Sequence() {
    let bytes: [UInt8] = Array(#"["x"#.utf8) + [0xE2, 0x80]
    let error = #expect(throws: JSONParseError.self) {
      _ = try JSONParser.parse(bytes)
    }
    #expect(error?.message == "invalid UTF-8")
  }

  @Test func errorDescriptionNamesThePosition() {
    let error = #expect(throws: JSONParseError.self) {
      _ = try JSONParser.parse("{\n  \"a\": NaN\n}")
    }
    #expect(error?.description == "line 2, column 8: NaN is not JSON")
  }
}
