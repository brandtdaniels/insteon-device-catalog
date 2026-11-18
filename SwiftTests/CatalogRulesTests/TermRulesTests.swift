import CatalogJSON
import CatalogRules
import Testing

/// The ruled-out terms. The Python build has no test of its own for them beyond the registry title
/// case, so every one of the eleven patterns gets positive and negative cases, with the matches
/// the Python `re` module finds for the same text.
struct TermRulesTests {
  /// What a string in `key` reports: the text each pattern matched, with what to write instead.
  static func found(in text: String, key: String = "description") -> [String] {
    let data = JSONValue.object([JSONMember(key: key, value: .string(text))])

    return TermRules.problems(label: "L", in: data)
  }

  static func line(_ match: String, _ replacement: String, key: String = "description") -> String {
    let quoted = match.contains("'") ? "\"\(match)\"" : "'\(match)'"

    return "L: \(quoted) in \(key); use \(replacement)"
  }

  // The first pattern: INSTEON in capitals.
  static let capitalInsteonIsRuledOutCases: [(String, [String])] = [
    ("INSTEON", ["INSTEON"]),
    ("the INSTEON hub", ["INSTEON"]),
    ("INSTEON-compatible", ["INSTEON"]),
    ("(INSTEON)", ["INSTEON"]),
    ("INSTEONS", []),
    ("xINSTEON", []),
    ("INSTEON_x", []),
    ("INSTEON2", []),
    ("Insteon", []),
    ("insteon", [])
  ]

  @Test(arguments: Self.capitalInsteonIsRuledOutCases)
  func capitalInsteonIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "Insteon") })
  }

  // The second pattern: i2cs without the CS capitals, not after a dot or a word character; or I2CS.
  static let i2csInTheWrongFormIsRuledOutCases: [(String, [String])] = [
    ("i2cs", ["i2cs"]),
    ("I2cs", ["I2cs"]),
    ("I2CS", ["I2CS"]),
    ("an i2cs device", ["i2cs"]),
    ("-i2cs", ["i2cs"]),
    ("(i2cs)", ["i2cs"]),
    (" i2cs.", ["i2cs"]),
    (".I2CS", ["I2CS"]),
    ("engine.i2cs", []),
    (".i2cs", []),
    ("ai2cs", []),
    ("_i2cs", []),
    ("9i2cs", []),
    ("\u{E9}i2cs", []),
    ("i2csx", []),
    ("i2cs_", []),
    ("i2CS", []),
    ("i2c", []),
    ("I2CSx", [])
  ]

  @Test(arguments: Self.i2csInTheWrongFormIsRuledOutCases)
  func i2csInTheWrongFormIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "i2CS") })
  }

  // The third pattern: acknowledgement with an e.
  static let acknowledgementIsRuledOutCases: [(String, [String])] = [
    ("Acknowledgement", ["Acknowledgement"]),
    ("an acknowledgement", ["acknowledgement"]),
    ("acknowledgements", ["acknowledgement"]),
    ("acknowledgment", []),
    ("unacknowledgement", []),
    ("ACKNOWLEDGEMENT", [])
  ]

  @Test(arguments: Self.acknowledgementIsRuledOutCases)
  func acknowledgementIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "acknowledgment") })
  }

  // The fourth pattern: power line as two words.
  static let powerLineAsTwoWordsIsRuledOutCases: [(String, [String])] = [
    ("Power line", ["Power line"]),
    ("the power line", ["power line"]),
    ("power lines", ["power line"]),
    ("powerline", []),
    ("Power Line", []),
    ("superpower line", []),
    ("power  line", [])
  ]

  @Test(arguments: Self.powerLineAsTwoWordsIsRuledOutCases)
  func powerLineAsTwoWordsIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "powerline") })
  }

  // The fifth pattern: on level without the hyphen.
  static let onLevelWithoutAHyphenIsRuledOutCases: [(String, [String])] = [
    ("on level", ["on level"]),
    ("the on level.", ["on level"]),
    ("on level,", ["on level"]),
    ("on-level", []),
    ("on levels", []),
    ("con level", []),
    ("on Level", [])
  ]

  @Test(arguments: Self.onLevelWithoutAHyphenIsRuledOutCases)
  func onLevelWithoutAHyphenIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "on-level") })
  }

  // The sixth pattern: a hub's number before its name.
  static let aHubNumberBeforeItsNameIsRuledOutCases: [(String, [String])] = [
    ("2242 Hub", ["2242 Hub"]),
    ("2245 Hub", ["2245 Hub"]),
    ("the 2245 Hub.", ["2245 Hub"]),
    ("Hub 2242", []),
    ("2242 Hubs", []),
    ("22420 Hub", []),
    ("12242 Hub", []),
    ("2243 Hub", []),
    ("2242 hub", [])
  ]

  @Test(arguments: Self.aHubNumberBeforeItsNameIsRuledOutCases)
  func aHubNumberBeforeItsNameIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "Hub 2242, Hub 2245") })
  }

  // The seventh pattern: All-Link in the wrong case.
  static let allLinkInTheWrongCaseIsRuledOutCases: [(String, [String])] = [
    ("All-Link", ["All-Link"]),
    ("all-link", ["all-link"]),
    ("an all-link group", ["all-link"]),
    ("All-Linking", ["All-Link"]),
    ("ALL-Link", []),
    ("ALL-LINK", []),
    ("Xall-link", []),
    ("overall-link", []),
    ("Small-Link", []),
    ("all link", [])
  ]

  @Test(arguments: Self.allLinkInTheWrongCaseIsRuledOutCases)
  func allLinkInTheWrongCaseIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "ALL-Link") })
  }

  // The eighth pattern: link database that is not part of ALL-Link database (a lookbehind).
  static let aLinkDatabaseNotPartOfAllLinkDatabaseIsRuledOutCases: [(String, [String])] = [
    ("Link database", ["Link database"]),
    ("link database", ["link database"]),
    ("the Insteon link database", ["link database"]),
    ("All-Link database", ["Link database"]),
    ("all-link database", ["link database"]),
    ("ALL-Link database", []),
    ("ALL-link database", []),
    ("XALL-Link database", []),
    ("linked database", []),
    ("Link databases", ["Link database"]),
    ("Xlink database", [])
  ]

  @Test(arguments: Self.aLinkDatabaseNotPartOfAllLinkDatabaseIsRuledOutCases)
  func aLinkDatabaseNotPartOfAllLinkDatabaseIsRuledOut(text: String, matches: [String]) {
    // `All-Link database` and `all-link database` also carry the seventh pattern's match.
    let seventh = ["All-Link database": "All-Link", "all-link database": "all-link"][text]
    let expected = (seventh.map { [Self.line($0, "ALL-Link")] } ?? []) + matches.map { Self.line($0, "ALL-Link database") }

    #expect(Self.found(in: text) == expected)
  }

  // The ninth pattern: clean-up with a hyphen.
  static let cleanUpWithAHyphenIsRuledOutCases: [(String, [String])] = [
    ("clean-up", ["clean-up"]),
    ("a clean-up step", ["clean-up"]),
    ("clean-ups", ["clean-up"]),
    ("Clean-up", []),
    ("cleanup", []),
    ("unclean-up", []),
    ("clean up", [])
  ]

  @Test(arguments: Self.cleanUpWithAHyphenIsRuledOutCases)
  func cleanUpWithAHyphenIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "cleanup") })
  }

  // The tenth pattern: Set button instead of SET button.
  static let aSetButtonInTheWrongCaseIsRuledOutCases: [(String, [String])] = [
    ("Set button", ["Set button"]),
    ("set button", ["set button"]),
    ("press the set button.", ["set button"]),
    ("SET button", []),
    ("Set buttons", []),
    ("reset button", []),
    ("Set Button", [])
  ]

  @Test(arguments: Self.aSetButtonInTheWrongCaseIsRuledOutCases)
  func aSetButtonInTheWrongCaseIsRuledOut(text: String, matches: [String]) {
    #expect(Self.found(in: text) == matches.map { Self.line($0, "SET button") })
  }

  // The eleventh pattern: a developer's guide not preceded by Insteon, Modem or Hub (three
  // lookbehinds); or the guide.
  static let aGuideNamedWithoutItsTitleIsRuledOutCases: [(String, [String])] = [
    ("Developer's Guide", ["Developer's Guide"]),
    ("the Developer's Guide", ["Developer's Guide"]),
    ("developer guides", ["developer guides"]),
    ("Developers Guide", ["Developers Guide"]),
    ("Developer Guide", ["Developer Guide"]),
    ("developer's guide", ["developer's guide"]),
    ("Insteon  Developer's Guide", ["Developer's Guide"]),
    ("insteon Developer's Guide", ["Developer's Guide"]),
    ("Insteon Developer's Guide", []),
    ("Modem Developer's Guide", []),
    ("Hub Developer's Guide", []),
    ("Insteon Modem Developer's Guide", []),
    ("Insteon Hub Developer's Guide", []),
    ("Leak Sensor Developer Notes", []),
    ("Developer's Guides", ["Developer's Guides"]),
    ("Developer's Guidebook", []),
    ("the guide", ["the guide"]),
    ("The guide", ["The guide"]),
    ("The guides", []),
    ("the Guide", []),
    ("breathe guide", []),
    ("Insteon The guide", ["The guide"])
  ]

  @Test(arguments: Self.aGuideNamedWithoutItsTitleIsRuledOutCases)
  func aGuideNamedWithoutItsTitleIsRuledOut(text: String, matches: [String]) {
    let replacement = "the document's title, such as Leak Sensor Developer Notes or Insteon Developer's Guide"

    #expect(Self.found(in: text) == matches.map { Self.line($0, replacement) })
  }

  @Test func eachPatternReportsOnceAndInPatternOrder() {
    #expect(Self.found(in: "set button, INSTEON and INSTEON, power line") == [
      Self.line("INSTEON", "Insteon"),
      Self.line("power line", "powerline"),
      Self.line("set button", "SET button")
    ])
  }

  @Test func textInBackticksIsLeftOut() {
    #expect(Self.found(in: "the `INSTEON` field and `a`b`") == [])
    #expect(Self.found(in: "`x` INSTEON `y`") == [Self.line("INSTEON", "Insteon")])
    #expect(Self.found(in: "an unclosed `INSTEON") == [Self.line("INSTEON", "Insteon")])
  }

  @Test func theBackticksComeOutBeforeTheMatch() {
    // Removing the span joins its neighbors, so a term can form across it, as it does in Python.
    #expect(Self.found(in: "INS`x`TEON") == [Self.line("INSTEON", "Insteon")])
  }

  @Test(arguments: ["description", "note", "notes", "sources", "label", "section", "text", "expect"])
  func theProseKeysAreChecked(key: String) {
    #expect(Self.found(in: "INSTEON", key: key) == [Self.line("INSTEON", "Insteon", key: key)])
  }

  @Test(arguments: ["title", "id", "kind", "model", "other", "Description"])
  func otherKeysAreNotChecked(key: String) {
    #expect(Self.found(in: "INSTEON", key: key) == [])
  }

  @Test func aNameIsCheckedOnlyWhenItHasASpace() {
    #expect(Self.found(in: "INSTEON", key: "name") == [])
    #expect(Self.found(in: "INSTEON Dimmer", key: "name") == [Self.line("INSTEON", "Insteon", key: "name")])
  }

  @Test func theWalkReadsNestedObjectsAndListsInOrder() throws {
    let data = try JSONParser.parse(#"""
    {"name": "Hub 2242 plain", "sources": ["INSTEON x"], "description": "INSTEON and `INSTEON` and Power line",
     "n": {"note": ["all-link", "All-Link database"], "name": "oneword INSTEON"}}
    """#)

    #expect(TermRules.problems(label: "L", in: data) == [
      "L: 'INSTEON' in sources; use Insteon",
      "L: 'INSTEON' in description; use Insteon",
      "L: 'Power line' in description; use powerline",
      "L: 'all-link' in note; use ALL-Link",
      "L: 'All-Link' in note; use ALL-Link",
      "L: 'Link database' in note; use ALL-Link database",
      "L: 'INSTEON' in name; use Insteon"
    ])
  }

  @Test func aListKeepsTheKeyOfItsParent() throws {
    let data = try JSONParser.parse(#"{"notes": [["INSTEON"], [["INSTEON"]]], "other": ["INSTEON"]}"#)

    #expect(TermRules.problems(label: "L", in: data) == [
      "L: 'INSTEON' in notes; use Insteon",
      "L: 'INSTEON' in notes; use Insteon"
    ])
  }

  @Test func valuesThatAreNotStringsAreSkipped() throws {
    let data = try JSONParser.parse(#"{"description": 5, "note": null, "text": ["INSTEON", 1, true]}"#)

    #expect(TermRules.problems(label: "L", in: data) == ["L: 'INSTEON' in text; use Insteon"])
  }
}
