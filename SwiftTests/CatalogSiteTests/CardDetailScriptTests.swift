import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// The full details a card shows when it is opened, which the page's script writes from the
/// published catalog.
struct CardDetailScriptTests {
  static let files = (try? CatalogPage.root.deviceFiles()) ?? []
  static let setFiles = (try? CatalogPage.root.commandSetFiles()) ?? []

  /// The details of every profile in the catalog, by model, from one run of the script.
  static let details: [String: String] = {
    let text = { (path: String) in String(decoding: (try? Data(contentsOf: CatalogRepository.url.appendingPathComponent(path))) ?? Data(), as: UTF8.self) }
    let rendered = (try? PageScript.render(profiles: files.map { text($0.path) }, commandSets: setFiles.map { text($0.path) })) ?? []

    return Dictionary(uniqueKeysWithValues: zip(files.map { $0.value.text("model") ?? "" }, rendered))
  }()

  static let models: [String] = CatalogPage.profiles.compactMap { $0.text("model") }.sorted()
  static let commandSetsByID = Dictionary(uniqueKeysWithValues: CatalogPage.commandSets.map { ($0.text("id") ?? "", $0) })

  static func render(_ profile: String, _ commandSets: [String] = []) throws -> String {
    try #require(try PageScript.render(profiles: [profile], commandSets: commandSets).first)
  }

  /// The words a reader sees: inline marks such as `code` don't split them.
  static func words(_ html: String) -> String {
    html.removing(#"</?(code|strong)>"#).pageText
  }

  /// The strings in a value, each with the keys that lead to it.
  static func strings(in value: JSONValue, path: [String] = []) -> [(path: [String], text: String)] {
    switch value {
    case .string(let text): [(path, text)]
    case .array(let elements): elements.flatMap { strings(in: $0, path: path) }
    case .object(let members): members.flatMap { strings(in: $0.value, path: path + [$0.key]) }
    default: []
    }
  }

  /// The values a card's own lines already give, and the ones the details word differently from the
  /// data: a radio, a role, an engine, a capability's kind and which device a step is done on.
  static func isElsewhereOrReworded(_ path: [String]) -> Bool {
    [["model"], ["name"], ["aliases"], ["description"], ["radio"], ["role"], ["engines", "engine"], ["capabilities", "kind"]].contains(path)
      || (path.first == "lifecycle" && path.last == "device")
  }

  @Test func everyProfileHasDetails() {
    #expect(Self.details.keys.sorted() == Self.models)
    #expect(Self.models.count > 100)
  }

  @Test(arguments: models)
  func everyValueOfAProfileAndItsCommandSetsIsInItsDetails(model: String) throws {
    let profile = CatalogPage.profile(model)
    let html = try #require(Self.details[model])
    var missing: [String] = []

    for (path, text) in Self.strings(in: profile) where !Self.isElsewhereOrReworded(path) {
      if !html.contains(HTMLEscaper.escape(text)) { missing.append("\(path.joined(separator: ".")): \(text)") }
    }

    for id in Set(profile.list("commandSets").compactMap { $0.text("commandSet") }) {
      let commandSet = try #require(Self.commandSetsByID[id])

      for (path, text) in Self.strings(in: commandSet) where !html.contains(HTMLEscaper.escape(text)) {
        missing.append("\(id).\(path.joined(separator: ".")): \(text)")
      }
    }

    #expect(missing == [])
  }

  @Test(arguments: models)
  func theDetailsAreWellFormedUnderTheCardsHeadingAndHoldNoIdentifiers(model: String) throws {
    let html = try #require(Self.details[model])
    var open: [String] = []
    var unbalanced: [String] = []
    var identifiers = 0

    for event in HTMLScanner.events(in: html) {
      switch event {
      case .start(let tag, let attributes):
        if tag != "br" { open.append(tag) }
        if attributes.contains(where: { $0.0 == "id" }) { identifiers += 1 }
      case .end(let tag):
        if open.last == tag { open.removeLast() } else { unbalanced.append(tag) }
      case .text:
        break
      }
    }

    #expect(open == [])
    #expect(unbalanced == [])
    #expect(identifiers == 0)
    #expect(!html.matches(#"<h[1236][ >]"#))
    #expect(html.hasPrefix(#"<div class="full">"#))
    #expect(!PageContentTests.hasDash(html))
  }

  /// A value added to the schema is shown before the script learns a name for it.
  @Test func aFieldTheScriptDoesNotKnowIsStillShown() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [{"kind": "modem", "futureOfCapability": "capability-extra"}], "sources": ["S"],
     "futureTopLevel": {"innerThing": "top-extra", "count": 4217},
     "identities": [{"category": "0x01", "subcategory": "0x01", "futureOfIdentity": "identity-extra"}],
     "groups": [{"number": "0x01", "name": "G", "role": "both", "futureOfGroup": ["group-extra"]}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}],
     "lifecycle": {"futureProcedureValue": "lifecycle-extra",
       "linking": {"futureOfProcedure": "procedure-extra", "steps": [{"text": "Step.", "action": "other", "futureOfStep": "step-extra"}]}}}
    """#, [#"""
    {"id": "a", "name": "A", "description": "D.", "sources": ["T"], "futurePart": [{"name": "p", "futureDeep": {"deeper": "set-extra"}}],
     "operatingFlags": [{"name": "f", "label": "F", "futureOfFlag": "flag-extra"}]}
    """#])

    for value in ["capability-extra", "top-extra", "4217", "identity-extra", "group-extra", "lifecycle-extra", "procedure-extra",
                  "step-extra", "set-extra", "flag-extra"] {
      #expect(html.contains(value), "\(value)")
    }

    #expect(html.contains("Future top level"))
  }

  @Test func aVerificationShowsItsStatusItsNoteAndItsFirmware() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"],
     "verification": {"status": "inferred", "note": "profile-note"},
     "identities": [{"category": "0x01", "subcategory": "0x01", "productKey": "0x00001A",
       "productKeyVerification": {"status": "conflicting", "note": "key-note"},
       "verification": {"status": "observed", "note": "identity-note", "firmware": ["0x41", "0xD1"]}}]}
    """#)

    for (status, note) in [("inferred", "profile-note"), ("conflicting", "key-note"), ("observed", "identity-note")] {
      #expect(html.matches(#"<p class="verification"><span class="status pill status-\#(status)">[^<]+</span>[^\n]*?\#(note)"#), "\(status)")
    }

    #expect(Self.words(html).contains("Seen on firmware 0x41, 0xD1"))
    #expect(Self.words(html).contains("Product key 0x00001A"))
  }

  @Test func aProcedureListsItsStepsInOrderWithWhatEachOneDoes() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x01"}],
     "lifecycle": {"reset": {"steps": [
       {"text": "First thing.", "action": "hold", "control": "SET button", "seconds": 10, "expect": "Long beep"},
       {"text": "Second thing.", "action": "release", "device": "other"}],
       "alternatives": [{"description": "Soft factory reset", "steps": [{"text": "Third thing.", "action": "tap", "count": 3}]}]},
       "resetErases": ["links", "settings"]}}
    """#)
    let text = Self.words(html)

    #expect(html.matches(#"<ol class="steps">.*First thing\..*Second thing\..*</ol>"#, options: [.dotMatchesLineSeparators]))
    #expect(html.contains("<summary>Factory reset</summary>"))
    #expect(html.contains("<summary>Soft factory reset</summary>"))
    #expect(text.contains("Third thing."))
    #expect(text.contains("Expect Long beep"))
    #expect(text.contains("Seconds 10"))
    #expect(text.contains("On the other device"))
    #expect(text.contains("Reset erases links, settings"))
  }

  @Test func eachIdentityGivesItsEngineAndEachCommandSetSaysWhoUsesIt() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"],
     "identities": [{"category": "0x01", "subcategory": "0x01"}, {"category": "0x01", "subcategory": "0x02"}],
     "engines": [{"category": "0x01", "subcategory": "0x02", "engine": "i2cs", "firmware": {"except": ["0x22"]}}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"},
                     {"commandSet": "b", "category": "0x01", "subcategory": "0x02", "firmware": {"only": ["0x41"]}}]}
    """#, [
      #"{"id": "a", "name": "Alpha", "description": "D.", "sources": ["S"]}"#,
      #"{"id": "b", "name": "Beta", "description": "D.", "sources": ["S"]}"#
    ])
    let text = Self.words(html)

    #expect(text.contains("Used by 0x01/0x01"))
    #expect(text.contains("Used by 0x01/0x02, firmware only 0x41"))
    #expect(text.contains("Engine i2CS, firmware except 0x22"))
    #expect(html.contains(#"data-command-set="a""#))
    #expect(html.contains(#"data-command-set="b""#))
  }

  @Test func eachPartOfACommandSetOpensOnItsOwnAndCountsItsEntries() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x01"}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}]}
    """#, [#"""
    {"id": "a", "name": "A", "description": "D.", "sources": ["S"],
     "operatingFlags": [{"name": "detach", "label": "Detach", "query": "0x00", "bit": 3}, {"name": "beep", "label": "Beep"}],
     "extendedSettings": {"perButton": false, "values": [{"name": "rate", "label": "Rate", "byte": 7}], "writes": []},
     "valueTables": [{"name": "ramp", "values": [{"value": "0x1F", "label": "0.1 s"}]}]}
    """#])

    #expect(html.contains("<summary>Operating flags (2)</summary>"))
    #expect(html.contains("<summary>Extended settings (1)</summary>"))
    #expect(html.contains("<summary>Value tables (1)</summary>"))
    #expect(html.matches(#"<table.*<th[^>]*>Value</th>.*<td><code>0x1F</code></td>"#, options: [.dotMatchesLineSeparators]))
    #expect(!html.contains("<details class=\"list\" open"))
  }

  /// The published catalog writes keys alphabetically, which isn't the order a reader wants them.
  @Test func factsAndColumnsComeInReadingOrder() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x01"}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}],
     "lifecycle": {"reset": {"steps": [{"action": "hold", "control": "SET button", "expect": "Beep", "seconds": 3, "text": "T."}]},
       "fromHub": {"legs": [{"deviceGroup": "0x03", "modem": "controller", "modemGroup": "0x00"}]}}}
    """#, [#"""
    {"id": "a", "name": "A", "description": "D.", "sources": ["S"],
     "operatingFlags": [{"bit": "0x20", "label": "F", "name": "f", "off": "0x0B", "on": "0x0A", "query": "0x00", "section": "Buttons", "default": true}]}
    """#])
    let text = Self.words(html)

    #expect(text.contains("Query (cmd2) 0x00 Bit 0x20 Set with cmd2 0x0A Clear with cmd2 0x0B"))
    #expect(text.contains("Action hold Control SET button Seconds 3 Expect Beep"))
    #expect(text.contains("Modem Modem group Device group"))
  }

  @Test func aCommandSetTheCatalogLacksIsNamedRatherThanLeftOut() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x01"}],
     "commandSets": [{"commandSet": "gone", "category": "0x01", "subcategory": "0x01"}]}
    """#)

    #expect(Self.words(html).contains("The catalog file holds no command set named gone."))
  }

  @Test func htmlSpecialCharactersInTheDataAreEscaped() throws {
    let html = try Self.render(#"""
    {"model": "9\"><b>", "name": "N", "capabilities": [], "sources": ["<s>"], "notes": ["</div><script>x()</script> 'q' & more"],
     "identities": [{"category": "0x01", "subcategory": "0x01"}], "<k>": "<v>"}
    """#)

    #expect(!html.contains("<b>"))
    #expect(!html.contains("<s>"))
    #expect(!html.contains("<k>"))
    #expect(!html.contains("<v>"))
    #expect(!html.contains("<script"))
    #expect(html.contains("&lt;/div&gt;&lt;script&gt;x()&lt;/script&gt; &#x27;q&#x27; &amp; more"))
  }

  @Test func theScriptsOwnWordingHasNoTemporalWords() throws {
    let html = try Self.render(#"""
    {"model": "9", "name": "Plain", "capabilities": [{"kind": "heartbeat", "group": "0x04", "intervalMinutes": 5}], "sources": ["S"],
     "identities": [{"category": "0x01", "subcategory": "0x01"}], "groups": [{"number": "0x04", "name": "Beat", "role": "controller"}],
     "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}],
     "lifecycle": {"linking": {"steps": [{"text": "Step.", "action": "other"}]}}}
    """#, [#"{"id": "a", "name": "A", "description": "D.", "sources": ["S"], "operatingFlags": [{"name": "f", "label": "F"}]}"#])
    let text = html.replacingMatches(of: "<[^>]+>", with: " ")

    #expect(!text.lowercased().matches(PageContentTests.temporalWords))
  }

  @Test func theDetailsLinkTheProfilesDataFile() throws {
    let html = try #require(Self.details["2477D"])

    #expect(html.contains(#"href="https://github.com/brandtdaniels/insteon-device-catalog/blob/main/devices/2477D.json""#))
  }

  @Test func thePageCarriesTheScriptAndNamesThePublishedCatalog() throws {
    let page = try CatalogPage.root.indexPage(patch: 1)

    #expect(!PageScript.source.isEmpty)
    #expect(page.contains(PageScript.source))
    #expect(page.contains(#"data-catalog="v0/catalog.json""#))
    #expect(!PageScript.source.contains("</script"))
    #expect(!PageContentTests.hasDash(page))
  }
}
