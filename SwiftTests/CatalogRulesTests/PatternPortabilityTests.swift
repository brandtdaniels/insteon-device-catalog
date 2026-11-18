import CatalogJSON
import CatalogRules
import Testing

/// Where ICU's `\w` and `\b` differ from Python's, and how the rules' patterns settle it. Each
/// expectation is what Python's `re` finds for the same text. The lookbehind cases are the second,
/// eighth and eleventh ruled-out terms.
struct PatternPortabilityTests {
  static func reports(_ text: String) -> Bool {
    let data = JSONValue.object([JSONMember(key: "description", value: .string(text))])

    return !TermRules.problems(label: "L", in: data).isEmpty
  }

  /// `\bINSTEON\b` around characters that are word characters to one engine and not the other.
  static let wordBoundaries: [(String, Bool)] = [
    ("INSTEON\u{301}", true),
    ("a\u{301}INSTEON", true),
    ("INSTEON\u{200D}", true),
    ("\u{203F}INSTEON", true),
    ("\u{24B6}INSTEON", true),
    ("\u{1F600}INSTEON", true),
    ("\u{B2}INSTEON", false),
    ("INSTEON\u{BD}", false),
    ("\u{2167}INSTEON", false),
    ("\u{4E00}INSTEON", false),
    ("\u{663}INSTEON", false),
    ("INSTEON\u{663}", false),
    ("\u{E9}INSTEON", false),
    ("INSTEON_", false),
    ("_INSTEON", false),
    ("1INSTEON", false),
    ("\u{1D7D8}INSTEON", false)
  ]

  @Test(arguments: wordBoundaries)
  func aWordBoundaryIsWhereAWordCharacterMeetsAnythingElse(text: String, reported: Bool) {
    #expect(Self.reports(text) == reported, "\(text.unicodeScalars.map(\.value))")
  }

  /// `(?<![.\w])[iI]2cs\b`: the lookbehind takes a dot or a word character, including a character
  /// outside the Basic Multilingual Plane.
  static let lookbehinds: [(String, Bool)] = [
    ("x i2cs", true),
    ("x\u{1F600}i2cs", true),
    ("\u{1D7D8} i2cs", true),
    ("\u{1D7D8}i2cs", false),
    ("\u{1D41}i2cs", false),
    ("\u{301}i2cs", true),
    ("\u{B2}i2cs", false),
    ("\u{203F}i2cs", true),
    ("a.i2cs", false),
    ("a-i2cs", true),
    ("i2cs", true)
  ]

  @Test(arguments: lookbehinds)
  func aLookbehindReadsTheCharacterBeforeTheMatch(text: String, reported: Bool) {
    #expect(Self.reports(text) == reported, "\(text.unicodeScalars.map(\.value))")
  }

  @Test func theLookbehindOfTheLinkDatabaseTermReadsFourCharacters() {
    #expect(Self.reports("ALL-Link database") == false)
    #expect(Self.reports("ALL-link database") == false)
    #expect(Self.reports("\u{1F600}ALL-Link database") == false)
    #expect(Self.reports("ALL\u{1F600}Link database") == true)
    #expect(Self.reports("link database") == true)
  }

  @Test func theThreeLookbehindsOfTheGuideTermEachBlockTheirWord() {
    #expect(Self.reports("Insteon Developer's Guide") == false)
    #expect(Self.reports("Modem Developer's Guide") == false)
    #expect(Self.reports("Hub Developer's Guide") == false)
    #expect(Self.reports("Insteon\u{A0}Developer's Guide") == true)
    #expect(Self.reports("Hubs Developer's Guide") == true)
    #expect(Self.reports("Developer's Guide") == true)
  }
}
