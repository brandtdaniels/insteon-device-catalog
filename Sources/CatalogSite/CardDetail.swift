import Foundation
import CatalogJSON

/// A card's "What the catalog describes" groups: hardware, ALL-Link groups and events, what
/// software can read or write, then the identities. Each fact is stated once; a column that differs
/// between identities is in the identity table, and the hardware row points to it.
struct CardDetail {
  let profile: JSONValue
  let commandSets: [String: JSONValue]

  /// One identity's row of the identity table.
  private struct IdentityRow {
    var subcategory: String
    var soldIn: String
    var commandSet: String
    var engine: String

    func value(of column: Column) -> String {
      switch column {
      case .subcategory: subcategory
      case .soldIn: soldIn
      case .commandSet: commandSet
      case .engine: engine
      }
    }
  }

  private enum Column: String, CaseIterable {
    case subcategory = "Subcategory"
    case soldIn = "Sold in"
    case commandSet = "Command set"
    case engine = "Engine"
  }

  /// One row per identity: its subcategory, where it is sold, its command sets and its engine.
  private func identityRows() throws(SiteError) -> [IdentityRow] {
    let identities = profile.list("identities")
    let category = identities.first?.text("category") ?? ""
    var rows: [IdentityRow] = []

    func belongs(_ entry: JSONValue, to identity: JSONValue) -> Bool {
      ExactText(entry.text("category")) == ExactText(identity.text("category"))
        && ExactText(entry.text("subcategory")) == ExactText(identity.text("subcategory"))
    }

    for identity in identities {
      let code = ExactText(identity.text("category")) == ExactText(category)
        ? identity.text("subcategory") : "\(identity.text("category"))/\(identity.text("subcategory"))"
      var where_: [String] = []

      if let region = identity["region"] { where_.append(region.string ?? "") }

      if let firmware = identity["firmware"] {
        where_.append("firmware \(firmware.text("from")) to \(firmware.text("through"))")
      }

      var settings: [String] = []
      for entry in profile.list("commandSets") where belongs(entry, to: identity) {
        guard let set = commandSets[entry.text("commandSet")] else { throw .missingCommandSet(entry.text("commandSet")) }
        settings.append(set.text("name") + (entry.has("firmware") ? " (some firmware)" : ""))
      }

      let engines = profile.list("engines").filter { belongs($0, to: identity) }.map { PageText.engineNote($0).label }

      rows.append(IdentityRow(
        subcategory: code, soldIn: where_.joined(separator: ", "), commandSet: settings.joined(separator: ", "),
        engine: engines.joined(separator: ", ")
      ))
    }

    return rows
  }

  /// What a command set covers: the figure, its noun and its labels for each part it holds.
  /// Operating flags, extended settings and readings carry their labels; the commands are only
  /// counted.
  private func facts(of commandSet: JSONValue) -> [(name: String, count: Int, noun: String, labels: [String])] {
    let settings = commandSet["extendedSettings"]
    let perButton = settings?.isSet("perButton") ?? false
    let parts: [(String, String, [JSONValue])] = [
      ("operatingFlags", "operating flag", commandSet.list("operatingFlags")),
      ("extendedSettings", "extended setting", settings?.list("values") ?? []),
      ("standardCommands", "standard command", commandSet.list("standardCommands")),
      ("extendedCommands", "extended command", commandSet.list("extendedCommands")),
      ("serialCommands", "serial command", commandSet.list("serialCommands")),
      ("readings", "reading", commandSet.list("readings"))
    ]
    let named: Set<String> = ["operatingFlags", "extendedSettings", "readings"]
    var found: [(name: String, count: Int, noun: String, labels: [String])] = []

    for name in PageTables.commandSetFacts {
      guard let (_, noun, entries) = parts.first(where: { $0.0 == name }), !entries.isEmpty else { continue }

      let counted = PageText.countNoun(entries.count, noun)
      let plural = String(counted.drop(while: { $0 != " " }).dropFirst())
      let text = plural + (name == "extendedSettings" && perButton ? ", set per button" : "")
      found.append((name, entries.count, text, named.contains(name) ? entries.map { $0.text("label") } : []))
    }

    return found
  }

  /// The groups, as the card's detail markup.
  func html() throws(SiteError) -> String {
    let escape = HTMLEscaper.escape
    let rows = try identityRows()

    func varies(_ column: Column) -> Bool {
      Set(rows.map { ExactText($0.value(of: column)) }).count > 1
    }

    func group(_ name: String, _ title: String, _ body: String) -> String {
      #"<section data-group="\#(name)"><h4>\#(title)</h4>\#(body)</section>"#
    }

    func row(_ term: String, _ fact: String, _ value: String) -> String {
      #"<dt>\#(term)</dt><dd data-fact="\#(fact)">\#(escape(value))</dd>"#
    }

    let engines = rows.map(\.engine).filter { !$0.isEmpty }.uniqued()
    let engine = varies(.engine) ? "Varies by identity" : engines.isEmpty ? "Not stated" : engines.joined(separator: ", ")
    var hardware = row("Radio", "radio", profile["radio"]?.string.flatMap { PageTables.radioLabels[$0] } ?? "Not stated")
    hardware += row("Role", "role", profile["role"]?.string.flatMap { PageTables.roleLabels[$0] } ?? "Not stated")
    hardware += row("Engine", "engine", engine)
    if profile.isSet("batteryPowered") { hardware += row("Battery", "battery", "Battery powered") }

    let allowed = ["controller": "controller", "responder": "responder", "both": "controller and responder"]
    let groups = profile.list("groups")
    var link = #"<dl class="rows">"#

    if groups.isEmpty {
      link += #"<dt>Groups</dt><dd data-fact="noGroups">None listed</dd>"#
    } else {
      link += "<dt>Groups</dt><dd><ul>"
      for item in groups {
        let number = PageText.number(ofHex: item.text("number"))
        link += #"<li data-fact="group">\#(number) \#(escape(item.text("name"))) (\#(allowed[item.text("role")] ?? ""))</li>"#
      }
      link += "</ul></dd>"
    }

    let events = profile.list("capabilities").filter { $0.text("kind") == "groupEvents" }.flatMap { $0.list("events") }

    if !events.isEmpty {
      link += "<dt>Reports</dt><dd><ul>"
      for event in events {
        let group = PageText.number(ofHex: event.text("group"))
        link += #"<li data-fact="event">\#(escape(event.text("event"))) (group \#(group), command \#(escape(event.text("command1"))))</li>"#
      }
      link += "</ul></dd>"
    }

    for capability in profile.list("capabilities") where capability.text("kind") == "heartbeat" {
      var interval = ""
      if let minutes = capability["intervalMinutes"]?.integer { interval = " every \(PageText.countNoun(minutes, "minute"))" }
      link += row("Heartbeat", "heartbeat", "group \(PageText.number(ofHex: capability.text("group")))\(interval)")
    }

    link += "</dl>"

    var software = ""
    let setIDs = profile.list("commandSets").map { $0.text("commandSet") }.uniqued()

    if setIDs.isEmpty {
      software += #"<p data-fact="noCommandSet">The catalog has no command set for this device.</p>"#
    }

    for setID in setIDs {
      guard let commandSet = commandSets[setID] else { throw .missingCommandSet(setID) }
      let parts = facts(of: commandSet)
      let label = #"<p class="set-name">\#(escape(commandSet.text("name")))</p>"#

      guard !parts.isEmpty else {
        software += #"<div class="command-set" data-command-set="\#(escape(setID))">\#(label)"#
        software += #"<p data-fact="noSettings">The catalog deliberately holds no settings for this device: there is nothing for software to read or write.</p></div>"#
        continue
      }

      var figures = ""
      for part in parts {
        figures += #"<li data-fact="\#(part.name)"><strong>\#(part.count)</strong> \#(escape(part.noun))</li>"#
      }

      var lists = ""
      for part in parts where !part.labels.isEmpty {
        lists += #"<details class="list" data-list="\#(part.name)"><summary>\#(PageTables.listTitles[part.name] ?? "")</summary><ul class="names">"#
        for item in part.labels { lists += "<li>\(escape(item))</li>" }
        lists += "</ul></details>"
      }

      let columns = parts.count > 4 ? min(parts.count, 3) : parts.count
      software += #"<div class="command-set" data-command-set="\#(escape(setID))">\#(label)<ul class="figures" style="--figures: \#(columns)">\#(figures)</ul>\#(lists)</div>"#
    }

    var shared: [String] = []
    var columns = [Column.subcategory]

    for column in [Column.soldIn, .commandSet, .engine] {
      if varies(column) {
        columns.append(column)
      } else if let first = rows.first, !first.value(of: column).isEmpty, column == .soldIn {
        shared.append(row(column.rawValue, "soldIn", first.value(of: column)))
      }
    }

    var identity: String

    if rows.count == 1 {
      let subcategory = row("Subcategory", "subcategory", rows[0].subcategory).replacingFirstOccurrence(of: "<dd ", with: #"<dd class="mono" "#)
      identity = #"<dl class="rows">\#(subcategory)\#(shared.joined())</dl>"#
    } else {
      var table = #"<table class="identity-table"><tr>"#
      for column in columns { table += "<th>\(column.rawValue)</th>" }
      table += "</tr>"
      for item in rows {
        table += "<tr>"
        for column in columns {
          table += "<td\(column == .subcategory ? #" class="mono""# : "")>\(escape(item.value(of: column)))</td>"
        }
        table += "</tr>"
      }
      table += "</table>"
      identity = (shared.isEmpty ? "" : #"<dl class="rows">"# + shared.joined() + "</dl>") + table
    }

    var html = #"<div class="groups">"#
    html += group("hardware", "Hardware", #"<dl class="rows">\#(hardware)</dl>"#)
    html += group("allLink", "ALL-Link groups and events", link)
    html += group("software", "What software can read or write", software)
    html += group("identity", "Identity", identity)
    html += "</div>"
    return html
  }
}

extension String {
  /// The text with the first occurrence of `target` replaced.
  func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
    guard let range = range(of: target) else { return self }
    return replacingCharacters(in: range, with: replacement)
  }
}
