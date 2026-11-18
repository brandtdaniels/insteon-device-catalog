import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// The legend: what each capability, radio, power source and engine means, and how many profiles
/// have it.
struct PageLegendTests {
  static let profiles = CatalogPage.profiles
  static let metrics: [String: Int] = CatalogPage.reader.metrics.compactMapValues { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

  @Test func eachCapabilityCountIsTheNumberOfProfilesThatHaveIt() throws {
    let schema = try CatalogPage.root.schema(.deviceProfile)
    let kinds = try #require(schema["$defs"]?["capability"]?["oneOf"]).elements.compactMap { $0["properties"]?["kind"]?["const"]?.string }

    #expect(kinds.sorted() == PageTables.capabilityExplanations.keys.sorted())

    for kind in kinds {
      let expected = Self.profiles.filter { $0.list("capabilities").contains { $0.text("kind") == kind } }.count
      #expect(Self.metrics["capability-\(kind)"] == expected, "\(kind)")
    }
  }

  @Test func eachRadioCountIsTheNumberOfProfilesThatStateIt() {
    for radio in ["powerline", "rf", "dual"] {
      #expect(Self.metrics["radio-\(radio)"] == Self.profiles.filter { $0.text("radio") == radio }.count, "\(radio)")
    }

    #expect(Self.metrics["radio-unstated"] == Self.profiles.filter { !$0.has("radio") }.count)
  }

  @Test func theBatteryCountIsTheNumberOfBatteryPoweredProfiles() {
    #expect(Self.metrics["battery"] == Self.profiles.filter { $0.isTrue("batteryPowered") }.count)
  }

  @Test func eachEngineCountIsTheNumberOfProfilesWithAnEntryForIt() {
    for engine in ["i1", "i2", "i2cs"] {
      let expected = Self.profiles.filter { $0.list("engines").contains { $0.text("engine") == engine } }.count
      #expect(Self.metrics["engine-\(engine)"] == expected, "\(engine)")
    }
  }

  @Test func everyTermHasOnePlainSentence() {
    let sentences = PageTables.capabilityExplanations.values + PageTables.radioExplanations.values + PageTables.engineExplanations.values
      + [PageTables.batteryExplanation]

    for sentence in sentences {
      #expect(sentence.hasSuffix("."), "\(sentence)")
      #expect(sentence.filter { $0 == "." }.count == 1, "\(sentence)")
      #expect(CatalogPage.page.contains(HTMLEscaper.escape(sentence)), "\(sentence)")
    }
  }

  @Test func theLegendIsALabeledSectionListedInThePageLinks() {
    #expect(CatalogPage.reader.hrefs.contains("#capabilities-heading"))
    #expect(CatalogPage.reader.headingTexts.contains("What the filters mean"))
    #expect(CatalogPage.page.contains(#"aria-labelledby="capabilities-heading""#))
  }

  @Test func aTermWithOneProfileSaysProfileAndOtherCountsSayProfiles() {
    let profiles = json(#"""
    [{"model": "1", "name": "A", "capabilities": [{"kind": "onOff"}], "identities": [{"category": "0x01", "subcategory": "0x01"}]},
     {"model": "2", "name": "B", "capabilities": [{"kind": "onOff"}], "identities": [{"category": "0x01", "subcategory": "0x02"}]}]
    """#).elements
    let legend = Legend(profiles: profiles).html

    #expect(legend.contains(#"<span data-metric="capability-onOff">2</span> profiles</span>"#))
    #expect(legend.contains(#"<span data-metric="capability-dimmable">0</span> profiles</span>"#))
    #expect(Legend(profiles: [profiles[0]]).html.contains(#"<span data-metric="capability-onOff">1</span> profile</span>"#))
  }
}
