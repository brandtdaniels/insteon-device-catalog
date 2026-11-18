import CatalogBuild
import CatalogIngest
import CatalogJSON
import CatalogSchema
import Foundation
import Testing

struct ObservationSchemaTests {
  static let swiftPackageCopy = Fixtures.repository.deletingLastPathComponent()
    .appendingPathComponent("swift-insteon/Packages/InsteonCLI/Schemas/insteon-observation-1.schema.json")

  @Test func theVendoredSchemaIsTheOneTheFormatWasAgreedOn() {
    let digest = Checksum.sha256Hex(of: Array(ObservationSchema.text.utf8))

    #expect(digest == "4f3e2fbd346f1fcd72c30d00b9fc269535affe511fa47fe3ef5fb2a3340d34ac")
    #expect(digest == ObservationSchema.sha256)
  }

  @Test(.enabled(if: FileManager.default.fileExists(atPath: swiftPackageCopy.path), "the swift package is not next to this checkout"))
  func theVendoredSchemaMatchesTheSwiftPackagesCopy() throws {
    #expect(Array(ObservationSchema.text.utf8) == Array(try Data(contentsOf: Self.swiftPackageCopy)))
  }

  @Test func theSchemaUsesOnlyKeywordsTheValidatorImplements() throws {
    let schema = try JSONParser.parse(ObservationSchema.text)
    let known = SchemaKeywords.validating.union(SchemaKeywords.annotations)
    let unknown = SchemaKeywords.used(in: schema).subtracting(known)

    #expect(unknown.isEmpty, "the schema uses keywords the validator does not implement: \(unknown.sorted().joined(separator: ", "))")
  }

  @Test func theSchemaIsOneTheValidatorAccepts() throws {
    _ = try ObservationSchema.validator()
  }
}
