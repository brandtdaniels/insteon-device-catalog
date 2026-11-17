import CatalogBuild
import CatalogJSON
import Foundation
import Testing

/// How the loader finds, orders and reads the catalog's data files.
struct RepositoryRootTests {
  /// A directory with the files named, each holding a small JSON object, removed when `body` ends.
  static func withRepository(
    devices: [String: String] = [:], commandSets: [String: String] = [:], directories: [String] = [],
    _ body: (RepositoryRoot) throws -> Void
  ) throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-root-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    for (folder, files) in [("devices", devices), ("commandSets", commandSets)] where !files.isEmpty {
      try FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
      for (name, text) in files {
        try Data(text.utf8).write(to: base.appendingPathComponent(folder).appendingPathComponent(name))
      }
    }
    for directory in directories {
      try FileManager.default.createDirectory(at: base.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    try body(RepositoryRoot(url: base))
  }

  @Test func sortsDeviceFilesByFileNameNotByModel() throws {
    let names = ["2442.json", "2442-222.json", "10.json", "B.json", "a.json", "2441ZTH.json"]
    try Self.withRepository(devices: Dictionary(uniqueKeysWithValues: names.map { ($0, #"{"model": "x"}"#) })) { root in
      let files = try root.deviceFiles()

      // '-' (0x2D) sorts before '.' (0x2E), so 2442-222.json comes first although model 2442 would.
      #expect(files.map(\.name) == ["10.json", "2441ZTH.json", "2442-222.json", "2442.json", "B.json", "a.json"])
      #expect(files.map(\.stem) == ["10", "2441ZTH", "2442-222", "2442", "B", "a"])
    }
  }

  @Test func sortsCommandSetFilesByFileName() throws {
    try Self.withRepository(commandSets: ["b.json": "{}", "a-b.json": "{}", "a.json": "{}", "Z.json": "{}"]) { root in
      let names = try root.commandSetFiles().map(\.name)
      #expect(names == ["Z.json", "a-b.json", "a.json", "b.json"])
    }
  }

  @Test func sortsByCodePointNotByLocale() throws {
    try Self.withRepository(devices: ["é.json": "{}", "a.json": "{}", "B.json": "{}"]) { root in
      let names = try root.deviceFiles().map(\.name)
      #expect(names == ["B.json", "a.json", "é.json"])
    }
  }

  @Test func readsEachFileIntoAJSONValue() throws {
    try Self.withRepository(devices: ["1.json": #"{"model": "1", "n": [1, 2.5]}"#]) { root in
      let file = try #require(try root.deviceFiles().first)

      #expect(file.value == .object([
        JSONMember(key: "model", value: .string("1")),
        JSONMember(key: "n", value: .array([.int(1), .double(2.5)]))
      ]))
    }
  }

  @Test func readsOnlyJSONFilesThatAreNotDirectories() throws {
    try Self.withRepository(devices: ["1.json": "{}", "notes.txt": "x", "2.json.bak": "{}"], directories: ["devices/3.json"]) { root in
      let names = try root.deviceFiles().map(\.name)
      #expect(names == ["1.json"])
    }
  }

  @Test func aMissingDirectoryHoldsNoFiles() throws {
    try Self.withRepository { root in
      let devices = try root.deviceFiles()
      let commandSets = try root.commandSetFiles()
      #expect(devices.isEmpty)
      #expect(commandSets.isEmpty)
    }
  }

  @Test func namesTheFileThatIsNotStrictJSON() throws {
    try Self.withRepository(devices: ["1.json": "{}", "2.json": #"{"a": 1,}"#]) { root in
      do {
        _ = try root.deviceFiles()
        Issue.record("expected an error")
      } catch let error as RepositoryError {
        guard case .unparseable(let file, _) = error else {
          Issue.record("wrong error \(error)")
          return
        }
        #expect(file == "devices/2.json")
        #expect(error.description.hasPrefix("devices/2.json: line 1"))
      }
    }
  }

  @Test func theCatalogsOwnRepositoryHasDevicesAndCommandSets() throws {
    let root = RepositoryRoot(url: CatalogRepository.url)

    let devices = try root.deviceFiles()
    let commandSets = try root.commandSetFiles()
    #expect(!devices.isEmpty)
    #expect(!commandSets.isEmpty)
  }
}

/// The repository this test file belongs to.
enum CatalogRepository {
  static let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
