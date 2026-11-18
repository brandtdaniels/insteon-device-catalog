import CatalogJSON

/// The `verification` marks in a value.
enum StatusMarks {
  /// The status of every `verification` in the value, nested at any depth, in the order they
  /// appear. A `verification` that is a list of marks counts each mark.
  static func statuses(in value: JSONValue) -> [String] {
    var found: [String] = []

    func visit(_ node: JSONValue, key: String?) {
      switch node {
      case .object(let members):
        if key == "verification", let status = node["status"] {
          found.append(status.string ?? "")
        }
        for member in members { visit(member.value, key: member.key) }
      case .array(let elements):
        for element in elements { visit(element, key: key) }
      default:
        break
      }
    }

    visit(value, key: nil)
    return found
  }

  /// How many of each status are in `statuses`, in the page's order.
  static func counts(_ statuses: [String]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: PageTables.statuses.map { status in
      (status, statuses.filter { ExactText($0) == ExactText(status) }.count)
    })
  }
}

/// What the catalog covers, counted from its data.
///
/// A value with no `verification` is documented, so an identity without one counts as documented.
/// A command set's values are counted only where they carry a mark. A profile has a command set
/// when one of its entries names a command set that describes behavior, and deliberately has none
/// when every entry names a command set that says there is nothing to read or write.
public struct CoverageSummary: Equatable, Sendable {
  public let profiles: Int
  public let identities: Int
  public let described: Int
  public let deliberatelyEmpty: Int
  public let undescribed: Int
  public let commandSetStatuses: [String: Int]
  public let identityStatuses: [String: Int]

  public init(profiles: [JSONValue], commandSets: [JSONValue]) throws(SiteError) {
    var describesBehavior: [String: Bool] = [:]

    for commandSet in commandSets {
      let keys = Set(commandSet.members.map(\.key))
      describesBehavior[commandSet.text("id")] = !keys.subtracting(PageTables.commandSetDescriptiveKeys).isEmpty
    }

    var described = 0
    var deliberatelyEmpty = 0

    for profile in profiles {
      var entries: [Bool] = []

      for entry in profile.list("commandSets") {
        guard let behavior = describesBehavior[entry.text("commandSet")] else { throw .missingCommandSet(entry.text("commandSet")) }
        entries.append(behavior)
      }

      described += entries.contains(true) ? 1 : 0
      deliberatelyEmpty += !entries.isEmpty && !entries.contains(true) ? 1 : 0
    }

    let identities = profiles.flatMap { $0.list("identities") }

    self.profiles = profiles.count
    self.identities = identities.count
    self.described = described
    self.deliberatelyEmpty = deliberatelyEmpty
    self.undescribed = profiles.count - described - deliberatelyEmpty
    self.commandSetStatuses = StatusMarks.counts(commandSets.flatMap { StatusMarks.statuses(in: $0) })
    self.identityStatuses = StatusMarks.counts(identities.map { $0["verification"]?["status"]?.string ?? "documented" })
  }

  /// The page's coverage summary: the counts and a table of statuses.
  var html: String {
    func number(_ metric: String, _ value: Int) -> String {
      #"<span data-metric="\#(metric)">\#(value)</span>"#
    }

    var rows = ""

    for status in PageTables.statuses {
      rows += #"<tr><th scope="row"><span class="status pill status-\#(status)">\#(PageText.capitalized(status))</span></th>"#
      rows += "<td>\(HTMLEscaper.escape(PageTables.statusExplanations[status] ?? ""))</td>"
      rows += #"<td class="num">\#(number("commandSet-\(status)", commandSetStatuses[status] ?? 0))</td>"#
      rows += #"<td class="num">\#(number("identity-\(status)", identityStatuses[status] ?? 0))</td></tr>"#
    }

    var html = #"<section class="coverage" aria-labelledby="coverage-heading">"#
    html += #"<h2 id="coverage-heading">What the catalog covers</h2>"#
    html += #"<ul class="totals">"#
    html += "<li><strong>\(number("profiles", profiles))</strong> profiles</li>"
    html += "<li><strong>\(number("identities", identities))</strong> identities (category, subcategory and firmware a device can report)</li>"
    html += "<li><strong>\(number("described", described))</strong> profiles with a command set</li>"
    html += "<li><strong>\(number("deliberatelyEmpty", deliberatelyEmpty))</strong> profiles that deliberately have none, because there is nothing to read or write</li>"
    html += "<li><strong>\(number("undescribed", undescribed))</strong> profiles with no command set in the catalog, which are gaps</li>"
    html += "</ul>"
    html += #"<table class="statuses-table"><caption>How sure the catalog is of what it states</caption>"#
    html += #"<thead><tr><th scope="col">Status</th><th scope="col">Meaning</th><th scope="col" class="num">Command set values</th><th scope="col" class="num">Identities</th></tr></thead>"#
    html += "<tbody>\(rows)</tbody></table>"
    html += #"<p class="note">A command set value or profile entry with no mark is documented. The command set column counts only values that carry a mark. "#
    html += "The identities column counts every identity. An identity with no mark is counted as documented: it is read from the documents the profile cites, not confirmed on a device.</p>"
    html += "</section>"
    return html
  }
}
