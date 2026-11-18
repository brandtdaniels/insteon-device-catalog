import CatalogJSON
import CatalogRules

/// Matches an observation to the catalog and drafts what it can honestly claim.
///
/// Drafting writes only verification marks. A value is never changed, and a disagreement is listed for
/// a maintainer. Every sentence it writes is built from validated fields; the contributor's free text
/// goes nowhere.
public enum ObservationDrafting {
  /// What a disagreement asks of the maintainer.
  static let needs = "maintainer decision; nothing written"
  static let knownChecks: Set<String> = ["Get Insteon Engine Version", "ID Request", "Product Data Request", "Status Request", "Get Operating Flags"]
  static let nothingAnswered = "No check was answered, so this file says nothing about the device. Run `insteon observe` again with the device awake."
  private static let engines = ["i1": "i1", "i2": "i2", "i2CS": "i2cs"]
  private static let engineLabels = ["i1": "i1", "i2": "i2", "i2cs": "i2CS"]

  /// What an observation that passed the check would change in the catalog, and what it contradicts.
  ///
  /// The catalog is updated as changes are drafted, so a second observation sees the first's marks.
  public static func draft(_ data: JSONValue, in catalog: inout ProfileCatalog, label: String = "observation") -> ObservationDraft {
    var result = ObservationDraft(label: label)
    let checks = data["checks"]?.elements ?? []
    var outcomes: [String: String] = [:]

    for check in checks {
      let name = check.text("name") ?? "", outcome = check.text("outcome") ?? ""

      if outcomes[name] == nil { outcomes[name] = outcome }
    }

    if outcomes.keys.contains(where: { !knownChecks.contains($0) }) {
      result.warnings.append("A check this tool does not read was ignored.")
    }

    for check in checks {
      let name = check.text("name") ?? "", outcome = check.text("outcome") ?? ""

      if knownChecks.contains(name), outcome != "answered", !result.skipped.contains(where: { $0.check == name }) {
        result.skipped.append(SkippedCheck(check: name, reason: "outcome was \(outcome); says nothing about the device"))
      }
    }

    let device = data["device"] ?? .null

    guard outcomes["ID Request"] == "answered", let category = device.text("category"), let subcategory = device.text("subcategory"),
          let firmware = device.text("firmware")
    else {
      result.warnings.append(
        outcomes.values.contains("answered") ? "The device's identity was not reported, so no profile was matched." : nothingAnswered
      )
      finish(&result)

      return result
    }

    let matches = catalog.profiles.keys.sortedByCodePoint().flatMap { model in
      (catalog.profiles[model]?["identities"]?.elements ?? []).compactMap { identity in
        identity.text("category") == category && identity.text("subcategory") == subcategory && covers(identity, firmware)
          ? (model, identity) : nil
      }
    }

    guard matches.count == 1 else {
      noOneProfile(&result, matches: matches.count, category: category, subcategory: subcategory, firmware: firmware, catalog: catalog)

      return result
    }

    let (model, identity) = matches[0]
    let profile = catalog.profiles[model] ?? .null
    result.matched = ProfileMatch(model: model, category: category, subcategory: subcategory)

    if let named = device.text("model"), !named.containsExactly(model), !(profile.text("name").map(named.containsExactly) ?? false) {
      result.warnings.append("The file names a different product than the profile its identity matched.")
    }

    let key = data.text("productKey")
    let keySentence = key == "none" && identity["productKey"] == nil ? " Product Data Request answered and reported no product key." : ""

    mark(
      &result, in: &catalog, model: model, kind: .identity, entry: identity, field: .verification, target: "identity \(category)/\(subcategory)",
      firmware: firmware, sentence: "ID Request answered with category \(category), subcategory \(subcategory) and firmware \(firmware).",
      extra: keySentence
    )

    draftEngine(&result, in: &catalog, model: model, device: device, outcomes: outcomes, firmware: firmware)
    draftKey(&result, in: &catalog, model: model, identity: identity, key: key, firmware: firmware)

    if let flags = data["operatingFlags"] {
      result.reportOnly.append(ReportOnlyItem(
        item: "Operating flags",
        detail: "The device gave \(flags.text("raw") ?? ""). Not compared with the catalog's flags: the file does not say which request each byte answers."
      ))
    }

    finish(&result)

    return result
  }

  /// Whether the identity's firmware range holds the version.
  private static func covers(_ identity: JSONValue, _ firmware: String) -> Bool {
    let (low, high) = ProfileRules.firmwareRange(identity)
    let version = hexByte(firmware)

    return low <= version && version <= high
  }

  private static func hexByte(_ text: String) -> Int {
    Int(text.dropFirst(2), radix: 16) ?? 0
  }

  private static func noOneProfile(
    _ result: inout ObservationDraft, matches: Int, category: String, subcategory: String, firmware: String, catalog: ProfileCatalog
  ) {
    if matches > 1 {
      disagree(&result, .ambiguous, "\(matches) profiles claim category \(category), subcategory \(subcategory) at firmware \(firmware).")
    } else if catalog.profiles.values.contains(where: { profile in
      (profile["identities"]?.elements ?? []).contains { $0.text("category") == category && $0.text("subcategory") == subcategory }
    }) {
      disagree(
        &result, .firmwareNotCovered,
        "Category \(category), subcategory \(subcategory) is in the catalog, but no identity covers firmware \(firmware). A maintainer decides whether to widen one."
      )
    } else {
      disagree(
        &result, .unknownDevice,
        "Category \(category), subcategory \(subcategory) and firmware \(firmware) match no profile. "
          + "A profile needs a name, aliases, an identity, capabilities, an engine and sources, each backed by a public document or an observation."
      )
    }

    finish(&result)
  }

  private static func disagree(_ result: inout ObservationDraft, _ code: DisagreementCode, _ detail: String) {
    result.disagreements.append(Disagreement(code: code, detail: detail, needs: needs))
  }

  private static func draftEngine(
    _ result: inout ObservationDraft, in catalog: inout ProfileCatalog, model: String, device: JSONValue, outcomes: [String: String], firmware: String
  ) {
    guard outcomes["Get Insteon Engine Version"] == "answered", let engine = device.text("engine"), let reported = engines[engine] else { return }

    let category = device.text("category") ?? "", subcategory = device.text("subcategory") ?? ""
    let version = hexByte(firmware)
    let entries = (catalog.profiles[model]?["engines"]?.elements ?? []).filter {
      $0.text("category") == category && $0.text("subcategory") == subcategory
        && ProfileRules.selectedFirmware($0["firmware"]).contains(version)
    }

    guard let entry = entries.first else {
      disagree(&result, .firmwareNotCovered, "No engine entry covers category \(category), subcategory \(subcategory) at firmware \(firmware); the device reported \(engine).")

      return
    }

    guard entry.text("engine") == reported else {
      disagree(
        &result, .engineDiffers,
        "The device reported \(engine); the catalog gives \(engineLabels[entry.text("engine") ?? ""] ?? "") for category \(category), subcategory \(subcategory) at firmware \(firmware)."
      )

      return
    }

    mark(
      &result, in: &catalog, model: model, kind: .engine, entry: entry, field: .verification,
      target: "engine \(engineLabels[reported] ?? reported) \(category)/\(subcategory)", firmware: firmware,
      sentence: "Get Insteon Engine Version answered with \(engine)."
    )
  }

  private static func draftKey(
    _ result: inout ObservationDraft, in catalog: inout ProfileCatalog, model: String, identity: JSONValue, key: String?, firmware: String
  ) {
    guard let key else { return }

    let recorded = identity.present("productKey")?.string
    let target = "\(identity.text("category") ?? "")/\(identity.text("subcategory") ?? "")"

    if recorded == nil, key == "none" { return }  // The identity's own note says the device reported no key.

    if let recorded {
      if key == "none", recorded != "none" {
        disagree(&result, .keyNotReported, "Product Data Request was answered with no key; the catalog gives \(recorded) for identity \(target).")
      } else if key != recorded {
        disagree(&result, .keyDiffers, "The device reported product key \(key); the catalog gives \(recorded) for identity \(target).")
      } else {
        let sentence = key == "none" ? "Product Data Request answered and reported no product key." : "Product Data Request reported product key \(key)."
        mark(
          &result, in: &catalog, model: model, kind: .identity, entry: identity, field: .productKeyVerification,
          target: "product key of identity \(target)", firmware: firmware, sentence: sentence
        )
      }
    } else {
      disagree(
        &result, .keyNotInCatalog,
        "The device reported product key \(key); the catalog gives none for identity \(target). Adding a value is a maintainer decision."
      )
    }
  }

  /// Records the change that marks the entry's field observed on firmware, or why none is needed.
  private static func mark(
    _ result: inout ObservationDraft, in catalog: inout ProfileCatalog, model: String, kind: EntryKind, entry: JSONValue, field: VerificationField,
    target: String, firmware: String, sentence: String, extra: String = ""
  ) {
    let current = entry.present(field.rawValue)
    let selector = ProfilePatching.selector(for: kind, entry)

    if let current, current.text("status") == "conflicting" {
      disagree(&result, .conflictingNotOverwritten, "The catalog marks \(target) conflicting; an observation does not settle which document is right.")

      return
    }

    let after: JSONValue
    let effect: String

    if let current, current.text("status") == "observed" {
      let listed = (current["firmware"]?.elements ?? []).compactMap(\.string)

      if listed.contains(where: { $0.isExactly(firmware) }) {
        result.unchanged.append(UnchangedTarget(target: target, reason: "already observed on firmware \(firmware)"))

        return
      }

      after = current.setting("firmware", to: .array((listed + [firmware]).sortedByCodePoint().map(JSONValue.string)))
      effect = "added firmware \(firmware) to the observed record"
    } else {
      var note = "Seen on a device running firmware \(firmware): \(sentence)\(extra)"

      if let current {
        note += " \(current.text("note") ?? "")"
      }

      after = .object([
        JSONMember(key: "status", value: .string("observed")),
        JSONMember(key: "note", value: .string(note)),
        JSONMember(key: "firmware", value: .array([.string(firmware)]))
      ])
      effect = "marked observed on firmware \(firmware)"
    }

    let change = ProposedChange(
      file: "devices/\(model).json", model: model, entry: kind, selector: selector, field: field, before: current, after: after, effect: effect,
      target: target
    )
    result.changes.append(change)

    if var profile = catalog.profiles[model] {
      _ = ProfilePatching.apply(change, to: &profile)
      catalog.profiles[model] = profile
    }
  }

  static func finish(_ result: inout ObservationDraft) {
    if !result.changes.isEmpty {
      result.outcome = .drafted
    } else if !result.disagreements.isEmpty {
      result.outcome = .needsHuman
    } else {
      result.outcome = .noChange
    }
  }
}
