import CatalogBuild
import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// The eight constant tables the page words its cards and legend from.
struct PageTablesTests {
  static let root = RepositoryRoot(url: CatalogRepository.url)
  static let profiles = ((try? root.deviceFiles()) ?? []).map(\.value)

  @Test func theStatusesAreInThePageOrder() {
    #expect(PageTables.statuses == ["observed", "documented", "inferred", "conflicting"])
  }

  @Test func eachStatusHasOneSentence() {
    #expect(PageTables.statusExplanations.keys == PageTables.statuses)

    for status in PageTables.statuses {
      let sentence = PageTables.statusExplanations[status] ?? ""

      #expect(sentence.hasSuffix("."))
      #expect(sentence.filter { $0 == "." }.count == 1, "\(status)")
    }
  }

  @Test func theCapabilityTablesNameEveryKindTheSchemaDefines() throws {
    let schema = try Self.root.schema(.deviceProfile)
    let kinds = try #require(schema["$defs"]?["capability"]?["oneOf"]).elements.compactMap { $0["properties"]?["kind"]?["const"]?.string }

    #expect(kinds.count == 8)
    #expect(kinds.sorted() == PageTables.capabilityExplanations.keys.sorted())
    #expect(kinds.sorted() == PageTables.capabilityLabels.keys.sorted())
  }

  @Test func theLegendListsCapabilitiesRadiosAndEnginesInTheirOrder() {
    #expect(PageTables.capabilityExplanations.keys == ["onOff", "dimmable", "modem", "hub", "hubPro", "thermostat", "groupEvents", "heartbeat"])
    #expect(PageTables.radioExplanations.keys == ["powerline", "rf", "dual", "unstated"])
    #expect(PageTables.engineExplanations.keys == ["i1", "i2", "i2cs"])
    #expect(PageTables.engineLabels.keys == ["i1", "i2", "i2cs"])
  }

  @Test func everyLegendSentenceIsOnePlainSentence() {
    let sentences = PageTables.capabilityExplanations.values + PageTables.radioExplanations.values + PageTables.engineExplanations.values
      + [PageTables.batteryExplanation]

    #expect(sentences.count == 16)

    for sentence in sentences {
      #expect(sentence.hasSuffix("."), "\(sentence)")
      #expect(sentence.filter { $0 == "." }.count == 1, "\(sentence)")
    }
  }

  @Test func theLabelTablesWordTheValuesTheProfilesUse() {
    #expect(PageTables.radioLabels.keys == ["powerline", "rf", "dual"])
    #expect(PageTables.radioLabels["rf"] == "RF")
    #expect(PageTables.radioLabels["dual"] == "Dual-band")
    #expect(PageTables.roleLabels["both"] == "Controller and responder")
    #expect(PageTables.engineLabels["i2cs"] == "i2CS")
    #expect(PageTables.capabilityLabels["hubPro"] == "Hub Pro")
    #expect(PageTables.capabilityLabels["groupEvents"] == "Group events")
  }

  @Test func theCategoryTableNamesEveryCategoryTheProfilesUse() {
    let used = Set(Self.profiles.flatMap { $0["identities"]?.elements ?? [] }.compactMap { $0["category"]?.string })

    #expect(!used.isEmpty)

    for category in used {
      #expect(PageTables.categoryNames[category] != nil, "\(category)")
    }
  }

  @Test func aCategoryDescriptionBelongsToANamedCategory() {
    for category in PageTables.categoryDescriptions.keys {
      #expect(PageTables.categoryNames[category] != nil, "\(category)")
    }

    #expect(PageTables.categoryNames.count == 23)
    #expect(PageTables.categoryDescriptions.count == 13)
  }

  @Test func theCommandSetFactsAndTheirListTitlesAreInTheCardOrder() {
    #expect(PageTables.commandSetFacts == ["operatingFlags", "extendedSettings", "standardCommands", "extendedCommands", "serialCommands", "readings"])
    #expect(PageTables.listTitles["operatingFlags"] == "Operating flags")
    #expect(PageTables.listTitles["extendedSettings"] == "Extended settings")
    #expect(PageTables.listTitles["readings"] == "Readings")
    #expect(PageTables.listTitles.keys.count == 3)
  }

  @Test func theDescriptiveKeysOfACommandSetAreThoseThatDescribeItNotItsBehavior() {
    #expect(PageTables.commandSetDescriptiveKeys == ["id", "name", "description", "notes", "sources"])
  }

  @Test func noTableTextHasADashOrAnUppercaseInsteon() {
    let text = PageTables.capabilityExplanations.values + PageTables.radioExplanations.values + PageTables.engineExplanations.values
      + PageTables.statusExplanations.values + PageTables.categoryDescriptions.values + PageTables.categoryNames.values

    for sentence in text {
      #expect(!sentence.unicodeScalars.contains { $0.value == 0x2013 || $0.value == 0x2014 }, "\(sentence)")
    }
  }
}

