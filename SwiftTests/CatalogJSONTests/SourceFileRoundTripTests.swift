import CatalogJSON
import Foundation
import Testing

/// The JSON files the repository keeps, read with the strict parser and written back.
struct SourceFileRoundTripTests {
  /// The repository root, found from this file's location.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  /// Directories whose files the tooling writes, so each is exactly what the writer produces.
  static let writtenDirectories = ["devices", "commandSets", "schema", "documents"]

  /// Directories and files laid out by hand or by another program. They parse strictly and keep
  /// their meaning when rewritten, but their bytes are not the writer's.
  static let handFormatted = ["documents/reviewed-distinct-titles.json", "SwiftTests/CatalogIngestTests/Golden/observations"]

  static func jsonFiles(under directory: String) -> [String] {
    let base = root.appendingPathComponent(directory)
    guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
    var paths: [String] = []
    for case let url as URL in walker where url.pathExtension == "json" {
      paths.append(directory + String(url.path.dropFirst(base.path.count)))
    }
    return paths
  }

  static let handFormattedFiles: [String] = handFormatted
    .flatMap { $0.hasSuffix(".json") ? [$0] : jsonFiles(under: $0) }
    .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }

  /// Repository-relative paths of the files the writer must reproduce, in code point order.
  static let writtenFiles: [String] = writtenDirectories
    .flatMap(jsonFiles(under:))
    .filter { !handFormattedFiles.contains($0) }
    .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }

  static func bytes(of path: String) throws -> [UInt8] {
    try [UInt8](Data(contentsOf: root.appendingPathComponent(path)))
  }

  @Test func findsFilesInEveryDirectory() {
    for directory in Self.writtenDirectories {
      #expect(Self.writtenFiles.contains { $0.hasPrefix(directory + "/") }, "no JSON files under \(directory)")
    }
    #expect(!Self.handFormattedFiles.isEmpty)
  }

  @Test(arguments: writtenFiles)
  func writesBackTheSameBytes(path: String) throws {
    let original = try Self.bytes(of: path)
    let written = try JSONWriter.write(JSONParser.parse(original)) + "\n"
    #expect(Array(written.utf8) == original)
  }

  @Test(arguments: handFormattedFiles)
  func keepsItsMeaningWhenWrittenBack(path: String) throws {
    let value = try JSONParser.parse(Self.bytes(of: path))
    let rewritten = try JSONWriter.write(value) + "\n"
    #expect(try JSONParser.parse(rewritten) == value)
  }
}
