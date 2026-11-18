import CatalogBuild
import CatalogJSON
import Foundation

extension RepositoryRoot {
  /// What the landing page is built from, read from the repository: its profiles and command sets,
  /// the capability descriptions in the profile schema, and the version `MAJOR.MINOR` from
  /// `VERSION` with `patch` appended.
  public func siteInput(patch: Int) throws -> SiteInput {
    let version = try majorMinor()

    return SiteInput(
      profiles: try deviceFiles().map(\.value),
      commandSets: try commandSetFiles().map(\.value),
      capabilityDescriptions: SiteInput.capabilityDescriptions(in: try schema(.deviceProfile)),
      version: "\(version).\(patch)",
      major: String(version.prefix { $0 != "." })
    )
  }

  /// The template the page is filled into.
  public func pageTemplate() throws -> Template {
    let url = self.url.appendingPathComponent("templates/index.html")

    guard let data = try? Data(contentsOf: url) else { throw SiteError.unreadableTemplate("templates/index.html") }

    // A text file read in text mode has its line ends made into newlines.
    let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    return Template(text)
  }

  /// The landing page for the repository's data, as the build writes `index.html`.
  public func indexPage(patch: Int) throws -> String {
    try SitePage.render(try siteInput(patch: patch), template: try pageTemplate())
  }

  /// `MAJOR.MINOR` from the `VERSION` file.
  func majorMinor() throws -> String {
    guard let data = try? Data(contentsOf: url.appendingPathComponent("VERSION")) else { throw SiteError.unreadableTemplate("VERSION") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
