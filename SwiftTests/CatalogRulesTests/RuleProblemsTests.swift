import CatalogBuild
import CatalogJSON
import CatalogRules
import Foundation
import Testing

/// The whole check over a repository: the catalog's own files, and the order and form of the lines.
struct RuleProblemsTests {
  @Test func theCatalogHasNoProblems() throws {
    #expect(try Fixtures.root.problems() == [])
  }

  @Test func everyProfileOfTheCatalogPassesTheRules() throws {
    for file in try Fixtures.root.deviceFiles() {
      #expect(ProfileRules.problems(in: file.value, fileStem: file.stem) == [], "\(file.name)")
    }
  }

  /// A repository on disk with the catalog's real files and these changes: profiles and command
  /// sets by file name.
  static func withRepository(
    devices: [String: JSONValue], commandSets: [String: JSONValue], documents: [String: String]? = nil,
    _ body: (RepositoryRoot) throws -> Void
  ) throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-rules-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }

    for (folder, files) in [("devices", devices), ("commandSets", commandSets)] {
      try FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
      for (name, value) in files {
        try Data(JSONWriter.write(value).utf8).write(to: base.appendingPathComponent(folder).appendingPathComponent(name))
      }
    }

    try FileManager.default.createDirectory(at: base.appendingPathComponent("documents"), withIntermediateDirectories: true)
    for (name, text) in try documents ?? realDocuments() {
      try Data(text.utf8).write(to: base.appendingPathComponent("documents").appendingPathComponent(name))
    }

    try body(RepositoryRoot(url: base))
  }

  /// The text of the catalog's own files in `documents`, by file name.
  static func realDocuments() throws -> [String: String] {
    let folder = CatalogRepository.url.appendingPathComponent("documents")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }

    return try Dictionary(uniqueKeysWithValues: names.map { ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)) })
  }

  @Test func problemsComeInTheOrderTheBuildFindsThem() throws {
    let profile = try Fixtures.profile("2441ZTH")
    let tempLinc = try Fixtures.commandSet("tempLinc")

    try Self.withRepository(
      devices: ["2441ZTH.json": profile, "9999.json": profile.setting(["model"], "\"9999\"")],
      commandSets: ["other.json": tempLinc, "tempLinc.json": tempLinc]
    ) { root in
      let problems = try root.problems(
        deviceSchema: Fixtures.root.schema(.deviceProfile), commandSetSchema: Fixtures.root.schema(.commandSet)
      )

      #expect(problems == [
        "9999 and 2441ZTH both claim 0x05/0x0A for overlapping firmware",
        "9999 and 2441ZTH both claim 0x05/0x07 for overlapping firmware",
        "9999 and 2441ZTH both claim 0x05/0x11 for overlapping firmware",
        "9999 and 2441ZTH both claim 0x05/0x12 for overlapping firmware",
        "other.json: the file name must be the id, 'tempLinc'"
      ])
    }
  }

  @Test func aFileThatFailsItsSchemaGetsNoRuleChecks() throws {
    let broken = try Fixtures.profile("2441ZTH").removing(["name"])

    try Self.withRepository(devices: ["wrong.json": broken], commandSets: ["tempLinc.json": Fixtures.commandSet("tempLinc")]) { root in
      let problems = try root.problems(
        deviceSchema: Fixtures.root.schema(.deviceProfile), commandSetSchema: Fixtures.root.schema(.commandSet)
      )

      #expect(problems == ["wrong.json: $: 'name' is a required property"])
    }
  }

  @Test func aProfileFileNamedForAnotherModelIsReportedWithItsFileName() throws {
    try Self.withRepository(devices: ["wrong.json": Fixtures.profile("2441ZTH")], commandSets: ["tempLinc.json": Fixtures.commandSet("tempLinc")]) { root in
      let problems = try root.problems(
        deviceSchema: Fixtures.root.schema(.deviceProfile), commandSetSchema: Fixtures.root.schema(.commandSet)
      )

      #expect(problems == ["wrong.json: the file name must be the model, '2441ZTH'"])
    }
  }
}
