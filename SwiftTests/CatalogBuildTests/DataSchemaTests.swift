import CatalogBuild
import CatalogJSON
import CatalogSchema
import Foundation
import Testing

/// Every data file against its schema, as the Python build checks them.
struct DataSchemaTests {
  static let root = RepositoryRoot(url: CatalogRepository.url)

  static let devices: [CatalogFile] = (try? root.deviceFiles()) ?? []
  static let commandSets: [CatalogFile] = (try? root.commandSetFiles()) ?? []
  static let deviceNames: [String] = devices.map(\.name)
  static let commandSetNames: [String] = commandSets.map(\.name)
  static let deviceValidator = try! SchemaValidator(schema: root.schema(.deviceProfile))
  static let commandSetValidator = try! SchemaValidator(schema: root.schema(.commandSet))

  @Test(arguments: deviceNames)
  func aDeviceProfileMatchesItsSchema(_ name: String) throws {
    let file = try #require(Self.devices.first { $0.name == name })
    let validator = Self.deviceValidator

    #expect(validator.errors(in: file.value).map { $0.report(file: name) } == [])
  }

  @Test(arguments: commandSetNames)
  func aCommandSetMatchesItsSchema(_ name: String) throws {
    let file = try #require(Self.commandSets.first { $0.name == name })
    let validator = Self.commandSetValidator

    #expect(validator.errors(in: file.value).map { $0.report(file: name) } == [])
  }

  @Test func theCatalogHasProfilesAndCommandSetsToCheck() {
    #expect(Self.deviceNames.count > 100)
    #expect(Self.commandSetNames.count > 40)
  }

  @Test func schemaProblemsAreEmptyForTheCatalog() throws {
    #expect(try Self.root.schemaProblems() == [])
  }

  @Test func schemaProblemsNameTheFileAndThePathInFileNameOrder() throws {
    try RepositoryRootTests.withRepository(
      devices: ["b.json": #"{"model": 1}"#, "a.json": #"{"model": 2}"#],
      commandSets: ["c.json": #"{"id": 3}"#]
    ) { root in
      let problems = try root.schemaProblems(
        deviceSchema: JSONParser.parse(#"{"properties": {"model": {"type": "string"}}}"#),
        commandSetSchema: JSONParser.parse(#"{"required": ["name"]}"#)
      )

      #expect(problems == [
        "a.json: $.model: 2 is not of type 'string'",
        "b.json: $.model: 1 is not of type 'string'",
        "c.json: $: 'name' is a required property"
      ])
    }
  }
}
