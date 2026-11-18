import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// What the whole page says and how it is built.
struct PageContentTests {
  static let page = CatalogPage.page
  static let reader = CatalogPage.reader
  static let temporalWords = #"\b(now|currently|latest|recent|recently|soon|today|yet|still|new|newly|later|upcoming)\b"#

  static func hasDash(_ text: String) -> Bool {
    text.unicodeScalars.contains { $0.value == 0x2013 || $0.value == 0x2014 }
  }

  @Test func summaryNumbersAreTheCatalogs() throws {
    let coverage = try CoverageSummary(profiles: CatalogPage.profiles, commandSets: CatalogPage.commandSets)
    let metrics = Self.reader.metrics.compactMapValues { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

    #expect(metrics["profiles"] == coverage.profiles)
    #expect(metrics["identities"] == coverage.identities)
    #expect(metrics["described"] == coverage.described)
    #expect(metrics["deliberatelyEmpty"] == coverage.deliberatelyEmpty)
    #expect(metrics["undescribed"] == coverage.undescribed)

    for status in PageTables.statuses {
      #expect(metrics["commandSet-\(status)"] == coverage.commandSetStatuses[status])
      #expect(metrics["identity-\(status)"] == coverage.identityStatuses[status])
    }
  }

  @Test func explainsEachStatusInOneSentence() {
    for status in PageTables.statuses {
      let sentence = PageTables.statusExplanations[status] ?? ""

      #expect(Self.page.contains(HTMLEscaper.escape(sentence)))
      #expect(sentence.filter { $0 == "." }.count == 1)
    }
  }

  @Test func aCardNamesTheStatusesItsOwnValuesCarry() throws {
    let profile = json(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [
      {"category": "0x01", "subcategory": "0x01", "verification": {"status": "observed", "note": "n"}},
      {"category": "0x01", "subcategory": "0x02", "verification": {"status": "inferred", "note": "n"}}]}
    """#)
    let plain = json(#"{"model": "8", "name": "M", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x03"}]}"#)

    let page = try CatalogPage.render([profile, plain], [])
    let cards = Array(page.components(separatedBy: #"<article class="card""#).dropFirst())

    #expect(cards.count == 2)
    #expect(cards[1].contains(#"data-verification="observed inferred""#))
    #expect(cards[1].contains(#"class="status pill status-observed""#))
    #expect(cards[1].contains(#"class="status pill status-inferred""#))
    #expect(!cards[1].contains("status-conflicting"))
    #expect(cards[0].contains(#"data-verification="""#))
    #expect(!cards[0].contains(#"class="status"#))
  }

  @Test func pageHasLandmarksAndOrderedHeadings() {
    let levels = Self.reader.headings.map { Int($0.tag.dropFirst()) ?? 0 }

    #expect(["header", "main", "footer"].allSatisfy(Self.reader.landmarks.contains))
    #expect(levels.first == 1)
    #expect(levels.filter { $0 == 1 }.count == 1)
    #expect(zip(levels, levels.dropFirst()).allSatisfy { $1 - $0 <= 1 })
    #expect(Self.reader.headingTexts.contains("How this catalog is built and how to help"))
  }

  @Test func pageMakesNoExternalRequests() {
    #expect(Self.reader.sources.filter { $0.contains("//") } == [])
  }

  @Test func pageLinksTheAPITheRepositoryAndTheIssueRoute() {
    let base = "https://github.com/brandtdaniels/insteon-device-catalog"

    for link in ["\(base)/blob/main/API.md", base, "\(base)/issues", "\(base)/pulls"] {
      #expect(Self.reader.hrefs.contains(link), "\(link)")
    }
  }

  @Test func pageTextHasNoDashAndNoTemporalWords() {
    // The cards quote catalog data; the rest of the page is the page's own wording.
    let text = Self.page
      .removing(#"<(script|style|article)\b.*?</\1>"#, options: [.dotMatchesLineSeparators])
      .replacingMatches(of: "<[^>]+>", with: " ")

    #expect(!Self.hasDash(Self.page))
    #expect(!text.lowercased().matches(Self.temporalWords))
  }

  @Test func thePageNamesTheStatusWordsNotUnverified() {
    let text = Self.page.pageText

    #expect(!text.lowercased().contains("unverified"))
    #expect(text.matches(#"status \(inferred, conflicting or observed\)"#))
    #expect(text.lowercased().contains("a value with no mark is documented"))
  }

  @Test func theIdentitiesColumnSaysWhatDocumentedMeans() {
    #expect(Self.page.pageText.contains("An identity with no mark is counted as documented: it is read from the documents the profile cites, not confirmed on a device."))
  }

  @Test func generatedTextHasNoDashAndNoTemporalWordsEvenInCards() throws {
    let profile = json(#"""
    {"model": "9", "name": "Plain", "capabilities": [{"kind": "dimmable"}, {"kind": "heartbeat", "group": "0x04", "intervalMinutes": 5}], "sources": ["S"],
     "radio": "rf", "batteryPowered": true, "groups": [{"number": "0x04", "name": "Beat", "role": "controller"}],
     "engines": [{"category": "0x01", "subcategory": "0x01", "engine": "i2"}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}],
     "identities": [{"category": "0x01", "subcategory": "0x01"}]}
    """#)
    let bare = json(#"{"model": "8", "name": "Bare", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x02"}]}"#)
    let none = json(#"""
    {"model": "7", "name": "None", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x03"}],
     "commandSets": [{"commandSet": "empty", "category": "0x01", "subcategory": "0x03"}]}
    """#)
    let sets = json(#"""
    [{"id": "a", "name": "A", "operatingFlags": [{"name": "f", "label": "Flag one"}], "extendedSettings": {"values": [{"label": "Setting one"}]},
      "standardCommands": [{}], "serialCommands": [{}]},
     {"id": "empty", "name": "E", "description": "Nothing.", "sources": ["S"]}]
    """#).elements

    let page = try CatalogPage.render([profile, bare, none], sets)
    let text = page.pageText

    #expect(!Self.hasDash(page))
    #expect(!text.lowercased().matches(Self.temporalWords))
    #expect(text.contains("Flag one"))
    #expect(text.contains("The catalog has no command set for this device."))
    #expect(text.contains("deliberately holds no settings"))
  }

  @Test func htmlSpecialCharactersInADescriptionAreEscapedInTheCard() throws {
    let profile = json(#"""
    {"model": "9", "name": "A <b> & \"q\" 'n'", "description": "x < y & z", "aliases": ["<i>"], "capabilities": [], "sources": ["S"],
     "identities": [{"category": "0x01", "subcategory": "0x01"}]}
    """#)

    let page = try CatalogPage.render([profile], [])

    #expect(page.contains("<h3>A &lt;b&gt; &amp; &quot;q&quot; &#x27;n&#x27;</h3>"))
    #expect(page.contains(#"<p class="description">x &lt; y &amp; z</p>"#))
    #expect(page.contains(#"<p class="aliases">Also known as &lt;i&gt;</p>"#))
  }

  @Test func cardsAreGroupedByCategoryInNaturalModelOrder() throws {
    func profile(_ model: String, _ category: String) -> JSONValue {
      json(#"{"model": "\#(model)", "name": "N\#(model)", "capabilities": [], "sources": ["S"], "identities": [{"category": "\#(category)", "subcategory": "0x01"}]}"#)
    }

    let page = try CatalogPage.render([profile("10", "0x02"), profile("9", "0x02"), profile("2A", "0x01"), profile("100", "0x01")], [])
    let order = page.captures(#"data-model="([^"]+)""#).map { $0[0] }
    let sections = page.captures(#"<section class="category" id="category-(0x[0-9A-F]+)""#).map { $0[0] }

    #expect(sections == ["0x01", "0x02"])
    #expect(order == ["2A", "100", "9", "10"])
    #expect(page.contains("<h2>Dimmable Lighting Control<span class=\"n\">2 products</span></h2>"))
  }

  @Test func aCategoryWithOneProductSaysProduct() throws {
    let profile = json(#"{"model": "1", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x0B", "subcategory": "0x01"}]}"#)
    let page = try CatalogPage.render([profile], [])

    #expect(page.contains(#"<h2>Plumbing<span class="n">1 product</span></h2>"#))
    #expect(!page.contains(#"<p class="category-description">"#))
  }

  @Test func aCategoryWithNoNameShowsItsCode() throws {
    let profile = json(#"{"model": "1", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x7F", "subcategory": "0x01"}]}"#)
    let page = try CatalogPage.render([profile], [])

    #expect(page.contains(#"<h2>0x7F<span class="n">1 product</span></h2>"#))
    #expect(page.contains(#"<option value="0x7F">0x7F</option>"#))
  }
}
