import Testing

@testable import CatalogSite

/// The small formatting helpers the page's wording uses.
struct PageTextTests {
  @Test(arguments: [
    (0, "0 minutes"), (1, "1 minute"), (2, "2 minutes"), (60, "60 minutes")
  ])
  func countNounAgreesWithTheCount(count: Int, expected: String) {
    #expect(PageText.countNoun(count, "minute") == expected)
  }

  @Test func countNounTakesAnExplicitPlural() {
    #expect(PageText.countNoun(1, "child", plural: "children") == "1 child")
    #expect(PageText.countNoun(2, "child", plural: "children") == "2 children")
  }

  @Test(arguments: [("0x01", 1), ("0x04", 4), ("0x0A", 10), ("0xFF", 255), ("0x2E", 46), ("0x00", 0)])
  func groupNumbersReadHexadecimalBytes(text: String, expected: Int) {
    #expect(PageText.number(ofHex: text) == expected)
  }

  @Test(arguments: [("observed", "Observed"), ("documented", "Documented"), ("conflicting", "Conflicting"), ("iNFERRED", "Inferred"), ("", "")])
  func capitalizesTheFirstLetterAndLowersTheRest(text: String, expected: String) {
    #expect(PageText.capitalized(text) == expected)
  }

  @Test func plainStatusWordsAreCapitalizedAsTheStatusPillsShowThem() {
    #expect(PageTables.statuses.map(PageText.capitalized) == ["Observed", "Documented", "Inferred", "Conflicting"])
  }
}
