import CatalogJSON

/// The ways the sweep changes a data file.
public enum MutationKind: String, CaseIterable, Sendable {
  /// Removes an object member.
  case dropMember
  /// Replaces a string with another value seen under the same key in the catalog.
  case crossValue
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

/// The strings seen under each key in the catalog, which `crossValue` draws from.
public struct ValuePool: Sendable {
  private let byKey: [String: [String]]

  public init(files: [JSONValue]) {
    var byKey: [String: [String]] = [:]

    for file in files {
      for (path, value) in file.locations() {
        guard case .string(let text) = value, case .key(let key)? = path.last, !Mutator.proseKeys.contains(key) else { continue }
        if !(byKey[key]?.contains(text) ?? false) {
          byKey[key, default: []].append(text)
        }
      }
    }

    self.byKey = byKey
  }

  func values(forKey key: String) -> [String] {
    byKey[key] ?? []
  }
}

/// Changes a file in one way, chosen by a seeded random source.
public struct Mutator: Sendable {
  /// Keys whose strings are prose or titles. The sweep leaves them alone, because the prose,
  /// source and term rules are not in the rule set the sweep compares.
  static let proseKeys: Set<String> = ["description", "note", "notes", "sources", "label", "section", "text", "expect", "title"]

  let pool: ValuePool

  public init(pool: ValuePool) {
    self.pool = pool
  }

  /// A copy of the file with one change, or `nil` when the chosen kind has nowhere to apply.
  public func mutate(
    _ file: JSONValue, name: String, using random: inout some RandomNumberGenerator
  ) -> (value: JSONValue, applied: AppliedMutation)? {
    let kind = MutationKind.allCases.randomElement(using: &random)!
    let places = file.locations()

    switch kind {
    case .dropMember:
      return pick(places, where: { $0.path.last.map(isMember) ?? false }, &random).map { place in
        result(file.replacing(at: place.path) { _ in nil }, name, kind, place.path)
      }
    case .crossValue:
      let candidates = places.filter { place in
        guard case .string = place.value, case .key(let key)? = place.path.last else { return false }
        return pool.values(forKey: key).count > 1
      }
      guard let place = candidates.randomElement(using: &random), case .key(let key)? = place.path.last,
            case .string(let current) = place.value,
            let other = pool.values(forKey: key).filter({ $0 != current }).randomElement(using: &random)
      else { return nil }
      return result(file.replacing(at: place.path) { _ in .string(other) }, name, kind, place.path)
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
  var elementsOrEmpty: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }
}
