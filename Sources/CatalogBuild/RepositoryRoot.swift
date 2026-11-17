import CatalogJSON
import CatalogSchema
import Foundation

/// A data file of the catalog, read into a ``JSONValue``.
public struct CatalogFile: Equatable, Sendable {
  /// The file name with its extension, such as `2442-222.json`.
  public let name: String
  /// The file name without `.json`.
  public let stem: String
  /// The path from the repository root, such as `devices/2442-222.json`.
  public let path: String
  /// The parsed contents.
  public let value: JSONValue
}

/// Why a repository file can't be read.
public enum RepositoryError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The file can't be read from disk.
  case unreadable(file: String, reason: String)
  /// The file is not strict JSON.
  case unparseable(file: String, JSONParseError)

  public var description: String {
    switch self {
    case .unreadable(let file, let reason):
      "\(file): \(reason)"
    case .unparseable(let file, let error):
      "\(file): \(error)"
    }
  }
}

/// The two schemas that describe the catalog's data files.
public enum CatalogSchemaKind: String, Sendable {
  case deviceProfile = "device-profile"
  case commandSet = "command-set"
}

/// The catalog repository on disk: where its data files are and how they are listed.
public struct RepositoryRoot: Sendable {
  /// The directory that holds `devices/`, `commandSets/` and `schema/`.
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// The profiles in `devices/`, in file name order.
  public func deviceFiles() throws(RepositoryError) -> [CatalogFile] {
    try files(in: "devices")
  }

  /// The command sets in `commandSets/`, in file name order.
  public func commandSetFiles() throws(RepositoryError) -> [CatalogFile] {
    try files(in: "commandSets")
  }

  /// The schema file for a kind of data file.
  public func schema(_ kind: CatalogSchemaKind) throws(RepositoryError) -> JSONValue {
    try read("schema/\(kind.rawValue).schema.json")
  }

  /// Every `.json` file directly inside the directory, sorted by file name in code point order.
  ///
  /// The order is by file name and not by model, so `2442-222.json` comes before `2442.json`
  /// because `-` sorts before `.`. A directory that does not exist holds no files.
  private func files(in directory: String) throws(RepositoryError) -> [CatalogFile] {
    let folder = url.appendingPathComponent(directory)
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: []
    ) else { return [] }

    let names = entries
      .filter { $0.pathExtension == "json" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
      .map(\.lastPathComponent)
      .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }

    return try names.map { name throws(RepositoryError) in
      let path = "\(directory)/\(name)"
      return CatalogFile(name: name, stem: String(name.dropLast(".json".count)), path: path, value: try read(path))
    }
  }

  private func read(_ path: String) throws(RepositoryError) -> JSONValue {
    let bytes: [UInt8]
    do {
      bytes = try [UInt8](Data(contentsOf: url.appendingPathComponent(path)))
    } catch {
      throw .unreadable(file: path, reason: "the file can't be read")
    }
    do {
      return try JSONParser.parse(bytes)
    } catch {
      throw .unparseable(file: path, error)
    }
  }
}
