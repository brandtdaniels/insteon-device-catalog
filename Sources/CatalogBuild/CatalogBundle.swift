import CatalogJSON

/// The two files a published catalog is made of: the catalog and the manifest that describes it.
///
/// The catalog holds every profile and command set and no version, so its bytes and their hash change
/// only when its data does. The manifest names the version, the device count and the catalog's hash.
public struct CatalogBundle: Equatable, Sendable {
  /// The directory the files are published in, `v` and the major version.
  public let directoryName: String
  /// The text of `catalog.json`, ending with a newline.
  public let catalog: String
  /// The text of `manifest.json`, ending with a newline.
  public let manifest: String

  /// The file name the manifest gives the catalog.
  public static let catalogFileName = "catalog.json"

  /// Bundles `profiles` and `commandSets`, in the order given, as version `version.patch`.
  ///
  /// - Parameters:
  ///   - version: The `MAJOR.MINOR` text from the `VERSION` file.
  ///   - patch: The version's last number.
  ///   - built: When the catalog was built. The manifest names it only when it isn't empty.
  /// - Throws: ``VersionProblem/malformed(_:)`` when `version` isn't `MAJOR.MINOR`, or
  ///   ``JSONWriteError`` when a number can't be written.
  public init(
    profiles: [JSONValue], commandSets: [JSONValue], version: String, patch: Int, built: String? = nil
  ) throws {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)

    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }) else {
      throw VersionProblem.malformed(version)
    }

    let catalog = try JSONWriter.write(
      .object([
        JSONMember(key: "devices", value: .array(profiles)),
        JSONMember(key: "commandSets", value: .array(commandSets))
      ]),
      style: .init(sortKeys: true)
    ) + "\n"

    var members = [
      JSONMember(key: "version", value: .string("\(version).\(patch)")),
      JSONMember(key: "devices", value: .int(profiles.count)),
      JSONMember(key: "catalog", value: .string(Self.catalogFileName)),
      JSONMember(key: "sha256", value: .string(Checksum.sha256Hex(of: Array(catalog.utf8))))
    ]

    if let built, !built.isEmpty {
      members.append(JSONMember(key: "built", value: .string(built)))
    }

    self.directoryName = "v\(parts[0])"
    self.catalog = catalog
    self.manifest = try JSONWriter.write(.object(members), style: .init(sortKeys: true, asciiOnly: true)) + "\n"
  }
}
