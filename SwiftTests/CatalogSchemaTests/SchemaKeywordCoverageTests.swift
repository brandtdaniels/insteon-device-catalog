import CatalogJSON
import CatalogSchema
import Foundation
import Testing

/// Every schema the repository keeps stays inside the keywords the validator implements, so the
/// validator can't pass a document a keyword would have rejected.
struct SchemaKeywordCoverageTests {
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  /// Directories that hold `*.schema.json` files: the catalog's own and the vendored ingest schema.
  static let schemaDirectories = ["schema", "scripts/ingest_lib/schemas"]

  static let schemaFiles: [String] = schemaDirectories.flatMap { directory -> [String] in
    let url = root.appendingPathComponent(directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    return names.filter { $0.hasSuffix(".schema.json") }.sorted().map { directory + "/" + $0 }
  }

  static func load(_ path: String) throws -> JSONValue {
    try JSONParser.parse([UInt8](Data(contentsOf: root.appendingPathComponent(path))))
  }

  @Test func findsEveryRepositorySchema() {
    #expect(Self.schemaFiles == [
      "schema/command-set.schema.json",
      "schema/device-profile.schema.json",
      "scripts/ingest_lib/schemas/insteon-observation-1.schema.json"
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
