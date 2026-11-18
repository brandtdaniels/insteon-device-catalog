import Foundation
import Testing

@testable import CatalogSite

/// The rendered stylesheet and the layout the page's markup relies on.
struct PageStyleTests {
  static let page = CatalogPage.page
  static let css: String = page.captures(#"<style>(.*?)</style>"#, options: [.dotMatchesLineSeparators]).first?.first ?? ""
  static let rules: [(head: String, body: String)] = {
    let withoutComments = css.removing(#"/\*.*?\*/"#, options: [.dotMatchesLineSeparators])
    let withoutMedia = withoutComments.removing(#"@media[^{]*\{"#)
    return withoutMedia.captures(#"([^{}]+)\{([^{}]*)\}"#).map { (head: $0[0], body: $0[1]) }
  }()

  static func declarations(_ selector: String) -> [String] {
    rules.filter { $0.head.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(selector) }.map(\.body)
  }

  @Test func headerMainAndFooterShareOneContainer() {
    for tag in ["header", "main", "footer"] {
      #expect(Self.page.matches("<\(tag) class=\"container\"[ >]"), "\(tag)")
    }

    let container = Self.declarations(".container").joined(separator: " ")

    #expect(container.contains("max-width: var(--page-width)"))
    #expect(container.contains("margin-inline: auto"))
    #expect(container.contains("padding-inline: var(--gutter)"))

    for tag in ["header", "main", "footer", "nav", "body"] {
      #expect(!Self.declarations(tag).joined(separator: " ").matches(#"max-width|padding-inline|margin-inline|padding: [^;]*var\(--gutter"#), "\(tag)")
    }
  }

  @Test func thePageLinksAreALabeledNavInsideTheHeader() throws {
    let header = try #require(Self.page.captures(#"(<header.*?</header>)"#, options: [.dotMatchesLineSeparators]).first?.first)

    #expect(header.matches(#"<nav aria-label="[^"]+">.*What the catalog covers.*</nav>"#, options: [.dotMatchesLineSeparators]))
  }

  @Test func spacingTypeAndRadiusAreTokensDefinedOnce() {
    let root = Self.declarations(":root").joined(separator: " ")
    let tokens = [
      "--space-1", "--space-2", "--space-3", "--space-4", "--space-5", "--space-6", "--text-xs", "--text-sm", "--text-base", "--text-lg",
      "--text-xl", "--radius-control", "--radius-card", "--radius-pill", "--page-width"
    ]

    for token in tokens {
      #expect(root.occurrences(of: token + ":") == 1, "\(token)")
    }
  }

  @Test func spacingAndTypeUseTokensNotRawValues() {
    for (head, body) in Self.rules where head.trimmingCharacters(in: .whitespacesAndNewlines) != ":root" {
      for property in body.captures(#"(font-size|gap|padding[a-z-]*|margin[a-z-]*|border-radius)\s*:\s*([^;]+)"#) {
        #expect(!property[1].matches(#"\d(rem|em|px)\b"#), "\(head) \(property[0]) \(property[1])")
      }
    }
  }

  @Test func cardsAlignToTheTopSoAnOpenCardDoesNotStretchItsRow() {
    #expect(Self.declarations(".grid").contains { $0.contains("align-items: start") })
  }

  @Test func theCoverageTableUsesTheSamePillAsTheCards() throws {
    let table = try #require(Self.page.captures(#"(<table class="statuses-table".*?</table>)"#, options: [.dotMatchesLineSeparators]).first?.first)

    for status in PageTables.statuses {
      #expect(table.contains(#"<span class="status pill status-\#(status)">"#))
    }

    for status in ["observed", "inferred", "conflicting"] {
      #expect(Self.declarations(".status-\(status)").count == 1)
    }
  }

  @Test func theFiguresGridHasOneColumnPerFigureUpToFourAndThreeBeyond() {
    let rows = Self.page.captures(#"<ul class="figures" style="--figures: (\d+)">(.*?)</ul>"#)

    #expect(!rows.isEmpty)

    for row in rows {
      let columns = Int(row[0]) ?? -1
      let figures = row[1].occurrences(of: "<li data-fact=")

      #expect(columns == (figures <= 4 ? figures : 3))
    }

    #expect(Self.declarations(".figures").joined(separator: " ").contains("repeat(var(--figures"))
  }

  @Test func aFigureIsShownOnlyForAPartTheCommandSetHolds() {
    for card in CatalogPage.cards.values {
      for items in card.lists.values { #expect(!items.isEmpty) }

      for fact in card.facts where PageTables.commandSetFacts.contains(fact.name) {
        #expect(!fact.text.trimmingCharacters(in: .whitespacesAndNewlines).matches("^0 "))
      }
    }
  }

  @Test func aCheckboxIsDrawnWithTheAccentSoCheckedAndUncheckedDiffer() {
    #expect(Self.declarations("input[type=checkbox]").joined(separator: " ").contains("accent-color: var(--accent)"))
  }

  @Test func chipsAndStatusMarksShareOnePill() {
    #expect(Self.declarations(".pill").count == 1)
    #expect(Self.page.matches(#"class="chip pill""#))
    #expect(Self.page.matches(#"class="status pill status-"#))
  }

  @Test func everyStatusPillHasTheSameOuterBox() {
    let root = Self.declarations(":root").joined(separator: " ")

    for token in ["--pill-border", "--pill-ring", "--pill-ring-extra"] {
      #expect(root.occurrences(of: token + ":") == 1, "\(token)")
    }

    let pill = Self.declarations(".pill").joined(separator: " ")
    let ring = Self.declarations(".status-conflicting").joined(separator: " ")

    #expect(pill.contains("border: var(--pill-border) solid transparent"))
    #expect(root.contains("--pill-ring-extra: calc(var(--pill-ring) - var(--pill-border))"))
    #expect(ring.contains("border-width: var(--pill-ring)"))
    #expect(ring.contains("border-style: double"))
    #expect(ring.contains("padding-inline: calc(var(--space-2) - var(--pill-ring-extra))"))
    #expect(ring.contains("line-height: calc(1.5em - 2 * var(--pill-ring-extra))"))
    #expect(!ring.matches("margin"))
  }

  @Test func theConflictingRingTakesLayoutSpaceInsteadOfAShadow() {
    #expect(!Self.declarations(".status-conflicting").joined(separator: " ").contains("box-shadow"))
    #expect(!Self.css.contains("--pill-gap"))
  }
}
