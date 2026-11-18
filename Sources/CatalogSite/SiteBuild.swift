import CatalogBuild
import CatalogJSON
import Foundation

/// What a site build did.
public enum SiteBuildResult: Equatable, Sendable {
  /// The catalog has problems, one line each. Nothing was written.
  case refused([String])
  /// The site was written for this many profiles and command sets.
  case written(profiles: Int, commandSets: Int)
}

extension RepositoryRoot {
  /// Checks the catalog, then writes the site it publishes into `output`.
  ///
  /// The site holds `index.html` and a `v<MAJOR>` directory with `catalog.json`, `manifest.json` and
  /// copies of the two schemas. Documents, such as the registry, are not published. A catalog with
  /// problems writes nothing. Files from an earlier build are replaced.
  ///
  /// - Parameters:
  ///   - output: The directory the site goes in. It and its parents are created when missing.
  ///   - patch: The version's last number.
  ///   - built: When the catalog was built, as the manifest names it; it names nothing when `nil` or empty.
  public func buildSite(into output: URL, patch: Int, built: String? = nil) throws -> SiteBuildResult {
    let version = try majorMinor()
    _ = try CatalogBundle.major(of: version)

    let problems = try problems()
    guard problems.isEmpty else { return .refused(problems) }

    let profiles = try deviceFiles().map(\.value)
    let commandSets = try commandSetFiles().map(\.value)
    let bundle = try CatalogBundle(profiles: profiles, commandSets: commandSets, version: version, patch: patch, built: built)
    let page = try indexPage(patch: patch)
    let directory = output.appendingPathComponent(bundle.directoryName, isDirectory: true)
    var files: [(URL, Data)] = [
      (directory.appendingPathComponent(CatalogBundle.catalogFileName), Data(bundle.catalog.utf8)),
      (directory.appendingPathComponent("manifest.json"), Data(bundle.manifest.utf8))
    ]

    for kind in [CatalogSchemaKind.deviceProfile, .commandSet] {
      let name = "\(kind.rawValue).schema.json"
      files.append((directory.appendingPathComponent(name), try Data(contentsOf: url.appendingPathComponent("schema/\(name)"))))
    }

    files.append((output.appendingPathComponent("index.html"), Data(page.utf8)))

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for (file, data) in files {
      try data.write(to: file)
    }

    return .written(profiles: profiles.count, commandSets: commandSets.count)
  }
}
