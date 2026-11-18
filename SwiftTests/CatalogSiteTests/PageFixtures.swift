@testable import CatalogBuild
import CatalogJSON
import Foundation

@testable import CatalogSite

/// The catalog's own data and the page rendered from it, read once for the page suites.
enum CatalogPage {
  static let root = RepositoryRoot(url: CatalogRepository.url)
  static let profiles: [JSONValue] = ((try? root.deviceFiles()) ?? []).map(\.value)
  static let commandSets: [JSONValue] = ((try? root.commandSetFiles()) ?? []).map(\.value)
  static let descriptions: [String: String] = {
    guard let schema = try? root.schema(.deviceProfile) else { return [:] }
    return SiteInput.capabilityDescriptions(in: schema)
  }()
  static let template: Template = {
    let text = (try? String(contentsOf: CatalogRepository.url.appendingPathComponent("templates/index.html"), encoding: .utf8)) ?? ""
    return Template(text)
  }()

  /// The page for these profiles and command sets, as the build writes it for version 0.0.0.
  static func render(_ profiles: [JSONValue], _ commandSets: [JSONValue]) throws -> String {
    try SitePage.render(
      SiteInput(profiles: profiles, commandSets: commandSets, capabilityDescriptions: descriptions, version: "0.0.0", major: "0"),
      template: template
    )
  }

  static let page: String = (try? render(profiles, commandSets)) ?? ""
  static let reader = PageReader(page)
  static let cards = CardReader(page).cards

  static func profile(_ model: String) -> JSONValue {
    profiles.first { $0.text("model") == model } ?? .null
  }

  /// A data file read from disk by its folder and name.
  static func disk(_ folder: String, _ name: String) -> JSONValue {
    (try? root.read("\(folder)/\(name).json")) ?? .null
  }
}
