import CatalogJSON

/// The ways the sweep changes what the registry, citation, term and dash rules read.
public enum RuleMutationKind: String, CaseIterable, Sendable {
  /// Changes a title in a `sources` list of a profile or command set to one the registry lacks.
  case unregisteredSource
  /// Adds a registry entry that repeats another's title.
  case duplicateRegistryTitle
  /// Puts an em dash or an en dash in a string of a data file or a documents file.
  case dashInDataString
  /// Adds a registry entry whose title adds a word to another's, or shares its model number, and
  /// sometimes lists the pair as reviewed.
  case nearDuplicateTitle
  /// Puts a ruled-out form in a registry title or in a prose string of a data file.
  case ruledOutTerm
  /// Damages a registry entry: its kind, edition, URL, title, or an unknown field.
  case registryEntry
  /// Changes the reviewed pairs: adds a stale pair, a pair with an unregistered title or an entry
  /// that isn't a pair, or removes a pair.
  case reviewedPair
}

/// One change the sweep made to what the rules read, with the files it touched.
public struct AppliedRuleMutation: Equatable, Sendable, CustomStringConvertible {
  public let kind: RuleMutationKind
  public let files: [String]
  public let detail: String

  public var description: String {
    "\(kind.rawValue) in \(files.joined(separator: ", ")): \(detail)"
  }
}

/// Changes the files the registry, citation, term and dash rules read, chosen by a seeded random
/// source. It works on every data file and on `documents/registry.json` and
/// `documents/reviewed-distinct-titles.json`, held by path.
public struct RuleMutator: Sendable {
  public static let registryPath = "documents/registry.json"
  public static let reviewedPath = "documents/reviewed-distinct-titles.json"

  /// Forms CONVENTIONS.md rules out, one for each term pattern.
  static let ruledOutForms = [
    "INSTEON", "i2cs", "acknowledgement", "power line", "on level", "2242 Hub", "all-link", "link database",
    "clean-up", "set button", "Developer's Guide", "the guide"
  ]

  static let proseKeys: Set<String> = ["description", "note", "notes", "sources", "label", "section", "text", "expect"]

  public init() {}

  /// Changes `files` in place and says what it did, or returns `nil` when the kind has nowhere to
  /// apply. The changed paths are the ones the result names.
  public func mutate(
    _ files: inout [String: JSONValue], kind: RuleMutationKind, using random: inout some RandomNumberGenerator
  ) -> AppliedRuleMutation? {
    switch kind {
    case .unregisteredSource: unregisteredSource(&files, &random)
    case .duplicateRegistryTitle: duplicateRegistryTitle(&files, &random)
    case .dashInDataString: dashInDataString(&files, &random)
    case .nearDuplicateTitle: nearDuplicateTitle(&files, &random)
    case .ruledOutTerm: ruledOutTerm(&files, &random)
    case .registryEntry: registryEntry(&files, &random)
    case .reviewedPair: reviewedPair(&files, &random)
    }
  }

  /// Changes `files` in place with a kind chosen at random.
  public func mutate(_ files: inout [String: JSONValue], using random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    let kind = RuleMutationKind.allCases.randomElement(using: &random)!

    return mutate(&files, kind: kind, using: &random)
  }

  // MARK: Kinds

  private func unregisteredSource(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    let places = dataPaths(files).flatMap { path in
      (files[path] ?? .null).locations().compactMap { place -> (file: String, path: JSONPath, title: String)? in
        guard case .string(let title) = place.value, isInSources(place.path) else { return nil }

        return (path, place.path, title)
      }
    }

    guard let place = places.randomElement(using: &random) else { return nil }
    let forms = [place.title + " (draft)", place.title.lowercased(), place.title + " ", "An Unregistered Document"]
    let replacement = forms.randomElement(using: &random)!

    files[place.file] = files[place.file]?.replacing(at: place.path) { _ in .string(replacement) }

    return AppliedRuleMutation(kind: .unregisteredSource, files: [place.file], detail: "\(place.title.debugDescription) became \(replacement.debugDescription)")
  }

  private func duplicateRegistryTitle(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    guard let entries = registryEntries(files), let entry = entries.randomElement(using: &random),
          case .string(let title)? = entry.value(at: ["title"])
    else { return nil }

    let kinds = ["other", "ownersManual", "quickStart"]
    let kind = kinds.randomElement(using: &random)!
    let copy = JSONValue.object([JSONMember(key: "title", value: .string(title)), JSONMember(key: "kind", value: .string(kind))])

    appendToRegistry(&files, copy)

    return AppliedRuleMutation(kind: .duplicateRegistryTitle, files: [Self.registryPath], detail: "\(title.debugDescription) added again as \(kind)")
  }

  private func dashInDataString(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    let paths = files.keys.sorted()
    let places = paths.flatMap { path in
      (files[path] ?? .null).locations().compactMap { place -> (file: String, path: JSONPath, text: String)? in
        guard case .string(let text) = place.value, !text.isEmpty else { return nil }

        return (path, place.path, text)
      }
    }

    guard let place = places.randomElement(using: &random) else { return nil }
    let dash = ["\u{2014}", "\u{2013}"].randomElement(using: &random)!
    let replacement = [place.text + " \(dash) x", "x\(dash)" + place.text, place.text + dash].randomElement(using: &random)!

    files[place.file] = files[place.file]?.replacing(at: place.path) { _ in .string(replacement) }

    return AppliedRuleMutation(kind: .dashInDataString, files: [place.file], detail: "\(describe(place.path)) gained a dash")
  }

  private func nearDuplicateTitle(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    guard let entries = registryEntries(files), let entry = entries.randomElement(using: &random),
          case .string(let title)? = entry.value(at: ["title"]), case .string(let kind)? = entry.value(at: ["kind"])
    else { return nil }

    let words = ["Extra", "Plus", "Wireless"]
    let word = words.randomElement(using: &random)!
    let added = Bool.random(using: &random) ? "\(word) \(title)" : "\(title) \(word)"
    var touched = [Self.registryPath]

    appendToRegistry(&files, .object([JSONMember(key: "title", value: .string(added)), JSONMember(key: "kind", value: .string(kind))]))

    if Bool.random(using: &random), case .object(var members)? = files[Self.reviewedPath],
       let position = members.firstIndex(where: { $0.key == "distinct" }), case .array(var pairs) = members[position].value {
      pairs.append(.array([.string(title), .string(added)]))
      members[position].value = .array(pairs)
      files[Self.reviewedPath] = .object(members)
      touched.append(Self.reviewedPath)
    }

    return AppliedRuleMutation(kind: .nearDuplicateTitle, files: touched, detail: "\(added.debugDescription) added next to \(title.debugDescription)")
  }

  private func ruledOutTerm(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    let form = Self.ruledOutForms.randomElement(using: &random)!

    if Bool.random(using: &random), let entries = registryEntries(files), !entries.isEmpty {
      let index = Int.random(in: 0..<entries.count, using: &random)
      files[Self.registryPath] = files[Self.registryPath]?.replacing(at: ["documents", .index(index), "title"]) { value in
        guard case .string(let title) = value else { return value }
        return .string("\(title) \(form)")
      }

      return AppliedRuleMutation(kind: .ruledOutTerm, files: [Self.registryPath], detail: "registry entry \(index) title gained \(form.debugDescription)")
    }

    let places = dataPaths(files).flatMap { path in
      (files[path] ?? .null).locations().compactMap { place -> (file: String, path: JSONPath)? in
        guard case .string(let text) = place.value, case .key(let key)? = place.path.last,
              Self.proseKeys.contains(key) || (key == "name" && text.contains(" "))
        else { return nil }

        return (path, place.path)
      }
    }

    guard let place = places.randomElement(using: &random) else { return nil }
    let ticks = Bool.random(using: &random)

    files[place.file] = files[place.file]?.replacing(at: place.path) { value in
      guard case .string(let text) = value else { return value }
      return .string(ticks ? "\(text) `\(form)`" : "\(text) \(form)")
    }

    return AppliedRuleMutation(
      kind: .ruledOutTerm, files: [place.file], detail: "\(describe(place.path)) gained \(form.debugDescription)\(ticks ? " in backticks" : "")"
    )
  }

  private func registryEntry(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    guard let entries = registryEntries(files), !entries.isEmpty else { return nil }
    let index = Int.random(in: 0..<entries.count, using: &random)
    let entry: JSONPath = ["documents", .index(index)]
    let damage = ["removeKind", "badKind", "emptyEdition", "httpURL", "unknownField", "emptyTitle", "notAnObject", "goodURL", "edition"].randomElement(using: &random)!

    files[Self.registryPath] = files[Self.registryPath]?.replacing(at: entry) { value in
      guard case .object(var members) = value else { return value }

      func set(_ key: String, _ replacement: JSONValue) {
        if let position = members.firstIndex(where: { $0.key == key }) {
          members[position].value = replacement
        } else {
          members.append(JSONMember(key: key, value: replacement))
        }
      }

      switch damage {
      case "removeKind": members.removeAll { $0.key == "kind" }
      case "badKind": set("kind", .string("ownerManual"))
      case "emptyEdition": set("edition", .string("  "))
      case "httpURL": set("url", .string("http://cache.insteon.com/a.pdf"))
      case "goodURL": set("url", .string("https://cache.insteon.com/a.pdf"))
      case "edition": set("edition", .string("2009"))
      case "unknownField": set("note", .string("x"))
      case "emptyTitle": set("title", .string(""))
      default: return .string("not an entry")
      }

      return .object(members)
    }

    return AppliedRuleMutation(kind: .registryEntry, files: [Self.registryPath], detail: "entry \(index): \(damage)")
  }

  private func reviewedPair(_ files: inout [String: JSONValue], _ random: inout some RandomNumberGenerator) -> AppliedRuleMutation? {
    guard case .object(var members)? = files[Self.reviewedPath], let position = members.firstIndex(where: { $0.key == "distinct" }),
          case .array(var pairs) = members[position].value, let entries = registryEntries(files), entries.count > 1
    else { return nil }

    let titles = entries.compactMap { entry -> String? in
      guard case .string(let title)? = entry.value(at: ["title"]) else { return nil }
      return title
    }
    guard titles.count > 1 else { return nil }
    let first = titles.randomElement(using: &random)!
    let second = titles.randomElement(using: &random)!
    let change = ["stale", "unregistered", "notAPair", "removeOne"].randomElement(using: &random)!

    switch change {
    case "stale": pairs.append(.array([.string(first), .string(second)]))
    case "unregistered": pairs.append(.array([.string(first), .string("An Unregistered Title 1234")]))
    case "notAPair": pairs.append(Bool.random(using: &random) ? .array([.string(first)]) : .string(first))
    default:
      guard !pairs.isEmpty else { return nil }
      pairs.remove(at: Int.random(in: 0..<pairs.count, using: &random))
    }

    members[position].value = .array(pairs)
    files[Self.reviewedPath] = .object(members)

    return AppliedRuleMutation(kind: .reviewedPair, files: [Self.reviewedPath], detail: change)
  }

  // MARK: Helpers

  /// The paths of the profiles and command sets, in order.
  private func dataPaths(_ files: [String: JSONValue]) -> [String] {
    files.keys.filter { $0.hasPrefix("devices/") || $0.hasPrefix("commandSets/") }.sorted()
  }

  private func registryEntries(_ files: [String: JSONValue]) -> [JSONValue]? {
    guard case .array(let entries)? = files[Self.registryPath]?.value(at: ["documents"]) else { return nil }
    return entries
  }

  private func appendToRegistry(_ files: inout [String: JSONValue], _ entry: JSONValue) {
    files[Self.registryPath] = files[Self.registryPath]?.replacing(at: ["documents"]) { value in
      guard case .array(let entries) = value else { return value }
      return .array(entries + [entry])
    }
  }

  /// The path as `$.a[0].b`.
  private func describe(_ path: JSONPath) -> String {
    "$" + path.map(\.description).joined()
  }

  /// Whether the path runs through a `sources` member and then, at most, array positions.
  private func isInSources(_ path: JSONPath) -> Bool {
    guard let position = path.lastIndex(of: .key("sources")) else { return false }

    return path.dropFirst(position + 1).allSatisfy { if case .index = $0 { true } else { false } }
  }
}
