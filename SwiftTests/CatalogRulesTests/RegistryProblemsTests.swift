import CatalogBuild
import CatalogJSON
import CatalogRules
import Foundation
import Testing

/// The registry, citation, term and dash checks over a repository: the catalog's own files, where
/// each check runs in the build's order, and what a missing or broken registry file reports.
struct RegistryProblemsTests {
  static let unlisted = "documents/registry.json; register the document or cite its exact title"

  static func problems(
    devices: [String: JSONValue] = [:], commandSets: [String: JSONValue] = [:], documents: [String: String]? = nil
  ) throws -> [String] {
    var found: [String] = []
    let devices = try devices.isEmpty ? ["2441ZTH.json": Fixtures.profile("2441ZTH")] : devices
    let commandSets = try commandSets.isEmpty ? ["tempLinc.json": Fixtures.commandSet("tempLinc")] : commandSets

    try RuleProblemsTests.withRepository(devices: devices, commandSets: commandSets, documents: documents) { root in
      found = try root.problems(
        deviceSchema: Fixtures.root.schema(.deviceProfile), commandSetSchema: Fixtures.root.schema(.commandSet)
      )
    }

    return found
  }

  /// The catalog's `registry.json` text with a document added at the end.
  static func registry(adding entry: String) throws -> String {
    let text = try RuleProblemsTests.realDocuments()["registry.json"] ?? ""

    let end = try #require(text.range(of: "\n  ]\n}", options: .backwards))

    return String(text[..<end.lowerBound]) + ",\n" + entry + "\n  ]\n}\n"
  }

  // DocumentRegistryTests.test_the_catalogs_registry_is_valid
  @Test func theCatalogsRegistryIsValid() throws {
    let load = Fixtures.root.documentRegistry()

    #expect(load.problems == [])
    #expect(load.titles != nil)
  }

  // NearDuplicateTitleTests.test_the_catalogs_registry_has_no_unreviewed_near_duplicates
  @Test func theCatalogsRegistryHasNoUnreviewedNearDuplicates() throws {
    let registry = try JSONParser.parse(RuleProblemsTests.realDocuments()["registry.json"] ?? "")
    let reviewed = try JSONParser.parse(RuleProblemsTests.realDocuments()["reviewed-distinct-titles.json"] ?? "")

    let pairs = reviewed["distinct"]?.elements ?? []

    #expect(pairs.count > 0)
    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: pairs) == [])
  }

  // DocumentRegistryTests.test_every_source_in_the_catalog_is_registered
  @Test func everySourceInTheCatalogIsRegistered() throws {
    let titles = try #require(Fixtures.root.documentRegistry().titles)
    var found: [String] = []

    for file in try Fixtures.root.deviceFiles() {
      found += SourceRules.problems(label: "\(file.stem).json", in: file.value, titles: titles)
    }

    for file in try Fixtures.root.commandSetFiles() {
      found += SourceRules.problems(label: "\(file.stem).json", in: file.value, titles: titles)
    }

    #expect(found == [])
  }

  // NoDashTests.test_no_data_file_has_a_dash_character
  @Test func noDataFileHasADashCharacter() throws {
    let found = try Fixtures.root.dashProblems()

    #expect(found == [])
  }

  @Test func theCatalogHasNoTermProblems() throws {
    for file in try Fixtures.root.deviceFiles() {
      #expect(TermRules.problems(label: file.name, in: file.value) == [], "\(file.name)")
    }

    for file in try Fixtures.root.commandSetFiles() {
      #expect(TermRules.problems(label: file.name, in: file.value) == [], "\(file.name)")
    }
  }

  // NoDashTests.test_a_dash_in_a_data_file_is_reported_with_its_file
  @Test func aDashInAProfileIsReportedWithItsDirectoryAndFile() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["aliases", .index(0)], #""A \#u{2014} B""#)

    #expect(try Self.problems(devices: ["2441ZTH.json": profile]) == [
      "devices/2441ZTH.json: has an em or en dash; use a hyphen, comma or colon"
    ])
  }

  @Test func dashFilesAreListedByDirectoryThenFileName() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["aliases", .index(0)], #""A \#u{2013} B""#)
    let commandSet = try Fixtures.commandSet("tempLinc").setting(["name"], #""A \#u{2014} B""#)
    let documents = try RuleProblemsTests.realDocuments().merging(["a.json": "\u{2014}", "z.json": "\u{2013}"]) { $1 }

    try RuleProblemsTests.withRepository(
      devices: ["2441ZTH.json": profile, "2441-x.json": profile], commandSets: ["tempLinc.json": commandSet], documents: documents
    ) { root in
      let found = try root.dashProblems()

      #expect(found == [
        "devices/2441-x.json: has an em or en dash; use a hyphen, comma or colon",
        "devices/2441ZTH.json: has an em or en dash; use a hyphen, comma or colon",
        "commandSets/tempLinc.json: has an em or en dash; use a hyphen, comma or colon",
        "documents/a.json: has an em or en dash; use a hyphen, comma or colon",
        "documents/z.json: has an em or en dash; use a hyphen, comma or colon"
      ])
    }
  }

  @Test func aTermInAProfileNamesItsModelAndTheKey() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["name"], #""INSTEON Thermostat""#)

    #expect(try Self.problems(devices: ["2441ZTH.json": profile]) == ["2441ZTH.json: 'INSTEON' in name; use Insteon"])
  }

  @Test func aTermIsLabeledWithTheModelAndNotTheFileName() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["name"], #""INSTEON Thermostat""#)

    #expect(try Self.problems(devices: ["wrong.json": profile]) == [
      "wrong.json: the file name must be the model, '2441ZTH'",
      "2441ZTH.json: 'INSTEON' in name; use Insteon"
    ])
  }

  @Test func anUnregisteredSourceNamesItsFileAndString() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["sources"], #"["Not A Title"]"#)

    #expect(try Self.problems(devices: ["2441ZTH.json": profile]) == [
      "2441ZTH.json: source 'Not A Title' is not in \(Self.unlisted)"
    ])
  }

  @Test func aFileThatFailsItsSchemaGetsNoTermOrSourceChecks() throws {
    let broken = try Fixtures.profile("2441ZTH").setting(["name"], #""INSTEON Thermostat""#).setting(["sources"], #"["Unlisted"]"#)
      .removing(["identities"])

    #expect(try Self.problems(devices: ["2441ZTH.json": broken]) == ["2441ZTH.json: $: 'identities' is a required property"])
  }

  @Test func aRegistryProblemSuppressesTheSourceChecks() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["name"], #""INSTEON Thermostat""#).setting(["sources"], #"["Unlisted"]"#)
    let registry = #"{"documents": [{"title": "A", "kind": "other"}, {"title": "A", "kind": "other"}]}"#
    let documents = try RuleProblemsTests.realDocuments().merging(["registry.json": registry]) { $1 }

    #expect(try Self.problems(devices: ["2441ZTH.json": profile], documents: documents) == [
      "registry.json: title 'A' appears more than once",
      "2441ZTH.json: 'INSTEON' in name; use Insteon"
    ])
  }

  @Test func aMissingRegistryIsReportedAndSuppressesTheSourceChecks() throws {
    var documents = try RuleProblemsTests.realDocuments()
    documents["registry.json"] = nil

    #expect(try Self.problems(documents: documents) == ["registry.json: the file can't be read"])
  }

  @Test func aRegistryThatIsNotJSONIsReportedWithItsPosition() throws {
    let documents = try RuleProblemsTests.realDocuments().merging(["registry.json": "{\"documents\": [,]}"]) { $1 }
    let found = try Self.problems(documents: documents)

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("registry.json: line 1, column ") == true)
  }

  @Test func theReviewedFileIsReadOnlyWhenTheRegistryHasNoProblems() throws {
    let badRegistry = #"{"documents": "x"}"#
    let documents = try RuleProblemsTests.realDocuments().merging(["registry.json": badRegistry, "reviewed-distinct-titles.json": "[]"]) { $1 }

    #expect(try Self.problems(documents: documents) == [#"registry.json: must be an object with only a "documents" list"#])
  }

  @Test(arguments: [
    ("[]", "reviewed-distinct-titles.json: TypeError('list indices must be integers or slices, not str')"),
    ("\"s\"", "reviewed-distinct-titles.json: TypeError(\"string indices must be integers, not 'str'\")"),
    ("5", "reviewed-distinct-titles.json: TypeError(\"'int' object is not subscriptable\")"),
    ("1.5", "reviewed-distinct-titles.json: TypeError(\"'float' object is not subscriptable\")"),
    ("true", "reviewed-distinct-titles.json: TypeError(\"'bool' object is not subscriptable\")"),
    ("null", "reviewed-distinct-titles.json: TypeError(\"'NoneType' object is not subscriptable\")"),
    ("{}", "reviewed-distinct-titles.json: KeyError('distinct')")
  ])
  func aReviewedFileThatIsNotAnObjectWithDistinctIsReportedAsPythonNamesTheError(text: String, expected: String) throws {
    let documents = try RuleProblemsTests.realDocuments().merging(["reviewed-distinct-titles.json": text]) { $1 }

    #expect(try Self.problems(documents: documents) == [expected])
  }

  @Test func aMissingReviewedFileIsReported() throws {
    var documents = try RuleProblemsTests.realDocuments()
    documents["reviewed-distinct-titles.json"] = nil

    #expect(try Self.problems(documents: documents) == ["reviewed-distinct-titles.json: the file can't be read"])
  }

  @Test func aNearDuplicatePairInTheRegistryIsReportedOnceItsTitlesAreRegistered() throws {
    let registry = try Self.registry(adding: #"    {"title": "Access Point 2443 Owner's Manual Copy", "kind": "ownersManual"}"#)
    let documents = try RuleProblemsTests.realDocuments().merging(["registry.json": registry]) { $1 }
    let found = try Self.problems(documents: documents)

    // The new title also shares its model number with the reviewed pair's other title.
    #expect(found.count == 2)
    #expect(found.first?.hasPrefix("registry.json: \"Access Point 2443 Owner's Manual\" and \"Access Point 2443 Owner's Manual Copy\" look like one document") == true)
  }
}
