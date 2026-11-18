import CatalogBuild
import CatalogSite
import CatalogSweep
import Foundation
import Testing

/// The byte comparison and the fragment-by-fragment comparison of two landing pages.
struct PageComparisonTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  static let root = RepositoryRoot(url: repository)
  static let input: SiteInput = try! root.siteInput(patch: 0)
  static let fragments: PageFragments = try! SitePage.fragments(input)
  static let page = try! SitePage.render(input, template: root.pageTemplate())

  @Test func samePagesHaveNoDifference() {
    #expect(PageComparison.firstDifference(swift: "<p>a</p>", python: "<p>a</p>") == nil)
    #expect(PageComparison.firstDifference(swift: "", python: "") == nil)
  }

  @Test func theFirstDifferingByteIsReportedWithItsContext() throws {
    let difference = try #require(PageComparison.firstDifference(swift: "<p>abXd</p>", python: "<p>abcd</p>"))

    #expect(difference.offset == 5)
    #expect(difference.swiftExcerpt == "<p>ab[HERE]Xd</p>")
    #expect(difference.pythonExcerpt == "<p>ab[HERE]cd</p>")
  }

  @Test func aPageThatIsAPrefixOfTheOtherDiffersAtItsEnd() throws {
    let difference = try #require(PageComparison.firstDifference(swift: "abc", python: "abcdef"))

    #expect(difference.offset == 3)
    #expect(difference.swiftExcerpt == "abc[HERE]")
    #expect(difference.pythonExcerpt == "abc[HERE]def")
  }

  @Test func offsetsCountBytesNotCharacters() throws {
    let difference = try #require(PageComparison.firstDifference(swift: "caf\u{E9}X", python: "caf\u{E9}Y"))

    #expect(difference.offset == 5)
  }

  @Test func textThatLooksTheSameButIsEncodedDifferentlyDiffers() throws {
    let difference = try #require(PageComparison.firstDifference(swift: "caf\u{E9}", python: "cafe\u{301}"))

    #expect(difference.offset == 3)
  }

  @Test func lineEndsAndTabsInAnExcerptAreWrittenOut() throws {
    let difference = try #require(PageComparison.firstDifference(swift: "a\n\tb", python: "a\n\tc"))

    #expect(difference.swiftExcerpt == "a\\n\\t[HERE]b")
  }

  @Test func anExcerptShowsAtMostSixtyBytesOnEachSide() throws {
    let long = String(repeating: "x", count: 200)
    let difference = try #require(PageComparison.firstDifference(swift: long + "A" + long, python: long + "B" + long))

    #expect(difference.offset == 200)
    #expect(difference.swiftExcerpt == String(repeating: "x", count: 60) + "[HERE]A" + String(repeating: "x", count: 59))
  }

  @Test func aPageComparedWithItselfAgreesInEveryFragment() {
    let results = FragmentComparison.compare(swift: Self.fragments, pythonPage: Self.page)

    #expect(results.map(\.name) == [
      "coverage summary", "legend", "how section", "category options", "capability options", "engine options", "verification options",
      "category sections", "cards"
    ])
    #expect(results.allSatisfy { $0.agrees })
    #expect(results.last?.total == 151)
    #expect(results.last?.identical == 151)
    #expect(results.first { $0.name == "category sections" }?.total == 11)
  }

  @Test func oneChangedCardIsTheOnlyFragmentThatDisagrees() throws {
    let changed = Self.page.replacingOccurrences(of: #"<span class="model mono">2242</span>"#, with: #"<span class="model mono">2242X</span>"#)

    #expect(changed != Self.page)

    let results = FragmentComparison.compare(swift: Self.fragments, pythonPage: changed)
    let cards = try #require(results.first { $0.name == "cards" })

    #expect(cards.identical == 150)
    #expect(cards.total == 151)
    let difference = try #require(cards.firstDifference)
    #expect(difference.pythonExcerpt.contains("2242[HERE]X"))
    #expect(results.filter { !$0.agrees }.map(\.name) == ["cards"])
  }

  @Test func aChangedLegendSentenceIsFoundInTheLegendOnly() {
    let changed = Self.page.replacingOccurrences(of: "Switches a load on and off.", with: "Switches a load on or off.")
    let results = FragmentComparison.compare(swift: Self.fragments, pythonPage: changed)

    #expect(results.filter { !$0.agrees }.map(\.name) == ["legend"])
  }

  @Test func aMissingCardIsReported() throws {
    let start = try #require(Self.page.range(of: #"<article class="card" data-model="2413U""#))
    let end = try #require(Self.page[start.upperBound...].range(of: "</article>"))
    var changed = Self.page
    changed.removeSubrange(start.lowerBound..<end.upperBound)

    let cards = try #require(FragmentComparison.compare(swift: Self.fragments, pythonPage: changed).first { $0.name == "cards" })

    #expect(cards.total == 150)
    #expect(cards.identical == 150)
    #expect(!cards.agrees)
  }
}
