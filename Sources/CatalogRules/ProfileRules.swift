import CatalogJSON

/// The rules a device profile has to satisfy beyond its schema, alone and against the command sets.
public enum ProfileRules {
  /// The problems in a profile that passed its schema: a file name that isn't the model, a
  /// capability kind used twice, engine entries for identities the product lacks or that overlap,
  /// a modem's record data, the fromHub flow, and command set entries for identities the product
  /// lacks or that overlap, in that order.
  ///
  /// - Parameter stem: The profile's file name without `.json`.
  public static func problems(in profile: JSONValue, fileStem stem: String) -> [String] {
    let model = profile.text("model") ?? ""
    let name = stem == model ? [] : ["the file name must be the model, \(pythonRepr(model))"]

    return name + problems(in: profile)
  }

  static func problems(in profile: JSONValue) -> [String] {
    var problems: [String] = []
    let kinds = profile.list("capabilities").map { $0.text("kind") ?? "" }

    if Set(kinds).count != kinds.count {
      problems.append("a capability kind appears more than once")
    }

    problems += scopedEntryProblems(profile, field: "engines", label: "engine")
    problems += modemLinkDataProblems(profile)
    problems += FromHubRules.problems(in: profile)
    problems += scopedEntryProblems(profile, field: "commandSets", label: "command set")

    return problems
  }

  /// The firmware versions a selection includes, or every version for none.
  static func selectedFirmware(_ selection: JSONValue?) -> Set<Int> {
    let all = Set(0..<0x100)

    guard let selection else { return all }

    if let only = selection["only"] {
      return Set(only.elements.compactMap(\.string).map(hexValue))
    }

    return all.subtracting(selection.list("except").compactMap(\.string).map(hexValue))
  }

  /// Reports entries of a field such as engines for identities the product doesn't have, and
  /// firmware versions two entries cover under the same identity.
  static func scopedEntryProblems(_ profile: JSONValue, field: String, label: String) -> [String] {
    let identities = Set(profile.list("identities").map(identityKey))
    var claimed: [String: Set<Int>] = [:]
    var problems: [String] = []

    for entry in profile.list(field) {
      let key = identityKey(entry)
      let category = entry.text("category") ?? "", subcategory = entry.text("subcategory") ?? ""

      guard identities.contains(key) else {
        problems.append("the \(label) entry for \(category)/\(subcategory) names an identity the product doesn't report")
        continue
      }

      let versions = selectedFirmware(entry["firmware"])

      if !versions.isDisjoint(with: claimed[key] ?? []) {
        problems.append("two \(label) entries cover the same firmware under \(category)/\(subcategory)")
      }

      claimed[key, default: []].formUnion(versions)
    }

    return problems
  }

  private static func identityKey(_ entry: JSONValue) -> String {
    "\(entry.text("category") ?? "")/\(entry.text("subcategory") ?? "")"
  }

  /// Reports a modem's record data that names a byte twice, or a byte that gives neither or both
  /// of a fixed value and an identity byte.
  static func modemLinkDataProblems(_ profile: JSONValue) -> [String] {
    var problems: [String] = []

    for capability in profile.list("capabilities") {
      for side in capability["linkData"]?.members ?? [] {
        let entries = side.value.elements
        let numbers = entries.map { $0["byte"]?.canonical ?? "" }

        if Set(numbers).count != numbers.count {
          problems.append("the modem's \(side.key) record data names a byte twice")
        }

        for entry in entries where entry.has("value") == entry.has("identity") {
          problems.append("the modem's \(side.key) record data \(entry.text("name") ?? "") needs a value or an identity, not both")
        }
      }
    }

    return problems
  }

  /// The identities that two profiles, or one profile twice, claim for the same firmware.
  public static func overlappingIdentities(_ profiles: [JSONValue]) -> [String] {
    var claimed: [String: [(model: String, low: Int, high: Int)]] = [:]
    var problems: [String] = []

    for profile in profiles {
      let model = profile.text("model") ?? ""

      for identity in profile.list("identities") {
        let key = identityKey(identity)
        let (low, high) = firmwareRange(identity)

        for other in claimed[key] ?? [] where low <= other.high && other.low <= high {
          problems.append("\(model) and \(other.model) both claim \(key) for overlapping firmware")
        }

        claimed[key, default: []].append((model, low, high))
      }
    }

    return problems
  }

  private static func firmwareRange(_ identity: JSONValue) -> (Int, Int) {
    guard let firmware = identity["firmware"] else { return (0x00, 0xFF) }
    return (hexValue(firmware.text("from") ?? ""), hexValue(firmware.text("through") ?? ""))
  }

  /// The problems in the profile's use of the command sets: command sets that don't exist, names
  /// the fromHub flow takes from them, and groups that don't fit the group types and flags they use.
  ///
  /// Each message starts with the profile's file name, as `2442.json: `.
  ///
  /// - Parameter commandSets: The command sets that passed their schema, by id.
  public static func commandSetProblems(for profile: JSONValue, commandSets: [String: JSONValue]) -> [String] {
    let file = "\(profile.text("model") ?? "").json"

    return commandSetProblems(for: profile, in: commandSets).map { "\(file): \($0)" }
  }

  static func commandSetProblems(for profile: JSONValue, in commandSets: [String: JSONValue]) -> [String] {
    var problems: [String] = []

    for entry in profile.list("commandSets") {
      let id = entry.text("commandSet") ?? ""

      if commandSets[id] == nil {
        problems.append("it names the command set \(pythonRepr(id)), which doesn't exist")
      }
    }

    problems += FromHubRules.commandSetProblems(for: profile, commandSets: commandSets)
    let entries = Set(profile.list("commandSets").compactMap { $0.text("commandSet") }.filter { commandSets[$0] != nil })
    let kinds = Set(profile.list("capabilities").compactMap { $0.text("kind") })
    let used = entries.codePointSorted()

    for group in profile.list("groups") {
      let label = "group \(group["number"]?.messageText ?? "")"
      let role = group.text("role") ?? ""

      if let type = group.text("type") {
        for entry in used {
          let groupType = GroupTypes(commandSets[entry]?.list("groupTypes") ?? [])[type]

          guard let groupType else {
            problems.append("\(label) names the group type \(pythonRepr(type)), which \(entry) doesn't have")
            continue
          }

          let state = groupType["state"]
          let kind = groupType.text("kind") ?? ""

          if state?.isSet("bitPerGroup") == true, hexValue(group.text("number") ?? "") > 8 {
            problems.append("\(label) reads one bit per group, but a reply has bits for groups 1 to 8 only")
          } else if groupType.isSet("actions"), role == "controller" {
            problems.append("\(label) is only a controller, but its group type has actions")
          } else if kind == "dimmer", !kinds.contains("dimmable") {
            problems.append("\(label) is a dimmer, but the profile isn't dimmable")
          } else if kind == "relay", !kinds.contains("onOff"), !kinds.contains("dimmable") {
            problems.append("\(label) is a relay, but the profile doesn't switch a load")
          }
        }
      }

      if let flag = group["activeWhen"]?.text("flag") {
        for entry in used {
          let names = Set((commandSets[entry]?.list("operatingFlags") ?? []).compactMap { $0.text("name") })

          if !names.contains(flag) {
            problems.append("\(label) depends on \(pythonRepr(flag)), which \(entry) has no flag for")
          }
        }
      }

      if let profileRole = profile.text("role"), profileRole == "controller" || profileRole == "responder", role != profileRole {
        problems.append("\(label) is a \(role), but the profile is only a \(profileRole)")
      }
    }

    return problems
  }
}

/// The group types of a command set by name; a name used twice keeps the last.
private struct GroupTypes {
  private let byName: [String: JSONValue]

  init(_ groupTypes: [JSONValue]) {
    byName = Dictionary(groupTypes.map { ($0.text("name") ?? "", $0) }, uniquingKeysWith: { $1 })
  }

  subscript(name: String) -> JSONValue? {
    byName[name]
  }
}
