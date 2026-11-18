import CatalogJSON

/// One change a scenario makes to a file.
public struct ScenarioChange: Sendable {
  public enum Kind: Sendable {
    /// Replaces the value, or adds the member, with the JSON text.
    case set(String)
    /// Removes the member or element.
    case remove
    /// Adds the elements of the JSON array text to the end of the array.
    case append(String)
    /// Repeats the element next to itself.
    case duplicate
  }

  public let path: JSONPath
  public let kind: Kind

  public init(_ path: JSONPath, _ kind: Kind) {
    self.path = path
    self.kind = kind
  }

  /// A copy of the file with the change made.
  func applied(to file: JSONValue) throws -> JSONValue {
    switch kind {
    case .set(let json):
      let value = try JSONParser.parse(json)
      return file.replacing(at: path) { _ in value }.addingMember(at: path, value)
    case .remove:
      return file.replacing(at: path) { _ in nil }
    case .append(let json):
      guard case .array(let added) = try JSONParser.parse(json) else { return file }
      return file.replacing(at: path) { value in
        guard case .array(let elements) = value else { return value }
        return .array(elements + added)
      }
    case .duplicate:
      guard case .index(let index)? = path.last else { return file }
      return file.replacing(at: Array(path.dropLast())) { value in
        guard case .array(var elements) = value, elements.indices.contains(index) else { return value }
        elements.insert(elements[index], at: index)
        return .array(elements)
      }
    }
  }
}

extension JSONValue {
  /// A copy that also has the member at `path` when the last step names a member that is missing.
  func addingMember(at path: JSONPath, _ value: JSONValue) -> JSONValue {
    guard case .key(let key)? = path.last, self.value(at: path) == nil else { return self }
    return replacing(at: Array(path.dropLast())) { parent in
      guard case .object(var members) = parent else { return parent }
      members.append(JSONMember(key: key, value: value))
      return .object(members)
    }
  }
}

/// A hand-picked change to the real data that should make one rule speak. The rules run on the changed
/// copy, and the messages `expecting` must come out of them.
public struct Scenario: Sendable {
  public let name: String
  public let file: String
  public let changes: [ScenarioChange]
  public let expecting: [String]

  public init(_ name: String, in file: String, _ changes: [ScenarioChange], expecting: [String]) {
    self.name = name
    self.file = file
    self.changes = changes
    self.expecting = expecting
  }
}
