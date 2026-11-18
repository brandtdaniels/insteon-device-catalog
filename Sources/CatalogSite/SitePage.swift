import CatalogJSON

/// What the landing page is built from.
public struct SiteInput: Sendable {
  /// The profiles, in file name order.
  public var profiles: [JSONValue]
  /// The command sets.
  public var commandSets: [JSONValue]
  /// Each capability kind's description, from the profile schema.
  public var capabilityDescriptions: [String: String]
  /// The catalog's version, `MAJOR.MINOR.PATCH`.
  public var version: String
  /// The major version, which names the folder the catalog is published in.
  public var major: String

  public init(profiles: [JSONValue], commandSets: [JSONValue], capabilityDescriptions: [String: String], version: String, major: String) {
    self.profiles = profiles
    self.commandSets = commandSets
    self.capabilityDescriptions = capabilityDescriptions
    self.version = version
    self.major = major
  }

  /// Each capability kind's description, read from the profile schema's `$defs.capability.oneOf`.
  public static func capabilityDescriptions(in schema: JSONValue) -> [String: String] {
    var descriptions: [String: String] = [:]

    for option in schema["$defs"]?["capability"]?.list("oneOf") ?? [] {
      if let kind = option["properties"]?["kind"]?["const"]?.string, let description = option["description"]?.string {
        descriptions[kind] = description
      }
    }

    return descriptions
  }
}

/// One card, by the profile's model.
public struct CardFragment: Equatable, Sendable {
  public let model: String
  public let html: String
}

/// One category's section and the cards in it.
public struct CategoryFragment: Equatable, Sendable {
  public let code: String
  public let html: String
  public let cards: [CardFragment]
}

/// The pieces the template is filled with, before they are put in it.
public struct PageFragments: Equatable, Sendable {
  public let coverage: String
  public let capabilities: String
  public let how: String
  public let categories: [CategoryFragment]
  public let verificationOptions: String
  public let categoryOptions: String
  public let engineOptions: String
  public let capabilityOptions: String
  public let count: Int

  /// The category sections, one after the other.
  public var sections: String {
    categories.map(\.html).joined(separator: "\n")
  }
}

/// Renders the landing page.
public enum SitePage {
  /// The page's pieces for the profiles and command sets.
  public static func fragments(_ input: SiteInput) throws(SiteError) -> PageFragments {
    let escape = HTMLEscaper.escape
    var commandSetsByID: [String: JSONValue] = [:]
    for commandSet in input.commandSets { commandSetsByID[commandSet.text("id")] = commandSet }

    var order: [String] = []
    var cards: [String: [CardFragment]] = [:]

    for profile in NaturalOrder.sorted(input.profiles, key: { $0.text("model") }) {
      let card = ProfileCard(profile: profile, commandSets: commandSetsByID, capabilityDescriptions: input.capabilityDescriptions)
      let category = card.category
      if cards[category] == nil { order.append(category) }
      cards[category, default: []].append(CardFragment(model: card.model, html: try card.html()))
    }

    var categories: [CategoryFragment] = []

    for code in order.codePointSorted() {
      let group = cards[code] ?? []
      var html = #"<section class="category" id="category-\#(code)" data-category="\#(code)">"#
      html += #"<h2>\#(escape(PageTables.categoryNames[code] ?? code))<span class="n">\#(group.count) product\#(group.count == 1 ? "" : "s")</span></h2>"#
      html += #"<p class="category-code">Category <span class="mono">\#(code)</span></p>"#
      if let description = PageTables.categoryDescriptions[code] { html += #"<p class="category-description">\#(escape(description))</p>"# }
      html += #"<div class="grid">\#(group.map(\.html).joined())</div></section>"#
      categories.append(CategoryFragment(code: code, html: html, cards: group))
    }

    let present = Set(input.profiles.flatMap { StatusMarks.statuses(in: $0) }.map(ExactText.init))
    let verification = PageTables.statuses.filter { present.contains(ExactText($0)) }
      .map { #"<option value="\#($0)">\#(PageText.capitalized($0))</option>"# }.joined()
    let usedEngines = Set(input.profiles.flatMap { $0.list("engines") }.map { ExactText($0.text("engine")) })
    let engines = PageTables.engineLabels.entries.filter { usedEngines.contains(ExactText($0.key)) }
      .map { #"<option value="\#($0.key)">\#($0.value)</option>"# }.joined()
    let kinds = Set(input.profiles.flatMap { $0.list("capabilities") }.map { $0.text("kind") }).codePointSorted()
    let capabilityOptions = kinds.map { #"<option value="\#($0)">\#(escape(PageTables.capabilityLabels[$0] ?? $0))</option>"# }.joined()
    let categoryOptions = categories.map { #"<option value="\#($0.code)">\#(escape(PageTables.categoryNames[$0.code] ?? $0.code))</option>"# }.joined()

    return PageFragments(
      coverage: try CoverageSummary(profiles: input.profiles, commandSets: input.commandSets).html,
      capabilities: Legend(profiles: input.profiles).html,
      how: HowSection.html,
      categories: categories,
      verificationOptions: verification,
      categoryOptions: categoryOptions,
      engineOptions: engines,
      capabilityOptions: capabilityOptions,
      count: input.profiles.count
    )
  }

  /// The landing page: what the catalog is, how to download it, and a card for each profile to
  /// search and filter.
  public static func render(_ input: SiteInput, template: Template) throws(SiteError) -> String {
    let fragments = try fragments(input)

    return try template.substitute([
      "version": input.major,
      "catalog_version": input.version,
      "count": String(fragments.count),
      "coverage": fragments.coverage,
      "capabilities": fragments.capabilities,
      "how": fragments.how,
      "verification_options": fragments.verificationOptions,
      "sections": fragments.sections,
      "category_options": fragments.categoryOptions,
      "engine_options": fragments.engineOptions,
      "capability_options": fragments.capabilityOptions
    ])
  }
}
