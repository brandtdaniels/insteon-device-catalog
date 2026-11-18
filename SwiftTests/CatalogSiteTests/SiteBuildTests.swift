import CatalogBuild
import CatalogJSON
import CatalogSite
import Foundation
import Testing

/// The directory a build writes: what it holds, byte for byte, and when it writes nothing.
struct SiteBuildTests {
  static let built = "2000-01-01T00:00:00Z"
  static let siteFiles = [
    "index.html", "v0/catalog.json", "v0/command-set.schema.json", "v0/device-profile.schema.json", "v0/manifest.json"
  ]

  /// A temporary directory removed when the test ends.
  final class Workspace {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-site-" + UUID().uuidString)

    init() throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func directory(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// A copy of what the build reads from the catalog repository.
    func copyOfCatalog(named name: String = "repository") throws -> RepositoryRoot {
      let copy = directory(name)
      try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)

      for item in ["devices", "commandSets", "schema", "documents", "templates", "VERSION"] {
        try FileManager.default.copyItem(at: CatalogRepository.url.appendingPathComponent(item), to: copy.appendingPathComponent(item))
      }

      return RepositoryRoot(url: copy)
    }
  }

  /// Every file under `directory`, by its path from `directory`.
  static func files(under directory: URL) throws -> [String: Data] {
    var found: [String: Data] = [:]
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])

    while let item = enumerator?.nextObject() as? URL {
      guard (try item.resourceValues(forKeys: [.isDirectoryKey])).isDirectory != true else { continue }
      let path = String(item.resolvingSymlinksInPath().path.dropFirst(directory.resolvingSymlinksInPath().path.count + 1))
      found[path] = try Data(contentsOf: item)
    }

    return found
  }

  @discardableResult
  static func build(
    _ repository: RepositoryRoot = RepositoryRoot(url: CatalogRepository.url), into output: URL, patch: Int = 3, built: String? = built
  ) throws -> SiteBuildResult {
    try repository.buildSite(into: output, patch: patch, built: built)
  }

  static func majorMinor() throws -> String {
    Self.text(try Data(contentsOf: CatalogRepository.url.appendingPathComponent("VERSION"))).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func text(_ data: Data?) -> String {
    String(decoding: data ?? Data(), as: UTF8.self)
  }

  @Test func writesTheIndexPageAndTheVersionedDirectoryAndNothingElse() throws {
    let workspace = try Workspace()

    try Self.build(into: workspace.directory("site"))

    #expect(try Self.files(under: workspace.directory("site")).keys.sorted() == Self.siteFiles)
  }

  @Test func reportsHowManyProfilesAndCommandSetsItWrote() throws {
    let workspace = try Workspace()
    let root = RepositoryRoot(url: CatalogRepository.url)

    let result = try Self.build(into: workspace.directory("site"))

    #expect(result == .written(profiles: try root.deviceFiles().count, commandSets: try root.commandSetFiles().count))
  }

  @Test func theCatalogFileHoldsTheProfilesAndCommandSetsOfTheRepository() throws {
    let workspace = try Workspace()
    let root = RepositoryRoot(url: CatalogRepository.url)
    try Self.build(into: workspace.directory("site"))

    let bundle = try CatalogBundle(
      profiles: root.deviceFiles().map(\.value), commandSets: root.commandSetFiles().map(\.value),
      version: try Self.majorMinor(),
      patch: 3, built: Self.built
    )
    let files = try Self.files(under: workspace.directory("site"))

    #expect(Self.text(files["v0/catalog.json"]) == bundle.catalog)
    #expect(Self.text(files["v0/manifest.json"]) == bundle.manifest)
  }

  @Test func theManifestHashIsTheHashOfTheCatalogFileOnDisk() throws {
    let workspace = try Workspace()
    try Self.build(into: workspace.directory("site"))
    let files = try Self.files(under: workspace.directory("site"))

    let hash = Checksum.sha256Hex(of: Array(files["v0/catalog.json"] ?? Data()))

    #expect(Self.text(files["v0/manifest.json"]).contains("\"sha256\": \"\(hash)\""))
  }

  @Test func theSchemaCopiesAreTheBytesOfTheSchemaFiles() throws {
    let workspace = try Workspace()
    try Self.build(into: workspace.directory("site"))
    let files = try Self.files(under: workspace.directory("site"))

    for name in ["device-profile.schema.json", "command-set.schema.json"] {
      #expect(files["v0/\(name)"] == (try Data(contentsOf: CatalogRepository.url.appendingPathComponent("schema/\(name)"))))
    }
  }

  @Test func theIndexPageIsTheRenderedPageForThePatch() throws {
    let workspace = try Workspace()
    let root = RepositoryRoot(url: CatalogRepository.url)
    try Self.build(into: workspace.directory("site"), patch: 17)

    #expect(Self.text(try Self.files(under: workspace.directory("site"))["index.html"]) == (try root.indexPage(patch: 17)))
  }

  @Test func twoBuildsWithTheSameInputWriteTheSameBytes() throws {
    let workspace = try Workspace()

    try Self.build(into: workspace.directory("first"))
    try Self.build(into: workspace.directory("second"))

    #expect(try Self.files(under: workspace.directory("first")) == (try Self.files(under: workspace.directory("second"))))
  }

  @Test func thePatchChangesTheManifestAndThePageButNotTheCatalog() throws {
    let workspace = try Workspace()

    try Self.build(into: workspace.directory("first"), patch: 1)
    try Self.build(into: workspace.directory("second"), patch: 2)
    let first = try Self.files(under: workspace.directory("first"))
    let second = try Self.files(under: workspace.directory("second"))

    #expect(first["v0/catalog.json"] == second["v0/catalog.json"])
    #expect(first["v0/manifest.json"] != second["v0/manifest.json"])
    #expect(first["index.html"] != second["index.html"])
    #expect(Self.text(first["v0/manifest.json"]).contains("\"version\": \"\(try Self.majorMinor()).1\""))
    #expect(Self.text(second["v0/manifest.json"]).contains("\"version\": \"\(try Self.majorMinor()).2\""))
  }

  @Test func theBuiltTimeIsInTheManifestOnlyWhenGiven() throws {
    let workspace = try Workspace()

    try Self.build(into: workspace.directory("with"), built: Self.built)
    try Self.build(into: workspace.directory("without"), built: nil)

    #expect(Self.text(try Self.files(under: workspace.directory("with"))["v0/manifest.json"]).contains(#""built": "2000-01-01T00:00:00Z""#))
    #expect(!Self.text(try Self.files(under: workspace.directory("without"))["v0/manifest.json"]).contains("built"))
  }

  @Test func theRegistryAndTheReviewedTitlesAreNotPublished() throws {
    let workspace = try Workspace()
    let documents = CatalogRepository.url.appendingPathComponent("documents")
    let names = try FileManager.default.contentsOfDirectory(atPath: documents.path)
    try Self.build(into: workspace.directory("site"))
    let published = try Self.files(under: workspace.directory("site"))

    #expect(names.contains { $0.contains("registry") })
    #expect(published.keys.allSatisfy { !$0.contains("registry") && !$0.contains("documents") && !$0.contains("reviewed") })
    #expect(published.keys.sorted() == Self.siteFiles)
  }

  @Test func aBuildReplacesWhatAnEarlierBuildWrote() throws {
    let workspace = try Workspace()
    let output = workspace.directory("site")
    try FileManager.default.createDirectory(at: output.appendingPathComponent("v0"), withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: output.appendingPathComponent("v0/catalog.json"))
    try Data("stale".utf8).write(to: output.appendingPathComponent("index.html"))

    try Self.build(into: output)
    let files = try Self.files(under: output)

    #expect(files["v0/catalog.json"] != Data("stale".utf8))
    #expect(files["index.html"] != Data("stale".utf8))
  }

  @Test func aProfileThatBreaksTheSchemaRefusesTheBuildAndWritesNothing() throws {
    let workspace = try Workspace()
    let repository = try workspace.copyOfCatalog()
    let file = try #require(try repository.deviceFiles().first)
    try Data("{}".utf8).write(to: repository.url.appendingPathComponent(file.path))

    let result = try Self.build(repository, into: workspace.directory("site"))

    guard case .refused(let problems) = result else {
      Issue.record("expected a refusal, got \(result)")
      return
    }
    #expect(!problems.isEmpty)
    #expect(problems.allSatisfy { $0.hasPrefix(file.name) })
    #expect(!FileManager.default.fileExists(atPath: workspace.directory("site").path))
  }

  @Test func aRefusedBuildLeavesAnExistingSiteAlone() throws {
    let workspace = try Workspace()
    let repository = try workspace.copyOfCatalog()
    let output = workspace.directory("site")
    try Self.build(repository, into: output)
    let before = try Self.files(under: output)
    try FileManager.default.removeItem(at: repository.url.appendingPathComponent("documents"))

    let result = try Self.build(repository, into: output, patch: 99)

    guard case .refused = result else {
      Issue.record("expected a refusal, got \(result)")
      return
    }
    #expect(try Self.files(under: output) == before)
  }

  @Test func aVersionThatIsNotMajorDotMinorStopsTheBuildBeforeAnythingIsWritten() throws {
    let workspace = try Workspace()
    let repository = try workspace.copyOfCatalog()
    try Data("1.2.3\n".utf8).write(to: repository.url.appendingPathComponent("VERSION"))

    #expect(throws: VersionProblem.malformed("1.2.3")) {
      try Self.build(repository, into: workspace.directory("site"))
    }
    #expect(!FileManager.default.fileExists(atPath: workspace.directory("site").path))
  }

  @Test func theMajorVersionNamesTheDirectory() throws {
    let workspace = try Workspace()
    let repository = try workspace.copyOfCatalog()
    try Data("7.0\n".utf8).write(to: repository.url.appendingPathComponent("VERSION"))

    try Self.build(repository, into: workspace.directory("site"))

    let files = try Self.files(under: workspace.directory("site"))
    #expect(files.keys.contains("v7/manifest.json"))
    #expect(Self.text(files["v7/manifest.json"]).contains(#""version": "7.0.3""#))
  }
}
