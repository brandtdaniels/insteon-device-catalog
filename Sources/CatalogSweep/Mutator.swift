import CatalogJSON

/// The ways the sweep changes a data file.
public enum MutationKind: String, CaseIterable, Sendable {
  /// Removes an object member.
  case dropMember
  /// Replaces a value with another value seen under the same key in the catalog.
  case crossValue
  /// Adds a member that other objects in the catalog have, such as a guard or a unit.
  case addMember
  /// Turns a boolean over.
  case flipBoolean
  /// Repeats an array element next to itself.
  case duplicateElement
  /// Swaps two elements of an array.
  case swapElements
  /// Removes an array element.
  case dropElement
  /// Replaces a hexadecimal byte such as `0x2E` with another byte.
  case changeHexByte
  /// Adds or subtracts one from a whole number.
  case nudgeNumber
  /// Appends a letter to a name.
  case renameName
}

/// One change the sweep made to a file.
public struct AppliedMutation: Equatable, Sendable, CustomStringConvertible {
  public let file: String
  public let kind: MutationKind
  public let path: JSONPath

  public var description: String {
    "\(file) \(kind.rawValue) $\(path.map(\.description).joined())"
  }
}

/// The values seen under each key in the catalog, which `crossValue` and `addMember` draw from.
public struct ValuePool: Sendable {
  private let byKey: [String: [JSONValue]]
  /// How many different values of one key the pool keeps.
  private static let limit = 24

  public init(files: [JSONValue]) {
    var byKey: [String: [JSONValue]] = [:]

    for file in files {
      for (path, value) in file.locations() where Mutator.isChangeable(path) {
        guard case .key(let key)? = path.last, byKey[key, default: []].count < Self.limit,
              !byKey[key, default: []].contains(value)
        else { continue }
        byKey[key, default: []].append(value)
      }
    }

    self.byKey = byKey
  }

  func values(forKey key: String) -> [JSONValue] {
    byKey[key] ?? []
  }

  /// Every key with the values seen under it, in key order.
  var members: [(key: String, values: [JSONValue])] {
    byKey.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }.map { ($0.key, $0.value) }
  }
}

/// Changes a file in one way, chosen by a seeded random source.
public struct Mutator: Sendable {
  /// Keys whose values are prose, titles or provenance. The sweep leaves them and everything
  /// under them alone, because the prose, source and term rules are not in the rule set the sweep
  /// compares and no rule reads them.
  static let proseKeys: Set<String> = [
    "description", "note", "notes", "sources", "label", "section", "text", "expect", "title", "verification", "aliases"
  ]

  /// Whether a place in a file can be changed: not prose, and not in the parts of a profile that
  /// describe a person's steps, which no rule reads. The `fromHub` flow is the exception.
  static func isChangeable(_ path: JSONPath) -> Bool {
    let keys = path.compactMap { step -> String? in
      if case .key(let key) = step { key } else { nil }
    }

    if keys.contains(where: proseKeys.contains) { return false }

    if let position = keys.firstIndex(of: "lifecycle"), keys.dropFirst(position + 1).first != "fromHub", keys.count > position + 1 {
      return false
    }

    return true
  }

  let pool: ValuePool

  public init(pool: ValuePool) {
    self.pool = pool
  }

  /// A copy of the file with one change, or `nil` when the chosen kind has nowhere to apply.
  public func mutate(
    _ file: JSONValue, name: String, using random: inout some RandomNumberGenerator
  ) -> (value: JSONValue, applied: AppliedMutation)? {
    let kind = MutationKind.allCases.randomElement(using: &random)!
    let places = file.locations().filter { Self.isChangeable($0.path) }

    switch kind {
    case .dropMember:
      return pick(places, where: { $0.path.last.map(isMember) ?? false }, &random).map { place in
        result(file.replacing(at: place.path) { _ in nil }, name, kind, place.path)
      }
    case .crossValue:
      let candidates = places.filter { place in
        guard case .key(let key)? = place.path.last else { return false }
        return pool.values(forKey: key).contains { $0 != place.value }
      }
      guard let place = candidates.randomElement(using: &random), case .key(let key)? = place.path.last,
            let other = pool.values(forKey: key).filter({ $0 != place.value }).randomElement(using: &random)
      else { return nil }
      return result(file.replacing(at: place.path) { _ in other }, name, kind, place.path)
    case .addMember:
      let objects = places.filter { place in
        if case .object = place.value { true } else { false }
      }
      guard let place = objects.randomElement(using: &random) else { return nil }
      let present = Set(place.value.members.map(\.key))
      let additions = pool.members.filter { !present.contains($0.key) }
      guard let addition = additions.randomElement(using: &random),
            let value = addition.values.randomElement(using: &random)
      else { return nil }
      return result(file.replacing(at: place.path) { object in
        guard case .object(var members) = object else { return object }
        members.append(JSONMember(key: addition.key, value: value))
        return .object(members)
      }, name, kind, place.path + [.key(addition.key)])
    case .flipBoolean:
      return pick(places, where: { if case .bool = $0.value { true } else { false } }, &random).map { place in
        result(file.replacing(at: place.path) { value in
          if case .bool(let flag) = value { .bool(!flag) } else { value }
        }, name, kind, place.path)
      }
    case .duplicateElement:
      return pick(places, where: { !$0.value.elementsOrEmpty.isEmpty }, &random).map { place in
        let index = Int.random(in: 0..<place.value.elementsOrEmpty.count, using: &random)
        return result(file.replacing(at: place.path) { value in
          guard case .array(var elements) = value else { return value }
          elements.insert(elements[index], at: index)
          return .array(elements)
        }, name, kind, place.path + [.index(index)])
      }
    case .swapElements:
      return pick(places, where: { $0.value.elementsOrEmpty.count > 1 }, &random).map { place in
        let count = place.value.elementsOrEmpty.count
        let first = Int.random(in: 0..<count - 1, using: &random)
        return result(file.replacing(at: place.path) { value in
          guard case .array(var elements) = value else { return value }
          elements.swapAt(first, first + 1)
          return .array(elements)
        }, name, kind, place.path + [.index(first)])
      }
    case .dropElement:
      return pick(places, where: { place in
        if case .index = place.path.last { true } else { false }
      }, &random).map { place in
        result(file.replacing(at: place.path) { _ in nil }, name, kind, place.path)
      }
    case .changeHexByte:
      return pick(places, where: { place in
        guard case .string(let text) = place.value else { return false }
        return text.count == 4 && text.hasPrefix("0x") && text.dropFirst(2).allSatisfy { $0.isHexDigit && !$0.isLowercase }
      }, &random).map { place in
        let byte = Int.random(in: 0...255, using: &random)
        let digits = String(byte, radix: 16, uppercase: true)
        return result(file.replacing(at: place.path) { _ in .string("0x" + (digits.count == 1 ? "0" : "") + digits) }, name, kind, place.path)
      }
    case .nudgeNumber:
      return pick(places, where: { if case .int = $0.value { true } else { false } }, &random).map { place in
        let delta = Bool.random(using: &random) ? 1 : -1
        return result(file.replacing(at: place.path) { value in
          if case .int(let number) = value { .int(number + delta) } else { value }
        }, name, kind, place.path)
      }
    case .renameName:
      return pick(places, where: { place in
        if case .key("name")? = place.path.last, case .string = place.value { true } else { false }
      }, &random).map { place in
        result(file.replacing(at: place.path) { value in
          if case .string(let text) = value { .string(text + "Z") } else { value }
        }, name, kind, place.path)
      }
    }
  }

  private func isMember(_ step: PathStep) -> Bool {
    if case .key = step { true } else { false }
  }

  private func pick(
    _ places: [(path: JSONPath, value: JSONValue)], where matches: ((path: JSONPath, value: JSONValue)) -> Bool,
    _ random: inout some RandomNumberGenerator
  ) -> (path: JSONPath, value: JSONValue)? {
    places.filter(matches).randomElement(using: &random)
  }

  private func result(_ value: JSONValue, _ name: String, _ kind: MutationKind, _ path: JSONPath) -> (JSONValue, AppliedMutation) {
    (value, AppliedMutation(file: name, kind: kind, path: path))
  }
}

extension JSONValue {
  var members: [JSONMember] {
    guard case .object(let members) = self else { return [] }
    return members
  }

  var elementsOrEmpty: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }
}
