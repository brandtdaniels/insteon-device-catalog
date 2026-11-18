import CatalogBuild
import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// The page for a frozen subset of the catalog, against the bytes the Python build wrote for the
/// same files, the same version and a small template that names every placeholder. The subset keeps
/// the tests independent of the catalog's current data and template.
struct PageGoldenTests {
  static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/subset")

  static func text(_ name: String) -> String {
    (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
  }

  static func files(_ directory: String) -> [JSONValue] {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(directory).path)) ?? [])
      .filter { $0.hasSuffix(".json") }
      .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }

    return names.map { json(text("\(directory)/\($0)")) }
  }

  static let input = SiteInput(
    profiles: files("devices"),
    commandSets: files("commandSets"),
    capabilityDescriptions: Dictionary(uniqueKeysWithValues: json(text("capability-descriptions.json")).members.compactMap { member in
      member.value.string.map { (member.key, $0) }
    }),
    version: "0.10.7",
    major: "0"
  )
  static let golden = text("index.html")
  static let page = (try? SitePage.render(input, template: Template(text("template.html")))) ?? ""
  static let goldenCards = golden.components(separatedBy: #"<article class="card""#).dropFirst().map { #"<article class="card""# + $0 }
  static let models: [String] = goldenCards.compactMap { $0.captures(#"data-model="([^"]+)""#).first?.first }

  @Test func theSubsetHoldsElevenProfilesAndTheirCards() {
    #expect(Self.input.profiles.count == 11)
    #expect(Self.input.commandSets.count == 10)
    #expect(Self.models.count == 11)
  }

  @Test func theWholePageIsTheSameBytesAsThePythonBuildWrote() {
    #expect(Self.page.utf8.elementsEqual(Self.golden.utf8))
  }

  @Test(arguments: models)
  func eachCardIsTheSameBytesAsThePythonBuildWroteIt(model: String) throws {
    let golden = try #require(Self.goldenCards.first { $0.contains(#"data-model="\#(model)""#) })
    let card = try #require(try SitePage.fragments(Self.input).categories.flatMap(\.cards).first { $0.model == model })

    #expect(golden.hasPrefix(card.html))
    #expect(card.html.utf8.elementsEqual(golden.prefix(card.html.utf8.count).utf8))
  }

  @Test func theFilterOptionsAndSectionsAreTheSameBytesAsThePythonBuildWroteThem() throws {
    let fragments = try SitePage.fragments(Self.input)

    #expect(Self.golden.contains(fragments.categoryOptions + "</select>"))
    #expect(Self.golden.contains(fragments.capabilityOptions + "</select>"))
    #expect(Self.golden.contains(fragments.engineOptions + "</select>"))
    #expect(Self.golden.contains(fragments.verificationOptions + "</select>"))
    #expect(Self.golden.contains(fragments.coverage + "\n\n" + fragments.capabilities + "\n\n" + fragments.sections + "\n" + fragments.how))
  }

  @Test func aDoubleDollarInTheTemplateIsOneDollarInThePage() {
    #expect(Self.page.contains("<p>Costs $5.</p>"))
  }
}
