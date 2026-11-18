import CatalogBuild
import CatalogJSON
import Foundation

/// A scenario could not be set up.
public struct ScenarioError: Error, CustomStringConvertible {
  public let description: String
}

/// Applies a scenario's changes to a copy of the catalog and reports what the rules say about it.
public struct ScenarioRunner: Sendable {
  public let repository: URL

  public init(repository: URL) {
    self.repository = repository
  }

  /// What a copy of the repository holds: the data, the schemas and what the rules read besides.
  static let copied = ["schema", "devices", "commandSets", "documents", "templates", "VERSION"]

  /// The registry and the reviewed pairs, which scenarios may change as well as the data.
  static let documents = ["documents/registry.json", "documents/reviewed-distinct-titles.json"]

  /// The problems the rules report for the repository with the scenario's changes made.
  public func problems(for scenario: Scenario) throws -> [String] {
    let root = RepositoryRoot(url: repository)
    var files = try root.deviceFiles().map { (path: $0.path, value: $0.value) }
      + root.commandSetFiles().map { (path: $0.path, value: $0.value) }

    for path in Self.documents {
      let bytes = try [UInt8](Data(contentsOf: repository.appendingPathComponent(path)))
      files.append((path: path, value: try JSONParser.parse(bytes)))
    }

    guard let file = files.first(where: { $0.path == scenario.file }) else {
      throw ScenarioError(description: "\(scenario.name): \(scenario.file) is not a data file")
    }

    var value = file.value
    for change in scenario.changes {
      value = try change.applied(to: value)
    }

    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-scenario-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)

    for name in Self.copied {
      try FileManager.default.copyItem(at: repository.appendingPathComponent(name), to: copy.appendingPathComponent(name))
    }

    try Data((try JSONWriter.write(value) + "\n").utf8).write(to: copy.appendingPathComponent(scenario.file))

    return try RepositoryRoot(url: copy).problems()
  }
}
