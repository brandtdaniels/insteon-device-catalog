import CatalogJSON

/// One profile's card on the page.
struct ProfileCard {
  let profile: JSONValue
  let commandSets: [String: JSONValue]
  let capabilityDescriptions: [String: String]

  var model: String { profile.text("model") }

  /// The category the profile is listed under: the category of its first identity.
  var category: String { profile.list("identities").first?.text("category") ?? "" }

  /// The statuses the profile's own values carry, in the page's order.
  var statuses: [String] {
    let marked = Set(StatusMarks.statuses(in: profile).map(ExactText.init))
    return PageTables.statuses.filter { marked.contains(ExactText($0)) }
  }

  func html() throws(SiteError) -> String {
    let escape = HTMLEscaper.escape
    let kinds = profile.list("capabilities").map { $0.text("kind") }
    let aliases = profile.list("aliases").compactMap(\.string)
    let statuses = self.statuses

    var marks = ""
    for status in statuses {
      let explanation = escape(PageTables.statusExplanations[status] ?? "")
      marks += #"<span class="status pill status-\#(status)" title="\#(explanation)">\#(PageText.capitalized(status))</span>"#
    }

    var chips = ""
    for kind in kinds {
      let description = escape(capabilityDescriptions[kind] ?? "")
      chips += #"<span class="chip pill" title="\#(description)">\#(escape(PageTables.capabilityLabels[kind] ?? kind))</span>"#
    }

    var words = [model, profile.text("name")] + aliases
    for identity in profile.list("identities") { words.append("\(identity.text("category"))/\(identity.text("subcategory"))") }
    words += profile.list("engines").map { $0.text("engine") }
    words += kinds.map { PageTables.capabilityLabels[$0] ?? $0 }
    if let radio = profile["radio"]?.string { words.append(PageTables.radioLabels[radio] ?? "") }
    if let role = profile["role"]?.string { words.append(PageTables.roleLabels[role] ?? "") }
    if profile.isSet("batteryPowered") { words.append("battery powered") }

    let engines = Set(profile.list("engines").map { ExactText($0.text("engine")) }).map { String(decoding: $0.utf8, as: UTF8.self) }
    let attributes: [(String, String)] = [
      ("search", PythonCase.lowercased(words.joined(separator: " "))),
      ("capabilities", kinds.joined(separator: " ")),
      ("engines", engines.codePointSorted().joined(separator: " ")),
      ("radio", profile["radio"]?.string ?? ""),
      ("battery", profile.isSet("batteryPowered") ? "true" : "false"),
      ("verification", statuses.joined(separator: " "))
    ]
    let data = attributes.map { #"data-\#($0.0)="\#(escape($0.1))""# }.joined(separator: " ")

    var html = #"<article class="card" data-model="\#(escape(model))" \#(data)>"#
    html += #"<div class="top"><span class="model mono">\#(escape(model))</span><span class="chips">\#(chips)</span></div>"#
    html += "<h3>\(escape(profile.text("name")))</h3>"
    if !aliases.isEmpty { html += #"<p class="aliases">Also known as \#(escape(aliases.joined(separator: ", ")))</p>"# }
    if let description = profile["description"] { html += #"<p class="description">\#(escape(description.string ?? ""))</p>"# }
    if !marks.isEmpty { html += #"<p class="marks"><span class="marks-label">Marked values</span> \#(marks)</p>"# }
    html += #"<details class="more"><summary>What the catalog describes</summary>"#
    html += try CardDetail(profile: profile, commandSets: commandSets).html()
    html += "</details>"
    html += "</article>"
    return html
  }
}
