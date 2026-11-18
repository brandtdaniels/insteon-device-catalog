import CatalogJSON

/// The page's legend: what each capability, radio, power source and engine means, and how many
/// profiles have it, counted from the data.
struct Legend {
  let profiles: [JSONValue]

  var html: String {
    func number(_ metric: String, _ value: Int) -> String {
      #"<span data-metric="\#(metric)">\#(value)</span>"#
    }

    func term(_ label: String, _ metric: String, _ count: Int, _ sentence: String) -> String {
      var html = "<dt>\(HTMLEscaper.escape(label)) "
      html += #"<span class="count-inline">\#(number(metric, count)) \#(count == 1 ? "profile" : "profiles")</span></dt>"#
      html += "<dd>\(HTMLEscaper.escape(sentence))</dd>"
      return html
    }

    func count(_ test: (JSONValue) -> Bool) -> Int {
      profiles.filter(test).count
    }

    var capabilities = ""
    for (kind, sentence) in PageTables.capabilityExplanations.entries {
      let total = count { $0.list("capabilities").contains { $0.text("kind") == kind } }
      capabilities += term(PageTables.capabilityLabels[kind] ?? kind, "capability-\(kind)", total, sentence)
    }

    let power = term("Battery powered", "battery", count { $0.isSet("batteryPowered") }, PageTables.batteryExplanation)

    var radios = ""
    for (radio, sentence) in PageTables.radioExplanations.entries {
      let total = count { radio == "unstated" ? !$0.has("radio") : $0["radio"]?.string == radio }
      radios += term(PageTables.radioLabels[radio] ?? "Radio not stated", "radio-\(radio)", total, sentence)
    }

    var engines = ""
    for (engine, sentence) in PageTables.engineExplanations.entries {
      let total = count { $0.list("engines").contains { $0.text("engine") == engine } }
      engines += term(PageTables.engineLabels[engine] ?? engine, "engine-\(engine)", total, sentence)
    }

    var html = #"<section class="capabilities" aria-labelledby="capabilities-heading">"#
    html += #"<h2 id="capabilities-heading">What the filters mean</h2>"#
    html += #"<p class="note">Each term below is a filter on the products. The count is how many profiles carry it, taken from the catalog's data. "#
    html += #"Open a card's "What the catalog describes" section to see what the catalog holds for that device.</p>"#
    html += #"<div class="legend">"#
    html += "<div><h3>Capabilities</h3><dl>\(capabilities)</dl></div>"
    html += "<div><h3>Radio and power</h3><dl>\(radios)\(power)</dl></div>"
    html += "<div><h3>Engines</h3><dl>\(engines)</dl></div>"
    html += "</div></section>"
    return html
  }
}
