import CatalogJSON
import Testing

struct JSONWriterTests {
  private func write(_ value: JSONValue, _ style: JSONWriter.Style = JSONWriter.Style()) throws -> String {
    try JSONWriter.write(value, style: style)
  }

  @Test(arguments: [
    (JSONValue.null, "null"),
    (.bool(true), "true"),
    (.bool(false), "false"),
    (.int(0), "0"),
    (.int(-42), "-42"),
    (.int(25105), "25105"),
    (.double(3.5), "3.5"),
    (.double(100.0), "100.0"),
    (.double(-0.0), "-0.0"),
    (.double(1e-07), "1e-07"),
    (.string("plain"), "\"plain\""),
    (.array([]), "[]"),
    (.object([]), "{}")
  ])
  func writesScalarsAndEmptyContainers(value: JSONValue, expected: String) throws {
    #expect(try write(value) == expected)
  }

  @Test(arguments: [
    ("\"", #"\""#), ("\\", #"\\"#), ("/", "/"), ("\n", #"\n"#), ("\r", #"\r"#), ("\t", #"\t"#),
    ("\u{8}", #"\b"#), ("\u{C}", #"\f"#), ("\u{0}", #"\u0000"#), ("\u{1}", #"\u0001"#),
    ("\u{1F}", #"\u001f"#), (" ", " "), ("\u{7F}", "\u{7F}"), ("a/b", "a/b"),
    ("\u{2026}", "\u{2026}"), ("\u{3A9}", "\u{3A9}"), ("\u{1F600}", "\u{1F600}"),
    ("\u{2028}", "\u{2028}")
  ])
  func escapesStringsAsPythonDoes(text: String, escaped: String) throws {
    #expect(try write(.string(text)) == "\"\(escaped)\"")
  }

  @Test(arguments: [
    ("\u{2026}", #"\u2026"#), ("\u{3A9}", #"\u03a9"#), ("\u{E9}", #"\u00e9"#),
    ("\u{7F}", #"\u007f"#), ("\u{1F600}", #"\ud83d\ude00"#), ("\u{7E}", "~"),
    ("\"", #"\""#), ("\n", #"\n"#), ("\u{1}", #"\u0001"#)
  ])
  func escapesNonASCIIWhenAsked(text: String, escaped: String) throws {
    let style = JSONWriter.Style(asciiOnly: true)
    #expect(try write(.string(text), style) == "\"\(escaped)\"")
  }

  @Test func indentsTwoSpacesPerLevelWithoutTrailingSpaces() throws {
    let value = JSONValue.object([
      JSONMember(key: "a", value: .array([.int(1), .array([]), .object([])])),
      JSONMember(key: "b", value: .object([JSONMember(key: "c", value: .null)]))
    ])
    let expected = """
      {
        "a": [
          1,
          [],
          {}
        ],
        "b": {
          "c": null
        }
      }
      """
    #expect(try write(value) == expected)
  }

  @Test func keepsMemberOrderByDefault() throws {
    let value = JSONValue.object([
      JSONMember(key: "b", value: .int(1)),
      JSONMember(key: "a", value: .int(2))
    ])
    #expect(try write(value) == "{\n  \"b\": 1,\n  \"a\": 2\n}")
  }

  @Test func sortsKeysByCodePointAtEveryLevel() throws {
    let value = JSONValue.object([
      JSONMember(key: "b", value: .object([
        JSONMember(key: "z", value: .int(1)),
        JSONMember(key: "y", value: .int(2))
      ])),
      JSONMember(key: "\u{E9}", value: .int(3)),
      JSONMember(key: "B", value: .int(4)),
      JSONMember(key: "a", value: .int(5)),
      JSONMember(key: "\u{1F600}", value: .int(6)),
      JSONMember(key: "\u{FF5E}", value: .int(7))
    ])
    let written = try write(value, JSONWriter.Style(sortKeys: true))
    let keys = written.split(separator: "\n").compactMap { line -> String? in
      guard line.hasPrefix("  \"") else { return nil }
      return String(line.dropFirst(3).prefix { $0 != "\"" })
    }
    #expect(keys == ["B", "a", "b", "\u{E9}", "\u{FF5E}", "\u{1F600}"])
    #expect(written.contains("\"y\": 2,\n    \"z\": 1"))
  }

  @Test func escapesKeysLikeStrings() throws {
    let value = JSONValue.object([JSONMember(key: "a\"/\u{2026}", value: .int(1))])
    #expect(try write(value) == "{\n  \"a\\\"/\u{2026}\": 1\n}")
    #expect(try write(value, JSONWriter.Style(asciiOnly: true)) == "{\n  \"a\\\"/\\u2026\": 1\n}")
  }

  @Test func honorsTheIndentWidth() throws {
    let value = JSONValue.array([.int(1)])
    #expect(try write(value, JSONWriter.Style(indent: 4)) == "[\n    1\n]")
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func refusesNonFiniteNumbers(number: Double) {
    #expect(throws: JSONWriteError.nonFiniteNumber) {
      _ = try JSONWriter.write(.array([.double(number)]))
    }
  }

  @Test func writesWhatTheParserReads() throws {
    let text = "{\n  \"a\": [\n    1,\n    2.5,\n    \"x\\ty\"\n  ],\n  \"b\": {}\n}"
    #expect(try write(JSONParser.parse(text)) == text)
  }
}
