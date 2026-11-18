import CatalogBuild
import CatalogJSON
import Foundation
import Testing

/// The catalog file and the manifest that describes it.
struct CatalogBundleTests {
  static func value(_ text: String) throws -> JSONValue {
    try JSONParser.parse(Array(text.utf8))
  }

  static func bundle(
    profiles: [String] = [#"{"model": "A", "name": "Switch", "ratio": 0.5}"#],
    commandSets: [String] = [#"{"id": "relay"}"#],
    version: String = "0.9",
    patch: Int = 4,
    built: String? = nil
  ) throws -> CatalogBundle {
    try CatalogBundle(
      profiles: profiles.map(value), commandSets: commandSets.map(value), version: version, patch: patch, built: built
    )
  }

  @Test func catalogListsCommandSetsBeforeDevicesWithEveryObjectsKeysSortedAndEndsWithANewline() throws {
    let catalog = try Self.bundle().catalog

    #expect(catalog == """
      {
        "commandSets": [
          {
            "id": "relay"
          }
        ],
        "devices": [
          {
            "model": "A",
            "name": "Switch",
            "ratio": 0.5
          }
        ]
      }

      """)
  }

  @Test func catalogKeepsDevicesAndCommandSetsInTheOrderGiven() throws {
    let catalog = try Self.value(try Self.bundle(profiles: [#"{"model": "B"}"#, #"{"model": "A"}"#]).catalog)

    #expect(Self.models(in: catalog) == ["B", "A"])
  }

  @Test func catalogWritesNonAsciiCharactersAsTheyAre() throws {
    let catalog = try Self.bundle(profiles: [#"{"name": "Caf\u00E9"}"#]).catalog

    #expect(catalog.contains("Caf\u{E9}"))
    #expect(!catalog.contains("\\u00e9"))
  }

  @Test func catalogHoldsNoVersion() throws {
    let first = try Self.bundle(version: "0.9", patch: 1).catalog
    let second = try Self.bundle(version: "1.2", patch: 7).catalog

    #expect(first == second)
  }

  @Test func manifestNamesTheVersionTheDeviceCountTheCatalogFileAndItsHash() throws {
    let manifest = try Self.bundle().manifest

    #expect(manifest == """
      {
        "catalog": "catalog.json",
        "devices": 1,
        "sha256": "\(Self.hash(of: try Self.bundle().catalog))",
        "version": "0.9.4"
      }

      """)
  }

  @Test func manifestHashIsTheSHA256OfTheCatalogsBytes() throws {
    // The digest of the 5 bytes `abc\n` is what `printf 'abc\n' | shasum -a 256` prints.
    #expect(Self.hash(of: "abc\n") == "edeaaff3f1774ad2888673770c6d64097e391bc362d7d6fb34982ddf0efd18cb")

    let bundle = try Self.bundle()
    #expect(try Self.field("sha256", of: bundle.manifest) == Self.hash(of: bundle.catalog))
  }

  @Test func manifestHashChangesWhenTheDataDoesAndNotWhenTheVersionDoes() throws {
    let base = try Self.field("sha256", of: Self.bundle().manifest)
    let newerVersion = try Self.field("sha256", of: Self.bundle(version: "0.10", patch: 99).manifest)
    let changedData = try Self.field("sha256", of: Self.bundle(profiles: [#"{"model": "B"}"#]).manifest)

    #expect(base == newerVersion)
    #expect(base != changedData)
  }

  @Test func manifestCountsOnlyProfilesAsDevices() throws {
    let manifest = try Self.value(try Self.bundle(profiles: ["{}", "{}", "{}"], commandSets: ["{}"]).manifest)

    #expect(manifest["devices"] == .int(3))
  }

  @Test func manifestHasABuiltTimeOnlyWhenGivenOne() throws {
    #expect(try Self.value(Self.bundle(built: nil).manifest)["built"] == nil)
    #expect(try Self.value(Self.bundle(built: "").manifest)["built"] == nil)
    #expect(try Self.value(Self.bundle(built: "2000-01-01T00:00:00Z").manifest)["built"] == .string("2000-01-01T00:00:00Z"))
  }

  @Test func manifestListsItsKeysInSortedOrderWithBuiltFirst() throws {
    let keys = try Self.keys(of: Self.bundle(built: "2000-01-01T00:00:00Z").manifest)

    #expect(keys == ["built", "catalog", "devices", "sha256", "version"])
  }

  @Test func manifestEscapesNonAsciiCharacters() throws {
    let manifest = try Self.bundle(built: "caf\u{E9} \u{1F600}").manifest

    #expect(manifest.contains(#""built": "caf\u00e9 \ud83d\ude00""#))
  }

  @Test func directoryNameIsTheMajorVersionAfterAV() throws {
    #expect(try Self.bundle(version: "0.9").directoryName == "v0")
    #expect(try Self.bundle(version: "12.3").directoryName == "v12")
  }

  @Test(arguments: ["", "1", "1.2.3", "a.b", "1.", ".1", "1.2\n3", "-1.2"])
  func aVersionThatIsNotMajorDotMinorIsRefused(version: String) throws {
    #expect(throws: VersionProblem.malformed(version)) {
      try Self.bundle(version: version)
    }
  }

  static func models(in catalog: JSONValue) -> [String] {
    guard case .array(let devices)? = catalog["devices"] else { return [] }
    return devices.compactMap { device in
      guard case .string(let model)? = device["model"] else { return nil }
      return model
    }
  }

  static func field(_ key: String, of text: String) throws -> String? {
    guard case .string(let value)? = try value(text)[key] else { return nil }
    return value
  }

  static func keys(of text: String) throws -> [String] {
    guard case .object(let members) = try value(text) else { return [] }
    return members.map(\.key)
  }

  static func hash(of text: String) -> String {
    Checksum.sha256Hex(of: Array(text.utf8))
  }
}
