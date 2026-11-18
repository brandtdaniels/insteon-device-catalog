import CatalogJSON
import Foundation
import Testing

@testable import CatalogSite

/// Each profile's card and its "What the catalog describes" detail section.
struct PageCardTests {
  static let profiles = CatalogPage.profiles
  static let cards = CatalogPage.cards
  static let page = CatalogPage.page

  static func card(_ profile: JSONValue) -> CardRecord {
    cards[profile.text("model") ?? ""] ?? CardRecord()
  }

  static func commandSetIDs(_ profile: JSONValue) -> [String] {
    var seen: [String] = []
    for entry in profile.list("commandSets") {
      if let id = entry.text("commandSet"), !seen.contains(id) { seen.append(id) }
    }
    return seen
  }

  static func engineNotes(_ profile: JSONValue, category: String, subcategory: String) -> [String] {
    profile.list("engines")
      .filter { $0.text("category") == category && $0.text("subcategory") == subcategory }
      .map { PageText.engineNote($0).label }
  }

  @Test func everyProfileHasACardWithAnExpandableDetail() {
    #expect(Self.cards.keys.sorted() == Self.profiles.compactMap { $0.text("model") }.sorted())

    for card in Self.cards.values {
      #expect(card.details)
      #expect(card.summary.contains("What the catalog describes"))
    }
  }

  @Test func theFirstLinesOfACardAreTheModelNameAliasesDescriptionAndMarksOnly() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let outside = card.paragraphs.filter { !$0.inside }.map(\.cls)

      #expect(outside.filter { !["aliases", "description", "marks"].contains($0) } == [], "\(profile.text("model") ?? "")")
      #expect(!card.outside.matches(#"\boperating flags?\b|\bextended settings?\b|\bstandard commands?\b|\bserial commands?\b|Battery powered|Powerline|Dual-band"#))
    }
  }

  @Test func theDescriptionAppearsOnceInFull() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let description = card.paragraphs.filter { $0.cls == "description" }.map(\.text)
      let model = profile.text("model") ?? ""

      #expect(description.count == (profile.has("description") ? 1 : 0), "\(model)")
      #expect((description.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == (profile.text("description") ?? ""), "\(model)")

      if let text = profile.text("description") {
        #expect(Self.page.occurrences(of: HTMLEscaper.escape(text)) == 1, "\(model)")
      }
    }
  }

  @Test func theDescriptionIsNotCutOffByTheStylesheet() {
    #expect(!Self.page.contains("line-clamp"))
  }

  @Test func theDetailSectionIsLabeledGroupsWithIdentityLast() {
    for card in Self.cards.values {
      let groups = card.terms.filter { $0.tag == "h4" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }

      #expect(groups[0] == "Hardware")
      #expect(groups[1] == "ALL-Link groups and events")
      #expect(groups.last == "Identity")
      #expect(Array(groups[2..<(groups.count - 1)]) == ["What software can read or write"])
    }
  }

  @Test func noParagraphInTheDetailSectionIsLongerThanASentence() {
    for profile in Self.profiles {
      for paragraph in Self.card(profile).paragraphs where paragraph.inside {
        #expect(!paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).matches(#"[.!?] \S"#), "\(paragraph.text)")
      }
    }
  }

  @Test func noFactIsARunOnList() {
    for profile in Self.profiles {
      for fact in Self.card(profile).facts {
        #expect(fact.text.filter { $0 == "," }.count <= 2, "\(fact.name) \(fact.text)")
        #expect(fact.text.count < 160, "\(fact.name) \(fact.text)")
      }
    }
  }

  @Test func eachFactAppearsOnceOnACard() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let model = profile.text("model") ?? ""
      let terms = card.terms.filter { $0.tag == "dt" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }

      for term in ["Radio", "Role", "Engine", "Battery", "Groups", "Reports", "Heartbeat", "Sold in"] {
        #expect(terms.filter { $0 == term }.count <= 1, "\(model) \(term)")
      }

      #expect(!card.inside.matches(#"Engine: |Settings: |Subcategory: |Radio: |Role: "#), "\(model)")
      #expect(card.terms.filter { ["dt", "th"].contains($0.tag) && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Subcategory" }.count == 1, "\(model)")

      let engine = card.facts("engine")

      if engine != ["Not stated"], engine != ["Varies by identity"] {
        for note in Set(profile.list("engines").map { PageText.engineNote($0).label }) {
          let pattern = #"(?<![\w/])"# + NSRegularExpression.escapedPattern(for: note) + #"(?![\w/])"#
          #expect(card.inside.captures(pattern).count == 1, "\(model) \(note)")
        }
      }
    }
  }

  @Test func theEngineRowNamesTheEngineOrPointsToTheIdentityTable() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let model = profile.text("model") ?? ""
      let engine = card.facts("engine")
      let perIdentity = profile.list("identities").map {
        Self.engineNotes(profile, category: $0.text("category") ?? "", subcategory: $0.text("subcategory") ?? "")
      }

      #expect(engine.count == 1, "\(model)")

      if profile.list("engines").isEmpty {
        #expect(engine == ["Not stated"], "\(model)")
      } else if Set(perIdentity).count > 1 {
        #expect(engine == ["Varies by identity"], "\(model)")
        #expect(card.terms.filter { $0.tag == "th" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.contains("Engine"), "\(model)")
      } else {
        for note in perIdentity[0] {
          #expect(engine[0].contains(note), "\(model)")
        }
      }
    }
  }

  @Test func aCommandSetsCountsAreARowOfFiguresAndItsNamesAreNestedLists() {
    let named: Set<String> = ["operatingFlags", "extendedSettings", "readings"]

    for profile in Self.profiles {
      let card = Self.card(profile)
      let model = profile.text("model") ?? ""

      for setID in Self.commandSetIDs(profile) {
        let commandSet = CatalogPage.disk("commandSets", setID)
        let settings = commandSet["extendedSettings"]?.list("values") ?? []
        let parts: [(String, [JSONValue])] = [
          ("operatingFlags", commandSet.list("operatingFlags")),
          ("extendedSettings", settings),
          ("standardCommands", commandSet.list("standardCommands")),
          ("extendedCommands", commandSet.list("extendedCommands")),
          ("serialCommands", commandSet.list("serialCommands")),
          ("readings", commandSet.list("readings"))
        ]

        for (name, items) in parts {
          let found = card.facts(name, commandSet: setID)
          let key = ListKey(commandSet: setID, name: name)

          if items.isEmpty {
            #expect(found == [], "\(model) \(name)")
            #expect(card.lists[key] == nil)
            continue
          }

          #expect(found.count == 1, "\(model) \(name)")
          #expect(found.first?.matches("^\(items.count) [a-z]") == true, "\(model) \(name)")

          if named.contains(name) {
            #expect(card.lists[key] == items.compactMap { $0.text("label") }, "\(model) \(name)")
          } else {
            #expect(card.lists[key] == nil)
          }
        }
      }
    }
  }

  @Test func nestedListsAreExpandableAndOpenInsideTheDetailSection() throws {
    let card = try #require(Self.cards["2477D"])

    #expect(card.nested >= 2)
    #expect(card.htmlClasses.contains { $0.tag == "details" && $0.cls == "list" })
  }

  @Test func aModemReportsItsSerialCommands() throws {
    let card = try #require(Self.cards["2413U"])

    for entry in CatalogPage.profile("2413U").list("commandSets") {
      let id = try #require(entry.text("commandSet"))
      let expected = CatalogPage.disk("commandSets", id).list("serialCommands").count

      #expect(try #require(card.facts("serialCommands", commandSet: id).first).matches("^\(expected) serial commands"))
    }
  }

  @Test func aProfileWithNoCommandSetSaysSoAndImpliesNoCapability() {
    let missing = Self.profiles.filter { $0.list("commandSets").isEmpty }

    #expect(!missing.isEmpty)

    for profile in missing {
      let card = Self.card(profile)

      #expect(card.facts("noCommandSet") == ["The catalog has no command set for this device."], "\(profile.text("model") ?? "")")
      #expect(card.facts.filter { PageTables.commandSetFacts.contains($0.name) }.isEmpty)
    }
  }

  @Test func aProfileDeliberatelyWithoutSettingsSaysSo() {
    let empty = Self.profiles.filter { profile in
      !profile.list("commandSets").isEmpty && profile.list("commandSets").allSatisfy { entry in
        let keys = Set(CatalogPage.disk("commandSets", entry.text("commandSet") ?? "").members.map(\.key))
        return keys.subtracting(PageTables.commandSetDescriptiveKeys).isEmpty
      }
    }

    #expect(!empty.isEmpty)

    for profile in empty {
      let card = Self.card(profile)

      #expect(card.facts("noSettings") == ["The catalog deliberately holds no settings for this device: there is nothing for software to read or write."])
      #expect(card.facts("noCommandSet") == [])
      #expect(card.facts.filter { PageTables.commandSetFacts.contains($0.name) }.isEmpty)
    }
  }

  @Test func radioRoleAndBatteryFollowTheProfile() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let model = profile.text("model") ?? ""

      #expect(card.facts("radio") == [profile.text("radio").flatMap { PageTables.radioLabels[$0] } ?? "Not stated"], "\(model)")
      #expect(card.facts("role") == [profile.text("role").flatMap { PageTables.roleLabels[$0] } ?? "Not stated"], "\(model)")
      #expect(!card.facts("battery").isEmpty == profile.isTrue("batteryPowered"), "\(model)")
    }
  }

  @Test func groupsEventsAndHeartbeatFollowTheProfile() {
    for profile in Self.profiles {
      let card = Self.card(profile)
      let model = profile.text("model") ?? ""
      let groups = card.facts("group")
      let expectedGroups = profile.list("groups")

      #expect(groups.count == expectedGroups.count, "\(model)")
      #expect(card.facts("noGroups").count == (expectedGroups.isEmpty ? 1 : 0), "\(model)")

      for (group, text) in zip(expectedGroups, groups) {
        #expect(text.contains(group.text("name") ?? "?"), "\(model)")
        #expect(text.hasPrefix("\(Int((group.text("number") ?? "").dropFirst(2), radix: 16) ?? -1) "), "\(text)")
      }

      let events = profile.list("capabilities").filter { $0.text("kind") == "groupEvents" }.flatMap { $0.list("events") }
      #expect(card.facts("event").count == events.count, "\(model)")

      for (event, text) in zip(events, card.facts("event")) {
        #expect(text.contains(event.text("event") ?? "?"))
        #expect(text.contains(event.text("command1") ?? "?"))
      }

      for capability in profile.list("capabilities") where capability.text("kind") == "heartbeat" {
        let text = card.facts("heartbeat").joined(separator: " ")

        #expect(text.contains("group \(Int((capability.text("group") ?? "").dropFirst(2), radix: 16) ?? -1)"))

        if let minutes = capability["intervalMinutes"]?.int {
          #expect(text.contains(String(minutes)))
        }
      }

      if !profile.list("capabilities").contains(where: { $0.text("kind") == "heartbeat" }) {
        #expect(card.facts("heartbeat") == [])
      }
    }
  }

  @Test func searchFindsACardByCapabilityRadioRoleAndBatteryWords() {
    for profile in Self.profiles {
      let search = Self.card(profile).attributes["data-search"] ?? ""
      let model = profile.text("model") ?? ""

      for capability in profile.list("capabilities") {
        for word in (PageTables.capabilityLabels[capability.text("kind") ?? ""] ?? "").lowercased().split(separator: " ") {
          #expect(search.contains(word), "\(model)")
        }
      }

      if profile.isTrue("batteryPowered") { #expect(search.contains("battery powered")) }

      if let radio = profile.text("radio") {
        #expect(search.contains(["powerline": "powerline", "rf": "rf", "dual": "dual-band"][radio] ?? "?"))
      }
    }
  }

  @Test func theSearchScriptAlsoReadsTheTextOfTheCard() {
    #expect(Self.page.contains("textContent"))
  }

  @Test func thePageStaysASaneSize() {
    #expect(Self.page.utf8.count < 450_000)
  }
}
