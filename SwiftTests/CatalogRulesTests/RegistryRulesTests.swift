import CatalogJSON
import CatalogRules
import Testing

/// The registry's shape and entries. Ports the registry tests of the Python `DocumentRegistryTests`,
/// and checks the messages the Python build printed for the same input.
struct RegistryRulesTests {
  // DocumentRegistryTests.test_a_valid_registry_has_no_problems
  @Test func aValidRegistryHasNoProblems() {
    let registry = Registry.with(
      Registry.document(),
      Registry.document("Insteon Developer's Guide (2009)", "developersGuide", optional: ["edition": "2009"]),
      Registry.document("Hub 2242 Quick Start Guide", "quickStart", optional: ["url": "https://cache.insteon.com/documentation/2242-qsg.pdf"])
    )

    #expect(RegistryRules.problems(in: registry) == [])
  }

  // DocumentRegistryTests.test_a_duplicate_title_fails
  @Test func aDuplicateTitleFails() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document(), Registry.document("Leak Sensor Developer Notes", "other")))

    #expect(found == ["registry.json: title 'Leak Sensor Developer Notes' appears more than once"])
  }

  /// The inputs of the Python test `test_a_malformed_entry_fails`, each with the line the Python
  /// build printed.
  static let malformed: [(String, [String])] = [
    (#"{"documents": "not a list"}"#, [#"registry.json: must be an object with only a "documents" list"#]),
    (#"{"documents": ["a string"]}"#, ["registry.json: entry 0 must be an object"]),
    (#"{"documents": [{"kind": "other"}]}"#, ["registry.json: entry 0: title must be a non-empty string"]),
    (#"{"documents": [{"title": "No Kind"}]}"#, ["registry.json: entry 0 ('No Kind'): kind must be a non-empty string"]),
    (#"{"documents": [{"title": "", "kind": "developerNotes"}]}"#, ["registry.json: entry 0 (''): title must be a non-empty string"]),
    (#"{"documents": [{"title": "Leak Sensor Developer Notes", "kind": "notAKind"}]}"#, [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): kind 'notAKind' is not one of \(Registry.kindList)"
    ]),
    (#"{"documents": [{"title": "Leak Sensor Developer Notes", "kind": "developerNotes", "edition": ""}]}"#, [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): edition must be a non-empty string"
    ]),
    (#"{"documents": [{"title": "Leak Sensor Developer Notes", "kind": "developerNotes", "url": "http://cache.insteon.com/a.pdf"}]}"#, [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): url must be an https URL"
    ]),
    (#"{"documents": [{"title": "Leak Sensor Developer Notes", "kind": "developerNotes", "url": "not a url"}]}"#, [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): url must be an https URL"
    ]),
    (#"{"documents": [{"title": "Leak Sensor Developer Notes", "kind": "developerNotes", "unknown": "field"}]}"#, [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): unknown field 'unknown'"
    ]),
    (#"{"documents": [], "extra": 1}"#, [#"registry.json: must be an object with only a "documents" list"#]),
    (#"["not an object"]"#, [#"registry.json: must be an object with only a "documents" list"#])
  ]

  // DocumentRegistryTests.test_a_malformed_entry_fails
  @Test(arguments: Self.malformed)
  func aMalformedEntryFails(registry: String, expected: [String]) throws {
    #expect(RegistryRules.problems(in: try JSONParser.parse(registry)) == expected)
  }

  @Test func anEntryWithValuesOfTheWrongTypeReportsEachField() throws {
    let registry = try JSONParser.parse(#"{"documents": [{"title": 5, "kind": 7, "edition": 3, "url": 4}]}"#)

    #expect(RegistryRules.problems(in: registry) == [
      "registry.json: entry 0: title must be a non-empty string",
      "registry.json: entry 0: kind must be a non-empty string",
      "registry.json: entry 0: edition must be a non-empty string",
      "registry.json: entry 0: url must be an https URL"
    ])
  }

  @Test func aBlankTitleAndKindAreEmpty() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document("  ", " ")))

    #expect(found == [
      "registry.json: entry 0 ('  '): title must be a non-empty string",
      "registry.json: entry 0 ('  '): kind must be a non-empty string",
      "registry.json: entry 0 ('  '): kind ' ' is not one of \(Registry.kindList)"
    ])
  }

  @Test func unknownFieldsAreReportedInCodePointOrder() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document(optional: ["zeta": 1, "alpha": 2])))

    #expect(found == [
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): unknown field 'alpha'",
      "registry.json: entry 0 ('Leak Sensor Developer Notes'): unknown field 'zeta'"
    ])
  }

  // DocumentRegistryTests.test_a_dash_in_any_field_fails
  @Test(arguments: [
    ("Leak Sensor \u{2014} Developer Notes", "developerNotes", "title"),
    ("Leak Sensor \u{2013} Developer Notes", "developerNotes", "title"),
    ("Leak Sensor Developer Notes", "developerNotes", "edition")
  ])
  func aDashInAnyFieldFails(title: String, kind: String, field: String) {
    let entry = field == "edition"
      ? Registry.document(title, kind, optional: ["edition": "2009 \u{2013} 2010"])
      : Registry.document(title, kind)
    let found = RegistryRules.problems(in: Registry.with(entry))

    #expect(found == ["registry.json: entry 0 (\(pythonQuoted(title))): \(field) has a dash; rewrite it with a comma, colon or hyphen"])
  }

  @Test func aDashInTheKindIsReportedAfterTheKindIsNotOneOfTheKinds() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document("x\u{2014}y", "\u{2013}")))

    #expect(found == [
      "registry.json: entry 0 ('x\u{2014}y'): kind '\u{2013}' is not one of \(Registry.kindList)",
      "registry.json: entry 0 ('x\u{2014}y'): title has a dash; rewrite it with a comma, colon or hyphen",
      "registry.json: entry 0 ('x\u{2014}y'): kind has a dash; rewrite it with a comma, colon or hyphen"
    ])
  }

  // DocumentRegistryTests.test_a_ruled_out_term_in_a_title_fails
  @Test func aRuledOutTermInATitleFails() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document("INSTEON Leak Sensor Developer Notes")))

    #expect(found == ["registry.json: entry 0 ('INSTEON Leak Sensor Developer Notes'): 'INSTEON' in sources; use Insteon"])
  }

  @Test func aTitleWithAnApostropheIsQuotedTheWayPythonQuotesIt() {
    #expect(RegistryRules.problems(in: Registry.with(Registry.document("it's"))) == [])
    #expect(RegistryRules.problems(in: Registry.with(Registry.document("it's", "nope"))) == [
      "registry.json: entry 0 (\"it's\"): kind 'nope' is not one of \(Registry.kindList)"
    ])
  }

  /// The positives and negatives of `https://[^\s/]+(/\S*)?`, matched against the whole value.
  @Test(arguments: [
    ("https://cache.insteon.com", true),
    ("https://cache.insteon.com/", true),
    ("https://cache.insteon.com/documentation/2242-qsg.pdf", true),
    ("https://a/b?c=d#e", true),
    ("http://cache.insteon.com", false),
    ("https://", false),
    ("https:///path", false),
    ("https://a b", false),
    ("https://a/b c", false),
    ("https://a\u{1C}b", false),
    ("https://a\u{85}b", false),
    ("https://a\u{A0}b", false),
    ("https://a\n", false),
    ("https://a/b\n", false),
    (" https://a", false),
    ("xhttps://a", false),
    ("HTTPS://a", false),
    ("https://a/b\u{2028}c", false)
  ])
  func anHTTPSURLIsTheWholeValue(url: String, accepted: Bool) {
    let found = RegistryRules.problems(in: Registry.with(Registry.document(optional: ["url": .string(url)])))

    #expect(found.isEmpty == accepted, "\(url.debugDescription)")
  }

  @Test(arguments: [" ", "\t", "\u{1C}", "\u{85}", "\u{A0}", "\u{2003}", "\u{3000}"])
  func aTitleOfOnlyWhitespaceIsEmptyAsPythonStripsIt(blank: String) {
    let found = RegistryRules.problems(in: Registry.with(Registry.document(blank)))

    #expect(found.contains { $0.hasSuffix("title must be a non-empty string") }, "\(blank.debugDescription)")
  }

  @Test(arguments: ["\u{200B}", "\u{FEFF}", "a"])
  func aTitleWithAnyOtherCharacterIsNotEmpty(text: String) {
    let found = RegistryRules.problems(in: Registry.with(Registry.document(text)))

    #expect(!found.contains { $0.hasSuffix("title must be a non-empty string") }, "\(text.debugDescription)")
  }

  @Test func titlesThatDifferOnlyInCanonicalFormAreDifferentTitles() {
    let found = RegistryRules.problems(in: Registry.with(Registry.document("Caf\u{E9}"), Registry.document("Cafe\u{301}")))

    #expect(found == [])
  }
}

/// A string in the quotes Python's `repr` picks, for the strings these tests use.
private func pythonQuoted(_ text: String) -> String {
  text.contains("'") && !text.contains("\"") ? "\"\(text)\"" : "'\(text)'"
}
