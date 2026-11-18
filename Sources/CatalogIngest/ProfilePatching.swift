import CatalogJSON
import CatalogRules

/// Finds the catalog entry a change names and sets its verification.
///
/// A report is read by a person and then handed back to apply, so apply accepts only the shape
/// drafting writes: a verification set from the observed template and nothing else.
enum ProfilePatching {
  private static let selectorKeys: [EntryKind: Set<String>] = [
    .identity: ["category", "subcategory", "firmware"],
    .engine: ["engine", "category", "subcategory", "firmware"]
  ]
  private static let profileFile = Pattern.whole(#"devices/([A-Za-z0-9\-]+)\.json"#)
  private static let byte = Pattern.whole(#"0x[0-9A-F]{2}"#)
  private static let observedNote = Pattern.whole(#"Seen on a device running firmware 0x[0-9A-F]{2}: [^\n]+"#)

  /// The profile's list of entries of this kind.
  static func listName(_ kind: EntryKind) -> String {
    switch kind {
    case .identity: "identities"
    case .engine: "engines"
    }
  }

  /// The members of an entry that say which one it is.
  static func selector(for kind: EntryKind, _ entry: JSONValue) -> JSONValue {
    let keys = kind == .identity ? ["category", "subcategory", "firmware"] : ["engine", "category", "subcategory", "firmware"]

    return .object(keys.compactMap { key in entry[key].map { JSONMember(key: key, value: $0) } })
  }

  /// The position of the one entry of the profile the selector names, or `nil` when none or several do.
  static func locate(_ kind: EntryKind, selector: JSONValue, in profile: JSONValue) -> Int? {
    let found = (profile[listName(kind)]?.elements ?? []).enumerated().filter { self.selector(for: kind, $0.element).pythonEquals(selector) }

    return found.count == 1 ? found[0].offset : nil
  }

  /// Why a change from a report cannot be trusted, as sentences; empty when it can be applied.
  static func problems(in change: JSONValue) -> [String] {
    guard change.isObject else { return ["a change is not an object"] }

    guard let kind = change["entry"]?.string.flatMap(EntryKind.init(rawValue:)) else {
      return ["a change names an entry kind apply does not set"]
    }

    var problems: [String] = []
    let field = change["field"]?.string.flatMap(VerificationField.init(rawValue:))

    if field == nil {
      problems.append("a change names a field apply does not set")
    }

    if change["field"]?.string == VerificationField.productKeyVerification.rawValue, kind != .identity {
      problems.append("only an identity has a product key verification")
    }

    if !namesTheModelsProfile(change) {
      problems.append("a change names a file that is not the model's profile")
    }

    if !hasASelector(change["selector"], of: kind) {
      problems.append("a change has a selector of the wrong shape")
    }

    problems += afterProblems(change["after"])

    return problems
  }

  private static func namesTheModelsProfile(_ change: JSONValue) -> Bool {
    guard let file = change["file"]?.string, profileFile.matches(file), let model = change["model"]?.string else { return false }

    return file == "devices/\(model).json"
  }

  private static func hasASelector(_ selector: JSONValue?, of kind: EntryKind) -> Bool {
    guard case .object(let members)? = selector else { return false }
    let keys = Set(members.map(\.key))

    return keys.isSuperset(of: ["category", "subcategory"]) && keys.isSubset(of: selectorKeys[kind] ?? [])
  }

  private static func afterProblems(_ after: JSONValue?) -> [String] {
    guard case .object(let members)? = after, Set(members.map(\.key)).isSubset(of: ["status", "note", "firmware"]),
          after?["status"] == .string("observed")
    else { return ["a change sets something other than an observed verification"] }

    guard let note = after?["note"]?.string, observedNote.matches(note),
          case .array(let firmware)? = after?["firmware"], !firmware.isEmpty,
          firmware.allSatisfy({ $0.string.map(byte.matches) ?? false })
    else { return ["a change's verification does not follow the observed form"] }

    return []
  }

  /// What setting a change on a profile did.
  enum Result: Equatable {
    case applied
    /// The entry holds the result already.
    case already
    /// The change can't be applied, for this reason.
    case refused(String)
  }

  /// Sets the change's field on its entry.
  static func apply(
    kind: EntryKind, selector: JSONValue, field: VerificationField, before: JSONValue?, after: JSONValue, to profile: inout JSONValue
  ) -> Result {
    let list = listName(kind)

    guard case .object(var members) = profile, let listPosition = members.firstIndex(where: { $0.key == list }),
          let position = locate(kind, selector: selector, in: profile), case .array(var entries) = members[listPosition].value,
          case .object(var entry) = entries[position]
    else { return .refused("the entry the change names is not in the profile") }

    let current = entries[position][field.rawValue]

    if current.pythonEquals(after) { return .already }

    if !current.pythonEquals(before) { return .refused("the entry does not hold what the report was drafted from") }

    if let index = entry.firstIndex(where: { $0.key == field.rawValue }) {
      entry[index].value = after
    } else if field == .productKeyVerification, let keyIndex = entry.firstIndex(where: { $0.key == "productKey" }) {
      // Keep the key's verification next to the key, as the files do.
      entry.insert(JSONMember(key: field.rawValue, value: after), at: keyIndex + 1)
    } else {
      entry.append(JSONMember(key: field.rawValue, value: after))
    }

    entries[position] = .object(entry)
    members[listPosition].value = .array(entries)
    profile = .object(members)

    return .applied
  }

  static func apply(_ change: ProposedChange, to profile: inout JSONValue) -> Result {
    apply(kind: change.entry, selector: change.selector, field: change.field, before: change.before, after: change.after, to: &profile)
  }
}
