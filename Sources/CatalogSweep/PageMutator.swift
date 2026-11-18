import CatalogJSON

/// The ways the page sweep changes what a card or the page shows.
public enum PageMutationKind: String, CaseIterable, Sendable {
  /// Gives a profile a name with HTML-special and non-ASCII characters.
  case renameProfile
  /// Gives an operating flag, extended setting or reading a label with HTML-special and non-ASCII characters.
  case relabelValue
  /// Removes a profile's command sets.
  case dropCommandSets
  /// Gives a profile a description of several thousand characters with HTML-special characters.
  case longDescription
  /// Turns a command set into one that deliberately holds nothing to read or write.
  case emptyCommandSet
  /// Adds an alias with HTML-special and non-ASCII characters.
  case addAlias
  /// Turns a profile's battery flag over.
  case toggleBattery
  /// Removes a profile's radio or role, so the card says it is not stated.
  case dropRadioOrRole
  /// Marks an identity as inferred or conflicting.
  case markIdentity
  /// Renames a profile's model and its file, which changes where the card sorts.
  case renameModel
}

/// One change the page sweep made.
public struct AppliedPageMutation: Equatable, Sendable, CustomStringConvertible {
  public let kind: PageMutationKind
  public let files: [String]
  public let detail: String

  public var description: String {
    "\(kind.rawValue) in \(files.joined(separator: ", ")): \(detail)"
  }
}

/// Changes the data files in ways that change what the landing page shows, chosen by a seeded
/// random source. It works on every profile and command set, held by path.
public struct PageMutator: Sendable {
  /// A tail with every character the page escapes, and non-ASCII letters, a combining accent and
  /// characters outside the basic plane.
  static let specialText = " <b> & \"q\" 'n' caf\u{E9} \u{3C9} e\u{301} \u{65E5}\u{672C} \u{1F600} \u{39F}\u{394}\u{39F}\u{3A3} \u{3A3} \u{130}"

  public init() {}

  /// Changes `files` in place and says what it did, or returns `nil` when the kind has nowhere to
  /// apply. A file that is renamed or removed appears under both paths in the result.
  public func mutate(
    _ files: inout [String: JSONValue], kind: PageMutationKind, using random: inout some RandomNumberGenerator
  ) -> AppliedPageMutation? {
    let devices = files.keys.filter { $0.hasPrefix("devices/") }.sorted()
    let commandSets = files.keys.filter { $0.hasPrefix("commandSets/") }.sorted()

    switch kind {
    case .renameProfile:
      return change(&files, among: devices, kind, &random) { value, _ in
        guard case .string(let name)? = value.value(at: ["name"]) else { return nil }
        return (value.replacing(at: ["name"]) { _ in .string(name + Self.specialText) }, "name")
      }
    case .relabelValue:
      return change(&files, among: commandSets, kind, &random) { value, random in
        let places = value.locations().filter { place in
          guard case .key("label")? = place.path.last, case .string = place.value else { return false }
          return !place.path.contains(.key("sources"))
        }
        guard let place = places.randomElement(using: &random), case .string(let label) = place.value else { return nil }
        return (value.replacing(at: place.path) { _ in .string(label + Self.specialText) }, "label at $\(place.path.map(\.description).joined())")
      }
    case .dropCommandSets:
      return change(&files, among: devices.filter { files[$0]?.value(at: ["commandSets"]) != nil }, kind, &random) { value, _ in
        (value.replacing(at: ["commandSets"]) { _ in nil }, "commandSets")
      }
    case .longDescription:
      return change(&files, among: devices, kind, &random) { value, random in
        let sentence = "Dims & switches <the lamp> on a \"powerline\" (it's quick). "
        let count = Int.random(in: 20...60, using: &random)
        let text = String(repeating: sentence, count: count).trimmingTrailingSpace()
        let member = JSONMember(key: "description", value: .string(text))

        if value.value(at: ["description"]) != nil {
          return (value.replacing(at: ["description"]) { _ in .string(text) }, "description of \(text.count) characters")
        }
        guard case .object(var members) = value else { return nil }
        members.append(member)
        return (.object(members), "description of \(text.count) characters")
      }
    case .emptyCommandSet:
      return change(&files, among: commandSets, kind, &random) { value, _ in
        let kept: Set<String> = ["id", "name", "description", "sources", "notes"]
        guard case .object(let members) = value else { return nil }
        var emptied = members.filter { kept.contains($0.key) }
        if !emptied.contains(where: { $0.key == "description" }) {
          emptied.append(JSONMember(key: "description", value: .string("Nothing to read or write.")))
        }
        return (.object(emptied), "kept \(emptied.map(\.key).joined(separator: ", "))")
      }
    case .addAlias:
      return change(&files, among: devices, kind, &random) { value, _ in
        let alias = JSONValue.string("Alias" + Self.specialText)

        if case .array(let aliases)? = value.value(at: ["aliases"]) {
          return (value.replacing(at: ["aliases"]) { _ in .array(aliases + [alias]) }, "one more alias")
        }
        guard case .object(var members) = value else { return nil }
        members.append(JSONMember(key: "aliases", value: .array([alias])))
        return (.object(members), "aliases")
      }
    case .toggleBattery:
      return change(&files, among: devices, kind, &random) { value, _ in
        if case .bool(let flag)? = value.value(at: ["batteryPowered"]) {
          return (value.replacing(at: ["batteryPowered"]) { _ in .bool(!flag) }, "batteryPowered \(!flag)")
        }
        guard case .object(var members) = value else { return nil }
        members.append(JSONMember(key: "batteryPowered", value: .bool(true)))
        return (.object(members), "batteryPowered true")
      }
    case .dropRadioOrRole:
      return change(&files, among: devices, kind, &random) { value, random in
        let present = ["radio", "role"].filter { value.value(at: [.key($0)]) != nil }
        guard let key = present.randomElement(using: &random) else { return nil }
        return (value.replacing(at: [.key(key)]) { _ in nil }, key)
      }
    case .markIdentity:
      return change(&files, among: devices, kind, &random) { value, random in
        guard case .array(let identities)? = value.value(at: ["identities"]), !identities.isEmpty else { return nil }
        let index = Int.random(in: 0..<identities.count, using: &random)
        let status = ["inferred", "conflicting"].randomElement(using: &random)!
        let mark = JSONValue.object([
          JSONMember(key: "status", value: .string(status)),
          JSONMember(key: "note", value: .string("Read from a similar product."))
        ])
        return (value.replacing(at: ["identities", .index(index)]) { identity in
          guard case .object(var members) = identity else { return identity }
          members.removeAll { $0.key == "verification" }
          members.append(JSONMember(key: "verification", value: mark))
          return .object(members)
        }, "identity \(index) \(status)")
      }
    case .renameModel:
      guard let path = devices.randomElement(using: &random), let value = files[path], case .string(let model)? = value.value(at: ["model"]) else { return nil }
      let renamed = ["Z", "A", "1", "0", "9", "10", "2A-"].randomElement(using: &random)! + model
      let newPath = "devices/\(renamed).json"
      guard files[newPath] == nil else { return nil }
      files[path] = nil
      files[newPath] = value.replacing(at: ["model"]) { _ in .string(renamed) }
      return AppliedPageMutation(kind: kind, files: [path, newPath], detail: "model \(model) to \(renamed)")
    }
  }

  private func change<Random: RandomNumberGenerator>(
    _ files: inout [String: JSONValue], among paths: [String], _ kind: PageMutationKind, _ random: inout Random,
    _ edit: (JSONValue, inout Random) -> (JSONValue, String)?
  ) -> AppliedPageMutation? {
    guard let path = paths.randomElement(using: &random), let value = files[path], let (changed, detail) = edit(value, &random) else { return nil }
    guard changed != value else { return nil }
    files[path] = changed
    return AppliedPageMutation(kind: kind, files: [path], detail: detail)
  }
}

private extension String {
  func trimmingTrailingSpace() -> String {
    hasSuffix(" ") ? String(dropLast()) : self
  }
}
