import Foundation

/// Where two site directories first differ.
public enum SiteDifference: Equatable, Sendable, CustomStringConvertible {
  /// The Swift site has a file the Python site lacks.
  case onlyInSwift(String)
  /// The Python site has a file the Swift site lacks.
  case onlyInPython(String)
  /// A file both sites have holds different bytes.
  case bytes(file: String, PageDifference)

  public var description: String {
    switch self {
    case .onlyInSwift(let path): "\(path) is only in the Swift site"
    case .onlyInPython(let path): "\(path) is only in the Python site"
    case .bytes(let file, let difference): "\(file): \(difference)"
    }
  }
}

/// Compares the site the Swift build wrote with the site the Python build wrote, file by file.
public enum SiteComparison {
  /// The first difference between the directories, in path order, or `nil` when both hold the same
  /// files with the same bytes. A file one side lacks comes before any byte difference in a later path.
  public static func firstDifference(swift: URL, python: URL) throws -> SiteDifference? {
    let swiftFiles = try files(under: swift)
    let pythonFiles = try files(under: python)

    for path in Set(swiftFiles.keys).union(pythonFiles.keys).sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
      switch (swiftFiles[path], pythonFiles[path]) {
      case (_?, nil): return .onlyInSwift(path)
      case (nil, _?): return .onlyInPython(path)
      case (let swiftBytes?, let pythonBytes?):
        if let difference = PageComparison.firstDifference(swift: swiftBytes, python: pythonBytes) {
          return .bytes(file: path, difference)
        }
      case (nil, nil): break
      }
    }

    return nil
  }

  /// Every file under `directory`, by its path from `directory`. A directory that doesn't exist holds none.
  public static func files(under directory: URL) throws -> [String: [UInt8]] {
    let root = directory.resolvingSymlinksInPath().path
    var found: [String: [UInt8]] = [:]

    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return found }

    while let item = enumerator.nextObject() as? URL {
      guard try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true else { continue }
      found[String(item.resolvingSymlinksInPath().path.dropFirst(root.count + 1))] = [UInt8](try Data(contentsOf: item))
    }

    return found
  }
}
