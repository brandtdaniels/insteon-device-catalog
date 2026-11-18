import CatalogJSON
import Foundation

/// The catalog an ingestion case reads, kept as frozen profiles beside the tests.
public enum GoldenCatalog: String, Sendable {
  /// Three real profiles.
  case real
  /// Small invented profiles, one for each state a draft meets.
  case invented
}

/// An observation file a case names.
public enum IngestInput: Equatable, Sendable {
  case bytes([UInt8])
  /// A path with no file.
  case missing
}

/// What a case asks of the tool.
public enum IngestAction: Equatable, Sendable {
  case check
  /// `draft`, with a report file, a Markdown file, both, or neither.
  case draft(report: Bool, markdown: Bool)
}

/// One run of `check` or `draft` on a catalog and some files.
public struct IngestCase: Sendable {
  public let name: String
  public let catalog: GoldenCatalog
  public let action: IngestAction
  public let inputs: [IngestInput]

  public init(name: String, catalog: GoldenCatalog, action: IngestAction, inputs: [IngestInput]) {
    self.name = name
    self.catalog = catalog
    self.action = action
    self.inputs = inputs
  }
}

/// The cases the goldens and the comparisons share.
public struct IngestCaseBook: Sendable {
  let fixtures: URL

  /// - Parameter fixtures: The folder with the five observation fixtures.
  public init(fixtures: URL) {
    self.fixtures = fixtures
  }

  func fixture(_ name: String) throws -> ObservationBuilder {
    try ObservationBuilder(fixture: fixtures.appendingPathComponent(name))
  }

  func rawFixture(_ name: String) throws -> IngestInput {
    .bytes(Array(try Data(contentsOf: fixtures.appendingPathComponent(name))))
  }

  /// The invented example observation with the device's fields replaced and three checks answered,
  /// as the Python tests build it.
  func observation(_ device: [String: String?] = [:]) throws -> ObservationBuilder {
    var builder = try fixture("example-invented-product.json")
    for (key, value) in device.sorted(by: { $0.key < $1.key }) { builder = builder.device(key, value) }

    return builder
      .checks([("Get Insteon Engine Version", "answered"), ("ID Request", "answered"), ("Product Data Request", "answered")])
      .productKey("0x00001A")
      .put([.key("operatingFlags")], nil)
  }

  /// An observation of the invented catalog's profile for this subcategory.
  func invented(_ subcategory: String, _ device: [String: String?] = [:]) throws -> ObservationBuilder {
    try observation(device.merging(["subcategory": subcategory]) { _, new in new })
  }

  static func input(_ builder: ObservationBuilder) -> IngestInput {
    .bytes(builder.bytes)
  }

  static func text(_ text: String) -> IngestInput {
    .bytes(Array(text.utf8))
  }

  /// Ways to write an address, a host, an account or a path, each invented in the shape the scan rejects.
  static let leaks: [(String, String)] = [
    ("dotted address", "2F.9A.C1"),
    ("bare address", "2F9AC1"),
    ("upper-case letter address", "FACADE"),
    ("IPv4 address", "192.168.7.20"),
    ("IPv6 address", "fe80::1:2:3:4"),
    ("MAC address", "a4:5e:60:11:22:33"),
    ("URL", "https://hub.example.test/status"),
    ("host name", "hub.example.com"),
    ("email address", "someone@example.test"),
    ("home path", "/Users/someone/notes.txt"),
    ("Linux path", "/home/someone/notes"),
    ("Windows path", "C:\\Users\\someone")
  ]

  static let plainTexts = [
    "Fresh battery, device on the bench.",
    "Seen on a device running firmware 0x34, key 0x00001A.",
    "Tested at 12:30 with a decade of use.",
    "I/O Module 2450 (I/O Linc)",
    "It reported 2A 00."
  ]

  /// Every case, in the order their goldens are listed.
  public func cases() throws -> [IngestCase] {
    try checkCases() + realDraftCases() + inventedDraftCases()
  }

  // MARK: check

  func checkCases() throws -> [IngestCase] {
    let example = try fixture("example-invented-product.json")
    let io = try fixture("io-module-2450.json")
    let dimmer = try fixture("dimmer-plug-2457D2.json")
    var cases: [IngestCase] = []

    func check(_ name: String, _ inputs: [IngestInput], catalog: GoldenCatalog = .real) {
      cases.append(IngestCase(name: "check-\(name)", catalog: catalog, action: .check, inputs: inputs))
    }

    check("fixtures", try ["dimmer-plug-2457D2", "example-invented-product", "io-module-2450", "on-off-plug-2635-222", "silent-sensor"].map { try rawFixture($0 + ".json") })
    check("leaks-in-a-note", Self.leaks.map { Self.input(example.note("On the bench next to \($0.1) here.")) })
    check("plain-texts", Self.plainTexts.map { Self.input(example.note($0)) })
    check("a-leak-in-a-detail", [Self.input(example.detail(2, "Answered by 2F.9A.C1."))])
    check("a-leak-in-the-tool-and-catalog-fields", [Self.input(example.put([.key("tool"), .key("version")], .string("10.0.0.7")).put([.key("catalog"), .key("version")], .string("user@example.test")))])
    check("a-serial-number-in-a-note", [Self.input(example.note("Label reads SN12345678 on the back."))])
    check("a-serial-number-outside-a-note", [Self.input(example.detail(0, "Label reads SN12345678 on the back."))])
    check("a-model-name-with-a-catalog-model", [Self.input(dimmer)])
    check("a-model-name-with-an-address-next-to-a-catalog-model", [Self.input(dimmer.device("model", "Dimmer Plug 2457D2 at 2F9AC1"))])
    check("a-model-name-with-a-model-not-in-the-catalog", [Self.input(dimmer.device("model", "Dimmer Plug 2457D3"))])
    check("a-lower-case-model-name", [Self.input(dimmer.device("model", "Dimmer Plug 2457d2"))])
    check("a-leak-in-an-unknown-field", [Self.input(example.put([.key("hubAddress")], .string("2F.9A.C1")))])
    check("a-leak-in-the-model-name", Self.leaks.map { Self.input(example.device("model", "Example \($0.1)")) })
    check("address-shapes-at-the-edges", [
      "2F.9A.C1", "x2F.9A.C1", "2F.9A.C1x", "2F.9A.C1.", "12.34.56.78", "decade", "DECADE", "decade1", "a1b2c3d", "abc123", "ABCDEF", "ABCDEFG",
      "001122", "0x001122", "key 0x00001A", "2F9AC1,", "(2F9AC1)", "a:b:c", "1:2:3:4", "::1", "1::", "fe80::", "::", ":::", "1:2:3:4:5:6:7:8",
      "1:2:3:4:5:6:7:8:9", "a4-5e-60-11-22-33", "a4:5e-60:11:22:33", "1.2.3", "1.2.3.4.5", "1.2.3.4", "999.999.999.999", "v1.2.3.4",
      "1.2.3.4a", "a.b.c.d", "www.example", "example.local", "example.localhost", "example.COM", "name@host", "name@host.x", "a@b.c.d",
      "ftp://x", "mailto:x", "/etc/hosts", "see /etc/hosts now", "(/tmp/x/y)", "=/a/b/", "~/notes", "C:\\x", "c:\\x", "\\\\server\\share",
      "a/b/c", "12/34/56", "ab12cd34", "ab12cd3", "abcdefgh", "ABCDEFGH1", "AB-12-CD-34", "x\n2F.9A.C1", "x\r\n/tmp/a/b/", "\u{00A0}/tmp/a/",
      "caf\u{00E9}.com", "\u{0663}.\u{0663}.\u{0663}.\u{0663}", "\u{FF11}.2.3.4", "2F.9A.C1\u{0301}", "\u{212A}.COM", "x.\u{017F}", "k.com"
    ].map { Self.input(example.note($0)) })
    check("an-address-after-unicode", [Self.input(example.note("caf\u{00E9} \u{1F600} 2F.9A.C1"))])

    check("a-missing-field", [Self.input(io.put([.key("observedOn")], nil))])
    check("a-missing-nested-field", [Self.input(io.put([.key("device"), .key("engine")], nil)), Self.input(io.put([.key("tool"), .key("name")], nil)), Self.input(io.put([.key("checks"), .index(0), .key("detail")], nil))])
    check("a-field-the-format-does-not-have", [Self.input(io.put([.key("hubAddress")], .string("value"))), Self.input(io.put([.key("device"), .key("extra")], .int(1)))])
    check("a-malformed-product-key", ["0xZZZZZZ", "0x00001a", "0x0000001A", "none ", "NONE", "0x1A"].map { Self.input(io.productKey($0)) })
    check("a-malformed-operating-flags", ["2a 00", "2A  00", "2A", "2A 0", "", "2A 00 "].map { Self.input(io.put([.key("operatingFlags"), .key("raw")], .string($0))) })
    check("identity-bytes", [("category", "7"), ("subcategory", "0x7"), ("firmware", "0x3b"), ("category", "0x007"), ("firmware", "41"), ("subcategory", "0xGG")].map { Self.input(io.device($0.0, $0.1)) })
    check("an-engine-the-protocol-lacks", ["i4", "I2", "i2cs", "i3", ""].map { Self.input(io.device("engine", $0)) })
    check("dates", ["2026-13-45", "2026-02-30", "2023-02-29", "2024-02-29", "0000-01-01", "9999-12-31", "2026-00-10", "2026-01-00", "26-01-01", "2026-1-01", "2026-01-15 "].map { Self.input(io.put([.key("observedOn")], .string($0))) })
    check("free-text-length", [
      Self.input(example.note(String(repeating: "a", count: 280))),
      Self.input(example.note(String(repeating: "a", count: 281)).detail(0, String(repeating: "b", count: 201))),
      Self.input(example.detail(0, String(repeating: "b", count: 200))),
      Self.input(example.note(String(repeating: "\u{00E9}", count: 280))),
      Self.input(example.note(String(repeating: "\u{1F600}", count: 281)))
    ])
    check("check-count", [
      Self.input(io.put([.key("checks")], .array([]))),
      Self.input(io.put([.key("checks")], .array(Array(repeating: io.valueAt("checks", 0), count: 16)))),
      Self.input(io.put([.key("checks")], .array(Array(repeating: io.valueAt("checks", 0), count: 17)))),
      Self.input(io.put([.key("checks")], .array(Array(repeating: io.valueAt("checks", 0), count: 20))))
    ])
    check("format", [
      Self.input(io.put([.key("format")], .string("insteon-observation/2"))),
      Self.input(io.put([.key("format")], .string("insteon-observation/12"))),
      Self.input(io.put([.key("format")], .string("insteon-observation/0"))),
      Self.input(io.put([.key("format")], .string("insteon-observation/\u{0663}"))),
      Self.input(io.put([.key("format")], .string("insteon-observation/"))),
      Self.input(io.put([.key("format")], .string("insteon-observation/1 "))),
      Self.input(io.put([.key("format")], .string("insteon-observation/1\n"))),
      Self.input(io.put([.key("format")], .int(1))),
      Self.input(io.put([.key("format")], .null)),
      Self.input(io.put([.key("format")], nil)),
      Self.text(#"{"format": "something-else"}"#),
      Self.text("{}")
    ])
    check("wrong-kinds-of-value", [
      Self.input(io.put([.key("checks")], .string("none"))),
      Self.input(io.put([.key("device")], .array([]))),
      Self.input(io.put([.key("checks"), .index(0), .key("outcome")], .string("maybe"))),
      Self.input(io.put([.key("checks"), .index(0), .key("name")], .int(5))),
      Self.input(io.put([.key("observedOn")], .int(20260115))),
      Self.input(io.put([.key("note")], .int(5))),
      Self.input(io.put([.key("tool")], .null)),
      Self.input(io.put([.key("catalog"), .key("version")], .int(1))),
      Self.input(io.productKey("0x00001A").put([.key("productKey")], .int(26)))
    ])
    check("several-errors-at-once", [
      Self.input(io.put([.key("observedOn")], nil).put([.key("hubAddress")], .int(1)).put([.key("checks"), .index(0), .key("outcome")], .string("maybe")).put([.key("device"), .key("engine")], .int(2)))
    ])
    check("silent-checks-only", [Self.input(try fixture("silent-sensor.json"))])

    check("not-json", [
      Self.text(#"{"format": "insteon-observation/1", 2F9AC1"#), Self.text(""), Self.text("   \n"), Self.text("{"), Self.text("}"), Self.text("nul"),
      Self.text("{\n  \"a\": 1,\n  \"b\": ,\n}"), Self.text("{\"a\": \"caf\u{00E9}\", x}"), Self.text("[1, 2"),
      Self.text("{\"a\": 1} trailing"), Self.text("{\"a\": 1}{\"b\": 2}"), Self.text("{'a': 1}"), Self.text("{\"a\": 01}"), 
      Self.text("{\"a\": \"line\nbreak\"}"), Self.text("{\"a\": \"\\u12\"}"), Self.text("\u{FEFF}{}"),
      Self.text("{\"a\": 1,\r\n\"b\": x}")
    ])
    check("not-an-object", [Self.text("[1, 2]"), Self.text("null"), Self.text("\"text\""), Self.text("5"), Self.text("true"), Self.text("[]"), Self.text("\n\n[{}]")])
    check("not-utf-8", [.bytes([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D]), .bytes([0xC3]), .bytes([0xED, 0xA0, 0x80]), .bytes([0xC0, 0xAF])])
    check("file-size", [
      .bytes(Array(io.bytes) + Array(repeating: 0x20, count: 65536 - io.bytes.count)),
      .bytes(Array(io.bytes) + Array(repeating: 0x20, count: 65537 - io.bytes.count)),
      .bytes(Array(repeating: 0x20, count: 70000))
    ])
    check("a-missing-file", [.missing, .bytes(io.bytes), .missing])
    return cases
  }

  /// Inputs on which the Swift tool differs from the Python tool on purpose. Their goldens are kept apart
  /// from the cases the Swift tool must match.
  public func knownDifferenceCases() throws -> [IngestCase] {
    let io = try fixture("io-module-2450.json")

    func check(_ name: String, _ inputs: [IngestInput]) -> IngestCase {
      IngestCase(name: "check-\(name)", catalog: .real, action: .check, inputs: inputs)
    }

    return [
      check("a-pattern-ends-at-the-end-of-the-text", [
        Self.input(io.put([.key("observedOn")], .string("2026-01-15\n"))),
        Self.input(io.put([.key("productKey")], .string("none\n"))),
        Self.input(io.put([.key("operatingFlags"), .key("raw")], .string("2A 00\n")))
      ]),
      check("json-the-python-reader-accepts", [
        Self.text(##"{"format": "insteon-observation/1", "format": "insteon-observation/1"}"##),
        Self.text(##"{"note": NaN}"##), Self.text(##"{"note": Infinity}"##), Self.text(##"{"note": -Infinity}"##),
        Self.text(##"{"note": "\ud800"}"##), Self.text(##"{"note": 99999999999999999999999999}"##), Self.text(##"{"note": 1e999}"##)
      ]),
      check("json-error-positions", [Self.text("{\"a\":\t1,\t}"), Self.text("{\"a\": 1.}"), Self.text("{\"a\": \"bad \\q escape\"}")])
    ]
  }

  // MARK: draft on the real catalog

  func realDraftCases() throws -> [IngestCase] {
    let names = ["dimmer-plug-2457D2", "io-module-2450", "on-off-plug-2635-222", "silent-sensor"]
    let four = try names.map { try rawFixture($0 + ".json") }
    var cases = [IngestCase(name: "draft-bench-four", catalog: .real, action: .draft(report: true, markdown: true), inputs: four)]

    for (name, input) in zip(names, four) {
      cases.append(IngestCase(name: "draft-\(name)", catalog: .real, action: .draft(report: true, markdown: true), inputs: [input]))
    }

    let example = try rawFixture("example-invented-product.json")
    cases.append(IngestCase(name: "draft-bench-and-the-invented-product", catalog: .real, action: .draft(report: true, markdown: true), inputs: four + [example]))
    cases.append(IngestCase(name: "draft-printed-only", catalog: .real, action: .draft(report: false, markdown: false), inputs: four))
    cases.append(IngestCase(name: "draft-report-file-only", catalog: .real, action: .draft(report: true, markdown: false), inputs: four))
    cases.append(IngestCase(name: "draft-markdown-file-only", catalog: .real, action: .draft(report: false, markdown: true), inputs: four))
    cases.append(IngestCase(name: "draft-the-same-file-twice", catalog: .real, action: .draft(report: true, markdown: true), inputs: [four[1], four[1]]))
    cases.append(IngestCase(name: "draft-a-missing-file", catalog: .real, action: .draft(report: true, markdown: true), inputs: [four[1], .missing]))

    return cases
  }

  // MARK: draft on the invented catalog

  func inventedDraftCases() throws -> [IngestCase] {
    let base = try observation()
    var cases: [IngestCase] = []

    func draft(_ name: String, _ inputs: [ObservationBuilder], report: Bool = true, markdown: Bool = true) {
      cases.append(IngestCase(name: "draft-\(name)", catalog: .invented, action: .draft(report: report, markdown: markdown), inputs: inputs.map(Self.input)))
    }

    draft("an-unmarked-identity", [base])
    draft("an-inferred-note-follows", [try invented("0x01")])
    draft("already-observed-on-this-firmware", [try invented("0x02")])
    draft("a-different-firmware-is-added", [try invented("0x03")])
    draft("a-conflicting-identity", [try invented("0x04")])
    draft("a-device-the-catalog-lacks", [try observation(["category": "0x70"])])
    draft("a-firmware-no-identity-covers", [try invented("0x05")])
    draft("matched-by-the-newer-firmware", [try invented("0x06")])
    draft("matched-by-the-older-firmware", [try invented("0x06", ["firmware": "0x40"])])
    draft("an-identity-two-profiles-claim", [try invented("0x07")])
    draft("another-product-than-the-match", [try observation(["model": "Some Other Product 1234"])])
    draft("the-product-named-by-its-model", [try observation(["model": "Item 9999 of the shelf"])])
    draft("the-product-named-by-its-name", [try observation(["model": "Invented 9999 (Bench Unit)"])])
    draft("no-model-in-the-file", [try observation(["model": nil])])
    draft("a-different-engine", [try observation(["engine": "i2"])])
    draft("an-engine-no-entry-covers", [try invented("0x08")])
    draft("a-profile-without-engine-entries", [try invented("0x09")])
    draft("a-profile-with-an-empty-engine-list", [try invented("0x07", ["firmware": "0x41"])])
    draft("an-engine-the-catalog-gives-as-i2", [try invented("0x0A")])
    draft("an-engine-conflicting", [try invented("0x0D")])
    draft("engine-entries-chosen-by-firmware", [try invented("0x0F"), try invented("0x0F", ["firmware": "0x42", "engine": "i2"])])
    draft("an-engine-answered-silent", [base.outcome(0, "silent")])
    draft("an-engine-refused", [base.outcome(0, "refused")])
    draft("an-engine-not-reported", [try observation(["engine": nil])])
    draft("a-key-equal-to-the-catalogs", [try invented("0x0E")])
    draft("a-key-already-observed", [try invented("0x02")])
    draft("a-different-key", [base.productKey("0x000050")])
    draft("a-key-for-an-identity-without-one", [try invented("0x0B")])
    draft("no-key-against-a-catalog-key", [base.productKey("none")])
    draft("no-key-against-a-catalog-that-says-none", [try invented("0x0C").productKey("none")])
    draft("no-key-against-a-catalog-without-one", [try invented("0x0B").productKey("none")])
    draft("a-silent-key-request", [base.productKey(nil).outcome(2, "silent")])
    draft("a-refused-key-request", [base.productKey(nil).outcome(2, "refused")])
    draft("a-key-without-a-key-request", [base.checks([("Get Insteon Engine Version", "answered"), ("ID Request", "answered")])])
    draft("the-contributors-text-goes-nowhere", [base.note("Zebra pattern marker note.").detail(1, "Zebra pattern marker detail.")])
    draft("a-note-in-the-markdown", [base.note("Bench note for the maintainer.").device("engine", "i2")])
    draft("a-note-with-lines-and-trailing-spaces", [base.note("Line one.\nLine two.  \t")])
    draft("a-note-with-unicode", [base.note("Caf\u{00E9} \u{1F600} bench.")])
    draft("an-empty-note", [base.note("")])
    draft("operating-flags", [try observation().put([.key("operatingFlags")], .object([JSONMember(key: "raw", value: .string("2A 00"))]))])
    draft("a-check-this-tool-does-not-read", [base.checks([("Get Insteon Engine Version", "answered"), ("ID Request", "answered"), ("Product Data Request", "answered"), ("Ping", "answered")])])
    draft("a-check-this-tool-does-not-read-that-is-silent", [base.checks([("ID Request", "answered"), ("Ping", "silent"), ("Status Request", "silent")])])
    draft("a-repeated-check-first-outcome-wins", [base.checks([("ID Request", "silent"), ("ID Request", "answered"), ("Get Insteon Engine Version", "answered"), ("Get Insteon Engine Version", "silent")])])
    draft("repeated-skipped-checks", [base.checks([("ID Request", "answered"), ("Status Request", "silent"), ("Status Request", "refused"), ("Status Request", "silent")])])
    draft("the-identity-was-not-reported", [base.device("category", nil).device("subcategory", nil).device("firmware", nil)])
    draft("the-identity-is-partly-reported", [base.device("firmware", nil)])
    draft("an-engine-answered-but-no-identity", [base.checks([("Get Insteon Engine Version", "answered"), ("ID Request", "silent")])])
    draft("nothing-answered", [base.checks([("Get Insteon Engine Version", "silent"), ("ID Request", "refused")])])
    draft("no-checks", [base.put([.key("checks")], .array([]))])
    draft("the-same-observation-twice", [base, base])
    draft("two-firmware-versions-in-order", [try invented("0x03", ["firmware": "0x41"]), try invented("0x03", ["firmware": "0x42"]), try invented("0x03", ["firmware": "0x3B"])])
    draft("a-second-observation-sees-the-first", [try invented("0x0E"), try invented("0x0E", ["firmware": "0x42"])])
    draft("a-rejected-file-and-a-drafted-one", [base.note("Next to 2F.9A.C1."), base])
    draft("a-rejected-file-with-several-errors", [base.put([.key("hubAddress")], .string("2F.9A.C1")).note("At 192.168.7.20 or a@b.example")])
    draft("a-disagreement-and-a-drafted-one", [try observation(["category": "0x70"]), base])
    draft("a-disagreement-and-a-rejected-one", [try observation(["category": "0x70"]), base.note("Next to 2F.9A.C1.")])
    draft("a-rejected-file-after-a-drafted-one", [base, base.put([.key("format")], .string("other"))])
    draft("no-change-and-a-disagreement", [try invented("0x02"), try observation(["category": "0x70"])])
    draft("a-product-without-a-name-line", [try invented("0x10")])
    draft("a-product-reporting-no-key-and-the-catalog-too", [try invented("0x10").productKey("none")])
    draft("printed-only-with-a-disagreement", [try observation(["category": "0x70"])], report: false, markdown: false)
    draft("report-file-only-with-a-rejection", [base.note("Next to 2F.9A.C1.")], report: true, markdown: false)

    return cases
  }
}

extension ObservationBuilder {
  /// The element of the array under `key`.
  func valueAt(_ key: String, _ index: Int) -> JSONValue {
    guard case .object(let members) = value, case .array(let elements)? = members.first(where: { $0.key == key })?.value else { return .null }

    return elements[index]
  }
}
