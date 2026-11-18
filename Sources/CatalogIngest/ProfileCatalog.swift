import CatalogBuild
import CatalogJSON
import Foundation

/// The catalog's profiles by model, as drafting reads and updates them.
public struct ProfileCatalog: Equatable, Sendable {
  public var profiles: [String: JSONValue]

  public init(profiles: [String: JSONValue]) {
    self.profiles = profiles
  }

  /// Every profile in `devices/`, by file name without `.json`.
  public static func load(from root: RepositoryRoot) throws(RepositoryError) -> ProfileCatalog {
    ProfileCatalog(profiles: Dictionary(uniqueKeysWithValues: try root.deviceFiles().map { ($0.stem, $0.value) }))
  }

  /// The model numbers of the profiles in `devices/`, which are their file names without `.json`.
  public static func models(in root: URL) -> Set<String> {
    let folder = root.appendingPathComponent("devices")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []

    return Set(names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(".json".count)) })
  }
}

/// A profile file as the repository writes it.
public enum ProfileFile {
  /// Two-space indent, characters as written, members in order, and one final newline.
  public static func text(of profile: JSONValue) -> String {
    ((try? JSONWriter.write(profile)) ?? "") + "\n"
  }
}
