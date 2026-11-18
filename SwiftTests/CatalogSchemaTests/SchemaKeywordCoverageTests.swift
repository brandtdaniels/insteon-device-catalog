import CatalogJSON
import CatalogSchema
import Foundation
import Testing

/// Every schema the repository keeps stays inside the keywords the validator implements, so the
/// validator can't pass a document a keyword would have rejected.
struct SchemaKeywordCoverageTests {
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  /// The `*.schema.json` files in the catalog's own `schema` directory.
  static let schemaFiles: [String] = {
    let url = root.appendingPathComponent("schema")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    return names.filter { $0.hasSuffix(".schema.json") }.sorted().map { "schema/" + $0 }
  }()

  static func load(_ path: String) throws -> JSONValue {
    try JSONParser.parse([UInt8](Data(contentsOf: root.appendingPathComponent(path))))
  }

  @Test func findsEveryRepositorySchema() {
    #expect(Self.schemaFiles == [
      "schema/command-set.schema.json",
      "schema/device-profile.schema.json"
    ])
  }

  @Test(arguments: schemaFiles)
  func usesOnlyKeywordsTheValidatorImplements(_ path: String) throws {
    let known = SchemaKeywords.validating.union(SchemaKeywords.annotations)
    let unknown = SchemaKeywords.used(in: try Self.load(path)).subtracting(known)

    #expect(unknown.isEmpty, "\(path) uses keywords the validator does not implement: \(unknown.sorted().joined(separator: ", "))")
  }

  @Test(arguments: schemaFiles)
  func loadsIntoAValidator(_ path: String) throws {
    #expect(throws: Never.self) { try SchemaValidator(schema: Self.load(path)) }
  }
}
